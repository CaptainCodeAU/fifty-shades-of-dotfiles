#!/bin/bash
# Fire at the MOMENT a grep is about to run, and point the session at the census tool.
# Runs on PreToolUse for Bash. Sibling of enforce-uv / enforce-pnpm / enforce-gh-ssh-only:
# it never blocks, never edits the command, and always exits 0.
#
# WHY IT EXISTS — measured, not felt
#   A grep is a lower bound wearing a fact's clothes. In one working sitting, five ad-hoc
#   greps returned wrong answers while every purpose-built tool in the tree was right every
#   time. All five were one shape: A NEGATIVE OR A COUNT TAKEN FROM AN UNPROVEN INSTRUMENT.
#     · `\|` is BRE alternation. Under -E it matches a literal backslash-pipe, so a
#       three-way search silently became a search for nonsense. It returned 0.
#     · a dropped -i, against text reading "Patient-less". It returned 0.
#     · an unquoted shell variable holding nine paths, which grep read as ONE filename.
#       It returned 0 — and "no retired names anywhere" was one sentence from being stated.
#     · a pattern that exceeded the regex engine's complexity limit and errored, while the
#       string being searched for was present the whole time.
#     · a `head -12` that truncated away the very control row that would have caught it.
#
#   The tool alone is not the fix. In the same sitting that built it, grep was reached for
#   again within the hour — a note in a file did not fire. This does, at the only moment it
#   is useful.
#
# 🔴 WHY IT SHOUTS INSTEAD OF GOING QUIET
#   A retired sibling hook opened with `[ -f "$TOOL" ] || exit 0`. Had its tool ever gone
#   missing it would have produced SILENCE, not an error, and a session would have read the
#   silence as health. A missing instrument must never be indistinguishable from a clean
#   bill. So: tool present -> remind. Tool absent -> say so, loudly, every time.
#
# The tool is machine-global and stow-symlinked from the dotfiles repo, so there is exactly
# one copy on this box and nothing to keep in sync per project.

set -uo pipefail

TOOL="$HOME/.claude/tools/census.py"

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Only fire on an actual grep. `git grep` counts — same dialect, same case traps.
case "$cmd" in *grep*) ;; *) exit 0 ;; esac

# Already corroborating? Say nothing. A reminder that fires when it is not needed is how a
# reminder gets ignored when it is.
case "$cmd" in *census.py*) exit 0 ;; esac

# STAND DOWN where a project already carries its own census reminder. Some repos are governed
# by a standard that requires a project-level copy and byte-checks it; firing on top of that
# would state the same rule twice, and two copies of a rule go unnoticed and only drift.
# The project's own copy is the one that fires there; this one covers everywhere else.
#
# ⚠️ The fallback is the REPO ROOT, never $PWD. Measured while building this: a $PWD fallback
# made the stand-down leak — the hook was invoked from one project's directory while pointed
# at another, found that directory's copy, and went silent for a project that had none. A
# stand-down that fires in the wrong place is worse than no stand-down, because its failure
# mode is silence.
_root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$_root" ] || _root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$_root" ] && [ -f "$_root/.claude/hooks/grep-census-reminder.sh" ]; then
  exit 0
fi

if [ -f "$TOOL" ]; then
  invocation="uv run python3 \$HOME/.claude/tools/census.py --control <a-token-you-KNOW-is-present> [--under PATH] PATTERN..."
  missing=""
else
  invocation="(THE CENSUS TOOL IS MISSING FROM THIS MACHINE — see below)"
  missing="

🔴 \`$TOOL\` DOES NOT EXIST. This hook is deployed but its tool is not, so nothing here can
corroborate a grep right now. That is a broken install, not a clean bill of health: report it
rather than working around it. Fix: re-run stow from the dotfiles repo, which symlinks
home/.claude/tools/census.py into place."
fi

read -r -d '' NOTE <<EOF
⚠️ A grep is about to run. Before trusting a ZERO or a COUNT from it, corroborate:

    $invocation

The census tool refuses to report anything unless the control hits first, always prints the
denominator AND how the population was drawn (git ls-files, or an explicit walk when the
project is not a repo), and never truncates. grep does none of that.

Measured: five ad-hoc greps in one sitting were wrong — \`\\|\` used as alternation under -E,
a dropped -i, an unquoted variable read as one filename, a regex complexity error, and a
\`head\` that cut off the control row — while every purpose-built tool was right every time.

⇒ A zero from grep is NOT evidence of absence. It is an unproven instrument until a control
has hit in the same breath. Using grep to LOCATE is fine; using it to CONCLUDE is what keeps
going wrong.$missing
EOF

jq -n --arg ctx "$NOTE" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}, suppressOutput: true}'
exit 0
