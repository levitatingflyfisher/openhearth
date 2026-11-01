// Package api is the Porch relay's entire HTTP surface (BUILD-SPEC §4):
// twelve endpoints, two auth mechanisms (knowledge capabilities + one
// stateless drain signature), per-IP token buckets, hard size caps.
//
// Structural privacy rules enforced here:
//   - ZERO logging calls anywhere in this package (CI-greped by privacy_test).
//   - Errors are bare status codes — no bodies, no echoes.
//   - Channel-plane handlers never read identity-bearing request state.
//   - Unknown JSON fields are rejected: nothing identity-shaped can ride in.
package api

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"

	"porch/relay/internal/store"
)

// Size caps (BUILD-SPEC §4). Tunable constants; tests assert enforcement.
const (
	maxJoinBlob     = 8 << 10  // join intro blob ≤8 KiB
	maxGrantBlob    = 16 << 10 // grant bundle ≤16 KiB
	maxMailboxBlob  = 8 << 10  // sealed rotation grant ≤8 KiB
	maxPresenceBlob = 1 << 10  // presence envelope ≤1 KiB
	maxBulletinBlob = 8 << 10  // bulletin envelope ≤8 KiB
	maxPresenceTTL  = 14700    // seconds (≈4 h 5 m)
	maxPinnedTTL    = 259200   // seconds (72 h)
	maxInviteHours  = 72
)

// Config wires the relay together. Zero-value Rates gets DefaultRateRules;
// nil Now gets time.Now.
type Config struct {
	Store store.Store
	Now   func() time.Time
	Rates RateRules
	// TrustForwarded uses the LAST X-Forwarded-For hop as the client IP for
	// rate limiting — the hop the trusted terminator itself appended from the
	// TCP connection. Every hop left of it arrived inside the client's own
	// request and is attacker-chosen, so keying on any earlier hop would let
	// a client mint a fresh bucket per request. Enable ONLY behind exactly
	// one trusted terminator (the docker-compose Caddy). Never affects
	// routing or storage.
	TrustForwarded bool
}

type server struct {
	st             store.Store
	now            func() time.Time
	rates          RateRules
	lim            *limiter
	trustForwarded bool
}

