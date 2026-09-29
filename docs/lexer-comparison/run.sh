#!/bin/bash
# Lexer comparison harness (W-20260929-A50, D-20260929-A19). Black box: every
# command goes to the REAL hook as a PreToolUse payload on stdin, exactly as
# Claude Code sends it, and only the decision is read back.
#
# Run from the repo root (the hooks read sibling files, so they are never copied):
#   bash <this dir>/run.sh            -> writes cases.tsv beside this script
#
# Four hooks, one trigger each (the trigger is denied in plain form):
#   del  enforce-no-permanent-delete.sh   lexer 1 (awk block inside it)
#   sec  enforce-secret-probe.sh          lexer 1 (loaded from the file above)
#   vb   validate-bash.sh                 lexer 2 (conv-shscan.awk)
#   gh   enforce-gh-ssh-only.sh           lexer 3 (its own)
#
# Trigger text lives only in this file, never on a command line, because the
# live guards read the operator's own Bash commands too.
#
# Template placeholders: @T@ whole trigger, @W@ command word, @R@ the rest,
# @A@ first letter of the word, @B@ the remaining letters, @N@ a newline.
# Output columns (cases.tsv): id, shape, expect, cmd_del, cmd_sec, cmd_vb,
# cmd_gh, res_del, res_sec, res_vb, res_gh, why_del, why_sec, why_vb, why_gh.
# A result is ok:<decision>, MISS:<decision> (expected deny, got allow),
# FP:<decision> (expected allow, got deny) or POLICY:deny (see below). A
# backslash-newline in a command shows as \\n. Rows
# S<nn> use the trigger, D<nn> are data shapes, N<nn> repeat S<nn> with a
# near-miss command that is allowed in plain form. Newlines in a command are written
# as the two characters \n. A reason is the first 70 ASCII characters of the
# hook's permissionDecisionReason (or of additionalContext, prefixed ctx:),
# plus [the phrases naming a nested body or a fail-closed 'cannot parse'].
# LEXCMP_WHYLEN=<n> gives the first n characters instead.

set -u
REPO="${LEXCMP_REPO:-$PWD}"
HK="$REPO/home/.claude/hooks"
OUT="${LEXCMP_OUT:-$(builtin cd "$(dirname "$0")" && pwd)/cases.tsv}"   # LEXCMP_OUT, LEXCMP_WHYLEN: for reading full reasons elsewhere
[ -f "$HK/conv-shscan.awk" ] || { echo "run.sh: run from the repo root (no $HK/conv-shscan.awk)" >&2; exit 2; }
command -v jq >/dev/null || { echo "run.sh: jq missing" >&2; exit 2; }

STATE="${TMPDIR:-/tmp}/lexcmp-state"; mkdir -p "$STATE"
export DEL_GUARD_LOG=/dev/null CONV_HOOK_LOG=/dev/null GH_SSH_ONLY_LOG=/dev/null XDG_STATE_HOME="$STATE"

HOOKS="del sec vb gh"
hookfile() { case $1 in del) echo enforce-no-permanent-delete.sh;; sec) echo enforce-secret-probe.sh;;
  vb) echo validate-bash.sh;; gh) echo enforce-gh-ssh-only.sh;; esac; }
word() { case $1 in del) echo rm;; sec) echo printenv;; vb) echo git;; gh) echo gh;; esac; }
# SET=hit: the trigger. SET=near: a harmless neighbour of it (same command word,
# allowed in plain form), used to catch a hook that denies a shape by crude text
# match instead of reading it.
SET=hit
rest() { if [ "$SET" = near ]; then
    case $1 in del) echo 'x';; sec) echo 'HOME';; vb) echo 'push --force origin feature';; gh) echo 'auth status';; esac
  else
    case $1 in del) echo '-P x';; sec) echo 'GH_TOKEN';; vb) echo 'push --force origin main';; gh) echo 'auth login';; esac
  fi; }

