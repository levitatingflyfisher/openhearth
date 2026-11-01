// Package store defines the relay's storage boundary.
//
// Design rules (BUILD-SPEC §5.4):
//   - Every write carries a TTL — no TTL-less write path exists in this
//     interface. TTLs are either caller-supplied (invites, presence, pinned
//     bulletin, replay guard) or fixed policy from Limits (mailbox, ring, seq).
//   - The store holds opaque ciphertext blobs only. It never parses them.
//   - All mutating invite operations are atomic (open→joined flip, proof
//     pinning, grant delete-after-retrieval).
package store

import (
	"context"
	"errors"
	"time"
)

// Sentinel errors. Handlers map these to bare HTTP status codes.
var (
	ErrNotFound = errors.New("store: not found")      // unknown or expired
	ErrGone     = errors.New("store: gone")           // invite already consumed
	ErrConflict = errors.New("store: already exists") // invite id collision
	ErrFull     = errors.New("store: full")           // mailbox depth / pinned cap
	ErrProof    = errors.New("store: proof mismatch") // pinned proof does not match
	// ErrOutOfMemory: the store is at its memory ceiling and refuses
	// writes (Redis maxmemory under noeviction). Nothing was written.
	ErrOutOfMemory = errors.New("store: out of memory")
)

// Limits are relay-wide storage policy constants (BUILD-SPEC §4, §5.4).
type Limits struct {
	MailboxDepth int           // max blobs per mailbox (spec: 200)
	MailboxTTL   time.Duration // rolling list TTL, refreshed on push (spec: 30d)
	RingSize     int           // unpinned bulletin ring size (spec: 8)
	RingTTL      time.Duration // sliding TTL for ring + seq counter (spec: 60d)
	PinCap       int           // max live pinned entries per channel (spec: 16)

	// Storage bounds against anonymous filling. Zero turns each off.
	//
	// MailboxFreshTTL: the TTL of a mailbox its owner has never drained.
	// Anyone may post to any mailbox id, so a mailbox nobody drains keeps
	// its mail only this long. A drain (a signed request) marks the
	// mailbox as owned for MailboxTTL, and pushes then get MailboxTTL.
	MailboxFreshTTL time.Duration
	// MaxFreshMailboxes: how many never-drained mailboxes may live at
	// once. A push that would open one more is ErrFull. Owned mailboxes
	// are never refused by it.
	MaxFreshMailboxes int
	// MaxChannels: how many channels (bulletin or presence) may live at
	// once. A write that would open one more is ErrFull.
	MaxChannels int
	// ChannelFreshTTL: how long a channel holds its place in MaxChannels
	// until a second writer (a second presence slot) shows up. The ring
	// and its entries keep their own TTLs; only the place is short.
	ChannelFreshTTL time.Duration
}

// Opener decides whether a write may open a new mailbox or channel, or
// own a mailbox: the relay's daily cap per address. Take spends one
// opening and reports whether there was one; Refund gives back a Take
// that opened nothing. The store never learns whose openings they are.
type Opener interface {
	Take() bool
	Refund()
}

type openerKey struct{}

// WithOpener returns ctx carrying o. A store asks it at the moment a write
// would open something; without one, opening is not limited.
func WithOpener(ctx context.Context, o Opener) context.Context {
	return context.WithValue(ctx, openerKey{}, o)
}

// openerFrom returns the Opener in ctx, or one that always allows.
func openerFrom(ctx context.Context) Opener {
	if o, ok := ctx.Value(openerKey{}).(Opener); ok && o != nil {
		return o
	}
	return unlimited{}
}

type unlimited struct{}

func (unlimited) Take() bool { return true }
func (unlimited) Refund()    {}

// DefaultLimits returns the BUILD-SPEC values.
func DefaultLimits() Limits {
	return Limits{
		MailboxDepth: 200,
		MailboxTTL:   30 * 24 * time.Hour,
		RingSize:     8,
		RingTTL:      60 * 24 * time.Hour,
		PinCap:       16,

		MailboxFreshTTL:   72 * time.Hour,
		MaxFreshMailboxes: 20000,
		MaxChannels:       20000,
		ChannelFreshTTL:   72 * time.Hour,
	}
}

// PresenceSlot is one live (unexpired) presence blob.
type PresenceSlot struct {
	SlotID    string
	Blob      []byte
	ExpiresAt time.Time
}