// New builds the relay handler.
func New(cfg Config) http.Handler {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Rates == (RateRules{}) {
		cfg.Rates = DefaultRateRules()
	}
	s := &server{
		st:             cfg.Store,
		now:            cfg.Now,
		rates:          cfg.Rates,
		lim:            newLimiter(cfg.Now),
		trustForwarded: cfg.TrustForwarded,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/invites", s.limited(s.rates.InviteCreate, "inv-create", s.createInvite))
	mux.HandleFunc("POST /v1/invites/{id}/join", s.limited(s.rates.ChannelWrite, "write", s.joinInvite))
	mux.HandleFunc("GET /v1/invites/{id}/join", s.limited(s.rates.Read, "read", s.fetchJoin))
	mux.HandleFunc("POST /v1/invites/{id}/grant", s.limited(s.rates.ChannelWrite, "write", s.putGrant))
	mux.HandleFunc("GET /v1/invites/{id}/grant", s.limited(s.rates.Read, "read", s.takeGrant))
	mux.HandleFunc("POST /v1/mailbox/{id}", s.limited(s.rates.MailboxPost, "mbox", s.mailboxPost))
	mux.HandleFunc("POST /v1/mailbox/{id}/drain", s.limited(s.rates.Drain, "drain", s.mailboxDrain))
	mux.HandleFunc("POST /v1/ch/{id}/presence", s.limited(s.rates.ChannelWrite, "write", s.presencePost))
	mux.HandleFunc("GET /v1/ch/{id}/presence", s.limited(s.rates.Read, "read", s.presenceGet))
	mux.HandleFunc("POST /v1/ch/{id}/bulletin", s.limited(s.rates.ChannelWrite, "write", s.bulletinPost))
	mux.HandleFunc("GET /v1/ch/{id}/bulletin", s.limited(s.rates.Read, "read", s.bulletinGet))
	mux.HandleFunc("GET /v1/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	return recoverPanics(mux)
}

// recoverPanics converts a handler panic into a bare 500 — silently, like
// everything else. net/http would otherwise log it.
func recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil && rec != http.ErrAbortHandler {
				w.WriteHeader(http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// limited wraps a handler with one rate-limit bucket, and hands the store
// the caller's daily openings (RateRules.Open) through the context.
func (s *server) limited(rule RateRule, bucket string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ip := s.clientIP(r)
		if !s.lim.allow(ip, bucket, rule) {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		if s.rates.Open.Burst > 0 {
			r = r.WithContext(store.WithOpener(r.Context(),
				opener{lim: s.lim, ip: ip, rule: s.rates.Open}))
		}
		next(w, r)
	}
}

// opener spends one caller's openings from its "open" bucket, keyed like
// every other bucket (an IPv6 address by its /64). The store sees only
// Take and Refund, never the address.
type opener struct {
	lim  *limiter
	ip   string
	rule RateRule
}

func (o opener) Take() bool { return o.lim.allow(o.ip, "open", o.rule) }
func (o opener) Refund()    { o.lim.refund(o.ip, "open", o.rule) }

// clientIP is used for RATE LIMITING ONLY — it is never stored, never keyed
// to any blob, never logged (there are no logs).
//
// With trustForwarded on, the key is the LAST X-Forwarded-For hop: the one
// hop appended by the single trusted terminator in front of us, taken from
// the actual TCP connection. The leftmost hops are client-supplied bytes —
// keying on them would let an attacker forge a new IP per request and never
// exhaust a bucket. If the header is missing or malformed, fall back to the
// direct peer (fail toward throttling the terminator, never toward a forged
// fresh bucket).
func (s *server) clientIP(r *http.Request) string {
	if s.trustForwarded {
		xff := r.Header.Get("X-Forwarded-For")
		if i := strings.LastIndexByte(xff, ','); i >= 0 {
			xff = xff[i+1:]
		}
		if ip := strings.TrimSpace(xff); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// --- shared helpers ---

const idAlphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"

// validID accepts capability-shaped identifiers: base64url charset,
// 16–64 chars (inviteId=22, slotId=22, mailboxId/channelId=43).
func validID(s string) bool {
	if len(s) < 16 || len(s) > 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !strings.ContainsRune(idAlphabet, rune(s[i])) {
			return false
		}
	}
	return true
}

// validProof accepts proof strings (base64url of 32-byte hashes → 43 chars,
// but only shape is checked; proofs are pinned, not verified).
func validProof(s string) bool {
	if len(s) < 16 || len(s) > 128 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !strings.ContainsRune(idAlphabet, rune(s[i])) {
			return false
		}
	}
	return true
}

// decodeJSON reads a size-capped, strict JSON body. On failure it writes the
// status itself (413 for size, 400 otherwise) and returns false.
func decodeJSON[T any](w http.ResponseWriter, r *http.Request, maxBytes int64) (T, bool) {
	var v T
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&v); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			w.WriteHeader(http.StatusRequestEntityTooLarge)
		} else {
			w.WriteHeader(http.StatusBadRequest)
		}
		return v, false
	}
	return v, true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// Encode errors after WriteHeader are unreportable (and unlogged, by
	// design); the values marshaled here are relay-constructed and total.
	_ = json.NewEncoder(w).Encode(v)
}

// storeErrStatus maps store sentinels to bare statuses. ErrProof maps to 404:
// the relay does not reveal whether a capability exists to a caller who
// cannot prove knowledge of it.
func storeErrStatus(err error) int {
	switch {
	case errors.Is(err, store.ErrNotFound), errors.Is(err, store.ErrProof):
		return http.StatusNotFound
	case errors.Is(err, store.ErrGone):
		return http.StatusGone
	case errors.Is(err, store.ErrConflict):
		return http.StatusConflict
	case errors.Is(err, store.ErrFull):
		return http.StatusTooManyRequests
	case errors.Is(err, store.ErrOutOfMemory):
		// The store is at its memory ceiling and refuses writes by design
		// (noeviction). 507 names that; it is a 5xx, so clients keep the
		// write and try again later.
		return http.StatusInsufficientStorage
	default:
		return http.StatusInternalServerError
	}
}
