package api_test

import (
	"bytes"
	"net/http"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

type presenceResp struct {
	Slots []struct {
		SlotID    string `json:"slotId"`
		Blob      []byte `json:"blob"`
		ExpiresAt int64  `json:"expiresAt"`
	} `json:"slots"`
}

type bulletinResp struct {
	Entries []struct {
		Seq       uint64 `json:"seq"`
		Blob      []byte `json:"blob"`
		Pinned    bool   `json:"pinned"`
		ExpiresAt int64  `json:"expiresAt"`
	} `json:"entries"`
}

func postPresence(t *testing.T, rl *relay, ch, slot string, blob []byte, ttlSec int) *relay {
	t.Helper()
	w := rl.do(t, "POST", "/v1/ch/"+ch+"/presence", map[string]any{"slotId": slot, "blob": blob, "ttlSec": ttlSec})
	wantStatus(t, w, http.StatusNoContent)
	return rl
}

func TestPresencePublishFetchTTL(t *testing.T) {
	rl := newRelay(t)
	blob := []byte{0xde, 0xad, 0x00, '"'}
	postPresence(t, rl, testChannel, testSlot, blob, 3600)

	w := rl.do(t, "GET", "/v1/ch/"+testChannel+"/presence", nil)
	wantStatus(t, w, http.StatusOK)
	got := decodeBody[presenceResp](t, w)
	if len(got.Slots) != 1 {
		t.Fatalf("want 1 slot, got %d", len(got.Slots))
	}
	s := got.Slots[0]
	if s.SlotID != testSlot || !bytes.Equal(s.Blob, blob) {
		t.Fatalf("slot mismatch: %+v", s)
	}
	if want := rl.clk.Now().Add(3600 * time.Second).Unix(); s.ExpiresAt != want {
		t.Fatalf("expiresAt = %d, want %d", s.ExpiresAt, want)
	}

	// Overwrite = status update / extend (same slot, new blob, new TTL).
	blob2 := []byte("off-tombstone")
	postPresence(t, rl, testChannel, testSlot, blob2, 60)
	got = decodeBody[presenceResp](t, rl.do(t, "GET", "/v1/ch/"+testChannel+"/presence", nil))
	if len(got.Slots) != 1 || !bytes.Equal(got.Slots[0].Blob, blob2) {
		t.Fatalf("overwrite did not replace blob: %+v", got.Slots)
	}

	// TTL expiry: presence structurally cannot exist after expiry.
	rl.clk.Advance(61 * time.Second)
	got = decodeBody[presenceResp](t, rl.do(t, "GET", "/v1/ch/"+testChannel+"/presence", nil))
	if len(got.Slots) != 0 {
		t.Fatalf("expired slot still visible: %+v", got.Slots)
	}
	// Empty list marshals as [], never null.
	if body := rl.do(t, "GET", "/v1/ch/"+testChannel+"/presence", nil).Body.String(); !bytes.Contains([]byte(body), []byte(`"slots":[]`)) {
		t.Fatalf("empty presence = %q, want slots:[]", body)
	}
}

func TestPresenceValidation(t *testing.T) {
	rl := newRelay(t)
	base := "/v1/ch/" + testChannel + "/presence"
	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"ttl above spec max 14700", map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": 14701}, 400},
		{"zero ttl", map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": 0}, 400},
		{"negative ttl", map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": -5}, 400},
		{"missing slot", map[string]any{"blob": []byte("x"), "ttlSec": 60}, 400},
		{"bad slot charset", map[string]any{"slotId": "not a slot id!!!!!!", "blob": []byte("x"), "ttlSec": 60}, 400},
		{"empty blob", map[string]any{"slotId": testSlot, "blob": []byte{}, "ttlSec": 60}, 400},
		{"blob over 1KiB", map[string]any{"slotId": testSlot, "blob": make([]byte, 1<<10+1), "ttlSec": 60}, 413},
		{"unknown field (no identity smuggling)", map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": 60, "userId": "alice"}, 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := rl.do(t, "POST", base, tc.body)
			if w.Code != tc.want {
				t.Fatalf("status %d, want %d", w.Code, tc.want)
			}
			wantEmptyErrorBody(t, w)
		})
	}
	// Max valid TTL is accepted.
	w := rl.do(t, "POST", base, map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": 14700})
	wantStatus(t, w, http.StatusNoContent)
	// Invalid channel id in path → 404.
	w = rl.do(t, "GET", "/v1/ch/nope/presence", nil)
	wantStatus(t, w, http.StatusNotFound)
}

func TestChannelIsolation(t *testing.T) {
	rl := newRelay(t)
	other := "chan_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0"
	postPresence(t, rl, testChannel, testSlot, []byte("mine"), 600)
	got := decodeBody[presenceResp](t, rl.do(t, "GET", "/v1/ch/"+other+"/presence", nil))
	if len(got.Slots) != 0 {
		t.Fatalf("presence leaked across channels: %+v", got.Slots)
	}
}

func TestBulletinSeqRingAndPins(t *testing.T) {
	lim := store.DefaultLimits()
	lim.RingSize = 3
	rl := newRelayWith(t, lim, generousRates())
	base := "/v1/ch/" + testChannel + "/bulletin"

	// Server-assigned monotonic seq.
	for i := 1; i <= 2; i++ {
		w := rl.do(t, "POST", base, map[string]any{"blob": []byte{byte(i)}, "pinned": false})
		wantStatus(t, w, http.StatusOK)
		got := decodeBody[struct {
			Seq uint64 `json:"seq"`
		}](t, w)
		if got.Seq != uint64(i) {
			t.Fatalf("seq = %d, want %d", got.Seq, i)
		}
	}

	// A pinned escrow entry (own TTL), then flood the ring.
	w := rl.do(t, "POST", base, map[string]any{"blob": []byte("ESCROW"), "pinned": true, "ttlSec": 72 * 3600})
	wantStatus(t, w, http.StatusOK)
	pinSeq := decodeBody[struct {
		Seq uint64 `json:"seq"`
	}](t, w).Seq

	for i := 0; i < 5; i++ {
		wantStatus(t, rl.do(t, "POST", base, map[string]any{"blob": []byte{0x10 + byte(i)}, "pinned": false}), http.StatusOK)
	}

	got := decodeBody[bulletinResp](t, rl.do(t, "GET", base, nil))
	var pinnedSeen bool
	var unpinned []uint64
	for _, e := range got.Entries {
		if e.Pinned {
			pinnedSeen = true
			if e.Seq != pinSeq || !bytes.Equal(e.Blob, []byte("ESCROW")) {
				t.Fatalf("pinned entry corrupted: %+v", e)
			}
			if e.ExpiresAt == 0 {
				t.Fatal("pinned entry missing expiresAt")
			}
		} else {
			unpinned = append(unpinned, e.Seq)
			if e.ExpiresAt != 0 {
				t.Fatalf("unpinned entry carries expiresAt: %+v", e)
			}
		}
	}
	if !pinnedSeen {
		t.Fatal("pinned entry was ring-evicted")
	}
	if len(unpinned) != lim.RingSize {
		t.Fatalf("ring kept %d unpinned, want %d", len(unpinned), lim.RingSize)
	}
	// Ordered by seq, and only the newest survived.
	for i := 1; i < len(unpinned); i++ {
		if unpinned[i] <= unpinned[i-1] {
			t.Fatal("entries not seq-ordered")
		}
	}

	// afterSeq paging.
	got = decodeBody[bulletinResp](t, rl.do(t, "GET", base+"?afterSeq="+itoa(pinSeq), nil))
	for _, e := range got.Entries {
		if e.Seq <= pinSeq {
			t.Fatalf("afterSeq leak: %d", e.Seq)
		}
	}
	// Bad afterSeq → 400.
	wantStatus(t, rl.do(t, "GET", base+"?afterSeq=banana", nil), http.StatusBadRequest)

	// Pinned entries die by their own TTL.
	rl.clk.Advance(73 * time.Hour)
	got = decodeBody[bulletinResp](t, rl.do(t, "GET", base, nil))
	for _, e := range got.Entries {
		if e.Pinned {
			t.Fatalf("pinned entry survived its TTL: %+v", e)
		}
	}
}

func TestBulletinValidation(t *testing.T) {
	rl := newRelay(t)
	base := "/v1/ch/" + testChannel + "/bulletin"
	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"unpinned with ttl", map[string]any{"blob": []byte("x"), "pinned": false, "ttlSec": 60}, 400},
		{"pinned without ttl", map[string]any{"blob": []byte("x"), "pinned": true}, 400},
		{"pinned ttl above 72h", map[string]any{"blob": []byte("x"), "pinned": true, "ttlSec": 259201}, 400},
		{"empty blob", map[string]any{"blob": []byte{}, "pinned": false}, 400},
		{"blob over 8KiB", map[string]any{"blob": make([]byte, 8<<10+1), "pinned": false}, 413},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := rl.do(t, "POST", base, tc.body)
			if w.Code != tc.want {
				t.Fatalf("status %d, want %d", w.Code, tc.want)
			}
		})
	}
}