// BulletinEntry is one bulletin item. ExpiresAt is zero for unpinned
// (ring-lifetime) entries and set for pinned entries.
type BulletinEntry struct {
	Seq       uint64
	Blob      []byte
	Pinned    bool
	ExpiresAt time.Time
}

// Store is the relay's entire persistence surface.
//
// Proof-pinning note: the server never learns the invite token t, so it holds
// no reference value for fetchProof/grantProof (BUILD-SPEC §3.5 registers only
// inviteId at create). Verification is therefore first-use pinning: the first
// proof presented on a gated operation is pinned atomically; every later call
// must present the identical proof. FetchJoin and PutGrant share one pin (the
// spec uses fetchProof for both); TakeGrant pins grantProof separately.
// Confidentiality never rests on the pin — join blobs are secretbox(k_i),
// grant blobs are sealed to the joiner's box_pk.
type Store interface {
	// CreateInvite registers an invite id (state open) with the given TTL.
	// Returns the absolute expiry. ErrConflict if the id already exists.
	CreateInvite(ctx context.Context, id string, ttl time.Duration) (time.Time, error)
	// JoinInvite atomically flips open→joined and stores the join blob.
	// ErrGone if already joined; ErrNotFound if unknown/expired.
	JoinInvite(ctx context.Context, id string, blob []byte) error
	// FetchJoin returns the join blob, gated on the pinned fetch proof.
	// ErrNotFound if unknown/expired/not-yet-joined; ErrProof on mismatch.
	FetchJoin(ctx context.Context, id, proof string) ([]byte, error)
	// PutGrant stores the grant blob, gated on the same fetch-proof pin.
	PutGrant(ctx context.Context, id, proof string, blob []byte) error
	// TakeGrant returns the grant blob and deletes it (delete-after-retrieval),
	// gated on the pinned grant proof. ErrNotFound once taken.
	TakeGrant(ctx context.Context, id, proof string) ([]byte, error)

	// MailboxPush appends a blob (FIFO) and refreshes the rolling TTL:
	// MailboxTTL once the owner has drained the mailbox, MailboxFreshTTL
	// before. ErrFull at Limits.MailboxDepth, or when the push would open
	// a never-drained mailbox past Limits.MaxFreshMailboxes.
	MailboxPush(ctx context.Context, mailboxID string, blob []byte) error
	// MailboxDrain atomically returns all blobs in FIFO order and deletes
	// them: returned == deleted, even under concurrent drains.
	// An empty/unknown mailbox drains to an empty slice, nil error.
	// Draining marks the mailbox as owned for MailboxTTL.
	MailboxDrain(ctx context.Context, mailboxID string) ([][]byte, error)

	// ReplayCheck records key with ttl if unseen and reports true ("fresh").
	// A key seen within its TTL reports false.
	ReplayCheck(ctx context.Context, key string, ttl time.Duration) (bool, error)

	// PresenceSet stores/overwrites one slot blob with its own TTL
	// (overwrite = status update/extend). ErrFull when it would open a
	// channel past Limits.MaxChannels (as BulletinAppend).
	PresenceSet(ctx context.Context, channelID, slotID string, blob []byte, ttl time.Duration) error
	// PresenceList returns all unexpired slots for a channel.
	PresenceList(ctx context.Context, channelID string) ([]PresenceSlot, error)

	// BulletinAppend stores a bulletin blob and returns the server-assigned
	// monotonic per-channel seq. Unpinned entries enter the ring (oldest
	// evicted past Limits.RingSize; ring + seq share the sliding RingTTL).
	// Pinned entries carry their own pinTTL, are never ring-evicted, and are
	// capped at Limits.PinCap live entries per channel (ErrFull beyond).
	// writer is an opaque id for the writing member (the app derives a
	// per-epoch bulletin writer id, unlike its presence slot id), or ""
	// when the client sent none; a second id confirms the channel, as a
	// second presence slot does (Limits.ChannelFreshTTL).
	BulletinAppend(ctx context.Context, channelID, writer string, blob []byte, pinned bool, pinTTL time.Duration) (uint64, error)
	// BulletinList returns all live entries with seq > afterSeq, ordered by seq.
	BulletinList(ctx context.Context, channelID string, afterSeq uint64) ([]BulletinEntry, error)
}
