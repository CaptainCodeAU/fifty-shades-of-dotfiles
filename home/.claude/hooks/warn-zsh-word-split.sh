#!/bin/bash
# Warn when a Bash-tool command uses an unquoted `$var` as if the shell would split it.
# Runs on PreToolUse for Bash. Sibling of enforce-census.sh: it never blocks, never edits
# the command, and always exits 0. #1110 (engage), Gavin's pick 2026-10-07.
#
# WHY IT EXISTS -- measured, not felt
#   The Bash tool runs zsh. In zsh an unquoted parameter expansion (`$c`, `${c}`) is ONE
#   word, whatever it holds; bash would split it on spaces. A prompt rule said so until
#   3 Oct, when it was dropped. On 7 Oct it bit twice in one probe:
#
#     for c in "agent list" "pane split" ...; do out=$(herdr $c --help 2>&1); ...
#
#   herdr got "agent list" as ONE argument and printed its top-level help every time, so
#   six different commands gave one checksum, and "--help no longer separates real from
#   invented subcommands" was committed as a finding (dotfiles c466be5). `${=c}` gave six
#   different answers (09d4e57). A note did not fire; this does.
#
#   Measured in the Bash tool on 2026-10-07 (zsh 5.9, SH_WORD_SPLIT off), each with its fix
#   as the control in the same command:
#     v="a b"; for x in $v           -> [a b]        for x in ${=v}   -> [a] [b]
#     v="a b"; printf '[%s]\n' $v    -> [a b]        ${(s: :)v}       -> [a] [b]
#     w=$(echo "p q"); printf .. $w  -> [p q]        printf .. $(echo "p q") -> [p] [q]
#     u=`echo "r s"`;  printf .. $u  -> [r s]        arr=(a b); $arr  -> [a] [b]
#     c="agent list";  printf .. $c  -> [agent list] ${=c}            -> [agent] [list]
#   So an unquoted $(cmd) used DIRECTLY does split in zsh, and stays quiet here.
#
# WHAT WARNS (only the shapes that go wrong, so ordinary "$f" use stays quiet)
#   a. `for x in $var` -- an unquoted parameter in a for-loop list. Not `${=var}`, not
#      `$@`/`$*`, not a subscript (`${arr[@]}`, `$arr[1]`), not any `${(flags)var}`, not a
#      variable this command made an array or set to text with no spaces, and not one of
#      zsh's own arrays ($path, $fpath, $argv, ...).
#   b. A variable set IN THIS COMMAND to text with whitespace (`v="a b"`, `v='a b'`,
#      `v=a\ b`), to command output (`v=$(cmd)`, `` v=`cmd` ``), or as the loop variable
#      of a `for` over quoted text with spaces (the 09d4e57 shape), then used unquoted as
#      a word of a command, including inside `$( )`, backticks and array literals.
#   Quiet: `"$var"`, `${=var}`, `$=var`, flags, arrays, `$(cmd)` itself, and any expansion
#   inside single quotes, a heredoc body, a comment, `[[ ]]`, `(( ))`, a `case` subject or
#   pattern, an assignment's value, a redirect target, or an `eval`'s arguments (eval
#   re-parses, so it splits). A variable set outside the command is unknown: shape a
#   still warns for it, shape b does not.
#
#   The words are read by a small lexer (awk, below), not a regex over the text, because
#   the same `$c` is harmless inside "..." and the bug inside `$( )` inside "...".
#
#   HOW OFTEN IT SPEAKS, measured 2026-10-07 by replaying 1,996 Bash commands from 60
#   recent transcripts: 35 warnings. Real catches among them, besides the incident:
#   `G="git -C <path>"; $G status`, `for a in "link --global" ...; pnpm $a`, and
#   `n=$(... | tr '\n' ' '); for l in $n`. Most of the rest are "set from command output"
#   on values that are one token anyway (mktemp paths, pane ids, short hashes). Warning on
#   `v=$(cmd)` only inside a for list would leave 7 warnings and every real catch; the
#   brief asked for both, so both are here, and the narrowing is a decision for #1110.
#   Selftest: ~/.claude/tools/warn-zsh-word-split-selftest (--mutants proves it can fail).
#
# 🔴 WHY IT SHOUTS INSTEAD OF GOING QUIET
#   Same rule as enforce-census.sh: a missing instrument must never look like a clean bill.
#   jq or awk missing, or a payload it cannot read that mentions a `$` expansion, says so.
#   An empty payload is not a command, and stays quiet like the sibling.
#
# The message never says the tool skips .zshrc: that half of the old rule was measured
# false (engage MAP.md C5). The splitting half is the one that bit.

