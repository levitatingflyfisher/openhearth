package store

import (
	"context"
	"sync"
	"time"
)

// Mem is the in-memory Store. It is the reference implementation for the
// conformance suite and powers the whole unit suite (no external services).
// Expiry is lazy: every read/write path drops entries whose deadline has
// passed according to the injected clock.
type Mem struct {
	mu  sync.Mutex
	now func() time.Time
	lim Limits

	invites  map[string]*memInvite
	boxes    map[string]*memMailbox
	replay   map[string]time.Time // key → expiry
	presence map[string]map[string]memSlot
	rings    map[string]*memRing
	pins     map[string]map[uint64]memPin
	seqs     map[string]memSeq
	owned    map[string]time.Time // mailboxId → until: drained by its owner
	chans    map[string]time.Time // channelId → until: live channels (MaxChannels)
	writers  map[string]memWriter // channelId → which slots have written there
}

// memWriter is a channel's first writing slot (by presence, or named by a
// bulletin write), or confirmed once a second slot has written. It lives
// as long as the channel's place in chans.
type memWriter struct {
	first     string
	confirmed bool
	until     time.Time
}

type memInvite struct {
	expiresAt  time.Time
	joined     bool
	joinBlob   []byte
	grantBlob  []byte // nil once taken (delete-after-retrieval)
	fetchProof string // "" until pinned
	grantProof string
}

type memMailbox struct {
	expiresAt time.Time
	blobs     [][]byte
}

type memSlot struct {
	blob      []byte
	expiresAt time.Time
}

type memRing struct {
	expiresAt time.Time
	entries   []BulletinEntry // unpinned only, seq-ascending
}

type memPin struct {
	blob      []byte
	expiresAt time.Time
}

type memSeq struct {
	n         uint64
	expiresAt time.Time
}

// NewMem builds an empty in-memory store with an injectable clock.
func NewMem(lim Limits, now func() time.Time) *Mem {
	return &Mem{
		now:      now,
		lim:      lim,
		invites:  map[string]*memInvite{},
		boxes:    map[string]*memMailbox{},
		replay:   map[string]time.Time{},
		presence: map[string]map[string]memSlot{},
		rings:    map[string]*memRing{},
		pins:     map[string]map[uint64]memPin{},
		seqs:     map[string]memSeq{},
		owned:    map[string]time.Time{},
		chans:    map[string]time.Time{},
		writers:  map[string]memWriter{},
	}
}

var _ Store = (*Mem)(nil)

// --- invites ---

// liveInvite returns the invite if present and unexpired, pruning otherwise.
// Caller holds mu.
func (m *Mem) liveInvite(id string) *memInvite {
	inv, ok := m.invites[id]
	if !ok {
		return nil
	}
	if !m.now().Before(inv.expiresAt) {
		delete(m.invites, id)
		return nil
	}
	return inv
}

func (m *Mem) CreateInvite(_ context.Context, id string, ttl time.Duration) (time.Time, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.liveInvite(id) != nil {
		return time.Time{}, ErrConflict
	}
	exp := m.now().Add(ttl)
	m.invites[id] = &memInvite{expiresAt: exp}
	return exp, nil
}

func (m *Mem) JoinInvite(_ context.Context, id string, blob []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	inv := m.liveInvite(id)
	if inv == nil {
		return ErrNotFound
	}
	if inv.joined {
		return ErrGone
	}
	inv.joined = true
	inv.joinBlob = cloneBytes(blob)
	return nil
}

// pinProof enforces first-use pinning: pins proof if the slot is empty,
// otherwise requires equality. Caller holds mu.
func pinProof(slot *string, proof string) error {
	if *slot == "" {
		*slot = proof
		return nil
	}
	if *slot != proof {
		return ErrProof
	}
	return nil
}

func (m *Mem) FetchJoin(_ context.Context, id, proof string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	inv := m.liveInvite(id)
	if inv == nil || !inv.joined || inv.joinBlob == nil {
		return nil, ErrNotFound
	}
	if err := pinProof(&inv.fetchProof, proof); err != nil {
		return nil, err
	}
	return cloneBytes(inv.joinBlob), nil
}

func (m *Mem) PutGrant(_ context.Context, id, proof string, blob []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	inv := m.liveInvite(id)
	if inv == nil || !inv.joined {
		return ErrNotFound
	}
	if err := pinProof(&inv.fetchProof, proof); err != nil {
		return err
	}
	inv.grantBlob = cloneBytes(blob)
	return nil
}

func (m *Mem) TakeGrant(_ context.Context, id, proof string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	inv := m.liveInvite(id)
	if inv == nil || inv.grantBlob == nil {
		return nil, ErrNotFound
	}
	if err := pinProof(&inv.grantProof, proof); err != nil {
		return nil, err
	}
	blob := inv.grantBlob
	inv.grantBlob = nil // delete-after-retrieval; record kept for honest 404s
	return blob, nil
}

