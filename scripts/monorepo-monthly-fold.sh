#!/usr/bin/env bash
# monorepo-monthly-fold.sh - build a per-component midnight-UTC monthly commit
# chain for the OpenHearth monorepo.
#
# Policy:
#   - Every published commit is stamped YYYY-MM-01T00:00:00Z (midnight UTC on
#     the 1st of the month) for both author and committer dates.
#   - Every published commit uses the neutral persona:
#       OpenHearth Development <90985475+levitatingflyfisher@users.noreply.github.com>
#   - First fold (no frozen monthly anchor in history):
#       1) Base commit: workspace root + packages/* + native/* + web/* + docs/ + scripts/ + .github/
#       2) One commit per app directory under apps/* (sorted case-insensitively)
#   - Incremental fold (after the last frozen monthly anchor):
#       Splits changed paths since the last anchor by top-level component
#       (workspace, packages/<Pkg>, native/<Lib>, web/<Site>, apps/<App>) so
#       only components touched that month receive a commit on YYYY-MM-01T00:00:00Z.
#   - Always writes a full local git bundle backup BEFORE touching any ref.
#   - Audits zero AI attribution lines, zero forbidden files (CLAUDE.md, .env,
#     docs/superpowers), and zero personal /home/ or /Users/ path leaks.
#   - Asserts final tree is 100% byte-identical to HEAD and every commit in the
#     resulting branch matches the exact persona and YYYY-MM-01T00:00:00Z shape.
#
# Usage:
#   monorepo-monthly-fold.sh [options]
#     --month YYYY-MM      Target UTC month (default: current UTC month)
#     --branch NAME        Branch to fold (default: current checked-out branch)
#     --repo DIR           Monorepo path (default: parent dir of scripts/)
#     --backup-dir DIR     Local backup bundle dir (default: ~/openhearth-backups)
#     --execute            Update local branch ref (and push to origin if set,
#                          unless --no-push is passed). Default is DRY RUN.
#     --no-push            With --execute, update local branch only (no push)
#     --keep-workdir       Keep temporary mirror directory after exit
#     -h, --help           Show this help to stdout and exit 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="${OH_BACKUP_DIR:-$HOME/openhearth-backups}"
MONTH="$(TZ=UTC date '+%Y-%m')"
BRANCH=""
EXECUTE=0
NO_PUSH=0
KEEP_WORKDIR=0

AUTHOR_NAME="OpenHearth Development"
AUTHOR_EMAIL="90985475+levitatingflyfisher@users.noreply.github.com"
PERSONA="$AUTHOR_NAME <$AUTHOR_EMAIL>"

usage() {
  sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --month)        [[ $# -ge 2 ]] || { echo "missing value for --month" >&2; exit 2; }
                    MONTH="$2"; shift 2 ;;
    --branch)       [[ $# -ge 2 ]] || { echo "missing value for --branch" >&2; exit 2; }
                    BRANCH="$2"; shift 2 ;;
    --repo)         [[ $# -ge 2 ]] || { echo "missing value for --repo" >&2; exit 2; }
                    REPO_DIR="$2"; shift 2 ;;
    --backup-dir)   [[ $# -ge 2 ]] || { echo "missing value for --backup-dir" >&2; exit 2; }
                    BACKUP_DIR="$2"; shift 2 ;;
    --execute)      EXECUTE=1; shift ;;
    --no-push)      NO_PUSH=1; shift ;;
    --keep-workdir) KEEP_WORKDIR=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! "$MONTH" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
  echo "invalid --month '$MONTH': expected YYYY-MM" >&2
  exit 2
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"
git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "not a git repository: $REPO_DIR" >&2
  exit 1
}

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD || true)"
  [[ -n "$BRANCH" ]] || { echo "detached HEAD: pass --branch NAME" >&2; exit 2; }
fi

git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH" || {
  echo "branch does not exist: $BRANCH" >&2
  exit 1
}

# Refuse to fold with a dirty working tree so HEAD represents everything cleanly.
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
  echo "REFUSED: working tree in $REPO_DIR has uncommitted changes." >&2
  echo "Commit or stash changes before running monorepo-monthly-fold.sh." >&2
  exit 1
fi

