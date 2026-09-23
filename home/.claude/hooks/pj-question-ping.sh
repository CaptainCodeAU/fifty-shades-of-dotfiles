#!/bin/bash
# pj-question-ping.sh -- ping Gavin whenever an AskUserQuestion popup opens.
# Runs on PreToolUse for AskUserQuestion. Never blocks, never delays, never
# prints a decision: every path exits 0 with empty stdout.
#
# WHY IT EXISTS. D-20260921-A10, widened by Gavin 2026-09-23: "ping me if you
# have a question for me (basically, whenever there is one of those Ask User
# Question tool popups) ... I may be moving around and may completely forget".
# A rule the model has to remember before every popup is a rule it forgets
# once in a while, and the popup it forgets is the one that stalls a session
# for an hour. A hook cannot forget.
#
# THE SIGNAL is pj-ping's, so the hook's messages look exactly like every
# session's: this hook decides, then runs
#   pj-ping question "<first question's header, or its text>" --detach
# from the payload's cwd. pj-ping plays the four sounds, sends the two
# numbered imsg messages one second apart, sanitises the text, names the
# session, and logs the id (see `pj-ping --help`). --detach makes pj-ping
# return in well under a second and do the work in a detached process, so the
# popup is never delayed.
#
# pj-ping is found as $PJ_PING_BIN when SET (even to a missing path), else
# ../../.local/bin/pj-ping beside this file (right in the repo and once
# stowed), else on PATH.
#
# SKIPS, all exit 0 and silent on screen:
#   PJ_NO_PING=1               kill switch (selftests, scratch, controls). No log.
#   tool_name not AskUserQuestion   belt and braces behind the matcher.
#   same session pinged < 20 s ago  debounce, so a re-render or two rapid
#                                   questions do not double-ping. Logged.
#   pj-ping missing            nothing sent. Logged.
# Missing afplay, imsg or IMSG_TO are pj-ping's to handle and log.
#
# STATE: ${PJ_PING_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/pj}
#   question-ping.log     one line per decision, with the ping id (never the text)
#   question-ping/<key>   epoch of the last ping for that session (debounce)
#   ping.log              pj-ping's own log, keyed by the same id
#
# TEST SEAMS: PJ_PING_BIN (above); PJ_PING_AFPLAY / PJ_PING_IMSG pass through
# to pj-ping; PJ_PING_DEBOUNCE overrides the 20 s window;
# PJ_QUESTION_PING_HOOK=<path> makes --selftest test another copy of the hook.
#
# `--selftest` proves every arm with fake afplay and imsg. It never calls the
# real ones. Exit 0 = all pass.

DEBOUNCE="${PJ_PING_DEBOUNCE:-20}"
STATE_DIR="${PJ_PING_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pj}"
LOG_FILE="$STATE_DIR/question-ping.log"
STAMP_DIR="$STATE_DIR/question-ping"

# One log line. The braces matter: a failed append is a redirection error the
# shell raises before any 2>/dev/null on the command applies (CLAUDE_HOOKS.md).
log() {
  { mkdir -p "$STATE_DIR" || return 0
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${KEY:-?}" "$1" >>"$LOG_FILE"
  } 2>/dev/null
  return 0
}

# find_ping: the seam when SET (even to a missing path), else beside this
# file, else PATH. Prints nothing when not found.
find_ping() {
  local near
  if [ -n "${PJ_PING_BIN+x}" ]; then
    [ -x "$PJ_PING_BIN" ] && printf '%s' "$PJ_PING_BIN"
    return 0
  fi
  near="$(dirname "$0")/../../.local/bin/pj-ping"
  if [ -x "$near" ]; then printf '%s' "$near"; return 0; fi
  command -v pj-ping 2>/dev/null
  return 0
}