ME="$(id -un)"
scrub() {  # one line, ASCII only, no home path or user name
  local s="$1"
  s="${s//$REPO/<repo>}"; s="${s//$HOME/~}"; s="${s//$ME/<user>}"
  s="$(printf '%s' "$s" | LC_ALL=C tr '\t\n\r' '   ' | LC_ALL=C tr -cd '\40-\176')"
  if [ -n "${LEXCMP_WHYLEN:-}" ]; then printf '%s' "${s:0:$LEXCMP_WHYLEN}"; return; fi
  # Default: the first 70 characters, plus the phrases that say HOW the hook got
  # there (which nested body, or that it could not parse and failed closed).
  local k
  k="$(printf '%s' "$s" | LC_ALL=C grep -oE 'cannot parse it \([^)]*\)|inside a nested shell body|inside [a-z -]+:|\(enforce-gh-ssh-only: [^)]*\)' | tr '\n' ' ')"
  printf '%s' "${s:0:70}"; [ -n "$k" ] && printf ' [%s]' "${k% }"
  return 0
}

# run_hook <hook> <command>  -> sets DEC (deny|ask|allow) and WHY
run_hook() {
  local out rc r c
  out="$(jq -nc --arg c "$2" --arg d "$PWD" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
        | /bin/bash "$HK/$(hookfile "$1")" 2>"$STATE/err")"; rc=$?
  DEC=allow; WHY=""
  if [ $rc -eq 2 ]; then DEC=deny; WHY="rc2:$(scrub "$(cat "$STATE/err")")"; return; fi
  [ $rc -ne 0 ] && { DEC="rc$rc"; WHY="$(scrub "$(cat "$STATE/err")")"; return; }
  [ -n "$out" ] || return
  r="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  case "$r" in deny|ask) DEC=$r; WHY="$(scrub "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')")";; esac
  if [ "$DEC" = allow ]; then
    c="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
    [ -n "$c" ] && WHY="ctx:$(scrub "$c")"
    r="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty' 2>/dev/null)"
    [ -n "$r" ] && WHY="rewrite:$(scrub "$r") $WHY"
  fi
}

render() {  # render <hook> <template>
  local w r t a b s
  w="$(word "$1")"; r="$(rest "$1")"; t="$w $r"; a="${w:0:1}"; b="${w:1}"
  s="$2"; s="${s//@T@/$t}"; s="${s//@W@/$w}"; s="${s//@R@/$r}"; s="${s//@A@/$a}"; s="${s//@B@/$b}"
  s="${s//@N@/$'\n'}"; printf '%s' "$s"
}
flat() { local s="${1//$'\n'/\\n}"; printf '%s' "$s"; }

# ------------------------------------------------------------------ controls
fail=0
for h in $HOOKS; do
  run_hook "$h" "$(render "$h" '@T@')"
  printf 'control %-3s plain trigger   -> %-5s %s\n' "$h" "$DEC" "$WHY" >&2
  [ "$DEC" = deny ] || fail=1
  run_hook "$h" 'echo ok'
  printf 'control %-3s echo ok         -> %-5s %s\n' "$h" "$DEC" "$WHY" >&2
  [ "$DEC" = allow ] || fail=1
  SET=near; run_hook "$h" "$(render "$h" '@T@')"; SET=hit
  printf 'control %-3s plain near-miss -> %-5s %s\n' "$h" "$DEC" "$WHY" >&2
  [ "$DEC" = allow ] || fail=1
done
[ $fail -eq 0 ] || { echo "run.sh: a control failed; no table written" >&2; exit 3; }

