package store_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"porch/relay/internal/store"
)

// The conformance suite runs identically against every Store implementation
// (BUILD-SPEC W3: "ONE suite, both impls; Redis leg gated on REDIS_URL").
//
// factory returns a fresh empty store built with the given Limits, plus an
// advance function that moves that store's notion of time forward. The
// memstore leg advances a fake clock; the Redis leg sleeps for small
// durations and skips subtests that would need to sleep too long.

type factory func(t *testing.T, lim store.Limits) (st store.Store, advance func(time.Duration))

// testLimits keeps TTL-sensitive tests fast enough for the sleeping Redis leg.
func testLimits() store.Limits {
	return store.Limits{
		MailboxDepth: 5,
		MailboxTTL:   1200 * time.Millisecond,
		RingSize:     8,
		RingTTL:      1200 * time.Millisecond,
		PinCap:       3,
	}
}

func TestMemStoreConformance(t *testing.T) {
	runConformance(t, func(t *testing.T, lim store.Limits) (store.Store, func(time.Duration)) {
		clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
		return store.NewMem(lim, clk.Now), clk.Advance
	})
}

func TestRedisStoreConformance(t *testing.T) {
	url := os.Getenv("REDIS_URL")
	if url == "" {
		t.Skip("REDIS_URL not set; Redis conformance leg skipped (memstore leg is authoritative for CI)")
	}
	runConformance(t, func(t *testing.T, lim store.Limits) (store.Store, func(time.Duration)) {
		rs, err := store.NewRedis(url, lim)
		if err != nil {
			t.Fatalf("connect redis: %v", err)
		}
		t.Cleanup(func() { rs.Close() })
		if err := rs.FlushForTest(context.Background()); err != nil {
			t.Fatalf("flush: %v", err)
		}
		return rs, func(d time.Duration) {
			if d > 3*time.Second {
				t.Skipf("cannot advance a real clock by %v; covered by memstore leg", d)
			}
			time.Sleep(d + 100*time.Millisecond)
		}
	})
}

