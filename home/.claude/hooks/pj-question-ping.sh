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
# THE SIGNAL is the ruling's, exactly: four sounds (Ping, Glass, Glass, Glass)
# via afplay, then TWO imsg messages ONE second apart. imsg takes no recipient;
# it sends to $IMSG_TO only, so this hook cannot address anyone else.
#   imsg 1: "<session>: question waiting: <first question's header, or the
#           first 80 chars of its text>"
#   imsg 2: "answer the popup in <session>"
# <session> is $CLAUDE_CODE_SESSION_NAME, else the basename of the git
# toplevel of the payload's cwd, else the cwd's basename.
#
# NEVER DELAYS THE POPUP. The hook only decides and stamps; the sounds and the
# messages run in a DETACHED process (double fork, stdin/stdout/stderr on
# /dev/null, so Claude Code has no pipe to wait on). The detached worker keeps
# the order: four sounds, imsg 1, sleep 1, imsg 2.
#
# TEXT IS UNTRUSTED. The question is agent-written, so control characters
# (C0, DEL, C1) and bidi overrides are replaced, token-shaped strings are
# redacted, and every part is length-capped before it reaches imsg. No
# environment value other than the session name ever goes into a message.
#
# SKIPS, all exit 0 and silent on screen:
#   PJ_NO_PING=1               kill switch (selftests, scratch, controls). No log.
#   tool_name not AskUserQuestion   belt and braces behind the matcher.
#   same session pinged < 20 s ago  debounce, so a re-render or two rapid
#                                   questions do not double-ping. Logged.
#   afplay missing             no sounds, messages still sent. Logged by name.
#   imsg missing / IMSG_TO unset   no messages, sounds still played. Logged.
#
# STATE: ${PJ_PING_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/pj}
#   question-ping.log     one line per decision (never the message text)
#   question-ping/<key>   epoch of the last ping for that session (debounce)
#
# TEST SEAMS: PJ_PING_AFPLAY / PJ_PING_IMSG, when SET (even to a missing path),
# replace the PATH lookup entirely, so a selftest can never fall through to the
# real binaries. PJ_PING_DEBOUNCE overrides the 20 s window.
#
# `--selftest` proves every arm with fake afplay and imsg. It never calls the
# real ones. Exit 0 = all pass.

DEBOUNCE="${PJ_PING_DEBOUNCE:-20}"
STATE_DIR="${PJ_PING_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pj}"
LOG_FILE="$STATE_DIR/question-ping.log"
STAMP_DIR="$STATE_DIR/question-ping"
SOUNDS_DIR="/System/Library/Sounds"

# One log line. The braces matter: a failed append is a redirection error the
# shell raises before any 2>/dev/null on the command applies (CLAUDE_HOOKS.md).
log() {
  { mkdir -p "$STATE_DIR" || return 0
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${KEY:-?}" "$1" >>"$LOG_FILE"
  } 2>/dev/null
  return 0
}

# clean <max-chars>: stdin -> one line, controls and bidi replaced by a space,
# token shapes redacted, whitespace squeezed, capped. Works on characters, not
# bytes, so a cap never splits a UTF-8 sequence.
clean() {
  perl -CSD -e '
    my $max = shift;
    local $/; my $s = <STDIN>; $s = "" unless defined $s;
    $s =~ s/[\x{00}-\x{1F}\x{7F}-\x{9F}\x{061C}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2069}\x{FEFF}]/ /g;
    $s =~ s/\b(?:gh[pousr]_|github_pat_|sk-ant-|sk-|xox[abprs]-|AKIA|glpat-)[A-Za-z0-9_\-]{6,}/[redacted]/g;
    $s =~ s/\s+/ /g; $s =~ s/^ //; $s =~ s/ $//;
    $s = substr($s, 0, $max) if length($s) > $max;
    print $s;
  ' "$1" 2>/dev/null
}

