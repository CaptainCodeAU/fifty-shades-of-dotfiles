#!/bin/bash
# pj-voice-contract.sh -- state the voice contract BEFORE the reply is written,
# and name what the previous reply actually broke. Runs on UserPromptSubmit.
# Never blocks: every path exits 0.
#
# WHY THIS EXISTS (P9, 2026-09-22). pj-voice rule V4 says "No em dashes, ever."
# Measured across 17 pj transcripts, 174,107 characters of assistant prose
# outside code blocks: 371 em dashes. Every other voice rule in the file was
# obeyed -- 0 filler openers, 0 hedges, 0 banned words -- so the file is not
# being ignored, this one rule is.
#
# THE DEFECT IS MODEL-SPECIFIC, and that is the single most important fact
# here. Split the same 17 transcripts by model:
#     claude-opus-5       371 em dashes in 157,774 prose chars   1 per 425
#     claude-fable-5-1      0 em dashes in  15,725 prose chars   none
# Same rules file, same output style, same repo. So V4 holds on one model and
# not on the other, and any count taken without naming the model is not a
# measurement. That is why this hook logs the model on every line.
#
# THE WORDING IS NOT THE PROBLEM. DA_IDENTITY.md line 45, which the `c` family
# loads, says "no em dashes, ever, use commas or full stops" -- almost word for
# word what V4 says, and the `c` family is clean.
#
# BUT THE `c` COMPARISON IS THINNER THAN IT FIRST LOOKED, and the first version
# of this comment overstated it. The `c` control set is 19,505 characters of
# prose with zero em dashes, and 15,831 of those characters are FABLE, which
# produces zero under pj as well. The arm that actually compares is `c` on
# Opus: 3,674 characters, 0 observed against about 9 predicted at the pj Opus
# rate. Real, and thin. Do not cite the 19,505 figure.
#
# What the `c` family has that pj does not is DriftReminder.hook.ts, which
# COUNTS. It is registered only in ~/.claude/settings.json, and pj passes
# --setting-sources project,local, so it has never fired here: its contract
# line appears twice in a `c` transcript and zero times in 35.3 MB of pj
# transcript. THAT separation is measured and solid. The inference from it,
# that counting is WHY `c` is clean, is a hypothesis: the one `c` transcript
# carrying the contract line ran on Fable, which is clean anyway. So this hook
# addresses a real, measured, Opus-specific defect by a mechanism with good
# evidence behind it and no proof yet. The log below is how that gets settled.
#
# WHY UserPromptSubmit AND NOT Stop. DriftReminder's own header records the
# measurement: FormatGate was a Stop hook, went observation-only 2026-07-11,
# and drift went from 0% across 168 turns to 61-91% every day across 2,608.
# A Stop hook fires after the text is on screen and can only block, which
# forces a doubled re-emit. Separately, on this machine peer-reply-check.sh
# prints on Stop with exit 0 and nothing sees it. Checking before the answer
# is written is the only point that works.
#
# WHY NOT JUST CARRY DriftReminder. It runs standalone, but its contract is
# hardcoded to "banner first, closer last, max 2 em-dashes" and its only
# environment seam is LIFEOS_DIR, a path. pj-voice defines no banner and no
# closer, and V4 says zero rather than two, so carrying it unedited would put
# a contract into every pj turn that is wrong in all three clauses, and would
# write state into lifeos-private. Ruled at the P9 gate: build a pj-side one.
#
# WHY EVERY TURN AND NOT ONLY ON A BREAK. Same header, same measurement: the
# old MIN_TURNS_BETWEEN_FIRES budget left the nudge silent 4 turns in 5, which
# is why 80% drift went unnoticed. The line is one sentence.
#
# CODE BLOCKS ARE NOT PROSE. An em dash inside a fence or inside inline
# backticks is quoted material or a shell command and is not a V4 violation.
# Counting it would make the hook cry wolf, which is the failure this repo
# cares most about. Arms 3 and 4 of --selftest are exactly that case.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all pass.

