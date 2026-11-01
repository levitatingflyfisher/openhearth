package api

// Stateless signed drain (BUILD-SPEC §1.2, §4 row 7) — the relay's ONE
// signature check, ~60 lines. No sessions, no tokens, no challenge flow:
// the drain request itself carries pubkey, timestamp, and an Ed25519
// signature over "porch-drain|{mailboxId}|{ts}". The server verifies
// hash(pubkey)==mailboxId, ±300 s freshness, the signature, and a replay
// cache keyed on hash(sig).

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strconv"
	"time"

	"golang.org/x/crypto/blake2b"

	"porch/relay/internal/store"
)

const (
	// mailboxIDContext matches core's derivation (BUILD-SPEC §3.1 step 5):
	// mailboxId = base64url(crypto_generichash(out=32, "porch/mbox/v1" ‖ sign_pk)).
	// libsodium crypto_generichash IS unkeyed BLAKE2b.
	mailboxIDContext   = "porch/mbox/v1"
	drainMessagePrefix = "porch-drain|"
	drainFreshness     = 300 * time.Second
	replayTTL          = 10 * time.Minute
)

var errDrainAuth = errors.New("drain auth failed")

// drainAuth is the drain request body. []byte fields are standard base64
// in JSON per encoding/json.
type drainAuth struct {
	Pubkey []byte `json:"pubkey"`
	Ts     int64  `json:"ts"`
	Sig    []byte `json:"sig"`
}

// DeriveMailboxID computes the wire mailbox id for an Ed25519 public key.
// Exported for the integration harness and Go-side protocol clients.
func DeriveMailboxID(signPk []byte) string {
	h, err := blake2b.New256(nil)
	if err != nil {
		panic(err) // unkeyed BLAKE2b-256 cannot fail to construct
	}
	h.Write([]byte(mailboxIDContext))
	h.Write(signPk)
	return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}

// deriveMailboxID is the package-internal spelling.
func deriveMailboxID(signPk []byte) string { return DeriveMailboxID(signPk) }

// verifyDrain returns nil iff the request may drain mailboxID. Every failure
// is the same opaque error: callers answer 401 with no detail.
func verifyDrain(ctx context.Context, st store.Store, now time.Time, mailboxID string, a drainAuth) error {
	if len(a.Pubkey) != ed25519.PublicKeySize || len(a.Sig) != ed25519.SignatureSize {
		return errDrainAuth
	}
	derived := deriveMailboxID(a.Pubkey)
	if subtle.ConstantTimeCompare([]byte(derived), []byte(mailboxID)) != 1 {
		return errDrainAuth
	}
	skew := now.Unix() - a.Ts
	if skew < 0 {
		skew = -skew
	}
	if skew > int64(drainFreshness/time.Second) {
		return errDrainAuth
	}
	msg := drainMessagePrefix + mailboxID + "|" + strconv.FormatInt(a.Ts, 10)
	if !ed25519.Verify(ed25519.PublicKey(a.Pubkey), []byte(msg), a.Sig) {
		return errDrainAuth
	}
	sigHash := sha256.Sum256(a.Sig)
	fresh, err := st.ReplayCheck(ctx, hex.EncodeToString(sigHash[:]), replayTTL)
	if err != nil {
		return err
	}
	if !fresh {
		return errDrainAuth
	}
	return nil
}