// A bulletin write names its writer by an opaque id. A second writer
// confirms the channel, so a channel used only for bulletins
// keeps its place past ChannelFreshTTL; one writer alone does not.
func TestBulletinSecondWriterConfirmsChannel(t *testing.T) {
	const otherSlot = "slot_bbbbbbbbbbbbbbbb0"
	const otherChannel = "chan_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0"
	for _, tc := range []struct {
		name      string
		second    string
		wantLater int
	}{
		{"two writers hold the place", otherSlot, http.StatusTooManyRequests},
		{"one writer twice does not", testSlot, http.StatusOK},
	} {
		t.Run(tc.name, func(t *testing.T) {
			lim := store.DefaultLimits()
			lim.MaxChannels = 1
			lim.ChannelFreshTTL = time.Hour
			rl := newRelayWith(t, lim, generousRates())
			base := "/v1/ch/" + testChannel + "/bulletin"
			wantStatus(t, rl.do(t, "POST", base, map[string]any{"slotId": testSlot, "blob": []byte("a"), "pinned": false}), http.StatusOK)
			wantStatus(t, rl.do(t, "POST", base, map[string]any{"slotId": tc.second, "blob": []byte("b"), "pinned": false}), http.StatusOK)
			rl.clk.Advance(2 * time.Hour) // past ChannelFreshTTL, inside RingTTL
			w := rl.do(t, "POST", "/v1/ch/"+otherChannel+"/bulletin", map[string]any{"slotId": testSlot, "blob": []byte("c"), "pinned": false})
			wantStatus(t, w, tc.wantLater)
		})
	}
}

