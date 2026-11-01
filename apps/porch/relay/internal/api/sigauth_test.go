package api

import (
	"context"
	"crypto/ed25519"
	"strconv"
	"testing"
	"time"

	"porch/relay/internal/store"
)

// Independent derivation vector: computed with Python hashlib.blake2b
// (digest_size=32) over "porch/mbox/v1" ‖ pk where pk = bytes 0x00..0x1f.
// hashlib.blake2b and libsodium crypto_generichash are the same BLAKE2b;
// this pins our Go derivation against an implementation we didn't write.
func TestDeriveMailboxIDVector(t *testing.T) {
	pk := make([]byte, 32)
	for i := range pk {
		pk[i] = byte(i)
	}
	const want = "587EjM9iNfVFa_VYVllvCcsFWqNZr3zGndg-SN3HPg8"
	if got := deriveMailboxID(pk); got != want {
		t.Fatalf("deriveMailboxID = %q, want %q", got, want)
	}
}

func drainFixture(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey, string) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	return pub, priv, deriveMailboxID(pub)
}

func signDrain(priv ed25519.PrivateKey, mailboxID string, ts int64) []byte {
	msg := drainMessagePrefix + mailboxID + "|" + strconv.FormatInt(ts, 10)
	return ed25519.Sign(priv, []byte(msg))
}

func newSigauthStore(t *testing.T) (store.Store, *store.FakeClock) {
	t.Helper()
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	return store.NewMem(store.DefaultLimits(), clk.Now), clk
}

func TestVerifyDrainAccepts(t *testing.T) {
	st, clk := newSigauthStore(t)
	pub, priv, mbox := drainFixture(t)
	ts := clk.Now().Unix()
	a := drainAuth{Pubkey: pub, Ts: ts, Sig: signDrain(priv, mbox, ts)}
	if err := verifyDrain(context.Background(), st, clk.Now(), mbox, a); err != nil {
		t.Fatalf("valid drain rejected: %v", err)
	}
}

func TestVerifyDrainRejects(t *testing.T) {
	ctx := context.Background()
	pub, priv, mbox := drainFixture(t)
	otherPub, otherPriv, _ := drainFixture(t)

	cases := []struct {
		name string
		auth func(now time.Time) drainAuth
		mbox string
	}{
		{"tampered sig", func(now time.Time) drainAuth {
			sig := signDrain(priv, mbox, now.Unix())
			sig[0] ^= 0xff
			return drainAuth{Pubkey: pub, Ts: now.Unix(), Sig: sig}
		}, ""},
		{"sig by wrong key", func(now time.Time) drainAuth {
			return drainAuth{Pubkey: pub, Ts: now.Unix(), Sig: signDrain(otherPriv, mbox, now.Unix())}
		}, ""},
		{"pubkey does not hash to mailboxId", func(now time.Time) drainAuth {
			return drainAuth{Pubkey: otherPub, Ts: now.Unix(), Sig: signDrain(otherPriv, mbox, now.Unix())}
		}, ""},
		{"stale ts (past)", func(now time.Time) drainAuth {
			ts := now.Add(-301 * time.Second).Unix()
			return drainAuth{Pubkey: pub, Ts: ts, Sig: signDrain(priv, mbox, ts)}
		}, ""},
		{"future ts", func(now time.Time) drainAuth {
			ts := now.Add(301 * time.Second).Unix()
			return drainAuth{Pubkey: pub, Ts: ts, Sig: signDrain(priv, mbox, ts)}
		}, ""},
		{"short pubkey", func(now time.Time) drainAuth {
			return drainAuth{Pubkey: pub[:31], Ts: now.Unix(), Sig: signDrain(priv, mbox, now.Unix())}
		}, ""},
		{"short sig", func(now time.Time) drainAuth {
			return drainAuth{Pubkey: pub, Ts: now.Unix(), Sig: signDrain(priv, mbox, now.Unix())[:63]}
		}, ""},
		{"signature bound to a different mailbox", func(now time.Time) drainAuth {
			otherBox := deriveMailboxID(otherPub)
			return drainAuth{Pubkey: pub, Ts: now.Unix(), Sig: signDrain(priv, otherBox, now.Unix())}
		}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			st, clk := newSigauthStore(t)
			target := tc.mbox
			if target == "" {
				target = mbox
			}
			if err := verifyDrain(ctx, st, clk.Now(), target, tc.auth(clk.Now())); err == nil {
				t.Fatal("invalid drain accepted")
			}
		})
	}
}

func TestVerifyDrainReplay(t *testing.T) {
	st, clk := newSigauthStore(t)
	pub, priv, mbox := drainFixture(t)
	ts := clk.Now().Unix()
	a := drainAuth{Pubkey: pub, Ts: ts, Sig: signDrain(priv, mbox, ts)}
	if err := verifyDrain(context.Background(), st, clk.Now(), mbox, a); err != nil {
		t.Fatalf("first use: %v", err)
	}
	if err := verifyDrain(context.Background(), st, clk.Now(), mbox, a); err == nil {
		t.Fatal("replayed signature accepted")
	}
	// A fresh signature (new ts) is fine.
	ts2 := ts + 1
	a2 := drainAuth{Pubkey: pub, Ts: ts2, Sig: signDrain(priv, mbox, ts2)}
	if err := verifyDrain(context.Background(), st, clk.Now(), mbox, a2); err != nil {
		t.Fatalf("fresh signature after replay: %v", err)
	}
	// After the replay window, the old signature is stale by freshness anyway:
	// replay cache TTL (10 min) exceeds freshness (±300 s) by design.
	if replayTTL < 2*drainFreshness {
		t.Fatalf("replay TTL %v must cover the whole freshness window %v", replayTTL, drainFreshness)
	}
}
