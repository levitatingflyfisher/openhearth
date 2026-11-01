// relayd is the Porch relay: one stdlib binary, twelve endpoints, zero logs.
//
// Output happens only before serving begins: requested help or --version
// on stdout, and an invocation or startup error on stderr. Once it serves:
// silence, structurally — the serving packages contain no logging calls
// (CI-greped), and net/http's own error logger is wired to io.Discard.
//
// Exit codes: 0 success (including -h and --version), 1 startup failure
// (unreachable Redis, port in use, unknown -store) or a Redis that stays
// down while serving (silently: the supervisor restarts relayd), 2 bad
// invocation (unknown flag, stray positional argument).
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"porch/relay/internal/api"
	"porch/relay/internal/store"
)

// version is stamped at build time:
//
//	go build -ldflags "-X main.version=v0.1.0" ./cmd/relayd
var version = "dev"

const usageText = `Usage: relayd [flags]

relayd is the Porch relay: a blind store-and-forward server for
end-to-end-encrypted presence. It keeps no logs and prints nothing
while it serves.

Examples:
  relayd                                   in-memory store on :8080
  relayd -addr 127.0.0.1:9000              a different listen address
  relayd -store=redis -redis-url redis://127.0.0.1:6379

Flags:
`

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run parses args and serves until SIGINT/SIGTERM. It returns the process
// exit code; everything it prints goes to stdout (requested output) or
// stderr (errors), and only before serving begins.
func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("relayd", flag.ContinueOnError)
	addr := fs.String("addr", ":8080", "listen address")
	storeKind := fs.String("store", "memory", "storage backend: memory|redis")
	redisURL := fs.String("redis-url", "redis://127.0.0.1:6379", "redis address (with -store=redis)")
	trustForwarded := fs.Bool("trust-forwarded", false,
		"rate-limit by the LAST X-Forwarded-For hop — the one the terminator appended (ONLY behind exactly one trusted TLS terminator)")
	opensPerDay := fs.Int("opens-per-day", api.DefaultOpensPerDay,
		"mailboxes and channels one address (an IPv6 /64) may open a day; 0 for no cap")
	showVersion := fs.Bool("version", false, "print the version and exit")
	printUsage := func(w io.Writer) {
		fmt.Fprint(w, usageText)
		fs.SetOutput(w)
		fs.PrintDefaults()
	}
	fs.SetOutput(stderr) // parse errors
	fs.Usage = func() {} // we print usage ourselves, to the right stream
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			printUsage(stdout)
			return 0
		}
		// fs already printed the error line to stderr.
		fmt.Fprintln(stderr, "Run 'relayd -h' for usage.")
		return 2
	}
	// Go's flag package stops at the first bare word, silently ignoring
	// every flag after it — refuse rather than serve a configuration the
	// operator did not ask for.
	if fs.NArg() > 0 {
		arg := fs.Arg(0)
		fmt.Fprintf(stderr, "relayd: unexpected argument %q\n", arg)
		if arg == "memory" || arg == "redis" {
			fmt.Fprintf(stderr, "Did you mean -store=%s?\n", arg)
		}
		fmt.Fprintln(stderr, "Run 'relayd -h' for usage.")
		return 2
	}
	if *opensPerDay < 0 {
		fmt.Fprintln(stderr, "relayd: -opens-per-day must be 0 or more")
		fmt.Fprintln(stderr, "Run 'relayd -h' for usage.")
		return 2
	}
	if *showVersion {
		fmt.Fprintln(stdout, "relayd", version)
		return 0
	}

	st, closeStore, err := openStore(*storeKind, *redisURL)
	if err != nil {
		fmt.Fprintln(stderr, "relayd:", err)
		return 1
	}
	defer closeStore()

	srv := &http.Server{
		Addr: *addr,
		Handler: api.New(api.Config{Store: st, TrustForwarded: *trustForwarded,
			Rates: rateRules(*opensPerDay)}),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
		// Zero-logging: net/http logs accept/handler errors by default;
		// discard them. This is a suppression sink, not a logger.
		ErrorLog: log.New(io.Discard, "", 0),
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() { errCh <- srv.ListenAndServe() }()

	// A store that can go down (Redis) says so on this channel; nil (the
	// memory store) never fires.
	var down <-chan struct{}
	if d, ok := st.(interface{ Down() <-chan struct{} }); ok {
		down = d.Down()
	}

	select {
	case <-down:
		// Redis has failed every command for a while. Exit without a word
		// (relayd is silent while serving) so the supervisor restarts it.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
		return 1
	case err := <-errCh:
		// Startup failure (e.g. bind): the one permitted stderr write.
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			fmt.Fprintln(stderr, "relayd:", err)
			return 1
		}
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx) // graceful; in-flight requests finish
	}
	return 0
}

// rateRules is the default rules with n openings a day (0: no cap).
func rateRules(n int) api.RateRules {
	r := api.DefaultRateRules()
	r.Open = api.RateRule{}
	if n > 0 {
		r.Open = api.OpensPerDay(n)
	}
	return r
}

// openStore is buildStore; tests swap it for a store they control.
var openStore = buildStore

func buildStore(kind, redisURL string) (store.Store, func(), error) {
	switch kind {
	case "memory":
		return store.NewMem(store.DefaultLimits(), time.Now), func() {}, nil
	case "redis":
		rs, err := store.NewRedis(redisURL, store.DefaultLimits())
		if err != nil {
			return nil, nil, fmt.Errorf("connect redis: %w", err)
		}
		return rs, func() { rs.Close() }, nil
	default:
		return nil, nil, fmt.Errorf("unknown -store %q (want memory|redis)", kind)
	}
}