STAMP="${MONTH}-01T00:00:00Z"
MONTH_LABEL="$(TZ=UTC date -d "${MONTH}-01" '+%B %Y')"
ORIG_HEAD="$(git -C "$REPO_DIR" rev-parse "refs/heads/$BRANCH")"
SHORT_SHA="$(git -C "$REPO_DIR" rev-parse --short "$ORIG_HEAD")"
TODAY_UTC="$(TZ=UTC date '+%Y%m%d')"

mkdir -p "$BACKUP_DIR"
BUNDLE_PATH="$BACKUP_DIR/openhearth-pre-monthly-${SHORT_SHA}-${TODAY_UTC}.bundle"

echo "=== OpenHearth Monorepo Monthly Fold ==="
echo "  Repo:      $REPO_DIR"
echo "  Branch:    $BRANCH ($SHORT_SHA)"
echo "  Month:     $MONTH ($MONTH_LABEL) -> $STAMP"
echo "  Author:    $PERSONA"
echo "  Mode:      $([[ $EXECUTE -eq 1 ]] && echo 'EXECUTE' || echo 'DRY RUN')"

# ---------------------------------------------------------------------------
# 1. Mandatory pre-flight backup bundle (local only, never pushed)
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Creating full local backup bundle..."
git -C "$REPO_DIR" bundle create -q "$BUNDLE_PATH" --all
git -C "$REPO_DIR" bundle verify -q "$BUNDLE_PATH"
echo "  OK: $BUNDLE_PATH"

# ---------------------------------------------------------------------------
# 2. Hygiene & leak audits against HEAD and all refs
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Running hygiene, attribution, and leak audits..."

AUDIT_FAIL=0

# 2a. Zero AI attribution lines in git commit metadata across all refs
ATTR_PAT="noreply@""anthropic\.com|co-authored-""by:.*(claude|anthropic|openai|gemini|copilot)|claude\.ai""/code|generated with .*(claude|ai|llm)|generated by (claude|anthropic|ai)"
if git -C "$REPO_DIR" log --all --format='%H %an %ae %cn %ce %s %b' | grep -inE "$ATTR_PAT" >/dev/null 2>&1; then
  echo "  FAIL: AI attribution found in commit history:" >&2
  git -C "$REPO_DIR" log --all --format='%H %an %ae %cn %ce %s' | grep -inE "$ATTR_PAT" | head -n 20 >&2
  AUDIT_FAIL=1
else
  echo "  OK: zero AI attribution lines in commit history"
fi

# 2b. Zero forbidden tracked files (CLAUDE.md, .env, docs/superpowers, build artifacts, keys)
FORBIDDEN_FILES="$(git -C "$REPO_DIR" ls-tree -r --name-only "$ORIG_HEAD" \
  | grep -iE '(^|/)claude\.md$|(^|/)\.env($|\.)|(^|/)docs/superpowers(/|$)|(^|/)local\.properties$|(^|/)key\.properties$' || true)"
if [[ -n "$FORBIDDEN_FILES" ]]; then
  echo "  FAIL: forbidden tracked files present in $BRANCH:" >&2
  printf '%s\n' "$FORBIDDEN_FILES" | sed 's/^/    /' >&2
  AUDIT_FAIL=1
else
  echo "  OK: zero CLAUDE.md, .env, docs/superpowers, or local/key.properties files tracked"
fi

# 2c. Zero personal /home/<user>/ or /Users/<user>/ host path leaks in tracked files
# Exclude the single known upstream build-source URL embedded in vendored ffmpeg.js.
VENDOR_FFMPEG_URL="file:///ho""me/jeromewu/ffmpeg\.wasm/"
HOME_LEAKS="$(git -C "$REPO_DIR" grep -nE '(^|[^[:alnum:]_./-])(/home/[a-zA-Z0-9._-]+/|/Users/[a-zA-Z0-9._-]+/)' "$ORIG_HEAD" \
  | grep -v "apps/PunctumTemporis/web/ffmpeg/ffmpeg.js:.*${VENDOR_FFMPEG_URL}" || true)"
if [[ -n "$HOME_LEAKS" ]]; then
  echo "  FAIL: personal filesystem path leaks found in tracked files:" >&2
  printf '%s\n' "$HOME_LEAKS" | head -n 20 | sed 's/^/    /' >&2
  AUDIT_FAIL=1
else
  echo "  OK: zero personal /home/ or /Users/ path leaks in tracked files"
fi

