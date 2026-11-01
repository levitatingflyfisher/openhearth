package store

import (
	"context"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"
)

// fullRedis connects to REDIS_URL and checks it is a small Redis under
// noeviction, so a test can really fill it. It skips, saying why, when
// there is no such Redis.
func fullRedis(t *testing.T, lim Limits) *Redis {
	t.Helper()
	url := os.Getenv("REDIS_URL")
	if url == "" {
		t.Skip("REDIS_URL not set; the full-memory leg needs a real Redis 7 " +
			"started with a small --maxmemory and --maxmemory-policy noeviction")
	}
	r, err := NewRedis(url, lim)
	if err != nil {
		t.Fatalf("connect redis: %v", err)
	}
	t.Cleanup(func() {
		r.FlushForTest(context.Background())
		r.Close()
	})
	if res, err := r.do("CONFIG", "GET", "maxmemory-policy"); err != nil || asString(res.([]any)[1]) != "noeviction" {
		t.Skipf("REDIS_URL is not under noeviction (%v, %v); not filling it", res, err)
	}
	res, err := r.do("CONFIG", "GET", "maxmemory")
	if err != nil {
		t.Fatalf("config get: %v", err)
	}
	max, _ := strconv.Atoi(asString(res.([]any)[1]))
	if max == 0 || max > 64<<20 {
		t.Skipf("REDIS_URL maxmemory is %d; the full-memory leg wants 1 to 64 MB", max)
	}
	if err := r.FlushForTest(context.Background()); err != nil {
		t.Fatalf("flush: %v", err)
	}
	return r
}

// fill pushes 8 KiB blobs to filler mailboxes until Redis refuses with
// ErrOutOfMemory, and returns the filler ids so the test can free them.
//
// Right at the ceiling Redis is only just over: a command's own arguments
// count toward its memory, so a refused 8 KiB push can leave room for a
// small write a moment later. To test what happens past the ceiling, not
// on it, fill then lowers this test Redis's ceiling to 512 KiB under what
// it uses (restored when the test ends).
func fill(t *testing.T, r *Redis) []string {
	t.Helper()
	ctx := context.Background()
	blob := make([]byte, 8<<10)
	var ids []string
	for n := 0; ; n++ {
		id := "fill-" + strconv.Itoa(n/100)
		if n%100 == 0 {
			ids = append(ids, id)
		}
		err := r.MailboxPush(ctx, id, blob)
		if errors.Is(err, ErrOutOfMemory) {
			break
		}
		if err != nil {
			t.Fatalf("fill push %d: %v", n, err)
		}
		if n > 100000 {
			t.Fatal("Redis never reached its memory ceiling")
		}
	}
	res, err := r.do("CONFIG", "GET", "maxmemory")
	if err != nil {
		t.Fatalf("config get: %v", err)
	}
	was := asString(res.([]any)[1])
	t.Cleanup(func() { r.do("CONFIG", "SET", "maxmemory", was) })
	info, err := r.do("MEMORY", "STATS")
	if err != nil {
		t.Fatalf("memory stats: %v", err)
	}
	used := int64(0)
	stats := info.([]any)
	for i := 0; i+1 < len(stats); i += 2 {
		if asString(stats[i]) == "total.allocated" {
			used, _ = stats[i+1].(int64)
		}
	}
	if used <= 1<<20 {
		t.Fatalf("total.allocated = %d after filling", used)
	}
	if _, err := r.do("CONFIG", "SET", "maxmemory", used-512<<10); err != nil {
		t.Fatalf("lower maxmemory: %v", err)
	}
	return ids
}

func free(t *testing.T, r *Redis, ids []string) {
	t.Helper()
	for _, id := range ids {
		if _, err := r.do("DEL", "mbox:"+id); err != nil {
			t.Fatalf("free %s: %v", id, err)
		}
	}
}

func fullLimits() Limits {
	lim := DefaultLimits()
	lim.MaxFreshMailboxes = 0 // the memory ceiling is what this tests
	lim.MaxChannels = 0
	return lim
}

// At the memory ceiling, writes are refused with ErrOutOfMemory, the
// replay entry cannot be written (so the drain is refused, fail closed),
// and a drain of a mailbox, never-drained or owned, loses no mail: either
// it returns every blob or it is refused with every blob kept.
func TestRedisAtMaxmemoryLosesNoMail(t *testing.T) {
	r := fullRedis(t, fullLimits())
	ctx := context.Background()

	if _, err := r.MailboxDrain(ctx, "mb-owned"); err != nil { // the owner polls
		t.Fatalf("drain: %v", err)
	}
	want := map[string]int{"mb-fresh": 3, "mb-owned": 3}
	for id, n := range want {
		for i := 0; i < n; i++ {
			if err := r.MailboxPush(ctx, id, []byte(id+strconv.Itoa(i))); err != nil {
				t.Fatalf("push %s: %v", id, err)
			}
		}
	}
	filler := fill(t, r)

	if err := r.MailboxPush(ctx, "mb-fresh", []byte("more")); !errors.Is(err, ErrOutOfMemory) {
		t.Fatalf("push at the ceiling: got %v, want ErrOutOfMemory", err)
	}
	if _, err := r.ReplayCheck(ctx, "sig-full", replayTTLForTest); !errors.Is(err, ErrOutOfMemory) {
		t.Fatalf("replay entry at the ceiling: got %v, want ErrOutOfMemory", err)
	}
	if err := r.PresenceSet(ctx, "ch-full", "slot", []byte("p"), replayTTLForTest); !errors.Is(err, ErrOutOfMemory) {
		t.Fatalf("presence at the ceiling: got %v, want ErrOutOfMemory", err)
	}

	got := map[string]int{}
	for id := range want {
		blobs, err := r.MailboxDrain(ctx, id)
		switch {
		case err == nil:
			got[id] += len(blobs)
			t.Logf("%s drained at the ceiling: %d blobs", id, len(blobs))
		case errors.Is(err, ErrOutOfMemory):
			t.Logf("%s drain refused at the ceiling", id)
		default:
			t.Fatalf("drain %s at the ceiling: %v", id, err)
		}
	}

	free(t, r, filler)
	for id := range want {
		blobs, err := r.MailboxDrain(ctx, id)
		if err != nil {
			t.Fatalf("drain %s after freeing: %v", id, err)
		}
		got[id] += len(blobs)
	}
	for id, n := range want {
		if got[id] != n {
			t.Errorf("%s: %d blobs came back, want %d (mail lost)", id, got[id], n)
		}
	}
}

const replayTTLForTest = 10 * time.Minute