func runConformance(t *testing.T, mk factory) {
	ctx := context.Background()

	t.Run("invite lifecycle open to joined", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		exp, err := st.CreateInvite(ctx, "inv-basic", time.Hour)
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		if exp.IsZero() {
			t.Fatal("create returned zero expiry")
		}
		if _, err := st.CreateInvite(ctx, "inv-basic", time.Hour); !errors.Is(err, store.ErrConflict) {
			t.Fatalf("duplicate create: want ErrConflict, got %v", err)
		}
		if err := st.JoinInvite(ctx, "inv-basic", []byte("join-blob")); err != nil {
			t.Fatalf("join: %v", err)
		}
		if err := st.JoinInvite(ctx, "inv-basic", []byte("second")); !errors.Is(err, store.ErrGone) {
			t.Fatalf("second join: want ErrGone, got %v", err)
		}
		if err := st.JoinInvite(ctx, "inv-unknown", []byte("x")); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("unknown join: want ErrNotFound, got %v", err)
		}
	})

	t.Run("invite expiry is a real TTL", func(t *testing.T) {
		st, advance := mk(t, testLimits())
		if _, err := st.CreateInvite(ctx, "inv-ttl", time.Second); err != nil {
			t.Fatalf("create: %v", err)
		}
		advance(1100 * time.Millisecond)
		if err := st.JoinInvite(ctx, "inv-ttl", []byte("late")); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("join after expiry: want ErrNotFound, got %v", err)
		}
		// An expired id may be re-registered.
		if _, err := st.CreateInvite(ctx, "inv-ttl", time.Hour); err != nil {
			t.Fatalf("re-create after expiry: %v", err)
		}
	})

	t.Run("join blob is proof-pinned and byte-identical", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		blob := []byte{0, 1, 2, 0xff, 0xfe, 'j'}
		mustCreate(t, st, "inv-fetch", time.Hour)
		mustJoin(t, st, "inv-fetch", blob)

		if _, err := st.FetchJoin(ctx, "inv-open", "p"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("fetch unknown: want ErrNotFound, got %v", err)
		}
		got, err := st.FetchJoin(ctx, "inv-fetch", "proof-A") // first use pins
		if err != nil {
			t.Fatalf("fetch: %v", err)
		}
		if !bytes.Equal(got, blob) {
			t.Fatalf("blob not byte-identical: got %x want %x", got, blob)
		}
		if _, err := st.FetchJoin(ctx, "inv-fetch", "proof-B"); !errors.Is(err, store.ErrProof) {
			t.Fatalf("wrong proof: want ErrProof, got %v", err)
		}
		if _, err := st.FetchJoin(ctx, "inv-fetch", "proof-A"); err != nil {
			t.Fatalf("repeat fetch with pinned proof: %v", err)
		}
	})

	t.Run("fetch before join is not found", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		mustCreate(t, st, "inv-early", time.Hour)
		if _, err := st.FetchJoin(ctx, "inv-early", "p"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("fetch on open invite: want ErrNotFound, got %v", err)
		}
	})

	t.Run("grant shares fetch pin and deletes after retrieval", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		mustCreate(t, st, "inv-grant", time.Hour)
		mustJoin(t, st, "inv-grant", []byte("intro"))
		if _, err := st.FetchJoin(ctx, "inv-grant", "fetch-P"); err != nil {
			t.Fatalf("fetch: %v", err)
		}
		// PutGrant must present the same (pinned) fetch proof.
		if err := st.PutGrant(ctx, "inv-grant", "other", []byte("g")); !errors.Is(err, store.ErrProof) {
			t.Fatalf("grant with wrong proof: want ErrProof, got %v", err)
		}
		grant := []byte{9, 8, 7, 0}
		if err := st.PutGrant(ctx, "inv-grant", "fetch-P", grant); err != nil {
			t.Fatalf("grant: %v", err)
		}
		// TakeGrant pins its own proof, returns the blob once, then deletes.
		got, err := st.TakeGrant(ctx, "inv-grant", "grant-P")
		if err != nil {
			t.Fatalf("take: %v", err)
		}
		if !bytes.Equal(got, grant) {
			t.Fatalf("grant blob mismatch: got %x want %x", got, grant)
		}
		if _, err := st.TakeGrant(ctx, "inv-grant", "grant-P"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("second take: want ErrNotFound (deleted after retrieval), got %v", err)
		}
	})

	t.Run("grant before join is not found", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		mustCreate(t, st, "inv-pre", time.Hour)
		if err := st.PutGrant(ctx, "inv-pre", "p", []byte("g")); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("grant on open invite: want ErrNotFound, got %v", err)
		}
		if _, err := st.TakeGrant(ctx, "inv-pre", "p"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("take with no grant: want ErrNotFound, got %v", err)
		}
	})

	t.Run("exactly one concurrent join wins", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		mustCreate(t, st, "inv-race", time.Hour)
		const n = 32
		var wg sync.WaitGroup
		wins := make(chan int, n)
		for i := 0; i < n; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				if err := st.JoinInvite(ctx, "inv-race", []byte{byte(i)}); err == nil {
					wins <- i
				}
			}(i)
		}
		wg.Wait()
		close(wins)
		var winners []int
		for w := range wins {
			winners = append(winners, w)
		}
		if len(winners) != 1 {
			t.Fatalf("want exactly 1 winning join, got %d (%v)", len(winners), winners)
		}
		// The stored blob must be the winner's, intact.
		got, err := st.FetchJoin(ctx, "inv-race", "p")
		if err != nil {
			t.Fatalf("fetch: %v", err)
		}
		if !bytes.Equal(got, []byte{byte(winners[0])}) {
			t.Fatalf("stored blob %x is not the winner's (%d)", got, winners[0])
		}
	})

	t.Run("mailbox push drain FIFO", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		for i := 0; i < 3; i++ {
			if err := st.MailboxPush(ctx, "mb-1", []byte{byte(i), 0xff}); err != nil {
				t.Fatalf("push %d: %v", i, err)
			}
		}
		blobs, err := st.MailboxDrain(ctx, "mb-1")
		if err != nil {
			t.Fatalf("drain: %v", err)
		}
		if len(blobs) != 3 {
			t.Fatalf("want 3 blobs, got %d", len(blobs))
		}
		for i, b := range blobs {
			if !bytes.Equal(b, []byte{byte(i), 0xff}) {
				t.Fatalf("blob %d out of order or corrupted: %x", i, b)
			}
		}
		// Drained means gone.
		blobs, err = st.MailboxDrain(ctx, "mb-1")
		if err != nil || len(blobs) != 0 {
			t.Fatalf("second drain: want empty, got %d blobs, err %v", len(blobs), err)
		}
	})

	t.Run("mailbox depth cap", func(t *testing.T) {
		lim := testLimits()
		st, _ := mk(t, lim)
		for i := 0; i < lim.MailboxDepth; i++ {
			if err := st.MailboxPush(ctx, "mb-cap", []byte{byte(i)}); err != nil {
				t.Fatalf("push %d: %v", i, err)
			}
		}
		if err := st.MailboxPush(ctx, "mb-cap", []byte("overflow")); !errors.Is(err, store.ErrFull) {
			t.Fatalf("push past cap: want ErrFull, got %v", err)
		}
		// Draining frees the depth again.
		if _, err := st.MailboxDrain(ctx, "mb-cap"); err != nil {
			t.Fatalf("drain: %v", err)
		}
		if err := st.MailboxPush(ctx, "mb-cap", []byte("ok")); err != nil {
			t.Fatalf("push after drain: %v", err)
		}
	})

	t.Run("mailbox TTL expires and push refreshes it", func(t *testing.T) {
		lim := testLimits()
		st, advance := mk(t, lim)
		if err := st.MailboxPush(ctx, "mb-ttl", []byte("a")); err != nil {
			t.Fatalf("push: %v", err)
		}
		advance(lim.MailboxTTL * 2 / 3)
		if err := st.MailboxPush(ctx, "mb-ttl", []byte("b")); err != nil { // refreshes rolling TTL
			t.Fatalf("push 2: %v", err)
		}
		advance(lim.MailboxTTL * 2 / 3) // past first push's TTL, within refreshed TTL
		blobs, err := st.MailboxDrain(ctx, "mb-ttl")
		if err != nil || len(blobs) != 2 {
			t.Fatalf("after refresh: want both blobs, got %d, err %v", len(blobs), err)
		}
		if err := st.MailboxPush(ctx, "mb-ttl2", []byte("x")); err != nil {
			t.Fatalf("push: %v", err)
		}
		advance(lim.MailboxTTL + 100*time.Millisecond)
		blobs, err = st.MailboxDrain(ctx, "mb-ttl2")
		if err != nil || len(blobs) != 0 {
			t.Fatalf("after TTL: want empty, got %d, err %v", len(blobs), err)
		}
	})

	// Anyone can post to a mailbox id they choose. A mailbox its owner
	// has never drained keeps only the short MailboxFreshTTL; once the
	// owner drains it (a signed request), pushes get the full MailboxTTL.
	t.Run("never-drained mailbox keeps the short TTL", func(t *testing.T) {
		lim := testLimits()
		lim.MailboxFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if err := st.MailboxPush(ctx, "mb-fresh", []byte("a")); err != nil {
			t.Fatalf("push: %v", err)
		}
		if _, err := st.MailboxDrain(ctx, "mb-owned"); err != nil { // the owner polls
			t.Fatalf("drain: %v", err)
		}
		if err := st.MailboxPush(ctx, "mb-owned", []byte("b")); err != nil {
			t.Fatalf("push: %v", err)
		}
		advance(600 * time.Millisecond)
		if blobs, _ := st.MailboxDrain(ctx, "mb-fresh"); len(blobs) != 0 {
			t.Fatalf("never-drained mailbox outlived MailboxFreshTTL: %d blobs", len(blobs))
		}
		if blobs, _ := st.MailboxDrain(ctx, "mb-owned"); len(blobs) != 1 {
			t.Fatalf("owned mailbox lost its mail inside MailboxTTL: %d blobs", len(blobs))
		}
	})

	t.Run("global cap on never-drained mailboxes", func(t *testing.T) {
		lim := testLimits()
		lim.MaxFreshMailboxes = 2
		lim.MailboxFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		for _, id := range []string{"mb-cap-a", "mb-cap-b"} {
			if err := st.MailboxPush(ctx, id, []byte("x")); err != nil {
				t.Fatalf("push %s: %v", id, err)
			}
		}
		if err := st.MailboxPush(ctx, "mb-cap-c", []byte("x")); !errors.Is(err, store.ErrFull) {
			t.Fatalf("third new mailbox: want ErrFull, got %v", err)
		}
		if err := st.MailboxPush(ctx, "mb-cap-a", []byte("y")); err != nil {
			t.Fatalf("existing mailbox refused at the cap: %v", err)
		}
		// A mailbox its owner drains is never refused by the cap.
		if _, err := st.MailboxDrain(ctx, "mb-cap-own"); err != nil {
			t.Fatalf("drain: %v", err)
		}
		if err := st.MailboxPush(ctx, "mb-cap-own", []byte("z")); err != nil {
			t.Fatalf("owned mailbox refused at the cap: %v", err)
		}
		// Room comes back when the fresh ones expire.
		advance(600 * time.Millisecond)
		if err := st.MailboxPush(ctx, "mb-cap-c", []byte("x")); err != nil {
			t.Fatalf("new mailbox after the fresh ones expired: %v", err)
		}
	})

	t.Run("global cap on channels", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 2
		st, advance := mk(t, lim)
		if _, err := st.BulletinAppend(ctx, "ch-cap-a", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin a: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-cap-b", "slot-1", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("presence b: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-cap-c", "", []byte("b"), false, 0); !errors.Is(err, store.ErrFull) {
			t.Fatalf("bulletin on a third channel: want ErrFull, got %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-cap-c", "", []byte("b"), true, time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("pin on a third channel: want ErrFull, got %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-cap-c", "slot-1", []byte("p"), time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("presence on a third channel: want ErrFull, got %v", err)
		}
		// Existing channels keep working at the cap.
		if _, err := st.BulletinAppend(ctx, "ch-cap-b", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin on an existing channel: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-cap-a", "slot-2", []byte("p"), time.Second); err != nil {
			t.Fatalf("presence on an existing channel: %v", err)
		}
		// Room comes back when a channel expires (RingTTL 1.2 s).
		advance(1300 * time.Millisecond)
		if err := st.PresenceSet(ctx, "ch-cap-c", "slot-1", []byte("p"), time.Second); err != nil {
			t.Fatalf("new channel after others expired: %v", err)
		}
	})

	// The relay caps how many mailboxes and channels one address may open
	// a day. The store asks the Opener in ctx at the moment a write would
	// open one; writes to what already exists never spend.
	t.Run("opening asks the opener; writes to what exists do not spend", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		op := &countOpener{left: 2}
		octx := store.WithOpener(ctx, op)
		if err := st.MailboxPush(octx, "mb-o1", []byte("a")); err != nil {
			t.Fatalf("open mailbox: %v", err)
		}
		if err := st.MailboxPush(octx, "mb-o1", []byte("b")); err != nil {
			t.Fatalf("push to an open mailbox: %v", err)
		}
		if err := st.PresenceSet(octx, "ch-o1", "slot-1", []byte("p"), time.Second); err != nil {
			t.Fatalf("open channel: %v", err)
		}
		if err := st.PresenceSet(octx, "ch-o1", "slot-2", []byte("p"), time.Second); err != nil {
			t.Fatalf("presence on an open channel: %v", err)
		}
		if _, err := st.BulletinAppend(octx, "ch-o1", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin on an open channel: %v", err)
		}
		if _, err := st.BulletinAppend(octx, "ch-o1", "", []byte("b"), true, time.Second); err != nil {
			t.Fatalf("pin on an open channel: %v", err)
		}
		if got := op.remaining(); got != 0 {
			t.Fatalf("openings left = %d, want 0 (two opened, nothing else spent)", got)
		}
		if err := st.MailboxPush(octx, "mb-o2", []byte("a")); !errors.Is(err, store.ErrFull) {
			t.Fatalf("new mailbox past the openings: want ErrFull, got %v", err)
		}
		if err := st.PresenceSet(octx, "ch-o2", "slot-1", []byte("p"), time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("new channel by presence past the openings: want ErrFull, got %v", err)
		}
		if _, err := st.BulletinAppend(octx, "ch-o2", "", []byte("b"), false, 0); !errors.Is(err, store.ErrFull) {
			t.Fatalf("new channel by bulletin past the openings: want ErrFull, got %v", err)
		}
		if _, err := st.BulletinAppend(octx, "ch-o2", "", []byte("b"), true, time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("new channel by pin past the openings: want ErrFull, got %v", err)
		}
		if got := op.remaining(); got != 0 {
			t.Fatalf("refused openings changed the count: %d left", got)
		}
	})

	// Owning a mailbox counts as opening one: anyone can make a key and
	// drain its empty mailbox. Without an opening the drain still returns
	// the mail, but the mailbox stays never-drained (short TTL, capped).
	t.Run("a drain that would own a mailbox asks the opener", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		if err := st.MailboxPush(ctx, "mb-own", []byte("m")); err != nil {
			t.Fatalf("push: %v", err)
		}
		none := store.WithOpener(ctx, &countOpener{})
		blobs, err := st.MailboxDrain(none, "mb-own")
		if err != nil || len(blobs) != 1 {
			t.Fatalf("drain without an opening: %d blobs, err %v (the mail must still come back)", len(blobs), err)
		}
		if err := st.MailboxPush(none, "mb-own", []byte("m")); !errors.Is(err, store.ErrFull) {
			t.Fatalf("push after an unowned drain opens a new mailbox: want ErrFull, got %v", err)
		}
		one := &countOpener{left: 1}
		if _, err := st.MailboxDrain(store.WithOpener(ctx, one), "mb-own"); err != nil {
			t.Fatalf("drain: %v", err)
		}
		if one.remaining() != 0 {
			t.Fatal("owning the mailbox did not spend an opening")
		}
		if err := st.MailboxPush(none, "mb-own", []byte("m")); err != nil {
			t.Fatalf("push to an owned mailbox spends nothing: %v", err)
		}
		if _, err := st.MailboxDrain(none, "mb-own"); err != nil {
			t.Fatalf("the owner's next drain spends nothing: %v", err)
		}
		if err := st.MailboxPush(none, "mb-own", []byte("m")); err != nil {
			t.Fatalf("still owned after a drain with no openings left: %v", err)
		}
	})

	// A channel holds its place in the channel cap only briefly until a
	// second writer (a second presence slot) shows up: one address cannot
	// hold slots for the ring's whole 60 days with writes nobody else makes.
	t.Run("a channel with one writer holds its place only briefly", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 1
		lim.ChannelFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if _, err := st.BulletinAppend(ctx, "ch-one", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-one", "slot-1", []byte("p"), time.Second); err != nil {
			t.Fatalf("presence: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-one", "slot-1", []byte("p"), time.Second); err != nil {
			t.Fatalf("same writer again: %v", err)
		}
		advance(600 * time.Millisecond)
		if err := st.PresenceSet(ctx, "ch-next", "slot-1", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("a one-writer channel still held its place past ChannelFreshTTL: %v", err)
		}
		// The ring itself lives on: only the place in the cap was short.
		entries, err := st.BulletinList(ctx, "ch-one", 0)
		if err != nil || len(entries) != 1 {
			t.Fatalf("one-writer channel lost its ring: %d entries, err %v", len(entries), err)
		}
	})

	t.Run("a second writer gives a channel its full life", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 1
		lim.ChannelFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if err := st.PresenceSet(ctx, "ch-two", "slot-1", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("presence 1: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-two", "slot-2", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("presence 2: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-two", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin: %v", err)
		}
		advance(600 * time.Millisecond) // past ChannelFreshTTL, inside RingTTL
		if err := st.PresenceSet(ctx, "ch-other", "slot-1", []byte("p"), time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("a two-writer channel lost its place early: want ErrFull, got %v", err)
		}
	})

	// A channel used only for bulletins (a quiet group's roster ops, an
	// old channel's rotation copy) is confirmed the same way: by a second
	// writer's bulletin, named by that member's bulletin writer id.
	t.Run("a second bulletin writer gives a channel its full life", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 1
		lim.ChannelFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if _, err := st.BulletinAppend(ctx, "ch-bul", "slot-1", []byte("b1"), false, 0); err != nil {
			t.Fatalf("bulletin 1: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-bul", "slot-2", []byte("b2"), true, time.Second); err != nil {
			t.Fatalf("bulletin 2: %v", err)
		}
		advance(600 * time.Millisecond) // past ChannelFreshTTL, inside RingTTL
		if err := st.PresenceSet(ctx, "ch-other", "slot-1", []byte("p"), time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("a channel with two bulletin writers lost its place early: want ErrFull, got %v", err)
		}
	})

	t.Run("a presence writer and a second bulletin writer confirm a channel", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 1
		lim.ChannelFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if err := st.PresenceSet(ctx, "ch-mix", "slot-1", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("presence: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-mix", "slot-2", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin: %v", err)
		}
		advance(600 * time.Millisecond)
		if err := st.PresenceSet(ctx, "ch-other", "slot-1", []byte("p"), time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("a two-writer channel lost its place early: want ErrFull, got %v", err)
		}
	})

	// The same id twice is one writer: it never confirms its own channel.
	// (The app names a member's bulletins by an id unlike its presence
	// slot, so the relay sees a member who writes both as two writers.)
	t.Run("one writer's bulletins and presence keep the place brief", func(t *testing.T) {
		lim := testLimits()
		lim.MaxChannels = 1
		lim.ChannelFreshTTL = 400 * time.Millisecond
		st, advance := mk(t, lim)
		if _, err := st.BulletinAppend(ctx, "ch-solo", "slot-1", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-solo", "slot-1", []byte("p"), time.Second); err != nil {
			t.Fatalf("presence: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-solo", "slot-1", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin again: %v", err)
		}
		if _, err := st.BulletinAppend(ctx, "ch-solo", "", []byte("b"), false, 0); err != nil {
			t.Fatalf("bulletin with no writer: %v", err)
		}
		advance(600 * time.Millisecond)
		if err := st.PresenceSet(ctx, "ch-next", "slot-1", []byte("p"), 300*time.Millisecond); err != nil {
			t.Fatalf("a one-writer channel held its place past ChannelFreshTTL: %v", err)
		}
	})

	t.Run("concurrent drains: returned equals deleted", func(t *testing.T) {
		st, _ := mk(t, store.Limits{MailboxDepth: 200, MailboxTTL: time.Hour,
			RingSize: 8, RingTTL: time.Hour, PinCap: 3})
		const n = 100
		for i := 0; i < n; i++ {
			if err := st.MailboxPush(ctx, "mb-race", []byte{byte(i)}); err != nil {
				t.Fatalf("push %d: %v", i, err)
			}
		}
		const drains = 8
		results := make([][][]byte, drains)
		var wg sync.WaitGroup
		for d := 0; d < drains; d++ {
			wg.Add(1)
			go func(d int) {
				defer wg.Done()
				blobs, err := st.MailboxDrain(ctx, "mb-race")
				if err != nil {
					t.Errorf("drain %d: %v", d, err)
					return
				}
				results[d] = blobs
			}(d)
		}
		wg.Wait()
		seen := map[byte]int{}
		total := 0
		for _, r := range results {
			for _, b := range r {
				seen[b[0]]++
				total++
			}
		}
		if total != n {
			t.Fatalf("drains returned %d blobs total, want %d (returned != deleted)", total, n)
		}
		for k, c := range seen {
			if c != 1 {
				t.Fatalf("blob %d returned %d times (duplicate delivery)", k, c)
			}
		}
	})

	t.Run("replay check", func(t *testing.T) {
		st, advance := mk(t, testLimits())
		fresh, err := st.ReplayCheck(ctx, "sig-1", time.Second)
		if err != nil || !fresh {
			t.Fatalf("first check: want fresh, got %v err %v", fresh, err)
		}
		fresh, err = st.ReplayCheck(ctx, "sig-1", time.Second)
		if err != nil || fresh {
			t.Fatalf("replayed check: want not fresh, got %v err %v", fresh, err)
		}
		advance(1100 * time.Millisecond)
		fresh, err = st.ReplayCheck(ctx, "sig-1", time.Second)
		if err != nil || !fresh {
			t.Fatalf("after TTL: want fresh again, got %v err %v", fresh, err)
		}
	})

	t.Run("presence set list overwrite expire", func(t *testing.T) {
		st, advance := mk(t, testLimits())
		if err := st.PresenceSet(ctx, "ch-1", "slot-a", []byte("A1"), time.Second); err != nil {
			t.Fatalf("set: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-1", "slot-b", []byte("B1"), 2*time.Second); err != nil {
			t.Fatalf("set: %v", err)
		}
		if err := st.PresenceSet(ctx, "ch-2", "slot-a", []byte("other-channel"), time.Second); err != nil {
			t.Fatalf("set: %v", err)
		}
		slots, err := st.PresenceList(ctx, "ch-1")
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		if len(slots) != 2 {
			t.Fatalf("want 2 slots, got %d", len(slots))
		}
		for _, s := range slots {
			if s.ExpiresAt.IsZero() {
				t.Fatalf("slot %s has zero ExpiresAt", s.SlotID)
			}
		}
		// Overwrite = update + extend.
		if err := st.PresenceSet(ctx, "ch-1", "slot-a", []byte("A2"), 2*time.Second); err != nil {
			t.Fatalf("overwrite: %v", err)
		}
		advance(1200 * time.Millisecond) // past slot-a's ORIGINAL ttl
		slots, err = st.PresenceList(ctx, "ch-1")
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		got := map[string]string{}
		for _, s := range slots {
			got[s.SlotID] = string(s.Blob)
		}
		if got["slot-a"] != "A2" {
			t.Fatalf("overwritten slot-a: want A2 alive after extension, got %q (slots %v)", got["slot-a"], got)
		}
		advance(1000 * time.Millisecond) // now past everything
		slots, err = st.PresenceList(ctx, "ch-1")
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		if len(slots) != 0 {
			t.Fatalf("presence must structurally not exist after expiry; got %d slots", len(slots))
		}
	})

	t.Run("bulletin seq is monotonic per channel", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		var last uint64
		for i := 0; i < 5; i++ {
			seq, err := st.BulletinAppend(ctx, "ch-seq", "", []byte{byte(i)}, false, 0)
			if err != nil {
				t.Fatalf("append %d: %v", i, err)
			}
			if seq <= last {
				t.Fatalf("seq not monotonic: %d after %d", seq, last)
			}
			last = seq
		}
		// Independent channels have independent counters.
		seq, err := st.BulletinAppend(ctx, "ch-seq-other", "", []byte("x"), false, 0)
		if err != nil {
			t.Fatalf("append other: %v", err)
		}
		if seq != 1 {
			t.Fatalf("fresh channel seq: want 1, got %d", seq)
		}
	})

	t.Run("ring evicts oldest unpinned only, pinned survive", func(t *testing.T) {
		lim := testLimits()
		st, _ := mk(t, lim)
		pinSeq, err := st.BulletinAppend(ctx, "ch-ring", "", []byte("PINNED"), true, time.Hour)
		if err != nil {
			t.Fatalf("pin: %v", err)
		}
		var seqs []uint64
		for i := 0; i < lim.RingSize+3; i++ { // overflow the ring
			s, err := st.BulletinAppend(ctx, "ch-ring", "", []byte{byte(i)}, false, 0)
			if err != nil {
				t.Fatalf("append %d: %v", i, err)
			}
			seqs = append(seqs, s)
		}
		entries, err := st.BulletinList(ctx, "ch-ring", 0)
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		var unpinned, pinned []store.BulletinEntry
		for _, e := range entries {
			if e.Pinned {
				pinned = append(pinned, e)
			} else {
				unpinned = append(unpinned, e)
			}
		}
		if len(pinned) != 1 || pinned[0].Seq != pinSeq || !bytes.Equal(pinned[0].Blob, []byte("PINNED")) {
			t.Fatalf("pinned entry lost under ring pressure: %+v", pinned)
		}
		if pinned[0].ExpiresAt.IsZero() {
			t.Fatal("pinned entry must carry its expiry")
		}
		if len(unpinned) != lim.RingSize {
			t.Fatalf("want %d unpinned survivors, got %d", lim.RingSize, len(unpinned))
		}
		// Survivors are exactly the newest RingSize appends, in seq order.
		wantOldest := seqs[len(seqs)-lim.RingSize]
		if unpinned[0].Seq != wantOldest {
			t.Fatalf("oldest survivor seq %d, want %d", unpinned[0].Seq, wantOldest)
		}
		for i := 1; i < len(unpinned); i++ {
			if unpinned[i].Seq <= unpinned[i-1].Seq {
				t.Fatal("entries not ordered by seq")
			}
		}
	})

	t.Run("bulletin afterSeq paging", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		var seqs []uint64
		for i := 0; i < 4; i++ {
			s, err := st.BulletinAppend(ctx, "ch-page", "", []byte{byte(i)}, false, 0)
			if err != nil {
				t.Fatalf("append: %v", err)
			}
			seqs = append(seqs, s)
		}
		entries, err := st.BulletinList(ctx, "ch-page", seqs[1])
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		if len(entries) != 2 || entries[0].Seq != seqs[2] || entries[1].Seq != seqs[3] {
			t.Fatalf("afterSeq=%d: got %+v", seqs[1], entries)
		}
	})

	t.Run("pinned cap and pin expiry", func(t *testing.T) {
		lim := testLimits()
		st, advance := mk(t, lim)
		for i := 0; i < lim.PinCap; i++ {
			if _, err := st.BulletinAppend(ctx, "ch-pin", "", []byte{byte(i)}, true, time.Second); err != nil {
				t.Fatalf("pin %d: %v", i, err)
			}
		}
		if _, err := st.BulletinAppend(ctx, "ch-pin", "", []byte("over"), true, time.Second); !errors.Is(err, store.ErrFull) {
			t.Fatalf("pin past cap: want ErrFull, got %v", err)
		}
		advance(1100 * time.Millisecond) // pins die by their own TTL
		entries, err := st.BulletinList(ctx, "ch-pin", 0)
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		for _, e := range entries {
			if e.Pinned {
				t.Fatalf("pinned entry survived its TTL: %+v", e)
			}
		}
		// Capacity is freed by expiry.
		if _, err := st.BulletinAppend(ctx, "ch-pin", "", []byte("again"), true, time.Second); err != nil {
			t.Fatalf("pin after expiry: %v", err)
		}
	})

	t.Run("ring TTL is sliding and expires", func(t *testing.T) {
		lim := testLimits()
		st, advance := mk(t, lim)
		if _, err := st.BulletinAppend(ctx, "ch-ttl", "", []byte("a"), false, 0); err != nil {
			t.Fatalf("append: %v", err)
		}
		advance(lim.RingTTL * 2 / 3)
		if _, err := st.BulletinAppend(ctx, "ch-ttl", "", []byte("b"), false, 0); err != nil { // slides TTL
			t.Fatalf("append 2: %v", err)
		}
		advance(lim.RingTTL * 2 / 3)
		entries, err := st.BulletinList(ctx, "ch-ttl", 0)
		if err != nil || len(entries) != 2 {
			t.Fatalf("within slid TTL: want 2 entries, got %d err %v", len(entries), err)
		}
		advance(lim.RingTTL + 100*time.Millisecond)
		entries, err = st.BulletinList(ctx, "ch-ttl", 0)
		if err != nil || len(entries) != 0 {
			t.Fatalf("after ring TTL: want empty, got %d err %v", len(entries), err)
		}
	})

	t.Run("stored blobs are byte-identical on every path", func(t *testing.T) {
		st, _ := mk(t, testLimits())
		// Binary-hostile blob: NULs, high bytes, JSON metacharacters.
		blob := []byte{0x00, 0xff, '"', '\\', 0x7f, 0x80, '\n', '{', 0x01}
		mustCreate(t, st, "inv-bytes", time.Hour)
		mustJoin(t, st, "inv-bytes", blob)
		if got, _ := st.FetchJoin(ctx, "inv-bytes", "p"); !bytes.Equal(got, blob) {
			t.Fatalf("join blob mutated: %x != %x", got, blob)
		}
		if err := st.PutGrant(ctx, "inv-bytes", "p", blob); err != nil {
			t.Fatalf("grant: %v", err)
		}
		if got, _ := st.TakeGrant(ctx, "inv-bytes", "g"); !bytes.Equal(got, blob) {
			t.Fatalf("grant blob mutated")
		}
		if err := st.MailboxPush(ctx, "mb-bytes", blob); err != nil {
			t.Fatalf("push: %v", err)
		}
		if got, _ := st.MailboxDrain(ctx, "mb-bytes"); len(got) != 1 || !bytes.Equal(got[0], blob) {
			t.Fatalf("mailbox blob mutated")
		}
		if err := st.PresenceSet(ctx, "ch-bytes", "s", blob, time.Hour); err != nil {
			t.Fatalf("presence: %v", err)
		}
		if got, _ := st.PresenceList(ctx, "ch-bytes"); len(got) != 1 || !bytes.Equal(got[0].Blob, blob) {
			t.Fatalf("presence blob mutated")
		}
		for _, pinned := range []bool{false, true} {
			if _, err := st.BulletinAppend(ctx, "ch-bytes", "", blob, pinned, time.Hour); err != nil {
				t.Fatalf("bulletin pinned=%v: %v", pinned, err)
			}
		}
		entries, _ := st.BulletinList(ctx, "ch-bytes", 0)
		if len(entries) != 2 {
			t.Fatalf("want 2 bulletin entries, got %d", len(entries))
		}
		for _, e := range entries {
			if !bytes.Equal(e.Blob, blob) {
				t.Fatalf("bulletin blob mutated (pinned=%v)", e.Pinned)
			}
		}
	})
}

