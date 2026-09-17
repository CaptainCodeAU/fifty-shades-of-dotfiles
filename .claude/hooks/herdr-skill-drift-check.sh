#!/usr/bin/env bash
# SessionStart hook (read-only): has a herdr upgrade moved the agent skill or
# left a doc behind?
#
# Sibling of herdr-cooldown-check.sh, which watches the BINARY. This one watches
# what the binary drags with it: ~/.claude/skills/herdr/SKILL.md is ours --
# upstream's skill with a lot of locally measured findings written into it --
# and herdr revises its own bundled copy (0.8.2 replaced it wholesale, #2847).
# Nothing anywhere announced that, so our skill could quietly describe a CLI
# that had moved on. The same upgrade also dates four docs/HERDR*.md, which sat
# stamped "0.7.5" while 0.8.2 was installed until someone happened to look.
#
# DELIBERATELY UNCACHED, unlike its siblings. It makes no network call -- it
# runs the local binary and reads four files -- so there is nothing to amortise,
# and a cache would keep reporting a stale doc for six hours after it was fixed.
# A guard you have already fixed but that keeps shouting is how a guard gets
# ignored.
#
# Guarantees (mirrors herdr-cooldown-check.sh):
#   - read-only   : never merges, never writes a snapshot, never edits a doc
#   - never blocks: always exits 0
#   - silent when herdr is not installed, and quiet when everything is green
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

command -v herdr >/dev/null 2>&1 || exit 0

TOOL=""
for cand in "$HOME/.local/bin/herdr-skill-drift-check" \
            "$PROJECT_DIR/home/.local/bin/herdr-skill-drift-check"; do
  [ -x "$cand" ] && { TOOL="$cand"; break; }
done
[ -z "$TOOL" ] && { echo "📄 herdr skill drift: tool not found — skipped (read-only)."; exit 0; }

command -v uv >/dev/null 2>&1 || { echo "📄 herdr skill drift: uv not found — skipped."; exit 0; }

# --quiet hides the OK rows, so output is empty exactly when nothing is wrong.
out=$(NO_COLOR=1 timeout 30 "$TOOL" --quiet 2>/dev/null || true)

if printf '%s' "$out" | grep -q 'ACTION\|DETECTOR BROKEN'; then
  echo "📄 herdr skill drift (SessionStart · read-only) — ⚠️  action needed:"
  printf '%s\n' "$out" | sed 's/^/   /'
  echo "    Assistant: read docs/HERDR_AGENT_SKILL.md section 1 for the merge runbook."
  echo "    skill-drift  -> diff the STORED UPSTREAM.md against a fresh \`herdr --skill\`;"
  echo "                    that shows what herdr changed, which is the only question."
  echo "    doc:*        -> re-verify the doc against the installed version, THEN move"
  echo "                    its \`herdr-verified:\` line. A stamp is a claim, not decoration."
else
  echo "📄 herdr skill: merge base current, all HERDR docs stamped for this version."
fi
exit 0
