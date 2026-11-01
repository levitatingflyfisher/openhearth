package api_test

// Shared black-box harness: every test drives the real router over
// httptest, with the in-memory store and a fake clock. No sleeps, no
// external services.

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// Realistic capability ids (base64url shapes from the spec).
const (
	testInvite  = "inv_aaaaaaaaaaaaaaaaa0" // 22 chars, like base64url(gh)[0:22]
	testInvite2 = "inv_bbbbbbbbbbbbbbbbb0"
	testChannel = "chan_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0" // 43-ish chars
	testSlot    = "slot_aaaaaaaaaaaaaaaa0"
	testIP      = "192.0.2.10:40000"
)

type relay struct {
	h   http.Handler
	clk *store.FakeClock
	st  *store.Mem
}

// generousRates keeps functional tests clear of throttling; rate-limit
// behavior is tested explicitly with tight rules.
func generousRates() api.RateRules {
	g := api.RateRule{Burst: 10000, PerSec: 10000}
	return api.RateRules{InviteCreate: g, MailboxPost: g, Drain: g, ChannelWrite: g, Read: g}
}

func newRelay(t *testing.T) *relay {
	return newRelayWith(t, store.DefaultLimits(), generousRates())
}

func newRelayWith(t *testing.T, lim store.Limits, rates api.RateRules) *relay {
	t.Helper()
	clk := store.NewFakeClock(time.Unix(1_750_000_000, 0))
	st := store.NewMem(lim, clk.Now)
	h := api.New(api.Config{Store: st, Now: clk.Now, Rates: rates})
	return &relay{h: h, clk: clk, st: st}
}

// do sends a JSON request from the default test IP.
func (rl *relay) do(t *testing.T, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	return rl.doFrom(t, method, path, body, testIP)
}

func (rl *relay) doFrom(t *testing.T, method, path string, body any, remoteAddr string) *httptest.ResponseRecorder {
	t.Helper()
	var rd *bytes.Reader
	if body == nil {
		rd = bytes.NewReader(nil)
	} else if raw, ok := body.([]byte); ok {
		rd = bytes.NewReader(raw)
	} else {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		rd = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rd)
	req.RemoteAddr = remoteAddr
	w := httptest.NewRecorder()
	rl.h.ServeHTTP(w, req)
	return w
}

// do2 sends a JSON request with extra headers set.
func (rl *relay) do2(t *testing.T, method, path string, body any, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var b []byte
	if body != nil {
		var err error
		if b, err = json.Marshal(body); err != nil {
			t.Fatalf("marshal body: %v", err)
		}
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(b))
	req.RemoteAddr = testIP
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	rl.h.ServeHTTP(w, req)
	return w
}

func wantStatus(t *testing.T, w *httptest.ResponseRecorder, want int) {
	t.Helper()
	if w.Code != want {
		t.Fatalf("status = %d, want %d (body %q)", w.Code, want, w.Body.String())
	}
}

func decodeBody[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode response %q: %v", w.Body.String(), err)
	}
	return v
}

// Error responses must be status codes only — no echoed bodies (spec §4).
func wantEmptyErrorBody(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	if s := strings.TrimSpace(w.Body.String()); s != "" {
		t.Fatalf("error response leaked a body: %q", s)
	}
}

func TestHealthz(t *testing.T) {
	rl := newRelay(t)
	w := rl.do(t, "GET", "/v1/healthz", nil)
	wantStatus(t, w, http.StatusOK)
}

func TestUnknownRouteIs404(t *testing.T) {
	rl := newRelay(t)
	w := rl.do(t, "GET", "/v1/users", nil) // no user records of any kind
	wantStatus(t, w, http.StatusNotFound)
}

func TestNoCookiesEver(t *testing.T) {
	rl := newRelay(t)
	for _, probe := range []struct{ method, path string }{
		{"GET", "/v1/healthz"},
		{"GET", "/v1/ch/" + testChannel + "/presence"},
	} {
		w := rl.do(t, probe.method, probe.path, nil)
		if sc := w.Header().Get("Set-Cookie"); sc != "" {
			t.Fatalf("%s %s set a cookie: %q", probe.method, probe.path, sc)
		}
	}
}
