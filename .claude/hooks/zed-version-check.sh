#!/usr/bin/env bash
# SessionStart hook (read-only): Zed Preview changelog freshness check.
#
# Purpose: at every session start, (1) notice when a NEWER Zed Preview release exists
# than the version recorded in docs/ZED_PREVIEW_CHANGELOG.md, and (2) report the merge
# status of watched upstream PRs (e.g. #58755 per-window themes) so a merge is caught
# the session it lands. Then nudge the assistant to refresh that doc (UI / config /
# theme focus). The hook NEVER edits the doc and NEVER fetches/synthesizes the changelog
# itself -- a bash hook cannot web-search. It only checks state and prints instructions
# the assistant acts on that session.
#
# Guarantees (mirrors the read-only llmster version-check hook pattern):
#   - read-only   : no writes except a throwaway version cache in $TMPDIR
#   - fast        : local doc read + a 6h-cached single GitHub API call
#   - never blocks: always exits 0; degrades cleanly when offline or tools missing
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DOC="$PROJECT_DIR/docs/ZED_PREVIEW_CHANGELOG.md"
ZED_REPO="zed-industries/zed"

# Upstream PRs to watch for merge, checked live at every session start.
# Format: "<number>:<short label>". When a PR merges (or closes), the hook nudges the
# assistant to update the doc/memory and to drop it from this list once recorded.
WATCHED_PRS=(
  "58755:per-window theme overrides (per-project themes / zed#13300)"
)

# Numeric semver compare: returns 0 (true) if $1 > $2, else 1. Pure shell, no sort -V
# (BSD sort lacks it). Inputs must already be validated X.Y.Z.
version_gt() {
  [ "$1" = "$2" ] && return 1
  local IFS=. a b i x y
  a=($1); b=($2)
  for i in 0 1 2; do
    x=${a[i]:-0}; y=${b[i]:-0}
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 1
}

# pr_status <num> -> echoes "src|state|merged|updated|title" for a GitHub PR.
# Queries live (gh -> curl), refreshes a per-PR cache, and falls back to that cache when
# offline. src is live|cached|offline. Never fails (so the session is never blocked).
pr_status() {
  local num="$1" pc out
  pc="${TMPDIR:-/tmp}/zed-pr-${num}.cache"
  out=""
  if command -v gh >/dev/null 2>&1; then
    out=$(timeout 8 gh api "repos/$ZED_REPO/pulls/$num" \
      --jq '[.state, (.merged|tostring), (.updated_at|split("T")[0]), .title] | join("|")' 2>/dev/null || true)
  fi
  if [ -z "$out" ] && command -v jq >/dev/null 2>&1; then
    out=$(timeout 8 curl -fsSL "https://api.github.com/repos/$ZED_REPO/pulls/$num" 2>/dev/null \
      | jq -r '[.state, (.merged|tostring), (.updated_at|split("T")[0]), .title] | join("|")' 2>/dev/null || true)
  fi
  if [ -n "$out" ] && printf '%s' "$out" | grep -q '|'; then
    printf '%s\n' "$out" >"$pc" 2>/dev/null || true
    printf 'live|%s' "$out"
  elif [ -s "$pc" ]; then
    printf 'cached|%s' "$(cat "$pc" 2>/dev/null)"
  else
    printf 'offline||||'
  fi
}

# Doc missing -> nothing to compare against; note and bail (read-only).
if [ ! -f "$DOC" ]; then
  echo "🔎 Zed Preview check: docs/ZED_PREVIEW_CHANGELOG.md not found — skipped (read-only, nothing changed)."
  exit 0
fi

# Documented version = the marker line the assistant maintains in the doc.
documented=$(grep -oE 'ZED_PREVIEW_DOC_VERSION:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$DOC" 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$documented" ] && documented="(none recorded)"

# Latest available preview = newest GitHub prerelease tag (vX.Y.Z-pre -> X.Y.Z).
# Slow cold network call -> cache 6h. A changelog-tracking doc needs no fresher.
cache="${TMPDIR:-/tmp}/zed-preview-latest.cache"
ttl=21600
now=$(date +%s)
# Portable mtime. Try GNU stat (-c %Y) FIRST, then BSD/macOS stat (-f %m). Order is load-
# bearing: on Linux `-f` means --file-system (not "format"), so `stat -f %m "$cache"` runs in
# FILESYSTEM mode and prints a multi-line block starting with `  File: "..."` to stdout. That
# `File:` text lands in mtime (and if that stat also exits non-zero, the `||` fallback's number
# is merely appended after it) -- either way mtime is non-numeric, which crashed
# `$((now - mtime))` under `set -u` (bash re-evaluated the word `File` as an unset variable ->
# "File: unbound variable"). GNU-first avoids the garbage path entirely; the numeric guard is
# a backstop so the arithmetic below can never choke on any stat output.
mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
case "$mtime" in ''|*[!0-9]*) mtime=0;; esac
latest=""
if [ -s "$cache" ] && [ "$((now - mtime))" -lt "$ttl" ]; then
  latest=$(cat "$cache" 2>/dev/null)