# The detached half: sounds in order, then the two messages one second apart.
send() { # send <afplay-or-empty> <imsg-or-empty> <msg1> <msg2>
  local afplay="$1" imsg="$2" s rc
  if [ -n "$afplay" ]; then
    for s in Ping Glass Glass Glass; do "$afplay" "$SOUNDS_DIR/$s.aiff"; done
  fi
  if [ -n "$imsg" ]; then
    "$imsg" "$3"; rc=$?
    sleep 1
    "$imsg" "$4"; rc="$rc,$?"
    log "sent imsg rc=$rc"
  fi
  return 0
}

# Resolve a tool: the seam variable when SET (even to a missing path), else PATH.
resolve() { # resolve <seam-var-name> <tool>
  local seam
  if [ -n "${!1+x}" ]; then
    seam="${!1}"
    [ -x "$seam" ] && printf '%s' "$seam"
    return 0
  fi
  command -v "$2" 2>/dev/null
  return 0
}

session_name() { # session_name <cwd>
  local n top
  n="${CLAUDE_CODE_SESSION_NAME:-}"
  if [ -z "$n" ] && [ -n "$1" ] && [ -d "$1" ]; then
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
    n=$(basename "${top:-$1}")
  fi
  printf '%s' "${n:-pj}"
}

selftest() {
  local root fake pass=0 fail=0 out rc t0 t1 got
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
  # PATH, so no path through the hook can reach the real binaries.
  export PATH="$fake:$PATH" PJ_PING_AFPLAY="$fake/afplay" PJ_PING_IMSG="$fake/imsg"
  export IMSG_TO="selftest@example.invalid" CLAUDE_CODE_SESSION_NAME="st-sess"
  unset PJ_NO_PING PJ_PING_DEBOUNCE
  echo "pj-question-ping selftest in $root"

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
    out="$(printf '%s' "$1" | "$0" 2>&1)"; rc=$?
    t1=$(perl -e "printf '%.3f', $(now) - $t0")
  }
  Q='The message to cc-warehouse-6c expired undelivered. How should I get those five questions to them?'

  # 1-6. POSITIVE: the whole signal, in order, off the popup's critical path.
  arm main
  run "$(payload sid-main Delivery "$Q")"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && ok "1 exit 0, empty stdout and stderr (no decision printed)" || bad "1 exit/stdout" "rc=$rc out=$out"
  perl -e "exit !($t1 < 0.5)" && ok "2 hook returned in ${t1}s (< 0.5 s) while the worker takes >= 2.2 s" || bad "2 hook blocked" "${t1}s"
  wait_lines 6
  got=$(awk '{print $2, $3}' "$PJ_PING_FAKE_LOG" | sed "s#$SOUNDS_DIR/##" | tr '\n' '|')
  [ "$got" = "afplay Ping.aiff|afplay Glass.aiff|afplay Glass.aiff|afplay Glass.aiff|imsg st-sess:|imsg answer|" ] \
    && ok "3 four sounds Ping Glass Glass Glass, then two imsg, in that order" || bad "3 order" "$got"
  got=$(sed -n 5p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  [ "$got" = "st-sess: question waiting: Delivery" ] && ok "4 imsg 1 names the session and the header" || bad "4 imsg 1 text" "$got"
  got=$(sed -n 6p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  [ "$got" = "answer the popup in st-sess" ] && ok "5 imsg 2 says what to do" || bad "5 imsg 2 text" "$got"
  got=$(awk 'NR==5{a=$1} NR==6{b=$1} END{printf "%.3f", b-a}' "$PJ_PING_FAKE_LOG")
  perl -e "exit !($got >= 1.0 && $got < 3.0)" && ok "6 gap between the messages ${got}s (>= 1 s)" || bad "6 gap" "${got}s"

  # 7. NEGATIVE: kill switch. Same harness as arm 1, which proved it can hear a call.
  arm kill
  out="$(payload sid-kill Delivery "$Q" | PJ_NO_PING=1 "$0")"; rc=$?
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
  run "$(payload sid-deb Delivery "$Q")"; wait_lines 6
  run "$(payload sid-deb Delivery "$Q")"; sleep 1
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 6 ] && ok "9 same session again within 20 s -> nothing more called" || bad "9 debounce" "$got lines, want 6"
  grep -q 'debounced' "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null && ok "9 the skip is logged as debounced" || bad "9 debounce log" "$(cat "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null)"
  run "$(payload sid-other Delivery "$Q")"; wait_lines 12
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 12 ] && ok "9 control: a different session in the same second still pings" || bad "9 control other session" "$got lines, want 12"
  echo $(($(date +%s) - 30)) >"$PJ_PING_STATE_DIR/question-ping/sid-deb"
  run "$(payload sid-deb Delivery "$Q")"; wait_lines 18
  got=$(wc -l <"$PJ_PING_FAKE_LOG" | tr -d ' ')
  [ "$got" -eq 18 ] && ok "9 control: a stamp 30 s old pings again" || bad "9 control stale stamp" "$got lines, want 18"

  # 10. Control and bidi characters are stripped; the text around them survives.
  arm ctl
  run "$(payload sid-ctl "$(printf 'Hi\033[31mRED\342\200\256evil\tx')" "$Q")"; wait_lines 6
  got=$(sed -n 5p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  if printf '%s' "$got" | perl -CSD -ne 'exit(/[\x00-\x1F\x7F-\x9F\x{202E}]/ ? 1 : 0)'; then
    ok "10 no control or bidi character reaches imsg"
  else bad "10 control chars leaked" "$(printf '%s' "$got" | od -c | head -3)"; fi
  [ "$got" = "st-sess: question waiting: Hi [31mRED evil x" ] && ok "10 control: the printable text around them survives" || bad "10 surviving text" "$got"

  # 11. No header: first 80 chars of the question text, capped.
  arm nohdr
  run "$(payload sid-nohdr "" "$Q")"; wait_lines 6
  got=$(sed -n 5p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  [ "$got" = "st-sess: question waiting: ${Q:0:80}" ] && ok "11 empty header -> first 80 chars of the question" || bad "11 fallback text" "$got"

  # 12. Token shapes are redacted; a 300-char header is capped.
  arm tok
  run "$(payload sid-tok "" "use ghp_$(printf 'A%.0s' $(seq 36)) now")"; wait_lines 6
  got=$(sed -n 5p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  case "$got" in *ghp_*) bad "12 token leaked" "$got" ;; *'[redacted]'*) ok "12 token-shaped text -> [redacted]" ;; *) bad "12 redaction" "$got" ;; esac
  arm cap
  run "$(payload sid-cap "$(printf 'x%.0s' $(seq 300))" "$Q")"; wait_lines 6
  got=$(sed -n 5p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  [ "${#got}" -le 140 ] && [ "${#got}" -gt 100 ] && ok "12 300-char header capped (${#got} chars)" || bad "12 cap" "${#got} chars"

  # 13. Missing tools are a silent partial skip, named in the log.
  arm noto
  out="$(payload sid-noto Delivery "$Q" | env -u IMSG_TO "$0")"; rc=$?; wait_lines 4; sleep 1.5
  got=$(awk '{print $2}' "$PJ_PING_FAKE_LOG" | tr '\n' ' ')
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$got" = "afplay afplay afplay afplay " ] && ok "13 IMSG_TO unset -> sounds only, no imsg" || bad "13 IMSG_TO unset" "rc=$rc calls=$got"
  grep -q 'IMSG_TO unset' "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null && ok "13 the log names IMSG_TO" || bad "13 log IMSG_TO" "$(cat "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null)"
  arm noaf
  out="$(payload sid-noaf Delivery "$Q" | PJ_PING_AFPLAY="$root/missing/afplay" "$0")"; rc=$?; wait_lines 2
  got=$(awk '{print $2}' "$PJ_PING_FAKE_LOG" | tr '\n' ' ')
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$got" = "imsg imsg " ] && ok "13 afplay missing -> messages only, no fallback to the real afplay" || bad "13 afplay missing" "rc=$rc calls=$got"
  grep -q 'afplay missing' "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null && ok "13 the log names afplay" || bad "13 log afplay" "$(cat "$PJ_PING_STATE_DIR/question-ping.log" 2>/dev/null)"

  # 14. Session name falls back to the repo basename when the variable is unset.
  arm name
  mkdir -p "$root/fixture-repo/sub" && git -C "$root/fixture-repo" init -q 2>/dev/null
  out="$(payload sid-name Delivery "$Q" | jq -c --arg c "$root/fixture-repo/sub" '.cwd = $c' \
    | env -u CLAUDE_CODE_SESSION_NAME "$0")"; wait_lines 6
  got=$(sed -n 6p "$PJ_PING_FAKE_LOG" | cut -d' ' -f3-)
  [ "$got" = "answer the popup in fixture-repo" ] && ok "14 no CLAUDE_CODE_SESSION_NAME -> git toplevel basename" || bad "14 fallback name" "$got"

  # 15. Malformed stdin: exit 0, nothing called.
  arm bad
  out="$(printf 'not json' | "$0")"; rc=$?; sleep 1
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$PJ_PING_FAKE_LOG" ] && ok "15 malformed stdin -> exit 0, nothing called" || bad "15 malformed" "rc=$rc $(cat "$PJ_PING_FAKE_LOG")"

  # 16. The log never carries the message text.
  if grep -qE 'Delivery|cc-warehouse' "$root"/state-*/question-ping.log 2>/dev/null; then
    bad "16 message text found in a log" "$(grep -E 'Delivery|cc-warehouse' "$root"/state-*/question-ping.log)"
  elif grep -q 'pinged' "$root"/state-main/question-ping.log 2>/dev/null; then
    ok "16 logs record decisions, never the question text (control: 'pinged' found)"
  else bad "16 control: no 'pinged' line in the main log" "$(cat "$root/state-main/question-ping.log" 2>/dev/null)"; fi

  printf 'pj-question-ping selftest: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
--selftest) selftest; exit $? ;;
--send) shift; send "$@"; exit 0 ;;
--help | -h) sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