selftest() {
  local root fake hook pass=0 fail=0 out rc t0 t1 got id m1 m2
  hook="${PJ_QUESTION_PING_HOOK:-$0}"
  root="$(mktemp -d "${TMPDIR:-/tmp}/pj-question-ping-selftest.XXXXXX")" || exit 1
  fake="$root/bin"; mkdir -p "$fake"
  ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
  bad() { fail=$((fail + 1)); printf '  FAIL %s\n       got: %s\n' "$1" "$2"; }
  now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

  # Fakes log "<hi-res epoch> <tool> <arg>" and never touch audio or Messages.
  # The fake afplay sleeps 0.3 s per sound, so the worker takes >= 2.2 s and a
  # hook that waited for it could not return inside the 0.5 s budget.
  cat >"$fake/afplay" <<'EOF'
#!/bin/bash
printf '%s afplay %s\n' "$(perl -MTime::HiRes=time -e 'printf "%.3f", time')" "$1" >>"$PJ_PING_FAKE_LOG"
sleep 0.3
EOF
  cat >"$fake/imsg" <<'EOF'
#!/bin/bash
printf '%s imsg %s\n' "$(perl -MTime::HiRes=time -e 'printf "%.3f", time')" "$1" >>"$PJ_PING_FAKE_LOG"
EOF
  chmod +x "$fake/afplay" "$fake/imsg"

  # Every arm runs with the seams pinned to the fakes AND the fakes first on
  # PATH, so no path through the hook or pj-ping can reach the real binaries.
  export PATH="$fake:$PATH" PJ_PING_AFPLAY="$fake/afplay" PJ_PING_IMSG="$fake/imsg"
  export IMSG_TO="selftest@example.invalid" CLAUDE_CODE_SESSION_NAME="st-sess" PJ_PING_PAIR_GAP=2
  unset PJ_NO_PING PJ_PING_DEBOUNCE PJ_PING_LOG HERDR_PANE_ID PJ_PING_BIN
  echo "pj-question-ping selftest of $hook in $root"
  echo "  pj-ping: $(f="$(dirname "$hook")/../../.local/bin/pj-ping"; [ -x "$f" ] && echo "$f" || command -v pj-ping || echo MISSING)"

  # The tool_input is a real AskUserQuestion input from a pj transcript
  # (2026-09, trimmed to two options); the envelope fields are the documented
  # PreToolUse ones.
  payload() { # payload <session_id> <header> <question> [tool_name]
    jq -cn --arg sid "$1" --arg h "$2" --arg q "$3" --arg tn "${4:-AskUserQuestion}" --arg cwd "$root" '{
      session_id: $sid, transcript_path: "/nonexistent.jsonl", cwd: $cwd,
      permission_mode: "bypassPermissions", hook_event_name: "PreToolUse",
      tool_name: $tn, tool_use_id: "toolu_selftest",
      tool_input: {questions: [
        {question: $q, header: $h, multiSelect: false, options: [
          {label: "You relay it (Recommended)", description: "I print the message as clean copy-paste text here."},
          {label: "Retry the send now", description: "I call SendMessage again."}]},
        {question: "Item A: approve?", header: "Item A", multiSelect: false, options: [
          {label: "Ship it", description: "x"}, {label: "Not yet", description: "y"}]}]}}'
  }
  # arm <name>: fresh state and fake log for one arm
  arm() {
    export PJ_PING_STATE_DIR="$root/state-$1" PJ_PING_FAKE_LOG="$root/fake-$1.log"
    : >"$PJ_PING_FAKE_LOG"
  }
  # wait_lines <n>: wait up to 8 s for the fake log to reach n lines
  wait_lines() {
    local i=0
    while [ "$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')" -lt "$1" ] && [ $i -lt 80 ]; do
      sleep 0.1; i=$((i + 1))
    done
  }
  # stdout AND stderr are captured, so a worker holding either pipe would
  # make run() wait for it and fail arm 2.
  run() { # run <stdin>; sets out (stdout+stderr), rc and the elapsed time in t1
    t0=$(now)
    out="$(printf '%s' "$1" | "$hook" 2>&1)"; rc=$?
    t1=$(perl -e "printf '%.3f', $(now) - $t0")
  }
  line() { sed -n "${1}p" "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-; }
  # summary_of <msg1>: the text after the second " | "
  summary_of() { printf '%s' "$1" | awk -F' [|] ' '{print $3}'; }
  Q='The message to cc-warehouse-6c expired undelivered. How should I get those five questions to them?'
  QI=$'\xe2\x9d\x93'

  # 1-6. POSITIVE: the whole signal, in order, off the popup's critical path.
  arm main
  run "$(payload sid-main Delivery "$Q")"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && ok "1 exit 0, empty stdout and stderr (no decision printed)" || bad "1 exit/stdout" "rc=$rc out=$out"
  perl -e "exit !($t1 < 0.5)" && ok "2 hook returned in ${t1}s (< 0.5 s) while the worker takes >= 2.2 s" || bad "2 hook blocked" "${t1}s"
  wait_lines 8
  got=$(awk '{print $2, $3}' "$PJ_PING_FAKE_LOG" | sed "s#/System/Library/Sounds/##" | tr '\n' '|')
  [ "$got" = "afplay Ping.aiff|afplay Glass.aiff|afplay Glass.aiff|afplay Glass.aiff|imsg $QI|imsg $QI|imsg $QI|imsg $QI|" ] \
    && ok "3 four sounds Ping Glass Glass Glass, then four imsg (each message twice), in that order" || bad "3 order" "$got"
  m1=$(line 5); id=$(printf '%s' "$m1" | awk '{print $4}')
  printf '%s' "$m1" | grep -Eqx "$QI PJ QUESTION #[A-Z2-9]{4} [0-9:]{8} \| st-sess \| Delivery" \
    && ok "4 imsg 1 is pj-ping's: PJ QUESTION, id, time, session, header" || bad "4 imsg 1 text" "$m1"
  got=$(line 7)
  [ "$got" = "$QI $id 2/2 | answer the popup | pane -" ] && ok "5 imsg 2 carries the same id ($id) and says what to do" || bad "5 imsg 2 text" "$got"
  got=$(awk 'NR==5{a=$1} NR==6{b=$1} END{printf "%.3f", b-a}' "$PJ_PING_FAKE_LOG")
  perl -e "exit !($got >= 1.0 && $got < 3.0)" && ok "6 gap between the messages ${got}s (>= 1 s)" || bad "6 gap" "${got}s"
  grep -q "pinged $id" "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null \
    && grep -q "	${id#\#}	question	st-sess	queued" "$PJ_PING_STATE_DIR/ping.log" 2>/dev/null \
    && ok "6 the hook's log and pj-ping's log carry the same id" || bad "6 id in logs" "$(cat "$PJ_PING_STATE_DIR"/*.log 2>/dev/null)"

  # 7. NEGATIVE: kill switch. Same harness as arm 1, which proved it can hear a call.
  arm kill
  out="$(payload sid-kill Delivery "$Q" | PJ_NO_PING=1 "$hook")"; rc=$?
  sleep 1
  [ "$rc" -eq 0 ] && [ ! -s "$PJ_PING_FAKE_LOG" ] && ok "7 PJ_NO_PING=1 -> nothing called" || bad "7 kill switch" "rc=$rc $(cat "$PJ_PING_FAKE_LOG")"

  # 8. NEGATIVE: another tool name.
  arm tool
  run "$(payload sid-tool Delivery "$Q" Bash)"
  sleep 1
  [ "$rc" -eq 0 ] && [ ! -s "$PJ_PING_FAKE_LOG" ] && ok "8 tool_name Bash -> nothing called" || bad "8 other tool" "$(cat "$PJ_PING_FAKE_LOG")"

  # 9. DEBOUNCE, with both controls: a second call inside the window is
  #    skipped, another session is not, and a stale stamp pings again.
  arm deb
  run "$(payload sid-deb Delivery "$Q")"; wait_lines 8
  run "$(payload sid-deb Delivery "$Q")"; sleep 1
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 8 ] && ok "9 same session again within 20 s -> nothing more called" || bad "9 debounce" "$got lines, want 8"
  grep -q 'debounced' "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null && ok "9 the skip is logged as debounced" || bad "9 debounce log" "$(cat "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null)"
  run "$(payload sid-other Delivery "$Q")"; wait_lines 16
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 16 ] && ok "9 control: a different session in the same second still pings" || bad "9 control other session" "$got lines, want 16"
  echo $(($(date +%s) - 30)) >"$PJ_PING_STATE_DIR/question-ping/sid-deb"
  run "$(payload sid-deb Delivery "$Q")"; wait_lines 24
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 24 ] && ok "9 control: a stamp 30 s old pings again" || bad "9 control stale stamp" "$got lines, want 24"

  # 10. Control and bidi characters are stripped; the text around them survives.
  arm ctl
  run "$(payload sid-ctl "$(printf 'Hi\033[31mRED\342\200\256evil\tx')" "$Q")"; wait_lines 8
  got=$(line 5)
  if printf '%s' "$got" | perl -CSD -ne 'exit(/[\x00-\x1F\x7F-\x9F\x{202E}]/ ? 1 : 0)'; then
    ok "10 no control or bidi character reaches imsg"
  else bad "10 control chars leaked" "$(printf '%s' "$got" | od -c | head -3)"; fi
  [ "$(summary_of "$got")" = "Hi [31mRED evil x" ] && ok "10 control: the printable text around them survives" || bad "10 surviving text" "$got"

  # 11. No header: first 80 chars of the question text, capped.
  arm nohdr
  run "$(payload sid-nohdr "" "$Q")"; wait_lines 8
  got=$(summary_of "$(line 5)")
  [ "$got" = "${Q:0:80}" ] && ok "11 empty header -> first 80 chars of the question" || bad "11 fallback text" "$got"

  # 12. Token shapes are redacted; a 300-char header is capped.
  arm tok
  run "$(payload sid-tok "" "use ghp_$(printf 'A%.0s' $(seq 36)) now")"; wait_lines 8
  got=$(line 5)
  case "$got" in *ghp_*) bad "12 token leaked" "$got" ;; *'[redacted]'*) ok "12 token-shaped text -> [redacted]" ;; *) bad "12 redaction" "$got" ;; esac
  arm cap
  run "$(payload sid-cap "$(printf 'x%.0s' $(seq 300))" "$Q")"; wait_lines 8
  got=$(summary_of "$(line 5)")
  [ "${#got}" -eq 80 ] && ok "12 300-char header capped (${#got} chars)" || bad "12 cap" "${#got} chars"

  # 13. Missing tools: pj-ping does the rest and names what was missing.
  arm noto
  out="$(payload sid-noto Delivery "$Q" | env -u IMSG_TO "$hook")"; rc=$?; wait_lines 4; sleep 1.5
  got=$(awk '{print $2}' "$PJ_PING_FAKE_LOG" | tr '\n' ' ')
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$got" = "afplay afplay afplay afplay " ] && ok "13 IMSG_TO unset -> sounds only, no imsg" || bad "13 IMSG_TO unset" "rc=$rc calls=$got"
  grep -q 'IMSG_TO unset' "$PJ_PING_STATE_DIR/ping.log" 2>/dev/null && ok "13 the ping log names IMSG_TO" || bad "13 log IMSG_TO" "$(cat "$PJ_PING_STATE_DIR"/*.log 2>/dev/null)"
  arm noaf
  out="$(payload sid-noaf Delivery "$Q" | PJ_PING_AFPLAY="$root/missing/afplay" "$hook")"; rc=$?; wait_lines 4
  got=$(awk '{print $2}' "$PJ_PING_FAKE_LOG" | tr '\n' ' ')
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$got" = "imsg imsg imsg imsg " ] && ok "13 afplay missing -> messages only, no fallback to the real afplay" || bad "13 afplay missing" "rc=$rc calls=$got"
  grep -q 'afplay missing' "$PJ_PING_STATE_DIR/ping.log" 2>/dev/null && ok "13 the ping log names afplay" || bad "13 log afplay" "$(cat "$PJ_PING_STATE_DIR"/*.log 2>/dev/null)"
  arm noping
  out="$(payload sid-noping Delivery "$Q" | PJ_PING_BIN="$root/missing/pj-ping" "$hook")"; rc=$?; sleep 1
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$PJ_PING_FAKE_LOG" ] && grep -q 'pj-ping missing' "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null \
    && ok "13 pj-ping missing -> exit 0, nothing called, logged" || bad "13 pj-ping missing" "rc=$rc $(cat "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null)"

  # 14. Session name falls back to the repo basename when the variable is unset.
  arm name
  mkdir -p "$root/fixture-repo/sub" && git -C "$root/fixture-repo" init -q 2>/dev/null
  out="$(payload sid-name Delivery "$Q" | jq -c --arg c "$root/fixture-repo/sub" '.cwd = $c' \
    | env -u CLAUDE_CODE_SESSION_NAME "$hook")"; wait_lines 8
  got=$(line 5)
  printf '%s' "$got" | grep -q ' | fixture-repo | Delivery$' && ok "14 no CLAUDE_CODE_SESSION_NAME -> git toplevel basename of the payload cwd" || bad "14 fallback name" "$got"

  # 15. Malformed stdin: exit 0, nothing called.
  arm bad
  out="$(printf 'not json' | "$hook")"; rc=$?; sleep 1
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$PJ_PING_FAKE_LOG" ] && ok "15 malformed stdin -> exit 0, nothing called" || bad "15 malformed" "rc=$rc $(cat "$PJ_PING_FAKE_LOG")"

  # 16. The logs never carry the message text.
  if grep -qE 'Delivery|cc-warehouse' "$root"/state-*/*.log 2>/dev/null; then
    bad "16 message text found in a log" "$(grep -E 'Delivery|cc-warehouse' "$root"/state-*/*.log)"
  elif grep -q 'pinged' "$root"/state-main/question-ping.log 2>/dev/null && grep -q 'queued' "$root"/state-main/ping.log 2>/dev/null; then
    ok "16 logs record decisions and ids, never the question text (control: 'pinged' and 'queued' found)"
  else bad "16 control: no 'pinged'/'queued' line in the main logs" "$(cat "$root"/state-main/*.log 2>/dev/null)"; fi

  printf 'pj-question-ping selftest: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
