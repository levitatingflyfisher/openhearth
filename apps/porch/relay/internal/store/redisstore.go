package store

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Redis is the production Store: single-node Redis 7, AOF everysec
// (docker-compose). Key shapes follow BUILD-SPEC §5.4 exactly:
//
//	inv:{inviteId}        HASH  state/join/grant/fp/gp   TTL ≤72h
//	mbox:{mailboxId}      LIST  raw blobs                30d rolling
//	replay:{sigHash}      SET NX                          10 min
//	p:{channelId}:{slot}  raw blob                        = status TTL
//	b:{channelId}         LIST "seq|rawblob"              60d sliding
//	bp:{channelId}:{seq}  raw blob (pinned)               own TTL ≤72h
//	bpi:{channelId}       ZSET live-pin index             60d sliding
//	seq:{channelId}       INCR counter                    60d sliding
//	mboxo:{mailboxId}     "1": the owner drains it        30d, set on drain
//	fresh                 ZSET never-drained mailboxes    score = expiry ms
//	chans                 ZSET live channels              score = expiry ms
//	chw:{channelId}       first writing slot, or "*"      = its chans entry
//	                      once a second slot has written
//	                      (by presence, or named by a bulletin write)
//
// fresh and chans bound what anonymous callers can open: a push may
// not open a never-drained mailbox past MaxFreshMailboxes, a channel write
// may not open a channel past MaxChannels. Both carry a TTL like every
// other key. A channel's place in chans lasts at most ChannelFreshTTL
// until chw shows a second writer. Opening anything, or owning a mailbox,
// also needs an opening from the ctx's Opener: the Go side takes one
// before the script (ARGV mayOpen "1"), and gives it back if the script
// reports it opened nothing.
//
// Every multi-step mutation is one Lua script (atomic). Blobs are stored as
// raw bytes end to end — the relay provably never parses or re-encodes them.
type Redis struct {
	c   *respPool
	lim Limits
}

var _ Store = (*Redis)(nil)

// NewRedis connects and pings. url: "redis://host:port[/db]" or "host:port".
func NewRedis(url string, lim Limits) (*Redis, error) {
	c, err := dialRedis(url)
	if err != nil {
		return nil, err
	}
	return &Redis{c: c, lim: lim}, nil
}

func (r *Redis) Close() error { return r.c.Close() }

// Down is closed once Redis has failed every command for 30 s. relayd
// then exits, and its supervisor starts it again.
func (r *Redis) Down() <-chan struct{} { return r.c.Down() }

// FlushForTest empties the current DB. Test harness use only.
func (r *Redis) FlushForTest(context.Context) error {
	_, err := r.do("FLUSHDB")
	return err
}

// --- invites ---

const luaCreateInvite = `
if redis.call('EXISTS', KEYS[1]) == 1 then return 'conflict' end
redis.call('HSET', KEYS[1], 'state', 'open')
redis.call('PEXPIRE', KEYS[1], ARGV[1])
return 'ok'`

func (r *Redis) CreateInvite(_ context.Context, id string, ttl time.Duration) (time.Time, error) {
	res, err := r.eval(luaCreateInvite, []string{"inv:" + id}, ttl.Milliseconds())
	if err != nil {
		return time.Time{}, err
	}
	if asString(res) == "conflict" {
		return time.Time{}, ErrConflict
	}
	return time.Now().Add(ttl), nil
}

const luaJoinInvite = `
local state = redis.call('HGET', KEYS[1], 'state')
if not state then return 'nf' end
if state ~= 'open' then return 'gone' end
redis.call('HSET', KEYS[1], 'state', 'joined', 'join', ARGV[1])
return 'ok'`

func (r *Redis) JoinInvite(_ context.Context, id string, blob []byte) error {
	res, err := r.eval(luaJoinInvite, []string{"inv:" + id}, blob)
	if err != nil {
		return err
	}
	switch asString(res) {
	case "ok":
		return nil
	case "gone":
		return ErrGone
	default:
		return ErrNotFound
	}
}

// Proof pinning: field ARGV[1] ('fp' or 'gp') pins ARGV[2] on first use.
const luaPinSnippet = `
local pin = redis.call('HGET', KEYS[1], ARGV[1])
if not pin then
  redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
elseif pin ~= ARGV[2] then
  return {'bad'}
end`

