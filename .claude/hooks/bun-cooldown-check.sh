#!/usr/bin/env bash
# SessionStart hook (read-only): is a globally-installed bun package silently
# stuck behind the ~/.bunfig.toml minimumReleaseAge supply-chain cooldown?
#
# Purpose: bun's own `install`/`add` output does not say when it silently kept
# the OLD version because the new one is still inside the cooldown window --
# it just prints success. A tool's own self-updater (codex 0.154.0, confirmed
# 2026-09-11) can then loop forever, always reporting "update ran successfully"
# while never actually updating. This hook runs the standalone
# `bun-cooldown-check` tool each session so a block is SEEN instead of hidden
# behind a fake success message. The hook NEVER edits anything or runs bun.
#
# Guarantees (mirrors the toolchain-cve-check.sh / zed-version-check.sh
# read-only hook pattern):
#   - read-only   : no writes except a throwaway verdict cache in $TMPDIR
#   - fast        : 6h-cached; the tool makes one npm-registry call per
#                   globally-installed bun package (usually just one or two)
#   - never blocks: always exits 0; degrades cleanly when offline/uv missing
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

TOOL=""
for cand in "$HOME/.local/bin/bun-cooldown-check" \
            "$PROJECT_DIR/home/.local/bin/bun-cooldown-check"; do
  [ -x "$cand" ] && { TOOL="$cand"; break; }
done
[ -z "$TOOL" ] && { echo "📦 bun cooldown check: tool not found — skipped (read-only)."; exit 0; }

command -v uv >/dev/null 2>&1 || { echo "📦 bun cooldown check: uv not found — skipped."; exit 0; }

# 6h cache of the tool's plain-text output. A cooldown window is measured in
# days, so a sub-6h staleness is not a real gap, and the assistant can always
# run `bun-cooldown-check` live.
cache="${TMPDIR:-/tmp}/bun-cooldown-check.verdict"
ttl=21600
now=$(date +%s)
mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
case "$mtime" in ''|*[!0-9]*) mtime=0;; esac

out=""
if [ -s "$cache" ] && [ "$((now - mtime))" -lt "$ttl" ]; then
  out=$(cat "$cache" 2>/dev/null)
else
  out=$(NO_COLOR=1 timeout 20 "$TOOL" --timeout 8 2>/dev/null || true)
  [ -n "$out" ] && { printf '%s\n' "$out" >"$cache" 2>/dev/null || true; }
fi

if [ -z "$out" ]; then
  echo "📦 bun cooldown check: no global bun packages found (or offline) — nothing to report."
  exit 0
fi


# Match "ready ~<date>" specifically, not "blocked by the minimumReleaseAge
# cooldown" -- the all-clear summary line also contains that exact phrase
# ("N checked -- NONE blocked by..."), so the looser match flagged the clean
# case as blocked (caught live 2026-09-11 running this hook against a real
# all-clear).
if printf '%s' "$out" | grep -q 'ready ~'; then
  echo "📦 bun cooldown check (SessionStart · read-only) — ⏳ update blocked by cooldown:"
  printf '%s\n' "$out" | sed 's/^/   /'
  echo "    Assistant: bun is correctly refusing a too-new package; the tool's own updater"
  echo "    will keep reporting false success until the date above. Tell the user, and only"
  echo "    add the package to minimumReleaseAgeExcludes in ~/.bunfig.toml if THEY decide"
  echo "    that specific package should bypass the cooldown."
else
  echo "$out" | head -1
fi
exit 0
