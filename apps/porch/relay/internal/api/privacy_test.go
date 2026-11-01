package api

// Privacy conformance (BUILD-SPEC §1.4, W3):
//
//  1. Byte-identity: every blob a client submits is returned byte-identical
//     on every read path — the relay provably never parses or re-encodes
//     ciphertext. (End-to-end through the real router.)
//  2. Zero-logging: the relay's serving packages contain no logging calls at
//     the source level. This is the CI-greppable structural guarantee.
//  3. Channel plane reads no identity: channels.go never touches headers,
//     cookies, or the remote address — capability knowledge is the only auth.

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"

	"porch/relay/internal/store"
)

func newPrivacyRelay(t *testing.T) (http.Handler, *store.FakeClock) {
	t.Helper()
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	st := store.NewMem(store.DefaultLimits(), clk.Now)
	g := RateRule{Burst: 10000, PerSec: 10000}
	h := New(Config{Store: st, Now: clk.Now, Rates: RateRules{
		InviteCreate: g, MailboxPost: g, Drain: g, ChannelWrite: g, Read: g,
	}})
	return h, clk
}

func privacyDo(t *testing.T, h http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var b []byte
	if body != nil {
		var err error
		if b, err = json.Marshal(body); err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(b))
	req.RemoteAddr = "192.0.2.99:1000"
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

// hostileBlob exercises NULs, high bytes, JSON metacharacters, and invalid
// UTF-8 — anything a parse-then-reserialize path would mangle.
func hostileBlob(t *testing.T, n int) []byte {
	t.Helper()
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	copy(b, []byte{0x00, 0xff, '"', '\\', '{', 0x80, '\n', 0x01})
	return b
}

func TestStoredBlobsByteIdenticalEndToEnd(t *testing.T) {
	h, clk := newPrivacyRelay(t)
	const ch = "chan_privacyaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"
	const slot = "slot_privacyaaaaaaaaa0"
	const inv = "inv_privacyaaaaaaaaaa0"

	t.Run("presence", func(t *testing.T) {
		blob := hostileBlob(t, 512)
		w := privacyDo(t, h, "POST", "/v1/ch/"+ch+"/presence",
			map[string]any{"slotId": slot, "blob": blob, "ttlSec": 600})
		if w.Code != 204 {
			t.Fatalf("post: %d", w.Code)
		}
		var got struct {
			Slots []struct {
				Blob []byte `json:"blob"`
			} `json:"slots"`
		}
		if err := json.Unmarshal(privacyDo(t, h, "GET", "/v1/ch/"+ch+"/presence", nil).Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if len(got.Slots) != 1 || !bytes.Equal(got.Slots[0].Blob, blob) {
			t.Fatal("presence blob not byte-identical")
		}
	})

	t.Run("bulletin", func(t *testing.T) {
		unpinned, pinned := hostileBlob(t, 900), hostileBlob(t, 900)
		if w := privacyDo(t, h, "POST", "/v1/ch/"+ch+"/bulletin",
			map[string]any{"blob": unpinned, "pinned": false}); w.Code != 200 {
			t.Fatalf("post unpinned: %d", w.Code)
		}
		if w := privacyDo(t, h, "POST", "/v1/ch/"+ch+"/bulletin",
			map[string]any{"blob": pinned, "pinned": true, "ttlSec": 3600}); w.Code != 200 {
			t.Fatalf("post pinned: %d", w.Code)
		}
		var got struct {
			Entries []struct {
				Blob   []byte `json:"blob"`
				Pinned bool   `json:"pinned"`
			} `json:"entries"`
		}
		if err := json.Unmarshal(privacyDo(t, h, "GET", "/v1/ch/"+ch+"/bulletin", nil).Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if len(got.Entries) != 2 {
			t.Fatalf("want 2 entries, got %d", len(got.Entries))
		}
		for _, e := range got.Entries {
			want := unpinned
			if e.Pinned {
				want = pinned
			}
			if !bytes.Equal(e.Blob, want) {
				t.Fatalf("bulletin blob not byte-identical (pinned=%v)", e.Pinned)
			}
		}
	})

	t.Run("mailbox", func(t *testing.T) {
		pub, priv, err := ed25519.GenerateKey(nil)
		if err != nil {
			t.Fatal(err)
		}
		mbox := deriveMailboxID(pub)
		blob := hostileBlob(t, 2048)
		if w := privacyDo(t, h, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": blob}); w.Code != 204 {
			t.Fatalf("post: %d", w.Code)
		}
		ts := clk.Now().Unix()
		msg := drainMessagePrefix + mbox + "|" + strconv.FormatInt(ts, 10)
		w := privacyDo(t, h, "POST", "/v1/mailbox/"+mbox+"/drain",
			map[string]any{"pubkey": []byte(pub), "ts": ts, "sig": ed25519.Sign(priv, []byte(msg))})
		if w.Code != 200 {
			t.Fatalf("drain: %d", w.Code)
		}
		var got struct {
			Blobs [][]byte `json:"blobs"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if len(got.Blobs) != 1 || !bytes.Equal(got.Blobs[0], blob) {
			t.Fatal("mailbox blob not byte-identical")
		}
	})

	t.Run("invite join and grant", func(t *testing.T) {
		join, grant := hostileBlob(t, 1024), hostileBlob(t, 2048)
		if w := privacyDo(t, h, "POST", "/v1/invites", map[string]any{"inviteId": inv, "ttlHours": 24}); w.Code != 201 {
			t.Fatalf("create: %d", w.Code)
		}
		if w := privacyDo(t, h, "POST", "/v1/invites/"+inv+"/join", map[string]any{"blob": join}); w.Code != 204 {
			t.Fatalf("join: %d", w.Code)
		}
		w := privacyDo(t, h, "GET", "/v1/invites/"+inv+"/join?proof=proof_fetch_aaaaaaaa", nil)
		if w.Code != 200 {
			t.Fatalf("fetch: %d", w.Code)
		}
		var got struct {
			Blob []byte `json:"blob"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got.Blob, join) {
			t.Fatal("join blob not byte-identical")
		}
		if w := privacyDo(t, h, "POST", "/v1/invites/"+inv+"/grant",
			map[string]any{"proof": "proof_fetch_aaaaaaaa", "blob": grant}); w.Code != 204 {
			t.Fatalf("grant: %d", w.Code)
		}
		w = privacyDo(t, h, "GET", "/v1/invites/"+inv+"/grant?proof=proof_grant_aaaaaaaa", nil)
		if w.Code != 200 {
			t.Fatalf("take: %d", w.Code)
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got.Blob, grant) {
			t.Fatal("grant blob not byte-identical")
		}
	})
}

// relaySourceDirs locates the serving packages relative to this file.
func relaySourceDirs(t *testing.T) []string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate source")
	}
	apiDir := filepath.Dir(thisFile)
	return []string{apiDir, filepath.Join(apiDir, "..", "store")}
}

// TestNoLoggingInServingPackages is the CI zero-logging grep (spec §1.4):
// no log./slog./fmt.Print* anywhere in the serving packages' non-test code.
func TestNoLoggingInServingPackages(t *testing.T) {
	forbidden := []string{"log.", "slog.", "fmt.Print", `"log"`, `"log/slog"`, "os.Stdout", "os.Stderr"}
	for _, dir := range relaySourceDirs(t) {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range entries {
			name := e.Name()
			if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
				continue
			}
			src, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				t.Fatal(err)
			}
			for _, f := range forbidden {
				if strings.Contains(string(src), f) {
					t.Errorf("%s contains forbidden %q — the relay must not log", name, f)
				}
			}
		}
	}
}

// TestChannelPlaneReadsNoIdentity mirrors the client-side structural test:
// the channel handlers' source never touches identity-bearing request state.
func TestChannelPlaneReadsNoIdentity(t *testing.T) {
	_, thisFile, _, _ := runtime.Caller(0)
	src, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "channels.go"))
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{".Header", "Cookie", "RemoteAddr", "BasicAuth", "TLS.Peer"} {
		if strings.Contains(string(src), f) {
			t.Errorf("channels.go touches %q — the channel plane must be identity-free", f)
		}
	}
}
