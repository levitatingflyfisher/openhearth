package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"porch/relay/internal/store"
)

func TestRateLimiterBurstAndRefill(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	l := newLimiter(clk.Now)
	rule := RateRule{Burst: 3, PerSec: 1}

	for i := 0; i < 3; i++ {
		if !l.allow("1.2.3.4", "test", rule) {
			t.Fatalf("request %d within burst denied", i)
		}
	}
	if l.allow("1.2.3.4", "test", rule) {
		t.Fatal("request past burst allowed")
	}
	clk.Advance(1 * time.Second) // refills one token
	if !l.allow("1.2.3.4", "test", rule) {
		t.Fatal("request after refill denied")
	}
	if l.allow("1.2.3.4", "test", rule) {
		t.Fatal("second request after single-token refill allowed")
	}
	clk.Advance(time.Hour) // refill caps at burst
	for i := 0; i < 3; i++ {
		if !l.allow("1.2.3.4", "test", rule) {
			t.Fatalf("request %d after long idle denied", i)
		}
	}
	if l.allow("1.2.3.4", "test", rule) {
		t.Fatal("burst cap not enforced after long idle")
	}
}

func TestRateLimiterIsolatesIPsAndBuckets(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	l := newLimiter(clk.Now)
	rule := RateRule{Burst: 1, PerSec: 0.001}

	if !l.allow("1.1.1.1", "a", rule) {
		t.Fatal("first request denied")
	}
	if l.allow("1.1.1.1", "a", rule) {
		t.Fatal("exhausted bucket allowed")
	}
	if !l.allow("2.2.2.2", "a", rule) {
		t.Fatal("different IP wrongly throttled")
	}
	if !l.allow("1.1.1.1", "b", rule) {
		t.Fatal("different bucket wrongly throttled")
	}
}

func TestRateLimiterPrunesIdleBuckets(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	l := newLimiter(clk.Now)
	rule := RateRule{Burst: 1, PerSec: 1}
	for i := 0; i < limiterPruneThreshold+10; i++ {
		l.allow(string(rune('a'+i%26))+string(rune('0'+i/26)), "x", rule)
	}
	clk.Advance(2 * limiterIdleEviction)
	l.allow("fresh", "x", rule) // triggers prune
	l.mu.Lock()
	n := len(l.buckets)
	l.mu.Unlock()
	if n > 2 {
		t.Fatalf("idle buckets not pruned: %d remain", n)
	}
}

// A bucket is dropped only once it has refilled to full: dropping a spent
// bucket would hand its owner a fresh burst. For a daily cap that refills
// over a day, being idle for the eviction time must not reset it.
func TestRateLimiterNeverForgetsASpentBucket(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	l := newLimiter(clk.Now)
	daily := RateRule{Burst: 2, PerSec: 2.0 / 86400}
	for i := 0; i < 2; i++ {
		if !l.allow("198.51.100.1", "open", daily) {
			t.Fatalf("opening %d within the day denied", i)
		}
	}
	for i := 0; i < limiterPruneThreshold+10; i++ {
		l.allow(fmt.Sprintf("10.%d.%d.1", i/256, i%256), "x", RateRule{Burst: 1, PerSec: 1})
	}
	clk.Advance(2 * limiterIdleEviction)
	l.allow("203.0.113.250", "x", RateRule{Burst: 1, PerSec: 1}) // triggers prune
	if l.allow("198.51.100.1", "open", daily) {
		t.Fatal("a spent daily bucket was pruned and came back full")
	}
	l.mu.Lock()
	n := len(l.buckets)
	l.mu.Unlock()
	if n > 3 {
		t.Fatalf("full idle buckets not pruned: %d remain", n)
	}
}