# THE LOG (Gavin, 2026-09-22). One line per turn, so the hook's effect is
# measured automatically instead of by a one-off scan somebody has to remember
# to run. TSV: timestamp, session (8 chars), turn, model, em dashes, prose
# chars. The MODEL field is not decoration and was not in the original request:
# the header above shows the defect is Opus-specific, so a count without a
# model beside it cannot be read at all.
#
# Turn is the number of assistant text blocks in the transcript when this hook
# fired, which is a measured number rather than a counter this hook keeps.
# Never blocks: an unwritable log is skipped in silence, because a voice hook
# that fails a prompt over a log file would be worse than the drift.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pj"
LOG_FILE="${PJ_VOICE_DRIFT_LOG:-$LOG_DIR/voice-drift.log}"

EM=$(printf '\xe2\x80\x94')

# Count em dashes in assistant PROSE: outside fenced blocks, outside inline backticks.
count_prose_em() {
  awk -v em="$EM" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, " ", line)
      n = gsub(em, "", line)
      total += n
    }
    END { print total + 0 }
  '
}

# Characters of PROSE, same definition as the counter above: the denominator
# without which an em-dash count means nothing.
strip_code_chars() {
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, " ", line)
      total += length(line) + 1
    }
    END { print total + 0 }
  '
}

# Last assistant visible text from a transcript, or nothing.
last_assistant_text() {
  local tr="$1"
  [ -n "$tr" ] && [ -r "$tr" ] || return 0
  tail -n 400 "$tr" 2>/dev/null | jq -rs '
    [ .[] | select(.type == "assistant")
          | .message.content[]? | select(.type == "text") | .text ]
    | last // empty' 2>/dev/null
}

# Model of the last assistant message, or "?" when it cannot be read.
last_model() {
  local tr="$1"
  [ -n "$tr" ] && [ -r "$tr" ] || { printf '?'; return 0; }
  tail -n 400 "$tr" 2>/dev/null | jq -rs '
    [ .[] | select(.type == "assistant") | .message.model // empty ] | last // "?"' 2>/dev/null
}

# Number of assistant text blocks so far: the turn this reply was.
turn_no() {
  local tr="$1"
  [ -n "$tr" ] && [ -r "$tr" ] || { printf '0'; return 0; }
  jq -s '[ .[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") ] | length' \
    "$tr" 2>/dev/null || printf '0'
}

log_turn() { # log_turn <session> <turn> <model> <em> <prose_chars>
  # The braces matter: a FAILED APPEND is a redirection error, raised by the
  # shell before the command's own 2>/dev/null can apply, so the bare form
  # printed "Operation not permitted" to stderr on every turn in a sandbox.
  # A voice hook that prints an error every prompt is noise of exactly the kind
  # this repo says trains you to skim. Measured 2026-09-22.
  { mkdir -p "$(dirname "$LOG_FILE")" || return 0
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1:0:8}" "$2" "$3" "$4" "$5" >>"$LOG_FILE"
  } 2>/dev/null
  return 0
}

emit() {
  jq -cn --arg c "$1" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}' 2>/dev/null
}

contract() {
  local n="$1" base
  base="VOICE CONTRACT (check before writing, not after): pj-voice V4, ZERO em dashes in prose; commas, full stops, or restructure."
  if [ -z "$n" ]; then
    printf '%s' "$base"
  elif [ "$n" -gt 0 ] 2>/dev/null; then
    printf '%s Last reply broke it: %s em dash(es) outside code.' "$base" "$n"
  else
    printf '%s Last reply was clean.' "$base"
  fi
}

