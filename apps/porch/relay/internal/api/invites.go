package api

// Invite endpoints (BUILD-SPEC §4 rows 1–5, §3.5). The server registers only
// inviteId — the token t never touches it. Join is an atomic one-time
// consumption; fetch/grant are proof-gated (first-use pinning, see
// store.Store docs); the grant blob is deleted after retrieval.

import (
	"net/http"
	"time"
)

type createInviteReq struct {
	InviteID string `json:"inviteId"`
	TTLHours int    `json:"ttlHours"`
}

func (s *server) createInvite(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeJSON[createInviteReq](w, r, 1024)
	if !ok {
		return
	}
	if !validID(req.InviteID) || req.TTLHours < 1 || req.TTLHours > maxInviteHours {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	expiresAt, err := s.st.CreateInvite(r.Context(), req.InviteID, time.Duration(req.TTLHours)*time.Hour)
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int64{"expiresAt": expiresAt.Unix()})
}

type blobReq struct {
	Blob []byte `json:"blob"`
}

func (s *server) joinInvite(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !validID(id) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	req, ok := decodeJSON[blobReq](w, r, maxJoinBlob*4/3+1024)
	if !ok {
		return
	}
	if len(req.Blob) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if len(req.Blob) > maxJoinBlob {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	if err := s.st.JoinInvite(r.Context(), id, req.Blob); err != nil {
		w.WriteHeader(storeErrStatus(err)) // 410 used, 404 unknown/expired
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) fetchJoin(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	proof := r.URL.Query().Get("proof")
	if !validID(id) || !validProof(proof) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	blob, err := s.st.FetchJoin(r.Context(), id, proof)
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	writeJSON(w, http.StatusOK, map[string][]byte{"blob": blob})
}

type grantReq struct {
	Proof string `json:"proof"`
	Blob  []byte `json:"blob"`
}

func (s *server) putGrant(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !validID(id) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	req, ok := decodeJSON[grantReq](w, r, maxGrantBlob*4/3+1024)
	if !ok {
		return
	}
	if !validProof(req.Proof) || len(req.Blob) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if len(req.Blob) > maxGrantBlob {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	if err := s.st.PutGrant(r.Context(), id, req.Proof, req.Blob); err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) takeGrant(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	proof := r.URL.Query().Get("proof")
	if !validID(id) || !validProof(proof) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	blob, err := s.st.TakeGrant(r.Context(), id, proof) // deleted after retrieval
	if err != nil {
		w.WriteHeader(storeErrStatus(err))
		return
	}
	writeJSON(w, http.StatusOK, map[string][]byte{"blob": blob})
}
