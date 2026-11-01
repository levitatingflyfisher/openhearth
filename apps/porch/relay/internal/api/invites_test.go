package api_test

import (
	"bytes"
	"net/http"
	"sync"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

func TestInviteCreate(t *testing.T) {
	rl := newRelay(t)
	w := rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 72})
	wantStatus(t, w, http.StatusCreated)
	body := decodeBody[struct {
		ExpiresAt int64 `json:"expiresAt"`
	}](t, w)
	wantExp := rl.clk.Now().Add(72 * time.Hour).Unix()
	if body.ExpiresAt != wantExp {
		t.Fatalf("expiresAt = %d, want %d", body.ExpiresAt, wantExp)
	}

	// Duplicate id → 409, empty error body.
	w = rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 1})
	wantStatus(t, w, http.StatusConflict)
	wantEmptyErrorBody(t, w)
}

func TestInviteCreateValidation(t *testing.T) {
	rl := newRelay(t)
	cases := []map[string]any{
		{"inviteId": testInvite},                               // missing ttl
		{"inviteId": testInvite, "ttlHours": 0},                // zero ttl
		{"inviteId": testInvite, "ttlHours": 73},               // above spec max
		{"inviteId": testInvite, "ttlHours": -1},               //
		{"ttlHours": 24},                                       // missing id
		{"inviteId": "short", "ttlHours": 24},                  // id too short
		{"inviteId": "has spaces here padpad", "ttlHours": 24}, // bad charset
		{"inviteId": testInvite, "ttlHours": 24, "x": 1},       // unknown field
	}
	for i, c := range cases {
		w := rl.do(t, "POST", "/v1/invites", c)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("case %d (%v): status %d, want 400", i, c, w.Code)
		}
		wantEmptyErrorBody(t, w)
	}
	// Garbage body.
	w := rl.do(t, "POST", "/v1/invites", []byte("{not json"))
	wantStatus(t, w, http.StatusBadRequest)
}

func TestInviteJoinLifecycle(t *testing.T) {
	rl := newRelay(t)
	wantStatus(t, rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 72}), http.StatusCreated)

	// Unknown invite → 404.
	w := rl.do(t, "POST", "/v1/invites/"+testInvite2+"/join", map[string]any{"blob": []byte("x")})
	wantStatus(t, w, http.StatusNotFound)

	// Join → 204, atomic open→joined.
	joinBlob := []byte{0x01, 0x02, 0xfe, 0x00, '"'}
	w = rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": joinBlob})
	wantStatus(t, w, http.StatusNoContent)

	// Second taker → 410 (one-time consumption).
	w = rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": []byte("second")})
	wantStatus(t, w, http.StatusGone)
	wantEmptyErrorBody(t, w)

	// Proof-gated fetch: absent proof → 404, then first use pins.
	w = rl.do(t, "GET", "/v1/invites/"+testInvite+"/join", nil)
	wantStatus(t, w, http.StatusNotFound)
	w = rl.do(t, "GET", "/v1/invites/"+testInvite+"/join?proof=fetchproof_aaaaaaaaaa", nil)
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blob []byte `json:"blob"`
	}](t, w)
	if !bytes.Equal(got.Blob, joinBlob) {
		t.Fatalf("join blob = %x, want %x", got.Blob, joinBlob)
	}
	// Wrong proof after pin → 404.
	w = rl.do(t, "GET", "/v1/invites/"+testInvite+"/join?proof=fetchproof_bbbbbbbbbb", nil)
	wantStatus(t, w, http.StatusNotFound)
}

func TestInviteJoinBlobCaps(t *testing.T) {
	rl := newRelay(t)
	wantStatus(t, rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 72}), http.StatusCreated)

	// >8 KiB join blob → 413.
	w := rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": make([]byte, 8<<10+1)})
	wantStatus(t, w, http.StatusRequestEntityTooLarge)

	// Empty blob → 400.
	w = rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": []byte{}})
	wantStatus(t, w, http.StatusBadRequest)
}

