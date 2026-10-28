#!/bin/zsh
# notify-permission-prompt.sh -- ping Gavin by ntfy when Claude Code stops for his approval, and log it.
#
# Gavin, dotfiles-main 28 Oct 2026: "ensure that everytime there are prompts like this, that I am
# ntfy pinged (so it grabs my attention whenever I am away or not looking at the screen)" and "LOG
# all these somewhere (also include session name, session ID, folder name, command, date & time,
# and anything else that may be helpful down the line)". The prompt that started it: "Dangerous rm
# operation not ruled out", which held an e-conductor helper for 13 minutes (11:44 to 11:57 AM,
# 28 Oct) while nobody looked at the screen.
#
# PermissionRequest hook. Claude Code runs it when a permission dialog is about to be shown, with
# tool_name, tool_input, permission_mode, session_id, cwd, transcript_path, and agent_id and
# agent_type when a helper (sub-agent) asked (measured in the 2.1.312 program file, 28 Oct 2026).
# It is not given WHY the dialog shows (a safety check, an ask rule, no allow rule), so the log
# cannot say that either. The Notification hook's permission_prompt is not used: it carries no
# command and no agent_id.
#
# It never decides: it prints nothing, so the dialog shows as before, and it always exits 0.
# The ping runs detached through engage-ping (kind waiting, topic agents), so the dialog never
# waits for it.
#
# Side effect worth knowing: Claude Code switches off CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS
# in any session that registers a PermissionRequest hook (2.1.312). That switch is not used here.
#
# THE LOG: one JSON object per line, file mode 600, in PERMISSION_PROMPT_LOG (default
# ~/.local/state/dotfiles/permission-prompts.jsonl). Fields: time (12-hour Melbourne), iso, session
# name, session id, folder (from ~), project (the git top folder's name), tool, command (Bash) or
# the tool's input, description, permission mode, agent id and type, transcript (from ~), Claude
# Code version, host, the herdr pane, and what happened to the ping. Known secret shapes in the
# command are replaced with <redacted> first (token prefixes, NAME_TOKEN=value and the like); a
# secret of another shape is not caught, though the same command is in the session's transcript.
#
# SEAMS: PERMISSION_PROMPT_LOG, PERMISSION_PROMPT_PING (default engage-ping on PATH),
# PERMISSION_PROMPT_NO_PING=1 (log only).
# Test: notify-permission-prompt.sh --selftest (a fake engage-ping; the real one never runs).
emulate -L zsh
setopt pipefail

if [[ "${1-}" == --selftest ]]; then
  self="${0:A}"
  . "$HOME/.local/bin/test-temp.sh" new perm-prompt-selftest || exit 2
  integer fails=0
  ok()  { print -r -- "ok    $1"; }
  bad() { print -r -- "FAIL  $1"; fails+=1; }
  fake="$TT/engage-ping"
  print -r -- '#!/bin/zsh
