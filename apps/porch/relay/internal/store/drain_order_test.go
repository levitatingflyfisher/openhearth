package store

import (
	"strings"
	"testing"
)

// The drain script writes before it deletes. A Lua script is not rolled
// back when a later command in it fails, and at maxmemory under
// noeviction Redis refuses a write such as SET. With DEL first, a refused
// SET would leave the mail deleted and the caller with an error: the mail
// lost. With the SET first, a refused SET stops the script before the mail
// is touched. redis_full_test.go runs this against a real Redis at its
// memory ceiling.
func TestDrainScriptWritesBeforeItDeletes(t *testing.T) {
	set := strings.Index(luaMailboxDrain, "'SET'")
	del := strings.Index(luaMailboxDrain, "'DEL'")
	if set < 0 || del < 0 {
		t.Fatalf("drain script lacks SET or DEL:\n%s", luaMailboxDrain)
	}
	if set > del {
		t.Fatalf("drain script deletes the mail before its write:\n%s", luaMailboxDrain)
	}
}
