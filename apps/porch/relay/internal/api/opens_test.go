package api_test

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// Each address (an IPv4 address, or an IPv6 /64) may open only so many
// mailboxes and channels a day. Without it one address opens all 20,000
// channel places in under 3 hours, and each is held for the ring's 60
// days, so no new group can open one. Owning a mailbox counts: anyone can
// make a key and drain its empty mailbox.
//
// Every test here runs on the memory store, and on Redis when REDIS_URL
// is set.

const opensPerDay = 3

func openRates() api.RateRules {
	r := generousRates()
	r.Open = api.RateRule{Burst: opensPerDay, PerSec: opensPerDay / 86400.0}
	return r
}

func eachStore(t *testing.T, run func(t *testing.T, rl *relay)) {
	t.Run("memory", func(t *testing.T) {
		run(t, newRelayWith(t, store.DefaultLimits(), openRates()))
	})
	t.Run("redis", func(t *testing.T) {
		url := os.Getenv("REDIS_URL")
		if url == "" {
			t.Skip("REDIS_URL not set; the Redis leg of the daily opening cap skipped")
		}
		rs, err := store.NewRedis(url, store.DefaultLimits())
		if err != nil {
			t.Fatalf("connect redis: %v", err)
		}
		if err := rs.FlushForTest(context.Background()); err != nil {
			t.Fatalf("flush: %v", err)
		}
		t.Cleanup(func() {
			rs.FlushForTest(context.Background())
			rs.Close()
		})
		clk := store.NewFakeClock(time.Now())
		h := api.New(api.Config{Store: rs, Now: clk.Now, Rates: openRates()})
		run(t, &relay{h: h, clk: clk})
	})
}

func chanID(n int) string {
	return "chan_opens_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" + string(rune('a'+n))
}

func presence(t *testing.T, rl *relay, ch, slot, from string) int {
	t.Helper()
	return rl.doFrom(t, "POST", "/v1/ch/"+ch+"/presence",
		map[string]any{"slotId": slot, "blob": []byte("p"), "ttlSec": 60}, from).Code
}

func TestOpeningCapAtTheLimitAndOnePast(t *testing.T) {
	eachStore(t, func(t *testing.T, rl *relay) {
		const ip = "198.51.100.7:4000"
		_, _, mbox := mailboxFixture(t)
		// Opening 1: a new mailbox. Openings 2 and 3: two channels.
		if c := rl.doFrom(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("m")}, ip).Code; c != http.StatusNoContent {
			t.Fatalf("open mailbox = %d", c)
		}
		for n := 0; n < opensPerDay-1; n++ {
			if c := presence(t, rl, chanID(n), testSlot, ip); c != http.StatusNoContent {
				t.Fatalf("opening %d = %d, want 204", n+2, c)
			}
		}
		// One past: refused, for a channel and for a mailbox alike.
		if c := presence(t, rl, chanID(9), testSlot, ip); c != http.StatusTooManyRequests {
			t.Fatalf("opening past the cap = %d, want 429", c)
		}
		if c := rl.doFrom(t, "POST", "/v1/ch/"+chanID(9)+"/bulletin", map[string]any{"blob": []byte("b")}, ip).Code; c != http.StatusTooManyRequests {
			t.Fatalf("bulletin opening past the cap = %d, want 429", c)
		}
		_, _, mbox2 := mailboxFixture(t)
		if c := rl.doFrom(t, "POST", "/v1/mailbox/"+mbox2, map[string]any{"blob": []byte("m")}, ip).Code; c != http.StatusTooManyRequests {
			t.Fatalf("mailbox opening past the cap = %d, want 429", c)
		}
		// What is already open keeps working.
		if c := presence(t, rl, chanID(0), testSlot, ip); c != http.StatusNoContent {
			t.Fatalf("write to an open channel = %d, want 204", c)
		}
		if c := rl.doFrom(t, "POST", "/v1/mailbox/"+mbox, map[string]any{"blob": []byte("m")}, ip).Code; c != http.StatusNoContent {
			t.Fatalf("push to an open mailbox = %d, want 204", c)
		}
		// Another address has its own day.
		if c := presence(t, rl, chanID(9), testSlot, "198.51.100.8:4000"); c != http.StatusNoContent {
			t.Fatalf("another address = %d, want 204", c)
		}
	})
}

func TestTwoAddressesInOneSlash64ShareTheOpeningCap(t *testing.T) {
	eachStore(t, func(t *testing.T, rl *relay) {
		for n := 0; n < opensPerDay; n++ {
			if c := presence(t, rl, chanID(n), testSlot, "[2001:db8:7:1::1]:4000"); c != http.StatusNoContent {
				t.Fatalf("opening %d = %d", n+1, c)
			}
		}
		if c := presence(t, rl, chanID(8), testSlot, "[2001:db8:7:1::2]:4000"); c != http.StatusTooManyRequests {
			t.Fatalf("a second address in the same /64 = %d, want 429", c)
		}
		if c := presence(t, rl, chanID(8), testSlot, "[2001:db8:7:2::1]:4000"); c != http.StatusNoContent {
			t.Fatalf("another /64 = %d, want 204", c)
		}
	})
}

// The bypass: make keys, drain each empty mailbox to own it, then push to
// the owned mailboxes with no cap. Owning now counts as opening, and past
// the cap a drain still returns the mail but does not own the mailbox.
func TestOwningMailboxesCountsAsOpening(t *testing.T) {
	eachStore(t, func(t *testing.T, rl *relay) {
		const ip = "198.51.100.9:4000"
		var lastMbox string
		for n := 0; n <= opensPerDay; n++ {
			pub, priv, mbox := mailboxFixture(t)
			w := rl.doFrom(t, "POST", "/v1/mailbox/"+mbox+"/drain",
				drainBody(priv, pub, mbox, rl.clk.Now().Unix()), ip)
			if w.Code != http.StatusOK {
				t.Fatalf("drain %d = %d; a drain is never refused for the cap", n, w.Code)
			}
			lastMbox = mbox
		}
		// The last drain was past the cap: that mailbox is not owned, so a
		// push to it opens a never-drained mailbox, and that is refused.
		if c := rl.doFrom(t, "POST", "/v1/mailbox/"+lastMbox, map[string]any{"blob": []byte("m")}, ip).Code; c != http.StatusTooManyRequests {
			t.Fatalf("push to a mailbox drained past the cap = %d, want 429", c)
		}
	})
}

// Writes to what already exists never spend an opening, even from an
// address that writes a lot.
func TestWritesToOpenChannelsSpendNothing(t *testing.T) {
	eachStore(t, func(t *testing.T, rl *relay) {
		if c := presence(t, rl, chanID(0), testSlot, "192.0.2.50:1"); c != http.StatusNoContent {
			t.Fatalf("open = %d", c)
		}
		const ip = "192.0.2.51:1"
		for i := 0; i < 10; i++ {
			if c := presence(t, rl, chanID(0), "slot_bbbbbbbbbbbbbbbb0", ip); c != http.StatusNoContent {
				t.Fatalf("write %d = %d", i, c)
			}
		}
		for n := 1; n <= opensPerDay; n++ {
			if c := presence(t, rl, chanID(n), testSlot, ip); c != http.StatusNoContent {
				t.Fatalf("opening %d after many plain writes = %d, want 204", n, c)
			}
		}
	})
}