const luaFetchJoin = `
local state = redis.call('HGET', KEYS[1], 'state')
if state ~= 'joined' then return {'nf'} end
local join = redis.call('HGET', KEYS[1], 'join')
if not join then return {'nf'} end
` + luaPinSnippet + `
return {'ok', join}`

func (r *Redis) FetchJoin(_ context.Context, id, proof string) ([]byte, error) {
	return r.gatedBlob(luaFetchJoin, id, "fp", proof)
}

const luaPutGrant = `
local state = redis.call('HGET', KEYS[1], 'state')
if state ~= 'joined' then return {'nf'} end
` + luaPinSnippet + `
redis.call('HSET', KEYS[1], 'grant', ARGV[3])
return {'ok'}`

func (r *Redis) PutGrant(_ context.Context, id, proof string, blob []byte) error {
	res, err := r.eval(luaPutGrant, []string{"inv:" + id}, "fp", proof, blob)
	if err != nil {
		return err
	}
	return statusOf(res)
}

const luaTakeGrant = `
local grant = redis.call('HGET', KEYS[1], 'grant')
if not grant then return {'nf'} end
` + luaPinSnippet + `
redis.call('HDEL', KEYS[1], 'grant')
return {'ok', grant}`

func (r *Redis) TakeGrant(_ context.Context, id, proof string) ([]byte, error) {
	return r.gatedBlob(luaTakeGrant, id, "gp", proof)
}

func (r *Redis) gatedBlob(script, id, pinField, proof string) ([]byte, error) {
	res, err := r.eval(script, []string{"inv:" + id}, pinField, proof)
	if err != nil {
		return nil, err
	}
	if err := statusOf(res); err != nil {
		return nil, err
	}
	arr := res.([]any)
	if len(arr) < 2 {
		return nil, errors.New("redis: gated blob reply missing payload")
	}
	blob, ok := arr[1].([]byte)
	if !ok {
		return nil, fmt.Errorf("redis: unexpected payload type %T", arr[1])
	}
	return blob, nil
}

// statusOf maps a Lua {status, ...} reply to a sentinel error.
func statusOf(res any) error {
	arr, ok := res.([]any)
	if !ok || len(arr) == 0 {
		return fmt.Errorf("redis: unexpected reply %T", res)
	}
	status, _ := arr[0].([]byte)
	switch string(status) {
	case "ok":
		return nil
	case "bad":
		return ErrProof
	case "gone":
		return ErrGone
	case "full":
		return ErrFull
	default:
		return ErrNotFound
	}
}

// --- mailbox ---

// luaNow is the server's clock in ms, and luaKeepAtLeast stretches a
// registry key's TTL to cover a member that lives ttl ms more.
const luaNow = `
local function nowMs()
  local t = redis.call('TIME')
  return tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
end
local function keepAtLeast(key, ttl)
  if redis.call('PTTL', key) < ttl then redis.call('PEXPIRE', key, ttl) end
end
`

// A push to an empty mailbox nobody owns opens a never-drained mailbox.
// KEYS: mbox:{id}, mboxo:{id}, fresh. ARGV: blob, depth, ttl, freshTTL,
// maxFresh, id, mayOpen. Reply {'ok', opened} or {'full'}.
const luaMailboxPush = luaNow + `
local now = nowMs()
local owned = redis.call('EXISTS', KEYS[2]) == 1
local len = redis.call('LLEN', KEYS[1])
local opened = 0
if len == 0 and not owned then
  if tonumber(ARGV[5]) > 0 then
    redis.call('ZREMRANGEBYSCORE', KEYS[3], '-inf', now)
    if not redis.call('ZSCORE', KEYS[3], ARGV[6])
       and redis.call('ZCARD', KEYS[3]) >= tonumber(ARGV[5]) then
      return {'full'}
    end
  end
  if ARGV[7] ~= '1' then return {'full'} end
  opened = 1
end
if len >= tonumber(ARGV[2]) then return {'full'} end
redis.call('RPUSH', KEYS[1], ARGV[1])
local ttl = tonumber(ARGV[3])
if not owned and tonumber(ARGV[4]) > 0 then ttl = tonumber(ARGV[4]) end
redis.call('PEXPIRE', KEYS[1], ttl)
if not owned then
  redis.call('ZADD', KEYS[3], now + ttl, ARGV[6])
  keepAtLeast(KEYS[3], ttl)
end
return {'ok', opened}`

