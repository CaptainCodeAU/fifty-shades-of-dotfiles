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

# jq is this hook's SECOND instrument, and it used to fail the way the header above
# condemns. `command -v jq || exit 0` is byte-for-byte the retired sibling's mistake:
# lose jq and the reminder stops in every project, forever, with no signal — silence
# read as a clean bill of health. The hook shouted about a missing census.py one screen
# below while doing exactly the wrong thing for jq one line up.
#
# Shout instead, for the same reason and in the same words. The message is emitted by
# hand here because building it needs the very tool that is missing.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE CENSUS REMINDER IS BROKEN: jq is not on PATH, so this hook cannot read the tool payload. It has been SILENT for every search in every project until now, and silence here is not a clean bill of health — it is a missing instrument. Install jq (brew install jq), then corroborate any count you already took. Do not treat a recent zero as evidence of absence."
  exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

# The BUILT-IN Grep tool carries no `.command`, so the old `[ -n "$cmd" ] || exit 0` dropped
# it on the floor. It is ripgrep underneath and inherits every trap: it skips hidden files
# and honours .gitignore by default, and it answers a miss with the bare words "No matches
# found" — no denominator, no statement of what it searched. That is the most confident
# nothing in the whole toolkit, and it was the one route this hook never covered.
if [ "$tool_name" = "Grep" ]; then
  _search=1
  _tool="Grep-tool search"
  _why="The Grep tool does none of that either: it skips hidden files and honours .gitignore
by default, and answers a miss with the bare words \"No matches found\" — no denominator, no
statement of what was actually searched."
fi
[ -n "$cmd" ] || [ "${_search:-0}" -eq 1 ] || exit 0

# Only fire on an actual search. `git grep` counts — same dialect, same case traps.
#
# `rg` was MISSED for as long as this hook has existed, because the substring test below
# looks for the letters "grep" and `rg` does not contain them. Measured 2026-09-04: a bare
# `rg -c safe-rm README.md` produced no reminder at all, while `grep` produced one every
# time. That is the wrong way round — ripgrep is the MORE trap-prone of the two here, since
# it skips dotfiles unless `--hidden` is passed, so an empty `rg` in a dotfiles repo is not
# a not-found. The reminder was firing on the safer tool and staying silent on the sharper one.
#
# `rg` needs a WORD BOUNDARY; a substring test would fire on merge, large, target, org,
# argv and rgb. A reminder that fires on `git merge` is a reminder that gets ignored on
# `rg`. Word characters here exclude `/` and `|` on purpose, so `/usr/bin/rg` and `… | rg`
# both fire, while `rg.py` and `rgb` do not.
# ripgrep is tested FIRST: "ripgrep" contains "grep", so the substring test would claim it
# and the notice would open "a grep is about to run" over an rg. Name the tool that actually
# ran — a notice that looks like a misfire stops being read.
#
# A word boundary alone was still too loose. `rg` is two letters, so it turns up inside
# ordinary English the moment a command carries any: measured false fires on
# `echo "the large rg thing"` and `cat CHANGELOG.md # mentions rg`. Firing on prose is
# how a reminder becomes wallpaper.
#
# So `rg` must appear in COMMAND POSITION — at the start, or straight after something
# that starts a new command: a pipe, a semicolon, && or ||, a subshell, a backtick, or a
# runner such as xargs/time/sudo/command/env/exec. An optional /path/to/ prefix is
# allowed so /usr/bin/rg still fires. Quotes and comments are stripped first, so the
# word cannot reach the test from inside a string or after a `#` at all.
_bare="${cmd//\\'*\\'/ }"                    # drop '...' single-quoted spans
_bare="$(printf '%s' "$_bare" | sed -e 's/"[^"]*"/ /g' -e 's/#.*$//')"
_cmdpos='(^|[|;&(`]|&&|\|\||\$\(|(^|[[:space:]])(xargs|time|sudo|command|env|exec|nohup)[[:space:]]+)[[:space:]]*([A-Za-z0-9_./-]*/)?(rg|ripgrep)([[:space:]]|$)'

_search="${_search:-0}"
_tool="${_tool:-search}"
if [ "$_search" -eq 1 ]; then
  :                                      # already settled by the Grep-tool branch above
elif [[ "$_bare" =~ $_cmdpos ]]; then
  _search=1
  _tool="ripgrep"
else
  case "$cmd" in *grep*) _search=1; _tool="grep" ;; esac
fi
[ "$_search" -eq 1 ] || exit 0

# Why THIS instrument cannot be trusted for a zero. Set by the Grep-tool branch; this is the
# shell-command wording.
if [ -z "${_why:-}" ]; then
  _why="Neither grep nor rg does any of that, and rg additionally SKIPS DOTFILES unless
--hidden is passed, so an empty rg is not a not-found."
fi

# Already corroborating? Say nothing. A reminder that fires when it is not needed is how a
# reminder gets ignored when it is. (Empty for the Grep tool, which carries no command and
# cannot invoke census itself.)
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
⚠️ A $_tool is about to run. Before trusting a ZERO or a COUNT from it, corroborate:

    $invocation

The census tool refuses to report anything unless the control hits first, always prints the
denominator AND how the population was drawn (git ls-files, or an explicit walk when the
project is not a repo), and never truncates.
$_why

Measured: five ad-hoc greps in one sitting were wrong — \`\\|\` used as alternation under -E,
a dropped -i, an unquoted variable read as one filename, a regex complexity error, and a
\`head\` that cut off the control row — while every purpose-built tool was right every time.

⇒ A zero from it is NOT evidence of absence. It is an unproven instrument until a control has
hit in the same breath. Using it to LOCATE is fine; using it to CONCLUDE is what keeps going
wrong.$missing
EOF

jq -n --arg ctx "$NOTE" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}, suppressOutput: true}'
exit 0
