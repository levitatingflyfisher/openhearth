package api

import (
	"net/netip"
	"sync"
	"time"
)

// Per-IP token buckets, in-memory (BUILD-SPEC module map). Values are
// tunable constants; tests assert enforcement, not exact numbers — except
// invite creation, which the spec pins at ≤50/day/IP.

// RateRule is one token bucket shape.
type RateRule struct {
	Burst  float64 // bucket capacity
	PerSec float64 // refill rate, tokens per second
}

// RateRules holds one rule per endpoint class.
type RateRules struct {
	InviteCreate RateRule // POST /v1/invites            (spec: ≤50/day/IP)
	MailboxPost  RateRule // POST /v1/mailbox/{id}       (anonymous, capped hard)
	Drain        RateRule // POST /v1/mailbox/{id}/drain
	ChannelWrite RateRule // presence/bulletin/invite-join/grant writes
	Read         RateRule // all GETs (polling-friendly)
	// Open: opening a mailbox or channel, or owning a mailbox (its first
	// drain), across every endpoint. A Burst of 0 turns the cap off.
	Open RateRule
}

// DefaultOpensPerDay is how many mailboxes and channels one address (an
// IPv4 address or an IPv6 /64) may open a day. A family member opens one
// mailbox (their identity's, on its first drain) and one channel per
// group, plus one for each key rotation. A household of five setting up
// three groups on one day opens about 10 to 15; 50 leaves room for
// several households behind one shared address. One address can then
// hold at most 50 × 3 = 150 places that last ChannelFreshTTL, not 20,000
// that last 60 days.
const DefaultOpensPerDay = 50

// DefaultRateRules — every endpoint class is limited; nothing is unmetered.
func DefaultRateRules() RateRules {
	return RateRules{
		InviteCreate: RateRule{Burst: 50, PerSec: 50.0 / 86400.0},
		MailboxPost:  RateRule{Burst: 120, PerSec: 1},  // rotation fan-outs are ≤ group size
		Drain:        RateRule{Burst: 30, PerSec: 0.5}, // one poll cycle drains once
		ChannelWrite: RateRule{Burst: 120, PerSec: 2},
		Read:         RateRule{Burst: 600, PerSec: 10}, // 25 s polling × many groups
		Open:         OpensPerDay(DefaultOpensPerDay),
	}
}

// OpensPerDay is the Open rule for n openings a day: at most n at once,
// then one more every 24 h / n.
func OpensPerDay(n int) RateRule {
	return RateRule{Burst: float64(n), PerSec: float64(n) / 86400.0}
}

const (
	limiterPruneThreshold = 4096
	limiterIdleEviction   = 10 * time.Minute
)

// tokenBucket keeps the rule it was made under, so prune can tell when it
// has refilled to full.
type tokenBucket struct {
	tokens   float64
	lastSeen time.Time
	rule     RateRule
}

// refill brings the bucket up to now, never past the burst.
func (b *tokenBucket) refill(now time.Time) {
	b.tokens += now.Sub(b.lastSeen).Seconds() * b.rule.PerSec
	if b.tokens > b.rule.Burst {
		b.tokens = b.rule.Burst
	}
	b.lastSeen = now
}

type limiter struct {
	mu      sync.Mutex
	now     func() time.Time
	buckets map[string]*tokenBucket
}

func newLimiter(now func() time.Time) *limiter {
	return &limiter{now: now, buckets: map[string]*tokenBucket{}}
}

// rateKey is the bucket owner for a client address: an IPv4 address as
// is, an IPv6 address by its /64. One subscriber's network is a /64 in
// practice, and it holds 2^64 addresses: keyed per address, one client
// could mint a fresh bucket for every request. Anything that does not
// parse as an address is kept whole.
func rateKey(ip string) string {
	a, err := netip.ParseAddr(ip)
	if err != nil {
		return ip
	}
	a = a.Unmap()
	if a.Is4() {
		return a.String()
	}
	p, err := a.WithZone("").Prefix(64)
	if err != nil {
		return ip
	}
	return p.String()
}

// bucket returns the (ip, name) bucket refilled to now. Caller holds mu.
func (l *limiter) bucket(ip, name string, rule RateRule) *tokenBucket {
	now := l.now()
	key := rateKey(ip) + "\x00" + name
	b, ok := l.buckets[key]
	if !ok {
		if len(l.buckets) > limiterPruneThreshold {
			l.prune(now)
		}
		b = &tokenBucket{tokens: rule.Burst, lastSeen: now, rule: rule}
		l.buckets[key] = b
		return b
	}
	b.rule = rule
	b.refill(now)
	return b
}

// allow spends one token from the (ip, name) bucket under rule. IPv6
// addresses share their /64's bucket (rateKey).
func (l *limiter) allow(ip, name string, rule RateRule) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.bucket(ip, name, rule)
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// refund gives back one token to the (ip, name) bucket, never past the
// burst.
func (l *limiter) refund(ip, name string, rule RateRule) {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.bucket(ip, name, rule)
	b.tokens++
	if b.tokens > rule.Burst {
		b.tokens = rule.Burst
	}
}

// prune drops buckets idle past eviction that have refilled to full.
// Dropping a bucket that is not full would hand its owner a fresh burst:
// for a daily cap, ten idle minutes would reset the day. Caller holds mu.
func (l *limiter) prune(now time.Time) {
	for k, b := range l.buckets {
		if now.Sub(b.lastSeen) <= limiterIdleEviction {
			continue
		}
		b.refill(now)
		if b.tokens >= b.rule.Burst {
			delete(l.buckets, k)
		}
	}
}
