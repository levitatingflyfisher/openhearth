package store

import (
	"bufio"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeRedis speaks just enough RESP2 on a loopback port to drive respConn:
// PING → +PONG, GET k → the value set for k, SLOW → +LATE after a delay
// (longer than the client's timeout, so the reply arrives late).
type fakeRedis struct {
	t    *testing.T
	ln   net.Listener
	slow time.Duration

	mu    sync.Mutex
	conns []net.Conn
	vals  map[string]string
	dials int
	oom   bool // answer EVAL and SET as a full Redis under noeviction does
}

func newFakeRedis(t *testing.T) *fakeRedis {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	f := &fakeRedis{t: t, ln: ln, slow: 300 * time.Millisecond, vals: map[string]string{}}
	go f.accept()
	t.Cleanup(f.stop)
	return f
}

func (f *fakeRedis) addr() string { return f.ln.Addr().String() }

func (f *fakeRedis) accept() {
	for {
		c, err := f.ln.Accept()
		if err != nil {
			return
		}
		f.mu.Lock()
		f.conns = append(f.conns, c)
		f.dials++
		f.mu.Unlock()
		go f.serve(c)
	}
}

// dropConns closes every open connection, as a Redis restart does.
func (f *fakeRedis) dropConns() {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, c := range f.conns {
		c.Close()
	}
	f.conns = nil
}

func (f *fakeRedis) stop() {
	f.ln.Close()
	f.dropConns()
}

func (f *fakeRedis) dialCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.dials
}

func (f *fakeRedis) serve(c net.Conn) {
	br := bufio.NewReader(c)
	for {
		args, err := readCommand(br)
		if err != nil {
			return
		}
		switch strings.ToUpper(args[0]) {
		case "PING":
			c.Write([]byte("+PONG\r\n"))
		case "SELECT":
			c.Write([]byte("+OK\r\n"))
		case "SLOW":
			time.Sleep(f.slow)
			c.Write([]byte("+LATE\r\n"))
		case "GET":
			f.mu.Lock()
			v, ok := f.vals[args[1]]
			f.mu.Unlock()
			if !ok {
				c.Write([]byte("$-1\r\n"))
				continue
			}
			c.Write([]byte("$" + strconv.Itoa(len(v)) + "\r\n" + v + "\r\n"))
		case "EVAL", "SET":
			f.mu.Lock()
			oom := f.oom
			f.mu.Unlock()
			if oom {
				c.Write([]byte("-OOM command not allowed when used memory > 'maxmemory'.\r\n"))
				continue
			}
			c.Write([]byte("-ERR unknown command\r\n"))
		default:
			c.Write([]byte("-ERR unknown command\r\n"))
		}
	}
}

func readCommand(br *bufio.Reader) ([]string, error) {
	line, err := br.ReadString('\n')
	if err != nil {
		return nil, err
	}
	n, err := strconv.Atoi(strings.TrimSpace(line[1:]))
	if err != nil {
		return nil, err
	}
	args := make([]string, n)
	for i := range args {
		if _, err := br.ReadString('\n'); err != nil { // $len
			return nil, err
		}
		v, err := br.ReadString('\n')
		if err != nil {
			return nil, err
		}
		args[i] = strings.TrimSuffix(v, "\r\n")
	}
	return args, nil
}

// After a timeout, the late reply must never be read as the answer to
// the next command. One request's drained mail could otherwise reach
// another client.
func TestTimedOutReplyNeverAnswersTheNextCommand(t *testing.T) {
	f := newFakeRedis(t)
	f.vals["k"] = "mine"
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	c.timeout = 100 * time.Millisecond

	if _, err := c.Do("SLOW"); err == nil {
		t.Fatal("SLOW did not time out")
	}
	// Let the late reply land on whatever connection SLOW used.
	time.Sleep(f.slow)

	got, err := c.Do("GET", "k")
	if err != nil {
		t.Fatalf("GET after a timeout: %v", err)
	}
	if b, _ := got.([]byte); string(b) != "mine" {
		t.Fatalf("GET read %#v, want \"mine\": a late reply leaked into it", got)
	}
}

// After a Redis restart the old connections are dead. At most the one
// command that finds a dead connection fails; the next one redials.
func TestRedisRestartCostsAtMostOneCommand(t *testing.T) {
	f := newFakeRedis(t)
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	c.timeout = time.Second

	f.dropConns()
	time.Sleep(20 * time.Millisecond)

	_, err1 := c.Do("PING")
	_, err2 := c.Do("PING")
	if err2 != nil {
		t.Fatalf("second PING after a restart: %v (first: %v)", err2, err1)
	}
}

// Commands from many requests at once each get their own reply.
func TestConcurrentCommandsGetTheirOwnReplies(t *testing.T) {
	f := newFakeRedis(t)
	for i := 0; i < 20; i++ {
		f.vals["k"+strconv.Itoa(i)] = "v" + strconv.Itoa(i)
	}
	c, err := dialRedis(f.addr())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()

	var wg sync.WaitGroup
	errs := make(chan string, 200)
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			k := "k" + strconv.Itoa(i%20)
			got, err := c.Do("GET", k)
			if err != nil {
				errs <- err.Error()
				return
			}
			if b, _ := got.([]byte); string(b) != "v"+strconv.Itoa(i%20) {
				errs <- k + " read " + string(b)
			}
		}(i)
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Error(e)
	}
}