// refund gives back one token, never past the burst.
func TestRateLimiterRefund(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	l := newLimiter(clk.Now)
	rule := RateRule{Burst: 1, PerSec: 0.0001}
	if !l.allow("192.0.2.1", "open", rule) {
		t.Fatal("first denied")
	}
	l.refund("192.0.2.1", "open", rule)
	if !l.allow("192.0.2.1", "open", rule) {
		t.Fatal("refunded token not there")
	}
	l.refund("192.0.2.1", "open", rule)
	l.refund("192.0.2.1", "open", rule) // past the burst: capped
	l.allow("192.0.2.1", "open", rule)
	if l.allow("192.0.2.1", "open", rule) {
		t.Fatal("refund went past the burst")
	}
}

// TestTrustForwardedKeyIsTrustedHopNotSpoofable proves the X-Forwarded-For
// rate-limit key cannot be forged by the client. Behind the single trusted
// terminator (the compose Caddy), the only trustworthy XFF hop is the LAST
// one — the hop Caddy itself appended from the TCP connection. Everything
// left of it arrived inside the client's own request and is attacker-chosen.
// A client must NOT escape its bucket by minting a fresh leftmost hop per
// request.
func TestTrustForwardedKeyIsTrustedHopNotSpoofable(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	st := store.NewMem(store.DefaultLimits(), clk.Now)
	generous := RateRule{Burst: 10000, PerSec: 10000}
	h := New(Config{Store: st, Now: clk.Now, TrustForwarded: true, Rates: RateRules{
		InviteCreate: generous, MailboxPost: generous, Drain: generous,
		ChannelWrite: generous,
		Read:         RateRule{Burst: 1, PerSec: 0.0001}, // one read, ~no refill
	}})

	get := func(xff string) int {
		req := httptest.NewRequest("GET", "/v1/ch/chan_xffaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0/presence", nil)
		// RemoteAddr is Caddy's compose-network address — same for everyone.
		req.RemoteAddr = "172.18.0.4:41234"
		if xff != "" {
			req.Header.Set("X-Forwarded-For", xff)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w.Code
	}

	// The real client (203.0.113.7, appended by Caddy) spends its one token.
	if code := get("203.0.113.7"); code != http.StatusOK {
		t.Fatalf("first request = %d, want 200", code)
	}
	// Same client forging a fresh leftmost hop each request must stay in its
	// bucket: the key is the trusted (rightmost) hop, not the spoofed one.
	for i := 0; i < 5; i++ {
		spoofed := fmt.Sprintf("42.42.42.%d, 203.0.113.7", i)
		if code := get(spoofed); code != http.StatusTooManyRequests {
			t.Fatalf("spoofed XFF %q escaped the rate limit: got %d, want 429", spoofed, code)
		}
	}
	// A genuinely different client (different Caddy-appended hop) is not
	// throttled by the first client's bucket.
	if code := get("42.42.42.0, 198.51.100.9"); code != http.StatusOK {
		t.Fatalf("distinct trusted hop wrongly throttled: got %d, want 200", code)
	}
}

// TestClientIPTrustedHopParsing pins clientIP's exact key derivation.
func TestClientIPTrustedHopParsing(t *testing.T) {
	cases := []struct {
		name  string
		trust bool
		xff   string
		want  string
	}{
		{"no trust ignores XFF entirely", false, "6.6.6.6, 7.7.7.7", "192.0.2.50"},
		{"trust without XFF uses RemoteAddr", true, "", "192.0.2.50"},
		{"trust single hop", true, "203.0.113.7", "203.0.113.7"},
		{"trust takes last hop of multi-hop", true, "6.6.6.6, 10.0.0.1, 203.0.113.7", "203.0.113.7"},
		{"trust trims whitespace around last hop", true, "6.6.6.6 ,\t 203.0.113.7  ", "203.0.113.7"},
		{"trust falls back on empty last hop", true, "6.6.6.6,", "192.0.2.50"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := &server{trustForwarded: tc.trust}
			req := httptest.NewRequest("GET", "/v1/healthz", nil)
			req.RemoteAddr = "192.0.2.50:9999"
			if tc.xff != "" {
				req.Header.Set("X-Forwarded-For", tc.xff)
			}
			if got := s.clientIP(req); got != tc.want {
				t.Fatalf("clientIP(trust=%v, xff=%q) = %q, want %q", tc.trust, tc.xff, got, tc.want)
			}
		})
	}
}