[ "${PJ_NO_PING:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "AskUserQuestion" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
NAME=$(session_name "${CWD:-$PWD}" | clean 40)
NAME="${NAME:-pj}"
# The debounce key is the session id when there is one; only [A-Za-z0-9_-]
# reaches a filename.
KEY=$(printf '%s' "${SID:-$NAME}" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)

# Debounce: the same session pinged inside the window -> skip.
NOW=$(date +%s)
LAST=$(cat "$STAMP_DIR/$KEY" 2>/dev/null)
case "$LAST" in '' | *[!0-9]*) LAST=0 ;; esac
if [ $((NOW - LAST)) -lt "$DEBOUNCE" ]; then
  log "debounced ($((NOW - LAST))s since last ping)"
  exit 0
fi
{ mkdir -p "$STAMP_DIR" && printf '%s\n' "$NOW" >"$STAMP_DIR/$KEY"; } 2>/dev/null

WHAT=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions[0].header // empty' 2>/dev/null | clean 80)
if [ -z "$WHAT" ]; then
  WHAT=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions[0].question // empty' 2>/dev/null | clean 80)
fi
MSG1="$NAME: question waiting: ${WHAT:-(no text)}"
MSG2="answer the popup in $NAME"
# imsg treats a leading dash as an option.
case "$MSG1" in -*) MSG1="pj $MSG1" ;; esac
case "$MSG2" in -*) MSG2="pj $MSG2" ;; esac

AFPLAY=$(resolve PJ_PING_AFPLAY afplay)
IMSG=$(resolve PJ_PING_IMSG imsg)
MISSING=""
[ -n "$AFPLAY" ] || MISSING="$MISSING afplay missing;"
[ -n "$IMSG" ] || MISSING="$MISSING imsg missing;"
if [ -n "$IMSG" ] && [ -z "${IMSG_TO:-}" ]; then
  MISSING="$MISSING IMSG_TO unset;"
  IMSG=""
fi
if [ -z "$AFPLAY" ] && [ -z "$IMSG" ]; then
  log "skipped:$MISSING"
  exit 0
fi
log "pinged${MISSING:+ (partial:$MISSING)}"

# Double fork with every descriptor off the hook's pipes: the hook returns now
# and the worker is reparented, so nothing Claude Code holds waits on it.
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
( KEY="$KEY" nohup "$SELF" --send "$AFPLAY" "$IMSG" "$MSG1" "$MSG2" </dev/null >/dev/null 2>&1 & ) </dev/null >/dev/null 2>&1
exit 0