func (r *Redis) MailboxPush(ctx context.Context, mailboxID string, blob []byte) error {
	mayOpen, settle := reserve(ctx)
	res, err := r.eval(luaMailboxPush,
		[]string{"mbox:" + mailboxID, "mboxo:" + mailboxID, "fresh"},
		blob, r.lim.MailboxDepth, r.lim.MailboxTTL.Milliseconds(),
		r.lim.MailboxFreshTTL.Milliseconds(), r.lim.MaxFreshMailboxes, mailboxID,
		mayOpen)
	if err != nil {
		settle(false)
		return err
	}
	settle(openedFlag(res, 1))
	return statusOf(res)
}

// The write comes first. A script is not rolled back when a later command
// fails, and a full Redis (noeviction) refuses SET: with the SET first, a
// refusal stops the script before the mail is touched, and the caller
// gets ErrOutOfMemory with every blob still stored. Nothing after the DEL
// can be refused for memory (ZREM only frees).
//
// The SET marks the mailbox owned. Owning one it did not own needs an
// opening (mayOpen); without one the mail still comes back, unowned.
// KEYS: mbox:{id}, mboxo:{id}, fresh. ARGV: ttl, id, mayOpen.
// Reply {opened, blobs}.
const luaMailboxDrain = `
local owned = redis.call('EXISTS', KEYS[2]) == 1
local opened = 0
if owned or ARGV[3] == '1' then
  redis.call('SET', KEYS[2], '1', 'PX', ARGV[1])
  if not owned then opened = 1 end
end
local blobs = redis.call('LRANGE', KEYS[1], 0, -1)
redis.call('DEL', KEYS[1])
redis.call('ZREM', KEYS[3], ARGV[2])
return {opened, blobs}`

func (r *Redis) MailboxDrain(ctx context.Context, mailboxID string) ([][]byte, error) {
	mayOpen, settle := reserve(ctx)
	res, err := r.eval(luaMailboxDrain,
		[]string{"mbox:" + mailboxID, "mboxo:" + mailboxID, "fresh"},
		r.lim.MailboxTTL.Milliseconds(), mailboxID, mayOpen)
	if err != nil {
		settle(false)
		return nil, err
	}
	reply, ok := res.([]any)
	if !ok || len(reply) != 2 {
		settle(false)
		return nil, fmt.Errorf("redis: drain reply %T", res)
	}
	opened, _ := reply[0].(int64)
	settle(opened == 1)
	arr, ok := reply[1].([]any)
	if !ok {
		return nil, fmt.Errorf("redis: drain blobs %T", reply[1])
	}
	out := make([][]byte, 0, len(arr))
	for _, v := range arr {
		b, ok := v.([]byte)
		if !ok {
			return nil, fmt.Errorf("redis: drain entry %T", v)
		}
		out = append(out, b)
	}
	return out, nil
}

// --- replay guard ---

func (r *Redis) ReplayCheck(_ context.Context, key string, ttl time.Duration) (bool, error) {
	res, err := r.do("SET", "replay:"+key, "1", "NX", "PX", ttl.Milliseconds())
	if err != nil {
		return false, err
	}
	s, _ := res.(string)
	return s == "OK", nil // null reply → already present → not fresh
}

// --- presence ---