func TestBulletinRejectsBadSlotID(t *testing.T) {
	rl := newRelay(t)
	base := "/v1/ch/" + testChannel + "/bulletin"
	wantStatus(t, rl.do(t, "POST", base, map[string]any{"slotId": "short", "blob": []byte("x"), "pinned": false}), http.StatusBadRequest)
}

func TestBulletinPinCap429(t *testing.T) {
	lim := store.DefaultLimits()
	lim.PinCap = 2
	rl := newRelayWith(t, lim, generousRates())
	base := "/v1/ch/" + testChannel + "/bulletin"
	for i := 0; i < 2; i++ {
		wantStatus(t, rl.do(t, "POST", base, map[string]any{"blob": []byte{byte(i)}, "pinned": true, "ttlSec": 3600}), http.StatusOK)
	}
	w := rl.do(t, "POST", base, map[string]any{"blob": []byte("over"), "pinned": true, "ttlSec": 3600})
	wantStatus(t, w, http.StatusTooManyRequests)
	// Expiry frees pin capacity.
	rl.clk.Advance(2 * time.Hour)
	wantStatus(t, rl.do(t, "POST", base, map[string]any{"blob": []byte("again"), "pinned": true, "ttlSec": 3600}), http.StatusOK)
}

func TestChannelWriteRateLimit(t *testing.T) {
	rates := generousRates()
	rates.ChannelWrite = api.RateRule{Burst: 2, PerSec: 0.0001}
	rl := newRelayWith(t, store.DefaultLimits(), rates)
	base := "/v1/ch/" + testChannel + "/presence"
	body := map[string]any{"slotId": testSlot, "blob": []byte("x"), "ttlSec": 60}
	wantStatus(t, rl.do(t, "POST", base, body), http.StatusNoContent)
	wantStatus(t, rl.do(t, "POST", base, body), http.StatusNoContent)
	wantStatus(t, rl.do(t, "POST", base, body), http.StatusTooManyRequests)
}

// Capability-only auth: a request carrying identity-shaped headers is served
// identically — the channel plane has no notion of who you are. (The
// structural source-level guarantee is asserted in privacy_test.go.)
func TestChannelIgnoresIdentityHeaders(t *testing.T) {
	rl := newRelay(t)
	postPresence(t, rl, testChannel, testSlot, []byte("hi"), 600)

	req := rl.doFrom(t, "GET", "/v1/ch/"+testChannel+"/presence", nil, testIP)
	plain := req.Body.String()

	w := rl.do2(t, "GET", "/v1/ch/"+testChannel+"/presence", nil, map[string]string{
		"Authorization": "Bearer sneaky",
		"Cookie":        "session=deadbeef",
		"X-User-Id":     "alice",
	})
	wantStatus(t, w, http.StatusOK)
	if w.Body.String() != plain {
		t.Fatal("identity headers changed a channel-plane response")
	}
}

func itoa(n uint64) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}
