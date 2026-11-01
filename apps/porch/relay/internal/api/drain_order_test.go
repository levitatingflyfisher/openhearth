package api_test

import (
	"context"
	"net/http"
	"slices"
	"sync"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// orderStore records the order of the drain's two writes, and can make
// the replay entry fail.
type orderStore struct {
	store.Store
	mu         sync.Mutex
	calls      []string
	replayFail error
}

func (o *orderStore) ReplayCheck(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	o.mu.Lock()
	o.calls = append(o.calls, "replay")
	fail := o.replayFail
	o.mu.Unlock()
	if fail != nil {
		return false, fail
	}
	return o.Store.ReplayCheck(ctx, key, ttl)
}

func (o *orderStore) MailboxDrain(ctx context.Context, id string) ([][]byte, error) {
	o.mu.Lock()
	o.calls = append(o.calls, "drain")
	o.mu.Unlock()
	return o.Store.MailboxDrain(ctx, id)
}

func newOrderRelay(t *testing.T) (*relay, *orderStore) {
	t.Helper()
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	mem := store.NewMem(store.DefaultLimits(), clk.Now)
	os := &orderStore{Store: mem}
	h := api.New(api.Config{Store: os, Now: clk.Now, Rates: generousRates()})
	return &relay{h: h, clk: clk, st: mem}, os
}

// The replay entry is written before the mail is taken. If the relay dies
// between the two, the signature is already spent: a replay of the same
// request can never take mail, and the owner signs a fresh drain.
func TestDrainWritesTheReplayEntryBeforeTakingMail(t *testing.T) {
	rl, os := newOrderRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("m")}), http.StatusNoContent)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix())), http.StatusOK)
	if !slices.Equal(os.calls, []string{"replay", "drain"}) {
		t.Fatalf("drain order = %v, want [replay drain]", os.calls)
	}
}

// A replay entry that cannot be written stops the drain: the mail is
// never touched.
func TestDrainWithoutAReplayEntryNeverTakesMail(t *testing.T) {
	rl, os := newOrderRelay(t)
	pub, priv, mbox := mailboxFixture(t)
	wantStatus(t, rl.do(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("m")}), http.StatusNoContent)
	os.replayFail = store.ErrOutOfMemory
	rl.do(t, "POST", "/v1/mailbox/"+mbox+"/drain", drainBody(priv, pub, mbox, rl.clk.Now().Unix()))
	if slices.Contains(os.calls, "drain") {
		t.Fatalf("the mailbox was drained without a replay entry: %v", os.calls)
	}
}
