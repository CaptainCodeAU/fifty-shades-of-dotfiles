#!/bin/bash
# enforce-go-build-output.sh -- PreToolUse(Bash) guard: a `go build` or `go test -c` that
# would write its binary into the current folder is DENIED, in every session.
#
# WHY. 2026-09-29 22:35, engage-main ran `go build ./cmd/engage/` in the engage repo with no
# -o; Go wrote a 6.6 MB `engage` binary into the repo root, untracked. Gavin: "Make sure there
# are no such accidents like this again." Scope ruled in dotfiles-one's box: everywhere, any
# folder (D-20260929-A31; docs/CLAUDE_HOOKS.md "The Go build guard").
#
# WHAT GO WRITES (measured 2026-09-29, go1.27.1, a throwaway module; controls in the selftest):
#   writes a binary here   go build | go build . | go build ./cmd/app | go build main.go
#                          go test -c ./lib   (lib.test)
#   writes nothing         go build ./... | go build ./cmd/... (even when it matches ONE main
#                          package) | go build ./a ./b | go build ./lib (not main) | go test | go vet
# The hook cannot tell a main package from a library without reading the tree, so a single
# package with no -o is denied either way (false positives over misses). The fix is one flag.
#
# RULES
#   go build   DENY unless: -o/--o given (`-o X` or `-o=X`), or a package argument holds `...`,
#              or there are two or more package arguments. `.go` file arguments count as ONE
#              package (Go builds them as one), so `go build a.go b.go` is denied.
#   go test    DENY when -c/--c is given (or -c=true) with no -o.
#   Looked past, like the other guards here: VAR=x prefixes, env (and its options),
#   command, builtin, exec, nohup, time, nice, sudo, xargs; `sh/bash/zsh -c BODY` and
#   `eval ...` bodies are read as shell text (4 deep at most, then denied as unreadable).
#   $(...) bodies are separate commands to the lexer, so they are checked too.
#
# FAIL CLOSED, NOT OPEN (W-20260929-A186: a guard whose judge is broken must not allow by
# default). Two ways it can break, both measured by the selftest:
#   at run time (a missing helper, the lexer missing or failing): the judge returns non-zero,
#     and the command is DENIED when its raw text mentions a go build/test; every other
#     command still runs, so this kind of fault cannot lock a session out of Bash.
#   a syntax error anywhere in this file: bash exits 2 before judging anything, and Claude
#     Code treats a PreToolUse exit 2 as a block, so EVERY Bash call is refused (loudly, with
#     bash's error) until the file is fixed from Gavin's own terminal. Closed, never open.
#
# THE LEXER is read at run time from enforce-no-permanent-delete.sh beside this file, as
# enforce-secret-probe.sh does: one lexer on the machine.
#
#   enforce-go-build-output.sh --selftest    every arm, allowed and denied, plus controls
set -uo pipefail

