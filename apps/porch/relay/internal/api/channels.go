package api

// Channel plane (BUILD-SPEC §1.2, §4 rows 8–11). Addressed by
// channelId = KDF(groupKey): knowledge of the capability IS membership
// proof. No user auth exists on these paths — this file deliberately never
// touches request headers, cookies, or the peer address, and privacy_test
// asserts that at the source level. The rate-limit middleware (router.go)
// is the only code that sees the client address, for limiting only.

import (
	"net/http"
	"sort"
	"strconv"
	"time"
)

type presencePostReq struct {
	SlotID string `json:"slotId"`
	Blob   []byte `json:"blob"`
	TTLSec int64  `json:"ttlSec"`
}

func (s *server) presencePost(w http.ResponseWriter, r *http.Request) {
	ch := r.PathValue("id")
	if !validID(ch) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	req, ok := decodeJSON[presencePostReq](w, r, maxPresenceBlob*4/3+1024)
	if !ok {
		return
	}
	if !validID(req.SlotID) || req.TTLSec < 1 || req.TTLSec > maxPresenceTTL || len(req.Blob) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if len(req.Blob) > maxPresenceBlob {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	// Overwrite = status update / extend; expiry is native TTL, never soft.
	if err := s.st.PresenceSet(r.Context(), ch, req.SlotID, req.Blob, time.Duration(req.TTLSec)*time.Second); err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type presenceSlotOut struct {
	SlotID    string `json:"slotId"`
	Blob      []byte `json:"blob"`
	ExpiresAt int64  `json:"expiresAt"`
}

func (s *server) presenceGet(w http.ResponseWriter, r *http.Request) {
	ch := r.PathValue("id")
	if !validID(ch) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	slots, err := s.st.PresenceList(r.Context(), ch)
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	out := make([]presenceSlotOut, 0, len(slots))
	for _, sl := range slots {
		out = append(out, presenceSlotOut{SlotID: sl.SlotID, Blob: sl.Blob, ExpiresAt: sl.ExpiresAt.Unix()})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotID < out[j].SlotID })
	writeJSON(w, http.StatusOK, map[string][]presenceSlotOut{"slots": out})
}

// SlotID is optional: an opaque id for the writing member in this epoch
// (the app sends a bulletin writer id that differs from its presence slot
// id). The relay keeps it only to tell a second writer from the first, so
// a channel written only by bulletin can be confirmed (store.Limits
// ChannelFreshTTL); it is never stored with the entry.
type bulletinPostReq struct {
	SlotID string `json:"slotId"`
	Blob   []byte `json:"blob"`
	Pinned bool   `json:"pinned"`
	TTLSec int64  `json:"ttlSec"`
}

func (s *server) bulletinPost(w http.ResponseWriter, r *http.Request) {
	ch := r.PathValue("id")
	if !validID(ch) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	req, ok := decodeJSON[bulletinPostReq](w, r, maxBulletinBlob*4/3+1024)
	if !ok {
		return
	}
	if len(req.Blob) == 0 || (req.SlotID != "" && !validID(req.SlotID)) {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if len(req.Blob) > maxBulletinBlob {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	// ttlSec is pinned-only (spec §4 row 10): pinned entries carry their own
	// TTL ≤72 h; unpinned entries live on the ring's sliding TTL.
	if req.Pinned && (req.TTLSec < 1 || req.TTLSec > maxPinnedTTL) {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if !req.Pinned && req.TTLSec != 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	seq, err := s.st.BulletinAppend(r.Context(), ch, req.SlotID, req.Blob, req.Pinned, time.Duration(req.TTLSec)*time.Second)
	if err != nil {
		w.WriteHeader(storeErrStatus(err)) // 429 at pin cap
		return
	}
	writeJSON(w, http.StatusOK, map[string]uint64{"seq": seq})
}

type bulletinEntryOut struct {
	Seq       uint64 `json:"seq"`
	Blob      []byte `json:"blob"`
	Pinned    bool   `json:"pinned"`
	ExpiresAt int64  `json:"expiresAt,omitempty"`
}

func (s *server) bulletinGet(w http.ResponseWriter, r *http.Request) {
	ch := r.PathValue("id")
	if !validID(ch) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	var afterSeq uint64
	if raw := r.URL.Query().Get("afterSeq"); raw != "" {
		n, err := strconv.ParseUint(raw, 10, 64)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		afterSeq = n
	}
	entries, err := s.st.BulletinList(r.Context(), ch, afterSeq)
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	out := make([]bulletinEntryOut, 0, len(entries))
	for _, e := range entries {
		o := bulletinEntryOut{Seq: e.Seq, Blob: e.Blob, Pinned: e.Pinned}
		if e.Pinned {
			o.ExpiresAt = e.ExpiresAt.Unix()
		}
		out = append(out, o)
	}
	writeJSON(w, http.StatusOK, map[string][]bulletinEntryOut{"entries": out})
}