# 2d. Zero AI attribution trailers in tracked source/docs
FILE_ATTR_PAT="noreply@""anthropic\.com|co-authored-""by:.*(claude|anthropic|openai|gemini|copilot)|claude\.ai""/code"
FILE_ATTR_LEAKS="$(git -C "$REPO_DIR" grep -inE "$FILE_ATTR_PAT" "$ORIG_HEAD" || true)"
if [[ -n "$FILE_ATTR_LEAKS" ]]; then
  echo "  FAIL: AI attribution markers found in tracked files:" >&2
  printf '%s\n' "$FILE_ATTR_LEAKS" | head -n 20 | sed 's/^/    /' >&2
  AUDIT_FAIL=1
else
  echo "  OK: zero AI attribution trailers in tracked files"
fi

if [[ $AUDIT_FAIL -ne 0 ]]; then
  echo "ABORTED: audit failed. Fix findings above before folding." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Clone into temporary bare mirror so dry-run leaves live repo untouched
# ---------------------------------------------------------------------------
WORKDIR="$(mktemp -d /tmp/openhearth-monthly-fold.XXXXXX)"
cleanup() {
  if [[ $KEEP_WORKDIR -eq 0 ]]; then
    rm -rf "$WORKDIR"
  else
    echo "  Workdir preserved at: $WORKDIR"
  fi
}
trap cleanup EXIT

MIRROR="$WORKDIR/openhearth.git"
TMP_INDEX="$WORKDIR/fold.index"
git clone --mirror -q "$REPO_DIR" "$MIRROR"

EM_DASH="$(printf '\xe2\x80\x94')"
EN_DASH="$(printf '\xe2\x80\x93')"

# Helper: sanitize em-dashes/en-dashes to plain ASCII hyphens in commit messages
sanitize_msg() {
  sed -e "s/${EM_DASH}/ - /g" -e "s/${EN_DASH}/-/g" -e 's/  */ /g' -e 's/^ //; s/ $//'
}

# Helper: true if commit already matches frozen midnight-UTC monthly shape
is_anchor() {
  local c="$1" ad cd an ae cn ce
  ad="$(TZ=UTC git -C "$MIRROR" log -1 --date=format-local:'%d %H%M%S' --format='%ad' "$c")"
  cd="$(TZ=UTC git -C "$MIRROR" log -1 --date=format-local:'%d %H%M%S' --format='%cd' "$c")"
  an="$(git -C "$MIRROR" log -1 --format='%an' "$c")"
  ae="$(git -C "$MIRROR" log -1 --format='%ae' "$c")"
  cn="$(git -C "$MIRROR" log -1 --format='%cn' "$c")"
  ce="$(git -C "$MIRROR" log -1 --format='%ce' "$c")"
  [[ "$ad" == "01 000000" && "$cd" == "01 000000" && \
     "$an" == "$AUTHOR_NAME" && "$ae" == "$AUTHOR_EMAIL" && \
     "$cn" == "$AUTHOR_NAME" && "$ce" == "$AUTHOR_EMAIL" ]]
}

# Helper: extract concise one-line description for an app from pubspec.yaml in ORIG_HEAD
app_description() {
  local app="$1" pubspec_path="" raw=""
  if git -C "$MIRROR" cat-file -e "${ORIG_HEAD}:apps/${app}/pubspec.yaml" 2>/dev/null; then
    pubspec_path="apps/${app}/pubspec.yaml"
  elif git -C "$MIRROR" cat-file -e "${ORIG_HEAD}:apps/${app}/app/pubspec.yaml" 2>/dev/null; then
    pubspec_path="apps/${app}/app/pubspec.yaml"
  fi
  if [[ -n "$pubspec_path" ]]; then
    raw="$(git -C "$MIRROR" show "${ORIG_HEAD}:${pubspec_path}" \
      | awk '/^description:/ {sub(/^description:[[:space:]]*/, ""); print; exit}' \
      | sed -e "s/^['\"]//; s/['\"]$//" -e 's/\\u2014/ - /g' -e 's/\\$//' \
      | sanitize_msg)"
  fi
  printf '%s' "$raw"
}

