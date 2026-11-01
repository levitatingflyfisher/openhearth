package api_test

import (
	"bytes"
	"crypto/ed25519"
	"net/http"
	"strconv"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// mailboxFixture builds a keypair and its true mailboxId via a drain
// round-trip helper in the api package's exported test hook — we instead
// derive it the same way clients do: by asking the api package. To keep this
// black-box, we use api.DeriveMailboxID (exported precisely because clients
// of the Go package — the integration harness — need it too).
func mailboxFixture(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey, string) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	return pub, priv, api.DeriveMailboxID(pub)
}

func drainBody(priv ed25519.PrivateKey, pub ed25519.PublicKey, mailboxID string, ts int64) map[string]any {
	msg := "porch-drain|" + mailboxID + "|" + strconv.FormatInt(ts, 10)
	return map[string]any{"pubkey": []byte(pub), "ts": ts, "sig": ed25519.Sign(priv, []byte(msg))}
}

func TestMailboxAnonymousPostAndSignedDrain(t *testing.T) {
	rl := newRelay(t)
	pub, priv, mbox := mailboxFixture(t)

	// Anonymous POSTs — no auth of any kind.
	blobs := [][]byte{{1, 0, 0xff}, {2}, {3, '"'}}
	for _, b := range blobs {
		w := rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": b})
		wantStatus(t, w, http.StatusNoContent)
	}

	// Stateless signed drain: atomic returned == deleted, FIFO order.
	ts := rl.clk.Now().Unix()
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, ts))
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blobs [][]byte `json:"blobs"`
	}](t, w)
	if len(got.Blobs) != len(blobs) {
		t.Fatalf("drained %d blobs, want %d", len(got.Blobs), len(blobs))
	}
	for i := range blobs {
		if !bytes.Equal(got.Blobs[i], blobs[i]) {
			t.Fatalf("blob %d = %x, want %x (order or bytes wrong)", i, got.Blobs[i], blobs[i])
		}
	}

	// Second drain (fresh signature) → empty list, not null.
	ts2 := ts + 1
	w = rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, ts2))
	wantStatus(t, w, http.StatusOK)
	if body := w.Body.String(); !bytes.Contains([]byte(body), []byte(`"blobs":[]`)) {
		t.Fatalf("empty drain body = %q, want blobs:[]", body)
	}
}

func TestMailboxDepthCap429(t *testing.T) {
	lim := store.DefaultLimits()
	lim.MailboxDepth = 3
	rl := newRelayWith(t, lim, generousRates())
	_, _, mbox := mailboxFixture(t)

	for i := 0; i < 3; i++ {
		wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte{byte(i)}}), http.StatusNoContent)
	}
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("over")})
	wantStatus(t, w, http.StatusTooManyRequests) // 429 mailbox full
	wantEmptyErrorBody(t, w)
}

func TestMailboxBlobCap(t *testing.T) {
	rl := newRelay(t)
	_, _, mbox := mailboxFixture(t)
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": make([]byte, 8<<10+1)})
	wantStatus(t, w, http.StatusRequestEntityTooLarge)
}

func TestMailboxDrainAuthFailures(t *testing.T) {
	rl := newRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	otherPub, otherPriv, otherBox := mailboxFixture(t)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("mail")}), http.StatusNoContent)

	now := rl.clk.Now().Unix()
	cases := []struct {
		name string
		body any
	}{
		{"garbage body", []byte("{nope")},
		{"missing fields", map[string]any{"pubkey": []byte(pub)}},
		{"tampered sig", func() map[string]any {
			b := drainBody(priv, pub, mbox, now)
			sig := b["sig"].([]byte)
			sig[3] ^= 0x80
			return b
		}()},
		{"stale ts", drainBody(priv, pub, mbox, now-400)},
		{"future ts", drainBody(priv, pub, mbox, now+400)},
		{"wrong key for this mailbox", drainBody(otherPriv, otherPub, otherBox, now)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", tc.body)
			wantStatus(t, w, http.StatusUnauthorized)
			wantEmptyErrorBody(t, w)
		})
	}

	// Valid drain still works after all the rejects, and the mail is intact.
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, now))
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blobs [][]byte `json:"blobs"`
	}](t, w)
	if len(got.Blobs) != 1 || !bytes.Equal(got.Blobs[0], []byte("mail")) {
		t.Fatalf("mail lost or corrupted: %v", got.Blobs)
	}
}

func TestMailboxDrainReplayed401(t *testing.T) {
	rl := newRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	body := drainBody(priv, pub, mbox, rl.clk.Now().Unix())
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", body), http.StatusOK)
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", body) // byte-identical replay
	wantStatus(t, w, http.StatusUnauthorized)
}

func TestMailboxTTLRefreshOnPush(t *testing.T) {
	lim := store.DefaultLimits()
	rl := newRelayWith(t, lim, generousRates())
	pub, priv, mbox := mailboxFixture(t)
	// The owner's app drains on every sync. That makes the mailbox owned,
	// so pushes get the full rolling MailboxTTL, not MailboxFreshTTL.
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain",
		drainBody(priv, pub, mbox, rl.clk.Now().Unix()-1)), http.StatusOK)

	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("a")}), http.StatusNoContent)
	rl.clk.Advance(lim.MailboxTTL * 2 / 3)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("b")}), http.StatusNoContent)
	rl.clk.Advance(lim.MailboxTTL * 2 / 3) // past original TTL, within refreshed

	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()))
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blobs [][]byte `json:"blobs"`
	}](t, w)
	if len(got.Blobs) != 2 {
		t.Fatalf("after rolling refresh: %d blobs, want 2", len(got.Blobs))
	}
}

// A mailbox nobody has drained keeps anonymous posts only for
// MailboxFreshTTL.
func TestNeverDrainedMailboxKeepsMailOnlyBriefly(t *testing.T) {
	lim := store.DefaultLimits()
	rl := newRelayWith(t, lim, generousRates())
	pub, priv, mbox := mailboxFixture(t)

	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("a")}), http.StatusNoContent)
	rl.clk.Advance(lim.MailboxFreshTTL + time.Second)

	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()))
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blobs [][]byte `json:"blobs"`
	}](t, w)
	if len(got.Blobs) != 0 {
		t.Fatalf("never-drained mailbox kept %d blobs past MailboxFreshTTL", len(got.Blobs))
	}
}

func TestMailboxPostRateLimit(t *testing.T) {
	rates := generousRates()
	rates.MailboxPost = api.RateRule{Burst: 2, PerSec: 0.0001}
	rl := newRelayWith(t, store.DefaultLimits(), rates)
	_, _, mbox := mailboxFixture(t)

	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("1")}), http.StatusNoContent)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("2")}), http.StatusNoContent)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("3")}), http.StatusTooManyRequests)
}

// The drain timestamp freshness window is ±300s per spec; pin it.
func TestDrainFreshnessWindowIsSpec(t *testing.T) {
	rl := newRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	// 299 s skew: accepted.
	ts := rl.clk.Now().Add(-299 * time.Second).Unix()
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, ts))
	wantStatus(t, w, http.StatusOK)
}