func TestDefaultRateRulesMatchSpec(t *testing.T) {
	r := DefaultRateRules()
	// Spec pins invite creation at ≤50/day/IP.
	if r.InviteCreate.Burst != 50 {
		t.Fatalf("invite-create burst = %v, want 50", r.InviteCreate.Burst)
	}
	perDay := r.InviteCreate.PerSec * 86400
	if perDay < 49.9 || perDay > 50.1 {
		t.Fatalf("invite-create refill = %v/day, want 50/day", perDay)
	}
	// Opening mailboxes and channels: 50 a day per address (or /64).
	if r.Open.Burst != 50 || r.Open.PerSec*86400 < 49.9 || r.Open.PerSec*86400 > 50.1 {
		t.Fatalf("open rule = %+v, want 50 a day", r.Open)
	}
	// Every other bucket must be non-zero (enforced on all endpoints).
	for name, rule := range map[string]RateRule{
		"MailboxPost": r.MailboxPost, "Drain": r.Drain,
		"ChannelWrite": r.ChannelWrite, "Read": r.Read, "Open": r.Open,
	} {
		if rule.Burst <= 0 || rule.PerSec <= 0 {
			t.Fatalf("bucket %s has no limit: %+v", name, rule)
		}
	}
}

// An IPv6 /64 is one subscriber's network in practice, and holds 2^64
// addresses. Keyed per address, one client could mint a fresh bucket for
// every request. Buckets are keyed on the /64; IPv4 stays per address.
func TestRateKeyIsTheIPv6Slash64(t *testing.T) {
	same := [][2]string{
		{"2001:db8:1:2::1", "2001:db8:1:2:ffff:ffff:ffff:ffff"},
		{"2001:db8:1:2:aaaa::1", "2001:DB8:1:2:bbbb::2"},
		{"::ffff:192.0.2.7", "192.0.2.7"}, // IPv4 mapped into IPv6 is IPv4
	}
	for _, p := range same {
		if rateKey(p[0]) != rateKey(p[1]) {
			t.Errorf("%s and %s got different buckets: %q, %q", p[0], p[1], rateKey(p[0]), rateKey(p[1]))
		}
	}
	differ := [][2]string{
		{"2001:db8:1:2::1", "2001:db8:1:3::1"},
		{"192.0.2.7", "192.0.2.8"},
	}
	for _, p := range differ {
		if rateKey(p[0]) == rateKey(p[1]) {
			t.Errorf("%s and %s share a bucket %q", p[0], p[1], rateKey(p[0]))
		}
	}
	// Not an address (a broken header): kept whole, never merged with others.
	if rateKey("not-an-ip") != "not-an-ip" {
		t.Errorf("rateKey(not-an-ip) = %q", rateKey("not-an-ip"))
	}
}

func TestOneSlash64SharesOneBucketOverHTTP(t *testing.T) {
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	st := store.NewMem(store.DefaultLimits(), clk.Now)
	generous := RateRule{Burst: 10000, PerSec: 10000}
	h := New(Config{Store: st, Now: clk.Now, Rates: RateRules{
		InviteCreate: generous, MailboxPost: generous, Drain: generous,
		ChannelWrite: generous,
		Read:         RateRule{Burst: 1, PerSec: 0.0001},
	}})
	get := func(remote string) int {
		req := httptest.NewRequest("GET", "/v1/ch/chan_v6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0/presence", nil)
		req.RemoteAddr = remote
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w.Code
	}
	if code := get("[2001:db8:1:2::1]:5000"); code != http.StatusOK {
		t.Fatalf("first request = %d, want 200", code)
	}
	for i := 2; i < 6; i++ {
		remote := fmt.Sprintf("[2001:db8:1:2::%x]:5000", i)
		if code := get(remote); code != http.StatusTooManyRequests {
			t.Fatalf("%s escaped its /64's bucket: %d", remote, code)
		}
	}
	if code := get("[2001:db8:1:3::1]:5000"); code != http.StatusOK {
		t.Fatalf("another /64 throttled: %d", code)
	}
}