// luaOpenChannel records in the chans ZSET that a channel lives ttl ms
// more. It refuses ('full') to open a new channel past max (0: no cap) or
// without an opening (mayOpen ~= '1'). slot is the presence slot writing,
// or the slot a bulletin write names, or ” for a bulletin write that names
// none; wkey (chw:{ch}) remembers the first slot,
// and '*' once a second slot has written. Until then the place lasts at
// most freshTTL (0: no limit). Returns 'ok', 'opened' or 'full'.
const luaOpenChannel = luaNow + `
local function openChannel(key, wkey, id, ttl, max, freshTTL, slot, mayOpen)
  local now = nowMs()
  local w = redis.call('GET', wkey)
  local confirmed = w and (w == '*' or (slot ~= '' and w ~= slot))
  local life = ttl
  if not confirmed and freshTTL > 0 and life > freshTTL then life = freshTTL end
  local status = 'ok'
  local exp = redis.call('ZSCORE', key, id)
  if exp and tonumber(exp) > now then
    if now + life > tonumber(exp) then redis.call('ZADD', key, now + life, id) end
  else
    if max > 0 then
      redis.call('ZREMRANGEBYSCORE', key, '-inf', now)
      if redis.call('ZCARD', key) >= max then return 'full' end
    end
    if mayOpen ~= '1' then return 'full' end
    redis.call('ZADD', key, now + life, id)
    status = 'opened'
  end
  keepAtLeast(key, life)
  local left = tonumber(redis.call('ZSCORE', key, id)) - now
  if confirmed then
    redis.call('SET', wkey, '*', 'PX', math.max(left, redis.call('PTTL', wkey)))
  elseif not w and slot ~= '' then
    redis.call('SET', wkey, slot, 'PX', left)
  elseif w then
    keepAtLeast(wkey, left)
  end
  return status
end
`

// KEYS: p:{ch}:{slot}, chans, chw:{ch}. ARGV: blob, ttl, ch, maxChannels,
// freshTTL, slot, mayOpen. Reply {'ok', opened} or {'full'}.
const luaPresenceSet = luaOpenChannel + `
local s = openChannel(KEYS[2], KEYS[3], ARGV[3], tonumber(ARGV[2]),
  tonumber(ARGV[4]), tonumber(ARGV[5]), ARGV[6], ARGV[7])
if s == 'full' then return {'full'} end
redis.call('SET', KEYS[1], ARGV[1], 'PX', ARGV[2])
if s == 'opened' then return {'ok', 1} end
return {'ok', 0}`

func (r *Redis) PresenceSet(ctx context.Context, channelID, slotID string, blob []byte, ttl time.Duration) error {
	mayOpen, settle := reserve(ctx)
	res, err := r.eval(luaPresenceSet,
		[]string{"p:" + channelID + ":" + slotID, "chans", "chw:" + channelID},
		blob, ttl.Milliseconds(), channelID, r.lim.MaxChannels,
		r.lim.ChannelFreshTTL.Milliseconds(), slotID, mayOpen)
	if err != nil {
		settle(false)
		return err
	}
	settle(openedFlag(res, 1))
	return statusOf(res)
}

func (r *Redis) PresenceList(_ context.Context, channelID string) ([]PresenceSlot, error) {
	prefix := "p:" + channelID + ":"
	keys, err := r.scan(prefix + "*")
	if err != nil {
		return nil, err
	}
	out := []PresenceSlot{}
	for _, k := range keys {
		blob, exp, err := r.getWithExpiry(k)
		if err != nil {
			return nil, err
		}
		if blob == nil {
			continue // expired between SCAN and GET
		}
		out = append(out, PresenceSlot{
			SlotID:    strings.TrimPrefix(k, prefix),
			Blob:      blob,
			ExpiresAt: exp,
		})
	}
	return out, nil
}

// --- bulletin ---

// KEYS: seq:{ch}, b:{ch}, chans, chw:{ch}. ARGV: blob, ringTTL, ringSize,
// ch, maxChannels, freshTTL, mayOpen, writer. Reply {seq, opened}, or -2:
// the channel cap or no opening.
const luaBulletinRing = luaOpenChannel + `
local s = openChannel(KEYS[3], KEYS[4], ARGV[4], tonumber(ARGV[2]),
  tonumber(ARGV[5]), tonumber(ARGV[6]), ARGV[8], ARGV[7])
if s == 'full' then return -2 end
local seq = redis.call('INCR', KEYS[1])
redis.call('PEXPIRE', KEYS[1], ARGV[2])
redis.call('RPUSH', KEYS[2], seq .. '|' .. ARGV[1])
redis.call('LTRIM', KEYS[2], -tonumber(ARGV[3]), -1)
redis.call('PEXPIRE', KEYS[2], ARGV[2])
if s == 'opened' then return {seq, 1} end
return {seq, 0}`