set -uo pipefail

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

_shout() { # $1 reason (no double quotes, no backslashes)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE ZSH WORD-SPLIT WARNING IS BROKEN: $1. This command ran WITHOUT the check. In zsh an unquoted \$var is ONE word even when it holds spaces, so if the command relies on one splitting, use \${=var} (spaces), \${(f)var} (lines) or an array. The hook needs fixing; until then its silence is not a clean bill of health."
  exit 0
}

# jq is how the command is read; awk is how it is lexed. Either missing is a shout, not an
# exit 0, and the jq one is built by hand because building it needs jq.
command -v jq >/dev/null 2>&1 || _shout "jq is not on PATH, so it cannot read the tool payload"
command -v awk >/dev/null 2>&1 || _shout "awk is not on PATH, so it cannot read the command"

# A truncated payload, or one where a Claude Code update moved the command to another key,
# reads as an empty command. Shout when the raw text mentions a parameter expansion; stay
# quiet otherwise, or the shout becomes wallpaper.
_raw_dollar='\$[{A-Za-z_]'
if ! printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
  [[ "$payload" =~ $_raw_dollar ]] && _shout "the payload is not valid JSON"
  exit 0
fi
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
if [ -z "$cmd" ]; then
  [[ "$payload" =~ $_raw_dollar ]] && _shout "the payload has no tool_input.command"
  exit 0
fi
# Cheap exit: no `$` followed by a name, `{` or `=` means nothing here can be a variable.
case "$cmd" in *'$'[A-Za-z_{=~^]*) ;; *) exit 0 ;; esac

