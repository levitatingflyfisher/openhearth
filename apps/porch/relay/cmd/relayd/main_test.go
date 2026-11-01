package main

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// The invocation paths below all return before serving, so they run
// without binding a port.

func TestStrayPositionalArgumentIsRefused(t *testing.T) {
	var out, errb bytes.Buffer
	// Go's flag package stops at the first bare word, so before this check
	// `relayd redis -addr X` silently ignored -addr and served on :8080.
	code := run([]string{"redis", "-addr", "127.0.0.1:1"}, &out, &errb)
	if code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if out.Len() != 0 {
		t.Errorf("stdout = %q, want empty (errors go to stderr)", out.String())
	}
	msg := errb.String()
	if !strings.Contains(msg, `unexpected argument "redis"`) {
		t.Errorf("stderr lacks the offending argument: %q", msg)
	}
	if !strings.Contains(msg, "-store=redis") {
		t.Errorf("stderr lacks the did-you-mean for a store name: %q", msg)
	}
}

func TestStrayArgumentWithoutASuggestionStillExitsTwo(t *testing.T) {
	var out, errb bytes.Buffer
	code := run([]string{"-addr", "127.0.0.1:1", "extra"}, &out, &errb)
	if code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if !strings.Contains(errb.String(), `unexpected argument "extra"`) {
		t.Errorf("stderr = %q", errb.String())
	}
}

func TestRequestedHelpGoesToStdoutAndSucceeds(t *testing.T) {
	for _, arg := range []string{"-h", "--help"} {
		var out, errb bytes.Buffer
		code := run([]string{arg}, &out, &errb)
		if code != 0 {
			t.Errorf("%s: exit = %d, want 0", arg, code)
		}
		if errb.Len() != 0 {
			t.Errorf("%s: stderr = %q, want empty", arg, errb.String())
		}
		for _, want := range []string{"Usage: relayd", "-addr", "-store", "-version"} {
			if !strings.Contains(out.String(), want) {
				t.Errorf("%s: stdout lacks %q:\n%s", arg, want, out.String())
			}
		}
	}
}

func TestUnknownFlagIsAUsageErrorOnStderr(t *testing.T) {
	var out, errb bytes.Buffer
	code := run([]string{"-bogus"}, &out, &errb)
	if code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if out.Len() != 0 {
		t.Errorf("stdout = %q, want empty", out.String())
	}
	if !strings.Contains(errb.String(), "bogus") {
		t.Errorf("stderr = %q", errb.String())
	}
}

func TestVersionPrintsToStdout(t *testing.T) {
	for _, arg := range []string{"-version", "--version"} {
		var out, errb bytes.Buffer
		code := run([]string{arg}, &out, &errb)
		if code != 0 {
			t.Errorf("%s: exit = %d, want 0", arg, code)
		}
		if got := strings.TrimSpace(out.String()); got != "relayd "+version {
			t.Errorf("%s: stdout = %q, want %q", arg, got, "relayd "+version)
		}
		if errb.Len() != 0 {
			t.Errorf("%s: stderr = %q", arg, errb.String())
		}
	}
}

// The daily opening cap is a setting: -opens-per-day, 50 by default, 0
// for no cap.
func TestOpensPerDayIsASetting(t *testing.T) {
	var out, errb bytes.Buffer
	run([]string{"-h"}, &out, &errb)
	if !strings.Contains(out.String(), "-opens-per-day") {
		t.Fatalf("help lacks -opens-per-day:\n%s", out.String())
	}
	if got := rateRules(7).Open; got != api.OpensPerDay(7) {
		t.Errorf("rateRules(7).Open = %+v", got)
	}
	if got := rateRules(0).Open; got.Burst != 0 {
		t.Errorf("rateRules(0).Open = %+v, want no cap", got)
	}
	if got := rateRules(api.DefaultOpensPerDay); got != api.DefaultRateRules() {
		t.Errorf("the default setting changes other rules: %+v", got)
	}
}

func TestNegativeOpensPerDayIsAUsageError(t *testing.T) {
	var out, errb bytes.Buffer
	code := run([]string{"-opens-per-day", "-1"}, &out, &errb)
	if code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if !strings.Contains(errb.String(), "-opens-per-day") {
		t.Errorf("stderr = %q", errb.String())
	}
}

func TestUnknownStoreStillExitsOne(t *testing.T) {
	var out, errb bytes.Buffer
	code := run([]string{"-store", "bogus"}, &out, &errb)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if !strings.Contains(errb.String(), `unknown -store "bogus"`) {
		t.Errorf("stderr = %q", errb.String())
	}
}

// downStore is a memory store that can be made to report Redis down.
type downStore struct {
	store.Store
	down chan struct{}
}

func (d downStore) Down() <-chan struct{} { return d.down }

// When Redis stays down, relayd exits 1, saying nothing, so systemd
// (Restart=on-failure) or compose restarts it.
func TestRedisThatStaysDownEndsTheProcessSilently(t *testing.T) {
	ds := downStore{
		Store: store.NewMem(store.DefaultLimits(), time.Now),
		down:  make(chan struct{}),
	}
	saved := openStore
	openStore = func(string, string) (store.Store, func(), error) {
		return ds, func() {}, nil
	}
	t.Cleanup(func() { openStore = saved })

	var out, errb bytes.Buffer
	done := make(chan int, 1)
	go func() { done <- run([]string{"-addr", "127.0.0.1:0", "-store", "redis"}, &out, &errb) }()

	select {
	case code := <-done:
		t.Fatalf("relayd stopped before Redis went down: exit %d, stderr %q", code, errb.String())
	case <-time.After(100 * time.Millisecond):
	}
	close(ds.down)
	select {
	case code := <-done:
		if code != 1 {
			t.Fatalf("exit = %d, want 1", code)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("relayd kept serving with Redis down")
	}
	if out.Len() != 0 || errb.Len() != 0 {
		t.Fatalf("relayd printed while serving: stdout %q, stderr %q", out.String(), errb.String())
	}
}
