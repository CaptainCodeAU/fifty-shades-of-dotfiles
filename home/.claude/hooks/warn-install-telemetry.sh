#!/bin/bash
# Remind the session, right after a Bash command installs a new tool, that the install is
# not finished until the tool's telemetry and update checks are off in its OWN config.
# Runs on PostToolUse for Bash. Sibling of enforce-census.sh and warn-zsh-word-split.sh:
# it never blocks, never edits the command, and always exits 0. #1110 (engage), Gavin's
# pick 2026-10-07 (engage-main Q13, option 3).
#
# WHY IT EXISTS
#   Gavin's rule, dropped from every prompt on 3 Oct: "An install is done only when its
#   telemetry and update checks are verified off in the tool's own config; an env var is
#   not coverage." Many tools phone home by default (usage data, update checks). Nothing
#   carried the rule after 3 Oct; he chose a reminder at the moment of install over a
#   prompt line.
#
# WHY PostToolUse, NOT PreToolUse
#   After the install ran is when the advice can be acted on: the tool and its config now
#   exist, and an install a guard denied (validate-bash denies brew install) or the user
#   refused never gets the reminder. Measured, not assumed, 2026-10-07 on 2.1.292: the
#   mods API for 2.1.292 lists additionalContext for PostToolUse; transcripts on this
#   machine hold 73 PostToolUse additionalContext records (2.1.283 to 2.1.292), 50 of them
#   from a user hook (the AskUserQuestion box check, last on 2.1.287), and the model
#   answered the box check on its next turn. A failed command fires PostToolUseFailure
#   instead; the hook answers under whichever event name the payload carries, so the same
#   script can be wired there too.
#
# WHAT FIRES (read by conv-shscan.awk, CONV_MODE=install, which tokenises zsh, so words
# inside quotes, heredocs and comments stay quiet, and $( ), backticks, sh -c, eval and
# text piped to a shell are read as the commands they are):
#   brew install (and --cask), npm i/install -g, pnpm add/install -g, bun add -g,
#   uv tool install, pipx install, cargo install, go install <module>@<version>,
#   gem install, mas install, and curl/wget piped into a shell (also bash <(curl ...)
#   and sh -c "$(curl ...)").
#   Quiet: project dependencies (no -g, uv add), upgrades (brew upgrade/reinstall,
#   uv tool install --reinstall/--upgrade), uninstalls, --help, -h, --dry-run.
#   Not read: a command run on another machine (ssh host '...'), a script file.
#
#   HOW OFTEN IT SPEAKS, measured 2026-10-07 by replaying every Bash command in this
#   machine's transcripts (140,693; 12,521 pass the cheap filter below): 43 reminders,
#   0 BROKEN, 3 of 3 known installs mixed in as controls caught. All but one are real
#   installs (pnpm -g, uv tool, brew, pipx, bun -g, nvm's curl | bash); the one false
#   alarm is a test that stubbed pnpm as a shell function. The last 60 transcripts
#   (2,306 commands) held no install and gave none.
#
# 🔴 WHY IT SHOUTS INSTEAD OF GOING QUIET
#   Same rule as enforce-census.sh: a missing instrument must never look like a clean
#   bill. jq or awk missing shouts on every call. The scanner missing or failing, or a
#   payload it cannot read, shouts when the text mentions an install; an empty payload is
#   not a command and stays quiet.
#   Selftest: ~/.claude/tools/warn-install-telemetry-selftest (--mutants proves it can fail).

set -uo pipefail

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

HOOKS_DIR="$(builtin cd "$(dirname "$0")" 2>/dev/null && pwd)"
SHSCAN="${CONV_SHSCAN:-$HOOKS_DIR/conv-shscan.awk}"
event="PostToolUse"

_shout() { # $1 reason (no double quotes, no backslashes)
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"},"suppressOutput":true}\n' \
    "$event" "🔴 THE INSTALL TELEMETRY REMINDER IS BROKEN: $1. This command was NOT checked. If it installed a tool, the install is not done until the tool's telemetry and update checks are off in its own config and read back; an environment variable alone does not count. The hook needs fixing; until then its silence is not a clean bill of health."
  exit 0
}

# jq reads the payload, awk runs the scanner. Either missing is a shout, not an exit 0,
# and it is built by hand because building it with jq needs jq.
command -v jq >/dev/null 2>&1 || _shout "jq is not on PATH, so it cannot read the tool payload"
command -v awk >/dev/null 2>&1 || _shout "awk is not on PATH, so it cannot read the command"

# A word that could be an install: instal(l), a -g/--global, or a pipe into a shell.
_maybe='instal|--global|--location|[[:space:]]-g([[:space:]]|$)|curl|wget'

# A truncated payload, or one where a Claude Code update moved the command to another
# key, reads as an empty command. Shout when the raw text mentions an install.
if ! printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
  [[ "$payload" =~ $_maybe ]] && _shout "the payload is not valid JSON"
  exit 0
fi
ev="$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null || true)"
case "$ev" in PreToolUse|PostToolUse|PostToolUseFailure) event="$ev" ;; esac
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
if [ -z "$cmd" ]; then
  [[ "$payload" =~ $_maybe ]] && _shout "the payload has no tool_input.command"
  exit 0
fi
# Cheap exit: no install word anywhere means nothing here can be an install.
[[ "$cmd" =~ $_maybe ]] || exit 0

[ -r "$SHSCAN" ] || _shout "its scanner conv-shscan.awk is missing beside the hook (restow home/.claude/hooks)"
# LC_ALL=C: the scanner counts bytes, and BSD awk in a UTF-8 locale can die on a
# multi-byte character.
found="$(printf '%s' "$cmd" | CONV_MODE=install LC_ALL=C awk -f "$SHSCAN" 2>/dev/null)" ||
  _shout "its scanner conv-shscan.awk failed on this command"
[ -n "$found" ] || exit 0

# One line: what was installed, by what. "pnpm -g: a, b; brew: jq".
seen=""
while IFS="$(printf '\t')" read -r tag mgr tools; do
  [ "$tag" = HIT ] || continue
  seen="${seen:+$seen; }$tools ($mgr)"
done <<EOF
$found
EOF
[ -n "$seen" ] || _shout "its scanner answered in a form the hook does not know"

verb="installed"; [ "$event" = PreToolUse ] && verb="installs"
msg="⚠️ install telemetry: this command $verb $seen. The install is not done until each tool's telemetry and update checks are switched off in the tool's OWN config (its settings file, or its own command such as \`brew analytics off\`) and read back to prove it. An environment variable alone does not count."

jq -n --arg ev "$event" --arg ctx "$msg" \
  '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}, suppressOutput: true}'
exit 0
