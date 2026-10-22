#!/usr/bin/env bash
# codebox-hooks-test.sh -- prove codebox's hooks end to end in a made-up home (Gavin, dotfiles-main
# Q50: 1, 23 Oct 2026): install.sh's own placement functions copy the hooks and place the settings,
# then each registered command from the placed settings.json is run the way Claude runs it, with a
# real payload on stdin. Runs on the Mac and on codebox alike; nothing outside the temp folder moves.
#
#   bash settings/codebox/hooks/tests/codebox-hooks-test.sh [REPO]
#
# REPO is the fifty-shades-of-dotfiles checkout (default: three folders up from here).
set -u
REPO_DIR="${1:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
W=$(mktemp -d "${TMPDIR:-/tmp}/codebox-hooks-test.XXXXXX")
# The real path: the file-edit lock follows links, and the Mac's /tmp is a link to /private/tmp.
W=$(cd "$W" && pwd -P)
pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s%s\n' "$1" "${2:+ -- $2}"; }
fns=$(awk '/^_place_codebox_(hooks|claude_settings)\(\) \{/{p=1} p{print} p&&/^}/{p=0}' "$REPO_DIR/install.sh")
[ -n "$fns" ] || { echo "could not read the placement functions from $REPO_DIR/install.sh"; exit 2; }
step() { :; }; warn() { echo "WARN $*"; }; info() { :; }; success() { :; }
run_cmd() { "$@"; }; pretty_path() { echo "$1"; }
# A stand-in for install.sh's Trash-routed rm: it moves its file arguments into $W/trash.
mkdir -p "$W/trash"
printf '#!/bin/sh\nfor a in "$@"; do case $a in -*) ;; *) mv "$a" "%s/trash/" ;; esac; done\n' "$W" > "$W/safe-rm"
chmod +x "$W/safe-rm"
PLACE_CODEBOX_SETTINGS=true DRY_RUN=false SAFE_RM="$W/safe-rm"
eval "$fns"
HOME="$W/home"; mkdir -p "$HOME/.claude"
S="$HOME/.claude/settings.json"

# 1. placement
_place_codebox_hooks
_place_codebox_claude_settings
L="$HOME/.claude/hooks/codebox"
n_json=$(jq '.hooks | length' "$REPO_DIR/settings/codebox/hooks/hooks.json")
n_rows=$(jq '[.hooks[] | .[] | .hooks | length] | add' "$S")
[ "$n_json" = "$n_rows" ] && ok "1 placed settings carry all $n_rows rows of hooks.json" || bad "1 rows" "json=$n_json settings=$n_rows"
missing=""; for s in $(jq -r '.hooks[].script' "$REPO_DIR/settings/codebox/hooks/hooks.json" | sort -u); do [ -x "$L/$s" ] || missing="$missing $s"; done
[ -z "$missing" ] && ok "1 every listed script is in ~/.claude/hooks/codebox and executable" || bad "1 scripts" "$missing"
[ ! -e "$L/tests" ] && [ ! -e "$L/build-rows.py" ] && ok "1 tests/ and build-rows.py stay out of the live copy" || bad "1 left-out files"
_place_codebox_hooks
[ ! -e "$L.new.$$" ] && [ -z "$(ls -d "$L".pre-dotfiles.* 2>/dev/null)" ] && ok "1 a second run changes nothing and keeps no backup" || bad "1 second run"

# 2. the registered commands, run as Claude runs them: bash -c "<command>", payload on stdin
cmd() { jq -r --arg e "$1" --arg m "$2" '.hooks[$e][] | select((.matcher // "") == $m) | .hooks[0].command' "$S" | sed -n "${3:-1}p"; }
pay() { jq -nc --arg c "$1" --arg cwd "$W" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd, session_id: "t1", hook_event_name: "PreToolUse"}'; }
decision() { jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null <<<"$1"; }
secret=$(cmd PreToolUse Bash 1); delete=$(cmd PreToolUse Bash 2)
o=$(pay 'printenv GH_TOKEN' | HOME="$HOME" bash -c "$secret"); d=$(decision "$o")
[ "$d" = deny ] && ok "2 secret guard denies printenv GH_TOKEN" || bad "2 secret deny" "$o"
o=$(pay 'ls -la' | HOME="$HOME" bash -c "$secret"); d=$(decision "${o:-{\}}")
[ "$d" = allow ] && ok "2 secret guard allows ls -la" || bad "2 secret allow" "$o"
o=$(pay '/bin/rm -rf /tmp/x' | HOME="$HOME" bash -c "$delete"); d=$(decision "$o")
[ "$d" = deny ] && ok "2 delete guard denies /bin/rm by path" || bad "2 delete deny" "$o"
edit=$(cmd PreToolUse 'Edit|Write|MultiEdit|NotebookEdit')
o=$(jq -nc --arg p "$S" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}, session_id: "t1"}' | HOME="$HOME" bash -c "$edit"); d=$(decision "$o")
[ "$d" = deny ] && ok "2 the file-edit lock denies a Write to ~/.claude/settings.json" || bad "2 lock deny" "$o"
o=$(jq -nc --arg p "$W/plain.txt" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}, session_id: "t1"}' | HOME="$HOME" bash -c "$edit"); d=$(decision "${o:-{\}}")
[ "$d" = allow ] && ok "2 the file-edit lock allows an ordinary file" || bad "2 lock allow" "$o"
chmod -x "$L/enforce-secret-probe.sh"
o=$(pay 'ls' | HOME="$HOME" bash -c "$secret"); d=$(decision "$o")
chmod +x "$L/enforce-secret-probe.sh"
[ "$d" = deny ] && grep -q 'HOOK MISSING' <<<"$o" && ok "2 a guard whose script cannot run denies (fail closed)" || bad "2 fail closed" "$o"

# 3. the start checks
start1=$(cmd SessionStart "" 1); start2=$(cmd SessionStart "" 2)
mkdir -p "$HOME/.claude/plugins" "$W/cap" "$HOME/.local/bin"
jq '.enabledPlugins["cc-capture@cc-warehouse"] = true' "$S" > "$S.t" && mv "$S.t" "$S"
printf '{"version": 2, "plugins": {"cc-capture@cc-warehouse": [{"installPath": "%s"}]}}\n' "$W/cap" > "$HOME/.claude/plugins/installed_plugins.json"
printf '#!/bin/sh\necho 0.1.4\n' > "$HOME/.local/bin/ccw"; chmod +x "$HOME/.local/bin/ccw"
o=$(echo '{}' | HOME="$HOME" NO_COLOR=1 PATH=/usr/bin:/bin bash -c "$start1" 2>&1)
grep -q 'OK capture installed' <<<"$o" && ok "3 the warehouse watch reads codebox's own ~/.claude and finds capture on" || bad "3 ccw-watch" "${o:0:200}"
: > "$W/envfile"
o=$(echo '{"session_id": "11111111-2222-3333-4444-555555555555"}' | HOME="$HOME" CLAUDE_ENV_FILE="$W/envfile" bash -c "$start2")
grep -q '(id: 11111111-2222-3333-4444-555555555555)' <<<"$o" && grep -qx 'export CLAUDE_SESSION_ID=11111111-2222-3333-4444-555555555555' "$W/envfile" \
  && ok "3 the session id hook names the session and writes its id" || bad "3 session id" "$o"

printf 'codebox hooks test: %d passed, %d failed  (left in %s, a temp folder)\n' "$pass" "$fail" "$W"
[ "$fail" -eq 0 ]