--selftest) selftest; exit $? ;;
--help | -h) sed -n '2,/^# `--selftest`/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

[ "${PJ_NO_PING:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "AskUserQuestion" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# The debounce key is the session id when there is one; only [A-Za-z0-9_-]
# reaches a filename.
KEY=$(printf '%s' "${SID:-$(basename "$CWD")}" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)

# Debounce: the same session pinged inside the window -> skip.
NOW=$(date +%s)
LAST=$(cat "$STAMP_DIR/$KEY" 2>/dev/null)
case "$LAST" in '' | *[!0-9]*) LAST=0 ;; esac
if [ $((NOW - LAST)) -lt "$DEBOUNCE" ]; then
  log "debounced ($((NOW - LAST))s since last ping)"
  exit 0
fi

PING=$(find_ping)
if [ -z "$PING" ]; then
  log "skipped: pj-ping missing"
  exit 0
fi
{ mkdir -p "$STAMP_DIR" && printf '%s\n' "$NOW" >"$STAMP_DIR/$KEY"; } 2>/dev/null

# Raw text: pj-ping sanitises and caps it (80 characters).
WHAT=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions[0].header // empty' 2>/dev/null)
if [ -z "$(printf '%s' "$WHAT" | tr -d '[:space:]')" ]; then
  WHAT=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions[0].question // empty' 2>/dev/null)
fi

# pj-ping --detach prints the id and returns at once; its worker holds none of
# our descriptors. It runs from the payload's cwd so it names the session from
# that repo. Exit 2 means the text cleaned to nothing: send a placeholder.
ping_it() { (builtin cd -- "$CWD" 2>/dev/null; "$PING" question "$1" --detach </dev/null 2>/dev/null); }
ID=$(ping_it "$WHAT"); RC=$?
if [ "$RC" -eq 2 ]; then
  ID=$(ping_it "(no text)"); RC=$?
fi
log "pinged ${ID:-(no id)} (pj-ping rc=$RC)"
exit 0
