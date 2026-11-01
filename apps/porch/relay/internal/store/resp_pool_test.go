package store

import (
	"sync"
	"testing"
	"time"
)

// The pool keeps a few connections, never one per request.
func TestPoolStaysSmall(t *testing.T) {
	f := newFakeRedis(t)
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c.Do("PING")
		}()
	}
	wg.Wait()
	if n := f.dialCount(); n > respPoolSize {
		t.Fatalf("%d connections dialed, want at most %d", n, respPoolSize)
	}
}

// If Redis stays down past downAfter, Down() closes so relayd can exit
// and systemd (or compose) restarts it.
func TestRedisThatStaysDownIsReported(t *testing.T) {
	f := newFakeRedis(t)
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	c.timeout = 200 * time.Millisecond
	c.downAfter = 50 * time.Millisecond

	select {
	case <-c.Down():
		t.Fatal("Down closed while Redis is up")
	default:
	}

	f.stop() // Redis goes away and stays away
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		c.Do("PING")
		select {
		case <-c.Down():
			return
		default:
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("Down never closed while Redis stayed down")
}

// A short outage that ends is not reported.
func TestShortOutageIsNotReported(t *testing.T) {
	f := newFakeRedis(t)
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	c.downAfter = time.Hour

	f.dropConns()
	c.Do("PING")
	if _, err := c.Do("PING"); err != nil {
		t.Fatalf("PING after reconnect: %v", err)
	}
	select {
	case <-c.Down():
		t.Fatal("Down closed after a short outage")
	default:
	}
}