# ------------------------------------------------------------------ the shapes
# id ::: expect ::: shape name ::: template
# (read -d '' rather than $(cat <<EOF): bash 3.2 mis-parses a heredoc inside $(...)
# when the body holds backticks or unbalanced parentheses.)
read -r -d '' CASES <<'EOF'
S01 ::: deny ::: plain ::: @T@
S02 ::: deny ::: after ; ::: echo a; @T@
S03 ::: deny ::: after && ::: true && @T@
S04 ::: deny ::: after || ::: false || @T@
S05 ::: deny ::: after newline ::: echo a@N@@T@
S06 ::: deny ::: backgrounded & ::: @T@ &
S07 ::: deny ::: pipeline, right side ::: echo a | @T@
S08 ::: deny ::: pipeline, left side ::: @T@ | cat
S09 ::: deny ::: $(...) ::: echo $(@T@)
S10 ::: deny ::: "$(...)" in double quotes ::: echo "$(@T@)"
S11 ::: deny ::: backticks ::: echo `@T@`
S12 ::: deny ::: bash -c '...' ::: bash -c '@T@'
S13 ::: deny ::: sh -c "..." ::: sh -c "@T@"
S14 ::: deny ::: zsh -c '...' ::: zsh -c '@T@'
S15 ::: deny ::: bash -lc (clustered flag) ::: bash -lc '@T@'
S16 ::: deny ::: eval "..." ::: eval "@T@"
S17 ::: deny ::: eval unquoted words ::: eval @T@
S18 ::: deny ::: ( subshell ) ::: ( @T@ )
S19 ::: deny ::: { group; } ::: { @T@; }
S20 ::: deny ::: f() { ...; }; f ::: f() { @T@; }; f
S21 ::: deny ::: function f { ...; }; f ::: function f { @T@; }; f
S22 ::: deny ::: if ...; then BODY; fi ::: if true; then @T@; fi
S23 ::: deny ::: if CONDITION; then ::: if @T@; then :; fi
S24 ::: deny ::: for body ::: for i in 1; do @T@; done
S25 ::: deny ::: while body ::: while true; do @T@; break; done
S26 ::: deny ::: case arm ::: case x in x) @T@;; esac
S27 ::: deny ::: ! negation ::: ! @T@
S28 ::: deny ::: [[ ]] && cmd ::: [[ -n x ]] && @T@
S29 ::: deny ::: FOO=1 cmd ::: FOO=1 @T@
S30 ::: deny ::: redirection before the word ::: 2>/dev/null @T@
S31 ::: deny ::: redirection after ::: @T@ 2>/dev/null
S32 ::: deny ::: env ::: env @T@
S33 ::: deny ::: env -i ::: env -i @T@
S34 ::: deny ::: command ::: command @T@
S35 ::: deny ::: exec ::: exec @T@
S36 ::: deny ::: nohup ::: nohup @T@
S37 ::: deny ::: sudo ::: sudo @T@
S38 ::: deny ::: sudo -u x ::: sudo -u x @T@
S39 ::: deny ::: timeout 5 ::: timeout 5 @T@
S40 ::: deny ::: nice -n 5 ::: nice -n 5 @T@
S41 ::: deny ::: time -p ::: time -p @T@
S42 ::: deny ::: xargs ::: echo | xargs @T@
S43 ::: deny ::: caffeinate -i ::: caffeinate -i @T@
S44 ::: deny ::: stdbuf -oL ::: stdbuf -oL @T@
S45 ::: deny ::: watch -n 1 ::: watch -n 1 @T@
S46 ::: deny ::: /usr/bin/env bash -c ::: /usr/bin/env bash -c '@T@'
S47 ::: deny ::: script -q /dev/null ::: script -q /dev/null @T@
S48 ::: deny ::: heredoc fed to bash (quoted marker) ::: bash <<'EOF'@N@@T@@N@EOF
S49 ::: deny ::: heredoc fed to sh (unquoted marker) ::: sh <<EOF@N@@T@@N@EOF
S50 ::: deny ::: cat <<'EOF' | bash ::: cat <<'EOF' | bash@N@@T@@N@EOF
S51 ::: deny ::: here-string bash <<< ::: bash <<< '@T@'
S52 ::: deny ::: echo '...' | bash ::: echo '@T@' | bash
S53 ::: deny ::: printf '...' | sh ::: printf '@T@' | sh
S54 ::: deny ::: source <(echo ...) ::: source <(echo '@T@')
S55 ::: deny ::: . /dev/stdin <<< ::: . /dev/stdin <<< '@T@'
S56 ::: deny ::: process substitution <(cmd) ::: cat <(@T@)
S57 ::: deny ::: $(...) in unquoted heredoc to cat ::: cat <<EOF@N@$(@T@)@N@EOF
S58 ::: deny ::: $'word' command word ::: $'@W@' @R@
S59 ::: deny ::: 'word' single-quoted command word ::: '@W@' @R@
S60 ::: deny ::: "word" double-quoted command word ::: "@W@" @R@
S61 ::: deny ::: \word backslashed command word ::: \@W@ @R@
S62 ::: deny ::: split word w''ord ::: @A@''@B@ @R@
S63 ::: deny ::: absolute path command word ::: /usr/bin/@T@
S64 ::: deny ::: line continuation between words ::: @W@ \@N@@R@
S65 ::: deny ::: line continuation inside the word ::: @A@\@N@@B@ @R@
S66 ::: deny ::: comment line before ::: # a note@N@@T@
S67 ::: deny ::: $(...) nested twice ::: echo $(echo $(@T@))
S68 ::: deny ::: bash -c nested in bash -c ::: bash -c "bash -c '@T@'"
S69 ::: deny ::: eval of $(...) output ::: eval "$(echo '@T@')"
S70 ::: deny ::: & inside { group } ::: { @T@ & }
D01 ::: allow ::: heredoc to cat (quoted marker) ::: cat <<'EOF'@N@@T@@N@EOF
D02 ::: allow ::: heredoc to cat (unquoted marker) ::: cat <<EOF@N@@T@@N@EOF
D03 ::: allow ::: $(...) text in quoted-marker heredoc to cat ::: cat <<'EOF'@N@$(@T@)@N@EOF
D04 ::: allow ::: double-quoted echo text ::: echo "@T@"
D05 ::: allow ::: single-quoted echo text ::: echo '@T@'
D06 ::: allow ::: unquoted echo arguments ::: echo @T@
D07 ::: allow ::: git commit -m "..." ::: git commit -m "@T@"
D08 ::: allow ::: git commit -m '...' ::: git commit -m '@T@'
D09 ::: allow ::: git commit -F - with heredoc ::: git commit -F - <<'EOF'@N@@T@@N@EOF
D10 ::: allow ::: grep pattern ::: grep '@T@' notes.txt
D11 ::: allow ::: rg pattern ::: rg "@T@" docs
D12 ::: allow ::: sed pattern ::: sed -n '/@T@/p' notes.txt
D13 ::: allow ::: awk pattern ::: awk '/@T@/' notes.txt
D14 ::: allow ::: for-list words ::: for w in @T@; do echo "$w"; done
D15 ::: allow ::: assignment X='...' ::: X='@T@'
D16 ::: allow ::: assignment X="..." ::: X="@T@"
D17 ::: allow ::: comment only ::: # @T@
D18 ::: allow ::: printf %s data ::: printf '%s\n' '@T@'
D19 ::: allow ::: echo text redirected to a file ::: echo '@T@' > notes.txt
D20 ::: allow ::: echo text piped to cat ::: echo "@T@" | cat
D21 ::: allow ::: git log --grep= ::: git log --grep='@T@'
D22 ::: allow ::: quoted sh -c text inside echo ::: echo "sh -c '@T@'"
D23 ::: allow ::: jq --arg value ::: jq -n --arg c '@T@' '$c'
D24 ::: allow ::: heredoc to tee a doc file ::: tee notes.md <<'EOF'@N@run @T@ never@N@EOF
EOF