// luaBulletinPin prunes the live-pin index, enforces the cap, then pins.
// bp:* keys are computed inside the script: single-node Redis by design.
// KEYS: seq:{ch}, b:{ch}, bpi:{ch}, chans, chw:{ch}. ARGV: blob, ringTTL,
// pinCap, bp prefix, pinTTL, ch, maxChannels, freshTTL, mayOpen, writer.
// Reply {seq, opened}, or -1: the pin cap; -2: the channel cap or no
// opening.
const luaBulletinPin = luaOpenChannel + `
local life = math.max(tonumber(ARGV[2]), tonumber(ARGV[5]))
local s = openChannel(KEYS[4], KEYS[5], ARGV[6], life,
  tonumber(ARGV[7]), tonumber(ARGV[8]), ARGV[10], ARGV[9])
if s == 'full' then return -2 end
local live = {}
for _, s in ipairs(redis.call('ZRANGE', KEYS[3], 0, -1)) do
  if redis.call('EXISTS', ARGV[4] .. s) == 1 then
    live[#live + 1] = s
  else
    redis.call('ZREM', KEYS[3], s)
  end
end
if #live >= tonumber(ARGV[3]) then return -1 end
local seq = redis.call('INCR', KEYS[1])
redis.call('PEXPIRE', KEYS[1], ARGV[2])
redis.call('SET', ARGV[4] .. seq, ARGV[1], 'PX', ARGV[5])
redis.call('ZADD', KEYS[3], seq, seq)
redis.call('PEXPIRE', KEYS[3], ARGV[2])
if s == 'opened' then return {seq, 1} end
return {seq, 0}`

func (r *Redis) BulletinAppend(ctx context.Context, channelID, writer string, blob []byte, pinned bool, pinTTL time.Duration) (uint64, error) {
	ringTTL := r.lim.RingTTL.Milliseconds()
	freshTTL := r.lim.ChannelFreshTTL.Milliseconds()
	mayOpen, settle := reserve(ctx)
	var res any
	var err error
	if pinned {
		res, err = r.eval(luaBulletinPin,
			[]string{"seq:" + channelID, "b:" + channelID, "bpi:" + channelID, "chans", "chw:" + channelID},
			blob, ringTTL, r.lim.PinCap, "bp:"+channelID+":", pinTTL.Milliseconds(),
			channelID, r.lim.MaxChannels, freshTTL, mayOpen, writer)
	} else {
		res, err = r.eval(luaBulletinRing,
			[]string{"seq:" + channelID, "b:" + channelID, "chans", "chw:" + channelID},
			blob, ringTTL, r.lim.RingSize, channelID, r.lim.MaxChannels, freshTTL, mayOpen, writer)
	}
	if err != nil {
		settle(false)
		return 0, err
	}
	switch v := res.(type) {
	case int64: // -1 the pin cap, -2 the channel cap or no opening
		settle(false)
		return 0, ErrFull
	case []any:
		if len(v) == 2 {
			if seq, ok := v[0].(int64); ok {
				settle(openedFlag(res, 1))
				return uint64(seq), nil
			}
		}
	}
	settle(false)
	return 0, fmt.Errorf("redis: bulletin reply %#v", res)
}

func (r *Redis) BulletinList(_ context.Context, channelID string, afterSeq uint64) ([]BulletinEntry, error) {
	out := []BulletinEntry{}
	// Ring entries: "seq|rawblob".
	res, err := r.do("LRANGE", "b:"+channelID, 0, -1)
	if err != nil {
		return nil, err
	}
	if arr, ok := res.([]any); ok {
		for _, v := range arr {
			raw, ok := v.([]byte)
			if !ok {
				continue
			}
			i := indexByte(raw, '|')
			if i < 0 {
				continue
			}
			seq, err := strconv.ParseUint(string(raw[:i]), 10, 64)
			if err != nil {
				continue
			}
			if seq > afterSeq {
				out = append(out, BulletinEntry{Seq: seq, Blob: raw[i+1:]})
			}
		}
	}
	// Pinned entries via the index.
	idx, err := r.do("ZRANGE", "bpi:"+channelID, 0, -1)
	if err != nil {
		return nil, err
	}
	if arr, ok := idx.([]any); ok {
		for _, v := range arr {
			sb, ok := v.([]byte)
			if !ok {
				continue
			}
			seq, err := strconv.ParseUint(string(sb), 10, 64)
			if err != nil || seq <= afterSeq {
				continue
			}
			blob, exp, err := r.getWithExpiry("bp:" + channelID + ":" + string(sb))
			if err != nil {
				return nil, err
			}
			if blob == nil {
				continue // pin expired; index prunes on next append
			}
			out = append(out, BulletinEntry{Seq: seq, Blob: blob, Pinned: true, ExpiresAt: exp})
		}
	}
	sortEntries(out)
	return out, nil
}