case "$0" in */*) _here="${0%/*}" ;; *) _here=. ;; esac
LEXER_FROM="${GO_GUARD_LEXER_FROM:-$_here/enforce-no-permanent-delete.sh}"
US=$'\037'; RSC=$'\036'; OPM=$'\002'
MAX_DEPTH=4

# A raw mention of a go build/test, used for the prefilter and for failing closed.
RAW_GO='(^|[^A-Za-z0-9_.-])go[[:space:]]([^;&|]*[[:space:]])?(build|test)([^A-Za-z0-9_-]|$)'
RE_ASSIGN='^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?='

FIX='SAFE: add -o <path outside the repo> (e.g. -o "$TMPDIR/name"), build several packages or a pattern (./... writes nothing), or run go vet to only check.'

_load_lexer() {
  LEXER="$(sed -n "/^read -r -d '' LEXER <<'AWK'\$/,/^AWK\$/p" "$LEXER_FROM" 2>/dev/null | sed '1d;$d')"
  case "$LEXER" in *'function emitcmd('*'function lex('*) return 0 ;; *) LEXER=""; return 1 ;; esac
}

# _go <word>... : one `go` invocation's arguments (after `go`). Sets R on a deny.
_go() {
  local sub="" w seen_o="" seen_c="" pkgs=0 files=0 dots="" skip=""
  # go's own flags before the subcommand (go -C dir build ...)
  while [ $# -gt 0 ]; do
    case "$1" in
      -C|--C) shift 2 || set -- ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  sub="$1"; shift
  case "$sub" in
    build)
      while [ $# -gt 0 ]; do
        w="$1"; shift
        if [ -n "$skip" ]; then skip=""; continue; fi
        case "$w" in
          -o|--o) seen_o=1; skip=1 ;;
          -o=*|--o=*) seen_o=1 ;;
          -C|--C|-asmflags|--asmflags|-buildmode|--buildmode|-compiler|--compiler|-covermode|--covermode|\
          -coverpkg|--coverpkg|-gccgoflags|--gccgoflags|-gcflags|--gcflags|-installsuffix|--installsuffix|\
          -ldflags|--ldflags|-mod|--mod|-modfile|--modfile|-overlay|--overlay|-p|--p|-pgo|--pgo|\
          -pkgdir|--pkgdir|-tags|--tags|-toolexec|--toolexec) skip=1 ;;
          -*) ;;
          *.go) files=$((files + 1)) ;;
          *...*) dots=1; pkgs=$((pkgs + 1)) ;;
          *) pkgs=$((pkgs + 1)) ;;
        esac
      done
      [ -n "$seen_o" ] && return 0
      [ -n "$dots" ] && return 0
      [ "$files" -eq 0 ] && [ "$pkgs" -ge 2 ] && return 0
      R="go build of a single package (or of .go files) with no -o writes the binary into the current folder. $FIX"
      ;;
    test)
      for w in "$@"; do
        case "$w" in
          -o|--o|-o=*|--o=*) seen_o=1 ;;
          -c|--c|-c=true|--c=true) seen_c=1 ;;
          -args|--args) break ;;
        esac
      done
      if [ -n "$seen_c" ] && [ -z "$seen_o" ]; then
        R="go test -c with no -o writes <pkg>.test into the current folder. SAFE: add -o <path outside the repo>, or drop -c to just run the tests."
      fi
      ;;
  esac
  return 0
}

# _argv <depth> <word>... : one simple command. Sets R on a deny.
_argv() {
  local depth="$1"; shift
  while [ $# -gt 0 ] && [[ $1 =~ $RE_ASSIGN ]]; do shift; done
  [ $# -gt 0 ] || return 0
  local c="$1"; shift
  local base="${c##*/}"
  case "$base" in
    go) _go "$@" ;;
    '{'|'!'|if|then|else|elif|do|while|until|nohup|noglob|builtin|chronic|unbuffer)
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    command)
      while [ $# -gt 0 ]; do case "$1" in -*[vV]*) return 0 ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    exec)
      while [ $# -gt 0 ]; do case "$1" in -a) shift 2 || set -- ;; -*) shift ;; --) shift; break ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    time)
      while [ $# -gt 0 ]; do case "$1" in -o) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    nice)
      while [ $# -gt 0 ]; do case "$1" in -n) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    env)
      while [ $# -gt 0 ]; do
        case "$1" in
          -u|-C|-P|-S) shift 2 || set -- ;;
          -*) shift ;;
          *=*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    sudo|doas)
      while [ $# -gt 0 ]; do case "$1" in -u|-g|-h|-p|-C|-D|-r|-t|-T|-U) shift 2 || set -- ;; --) shift; break ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    xargs)
      while [ $# -gt 0 ]; do case "$1" in -I|-n|-P|-L|-s|-d|-E|-J|-R|-S) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$depth" "$@" ;;
    sh|bash|zsh|dash|ksh)
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|-*c|-c*) shift; [ $# -gt 0 ] && _lexed "$1" $((depth + 1)); return 0 ;;
          -*) shift ;;
          *) break ;;
        esac
      done ;;
    eval)
      [ $# -gt 0 ] && _lexed "$*" $((depth + 1)) ;;
  esac
  return 0
}