selftest() {
  local root pass=0 fail=0 out n
  root="$(mktemp -d "${TMPDIR:-/tmp}/pj-voice-contract-selftest.XXXXXX")" || exit 1
  # Never let a selftest write into the real drift log: its rows would be
  # fixtures sitting in what is meant to be a record of real turns.
  export PJ_VOICE_DRIFT_LOG="$root/drift.log"
  ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
  bad() { fail=$((fail + 1)); printf '  FAIL %s\n       got: %s\n' "$1" "$2"; }
  mk() { printf '%s\n' "$2" | jq -Rs '{type:"assistant",message:{content:[{type:"text",text:.}]}}' > "$1"; }
  echo "pj-voice-contract selftest in $root"

  # 1. POSITIVE: two prose em dashes are counted and named
  mk "$root/a.jsonl" "A reply with one${EM}and another${EM}here."
  out="$(printf '{"transcript_path":"%s"}' "$root/a.jsonl" | "$0")"
  case "$out" in *'broke it: 2 em dash'*) ok "1 two prose em dashes -> counted as 2" ;; *) bad "1 two prose em dashes" "$out" ;; esac

  # 2. NEGATIVE CONTROL: a clean reply must NOT report a break
  mk "$root/b.jsonl" "A clean reply. No dashes at all."
  out="$(printf '{"transcript_path":"%s"}' "$root/b.jsonl" | "$0")"
  case "$out" in
    *'broke it'*) bad "2 clean reply must not report a break" "$out" ;;
    *'Last reply was clean'*) ok "2 clean reply -> says clean, no break" ;;
    *) bad "2 clean reply" "$out" ;;
  esac

  # 3. NEGATIVE CONTROL: an em dash inside a fenced block is not prose
  mk "$root/c.jsonl" "Prose with none.
