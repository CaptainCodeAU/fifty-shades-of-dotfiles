#!/bin/bash
# Block the shell probe that prints a secret while looking like it hides one.
# PreToolUse on Bash. Sibling of enforce-census.sh: same payload contract, same
# jq-must-shout rule, but this one DENIES instead of reminding.
#
# WHY IT EXISTS -- measured, not felt
#   Audited ~/.claude/projects on 2026-09-17. Two real credentials were sitting in
#   local transcripts, one for three months. Neither was written there by a tool.
#   Agents typed them, in commands written to be CAREFUL:
#
#     echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"   -> yes<the whole token>
#     echo "interactive-shell sees it: ${V:+SET}${V:-unset}" -> SET<the whole token>
#     env | grep -i git                                      -> GH_TOKEN=<the whole token>
#
#   `${V:-word}` does NOT mean "print word instead of the value". It means "use word
#   ONLY if V is empty", so when V IS set it expands to the value. The author wanted
#   yes/no and got yes-plus-secret. It reads as a redaction and is an expansion, which
#   is why nobody reviewing those commands looked twice.
#
#   Prose alone does not stop this: the rule now lives in OPERATIONAL_RULES.md, but the
#   two leaks were written by sessions that had every count-and-absence rule loaded and
#   still typed the probe. This fires at the only moment that helps.
#
# 🔴 WHY IT BLOCKS RATHER THAN WARNS
#   A warning arrives in the same breath as the output. By then the secret is in the
#   transcript and the transcript is append-only. There is no "undo" for a printed key,
#   so the only useful intervention is BEFORE the command runs.
#
# 🔴 AND WHY A MISSING jq MUST SHOUT
#   `command -v jq || exit 0` would make this hook silent in every project forever, and
#   silence here is indistinguishable from a clean bill of health. Same reasoning as
#   enforce-census.sh, same remedy: say so, loudly, every time.
#
# SINCE 2026-09-29 (W-20260929-A34, red team row H4) it also reads the command with
#   the shell lexer of enforce-no-permanent-delete.sh (see "the shell lexer" below) and
#   denies the printers that name no ${...}: printenv NAME, bare env/printenv/set/
#   export -p/declare -x/typeset -p, gh auth token|status, security ... -w|-g,
#   git credential fill, reading a .env / private key / .netrc, ps with environments,
#   infisical export, python -c / node -e dumping the whole environment. A `sh -c`,
#   `eval`, `env -S` body, and a heredoc or pipe fed to a shell, are classified again
#   with every rule. Words inside a message, a pattern or a heredoc for a non-shell
#   stay DATA: the lexer keeps a quoted span as one word, it does not delete it.
#   A printer inside $(...) is denied too: the lexer cannot tell whether the captured
#   value is printed later, and the pinned rule is caution.
#
# WHAT IT DELIBERATELY DOES NOT CATCH
#   A printer hidden in a script, an alias or a function; a name held in a variable
#   (`$cmd`); a subscript read in inline code (os.environ["GH_TOKEN"]); a recursive
#   search for key names (rg API_KEY ~/.config); github-agent-token token, which the
#   git-auth recovery rule tells the model to run. The ${...} rules still skip heredoc
#   bodies, for the reason the sibling hooks do: prose must not fire a gate.
#
#   `--selftest` proves every arm, positive AND negative. A block rule with no negative
#   arm cannot tell "correctly silent" from "broken and silent".

set -uo pipefail

# A variable whose NAME says it holds a credential. Kept deliberately narrow: this must
# not fire on TMPDIR, EDITOR or PATH, or the block becomes something to route around.
# PAT counts only as a whole _-separated part (GH_PAT, PAT_RO): until 2026-09-29 it
# matched inside PATH, so `echo "$PATH"` was denied. Where the pattern is not followed
# by a fixed character it is used with SECRET_END, so $PATH cannot match as $PAT + H.
SECRETY='([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|_KEY|CREDENTIAL|PRIVKEY)[A-Za-z0-9_]*|([A-Za-z0-9]+_)*PAT(_[A-Za-z0-9]+)*)'
SECRET_END='([^A-Za-z0-9_]|$)'
RE_SECRET_NAME="^${SECRETY}\$"

# Commands that print a credential with no ${...} in sight (W-20260929-A34). The
# crude text form, for when the payload or the lexer cannot be read.
CRUDE='(^|[^A-Za-z0-9_.-])(printenv|gh[[:space:]]+auth|find-(generic|internet)-password|credential[[:space:]]+fill|eval|infisical[[:space:]]+export)([^A-Za-z0-9_-]|$)|(^|[;&|(])[[:space:]]*(env|set|export|declare|typeset)[[:space:]]*($|[;&|)])|(^|[^A-Za-z0-9_.-])(ba|z|da|k)?sh[[:space:]]+-[A-Za-z]*c|\.env([[:space:]"'"'"']|$)|os\.environ|process\.env'

# The crude match on the RAW payload, used ONLY when the payload cannot be read
# (jq missing, invalid JSON, no tool_input.command; D-20260925-A03). Any
# expansion of a credential-named variable, ${#V} included (it cannot be told
# apart here), an env/printenv piped anywhere, or a CRUDE hit. A hit DENIES by name.
RAW_TRIGGER='\$\{?#?'"$SECRETY$SECRET_END"'|(^|[^A-Za-z0-9_.-])(env|printenv)([[:space:]]+-[A-Za-z0-9]+)*[[:space:]]*\||'"$CRUDE"