// --- helpers ---

// reserve takes an opening from the ctx's Opener before a script that may
// open something. It returns the script's mayOpen flag, and settle, which
// gives the opening back unless the script reports it opened one. Call
// settle exactly once.
func reserve(ctx context.Context) (mayOpen string, settle func(opened bool)) {
	op := openerFrom(ctx)
	if !op.Take() {
		return "0", func(bool) {}
	}
	return "1", func(opened bool) {
		if !opened {
			op.Refund()
		}
	}
}

// openedFlag reports whether a script reply array holds 1 at index i.
func openedFlag(res any, i int) bool {
	arr, ok := res.([]any)
	if !ok || len(arr) <= i {
		return false
	}
	n, _ := arr[i].(int64)
	return n == 1
}

// do sends one command. A full Redis (maxmemory under noeviction) answers
// a write with an -OOM error, inside a script too: that becomes
// ErrOutOfMemory, so the relay can say "full" rather than "broken".
func (r *Redis) do(args ...any) (any, error) {
	res, err := r.c.Do(args...)
	var re respError
	if errors.As(err, &re) && strings.HasPrefix(string(re), "OOM ") {
		return nil, fmt.Errorf("%w: %v", ErrOutOfMemory, err)
	}
	return res, err
}

func (r *Redis) eval(script string, keys []string, argv ...any) (any, error) {
	args := make([]any, 0, 2+len(keys)+len(argv))
	args = append(args, "EVAL", script, len(keys))
	for _, k := range keys {
		args = append(args, k)
	}
	args = append(args, argv...)
	return r.do(args...)
}

func (r *Redis) getWithExpiry(key string) ([]byte, time.Time, error) {
	res, err := r.do("GET", key)
	if err != nil {
		return nil, time.Time{}, err
	}
	blob, _ := res.([]byte)
	if blob == nil {
		return nil, time.Time{}, nil
	}
	ttlRes, err := r.do("PTTL", key)
	if err != nil {
		return nil, time.Time{}, err
	}
	ms, _ := ttlRes.(int64)
	if ms < 0 {
		return nil, time.Time{}, nil // vanished or (impossible here) no TTL
	}
	return blob, time.Now().Add(time.Duration(ms) * time.Millisecond), nil
}

func (r *Redis) scan(pattern string) ([]string, error) {
	var keys []string
	cursor := "0"
	for {
		res, err := r.do("SCAN", cursor, "MATCH", pattern, "COUNT", 200)
		if err != nil {
			return nil, err
		}
		arr, ok := res.([]any)
		if !ok || len(arr) != 2 {
			return nil, fmt.Errorf("redis: scan reply %T", res)
		}
		cb, _ := arr[0].([]byte)
		cursor = string(cb)
		if batch, ok := arr[1].([]any); ok {
			for _, v := range batch {
				if kb, ok := v.([]byte); ok {
					keys = append(keys, string(kb))
				}
			}
		}
		if cursor == "0" {
			return keys, nil
		}
	}
}

// asString normalizes RESP replies: Lua string returns arrive as bulk
// strings ([]byte), status replies as string.
func asString(v any) string {
	switch s := v.(type) {
	case string:
		return s
	case []byte:
		return string(s)
	default:
		return ""
	}
}

func indexByte(b []byte, c byte) int {
	for i, v := range b {
		if v == c {
			return i
		}
	}
	return -1
}
