#!/usr/bin/env bash
# retire-legacy-repos.sh - reviewable retirement script for old standalone
# OpenHearth per-app and per-library GitHub repositories after monorepo cutover.
#
# Defaults to DRY RUN: prints every action and touches nothing on GitHub.
#
# Modes:
#   (default)                  Dry-run only. Lists legacy repos and prints planned
#                              archive/pointer commands without calling mutations.
#   --archive                  Recommended first step: sets each legacy repo's
#                              description to point at the canonical monorepo and
#                              archives it read-only via `gh repo archive`.
#   --delete --confirm-delete  Permanent deletion via `gh repo delete`. Requires
#                              BOTH flags so deletion can never happen by accident.
#
# Options:
#   --owner NAME               GitHub owner (default: levitatingflyfisher)
#   --monorepo NAME            Canonical monorepo name (default: openhearth)
#   --check-remote             Query `gh repo view` read-only during dry-run to
#                              show which legacy repos currently exist on GitHub
#   -h, --help                 Show this help to stdout and exit 0
#
# Protected repositories (hard-blocked, NEVER retired by this script):
#   openhearth, openDaisugi, glean, levitatingflyfisher.github.io,
#   audioguardian, heritage, deseretBench, SurpriseMe, iss-skills,
#   PaperLantern, reckonBounty

set -euo pipefail

OWNER="levitatingflyfisher"
MONOREPO="openhearth"
MODE="dry-run"
CONFIRM_DELETE=0
CHECK_REMOTE=0

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)          [[ $# -ge 2 ]] || { echo "missing value for --owner" >&2; exit 2; }
                      OWNER="$2"; shift 2 ;;
    --monorepo)       [[ $# -ge 2 ]] || { echo "missing value for --monorepo" >&2; exit 2; }
                      MONOREPO="$2"; shift 2 ;;
    --archive)        MODE="archive"; shift ;;
    --delete)         MODE="delete"; shift ;;
    --confirm-delete) CONFIRM_DELETE=1; shift ;;
    --check-remote)   CHECK_REMOTE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$MODE" == "delete" && $CONFIRM_DELETE -ne 1 ]]; then
  echo "REFUSED: --delete requires explicit --confirm-delete flag." >&2
  echo "Tip: run dry-run first, and prefer --archive before permanent deletion." >&2
  exit 2
fi

MONOREPO_URL="https://github.com/${OWNER}/${MONOREPO}"

# Hard-coded denylist of repositories that MUST NEVER be archived or deleted.
PROTECTED_REPOS=(
  "openhearth"
  "openDaisugi"
  "glean"
  "levitatingflyfisher.github.io"
  "audioguardian"
  "heritage"
  "deseretBench"
  "SurpriseMe"
  "iss-skills"
  "PaperLantern"
  "reckonBounty"
)
if [[ "${MONOREPO,,}" != "openhearth" ]]; then
  PROTECTED_REPOS=("$MONOREPO" "${PROTECTED_REPOS[@]}")
fi

# Standalone legacy OpenHearth repos consolidated into the monorepo.
# Format: "<legacy_repo_name>|<monorepo_subpath>"
LEGACY_REPOS=(
  # 14 Flutter apps
  "Bulwark|apps/Bulwark"
  "Furrow|apps/Furrow"
  "WeatherGlass|apps/Glass"
  "Hatch|apps/Hatch"
  "Lilt|apps/Lilt"
  "Lullaby|apps/Lullaby"
  "Mantle|apps/Mantle"
  "Peckish|apps/Peckish"
  "Porch|apps/porch"
  "PunctumTemporis|apps/PunctumTemporis"
  "Reckon|apps/Reckon"
  "StillLife|apps/StillLife"
  "Sundial|apps/Sundial"
  "Trellis|apps/Trellis"
  # Shared libraries and native sync
  "DomovoiDiscernment|packages/domovoi"
  "eloEngine|packages/elo_engine"
  "ohStyle|packages/ohStyle"
  "sanctuaryAuthCore|packages/sanctuary_auth_core"
  "sanctuaryBackupUi|packages/sanctuary_backup_ui"
  "ohFleetConformance|packages/oh_fleet_conformance"
  "oh-packages|packages/"
  "hearthSync|native/hearthSync"
  # Web properties
  "NightGlass|web/NightGlass"
  "Parlour|web/Parlour"
  "ohSite|web/ohSite"
  # Retired predecessor
  "ohPrimer|apps/Trellis"
)

is_protected() {
  local candidate="$1" p
  for p in "${PROTECTED_REPOS[@]}"; do
    if [[ "${candidate,,}" == "${p,,}" ]]; then
      return 0
    fi
  done
  return 1
}

# Sanity-check list against denylist before doing anything
for entry in "${LEGACY_REPOS[@]}"; do
  repo="${entry%%|*}"
  if is_protected "$repo"; then
    echo "FATAL: protected repo '$repo' appeared in LEGACY_REPOS!" >&2
    exit 1
  fi
done

echo "=== OpenHearth Legacy Repo Retirement ==="
echo "  Owner:       $OWNER"
echo "  Monorepo:    $MONOREPO_URL"
echo "  Mode:        $MODE"
echo "  Legacy list: ${#LEGACY_REPOS[@]} repositories"
echo "  Protected:   ${PROTECTED_REPOS[*]}"
echo ""

if [[ "$MODE" != "dry-run" || $CHECK_REMOTE -eq 1 ]]; then
  command -v gh >/dev/null 2>&1 || { echo "gh CLI is required for remote operations" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh CLI is not authenticated (run: gh auth login)" >&2; exit 1; }
fi

for entry in "${LEGACY_REPOS[@]}"; do
  repo="${entry%%|*}"
  subpath="${entry#*|}"
  full="${OWNER}/${repo}"
  pointer_desc="Moved to OpenHearth monorepo: ${MONOREPO_URL}/tree/master/${subpath}"

  if [[ "$MODE" == "dry-run" ]]; then
    status_note="planned"
    if [[ $CHECK_REMOTE -eq 1 ]]; then
      if gh repo view "$full" --json isArchived,isPrivate --jq '"exists (private=\(.isPrivate), archived=\(.isArchived))"' 2>/dev/null; then
        status_note="checked"
      else
        status_note="not found on GitHub"
      fi
    fi
    printf '  [DRY-RUN] %-42s -> %-26s (%s)\n' "$full" "$subpath" "$status_note"
    printf '            archive cmd: gh repo edit %s --description "%s" && gh repo archive %s --yes\n' \
      "$full" "$pointer_desc" "$full"
  elif [[ "$MODE" == "archive" ]]; then
    if ! gh repo view "$full" >/dev/null 2>&1; then
      printf '  [SKIP]    %-42s (not found on GitHub)\n' "$full"
      continue
    fi
    printf '  [ARCHIVE] %-42s -> %s\n' "$full" "$subpath"
    gh repo edit "$full" --description "$pointer_desc" --homepage "${MONOREPO_URL}/tree/master/${subpath}"
    gh repo archive "$full" --yes
  elif [[ "$MODE" == "delete" ]]; then
    if ! gh repo view "$full" >/dev/null 2>&1; then
      printf '  [SKIP]    %-42s (not found on GitHub)\n' "$full"
      continue
    fi
    printf '  [DELETE]  %-42s\n' "$full"
    gh repo delete "$full" --yes
  fi
done

echo ""
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY RUN COMPLETE: zero GitHub repositories were modified."
  echo "Recommended next step after monorepo cutover is verified:"
  echo "  ./scripts/retire-legacy-repos.sh --check-remote"
  echo "  ./scripts/retire-legacy-repos.sh --archive"
fi