# _lexed <text> <depth> : every simple command in the text. Sets R on a deny; returns
# non-zero when the text could not be read (the caller fails closed on that).
_lexed() {
  local text="$1" depth="$2" recs line rest k i n
  if [ "$depth" -ge "$MAX_DEPTH" ]; then
    R="shell text nested $MAX_DEPTH deep is not read further, and it mentions go build/test. SAFE: run the go command directly."
    return 0
  fi
  recs="$(printf '%s' "$text" | LC_ALL=C awk -v base=0 -v snap= -v nofilter=1 "$LEXER" 2>/dev/null)" || return 1
  [[ $recs == *"E$US"* ]] || return 1
  local -a words=() a=() cmds=()
  while IFS= read -r line; do
    case "$line" in C"$US"*) rest="${line#?"$US"}"; cmds[${#cmds[@]}]="${rest#*"$US"}" ;; esac
  done <<< "$recs"
  n=${#cmds[@]}; i=0
  while [ "$i" -lt "$n" ]; do
    IFS="$US" read -r -a words <<< "${cmds[$i]}"
    a=(); k=0
    while [ "$k" -lt "${#words[@]}" ]; do
      if [[ ${words[$k]} == "$OPM"* ]]; then k=$((k + 2)); continue; fi
      a[${#a[@]}]="${words[$k]//$RSC/$'\n'}"; k=$((k + 1))
    done
    if [ "${#a[@]}" -gt 0 ]; then
      _argv "$depth" "${a[@]}"
      [ -n "$R" ] && return 0
    fi
    i=$((i + 1))
  done
  return 0
}

# _judge <text> : 0 = explicit allow (R empty); 0 with R set = deny; non-zero = could not judge.
_judge() {
  R=""
  [[ $1 =~ $RAW_GO ]] || return 0          # no go build/test anywhere: allow, fast
  _load_lexer || return 3
  _lexed "$1" 0 || return 4
  return 0
}

_deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED (go-build-output): " + $r + "\n\nWhy: on 2026-09-29 a go build with no -o wrote a 6.6 MB binary into the engage repo root.")}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED (go-build-output): %s"}}\n' \
      "$(printf '%s' "$reason" | sed 's/["\\]/ /g')"
  fi
}

_main() {
  local payload cmd rc
  payload="$(cat 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"; rc=$?
  else
    rc=9
  fi
  if [ "$rc" -ne 0 ]; then
    # payload unreadable: deny only a raw mention of a go build/test
    local raw; raw="$(printf '%s' "$payload" | sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')"
    [[ $raw =~ $RAW_GO ]] && _deny "the tool payload could not be read (jq rc=$rc), and it mentions go build/test. Install jq, then run enforce-go-build-output.sh --selftest."
    return 0
  fi
  [ -n "$cmd" ] || return 0
  if _judge "$cmd"; then
    [ -n "$R" ] && _deny "$R"
    return 0
  fi
  rc=$?
  [[ $cmd =~ $RAW_GO ]] && _deny "this guard could not judge the command (rc=$rc: the lexer in $LEXER_FROM is missing or failed), and it mentions go build/test, so it is denied rather than allowed. Restow the hooks, then run enforce-go-build-output.sh --selftest."
  return 0
}

# ------------------------------------------------------------------ selftest
_selftest() {
  local pass=0 fail=0 self="${BASH_SOURCE[0]}" out got want name cmd tmp
  _pl() { jq -nc --arg c "$1" '{session_id:"s",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
  _run() { _pl "$2" | env ${3:+GO_GUARD_LEXER_FROM="$3"} bash "$1" 2>/dev/null; }
  _arm() { # want(allow|deny) name cmd [script] [lexer-from]
    want="$1" name="$2" cmd="$3"
    out="$(_run "${4:-$self}" "$cmd" "${5:-}")"
    case "$out" in *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*) got=deny ;; *) got=allow ;; esac
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); printf '  ok   %-5s %s\n' "$want" "$name"
    else fail=$((fail + 1)); printf '  FAIL want %s got %s: %s\n       cmd: %s\n' "$want" "$got" "$name" "$cmd"; fi
  }
  command -v jq >/dev/null 2>&1 || { echo "selftest needs jq"; return 1; }
  echo "enforce-go-build-output selftest ($self)"
  echo "--- denied: a binary would land in the current folder"
  _arm deny "bare go build" 'go build'
  _arm deny "go build ." 'go build .'
  _arm deny "go build ./cmd/engage/ (the 2026-09-29 incident)" 'go build ./cmd/engage/'
  _arm deny "go build main.go" 'go build main.go'
  _arm deny "go build a.go b.go (one package from files)" 'go build a.go b.go'
  _arm deny "flags with values do not count as packages" 'go build -tags netgo -ldflags "-s -w" ./cmd/x'
  _arm deny "go -C dir build" 'go -C sub build ./cmd/x'
  _arm deny "absolute path to go" '/opt/homebrew/bin/go build ./cmd/x'
  _arm deny "GOFLAGS and env prefixes" 'GOFLAGS=-mod=mod CGO_ENABLED=0 go build ./cmd/x'
  _arm deny "env wrapper" 'env -u GOPATH CGO_ENABLED=0 go build ./cmd/x'
  _arm deny "command/nohup/time/nice wrappers" 'command nohup time nice -n 5 go build ./cmd/x'
  _arm deny "inside an && chain" 'cd /tmp && go vet ./... && go build ./cmd/x'
  _arm deny "inside a ; chain" 'echo hi; go build ./cmd/x'
  _arm deny "inside bash -c" "bash -c 'go build ./cmd/x'"
  _arm deny "inside eval" 'eval go build ./cmd/x'
  _arm deny "inside \$(...)" 'echo "$(go build ./cmd/x)"'
  _arm deny "go test -c" 'go test -c ./lib'
  _arm deny "go test -c=true" 'go test -c=true ./lib'
  _arm deny "go test -c through sudo" 'sudo -u me go test -c ./lib'
  echo "--- allowed: nothing is written here"
  _arm allow "go build -o path" 'go build -o "$TMPDIR/engage" ./cmd/engage'
  _arm allow "go build -o=path" 'go build -o=/tmp/x ./cmd/x'
  _arm allow "engage's own build line" 'CGO_ENABLED=0 go build -trimpath -o build/engage-go ./cmd/engage'
  _arm allow "go build ./..." 'go build ./...'
  _arm allow "go build ./cmd/... (a pattern writes nothing, measured)" 'go build ./cmd/...'
  _arm allow "two packages" 'go build ./cmd/a ./lib'
  _arm allow "go vet" 'go vet ./...'
  _arm allow "go test (no -c)" 'go test ./...'
  _arm allow "go test -c -o path" 'go test -c -o "$TMPDIR/lib.test" ./lib'
  _arm allow "go run" 'go run ./cmd/x'
  _arm allow "go install" 'go install ./cmd/x'
  _arm allow "the words as data (echo)" "echo 'use go build -o, never plain go build'"
  _arm allow "a heredoc mentioning go build" "$(printf 'cat <<EOF\ngo build ./cmd/x\nEOF')"
  _arm allow "CONTROL: an unrelated command" 'ls -la'
  _arm allow "CONTROL: an empty command" ''
  echo "--- fail closed when the lexer is missing (A186)"
  _arm deny "no lexer: go build is denied, not allowed" 'go build ./cmd/x' "$self" /nonexistent/lexer.sh
  _arm deny "no lexer: even go build -o is denied (cannot judge)" 'go build -o /tmp/x ./cmd/x' "$self" /nonexistent/lexer.sh
  _arm allow "no lexer: an unrelated command still runs" 'ls -la' "$self" /nonexistent/lexer.sh
  echo "--- fail closed when the judge breaks at run time (A186 shape)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/go-guard-mutant.XXXXXX")"
  cp "$self" "$tmp"
  sed -i '' 's/  _load_lexer || return 3/  _no_such_helper || return 3/' "$tmp" 2>/dev/null || sed -i 's/  _load_lexer || return 3/  _no_such_helper || return 3/' "$tmp"
  if cmp -s "$self" "$tmp"; then fail=$((fail + 1)); echo "  FAIL could not build the run-time-broken mutant"
  else
    _arm deny "MUTANT judge broken at run time: go build is denied" 'go build ./cmd/x' "$tmp" "$LEXER_FROM"
    _arm allow "MUTANT judge broken at run time: an unrelated command still runs" 'ls -la' "$tmp" "$LEXER_FROM"
  fi
  echo "--- a syntax error blocks everything (exit 2 is a block to Claude Code)"
  cp "$self" "$tmp"
  sed -i '' 's/^_judge() {$/_judge() { if then/' "$tmp" 2>/dev/null || sed -i 's/^_judge() {$/_judge() { if then/' "$tmp"
  local src
  for cmd in 'go build ./cmd/x' 'ls -la'; do
    _pl "$cmd" | GO_GUARD_LEXER_FROM="$LEXER_FROM" bash "$tmp" >/dev/null 2>&1; src=$?
    if [ "$src" -eq 2 ]; then pass=$((pass + 1)); printf '  ok   block MUTANT syntax error: exit 2 for %s\n' "$cmd"
    else fail=$((fail + 1)); printf '  FAIL MUTANT syntax error: exit %s (want 2) for %s\n' "$src" "$cmd"; fi
  done
  echo "--- one-fault mutants must be caught"
  local m mname mexpr mcmd
  local TAB=$'\t'
  for m in "o${TAB}s/-o|--o) seen_o=1; skip=1 ;;/-o|--o) skip=1 ;;/${TAB}go build -o /tmp/x ./cmd/x${TAB}allow" \
           "dots${TAB}s/\\[ -n \"\$dots\" \\] \\&\\& return 0/:/${TAB}go build ./...${TAB}allow" \
           "testc${TAB}s/seen_c=1 ;;/: ;;/${TAB}go test -c ./lib${TAB}deny" \
           "shc${TAB}s/_lexed \"\$1\" \$((depth + 1)); return 0 ;;/return 0 ;;/${TAB}bash -c 'go build ./cmd/x'${TAB}deny"; do
    IFS="$TAB" read -r mname mexpr mcmd want <<< "$m"
    cp "$self" "$tmp"; sed -i '' "$mexpr" "$tmp" 2>/dev/null || sed -i "$mexpr" "$tmp"
    if cmp -s "$self" "$tmp"; then fail=$((fail + 1)); echo "  FAIL mutant $mname: the edit changed nothing"; continue; fi
    out="$(_run "$tmp" "$mcmd" "$LEXER_FROM")"
    case "$out" in *'"permissionDecision"'*'"deny"'*) got=deny ;; *) got=allow ;; esac
    if [ "$got" != "$want" ]; then pass=$((pass + 1)); printf '  ok   mutant %-6s caught (%s now %s)\n' "$mname" "$mcmd" "$got"
    else fail=$((fail + 1)); printf '  FAIL mutant %s NOT caught\n' "$mname"; fi
  done
  rm -f "$tmp" 2>/dev/null
  echo "enforce-go-build-output selftest: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest) _selftest; exit $? ;;
esac
_main
exit 0
