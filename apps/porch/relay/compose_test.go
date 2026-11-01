package relay_test

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// Redis must never grow without bound, and must never drop a key to make
// room. docker-compose.yml gives it a memory ceiling with noeviction: at
// the ceiling it refuses writes. An evicting policy would drop the keys
// closest to expiry first, and the drain replay entries (10 minutes) are
// the shortest-lived keys in the store: a captured drain would become
// replayable.
func TestComposeCapsRedisMemoryWithoutEviction(t *testing.T) {
	b, err := os.ReadFile("docker-compose.yml")
	if err != nil {
		t.Fatal(err)
	}
	compose := string(b)
	i := strings.Index(compose, "redis-server")
	if i < 0 {
		t.Fatal("no redis-server command in docker-compose.yml")
	}
	line := compose[i:]
	line = line[:strings.IndexByte(line, '\n')]
	for _, want := range []string{`"--maxmemory"`, `"--maxmemory-policy", "noeviction"`} {
		if !strings.Contains(line, want) {
			t.Errorf("redis command lacks %s: %s", want, line)
		}
	}
	if strings.Contains(compose, "volatile-") || strings.Contains(compose, "allkeys-") {
		t.Error("docker-compose.yml still names an evicting policy")
	}
}

// The bare-metal guide sets the same lines in redis.conf, and says that a
// full Redis refuses writes by design.
func TestDeployGuideCapsRedisMemoryWithoutEviction(t *testing.T) {
	b, err := os.ReadFile("ops/DEPLOY.md")
	if err != nil {
		t.Fatal(err)
	}
	guide := string(b)
	for _, want := range []string{"maxmemory ", "maxmemory-policy noeviction", "refuses writes by design"} {
		if !strings.Contains(guide, want) {
			t.Errorf("DEPLOY.md lacks %q", want)
		}
	}
	if strings.Contains(guide, "volatile-") || strings.Contains(guide, "allkeys-") {
		t.Error("DEPLOY.md still names an evicting policy")
	}
}

// A tag can be moved to other code; a digest cannot. Every image in the
// compose file is pinned by digest, with the tag it was taken from in a
// comment on the same line.
//
// unpinnedOwed names images whose digest has not been looked up yet. The
// test fails if one of them gets pinned without leaving this list, so the
// list only shrinks.
var unpinnedOwed = map[string]bool{}

func TestComposeImagesArePinnedByDigest(t *testing.T) {
	b, err := os.ReadFile("docker-compose.yml")
	if err != nil {
		t.Fatal(err)
	}
	image := regexp.MustCompile(`(?m)^\s*image:\s*(\S+)(.*)$`)
	pinned := regexp.MustCompile(`^([^@\s]+)@sha256:[0-9a-f]{64}$`)
	tagComment := regexp.MustCompile(`#\s*\S+:\S+`)
	found := 0
	for _, m := range image.FindAllStringSubmatch(string(b), -1) {
		found++
		ref, rest := m[1], m[2]
		name, _, _ := strings.Cut(ref, "@")
		if slash := strings.LastIndexByte(name, '/'); strings.IndexByte(name[slash+1:], ':') >= 0 {
			name = name[:slash+1+strings.IndexByte(name[slash+1:], ':')]
		}
		p := pinned.FindStringSubmatch(ref)
		if p == nil {
			if !unpinnedOwed[name] {
				t.Errorf("image %s is not pinned by digest", ref)
			}
			continue
		}
		if unpinnedOwed[p[1]] {
			t.Errorf("image %s is pinned now: take it off unpinnedOwed", p[1])
		}
		if !tagComment.MatchString(rest) {
			t.Errorf("image %s has no tag comment beside its digest", ref)
		}
	}
	if found == 0 {
		t.Fatal("no image lines in docker-compose.yml")
	}
}