# Every S row again with the near-miss set, expected to allow: N<nn>.
NEAR="$(printf '%s\n' "$CASES" | sed -n 's/^S\([0-9]*\) ::: deny ::: /N\1 ::: allow ::: near-miss, /p')"
CASES="$CASES
$NEAR"

TAB=$'\t'
{
  printf 'id\tshape\texpect\tcmd_del\tcmd_sec\tcmd_vb\tcmd_gh\tres_del\tres_sec\tres_vb\tres_gh\twhy_del\twhy_sec\twhy_vb\twhy_gh\n'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line%% ::: *}"; x="${line#* ::: }"
    exp="${x%% ::: *}"; x="${x#* ::: }"
    name="${x%% ::: *}"; tpl="${x#* ::: }"
    cmds=""; ress=""; whys=""
    case $id in N*) SET=near;; *) SET=hit;; esac
    for h in $HOOKS; do
      cmd="$(render "$h" "$tpl")"
      run_hook "$h" "$cmd"
      if [ "$DEC" = "$exp" ]; then tag=ok
      elif [ "$exp" = deny ]; then tag=MISS
      else tag=FP; fi
      # A delete-guard deny for routing plain rm past the Trash wrapper (env,
      # sudo, a path) is that hook's policy, not a misread: tagged POLICY.
      case "$tag:$h:$WHY" in FP:del:*'(rm-lookup)'*|FP:del:*'(rm-path)'*) tag=POLICY;; esac
      cmds="$cmds$TAB$(flat "$cmd")"; ress="$ress$TAB$tag:$DEC"; whys="$whys$TAB$WHY"
    done
    printf '%s\t%s\t%s%s%s%s\n' "$id" "$name" "$exp" "$cmds" "$ress" "$whys"
    printf '.' >&2
  done <<< "$CASES"
} > "$OUT"
printf '\nwrote %s (%s rows)\n' "$OUT" "$(( $(wc -l < "$OUT") - 1 ))" >&2
