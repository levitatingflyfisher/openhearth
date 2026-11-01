package store

import (
	"bufio"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

// respPoolSize is how many Redis connections a relay keeps at most.
// Commands beyond it wait for a free one.
const respPoolSize = 4

// respDownAfter is how long Redis may fail every connection attempt
// before the pool reports it down, so relayd exits and its supervisor
// (systemd Restart=on-failure, compose restart) starts it again.
const respDownAfter = 30 * time.Second

// respPool is a deliberately minimal RESP2 client: just enough Redis for
// this relay, over a small pool of connections. Using it keeps the relay
// a single stdlib-only binary (no third-party Redis client dependency).
// Single-node Redis only (BUILD-SPEC deploys one Redis per relay).
//
// A connection that returns any error is closed, never reused: after a
// timeout or a transport error the stream is out of step, and a late
// reply on it would answer the next command, handing one request's
// drained mail to another. The next command dials a fresh connection.
type respPool struct {
	addr string
	db   int

	// timeout bounds one command; downAfter bounds an outage (tests
	// shorten both).
	timeout   time.Duration
	downAfter time.Duration

	slots chan struct{}  // one token per connection allowed
	idle  chan *respConn // healthy connections not in use

	mu        sync.Mutex
	lastOK    time.Time // the last time a command succeeded
	down      chan struct{}
	downOnce  sync.Once
	closed    bool
	closeOnce sync.Once
}

// respConn is one connection, used by one command at a time.
type respConn struct {
	conn net.Conn
	br   *bufio.Reader
	bw   *bufio.Writer
}

// respError is a Redis -ERR reply.
type respError string

func (e respError) Error() string { return "redis: " + string(e) }

// dialRedis accepts "redis://host:port[/db]", "host:port", or ":port". It
// makes one connection and pings, so a Redis that is not there fails at
// startup.
func dialRedis(url string) (*respPool, error) {
	addr := strings.TrimPrefix(url, "redis://")
	db := 0
	if i := strings.IndexByte(addr, '/'); i >= 0 {
		n, err := strconv.Atoi(addr[i+1:])
		if err != nil {
			return nil, fmt.Errorf("bad redis db in %q", url)
		}
		db, addr = n, addr[:i]
	}
	p := &respPool{
		addr:      addr,
		db:        db,
		timeout:   10 * time.Second,
		downAfter: respDownAfter,
		slots:     make(chan struct{}, respPoolSize),
		idle:      make(chan *respConn, respPoolSize),
		lastOK:    time.Now(),
		down:      make(chan struct{}),
	}
	if _, err := p.Do("PING"); err != nil {
		p.Close()
		return nil, err
	}
	return p, nil
}

// Down is closed once Redis has failed every command for downAfter.
func (p *respPool) Down() <-chan struct{} { return p.down }

func (p *respPool) Close() error {
	p.closeOnce.Do(func() {
		p.mu.Lock()
		p.closed = true
		p.mu.Unlock()
		for {
			select {
			case c := <-p.idle:
				c.conn.Close()
			default:
				return
			}
		}
	})
	return nil
}

// Do sends one command and reads one reply. args may be string, []byte,
// int, or int64. Replies: string (simple), int64, []byte (bulk, nil for
// null), []any (array), or respError.
func (p *respPool) Do(args ...any) (any, error) {
	p.slots <- struct{}{} // wait for room
	c, err := p.get()
	if err != nil {
		<-p.slots
		p.failed()
		return nil, err
	}
	res, err := c.do(p.timeout, args)
	if err != nil {
		// Any error: the connection may be out of step. Drop it.
		c.conn.Close()
		<-p.slots
		var re respError
		if errors.As(err, &re) {
			p.succeeded() // Redis answered; it is up
		} else {
			p.failed()
		}
		return nil, err
	}
	p.put(c)
	<-p.slots
	p.succeeded()
	return res, nil
}

// get takes an idle connection or dials a new one.
func (p *respPool) get() (*respConn, error) {
	select {
	case c := <-p.idle:
		return c, nil
	default:
	}
	conn, err := net.DialTimeout("tcp", p.addr, 5*time.Second)
	if err != nil {
		return nil, err
	}
	c := &respConn{conn: conn, br: bufio.NewReader(conn), bw: bufio.NewWriter(conn)}
	if p.db != 0 {
		if _, err := c.do(p.timeout, []any{"SELECT", strconv.Itoa(p.db)}); err != nil {
			conn.Close()
			return nil, err
		}
	}
	return c, nil
}

func (p *respPool) put(c *respConn) {
	p.mu.Lock()
	closed := p.closed
	p.mu.Unlock()
	if closed {
		c.conn.Close()
		return
	}
	select {
	case p.idle <- c:
	default:
		c.conn.Close()
	}
}

func (p *respPool) succeeded() {
	p.mu.Lock()
	p.lastOK = time.Now()
	p.mu.Unlock()
}

func (p *respPool) failed() {
	p.mu.Lock()
	since := time.Since(p.lastOK)
	p.mu.Unlock()
	if since >= p.downAfter {
		p.downOnce.Do(func() { close(p.down) })
	}
}

func (c *respConn) do(timeout time.Duration, args []any) (any, error) {
	if err := c.conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	if err := c.writeCommand(args); err != nil {
		return nil, err
	}
	if err := c.bw.Flush(); err != nil {
		return nil, err
	}
	return c.readReply()
}

func (c *respConn) writeCommand(args []any) error {
	fmt.Fprintf(c.bw, "*%d\r\n", len(args))
	for _, a := range args {
		var b []byte
		switch v := a.(type) {
		case string:
			b = []byte(v)
		case []byte:
			b = v
		case int:
			b = []byte(strconv.Itoa(v))
		case int64:
			b = []byte(strconv.FormatInt(v, 10))
		case uint64:
			b = []byte(strconv.FormatUint(v, 10))
		default:
			return fmt.Errorf("respConn: unsupported arg type %T", a)
		}
		fmt.Fprintf(c.bw, "$%d\r\n", len(b))
		c.bw.Write(b)
		c.bw.WriteString("\r\n")
	}
	return nil
}

func (c *respConn) readReply() (any, error) {
	line, err := c.readLine()
	if err != nil {
		return nil, err
	}
	if len(line) == 0 {
		return nil, errors.New("respConn: empty reply line")
	}
	body := string(line[1:])
	switch line[0] {
	case '+':
		return body, nil
	case '-':
		return nil, respError(body)
	case ':':
		n, err := strconv.ParseInt(body, 10, 64)
		return n, err
	case '$':
		n, err := strconv.Atoi(body)
		if err != nil {
			return nil, err
		}
		if n < 0 {
			return []byte(nil), nil // null bulk
		}
		buf := make([]byte, n+2)
		if _, err := ioReadFull(c.br, buf); err != nil {
			return nil, err
		}
		return buf[:n], nil
	case '*':
		n, err := strconv.Atoi(body)
		if err != nil {
			return nil, err
		}
		if n < 0 {
			return []any(nil), nil
		}
		arr := make([]any, n)
		for i := range arr {
			v, err := c.readReply()
			if err != nil {
				// A nested -ERR is a real value in arrays; only transport
				// errors abort the read.
				var re respError
				if errors.As(err, &re) {
					arr[i] = re
					continue
				}
				return nil, err
			}
			arr[i] = v
		}
		return arr, nil
	default:
		return nil, fmt.Errorf("respConn: unknown reply type %q", line[0])
	}
}

func (c *respConn) readLine() ([]byte, error) {
	line, err := c.br.ReadBytes('\n')
	if err != nil {
		return nil, err
	}
	if len(line) < 2 || line[len(line)-2] != '\r' {
		return nil, errors.New("respConn: malformed line terminator")
	}
	return line[:len(line)-2], nil
}

func ioReadFull(br *bufio.Reader, buf []byte) (int, error) {
	total := 0
	for total < len(buf) {
		n, err := br.Read(buf[total:])
		total += n
		if err != nil {
			return total, err
		}
	}
	return total, nil
}
