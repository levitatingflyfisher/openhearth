package api_test

import (
	"bytes"
	"context"
	"net/http"
	"sync"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// fullStore wraps a store and, while full is set, refuses every write the
// way Redis does at maxmemory under noeviction.
type fullStore struct {
	store.Store
	mu   sync.Mutex
	full bool
}

func (f *fullStore) setFull(v bool) { f.mu.Lock(); f.full = v; f.mu.Unlock() }
func (f *fullStore) isFull() bool   { f.mu.Lock(); defer f.mu.Unlock(); return f.full }

func (f *fullStore) CreateInvite(ctx context.Context, id string, ttl time.Duration) (time.Time, error) {
	if f.isFull() {
		return time.Time{}, store.ErrOutOfMemory
	}
	return f.Store.CreateInvite(ctx, id, ttl)
}

func (f *fullStore) MailboxPush(ctx context.Context, id string, blob []byte) error {
	if f.isFull() {
		return store.ErrOutOfMemory
	}
	return f.Store.MailboxPush(ctx, id, blob)
}

func (f *fullStore) ReplayCheck(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	if f.isFull() {
		return false, store.ErrOutOfMemory
	}
	return f.Store.ReplayCheck(ctx, key, ttl)
}

func (f *fullStore) PresenceSet(ctx context.Context, ch, slot string, blob []byte, ttl time.Duration) error {
	if f.isFull() {
		return store.ErrOutOfMemory
	}
	return f.Store.PresenceSet(ctx, ch, slot, blob, ttl)
}

func (f *fullStore) BulletinAppend(ctx context.Context, ch, writer string, blob []byte, pinned bool, pinTTL time.Duration) (uint64, error) {
	if f.isFull() {
		return 0, store.ErrOutOfMemory
	}
	return f.Store.BulletinAppend(ctx, ch, writer, blob, pinned, pinTTL)
}

func newFullRelay(t *testing.T) (*relay, *fullStore) {
	t.Helper()
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	mem := store.NewMem(store.DefaultLimits(), clk.Now)
	fs := &fullStore{Store: mem}
	h := api.New(api.Config{Store: fs, Now: clk.Now, Rates: generousRates()})
	return &relay{h: h, clk: clk, st: mem}, fs
}

// A full Redis refuses new posts with 507 Insufficient Storage: the relay
// cannot store more right now. It is a 5xx, so the app keeps the post in
// its outbox and tries again; a 500 would say the relay is broken, a 429
// would blame the caller.
func TestFullStoreRefusesNewPostsWith507(t *testing.T) {
	rl, fs := newFullRelay(t)
	_, _, mbox := mailboxFixture(t)
	fs.setFull(true)

	posts := []struct {
		name, path string
		body       any
	}{
		{"mailbox", "/v1/mailbox/" + mbox, map[string]any{"blob": []byte("m")}},
		{"presence", "/v1/ch/" + testChannel + "/presence",
			map[string]any{"slotId": testSlot, "blob": []byte("p"), "ttlSec": 60}},
		{"bulletin", "/v1/ch/" + testChannel + "/bulletin", map[string]any{"blob": []byte("b")}},
		{"invite", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 1}},
	}
	for _, p := range posts {
		t.Run(p.name, func(t *testing.T) {
			w := rl.do(t, "POST", p.path, p.body)
			wantStatus(t, w, http.StatusInsufficientStorage)
			wantEmptyErrorBody(t, w)
		})
	}
}

// At full memory the drain's replay entry cannot be written, so the drain
// is refused (507) before any mail is touched. The mail is all there once
// memory frees.
func TestDrainAtFullMemoryIsRefusedAndLosesNoMail(t *testing.T) {
	rl, fs := newFullRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	for _, b := range []string{"one", "two"} {
		wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte(b)}), http.StatusNoContent)
	}
	fs.setFull(true)
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()))
	wantStatus(t, w, http.StatusInsufficientStorage)
	wantEmptyErrorBody(t, w)

	fs.setFull(false)
	w = rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()+1))
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blobs [][]byte `json:"blobs"`
	}](t, w)
	if len(got.Blobs) != 2 || !bytes.Equal(got.Blobs[0], []byte("one")) || !bytes.Equal(got.Blobs[1], []byte("two")) {
		t.Fatalf("mail after memory freed: %q", got.Blobs)
	}
}

// A bad signature is still a bare 401 at full memory: the 507 comes only
// after the signature checks out, so it tells a stranger nothing.
func TestDrainWithBadSignatureIs401EvenWhenFull(t *testing.T) {
	rl, fs := newFullRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	fs.setFull(true)
	w := rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()-400))
	wantStatus(t, w, http.StatusUnauthorized)
}