// --- mailbox ---

func (m *Mem) liveMailbox(id string) *memMailbox {
	mb, ok := m.boxes[id]
	if !ok {
		return nil
	}
	if !m.now().Before(mb.expiresAt) {
		delete(m.boxes, id)
		return nil
	}
	return mb
}

// isOwned reports whether the mailbox's owner has drained it within
// MailboxTTL. Caller holds mu.
func (m *Mem) isOwned(id string, now time.Time) bool {
	until, ok := m.owned[id]
	if !ok {
		return false
	}
	if !now.Before(until) {
		delete(m.owned, id)
		return false
	}
	return true
}

// freshMailboxes counts live mailboxes their owners have never drained,
// pruning expired ones. Caller holds mu.
func (m *Mem) freshMailboxes(now time.Time) int {
	n := 0
	for id, mb := range m.boxes {
		if !now.Before(mb.expiresAt) {
			delete(m.boxes, id)
			continue
		}
		if !m.isOwned(id, now) {
			n++
		}
	}
	return n
}

func (m *Mem) MailboxPush(ctx context.Context, mailboxID string, blob []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := m.now()
	owned := m.isOwned(mailboxID, now)
	mb := m.liveMailbox(mailboxID)
	if mb == nil {
		if !owned {
			// This push opens a never-drained mailbox.
			if m.lim.MaxFreshMailboxes > 0 &&
				m.freshMailboxes(now) >= m.lim.MaxFreshMailboxes {
				return ErrFull
			}
			if !openerFrom(ctx).Take() {
				return ErrFull
			}
		}
		mb = &memMailbox{}
		m.boxes[mailboxID] = mb
	}
	if len(mb.blobs) >= m.lim.MailboxDepth {
		return ErrFull
	}
	mb.blobs = append(mb.blobs, cloneBytes(blob))
	ttl := m.lim.MailboxTTL
	if !owned && m.lim.MailboxFreshTTL > 0 {
		ttl = m.lim.MailboxFreshTTL // nobody has drained it: short life
	}
	mb.expiresAt = now.Add(ttl) // rolling TTL refresh
	return nil
}

func (m *Mem) MailboxDrain(ctx context.Context, mailboxID string) ([][]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := m.now()
	if len(m.owned) > memPruneThreshold {
		for id, until := range m.owned {
			if !now.Before(until) {
				delete(m.owned, id)
			}
		}
	}
	// The owner drains: owned. Owning a mailbox it did not own counts as
	// an opening; without one the mail still comes back, unowned.
	if m.isOwned(mailboxID, now) || openerFrom(ctx).Take() {
		m.owned[mailboxID] = now.Add(m.lim.MailboxTTL)
	}
	mb := m.liveMailbox(mailboxID)
	if mb == nil {
		return nil, nil
	}
	blobs := mb.blobs
	delete(m.boxes, mailboxID) // atomic: returned == deleted
	return blobs, nil
}

// --- replay guard ---

func (m *Mem) ReplayCheck(_ context.Context, key string, ttl time.Duration) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if exp, ok := m.replay[key]; ok && m.now().Before(exp) {
		return false, nil
	}
	m.replay[key] = m.now().Add(ttl)
	return true, nil
}

// --- presence ---

// memPruneThreshold is the map size past which the bookkeeping maps (owned,
// chans) drop expired entries before growing further.
const memPruneThreshold = 4096

// openChannel records that channelID lives life more, and refuses
// (ErrFull) to open a new channel past Limits.MaxChannels or without an
// opening from the ctx's Opener. slot is the presence slot writing, or the
// slot a bulletin write names, or "" for a bulletin write that names none.
// Until a second slot has written, the place lasts at most
// Limits.ChannelFreshTTL. Caller holds mu.
func (m *Mem) openChannel(ctx context.Context, channelID string, life time.Duration, slot string) error {
	now := m.now()
	w, hasW := m.writers[channelID]
	if hasW && !now.Before(w.until) {
		delete(m.writers, channelID)
		w, hasW = memWriter{}, false
	}
	confirmed := hasW && (w.confirmed || (slot != "" && w.first != slot))
	if !confirmed && m.lim.ChannelFreshTTL > 0 && life > m.lim.ChannelFreshTTL {
		life = m.lim.ChannelFreshTTL
	}
	until := now.Add(life)
	if exp, ok := m.chans[channelID]; ok && now.Before(exp) {
		if until.After(exp) {
			m.chans[channelID] = until
		}
	} else {
		if m.lim.MaxChannels > 0 || len(m.chans) > memPruneThreshold {
			for id, exp := range m.chans {
				if !now.Before(exp) {
					delete(m.chans, id)
					delete(m.writers, id)
				}
			}
		}
		if m.lim.MaxChannels > 0 && len(m.chans) >= m.lim.MaxChannels {
			return ErrFull
		}
		if !openerFrom(ctx).Take() {
			return ErrFull
		}
		m.chans[channelID] = until
	}
	switch {
	case confirmed:
		w.confirmed = true
	case !hasW && slot != "":
		w.first = slot
	case !hasW:
		return nil // a bulletin write that names no writer: none to record
	}
	w.until = m.chans[channelID]
	m.writers[channelID] = w
	return nil
}