# THE LEXER. Reads the whole command, keeps a table of the variables it assigns, and prints
# one line per variable that warns: name TAB shape (for|arg) TAB kind (ws|cs|forws|unknown).
# \047 is a single quote. Written for POSIX awk (BSD awk on macOS, mawk, gawk).
_lex='
function isn1(c) { return c ~ /^[A-Za-z_]$/ }
function isnc(c) { return c ~ /^[A-Za-z0-9_]$/ }
function readname(p,   q) { q = p; while (q <= N && isnc(substr(S, q, 1))) q++; return q }
function warn(name, shape, kind) {
  if (name in WARNED) return
  WARNED[name] = 1; NW++; WN[NW] = name; WS[NW] = shape; WK[NW] = kind
}
function zarray(n) { return n ~ /^(path|fpath|cdpath|manpath|mailpath|module_path|psvar|argv|pipestatus|fignore|watch|historywords|dirstack|funcstack|reply|match|mbegin|mend|signals)$/ }
function checkarg(list,   n, i, a, t) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) {
    t = VT[a[i]]
    if (t == "ws" || t == "cs" || t == "forws") warn(a[i], "arg", t)
  }
}
function checkfor(list,   n, i, a, t) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) {
    if (zarray(a[i])) continue
    t = VT[a[i]]
    if (t == "arr" || t == "lit") continue
    warn(a[i], "for", (t == "" ? "unknown" : t))
  }
}
function inherit(list,   n, i, a, t) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) { t = VT[a[i]]; if (t == "ws" || t == "cs" || t == "forws") return t }
  return ""
}
# Skip a balanced "((...))" or "$((...))" starting at the first "(" at p. Returns the
# position after the last ")".
function skiparith(p,   d, c) {
  d = 0
  while (p <= N) {
    c = substr(S, p, 1)
    if (c == "(") d++
    else if (c == ")") { d--; if (d == 0) return p + 1 }
    p++
  }
  return p
}
# p is at "{" of "${". Returns position after the matching "}"; sets BR to the inside.
function brace(p,   d, c, q) {
  d = 0; q = p
  while (q <= N) {
    c = substr(S, q, 1)
    if (c == "\\") { q += 2; continue }
    if (c == "{") d++
    else if (c == "}") { d--; if (d == 0) { BR = substr(S, p + 1, q - p - 1); return q + 1 } }
    q++
  }
  BR = substr(S, p + 1); return q
}
# The variable a "${...}" body names, or "" when it is quiet: a split, a flag, a length, a
# set-test, a subscript or a special parameter.
function bracename(b,   c, n) {
  c = substr(b, 1, 1)
  if (c == "=" || c == "(" || c == "#" || c == "+" || c == "!") return ""
  while (c == "^" || c == "~") { b = substr(b, 2); c = substr(b, 1, 1) }
  if (!isn1(c)) return ""
  n = 1; while (n <= length(b) && isnc(substr(b, n, 1))) n++
  if (substr(b, n, 1) == "[") return ""
  return substr(b, 1, n - 1)
}
# Lex one dollar expansion at p (S[p] == "$") outside single quotes. Sets DN to the name it
# uses ("" when quiet) and DCS to 1 for a command substitution. Returns the next position.
function dollar(p,   c, q, n) {
  DN = ""; DCS = 0
  c = substr(S, p + 1, 1)
  if (c == "(") {
    if (substr(S, p + 2, 1) == "(") return skiparith(p + 1)
    q = scan(p + 2, ")"); DN = ""; DCS = 1; return q
  }
  if (c == "{") { q = brace(p + 1); DN = bracename(BR); return q }
  if (c == "=") { q = p + 2; if (isn1(substr(S, q, 1))) q = readname(q); return q }
  if (c == "^" || c == "~") { p++; c = substr(S, p + 1, 1) }
  if (isn1(c)) {
    q = readname(p + 1); n = substr(S, p + 1, q - p - 1)
    if (substr(S, q, 1) != "[") DN = n
    return q
  }
  if (c ~ /^[@*#?$!0-9-]$/) return p + 2
  return p + 1
}
function sqend(p, start,   q) {           # p at the opening quote; returns after the close
  q = p + 1
  while (q <= N && substr(S, q, 1) != "\047") q++
  if (substr(S, start, q - start) ~ /[ \t\n]/) LWS = 1
  return q + 1
}
# Read one word at p. Sets W (raw text), WU (names used unquoted), WQ (names used inside
# double quotes), WWS (quoted or escaped whitespace), WCS (command output in it), WASG
# (assigned name) and WARR (array assignment). Recursion into $( ) clobbers globals, so
# everything is built in locals and published at the end.
function word(p,   start, c, u, q, ws, cs, r, asg, arr, a2, d, lu, nm) {
  start = p; u = ""; q = ""; ws = 0; cs = 0; asg = ""; arr = 0
  while (p <= N) {
    c = substr(S, p, 1)
    if (c ~ /[ \t\n;&|<>)]/) break
    if (c == "(" ) {
      r = substr(S, start, p - start)
      if (r ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=$/) {        # arr=( ... ): an array literal
        arr = 1; p++
        while (p <= N) {
          c = substr(S, p, 1)
          if (c ~ /[ \t\n]/) { p++; continue }
          if (c == ")") { p++; break }
          p = word(p); checkarg(WU)
        }
        continue
      }
      if (p == start) break
      d = 0                                            # a glob qualifier: *(N) and kin
      while (p <= N) { c = substr(S, p, 1); if (c == "(") d++; else if (c == ")") { d--; if (d == 0) { p++; break } }; p++ }
      continue
    }
    if (c == "\\") { if (substr(S, p + 1, 1) ~ /[ \t]/) ws = 1; p += 2; continue }
    if (c == "\047") { LWS = 0; p = sqend(p, p + 1); if (LWS) ws = 1; continue }
    if (c == "$" && substr(S, p + 1, 1) == "\047") {
      p += 2; a2 = p
      while (p <= N && substr(S, p, 1) != "\047") { if (substr(S, p, 1) == "\\") p++; p++ }
      if (substr(S, a2, p - a2) ~ /[ \t\n]|\\[tn ]/) ws = 1
      p++; continue
    }
    if (c == "\"") {
      p++
      while (p <= N) {
        c = substr(S, p, 1)
        if (c == "\"") { p++; break }
        if (c == "\\") { p += 2; continue }
        if (c ~ /[ \t\n]/) ws = 1
        if (c == "$") { p = dollar(p); if (DCS) cs = 1; if (DN != "") q = q " " DN; continue }
        if (c == "`") { cs = 1; p = scan(p + 1, "`"); continue }
        p++
      }
      continue
    }
    if (c == "`") { if (BQ) break; cs = 1; p = scan(p + 1, "`"); continue }
    if (c == "$") { p = dollar(p); if (DCS) cs = 1; if (DN != "") u = u " " DN; continue }
    p++
  }
  r = substr(S, start, p - start)
  if (match(r, /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/)) {
    nm = substr(r, 1, RSTART + RLENGTH - 1); sub(/(\[[^]]*\])?\+?=$/, "", nm)
    asg = nm
    if (r ~ /^[A-Za-z_][A-Za-z0-9_]*\[/) arr = 1
  }
  W = r; WU = u; WQ = q; WWS = ws; WCS = cs; WASG = asg; WARR = arr
  return p
}
function assign(name, isarr,   t) {
  if (isarr) { VT[name] = "arr"; return }
  if (WCS) t = "cs"; else if (WWS) t = "ws"; else t = inherit(WU " " WQ)
  VT[name] = (t == "" ? "lit" : t)
}
function heredocs(p,   i, line, e, t) {   # p is just after a newline; skip pending bodies
  for (i = 1; i <= NH; i++) {
    while (p <= N) {
      e = index(substr(S, p), "\n"); line = (e ? substr(S, p, e - 1) : substr(S, p))
      p = (e ? p + e : N + 1)
      t = line; sub(/^[ \t]+/, "", t)
      if (t == HD[i]) break
    }
  }
  NH = 0
  return p
}
# Scan commands from p until the unmatched closer `cl` (")" or "`"), or the end of text.
function scan(p, cl,   c, c2, cmdst, mode, fv, fws, par, decl, darr, ev, quiet, incase, cpat, r) {
  cmdst = 1; mode = ""; par = 0; decl = 0; ev = 0; quiet = 0; incase = 0; cpat = 0
  if (cl == "`") BQ++
  while (p <= N) {
    c = substr(S, p, 1); c2 = substr(S, p, 2)
    if (cl == "`" && c == "`") { p++; break }
    if (mode == "dbrack" && c ~ /[&|()<>!]/) { p++; continue }
    if (c == "\n" || c == ";" || c == "&" || c == "|") {
      if (cpat && c == "|") { p++; continue }
      if (c == "\n") { p++; if (NH) p = heredocs(p) }
      else if (c == ";" && substr(S, p + 1, 1) ~ /[;&|]/) { p += 2; if (incase) cpat = 1 }
      else if (c2 == "&>") { p += 2; quiet = 1; continue }
      else if (c2 == "&&" || c2 == "||" || c2 == "&|" || c2 == "&!" || c2 == "|&") p += 2
      else p++
      if (mode == "dbrack") continue
      if (mode == "flist" && fws) VT[fv] = "forws"; else if (mode == "flist") VT[fv] = "lit"
      if (mode != "") mode = ""
      cmdst = 1; decl = 0; ev = 0; quiet = 0
      continue
    }
    if (c == " " || c == "\t") { p++; continue }
    if (c2 == "\\\n") { p += 2; continue }
    if (c == "#") { while (p <= N && substr(S, p, 1) != "\n") p++; continue }
    if (c == "<" || c == ">") {
      if (substr(S, p + 1, 1) == "(") { p = scan(p + 2, ")"); cmdst = 0; continue }
      if (substr(S, p, 3) == "<<<") { p += 3; quiet = 1; continue }
      if (c2 == "<<") {
        p += 2; if (substr(S, p, 1) == "-") p++
        while (substr(S, p, 1) ~ /[ \t]/) p++
        p = word(p); r = W; gsub(/["\047\\]/, "", r); NH++; HD[NH] = r
        continue
      }
      p++; while (substr(S, p, 1) ~ /[<>&|!]/) p++
      quiet = 1; continue
    }
    if (c == "(") {
      if (cmdst && substr(S, p + 1, 1) == "(") { p = skiparith(p); cmdst = 0; continue }
      if (mode == "fin") { mode = "flist"; fws = 0; p++; continue }   # zsh: for x (a b)
      if (cpat) { p++; continue }
      par++; cmdst = 1; p++; continue
    }
    if (c == ")") {
      p++
      if (mode == "flist") { VT[fv] = (fws ? "forws" : "lit"); mode = ""; continue }
      if (cpat) { cpat = 0; cmdst = 1; continue }
      if (par > 0) { par--; cmdst = 1; continue }
      if (cl == ")") break
      continue
    }
    p = word(p)
    if (W == "") { p++; continue }
    if (W ~ /^[A-Za-z_][A-Za-z0-9_.:-]*\(\)$/) { cmdst = 1; continue }   # f() { body }
    if (mode == "dbrack") { if (W == "]]") mode = ""; continue }
    if (quiet) { quiet = 0; continue }
    if (mode == "fvar") { fv = W; mode = "fin"; continue }
    if (mode == "fname") { mode = ""; continue }          # function f { body }
    if (mode == "fin") {
      if (W == "in") { mode = "flist"; fws = 0; continue }
      mode = ""; cmdst = 1
    }
    if (mode == "flist") {
      if (W == "do") { VT[fv] = (fws ? "forws" : "lit"); mode = ""; cmdst = 1; continue }
      if (WWS) fws = 1
      checkfor(WU); continue
    }
    if (mode == "csubj") { mode = "cin"; continue }
    if (mode == "cin") { mode = ""; if (W == "in") { incase++; cpat = 1 }; continue }
    if (cpat) { if (W == "esac") { incase--; cpat = 0 }; continue }
    if (cmdst) {
      if (WASG != "") { assign(WASG, WARR); continue }
      if (W == "for" || W == "select" || W == "foreach") { mode = "fvar"; cmdst = 0; continue }
      if (W == "case") { mode = "csubj"; cmdst = 0; continue }
      if (W == "[[") { mode = "dbrack"; cmdst = 0; continue }
      if (W == "esac") { if (incase) incase--; continue }
      if (W ~ /^(do|then|else|elif|if|while|until|time|!|\{|\}|done|fi|coproc|nocorrect|noglob|repeat)$/) continue
      if (W == "function") { mode = "fname"; continue }
      cmdst = 0
      if (W ~ /^(local|typeset|declare|export|readonly|integer|float)$/) { decl = 1; darr = 0; continue }
      if (W == "eval") { ev = 1; continue }
    }
    if (decl) {
      if (W ~ /^[-+]/) { if (W ~ /[aA]/) darr = 1; continue }
      if (WASG != "") { assign(WASG, WARR || darr); continue }
      if (darr && W ~ /^[A-Za-z_][A-Za-z0-9_]*$/) { VT[W] = "arr"; continue }
    }
    if (ev) continue
    checkarg(WU)
  }
  if (mode == "flist") VT[fv] = (fws ? "forws" : "lit")
  if (cl == "`") BQ--
  return p
}
{ S = (NR > 1 ? S "\n" : "") $0 }
END {
  N = length(S); NW = 0; NH = 0
  scan(1, "")
  for (i = 1; i <= NW; i++) printf "%s\t%s\t%s\n", WN[i], WS[i], WK[i]
}'

# LC_ALL=C: the syntax is all ASCII, and BSD awk in a UTF-8 locale dies on a multi-byte
# character ("towc: multibyte conversion failure", measured on a command holding a box-drawing
# dash). Byte-wise, such characters are just more word.
found="$(printf '%s\n' "$cmd" | LC_ALL=C awk "$_lex" 2>/dev/null)" || _shout "its awk lexer failed on this command"
[ -n "$found" ] || exit 0

# One short paragraph: each variable seen, what it was used as, and the fix.
whys=""; first=""
while IFS="$(printf '\t')" read -r v shape kind; do
  [ -n "$v" ] || continue
  case "$shape:$kind" in
    for:*)     why="\$$v is used unquoted as a for-loop list" ;;
    arg:ws)    why="\$$v is used unquoted and was set to text with spaces" ;;
    arg:cs)    why="\$$v is used unquoted and was set from command output" ;;
    arg:forws) why="\$$v is used unquoted and loops over quoted text with spaces" ;;
    *)         why="\$$v is used unquoted" ;;
  esac
  whys="${whys:+$whys; }$why"
  [ -n "$first" ] || first="$v"
done <<EOF
$found
EOF

msg="⚠️ zsh word-split: $whys. The Bash tool runs zsh, and zsh keeps an unquoted \$var as ONE word even when it holds spaces; bash would split it. If you meant separate words, write \${=$first} to split on spaces, \${(f)$first} to split on lines, or use an array. If one word is what you meant, quote it: \"\$$first\"."

jq -n --arg ctx "$msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}, suppressOutput: true}'
exit 0
