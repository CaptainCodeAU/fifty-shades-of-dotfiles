#!/usr/bin/env bash
# SessionStart hook (read-only): is a herdr upgrade eligible under the 7-day
# release cooldown, and are the guards that enforce it still in place?
#
# Purpose: herdr is the one tool in this estate that can move on its own --
# it ships a self-updater plus TWO default-on background calls to herdr.dev
# (update.version_check, and update.manifest_check which reloads remote
# agent-detection manifests into the RUNNING server). pnpm/bun/uv all have a
# native minimumReleaseAge knob; herdr has none. This hook runs the standalone
# `herdr-cooldown-check` tool each session so that (a) an eligible upgrade is
# surfaced the session it ages past the gate, and (b) a dropped guard (formula
# unpinned, phone-home re-enabled) is caught rather than assumed. The hook
# NEVER edits, pins, or upgrades anything.
#
# Guarantees (mirrors toolchain-cve-check.sh):
#   - read-only   : no writes except a throwaway verdict cache in $TMPDIR
#   - fast        : 6h-cached; one GitHub releases API call at most
#   - never blocks: always exits 0; degrades cleanly when offline/uv missing
#   - silent when herdr is not installed -- nothing to gate, so no noise
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Nothing installed -> nothing to say. Checked before locating the tool so this
# hook stays completely silent on machines that never adopted herdr.
command -v herdr >/dev/null 2>&1 || exit 0

# Locate the checker: prefer the stow-deployed copy on PATH, fall back to the
# repo source (always present, even before the first stow).
TOOL=""
for cand in "$HOME/.local/bin/herdr-cooldown-check" \
            "$PROJECT_DIR/home/.local/bin/herdr-cooldown-check"; do
  [ -x "$cand" ] && { TOOL="$cand"; break; }
done
[ -z "$TOOL" ] && { echo "🐑 herdr cooldown: tool not found — skipped (read-only)."; exit 0; }

# The tool runs via `uv run` (PEP 723). No uv -> nothing to do.
command -v uv >/dev/null 2>&1 || { echo "🐑 herdr cooldown: uv not found — skipped."; exit 0; }

# The gate itself is the canonical bash constant in install.sh, so the policy
# lives in one place alongside PNPM_MIN_VERSION / NVM_MIN_VERSION.
days=$(grep -oE 'HERDR_COOLDOWN_DAYS="[0-9]+"' "$PROJECT_DIR/install.sh" 2>/dev/null \
  | grep -oE '[0-9]+' | head -1)

# 6h cache of the tool's plain-text verdict. A release crossing the 3-day line
# is not a sub-6h event, and the assistant can always run the tool live.
cache="${TMPDIR:-/tmp}/herdr-cooldown-check.verdict"
ttl=21600
now=$(date +%s)
# Portable mtime: GNU `stat -c` FIRST, then BSD/macOS `stat -f`, numeric-guarded
# (same trap documented in zed-version-check.sh).
mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
case "$mtime" in ''|*[!0-9]*) mtime=0;; esac

out=""
if [ -s "$cache" ] && [ "$((now - mtime))" -lt "$ttl" ]; then
  out=$(cat "$cache" 2>/dev/null)
else
  args=(--timeout 8)
  [ -n "$days" ] && args+=(--cooldown-days "$days")
  out=$(NO_COLOR=1 timeout 25 "$TOOL" "${args[@]}" 2>/dev/null || true)
  [ -n "$out" ] && { printf '%s\n' "$out" >"$cache" 2>/dev/null || true; }
fi

# Offline with no cache -> note and bail (retries next session).
[ -z "$out" ] && { echo "🐑 herdr cooldown: could not run (offline?) — will retry next session."; exit 0; }

if printf '%s' "$out" | grep -q 'ACTION'; then
  echo "🐑 herdr cooldown (SessionStart · read-only) — ⚠️  action available:"
  printf '%s\n' "$out" | sed 's/^/   /'
  echo "    Assistant: an upgrade has aged past the gate, or a guard has lapsed."
  echo "    Upgrade path is deliberate and three-step — unpin, upgrade, re-pin —"
  echo "    never a bare \`brew upgrade\`. Re-verify with \`herdr-cooldown-check\`."
else
  line="🐑 herdr cooldown: herdr current or held by the ${days:-3}-day gate; guards in place (cached <=6h)."
  printf '%s' "$out" | grep -q 'SKIPPED' && line="$line  (some checks skipped)"
  echo "$line"
fi
exit 0