func (m *Mem) PresenceSet(ctx context.Context, channelID, slotID string, blob []byte, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.openChannel(ctx, channelID, ttl, slotID); err != nil {
		return err
	}
	ch, ok := m.presence[channelID]
	if !ok {
		ch = map[string]memSlot{}
		m.presence[channelID] = ch
	}
	ch[slotID] = memSlot{blob: cloneBytes(blob), expiresAt: m.now().Add(ttl)}
	return nil
}

func (m *Mem) PresenceList(_ context.Context, channelID string) ([]PresenceSlot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	ch := m.presence[channelID]
	now := m.now()
	out := []PresenceSlot{}
	for slotID, s := range ch {
		if !now.Before(s.expiresAt) {
			delete(ch, slotID) // structurally cannot exist after expiry
			continue
		}
		out = append(out, PresenceSlot{SlotID: slotID, Blob: cloneBytes(s.blob), ExpiresAt: s.expiresAt})
	}
	return out, nil
}

// --- bulletin ---

func (m *Mem) nextSeq(channelID string) uint64 {
	s := m.seqs[channelID]
	if !s.expiresAt.IsZero() && !m.now().Before(s.expiresAt) {
		s = memSeq{}
	}
	s.n++
	s.expiresAt = m.now().Add(m.lim.RingTTL) // sliding, like Redis INCR+EXPIRE
	m.seqs[channelID] = s
	return s.n
}

func (m *Mem) liveRing(channelID string) *memRing {
	r, ok := m.rings[channelID]
	if !ok {
		return nil
	}
	if !m.now().Before(r.expiresAt) {
		delete(m.rings, channelID)
		return nil
	}
	return r
}

// livePins prunes expired pinned entries and returns the channel's pin map.
// Caller holds mu.
func (m *Mem) livePins(channelID string) map[uint64]memPin {
	pins := m.pins[channelID]
	now := m.now()
	for seq, p := range pins {
		if !now.Before(p.expiresAt) {
			delete(pins, seq)
		}
	}
	return pins
}

func (m *Mem) BulletinAppend(ctx context.Context, channelID, writer string, blob []byte, pinned bool, pinTTL time.Duration) (uint64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	life := m.lim.RingTTL // the seq counter lives this long
	if pinned && pinTTL > life {
		life = pinTTL
	}
	if err := m.openChannel(ctx, channelID, life, writer); err != nil {
		return 0, err
	}
	if pinned {
		pins := m.livePins(channelID)
		if pins == nil {
			pins = map[uint64]memPin{}
			m.pins[channelID] = pins
		}
		if len(pins) >= m.lim.PinCap {
			return 0, ErrFull
		}
		seq := m.nextSeq(channelID)
		pins[seq] = memPin{blob: cloneBytes(blob), expiresAt: m.now().Add(pinTTL)}
		return seq, nil
	}
	seq := m.nextSeq(channelID)
	r := m.liveRing(channelID)
	if r == nil {
		r = &memRing{}
		m.rings[channelID] = r
	}
	r.entries = append(r.entries, BulletinEntry{Seq: seq, Blob: cloneBytes(blob)})
	if over := len(r.entries) - m.lim.RingSize; over > 0 {
		r.entries = r.entries[over:] // evict oldest unpinned only
	}
	r.expiresAt = m.now().Add(m.lim.RingTTL) // sliding
	return seq, nil
}

func (m *Mem) BulletinList(_ context.Context, channelID string, afterSeq uint64) ([]BulletinEntry, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := []BulletinEntry{}
	if r := m.liveRing(channelID); r != nil {
		for _, e := range r.entries {
			if e.Seq > afterSeq {
				out = append(out, BulletinEntry{Seq: e.Seq, Blob: cloneBytes(e.Blob)})
			}
		}
	}
	for seq, p := range m.livePins(channelID) {
		if seq > afterSeq {
			out = append(out, BulletinEntry{Seq: seq, Blob: cloneBytes(p.blob), Pinned: true, ExpiresAt: p.expiresAt})
		}
	}
	sortEntries(out)
	return out, nil
}

func sortEntries(es []BulletinEntry) {
	// Insertion sort: entry counts are ≤ RingSize+PinCap (24 at spec limits).
	for i := 1; i < len(es); i++ {
		for j := i; j > 0 && es[j].Seq < es[j-1].Seq; j-- {
			es[j], es[j-1] = es[j-1], es[j]
		}
	}
}

func cloneBytes(b []byte) []byte {
	if b == nil {
		return nil
	}
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