# A VALUE-STRIPPER in the command: `env | cut -d= -f1` prints names, not values.
STRIPPER='cut[[:space:]]+-d[[:space:]]*['"'"'"]?=['"'"'"]?[[:space:]]+-f[[:space:]]*1|awk[[:space:]]+-F[[:space:]]*['"'"'"]?=|s/=\.\*//'

# ---------------------------------------------------------------- the shell lexer
# NOT a copy. The awk lexer in enforce-no-permanent-delete.sh (the block between
# `read -r -d '' LEXER <<'AWK'` and `AWK`) is read from that file at run time, so
# there is one lexer on this machine. It splits a command into simple commands the
# way zsh does: quotes removed, heredoc bodies and here-strings set aside as stdin
# data, every $(...) and `...` body emitted as a command of its own. Records:
#   C <pid> <word>...   a simple command (redirection operators are OPM-prefixed words)
#   H <pid> <text>      stdin data for pipeline <pid> (heredoc, here-string, echo data)
#   E <maxpid>          always last; its absence means the lexer failed
# Both files are stowed side by side into ~/.claude/hooks. When the block cannot be
# read, the CRUDE text match stands in (deny by name) and the hook SHOUTS.
US=$'\037'; RSC=$'\036'; OPM=$'\002'
case "$0" in */*) _here="${0%/*}" ;; *) _here=. ;; esac
LEXER_FROM="${SECRET_PROBE_LEXER_FROM:-$_here/enforce-no-permanent-delete.sh}"
LEXER="$(sed -n "/^read -r -d '' LEXER <<'AWK'\$/,/^AWK\$/p" "$LEXER_FROM" 2>/dev/null | sed '1d;$d')"
case "$LEXER" in *'function emitcmd('*'function lex('*) ;; *) LEXER="" ;; esac

# ---------------------------------------------------------------- matching engine
# Returns the reason on stdout, or nothing. Never echoes the command back, and never
# echoes a value: a guard that quotes the secret in its own refusal is the bug again.
_classify() { # $1 = shell text, $2 = nesting depth (sh -c / eval / stdin shell)
  local cmd="$1" depth="${2:-0}" bare reason=""

  # Strip heredoc bodies, then quoted spans, then comments -- identical order to
  # enforce-census.sh, for the identical reason (prose must not fire a gate).
  local hd='BEGIN{inhd=0}
inhd==0{
  if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
    tag=substr($0,RSTART,RLENGTH); sub(/^<<-?[ \t]*/,"",tag); gsub(/["\047]/,"",tag)
    inhd=1; hd=tag
  }
  print; next
}
{ t=$0; sub(/^[ \t]+/,"",t); if (t==hd) { inhd=0; hd="" } ; next }'
  # A comment starts at a word boundary only. Until 2026-09-29 every `#` cut the line,
  # so `echo "${#GH_TOKEN} $GH_TOKEN"` lost its second half and printed the token.
  bare="$(printf '%s' "$cmd" | awk "$hd" | sed -E 's/(^|[[:space:]])#.*$/\1/')"

  # RULE 1 -- the default-substitution leak. `${V:-word}` / `${V-word}` on a secret-named
  # variable, where word is NON-EMPTY. `${V:-}` is excluded on purpose: an empty default
  # is the standard set -u guard and prints nothing extra.
  if [[ "$bare" =~ \$\{$SECRETY:?-[^\}\"\'][^\}]*\} ]]; then
    reason="RULE 1: \${VAR:-word} on a credential variable"
  fi

  # RULE 2 -- dumping the whole environment. `env` or `printenv` with no variable named,
  # piped anywhere. This is how the second real token reached a transcript.
  if [ -z "$reason" ] && [[ "$bare" =~ (^|[|;\&\(]|\&\&)[[:space:]]*(env|printenv)([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]*\| ]]; then
    # ...unless a VALUE-STRIPPER is in the pipeline. `env | cut -d= -f1 | grep -i token`
    # is the form this hook's own advice recommends, and blocking the recommended fix is
    # how a gate teaches people to route around it. Checked across the whole command
    # rather than strictly the next stage: over-permissive by a hair, and the hair is
    # cheaper than refusing the safe answer.
    if ! [[ "$bare" =~ $STRIPPER ]]; then
      reason="RULE 2: env/printenv dumped and filtered -- prints every matching VALUE"
    fi
  fi

  # RULE 3 -- a bare secret variable inside echo/printf/print. `${#V}` (length) is
  # allowed, and so is `${V:+literal}` on its own, because neither can expand to the
  # value. So is a stage piped straight into a hash or a byte count: that is the
  # fingerprint this hook's own advice recommends, and it was denied until 2026-09-29.
  if [ -z "$reason" ]; then
    local echoes
    local hashers='(shasum|sha1sum|sha256sum|sha512sum|md5|md5sum|b2sum|openssl[[:space:]]+dgst|wc[[:space:]]+-[cm])'
    echoes="$(printf '%s' "$bare" | grep -oE '(^|[|;&(]|&&)[[:space:]]*(echo|printf|print)[^|;&]*(\|[[:space:]]*'"$hashers"')?' 2>/dev/null | grep -vE '\|[[:space:]]*'"$hashers"'$' || true)"
    if [ -n "$echoes" ]; then
      local stripped
      stripped="$(printf '%s' "$echoes" | sed -E "s/\\\$\{#$SECRETY\}//g; s/\\\$\{$SECRETY:\+[^\}]*\}//g")"
      if [[ "$stripped" =~ \$\{?$SECRETY$SECRET_END ]]; then
        reason="RULE 3: a credential variable expanded inside echo/printf/print"
      fi
    fi
  fi

  # RULES 4+ -- commands that print a secret without naming a ${...}: read by the lexer.
  if [ -z "$reason" ]; then
    R=""
    _lexed "$cmd" "$depth"
    reason="$R"
  fi

  printf '%s' "$reason"
}

# ---------------------------------------------------------------- lexer-based rules
# Each sets R to the reason, which names the SAFE form, and returns.
SAFE_NAMES='SAFE: names only, no values: env | cut -d= -f1 | grep -i token'
RE_ASSIGN='^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?='
RE_ENVDUMP='(os\.environ|process\.env)([^].[A-Za-z0-9_]|$)'
MAX_DEPTH=4

# The CRUDE stand-in, when the lexer is missing or failed on this text.
_crude() { # $1 = text, $2 = why the lexer could not be used
  [[ $1 =~ $CRUDE ]] || return 0
  R="the shell lexer could not be used ($2), and this command mentions a secret printer (printenv, env, gh auth, security -w, credential fill, a .env file, sh -c, eval). Denied by name. Check that enforce-no-permanent-delete.sh sits beside this hook, then run enforce-secret-probe.sh --selftest."
}

_lexed() { # $1 = text, $2 = depth. Sets R.
  local text="$1" depth="$2" recs line rest pid k
  if [ "$depth" -ge "$MAX_DEPTH" ]; then
    R="RULE 12: shell text nested $MAX_DEPTH deep (sh -c inside eval inside ...) is not read further. SAFE: run the inner command directly."
    return 0
  fi
  [ -n "$LEXER" ] || { _crude "$text" "not found in $LEXER_FROM"; return 0; }
  recs="$(printf '%s' "$text" | LC_ALL=C awk -v base=0 -v snap= -v nofilter=1 "$LEXER" 2>/dev/null)" \
    || { _crude "$text" "it exited non-zero"; return 0; }
  [[ $recs == *"E$US"* ]] || { _crude "$text" "it gave no end record"; return 0; }
  CUR_TEXT="$text"; STDIN_SH=" "
  local -a hp=() hb=() words=() a=()
  while IFS= read -r line; do
    case "$line" in
      C"$US"*)
        rest="${line#C"$US"}"; CUR_PID="${rest%%"$US"*}"; rest="${rest#*"$US"}"
        IFS="$US" read -r -a words <<< "$rest"
        a=(); k=0
        while [ "$k" -lt "${#words[@]}" ]; do
          if [[ ${words[$k]} == "$OPM"* ]]; then k=$((k + 2)); continue; fi   # an operator and its target
          a[${#a[@]}]="${words[$k]//$RSC/$'\n'}"; k=$((k + 1))
        done
        [ "${#a[@]}" -gt 0 ] && _argv "$depth" "${a[@]}" ;;
      H"$US"*)
        rest="${line#H"$US"}"; pid="${rest%%"$US"*}"
        hp[${#hp[@]}]="$pid"; hb[${#hb[@]}]="${rest#*"$US"}" ;;
    esac
    [ -n "$R" ] && return 0
  done <<< "$recs"
  # stdin data (a heredoc, a here-string, echo piped in) read by a shell as commands
  k=0
  while [ -z "$R" ] && [ "$k" -lt "${#hp[@]}" ]; do
    case "$STDIN_SH" in *" ${hp[$k]} "*) _sub "$depth" "${hb[$k]//$RSC/$'\n'}" "a shell reading stdin" ;; esac
    k=$((k + 1))
  done
  return 0
}

_sub() { # $1 = depth, $2 = shell text, $3 = where it came from. Sets R.
  local r
  r="$(_classify "$2" $(($1 + 1)))"
  [ -n "$r" ] && R="inside $3: $r"
  return 0
}

_dump() { # $1 = what. A whole-environment listing, unless a value-stripper is in play.
  [[ $CUR_TEXT =~ $STRIPPER ]] && return 0
  R="RULE 4: $1 lists every variable WITH its value, tokens included. $SAFE_NAMES"
}

_secret_file() { # $1 = a word. True when it names a file that holds secrets.
  local p="$1" b t
  b="${p##*/}"
  case "$b" in
    .env.example|.env.sample|.env.template|.env.dist|.env.defaults) return 1 ;;
    .env|.env.*|*.env|.netrc|.pgpass|credentials|*.pem|*.key|*.p12|*.pfx) return 0 ;;
    id_*.pub) return 1 ;;
  esac
  case "$p" in */.ssh/id_*|id_rsa|id_dsa|id_ecdsa|id_ed25519) return 0 ;; esac
  # a symlink whose TARGET is one (~/.claude/.env is caught by its own name above)
  case "$p" in '~/'*) p="$HOME/${p#'~/'}" ;; '$HOME/'*) p="$HOME/${p#'$HOME/'}" ;; esac
  if [ -L "$p" ]; then
    t="$(readlink "$p" 2>/dev/null)"; t="${t##*/}"
    case "$t" in .env.example|.env.sample|.env.template) return 1 ;; .env|.env.*|*.env|*.pem|*.key) return 0 ;; esac
  fi
  return 1
}