// countOpener grants left openings and counts what is given back.
type countOpener struct {
	mu   sync.Mutex
	left int
}

func (c *countOpener) Take() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.left <= 0 {
		return false
	}
	c.left--
	return true
}

func (c *countOpener) Refund() {
	c.mu.Lock()
	c.left++
	c.mu.Unlock()
}

func (c *countOpener) remaining() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.left
}

func mustCreate(t *testing.T, st store.Store, id string, ttl time.Duration) {
	t.Helper()
	if _, err := st.CreateInvite(context.Background(), id, ttl); err != nil {
		t.Fatalf("create %s: %v", id, err)
	}
}

func mustJoin(t *testing.T, st store.Store, id string, blob []byte) {
	t.Helper()
	if err := st.JoinInvite(context.Background(), id, blob); err != nil {
		t.Fatalf("join %s: %v", id, err)
	}
}

// Guard: DefaultLimits must match BUILD-SPEC §4/§5.4 exactly.
func TestDefaultLimitsMatchSpec(t *testing.T) {
	lim := store.DefaultLimits()
	want := store.Limits{
		MailboxDepth: 200,
		MailboxTTL:   30 * 24 * time.Hour,
		RingSize:     8,
		RingTTL:      60 * 24 * time.Hour,
		PinCap:       16,
		// Storage bounds (not in BUILD-SPEC; the relay's own policy).
		MailboxFreshTTL:   72 * time.Hour,
		MaxFreshMailboxes: 20000,
		MaxChannels:       20000,
		ChannelFreshTTL:   72 * time.Hour,
	}
	if lim != want {
		t.Fatalf("DefaultLimits = %+v, want spec values %+v", lim, want)
	}
}
