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
# AND THE WORDING IS NOT THE PROBLEM. DA_IDENTITY.md line 45, which the `c`
# family loads, says "no em dashes, ever, use commas or full stops" -- almost
# word for word what V4 says. The control set of 8 non-pj transcripts, 19,505
# characters of prose, contains ZERO. Same rule, opposite outcome.
#
# What the `c` family has that pj does not is DriftReminder.hook.ts, which
# COUNTS. It is registered only in ~/.claude/settings.json, and pj passes
# --setting-sources project,local, so it has never fired here: its contract
# line appears twice in a `c` transcript and zero times in 35.3 MB of pj
# transcript. That separation, with a positive arm in the control, is the
# whole argument for this file.
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

# Last assistant visible text from a transcript, or nothing.
last_assistant_text() {
  local tr="$1"
  [ -n "$tr" ] && [ -r "$tr" ] || return 0
  tail -n 400 "$tr" 2>/dev/null | jq -rs '
    [ .[] | select(.type == "assistant")
          | .message.content[]? | select(.type == "text") | .text ]
    | last // empty' 2>/dev/null
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

TEXT=$(last_assistant_text "$TR")
if [ -z "$TEXT" ]; then
  emit "$(contract "")"
else
  N=$(printf '%s\n' "$TEXT" | count_prose_em)
  emit "$(contract "$N")"
fi
exit 0