_argv() { # $1 = depth, then one simple command's words. Sets R.
  local depth="$1"; shift
  while [ $# -gt 0 ] && [[ $1 =~ $RE_ASSIGN ]]; do shift; done
  [ $# -gt 0 ] || return 0
  local c="${1#=}"; shift
  local base="${c##*/}" w opts names joined first
  case "$base" in
    # ---- look past precommands, as enforce-no-permanent-delete.sh does
    '{'|'!'|if|then|else|elif|do|while|until|-|nohup|noglob|nocorrect|builtin|unbuffer|chronic)
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    command)
      while [ $# -gt 0 ]; do case "$1" in -*[vV]*) return 0 ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    exec)
      while [ $# -gt 0 ]; do case "$1" in -a) shift 2 || set -- ;; -c|-l|-cl|-lc) shift ;; --) shift; break ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    time)
      while [ $# -gt 0 ]; do case "$1" in -o) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    sudo|doas)
      while [ $# -gt 0 ]; do case "$1" in --) shift; break ;; -u|-g|-h|-p|-C|-D|-r|-t|-T|-U|-c) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    nice)
      while [ $# -gt 0 ]; do case "$1" in -n) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    timeout|gtimeout)
      while [ $# -gt 0 ]; do case "$1" in -s|-k) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && shift
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    xargs|gxargs)
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -I|-n|-P|-L|-s|-d|-E|-a|-J|-R|-S) shift 2 || set -- ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    eval)
      [ $# -gt 0 ] && _sub "$depth" "$*" "eval"; return 0 ;;
    sh|bash|zsh|dash|ksh|mksh|yash|fish)
      local want=0 stdin=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -o|+o|-O|+O) shift 2 || set --; continue ;;
          -) stdin=1; shift; continue ;;
          --*) shift; continue ;;
          -*|+*) [[ $1 == *c* ]] && want=1; [[ $1 == *s* ]] && stdin=1; shift; continue ;;
        esac
        break
      done
      if [ "$want" -eq 1 ]; then [ $# -gt 0 ] && _sub "$depth" "$1" "$base -c"; return 0; fi
      [ $# -eq 0 ] && stdin=1
      [ "$stdin" -eq 1 ] && STDIN_SH="$STDIN_SH$CUR_PID "
      return 0 ;;

    # ---- RULE 4: the whole environment
    env)
      local cleared=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -u|-C|-P|--unset|--chdir) shift 2 || set -- ;;
          -S|--split-string) _sub "$depth" "${2:-}" "env -S"; [ -n "$R" ] && return 0; shift 2 || set -- ;;
          --split-string=*) _sub "$depth" "${1#*=}" "env -S"; [ -n "$R" ] && return 0; shift ;;
          -i|--ignore-environment|-) cleared=1; shift ;;
          -*) shift ;;
          *) if [[ $1 =~ $RE_ASSIGN ]]; then shift; else break; fi ;;
        esac
      done
      if [ $# -gt 0 ]; then _argv "$depth" "$@"; return 0; fi   # env sets, then runs a command
      [ "$cleared" -eq 1 ] || _dump "env with no command"
      return 0 ;;
    set)
      [ $# -eq 0 ] && _dump "set with no arguments"
      return 0 ;;
    export|declare|typeset|readonly)
      opts=""; names=0
      for w in "$@"; do case "$w" in -*|+*) opts="$opts${w#[-+]}" ;; *) names=1 ;; esac; done
      if [ "$names" -eq 0 ]; then
        case "$opts" in *[fF]*) return 0 ;; esac        # functions, not variables
        _dump "$base${opts:+ -$opts} with no names"; return 0
      fi
      case "$opts" in
        *m*) _dump "$base -m (a pattern listing)"; return 0 ;;
        *p*) for w in "$@"; do
               case "$w" in -*|+*) continue ;; esac
               if [[ ${w%%=*} =~ $RE_SECRET_NAME ]]; then
                 R="RULE 5: $base -p ${w%%=*} prints the value of a credential variable. SAFE: [ -n \"\${${w%%=*}-}\" ] && echo \"SET len=\${#${w%%=*}}\""; return 0
               fi
             done ;;
      esac
      return 0 ;;

    # ---- RULE 5: one named variable
    printenv)
      names=0
      for w in "$@"; do
        case "$w" in -*) continue ;; esac
        names=1
        if [[ $w =~ $RE_SECRET_NAME ]]; then
          R="RULE 5: printenv $w prints the value of a credential variable. SAFE: [ -n \"\${$w-}\" ] && echo \"$w: SET len=\${#$w}\" || echo \"$w: unset\""; return 0
        fi
        case "$w" in *'$'*) R="RULE 5: printenv of a name held in a variable (${w}) cannot be judged here. SAFE: name the variable literally, or print its length: \${#NAME}"; return 0 ;; esac
      done
      [ "$names" -eq 0 ] && _dump "printenv with no name"
      return 0 ;;

    # ---- RULE 6: the gh CLI's own token (also "$(whence -p gh)" auth ...)
    gh|'$(...)')
      [ "${1:-}" = auth ] || return 0
      case "${2:-}" in
        token)  R="RULE 6: gh auth token prints a GitHub token. SAFE: pass one without printing it, GH_TOKEN=\"\$(github-agent-token token)\" <cmd>; to check one exists, github-agent-token token | cut -c1-4" ;;
        status) R="RULE 6: gh auth status prints part of the token (23 characters of a PAT, OPERATIONAL_RULES [H11]). SAFE: gh api user --jq .login names who answers; gh api -i user 2>&1 | grep -i '^x-oauth-scopes' shows the scopes; [ -n \"\${GH_TOKEN-}\" ] && echo \"SET len=\${#GH_TOKEN}\" shows whether one is set" ;;
      esac
      return 0 ;;

    # ---- RULE 7: the macOS keychain
    security)
      case "${1:-}" in
        find-generic-password|find-internet-password)
          for w in "$@"; do
            if [[ $w =~ ^-[A-Za-z]+$ ]] && [[ $w == *[gw]* ]]; then
              R="RULE 7: security $1 $w prints the keychain secret. SAFE: drop -w/-g to confirm the item exists (attributes only); let the tool that owns it read it (github-agent-token), or ask Gavin"; return 0
            fi
          done ;;
        dump-keychain)
          for w in "$@"; do [[ $w =~ ^-[A-Za-z]*d ]] && { R="RULE 7: security dump-keychain -d prints every secret in the keychain. SAFE: drop -d, or ask Gavin"; return 0; }; done ;;
      esac
      return 0 ;;

    # ---- RULE 8: git's credential store
    git)
      while [ $# -gt 0 ]; do
        case "$1" in -C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) shift 2 || set -- ;; -*) shift ;; *) break ;; esac
      done
      case "${1:-}" in
        credential) [ "${2:-}" = fill ] && R="RULE 8: git credential fill prints the password field. SAFE: git ls-remote origin HEAD >/dev/null && echo auth-ok proves auth without printing it" ;;
        credential-*) [ "${2:-}" = get ] && R="RULE 8: git $1 get prints the stored password. SAFE: git ls-remote origin HEAD >/dev/null && echo auth-ok" ;;
      esac
      return 0 ;;

    # ---- RULE 9: reading a secrets file (.env, private key, .netrc)
    cat|gcat|bat|batcat|head|ghead|tail|gtail|less|more|most|nl|tac|strings|xxd|od|hexdump|grep|egrep|fgrep|ggrep|rg|ag|awk|gawk|sed|gsed|sort|uniq|diff|column|jq|yq|base64|cut)
      if [ "$base" = cut ]; then
        joined=" $* "
        [[ $joined =~ [[:space:]]-d[[:space:]]?=[[:space:]] ]] && [[ $joined =~ [[:space:]]-f[[:space:]]?1[[:space:]] ]] && return 0
      fi
      for w in "$@"; do
        if _secret_file "$w"; then
          R="RULE 9: $base reads $w, a file that holds secrets. SAFE: cut -d= -f1 $w (names only), or [ -s $w ] && echo present"; return 0
        fi
      done
      return 0 ;;

    # ---- RULE 10: other processes' environments, and secret managers
    ps)
      first=1
      for w in "$@"; do
        if { [[ $w =~ ^-[A-Za-z]+$ ]] && [[ $w == *E* ]]; } || { [ "$first" -eq 1 ] && [[ $w =~ ^[A-Za-z]+$ ]] && [[ $w == *[eE]* ]]; }; then
          R="RULE 10: ps $w shows each process's environment, tokens included. SAFE: ps -A -o pid,command (no E / BSD e)"; return 0
        fi
        first=0
      done
      return 0 ;;
    infisical)
      [ "${1:-}" = export ] && R="RULE 10: infisical export prints every secret in the environment. SAFE: infisical run -- <cmd> passes them without printing"
      return 0 ;;

    # ---- RULE 11: an interpreter dumping the whole environment
    uv)
      [ "${1:-}" = run ] || return 0
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          --with|--with-editable|--with-requirements|--python|-p|--project|--directory|--package|--extra|--group|--env-file|--index|--cache-dir|--config-file) shift 2 || set -- ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$depth" "$@"; return 0 ;;
    python|python[0-9]*|pypy|pypy[0-9]*|node|nodejs|deno|bun)
      [ "$base" = deno ] && [ "${1:-}" = eval ] && shift && set -- -e "$@"
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|-e|-p|--eval|--print)
            if [[ ${2:-} =~ $RE_ENVDUMP ]]; then
              R="RULE 11: $base $1 prints the whole environment (os.environ / process.env), tokens included. $SAFE_NAMES"
            fi
            return 0 ;;
        esac
        shift
      done
      return 0 ;;
  esac
  return 0
}