else
  raw=""
  # Prefer gh (authenticated, higher rate limit); fall back to public curl.
  if command -v gh >/dev/null 2>&1; then
    raw=$(timeout 8 gh api 'repos/zed-industries/zed/releases?per_page=30' \
      --jq '.[] | select(.prerelease==true) | .tag_name' 2>/dev/null || true)
  fi
  if [ -z "$raw" ]; then
    json=$(timeout 8 curl -fsSL 'https://api.github.com/repos/zed-industries/zed/releases?per_page=30' 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
      raw=$(printf '%s' "$json" | jq -r '.[] | select(.prerelease==true) | .tag_name' 2>/dev/null || true)
    else
      raw=$(printf '%s' "$json" | grep -oE '"tag_name":[[:space:]]*"v[0-9.]+-pre"' | grep -oE 'v[0-9.]+-pre' || true)
    fi
  fi
  # Reduce tags to clean X.Y.Z, pick the true max (guards against late backports).
  for t in $(printf '%s\n' "$raw" | sed -E 's/^v//; s/-pre$//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'); do
    if [ -z "$latest" ] || version_gt "$t" "$latest"; then latest="$t"; fi
  done
  [ -n "$latest" ] && { printf '%s\n' "$latest" >"$cache" 2>/dev/null || true; }
fi

# Offline / unparseable -> note and bail (will retry next session).
if [ -z "$latest" ]; then
  echo "🔎 Zed Preview check: could not fetch latest release (offline/timeout) — doc records $documented. Will retry next session."
  exit 0
fi

# Optional, best-effort: installed Zed Preview version (macOS app bundle).
installed=""
plist="/Applications/Zed Preview.app/Contents/Info.plist"
if [ -f "$plist" ] && command -v defaults >/dev/null 2>&1; then
  installed=$(defaults read "${plist%.plist}" CFBundleShortVersionString 2>/dev/null || true)
fi

# Is the doc behind? Only compare when documented is a real semver.
newer_exists=0
if printf '%s' "$documented" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  version_gt "$latest" "$documented" && newer_exists=1
else
  newer_exists=1   # doc has no recorded version -> needs attention
fi

echo "🔎 Zed Preview changelog check (SessionStart · read-only)"
echo "   Doc records:      $documented   (docs/ZED_PREVIEW_CHANGELOG.md)"
echo "   Latest preview:   $latest   (GitHub zed-industries/zed, cached <=6h)"
[ -n "$installed" ] && echo "   Installed (Mac):  $installed   (/Applications/Zed Preview.app)"
echo

if [ "$newer_exists" -eq 1 ]; then
  echo "⚠️  A newer Zed Preview ($latest) exists than the doc records ($documented)."
  echo "    Assistant: refresh docs/ZED_PREVIEW_CHANGELOG.md this session —"
  echo "      1. WebFetch https://zed.dev/releases/preview/latest (+ any versions in between)."
  echo "      2. Capture UI / configuration / theme changes (introduced AND fixed)."
  echo "      3. Re-check standing watch-items (per-project themes / zed#13300, detect_venv)."
  echo "      4. Bump the <!-- ZED_PREVIEW_DOC_VERSION --> + LAST_UPDATED markers to $latest."
  echo "    (See the doc's 'Update runbook' section for the full procedure.)"
else
  echo "✅ Doc is current ($documented) — no newer preview release. Nothing to do."
fi

echo
echo "🔀 Watched Zed PRs (merge status · checked live each session):"
for entry in "${WATCHED_PRS[@]}"; do
  num="${entry%%:*}"; label="${entry#*:}"
  IFS='|' read -r src st mg upd _title <<<"$(pr_status "$num")"
  case "$mg" in
    true)
      echo "   ⭐ #$num MERGED — $label"
      echo "      Assistant: this PR merged. Update docs/ZED_PREVIEW_CHANGELOG.md + the"
      echo "      project_zed_per_project_theme memory (flip the watch-item to MERGED, note which"
      echo "      Preview release ships it, mark the --user-data-dir workaround obsolete), then"
      echo "      remove #$num from WATCHED_PRS in this hook so it stops being polled."
      ;;
    false)
      if [ "$st" = "closed" ]; then
        echo "   ✖ #$num CLOSED without merge — $label"
        echo "      Assistant: record the closure in the doc/memory and reassess the workaround."
      else
        echo "   ⏳ #$num still open (last activity ${upd:-?}) — $label   [${src}]"
      fi
      ;;
    *)
      echo "   • #$num status unavailable (${src:-offline}) — $label"
      ;;
  esac
done
exit 0
