package api

// Mailbox plane (BUILD-SPEC §1.2, §4 rows 6–7).
//
// POST is UNAUTHENTICATED BY DESIGN: a live-compromised server must not be
// able to attribute rotation fan-outs as pk-level sender→recipient edges.
// Abuse is bounded by rate limits, the 8 KiB size cap, and the depth cap.
//
// Drain is the relay's only signature check — stateless, no session ever
// created (see sigauth.go).

import (
	"encoding/json"
	"errors"
	"net/http"
)

func (s *server) mailboxPost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !validID(id) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	req, ok := decodeJSON[blobReq](w, r, maxMailboxBlob*4/3+1024)
	if !ok {
		return
	}
	if len(req.Blob) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if len(req.Blob) > maxMailboxBlob {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	if err := s.st.MailboxPush(r.Context(), id, req.Blob); err != nil {
		w.WriteHeader(storeErrStatus(err)) // 429 mailbox full
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) mailboxDrain(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !validID(id) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	// The drain endpoint has exactly one failure mode short of a verified
	// signature: a bare 401. Unparseable auth material is an auth failure —
	// no separate 400 oracle exists here.
	var auth drainAuth
	r.Body = http.MaxBytesReader(w, r.Body, 1024)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&auth); err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	if err := verifyDrain(r.Context(), s.st, s.now(), id, auth); err != nil {
		if errors.Is(err, errDrainAuth) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		// The signature checked out, but the replay entry could not be
		// written (a full or failing store): refuse before any mail is
		// touched. The status says why; a stranger never gets this far.
		w.WriteHeader(storeErrStatus(err))
		return
	}
	blobs, err := s.st.MailboxDrain(r.Context(), id) // atomic: returned == deleted
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	if blobs == nil {
		blobs = [][]byte{}
	}
	writeJSON(w, http.StatusOK, map[string][][]byte{"blobs": blobs})
}
