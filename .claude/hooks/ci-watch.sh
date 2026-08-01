#!/usr/bin/env bash
# SessionStart hook (read-only): escalating CI-status watch for the welcome dash.
#
# STATUS: NOT WIRED (as of 2026-08-01). ci-watch runs at USER level --
# ~/.claude/settings.json calls the ~/.local/bin/ci-watch engine inline, so it
# fires in every project. The three sibling hooks here are PROJECT-level, where
# CLAUDE_PROJECT_DIR makes the repo-source fallback below meaningful; at user
# level it does not, because $PROJECT_DIR is whatever repo you happen to be in.
# Kept for the guarantees documented below and in case ci-watch ever becomes
# project-scoped. Do not wire it globally without re-solving the fallback.
#
# Thin wrapper -- locates the `ci-watch` engine and runs its session render. The
# engine is read-only to your repos, queries gh live (falls back to a per-target
# cache when offline), escalates a red that stays red, and CANNOT be dismissed by
# being seen (only by CI going green or a deliberate `ci-watch --snooze`).
#
# Guarantees (mirrors zed-version-check.sh / toolchain-cve-check.sh):
#   - read-only   : the engine's only writes are state under XDG_STATE_HOME
#   - fast        : a single gh call per watched target, 8s timeout each
#   - never blocks: always exits 0; degrades cleanly without gh/GH_TOKEN
#
# Real repo names live ONLY in ~/.config/ci-watch/watchlist (gitignored); this
# wrapper and the engine are generic and safe to commit. See watchlist.example.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Prefer the stow-deployed copy on PATH, fall back to the repo source.
TOOL=""
for cand in "$HOME/.local/bin/ci-watch" \
            "$PROJECT_DIR/home/.local/bin/ci-watch"; do
  [ -x "$cand" ] && { TOOL="$cand"; break; }
done
[ -z "$TOOL" ] && exit 0   # not deployed -> nothing to do (read-only)

"$TOOL" || true
exit 0