print -rl -- "$@" > "'"$TT"'/ping-args"' > "$fake"; chmod +x "$fake"
  log="$TT/log.jsonl"
  run() { print -r -- "$1" | PERMISSION_PROMPT_LOG="$log" PERMISSION_PROMPT_PING="$fake" \
    CLAUDE_CODE_SESSION_NAME="${2-test-session}" "$self"; }

  # 1. a helper's Bash prompt: logged with every field, and pinged
  run '{"session_id":"abc-123","cwd":"'"$HOME"'/CODE/x","permission_mode":"bypassPermissions","agent_id":"a1","agent_type":"general-purpose","transcript_path":"'"$HOME"'/t.jsonl","tool_name":"Bash","tool_input":{"command":"print -rl -- ${(s.:.)PATH}","description":"probe PATH"}}'
  [[ $? == 0 ]] && ok "exit 0" || bad "exit not 0"
  for i in {1..50}; do [[ -s "$TT/ping-args" ]] && break; sleep 0.1; done
  line="$(tail -n 1 "$log" 2>/dev/null)"
  [[ "$(print -r -- "$line" | jq -r '.session_id')" == abc-123 ]] && ok "log: session id" || bad "log: session id"
  [[ "$(print -r -- "$line" | jq -r '.session_name')" == test-session ]] && ok "log: session name" || bad "log: session name"
  [[ "$(print -r -- "$line" | jq -r '.folder')" == "~/CODE/x" ]] && ok "log: folder from ~" || bad "log: folder from ~"
  [[ "$(print -r -- "$line" | jq -r '.command')" == 'print -rl -- ${(s.:.)PATH}' ]] && ok "log: command" || bad "log: command"
  [[ "$(print -r -- "$line" | jq -r '.agent_type')" == general-purpose ]] && ok "log: agent type" || bad "log: agent type"
  [[ "$(print -r -- "$line" | jq -r '.time')" == *(AM|PM)* ]] && ok "log: 12-hour time" || bad "log: 12-hour time"
  [[ "$(stat -f %Lp "$log")" == 600 ]] && ok "log: mode 600" || bad "log: mode $(stat -f %Lp "$log")"
  [[ "$(<"$TT/ping-args" 2>/dev/null)" == waiting$'\n'* ]] && ok "ping: kind waiting" || bad "ping: not sent as waiting"
  command grep -qx -- '--detach' "$TT/ping-args" 2>/dev/null && ok "ping: detached" || bad "ping: not detached"
  command grep -q -- 'Who: helper general-purpose' "$TT/ping-args" 2>/dev/null && ok "ping: names the helper" || bad "ping: helper not named"
  long="$(command grep -E '^(Session|Tool|Who): ' "$TT/ping-args" | awk 'length > 40' | head -n 1)"
  [[ -z "$long" ]] && command grep -q '^Tool: ' "$TT/ping-args" && ok "ping: preview lines fit 40" || bad "ping: line over 40: $long"

  # 2. a secret in the command is redacted in the log and the ping
  : > "$TT/ping-args"
  fake_tok="gh""p_abcdefghijklmnopqrstuvwxyz0123"   # built here, so no token shape sits in the file
  run '{"session_id":"s2","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"curl -H x '"$fake_tok"' MY_TOKEN=hunter2hunter2"}}'
  for i in {1..50}; do [[ -s "$TT/ping-args" ]] && break; sleep 0.1; done
  line="$(tail -n 1 "$log")"
  [[ "$line" != *ghp_abcdef* && "$line" != *hunter2* && "$line" == *'<redacted>'* ]] && ok "redacted in log" || bad "secret reached the log"
  ! command grep -q -e ghp_abcdef -e hunter2 "$TT/ping-args" && ok "redacted in ping" || bad "secret reached the ping"
  long="$(command grep -E '^(Session|Tool|Who): ' "$TT/ping-args" | awk 'length > 40' | head -n 1)"
  [[ -z "$long" ]] && command grep -q '^Command: curl' "$TT/ping-args" && ok "ping: a long command is cut to 40, whole under Command" || bad "ping: long command: $long"

  # 3. a non-Bash tool: its input is logged
  run '{"session_id":"s3","cwd":"/tmp","tool_name":"Edit","tool_input":{"file_path":"'"$HOME"'/a.txt","old_string":"x","new_string":"y"}}'
  [[ "$(tail -n 1 "$log" | jq -r '.input.file_path')" == "~/a.txt" ]] && ok "non-Bash input logged" || bad "non-Bash input not logged"

  # 4. control: an unreadable payload still logs one line and exits 0, prints nothing
  out="$(print -r -- 'not json' | PERMISSION_PROMPT_LOG="$log" PERMISSION_PROMPT_NO_PING=1 "$self" 2>&1)"; rc=$?
  [[ $rc == 0 && -z "$out" ]] && ok "bad payload: exit 0, silent" || bad "bad payload: rc $rc, said '$out'"
  [[ "$(tail -n 1 "$log" | jq -r '.ping')" == "not sent: unreadable payload" ]] && ok "bad payload: logged" || bad "bad payload: not logged"

  n="$(wc -l < "$log" | tr -d ' ')"
  [[ "$n" == 4 ]] && ok "4 log lines for 4 runs" || bad "$n log lines for 4 runs"
  (( fails == 0 )) && print -r -- "selftest: all passed" || print -r -- "selftest: $fails FAILED"
  return $(( fails > 0 ))
fi

exec 1>/dev/null 2>/dev/null   # nothing reaches Claude Code from here, whatever fails below
in="$(cat)"
LOG="${PERMISSION_PROMPT_LOG:-$HOME/.local/state/dotfiles/permission-prompts.jsonl}"
H="${HOME%/}"

now_local="$(TZ=Australia/Melbourne date '+%-I:%M:%S %p %a %-d %b %Y')"
now_iso="$(TZ=Australia/Melbourne date '+%Y-%m-%dT%H:%M:%S%z')"
name="${CLAUDE_CODE_SESSION_NAME-}"
ver="${$(readlink "$HOME/.local/bin/claude" 2>/dev/null):t}"
host="$(hostname -s 2>/dev/null)"

writelog() {   # writelog <json>: append one line, the file kept at mode 600
  { mkdir -p "${LOG:h}" && [[ -e "$LOG" ]] || { : >> "$LOG" && chmod 600 "$LOG"; }
    print -r -- "$1" >> "$LOG"; } 2>/dev/null
  return 0
}