func TestInviteGrantFlow(t *testing.T) {
	rl := newRelay(t)
	wantStatus(t, rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 72}), http.StatusCreated)
	wantStatus(t, rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": []byte("intro")}), http.StatusNoContent)

	const fetchProof = "fetchproof_aaaaaaaaaa"
	const grantProof = "grantproof_aaaaaaaaaa"

	// Fetch join (pins fetchProof).
	wantStatus(t, rl.do(t, "GET", "/v1/invites/"+testInvite+"/join?proof="+fetchProof, nil), http.StatusOK)

	// Grant with a different proof than the pinned one → 404.
	w := rl.do(t, "POST", "/v1/invites/"+testInvite+"/grant",
		map[string]any{"proof": "fetchproof_bbbbbbbbbb", "blob": []byte("g")})
	wantStatus(t, w, http.StatusNotFound)

	// Grant with pinned proof → 204.
	grantBlob := []byte{9, 9, 9, 0, 0xff}
	w = rl.do(t, "POST", "/v1/invites/"+testInvite+"/grant",
		map[string]any{"proof": fetchProof, "blob": grantBlob})
	wantStatus(t, w, http.StatusNoContent)

	// >16 KiB grant blob → 413.
	w = rl.do(t, "POST", "/v1/invites/"+testInvite+"/grant",
		map[string]any{"proof": fetchProof, "blob": make([]byte, 16<<10+1)})
	wantStatus(t, w, http.StatusRequestEntityTooLarge)

	// Bob retrieves the grant (pins grantProof) — then it is deleted.
	w = rl.do(t, "GET", "/v1/invites/"+testInvite+"/grant?proof="+grantProof, nil)
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[struct {
		Blob []byte `json:"blob"`
	}](t, w)
	if !bytes.Equal(got.Blob, grantBlob) {
		t.Fatalf("grant blob = %x, want %x", got.Blob, grantBlob)
	}
	w = rl.do(t, "GET", "/v1/invites/"+testInvite+"/grant?proof="+grantProof, nil)
	wantStatus(t, w, http.StatusNotFound) // delete-after-retrieval
}

func TestInviteExpiryEndToEnd(t *testing.T) {
	rl := newRelay(t)
	wantStatus(t, rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 1}), http.StatusCreated)
	rl.clk.Advance(61 * time.Minute)
	w := rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": []byte("late")})
	wantStatus(t, w, http.StatusNotFound)
}

func TestInviteConcurrentJoinsExactlyOne204(t *testing.T) {
	rl := newRelay(t)
	wantStatus(t, rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": testInvite, "ttlHours": 72}), http.StatusCreated)

	const n = 32
	codes := make([]int, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := rl.do(t, "POST", "/v1/invites/"+testInvite+"/join", map[string]any{"blob": []byte{byte(i)}})
			codes[i] = w.Code
		}(i)
	}
	wg.Wait()
	got204, got410 := 0, 0
	for _, c := range codes {
		switch c {
		case http.StatusNoContent:
			got204++
		case http.StatusGone:
			got410++
		default:
			t.Fatalf("unexpected status %d in join race", c)
		}
	}
	if got204 != 1 || got410 != n-1 {
		t.Fatalf("join race: %d×204 and %d×410, want 1 and %d", got204, got410, n-1)
	}
}

func TestInviteCreateRateLimit(t *testing.T) {
	rates := generousRates()
	rates.InviteCreate = api.RateRule{Burst: 3, PerSec: 0.0001}
	rl := newRelayWith(t, store.DefaultLimits(), rates)

	ids := []string{
		"inv_ratelimit_aaaaaaa0", "inv_ratelimit_bbbbbbb0",
		"inv_ratelimit_ccccccc0", "inv_ratelimit_ddddddd0",
	}
	for i, id := range ids[:3] {
		w := rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": id, "ttlHours": 24})
		if w.Code != http.StatusCreated {
			t.Fatalf("create %d within limit: %d", i, w.Code)
		}
	}
	w := rl.do(t, "POST", "/v1/invites", map[string]any{"inviteId": ids[3], "ttlHours": 24})
	wantStatus(t, w, http.StatusTooManyRequests)
	wantEmptyErrorBody(t, w)

	// A different IP is unaffected.
	w = rl.doFrom(t, "POST", "/v1/invites", map[string]any{"inviteId": ids[3], "ttlHours": 24}, "198.51.100.7:1234")
	wantStatus(t, w, http.StatusCreated)
}

func TestInvitePathIDValidation(t *testing.T) {
	rl := newRelay(t)
	// Too-short / invalid path ids are 404 — the id space is capability-shaped.
	w := rl.do(t, "POST", "/v1/invites/tiny/join", map[string]any{"blob": []byte("x")})
	wantStatus(t, w, http.StatusNotFound)
	w = rl.do(t, "GET", "/v1/invites/in!valid!id!!!!!!!!!/join?proof=fetchproof_aaaaaaaaaa", nil)
	wantStatus(t, w, http.StatusNotFound)
}
