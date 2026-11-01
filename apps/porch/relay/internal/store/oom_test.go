package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

// Under noeviction a full Redis answers every write with -OOM. The store
// names that ErrOutOfMemory, so the relay can refuse with a clear status
// instead of a bare 500, and so nobody mistakes it for a lost connection.
func TestRedisOutOfMemoryIsErrOutOfMemory(t *testing.T) {
	f := newFakeRedis(t)
	f.mu.Lock()
	f.oom = true
	f.mu.Unlock()
	r, err := NewRedis(f.addr(), DefaultLimits())
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer r.Close()
	ctx := context.Background()

	checks := map[string]error{}
	checks["MailboxPush"] = r.MailboxPush(ctx, "mb-oom", []byte("x"))
	_, checks["MailboxDrain"] = r.MailboxDrain(ctx, "mb-oom")
	_, checks["ReplayCheck"] = r.ReplayCheck(ctx, "sig", time.Minute)
	checks["PresenceSet"] = r.PresenceSet(ctx, "ch-oom", "slot", []byte("p"), time.Minute)
	_, checks["BulletinAppend"] = r.BulletinAppend(ctx, "ch-oom", "", []byte("b"), false, 0)
	_, checks["CreateInvite"] = r.CreateInvite(ctx, "inv-oom", time.Hour)
	for name, err := range checks {
		if !errors.Is(err, ErrOutOfMemory) {
			t.Errorf("%s at full memory: got %v, want ErrOutOfMemory", name, err)
		}
	}
}

// Any other Redis error stays what it was.
func TestOtherRedisErrorsAreNotOutOfMemory(t *testing.T) {
	f := newFakeRedis(t)
	r, err := NewRedis(f.addr(), DefaultLimits())
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer r.Close()
	err = r.MailboxPush(context.Background(), "mb", []byte("x")) // -ERR unknown command
	if err == nil || errors.Is(err, ErrOutOfMemory) {
		t.Fatalf("got %v, want a plain Redis error", err)
	}
}