# The record, built by jq from the payload. Paths under the home folder become ~, known secret
# shapes become <redacted>.
rec="$(print -r -- "$in" | jq -c --arg h "$H" --arg t "$now_local" --arg iso "$now_iso" \
  --arg name "$name" --arg ver "$ver" --arg host "$host" --arg pane "${HERDR_PANE_ID-}" '
  def tilde: if type == "string" and $h != "" and startswith($h) then "~" + .[($h | length):] else . end;
  def red: if type == "string" then
      gsub("(ghp_|gho_|ghs_|ghu_|github_pat_|sk-ant-|sk-|xox[abpr]-|AKIA|glpat-)[A-Za-z0-9_\\-]{8,}"; "<redacted>")
      | gsub("(?<k>[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|APIKEY)[A-Za-z0-9_]*=)[^ \"'"'"']+"; "\(.k)<redacted>"; "i")
    else . end;
  select(type == "object")
  | (.tool_input // {}) as $in
  | (.cwd // "") as $cwd
  | {time: $t, iso: $iso,
     session_name: (if $name != "" then $name else null end),
     session_id: (.session_id // null),
     folder: ($cwd | tilde),
     folder_name: ($cwd | split("/") | map(select(. != "")) | last // null),
     tool: (.tool_name // null),
     command: (if (.tool_name == "Bash") then ($in.command // null | red) else null end),
     description: ($in.description // null | red),
     input: (if (.tool_name == "Bash") then null else ($in | walk(if type == "string" then (red | tilde) else . end)) end),
     permission_mode: (.permission_mode // null),
     agent_id: (.agent_id // null), agent_type: (.agent_type // null),
     transcript: (.transcript_path // null | tilde),
     claude_version: (if $ver != "" then $ver else null end),
     host: (if $host != "" then $host else null end),
     herdr_pane: (if $pane != "" then $pane else null end)}
  | with_entries(select(.value != null))' 2>/dev/null)"

if [[ -z "$rec" ]]; then
  writelog "$(jq -cn --arg t "$now_local" --arg iso "$now_iso" --arg name "$name" \
    '{time: $t, iso: $iso, session_name: $name, ping: "not sent: unreadable payload"}')"
  exit 0
fi

# The project: the git top folder's name, else the folder's own name.
cwd="$(print -r -- "$in" | jq -r '.cwd // empty' 2>/dev/null)"
proj=""
[[ -n "$cwd" && -d "$cwd" ]] && proj="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
proj="${proj:t}"; [[ -n "$proj" ]] || proj="$(print -r -- "$rec" | jq -r '.folder_name // empty')"
[[ -n "$proj" ]] && rec="$(print -r -- "$rec" | jq -c --arg p "$proj" '. + {project: $p}')"

ping="${PERMISSION_PROMPT_PING:-$(whence -p engage-ping 2>/dev/null)}"
if [[ "${PERMISSION_PROMPT_NO_PING-}" == 1 ]]; then
  writelog "$(print -r -- "$rec" | jq -c '. + {ping: "not sent: switched off"}')"; exit 0
fi
if [[ -z "$ping" || ! -x "$ping" ]]; then
  writelog "$(print -r -- "$rec" | jq -c '. + {ping: "not sent: engage-ping not found"}')"; exit 0
fi

# The ping's lines, each about 40 characters for the lock screen (engage-ping --help).
f=("${(@f)$(print -r -- "$rec" | jq -r '
  (.session_name // .folder_name // "?"),
  (.tool // "?"),
  ((.command // .input.file_path // .description // "") | gsub("[\\n\\r\\t]"; " ")),
  (if .agent_type then "helper " + .agent_type else "" end)')}")
who="${f[1]}"; tool="${f[2]}"; what="${f[3]}"; helper="${f[4]}"
args=(waiting "Needs your OK" --line "Session: ${who[1,30]}" --line "Tool: $tool: ${what[1,$(( 32 - ${#tool} ))]}")
[[ -n "$helper" ]] && args+=(--line "Who: ${helper[1,34]}")
[[ ${#what} -gt $(( 32 - ${#tool} )) ]] && args+=(--more "Command: ${what[1,400]}")
args+=(--you "approve or deny in the pane" --topic agents --detach)

( cd "${cwd:-$HOME}" 2>/dev/null; "$ping" "${args[@]}" </dev/null >/dev/null 2>&1 ) &!
writelog "$(print -r -- "$rec" | jq -c '. + {ping: "sent to engage-ping"}')"
exit 0