# Helper: mint a commit stamped YYYY-MM-01T00:00:00Z under neutral persona
mint_commit() {
  local tree="$1" parent="$2" msg="$3"
  local clean_msg
  clean_msg="$(printf '%s\n' "$msg" | sed -e "s/${EM_DASH}/ - /g" -e "s/${EN_DASH}/-/g")"
  GIT_AUTHOR_NAME="$AUTHOR_NAME" \
  GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
  GIT_COMMITTER_NAME="$AUTHOR_NAME" \
  GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
  GIT_AUTHOR_DATE="$STAMP" \
  GIT_COMMITTER_DATE="$STAMP" \
  git -C "$MIRROR" commit-tree "$tree" ${parent:+-p "$parent"} -m "$clean_msg"
}

# ---------------------------------------------------------------------------
# 4. Build per-component midnight-UTC commit chain
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Building per-component monthly commit chain..."

mapfile -t COMMITS < <(git -C "$MIRROR" rev-list --reverse --first-parent "refs/heads/$BRANCH")
ANCHOR=""
START_IDX=0
for i in "${!COMMITS[@]}"; do
  if is_anchor "${COMMITS[$i]}"; then
    ANCHOR="${COMMITS[$i]}"
    START_IDX=$((i + 1))
  fi
done

if [[ $START_IDX -ge ${#COMMITS[@]} ]]; then
  echo "  Already fully folded (${#COMMITS[@]} midnight-UTC commits) - nothing to do."
  exit 0
fi

MINTED=()
PARENT="$ANCHOR"

if [[ -z "$ANCHOR" ]]; then
  echo "  Strategy: initial per-app monthly fold (${#COMMITS[@]} source commits -> base + per-app commits)"

  # 4a. Base commit: everything in ORIG_HEAD except apps/*
  rm -f "$TMP_INDEX"
  git -C "$MIRROR" ls-tree -r "$ORIG_HEAD" \
    | awk -F'\t' '$2 !~ /^"?apps\//' \
    | GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" update-index --index-info
  BASE_TREE="$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" write-tree)"

  BASE_SUBJECTS="$(git -C "$MIRROR" log --reverse --format='- %s' "$ORIG_HEAD" -- \
    ':!apps/' | sanitize_msg || true)"
  BASE_MSG="OpenHearth workspace & shared libraries (${MONTH_LABEL})"$'\n\n'"Root Dart Pub Workspace, shared libraries (packages/*), native/hearthSync, web/*, docs/, scripts/, and CI workflows."
  if [[ -n "$BASE_SUBJECTS" ]]; then
    BASE_MSG+=$'\n\n'"Included changes:"$'\n'"$BASE_SUBJECTS"
  fi

  PARENT="$(mint_commit "$BASE_TREE" "" "$BASE_MSG")"
  MINTED+=("$PARENT")
  printf '  + %-24s -> %s (%s)\n' "workspace+shared" "$(git -C "$MIRROR" rev-parse --short "$PARENT")" "$STAMP"

  # 4b. One commit per app directory under apps/* (sorted case-insensitively)
  mapfile -t APPS < <(git -C "$MIRROR" ls-tree --name-only "$ORIG_HEAD" apps/ \
    | sed 's|^apps/||' | LC_ALL=C sort -f)

  for app in "${APPS[@]}"; do
    [[ -n "$app" ]] || continue
    git -C "$MIRROR" ls-tree -r "$ORIG_HEAD" -- "apps/${app}/" \
      | GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" update-index --index-info
    APP_TREE="$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" write-tree)"

    DESC="$(app_description "$app")"
    # Collect commits touching this app (prefer specific commits over root init if present)
    ALL_APP_SUBJ="$(git -C "$MIRROR" log --reverse --format='- %s' "$ORIG_HEAD" -- "apps/${app}" | sanitize_msg || true)"
    SPECIFIC_SUBJ="$(printf '%s\n' "$ALL_APP_SUBJ" | grep -vE '^- Initialize OpenHearth Flutter monorepo' || true)"

    APP_MSG="apps/${app}: monthly fold (${MONTH_LABEL})"
    if [[ -n "$DESC" ]]; then
      APP_MSG+=$'\n\n'"$DESC"
    fi
    if [[ -n "$SPECIFIC_SUBJ" ]]; then
      APP_MSG+=$'\n\n'"Included changes:"$'\n'"$SPECIFIC_SUBJ"
    else
      APP_MSG+=$'\n\n'"- Initial monorepo snapshot of apps/${app}"
    fi

    PARENT="$(mint_commit "$APP_TREE" "$PARENT" "$APP_MSG")"
    MINTED+=("$PARENT")
    printf '  + %-24s -> %s (%s)\n' "apps/${app}" "$(git -C "$MIRROR" rev-parse --short "$PARENT")" "$STAMP"
  done
else
  echo "  Strategy: incremental per-component monthly fold since anchor $(git -C "$MIRROR" rev-parse --short "$ANCHOR")"

  # Guard: target month must not predate the last frozen anchor's month
  ANCHOR_MONTH="$(TZ=UTC git -C "$MIRROR" log -1 --date=format-local:'%Y-%m' --format='%ad' "$ANCHOR")"
  if [[ "$MONTH" < "$ANCHOR_MONTH" ]]; then
    echo "REFUSED: target month $MONTH predates last anchor month $ANCHOR_MONTH" >&2
    exit 1
  fi

  mapfile -t CHANGED_FILES < <(git -C "$MIRROR" -c core.quotePath=false diff --name-only "$ANCHOR" "$ORIG_HEAD")
  if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    echo "  No tree changes since anchor $(git -C "$MIRROR" rev-parse --short "$ANCHOR") - nothing to fold."
    exit 0
  fi

  declare -A SEEN_COMP=()
  WORKSPACE_TOUCHED=0
  PKG_COMPS=()
  NATIVE_COMPS=()
  WEB_COMPS=()
  APP_COMPS=()

  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in
      apps/*/*)
        c="apps/$(printf '%s' "${f#apps/}" | cut -d/ -f1)"
        if [[ -z "${SEEN_COMP[$c]:-}" ]]; then SEEN_COMP["$c"]=1; APP_COMPS+=("$c"); fi ;;
      packages/*/*)
        c="packages/$(printf '%s' "${f#packages/}" | cut -d/ -f1)"
        if [[ -z "${SEEN_COMP[$c]:-}" ]]; then SEEN_COMP["$c"]=1; PKG_COMPS+=("$c"); fi ;;
      native/*/*)
        c="native/$(printf '%s' "${f#native/}" | cut -d/ -f1)"
        if [[ -z "${SEEN_COMP[$c]:-}" ]]; then SEEN_COMP["$c"]=1; NATIVE_COMPS+=("$c"); fi ;;
      web/*/*)
        c="web/$(printf '%s' "${f#web/}" | cut -d/ -f1)"
        if [[ -z "${SEEN_COMP[$c]:-}" ]]; then SEEN_COMP["$c"]=1; WEB_COMPS+=("$c"); fi ;;
      *)
        WORKSPACE_TOUCHED=1 ;;
    esac
  done

  ORDERED_COMPS=()
  [[ $WORKSPACE_TOUCHED -eq 1 ]] && ORDERED_COMPS+=("workspace")
  if [[ ${#PKG_COMPS[@]} -gt 0 ]]; then
    mapfile -t PKG_COMPS < <(printf '%s\n' "${PKG_COMPS[@]}" | LC_ALL=C sort -f)
    ORDERED_COMPS+=("${PKG_COMPS[@]}")
  fi
  if [[ ${#NATIVE_COMPS[@]} -gt 0 ]]; then
    mapfile -t NATIVE_COMPS < <(printf '%s\n' "${NATIVE_COMPS[@]}" | LC_ALL=C sort -f)
    ORDERED_COMPS+=("${NATIVE_COMPS[@]}")
  fi
  if [[ ${#WEB_COMPS[@]} -gt 0 ]]; then
    mapfile -t WEB_COMPS < <(printf '%s\n' "${WEB_COMPS[@]}" | LC_ALL=C sort -f)
    ORDERED_COMPS+=("${WEB_COMPS[@]}")
  fi
  if [[ ${#APP_COMPS[@]} -gt 0 ]]; then
    mapfile -t APP_COMPS < <(printf '%s\n' "${APP_COMPS[@]}" | LC_ALL=C sort -f)
    ORDERED_COMPS+=("${APP_COMPS[@]}")
  fi

  rm -f "$TMP_INDEX"
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" read-tree "$ANCHOR"

  apply_changed_file() {
    local f="$1" line del_path
    line="$(git -C "$MIRROR" ls-tree -r "$ORIG_HEAD" -- "$f")"
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line" | GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" update-index --index-info
    else
      del_path="$(git -C "$MIRROR" ls-tree -r "$ANCHOR" -- "$f" | cut -f2-)"
      printf '0 0000000000000000000000000000000000000000\t%s\n' "$del_path" \
        | GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" update-index --index-info
    fi
  }

  for comp in "${ORDERED_COMPS[@]}"; do
    if [[ "$comp" == "workspace" ]]; then
      for f in "${CHANGED_FILES[@]}"; do
        case "$f" in
          apps/*/*|packages/*/*|native/*/*|web/*/*) continue ;;
        esac
        apply_changed_file "$f"
      done
      SUBJ="$(git -C "$MIRROR" log --reverse --format='- %s' "${ANCHOR}..${ORIG_HEAD}" -- \
        ':!apps/' ':!packages/' ':!native/' ':!web/' | sanitize_msg || true)"
      TITLE="OpenHearth workspace (${MONTH_LABEL})"
    else
      for f in "${CHANGED_FILES[@]}"; do
        case "$f" in
          "${comp}/"*) apply_changed_file "$f" ;;
        esac
      done
      SUBJ="$(git -C "$MIRROR" log --reverse --format='- %s' "${ANCHOR}..${ORIG_HEAD}" -- "$comp" | sanitize_msg || true)"
      TITLE="${comp}: monthly fold (${MONTH_LABEL})"
    fi

    NEXT_TREE="$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$MIRROR" write-tree)"
    PREV_TREE="$(git -C "$MIRROR" rev-parse "${PARENT}^{tree}")"
    if [[ "$NEXT_TREE" == "$PREV_TREE" ]]; then
      continue
    fi

    COMP_MSG="$TITLE"
    if [[ -n "$SUBJ" ]]; then
      COMP_MSG+=$'\n\n'"Included changes:"$'\n'"$SUBJ"
    fi

    PARENT="$(mint_commit "$NEXT_TREE" "$PARENT" "$COMP_MSG")"
    MINTED+=("$PARENT")
    printf '  + %-24s -> %s (%s)\n' "$comp" "$(git -C "$MIRROR" rev-parse --short "$PARENT")" "$STAMP"
  done
fi

NEW_TIP="$PARENT"

# ---------------------------------------------------------------------------
# 5. Strict verification assertions (tree equality + metadata on every commit)
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Verifying tree byte-identity and commit metadata..."

# 5a. Byte-identical tree proof
if ! git -C "$MIRROR" diff --quiet "$ORIG_HEAD" "$NEW_TIP"; then
  echo "  FATAL: folded tip tree differs from original HEAD!" >&2
  git -C "$MIRROR" diff --stat "$ORIG_HEAD" "$NEW_TIP" >&2
  exit 1
fi
ORIG_TREE="$(git -C "$MIRROR" rev-parse "${ORIG_HEAD}^{tree}")"
NEW_TREE="$(git -C "$MIRROR" rev-parse "${NEW_TIP}^{tree}")"
if [[ "$ORIG_TREE" != "$NEW_TREE" ]]; then
  echo "  FATAL: tree OID mismatch ($ORIG_TREE != $NEW_TREE)" >&2
  exit 1
fi
echo "  OK: git diff --quiet HEAD new_tip passed (tree OID $NEW_TREE)"

# 5b. Every commit in the resulting branch matches persona + YYYY-MM-01T00:00:00Z + zero em-dash/attribution
VERIFY_FAIL=0
while IFS=$'\t' read -r c an ae cn ce ad cd subj; do
  if [[ "$an" != "$AUTHOR_NAME" || "$ae" != "$AUTHOR_EMAIL" || "$cn" != "$AUTHOR_NAME" || "$ce" != "$AUTHOR_EMAIL" ]]; then
    echo "  FAIL: wrong identity on $c: $an <$ae> / $cn <$ce>" >&2
    VERIFY_FAIL=1
  fi
  if [[ ! "$ad" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-01T00:00:00Z$ || ! "$cd" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-01T00:00:00Z$ ]]; then
    echo "  FAIL: non-midnight-UTC date on $c: author=$ad committer=$cd" >&2
    VERIFY_FAIL=1
  fi
  if git -C "$MIRROR" log -1 --format='%B' "$c" | grep -q "$EM_DASH"; then
    echo "  FAIL: em-dash found in commit message of $c" >&2
    VERIFY_FAIL=1
  fi
  if git -C "$MIRROR" log -1 --format='%B' "$c" | grep -iqE "$ATTR_PAT"; then
    echo "  FAIL: attribution string found in commit message of $c" >&2
    VERIFY_FAIL=1
  fi
done < <(TZ=UTC git -C "$MIRROR" log --reverse --date=format-local:'%Y-%m-%dT%H:%M:%SZ' \
  --format='%H%x09%an%x09%ae%x09%cn%x09%ce%x09%ad%x09%cd%x09%s' "$NEW_TIP")

# Also assert every newly minted commit has exact target STAMP
for mc in "${MINTED[@]}"; do
  mad="$(TZ=UTC git -C "$MIRROR" log -1 --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%ad' "$mc")"
  mcd="$(TZ=UTC git -C "$MIRROR" log -1 --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%cd' "$mc")"
  if [[ "$mad" != "$STAMP" || "$mcd" != "$STAMP" ]]; then
    echo "  FAIL: minted commit $mc has date $mad / $mcd (expected $STAMP)" >&2
    VERIFY_FAIL=1
  fi
done

if [[ $VERIFY_FAIL -ne 0 ]]; then
  echo "ABORTED: verification failed." >&2
  exit 1
fi
TOTAL_NEW="$(git -C "$MIRROR" rev-list --count "$NEW_TIP")"
echo "  OK: all $TOTAL_NEW commits verified (persona + YYYY-MM-01T00:00:00Z + clean messages)"

# Print summary table of resulting commit chain
echo ""
echo "[5/5] Resulting commit chain on '$BRANCH':"
TZ=UTC git -C "$MIRROR" log --reverse --date=format-local:'%Y-%m-%dT%H:%M:%SZ' \
  --format='  %h | %ad | %cd | %an <%ae> | %s' "$NEW_TIP"

if [[ $EXECUTE -eq 0 ]]; then
  echo ""
  echo "DRY RUN COMPLETE: no refs modified and nothing pushed."
  echo "Backup bundle saved at: $BUNDLE_PATH"
  echo "Re-run with --execute --no-push (local rewrite) or --execute (rewrite + push)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Execute mode: transfer verified objects into source repo and update branch
# ---------------------------------------------------------------------------
echo ""
echo "Executing local branch rewrite on $REPO_DIR ($BRANCH)..."
git -C "$MIRROR" update-ref "refs/heads/$BRANCH" "$NEW_TIP"
git -C "$REPO_DIR" fetch -q "$MIRROR" "refs/heads/$BRANCH:refs/tmp/monthly-fold-$BRANCH"
FOLDED_IN_REPO="$(git -C "$REPO_DIR" rev-parse "refs/tmp/monthly-fold-$BRANCH")"

# Re-verify byte-identical tree inside the live repository before updating HEAD ref
git -C "$REPO_DIR" diff --quiet "$ORIG_HEAD" "$FOLDED_IN_REPO"
git -C "$REPO_DIR" update-ref "refs/heads/$BRANCH" "$FOLDED_IN_REPO" "$ORIG_HEAD"
git -C "$REPO_DIR" update-ref -d "refs/tmp/monthly-fold-$BRANCH"
echo "  OK: updated refs/heads/$BRANCH -> $(git -C "$REPO_DIR" rev-parse --short "$FOLDED_IN_REPO")"

if [[ $NO_PUSH -eq 1 ]]; then
  echo "  --no-push set: skipped remote push."
  exit 0
fi

if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
  git -C "$REPO_DIR" fetch -q origin "$BRANCH" || true
  REMOTE_REF="refs/remotes/origin/$BRANCH"
  if git -C "$REPO_DIR" show-ref --verify --quiet "$REMOTE_REF"; then
    REMOTE_SHA="$(git -C "$REPO_DIR" rev-parse "$REMOTE_REF")"
    if ! git -C "$REPO_DIR" merge-base --is-ancestor "$REMOTE_SHA" "$ORIG_HEAD"; then
      echo "  REFUSED PUSH: origin/$BRANCH ($REMOTE_SHA) has commits not in pre-fold HEAD ($ORIG_HEAD)." >&2
      echo "  Local branch was rewritten, but push was aborted for safety." >&2
      exit 1
    fi
    git -C "$REPO_DIR" push --force-with-lease="refs/heads/$BRANCH:$REMOTE_SHA" origin "refs/heads/$BRANCH"
  else
    git -C "$REPO_DIR" push -u origin "refs/heads/$BRANCH"
  fi
  echo "  OK: pushed $BRANCH to origin."
else
  echo "  NOTE: no 'origin' remote configured; local branch updated only."
fi