\`\`\`
echo a${EM}b
\`\`\`
More prose."
  out="$(printf '{"transcript_path":"%s"}' "$root/c.jsonl" | "$0")"
  case "$out" in
    *'broke it'*) bad "3 fenced em dash must not count" "$out" ;;
    *'Last reply was clean'*) ok "3 em dash inside a fence -> not counted" ;;
    *) bad "3 fenced em dash" "$out" ;;
  esac

  # 4. NEGATIVE CONTROL: an em dash inside inline backticks is not prose
  mk "$root/d.jsonl" "See \`a${EM}b\` for the flag."
  out="$(printf '{"transcript_path":"%s"}' "$root/d.jsonl" | "$0")"
  case "$out" in
    *'broke it'*) bad "4 inline-code em dash must not count" "$out" ;;
    *'Last reply was clean'*) ok "4 em dash inside inline backticks -> not counted" ;;
    *) bad "4 inline-code em dash" "$out" ;;
  esac

  # 4b. CONTROL ON THE CONTROLS: the same text OUTSIDE code still counts,
  #     so arms 3 and 4 are proving the fence rule and not a dead counter.
  mk "$root/d2.jsonl" "See a${EM}b for the flag."
  out="$(printf '{"transcript_path":"%s"}' "$root/d2.jsonl" | "$0")"
  case "$out" in *'broke it: 1 em dash'*) ok "4b same text outside code -> counted (controls are live)" ;; *) bad "4b control on the controls" "$out" ;; esac

  # 5. no transcript: still emits the bare contract, exit 0
  out="$(printf '{"transcript_path":"%s/nope.jsonl"}' "$root" | "$0")"; n=$?
  case "$out" in
    *'VOICE CONTRACT'*) [ "$n" -eq 0 ] && ok "5 missing transcript -> bare contract, exit 0" || bad "5 exit code" "rc=$n" ;;
    *) bad "5 missing transcript" "$out" ;;
  esac
  case "$out" in *'broke it'*|*'was clean'*) bad "5 must not claim to have measured anything" "$out" ;; *) ok "5 says nothing about a previous reply it never read" ;; esac

  # 6. malformed stdin: exit 0, no crash
  out="$(printf 'not json at all' | "$0")"; n=$?
  [ "$n" -eq 0 ] && ok "6 malformed stdin -> exit 0" || bad "6 malformed stdin" "rc=$n"

  # 7. first turn (transcript with no assistant message yet)
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' > "$root/e.jsonl"
  out="$(printf '{"transcript_path":"%s"}' "$root/e.jsonl" | "$0")"
  case "$out" in
    *'broke it'*|*'was clean'*) bad "7 first turn must not report on a reply that does not exist" "$out" ;;
    *'VOICE CONTRACT'*) ok "7 first turn -> bare contract only" ;;
    *) bad "7 first turn" "$out" ;;
  esac

  # 8. output is valid JSON with the right event name
  mk "$root/f.jsonl" "clean"
  out="$(printf '{"transcript_path":"%s"}' "$root/f.jsonl" | "$0")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1; then
    ok "8 emits valid JSON naming UserPromptSubmit"
  else bad "8 JSON shape" "$out"; fi

  # 9. THE LOG. One TSV row per measured turn: ts, session, turn, model, em, prose chars.
  : >"$PJ_VOICE_DRIFT_LOG"
  printf '%s\n' \
    '{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"text","text":"one'"$EM"'two"}]}}' \
    >"$root/g.jsonl"
  printf '{"session_id":"abcdefgh-1111","transcript_path":"%s"}' "$root/g.jsonl" | "$0" >/dev/null
  n="$(wc -l <"$PJ_VOICE_DRIFT_LOG" | tr -d ' ')"
  [ "$n" -eq 1 ] && ok "9 one measured turn -> exactly one log row" || bad "9 log rows" "$n"
  IFS=$'\t' read -r _ts _sid _turn _model _em _prose <"$PJ_VOICE_DRIFT_LOG"
  [ "$_sid" = "abcdefgh" ] && ok "9 row carries the 8-char session" || bad "9 session field" "$_sid"
  [ "$_model" = "claude-opus-5" ] && ok "9 row carries the MODEL (the field that decides how to read the count)" || bad "9 model field" "$_model"
  [ "$_em" -eq 1 ] 2>/dev/null && ok "9 row carries the em-dash count" || bad "9 em field" "$_em"
  [ "$_turn" -eq 1 ] 2>/dev/null && ok "9 row carries the turn number" || bad "9 turn field" "$_turn"
  [ "$_prose" -gt 0 ] 2>/dev/null && ok "9 row carries prose chars, the denominator" || bad "9 prose field" "$_prose"

  # 9b. CONTROL: a clean turn is logged too, at zero. A log that only records
  #     breaks cannot produce a RATE, and a rate is the whole point.
  : >"$PJ_VOICE_DRIFT_LOG"
  mk "$root/h.jsonl" "clean prose, no dashes"
  printf '{"session_id":"zzzz1111","transcript_path":"%s"}' "$root/h.jsonl" | "$0" >/dev/null
  IFS=$'\t' read -r _ts _sid _turn _model _em _prose <"$PJ_VOICE_DRIFT_LOG" 2>/dev/null
  [ "${_em:-x}" = "0" ] && ok "9b a clean turn is logged at 0, so the log yields a rate not a tally" || bad "9b clean turn logged" "${_em:-<no row>}"

  # 10. CONTROL: nothing is logged when there was no previous reply to measure.
  : >"$PJ_VOICE_DRIFT_LOG"
  printf '{"session_id":"nope","transcript_path":"%s/absent.jsonl"}' "$root" | "$0" >/dev/null
  [ ! -s "$PJ_VOICE_DRIFT_LOG" ] && ok "10 no previous reply -> no log row invented" || bad "10 logged something it never measured" "$(cat "$PJ_VOICE_DRIFT_LOG")"

  # 11. An unwritable log must not break the prompt.
  mkdir -p "$root/ro" && chmod 500 "$root/ro"
  out="$(printf '{"session_id":"x","transcript_path":"%s/g.jsonl"}' "$root" | PJ_VOICE_DRIFT_LOG="$root/ro/sub/drift.log" "$0" 2>/dev/null)"; n=$?
  chmod 700 "$root/ro"
  case "$out" in *'VOICE CONTRACT'*) [ "$n" -eq 0 ] && ok "11 unwritable log -> contract still emitted, exit 0" || bad "11 exit" "rc=$n" ;; *) bad "11 unwritable log" "$out" ;; esac

  printf 'pj-voice-contract selftest: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
--selftest) selftest; exit $? ;;
--help | -h) sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
TR=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

TEXT=$(last_assistant_text "$TR")
if [ -z "$TEXT" ]; then
  emit "$(contract "")"
else
  N=$(printf '%s\n' "$TEXT" | count_prose_em)
  PROSE=$(printf '%s\n' "$TEXT" | strip_code_chars)
  log_turn "$SID" "$(turn_no "$TR")" "$(last_model "$TR")" "$N" "$PROSE"
  emit "$(contract "$N")"
fi
exit 0