_advice='Print a FACT ABOUT the secret, never the secret:

    [ -n "${V-}" ] && echo "V: SET len=${#V}" || echo "V: unset"
    printf %s "$V" | shasum -a 256 | cut -c1-8     # a fingerprint you can compare
    env | cut -d= -f1 | grep -i token              # names only, no values

${V:-word} returns the VALUE when V is set -- it is an expansion, not a redaction.
Transcripts under ~/.claude/projects are append-only and gitignored, so git-leak-scan
cannot see them: a secret printed here is a secret with no way back.
Full rule: OPERATIONAL_RULES.md, "A shell probe written to CHECK whether a secret is set".'

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  fails=0
  _must() { # $1 = expect-hit(1)/expect-miss(0), $2 = label, $3 = command
    local got; got="$(_classify "$3")"
    local hit=0; [ -n "$got" ] && hit=1
    if [ "$hit" -eq "$1" ]; then printf 'ok    %s\n' "$2"
    else printf 'FAIL  %s  (expected hit=%s, got hit=%s)\n' "$2" "$1" "$hit"; fails=$((fails+1)); fi
  }
  echo "=== POSITIVE arms: these MUST be blocked ==="
  _must 1 'the real 2026-09-15 leak'      'echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"'
  _must 1 'the real 2026-06-20 leak'      'echo "shell sees it: ${GITHUB_PERSONAL_ACCESS_TOKEN:+SET}${GITHUB_PERSONAL_ACCESS_TOKEN:-unset}"'
  _must 1 'env dump, the other real leak' 'env | grep -i git'
  _must 1 'printenv dump'                 'printenv | grep -iE "token|pat"'
  _must 1 'bare echo of a secret'         'echo "$ANTHROPIC_API_KEY"'
  _must 1 'no-colon default form'         'echo "${NVD_API_KEY-none}"'
  echo "=== NEGATIVE arms: these MUST NOT be blocked ==="
  _must 0 'length only'                   'echo "GH_TOKEN len=${#GH_TOKEN}"'
  _must 0 'set-test only'                 'echo "GH_TOKEN: ${GH_TOKEN:+SET}"'
  _must 0 'the recommended safe form'     '[ -n "${GH_TOKEN-}" ] && echo "SET len=${#GH_TOKEN}" || echo unset'
  _must 0 'empty default, set -u guard'   'foo="${GH_TOKEN:-}"; [ -n "$foo" ] && echo yes'
  _must 0 'non-secret default'            'echo "${TMPDIR:-/tmp}/x"'
  _must 0 'env names only'                'env | cut -d= -f1 | grep -i token'
  _must 0 'secret passed, not printed'    'GH_TOKEN="$T" gh api user --jq .login'
  _must 0 'prose in a heredoc'            $'git commit -F - <<EOF\necho "${GH_TOKEN:-no}" is the bug\nEOF'

  # W-20260929-A34 (red team 2026-09-28, section 1 "Secrets", row H4). S-numbers are
  # that report's rows; E-numbers are edge cases from the worker brief.
  echo "=== the lexer, read from $LEXER_FROM ==="
  if [ -n "$LEXER" ]; then printf 'ok    %s\n' 'lexer block loaded'
  else printf 'FAIL  %s\n' 'lexer block NOT loaded: every arm below ran on the crude fallback'; fails=$((fails+1)); fi
  echo "=== POSITIVE arms, H4: printers that name no \${...} at all ==="
  _must 1 'S07 printenv a credential'      'printenv GH_TOKEN'
  _must 1 'S05 bare env'                   'env'
  _must 1 'S06 bare printenv'              'printenv'
  _must 1 'S09 set | grep'                 'set | grep TOKEN'
  _must 1 'S16 gh auth token'              'gh auth token'
  _must 1 'S17 gh auth status'             'gh auth status'
  _must 1 'S15 security -w'                'security find-generic-password -s infisical-gap-cc-high-value-shared -w'
  _must 1 'S12 cat ~/.claude/.env'         'cat ~/.claude/.env'
  _must 1 'S20 git credential fill'        "printf 'protocol=https\\nhost=github.com\\n' | git credential fill"
  _must 1 'S24 bash -c single-quoted'      "bash -c 'echo \$GH_TOKEN'"
  _must 1 'S10 export -p | grep'           'export -p | grep KEY'
  _must 1 'S11 typeset -p a credential'    'typeset -p GITHUB_TOKEN'
  _must 1 'S13 cat the PAI .env'           'cat ~/.config/PAI/.env'
  _must 1 'S21 python print(os.environ)'   'uv run python -c "import os; print(os.environ)"'
  _must 1 'S22 node process.env'           'node -e "console.log(process.env)"'
  _must 1 'S26 declare -x'                 'declare -x'
  _must 1 'S27 ps with environments'       'ps eww -A'
  _must 1 'S28 cat a private key'          'cat ~/.ssh/id_ed25519'
  _must 1 'S29 infisical export'           'infisical export --env prod'
  _must 1 'E02 env | grep, as before'      'env | grep TOKEN'
  _must 1 'E08 security -g'                'security find-generic-password -s some-item -g'
  _must 1 'E10 cat .env.local'             'cat .env.local'
  _must 1 'E13 bare git credential fill'   'git credential fill'
  _must 1 'E15 bash -c double-quoted'      'bash -c "echo \$GH_TOKEN"'
  _must 1 'E16 sh -c printenv'             "sh -c 'printenv GH_TOKEN'"
  _must 1 'E17 zsh -c gh auth token'       "zsh -c 'gh auth token'"
  _must 1 'E18 eval single-quoted'         "eval 'echo \$GH_TOKEN'"
  _must 1 'E19 eval double-quoted'         'eval "printenv GITHUB_TOKEN"'
  _must 1 'E20 gh auth status -t'          'gh auth status --show-token'
  _must 1 'E21 gh by path, auth status'    '"$(whence -p gh)" auth status'
  _must 1 'E22 heredoc fed to bash'        $'bash <<\'EOF\'\nprintenv GH_TOKEN\nEOF'
  _must 1 'E23 echo piped to sh'           "echo 'gh auth token' | sh"
  _must 1 'E24 sudo printenv'              'sudo printenv GH_TOKEN'
  _must 1 'E25 env -u with no command'     'env -u GH_TOKEN'
  _must 1 'E32 length then the value'      'echo "${#GH_TOKEN} $GH_TOKEN"'
  _must 1 'E46 grep a .env'                'grep KEY .env'
  _must 1 'E48 git -C x credential fill'   'git -C /tmp credential fill'
  _must 1 'E52 token captured then echoed' 'X="$(gh auth token)"; echo "$X"'
  _must 1 'E55 zsh print'                  'print -r -- $GH_TOKEN'
  _must 1 'E57 security -gs bundled'       'security find-internet-password -gs github.com'
  _must 1 'E59 printenv of a $variable'    'printenv "$name"'
  _must 1 'E60 xargs printenv'             'echo GH_TOKEN | xargs printenv'
  echo "=== NEGATIVE arms, H4: the safe forms and look-alikes ==="
  _must 0 'S35 env names only'             'env | cut -d= -f1'
  _must 0 'S31 length only, bare'          'echo ${#GH_TOKEN}'
  _must 0 'S41 token passed via $(...)'    'GH_TOKEN="$(github-agent-token token)" gh api user --jq .login'
  _must 0 'S42 token prefix only'          'github-agent-token token | cut -c1-4'
  _must 0 'E03 env sets and runs'          'env FOO=1 somecmd --flag'
  _must 0 'E04 env -u then a command'      'env -u GH_TOKEN -u GITHUB_TOKEN gh api user'
  _must 0 'E05 printenv HOME'              'printenv HOME'
  _must 0 'E06 printenv PATH'              'printenv PATH'
  _must 0 'E07 security without -w/-g'     'security find-generic-password -s some-item'
  _must 0 'E12 cat .env.example'           'cat .env.example'
  _must 0 'E14 git credential-cache exit'  'git credential-cache exit'
  _must 0 'E26 set -euo pipefail'          'set -euo pipefail'
  _must 0 'E27 export an assignment'       'export FOO=bar'
  _must 0 'E31 declare -p HOME'            'declare -p HOME'
  _must 0 'E33 echo $PATH (PAT inside)'    'echo "$PATH"'
  _must 0 'E34 the advised fingerprint'    'printf %s "$GH_TOKEN" | shasum -a 256 | cut -c1-8'
  _must 0 'E37 os.environ.get'             "uv run python3 -c \"import os; print(os.environ.get('HOME'))\""
  _must 0 'E38 the words in a message'     'git commit -m "block printenv GH_TOKEN and gh auth token"'
  _must 0 'E39 the words in a pattern'     "rg -n 'printenv|gh auth token' docs/"
  _must 0 'E41 ps -ef (macOS -e is -A)'    'ps -ef'
  _must 0 'E44 cat a public key'           'cat ~/.ssh/id_ed25519.pub'
  _must 0 'E45 .env names only'            'cut -d= -f1 ~/.claude/.env'
  _must 0 'E47 credential helper erase'    'git credential-osxkeychain erase'
  _must 0 'E51 gh by path, App token'      'GH_TOKEN="$(github-agent-token token)" "$(whence -p gh)" api /installation/repositories'
  _must 0 'E53 env -i ... sh -c lookup'    "env -i PATH=\"\$PATH\" sh -c 'command -v gh'"
  _must 0 'E54 the words in a heredoc'     $'git commit -F - <<\'EOF\'\nprintenv GH_TOKEN is now blocked\nEOF'
  _must 0 'E56 security, other flags'      'security find-generic-password -s x -a me -l label'
  _must 0 'E58 printenv names only'        'printenv | cut -d= -f1'
  _must 0 'E61 typeset -f functions'       'typeset -f'
  _must 0 'E62 gh auth, other verb'        'gh auth switch'
  _must 0 'E63 env | cut -d "=" -f 1'      'env | cut -d "=" -f 1'

  # The arms above test _classify in THIS file. These run the whole hook, payload
  # on stdin, so SECRET_PROBE_UNDER_TEST=<path> runs them on another copy.
  echo "=== HOOK arms: the payload read, or not (D-20260925-A03) ==="
  _hook="${SECRET_PROBE_UNDER_TEST:-$0}"
  echo "hook under test: $_hook"
  _pl() { jq -nc --arg c "$1" '{session_id:"selftest", transcript_path:"/dev/null", cwd:"/tmp",
    permission_mode:"default", hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:$c, description:"selftest arm", timeout:120000}, tool_use_id:"toolu_selftest"}'; }
  _mv() { printf '%s' "$1" | jq -c '.tool_input.cmd = .tool_input.command | del(.tool_input.command)'; }
  # A PATH with every tool in /bin and /usr/bin EXCEPT jq (macOS ships /usr/bin/jq).
  _nojq="$(mktemp -d "${TMPDIR:-/tmp}/secret-probe-nojq.XXXXXX")"
  for f in /bin/* /usr/bin/*; do
    case "${f##*/}" in jq) continue ;; esac
    [ -e "$_nojq/${f##*/}" ] || ln -s "$f" "$_nojq/${f##*/}"
  done
  _hk() { # $1 blocked|unreadable|shout|quiet, $2 label, $3 raw payload, [$4 nojq]
    local out rc got ok=0 path="$PATH"
    if [ "${4:-}" = nojq ]; then
      if PATH="$_nojq" command -v jq >/dev/null 2>&1 || ! PATH="$_nojq" command -v grep >/dev/null 2>&1; then
        printf 'FAIL  %s  (the no-jq PATH is not one: invalid trial)\n' "$2"; fails=$((fails+1)); return
      fi
      path="$_nojq"
    fi
    out="$(printf '%s' "$3" | PATH="$path" "$_hook" 2>/dev/null)"; rc=$?
    got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason) \(.additionalContext)"' 2>/dev/null || true)"
    case "$1" in
      blocked)    [[ $got == "deny 🔴 BLOCKED"* ]] && ok=1 ;;
      unreadable) [[ $got == "deny enforce-secret-probe: cannot read the tool payload"* ]] && ok=1 ;;
      shout)      [[ $got == "null null 🔴 THE SECRET-PROBE GUARD IS BROKEN"* ]] && ok=1 ;;
      halfbroken) [[ $got == "null null 🔴 THE SECRET-PROBE GUARD IS HALF BROKEN"* ]] && ok=1 ;;
      unreadable_lexer) [[ $got == "deny 🔴 BLOCKED"*"the shell lexer could not be used"* ]] && ok=1 ;;
      quiet)      [ -z "$out" ] && ok=1 ;;
    esac
    [ "$rc" -eq 0 ] || ok=0
    if [ "$ok" -eq 1 ]; then printf 'ok    %s\n' "$2"
    else printf 'FAIL  %s  (expected %s, rc=%s, got: %s)\n' "$2" "$1" "$rc" "$(printf '%s' "${got:-$out}" | head -c 200)"; fails=$((fails+1)); fi
  }
  W_T='echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"'
  W_O='ls -la'
  _hk blocked    'control: valid payload, the real leak is blocked as before'   "$(_pl "$W_T")"
  _hk quiet      'control: valid payload, harmless, no output as before'        "$(_pl "$W_O")"
  p="$(_pl "$W_T")"; _hk unreadable 'truncated JSON, with the trigger'           "${p%??????????}"
  p="$(_pl "$W_O")"; _hk quiet      'truncated JSON, without the trigger'        "${p%??????????}"
  _hk unreadable 'command under another key, with the trigger'                  "$(_mv "$(_pl "$W_T")")"
  _hk quiet      'command under another key, without the trigger'               "$(_mv "$(_pl "$W_O")")"
  _hk unreadable 'PATH without jq, with the trigger'                            "$(_pl "$W_T")" nojq
  _hk shout      'PATH without jq, without the trigger: the jq warning as before' "$(_pl "$W_O")" nojq
  _hk unreadable 'PATH without jq, an env dump'                                 "$(_pl 'env | grep -i git')" nojq
  _hk unreadable 'PATH without jq, ${#V} too: it cannot be told apart unread'   "$(_pl 'echo "len=${#GH_TOKEN}"')" nojq
  p="$(_pl $'cd /tmp\necho "$ANTHROPIC_API_KEY"')"
  _hk unreadable 'truncated, the variable after an escaped newline'             "${p%??????????}"
  _hk quiet      'a real, EMPTY command stays quiet, trigger in the description' \
    "$(_pl '' | jq -c '.tool_input.description = "echo $GH_TOKEN"')"
  _hk blocked    'H4 through the hook: printenv a credential'                   "$(_pl 'printenv GH_TOKEN')"
  _hk blocked    'H4 through the hook: bash -c body'                            "$(_pl "bash -c 'echo \$GH_TOKEN'")"
  _hk quiet      'H4 through the hook: a safe form stays quiet'                 "$(_pl 'env | cut -d= -f1')"
  # The lexer missing: the crude match denies by name, a harmless command SHOUTS.
  _lk() { SECRET_PROBE_LEXER_FROM=/nonexistent/enforce-no-permanent-delete.sh _hk "$@"; }
  _lk unreadable_lexer 'lexer missing: printenv a credential still denied'      "$(_pl 'printenv GH_TOKEN')"
  _lk halfbroken 'lexer missing: harmless command, the shout'                   "$(_pl "$W_O")"
  _lk blocked    'lexer missing: the ${V:-x} rule is untouched'                 "$(_pl "$W_T")"
  echo
  [ "$fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; } || { echo "$fails ARM(S) FAILED"; exit 1; }
fi

# ---------------------------------------------------------------- hook body
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# The payload cannot be read. $1 = why. When the RAW text mentions a trigger,
# DENY by name, built without jq; otherwise return and go on as before. The
# common JSON escapes are undone first (\n \r \t to a space, \" to "). Matched
# with [[ =~ ]], not a pipe into grep -q: under pipefail an early grep exit can
# turn a hit into a miss. The matched text is never printed.
_unreadable() {
  local raw
  raw="$(printf '%s' "$payload" | sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')"
  [[ $raw =~ $RAW_TRIGGER ]] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-secret-probe: cannot read the tool payload (%s); denying because it mentions a credential-named variable or an env dump. Install jq (brew install jq) or check the payload shape, then run enforce-secret-probe.sh --selftest."}}\n' "$1"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  _unreadable "jq is not on PATH"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE SECRET-PROBE GUARD IS BROKEN: jq is not on PATH, so this hook cannot read the tool payload. It has been SILENT for every command until now, and silence here is not a clean bill of health. Install jq (brew install jq). Until then, check by hand that nothing prints a credential value."
  exit 0
fi

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"; rc=$?
if [ -z "$cmd" ]; then
  if [ "$rc" -ne 0 ]; then
    _unreadable "jq could not parse it, rc=$rc"
  elif ! printf '%s' "$payload" | jq -e '.tool_input | has("command")' >/dev/null 2>&1; then
    _unreadable "it has no tool_input.command"
  fi
  exit 0   # a real, empty command: nothing to check, as before
fi

reason="$(_classify "$cmd")"
if [ -z "$reason" ]; then
  # Nothing matched, but the lexer rules never ran: say so, like a missing jq.
  [ -n "$LEXER" ] || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE SECRET-PROBE GUARD IS HALF BROKEN: its shell lexer could not be read from $LEXER_FROM, so printenv, env, gh auth, security -w, credential fill, .env reads and sh -c bodies are checked only by a crude text match. Restow the hooks (both files sit side by side in ~/.claude/hooks), then run enforce-secret-probe.sh --selftest."
  exit 0
fi

jq -n --arg r "$reason" --arg a "$_advice" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: ("🔴 BLOCKED -- this command would print a credential into the transcript.\n\n" + $r + "\n\n" + $a)}}'
exit 0
