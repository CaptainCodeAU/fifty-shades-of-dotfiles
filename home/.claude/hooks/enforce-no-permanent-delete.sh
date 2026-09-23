#!/bin/bash
# enforce-no-permanent-delete.sh -- DENY agent Bash commands that destroy data
# without going through the Trash, and name the safe route in the denial.
# PreToolUse on Bash. Registered for BOTH targets (user and project) in
# settings/claude/hooks.json, because the rule it enforces is machine-wide:
# OPERATIONAL_RULES.md "Deletion" and CLAUDE.md "Deletion safety".
#
# WHY IT EXISTS. Ruled by Gavin 2026-09-23 (option A). The trigger: an agent was
# one step from `git worktree remove`, which unlinks a whole tree outside the
# Trash, and no rm wrapper can see it because it never calls rm. The rm PATH
# shim covers `rm`; it cannot cover `git clean`, `find -delete`, `unlink`,
# `rsync --delete`, `> file`, an absolute `/bin/rm`, or `os.remove` inside a
# `python3 -c`. docs/DELETION_SAFETY.md lists those under "What the rm wrappers
# do NOT protect against"; this hook turns most of that list into a refusal.
#
# HOW IT READS A COMMAND. Not a regex over the text. A small shell lexer (awk,
# below) splits the command into SIMPLE COMMANDS the way zsh would: quotes are
# removed and their contents stay inside one word, heredoc bodies are set aside,
# comments are dropped, and every $(...), `...`, <(...), >(...) and =(...) body
# is emitted as a command of its own. The rules then look at argv[0] of each
# simple command, after seeing through prefixes (VAR=1, sudo, command, env,
# nohup, time, nice, timeout, xargs, noglob, nocorrect, builtin, exec, -,
# repeat N, uv run, git -C/-c/--git-dir, find -exec, fd -x). So a banned word
# inside a commit message, an echo, an rg pattern or a heredoc is DATA and is
# allowed, while the same word as a command is denied wherever it sits.
#
# THE BASH TOOL IS ZSH. The lexer covers zsh shapes too: &! and &| (disown),
# |&, =(...), glob qualifiers like *(.) (kept inside the word), ${(f)...},
# >! and >>! (clobber), precommands noglob / nocorrect / -, repeat N.
# Unquoted $var does not word-split in zsh, so `x="git clean -fd"; $x` runs a
# command literally named "git clean -fd" and fails: not a deletion, allowed.
#
# ALIASES. Agent shells source Claude Code's shell snapshot, which defines
# ~300 aliases that DO expand. A hook sees the text before expansion, so each
# command word is looked up in the newest snapshot's alias table and the
# expansion is classified too (recursively, as zsh does). Functions in the
# snapshot are NOT expanded: the rm() wrapper's body contains /bin/rm on its
# SAFE_RM_OFF branch, so expanding functions would deny every bare rm.
#
# WHAT STAYS INVISIBLE (docs/DELETION_SAFETY.md has the full table): a script
# or Makefile target that deletes internally, a compiled program, a command
# name held in a variable ($RM x, $=x), git aliases, ssh to another host,
# `mv`/`cp` over an existing file, and code piped in from a file.
#
# LOGS every denial to ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log,
# the same shape as validate-bash.sh / enforce-uv.sh. The logged command is
# capped at 400 chars and token-shaped strings and credential-named
# assignments are redacted first: a guard must not become the leak.
#
# FAILS OPEN on malformed JSON or an empty command (exit 0, no decision): a
# crash here would block every Bash call. jq missing, or the lexer failing,
# SHOUTS through additionalContext instead of going quiet.
#
# `--selftest` proves every arm, deny AND allow. `--mutants [text]` removes each
# `#M:` line (or only those whose tag holds text) in turn from a copy and shows
# the selftest catch it.

# No `set -u`: /bin/bash is 3.2 on macOS, where an EMPTY array expanded as
# "${a[@]}" is an unbound-variable error. Globbing is off for the whole run
# (words are split on US and must never glob); _snapshot_file turns it back on
# for its one glob.
set -f

HOOK_NAME="enforce-no-permanent-delete"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_FILE="${DEL_GUARD_LOG:-$STATE_DIR/hooks-security.log}"
SNAP_DIR="${DEL_GUARD_SNAPSHOT_DIR:-$HOME/.claude/shell-snapshots}"
MAX_DEPTH=4

US=$'\037'   # field separator in lexer records
RSC=$'\036'  # stands for a newline inside a word
OPM=$'\002'  # marks a redirection operator word

# ---------------------------------------------------------------- the lexer
# Input: the command on stdin. Output, one record per line, fields split by US:
#   C <pid> <word>...   a simple command; redirection ops are OPM-prefixed words
#                       followed by their target word
#   H <pid> <text>      stdin data for pipeline <pid>: a heredoc body or a
#                       here-string (<<<)
#   E <maxpid>          last line, always; its absence means the lexer failed
# <pid> numbers a pipeline: it changes at ; & && || newline, not at |.
read -r -d '' LEXER <<'AWK'
BEGIN { US = sprintf("%c", 31); RSC = sprintf("%c", 30); OPM = sprintf("%c", 2); Q = sprintf("%c", 39)
        HEX = "0123456789abcdef"; buf = ""; first = 1
        # Command names the bash rules act on. A simple command that contains none
        # of them, no alias, no SAFE_RM_OFF and no truncating redirection cannot be
        # denied, so it is not emitted: bash 3.2 costs ~0.15 ms per command it sees.
        # nofilter=1 emits everything; the selftest runs every arm both ways.
        nt = split("sudo doas env command exec time repeat nice timeout gtimeout caffeinate stdbuf gstdbuf watch xargs gxargs eval sh bash zsh dash ksh mksh yash fish rm grm unlink gunlink shred gshred srm wipe truncate gtruncate dd gdd cp gcp find gfind fd fdfind git rsync rimraf del-cli docker podman docker-compose brew pnpm bun bunx npx pnpx uv node nodejs deno perl ruby osascript diskutil wipefs tmutil trash-empty trash-rm export declare typeset local readonly grhh gwipe gpristine", TL, " ")
        for (k = 1; k <= nt; k++) TRIG[TL[k]] = 1
        hasal = 0
        if (snap != "") loadaliases() }
function loadaliases(   line, l, k, v) {
  while ((getline line < snap) > 0) {
    if (index(line, "alias ") != 1) continue
    l = line; sub(/^alias (-- )?/, "", l)
    k = index(l, "="); if (k < 2) continue
    v = substr(l, k + 1)
    if (length(v) >= 2 && substr(v, 1, 1) == Q && substr(v, length(v), 1) == Q) {
      v = substr(v, 2, length(v) - 2); gsub(Q "\\\\" Q Q, Q, v)
    }
    AV[substr(l, 1, k - 1)] = v; hasal = 1   #M: alias table loaded
  }
  close(snap)
}
function trig(w,   b) {
  if (index(w, "SAFE_RM_OFF") == 1) return 1
  b = w; sub(/^=/, "", b); sub(/.*\//, "", b)
  if (b in TRIG) return 1
  if (b ~ /^(python|pypy)[0-9.]*$/ || b ~ /^mkfs/ || b ~ /^newfs/) return 1
  return 0
}
{ if (first) { buf = $0; first = 0 } else buf = buf "\n" $0 }
END {
  s = buf; n = length(s); P = base + 0; maxp = P; hn = 0; hstart = 1; d = 0
  lex(1, "")
  print "E" US maxp
}
function newstate() {
  d++; nw[d] = 0; cur[d] = ""; inw[d] = 0; pd[d] = 0; hdp[d] = 0; hst[d] = 0; hsp[d] = 0
  P++; if (P > maxp) maxp = P; pid[d] = P
}
function newpipe() { P++; if (P > maxp) maxp = P; pid[d] = P }
function enc(x) { gsub(/\n/, RSC, x); return x }
function flushword() {
  if (inw[d]) {
    nw[d]++; W[d, nw[d]] = cur[d]
    if (hdp[d]) { hn++; HD[hn] = cur[d]; HT[hn] = hst[d]; HP[hn] = pid[d]; hdp[d] = 0 }
    else if (hsp[d]) { hsp[d] = 0; print "H" US pid[d] US enc(cur[d]) }
  }
  cur[d] = ""; inw[d] = 0
}
function emitcmd(   k, out, w, op, intr, nop, fw, data, al, safe) {
  flushword()
  if (nw[d] > 0) {
    intr = nofilter + 0; nop = 0; fw = ""; data = ""; al = 0; safe = 0
    for (k = 1; k <= nw[d]; k++) {
      w = W[d, k]
      if (substr(w, 1, 1) == OPM) {
        op = substr(w, 2); if (op == ">" || op == "&>" || op == ">&") intr = 1   #M: prefilter: truncating redirect
        k++; continue
      }
      nop++
      if (fw == "" && w !~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) fw = w
      else if (fw != "") data = (data == "") ? w : data " " w
      if (trig(w)) intr = 1   #M: prefilter: trigger words
      if (index(w, "SAFE_RM_OFF") == 1) safe = 1
      if (hasal && (w in AV)) { intr = 1; al = 1 }
    }
    if (nop == 0) intr = 1
    # echo/printf/print is DATA: emitted as stdin for its pipeline, which only
    # matters when an interpreter reads it (echo code | python3)
    if (!al && (fw == "echo" || fw == "printf" || fw == "print") && !(fw in AV)) {
      if (!safe) { print "H" US pid[d] US enc(data); nw[d] = 0; return }   #M: echo is data for its pipeline
    }
    if (intr) {
      if (al) for (k = 1; k <= nw[d]; k++) {
        w = W[d, k]
        if ((w in AV) && !(w in EA)) { EA[w] = 1; print "A" US w US enc(AV[w]) }   #M: alias records sent
      }
      out = "C" US pid[d]
      for (k = 1; k <= nw[d]; k++) out = out US enc(W[d, k])
      print out
    }
  }
  nw[d] = 0
}
function addop(op) { flushword(); nw[d]++; W[d, nw[d]] = OPM op }
function readheredocs(i,   k, j, line, t, body, rest) {
  for (k = hstart; k <= hn; k++) {
    body = ""
    while (i < n) {
      rest = substr(s, i + 1); j = index(rest, "\n")
      if (j == 0) { line = rest; i = n } else { line = substr(rest, 1, j - 1); i = i + j }
      t = line; if (HT[k]) sub(/^\t+/, "", t)   #M: lexer: <<- strips tabs
      if (t == HD[k]) break
      body = body line "\n"
    }
    print "H" US HP[k] US enc(body)
  }
  hstart = hn + 1
  return i
}
function matchparen(i,   depth, c) {
  depth = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "(") depth++
    else if (c == ")") { depth--; if (depth == 0) return i }
    i++
  }
  return n
}
function brace(i,   depth, c) {
  depth = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") { i = lex(i + 2, ")"); continue }   #M: lexer: $( ) inside ${ }
    if (c == "{") depth++
    else if (c == "}") { depth--; if (depth == 0) return i + 1 }
    i++
  }
  return n + 1
}
function hexval(h,   a, b) {
  a = index(HEX, tolower(substr(h, 1, 1))) - 1; b = index(HEX, tolower(substr(h, 2, 1))) - 1
  if (a < 0) return -1
  if (b < 0) return a
  return a * 16 + b
}
function ansic(i,   c, c2, v) {
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "'") return i + 1
    if (c == "\\") {
      c2 = substr(s, i + 1, 1)
      if (c2 == "n") cur[d] = cur[d] "\n"
      else if (c2 == "t") cur[d] = cur[d] "\t"
      else if (c2 == "x") {
        v = hexval(substr(s, i + 2, 2))
        if (v >= 0) { cur[d] = cur[d] sprintf("%c", v); i += (index(HEX, tolower(substr(s, i + 3, 1))) > 0) ? 4 : 3; continue }   #M: lexer: $'\\xHH'
        cur[d] = cur[d] c2
      }
      else cur[d] = cur[d] c2
      i += 2; continue
    }
    cur[d] = cur[d] c; i++
  }
  return i
}
function dq(i,   c, c2, j) {
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") return i + 1
    if (c == "\\") {
      c2 = substr(s, i + 1, 1)
      if (c2 == "\n") { i += 2; continue }
      if (c2 == "\"" || c2 == "\\" || c2 == "$" || c2 == "`") { cur[d] = cur[d] c2; i += 2; continue }
      cur[d] = cur[d] c; i++; continue
    }
    if (c == "$" && substr(s, i + 1, 1) == "(") { i = lex(i + 2, ")"); cur[d] = cur[d] "$(...)"; continue }   #M: lexer: $( ) inside double quotes
    if (c == "$" && substr(s, i + 1, 1) == "{") { j = brace(i + 2); cur[d] = cur[d] substr(s, i, j - i); i = j; continue }
    if (c == "`") { i = lex(i + 1, "`"); cur[d] = cur[d] "$(...)"; continue }   #M: lexer: backticks inside double quotes
    cur[d] = cur[d] c; i++
  }
  return i
}
function redirop(i,   t3, t2) {
  t3 = substr(s, i, 3); t2 = substr(s, i, 2)
  if (t3 == "<<<" || t3 == "<<-" || t3 == ">>!" || t3 == ">>|") return t3
  if (t2 == "<<" || t2 == "<>" || t2 == "<&" || t2 == ">>" || t2 == ">&" || t2 == ">|" || t2 == ">!") return t2
  return substr(s, i, 1)
}
function lex(i, term,   c, c2, j, op) {
  newstate()
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") {
      c2 = substr(s, i + 1, 1)
      if (c2 == "\n") { i += 2; continue }
      cur[d] = cur[d] c2; inw[d] = 1; i += 2; continue
    }
    if (c == "'") {
      j = index(substr(s, i + 1), "'")
      if (j == 0) { cur[d] = cur[d] substr(s, i + 1); inw[d] = 1; i = n + 1; continue }
      cur[d] = cur[d] substr(s, i + 1, j - 1); inw[d] = 1; i = i + j + 1; continue   #M: lexer: single quotes
    }
    if (c == "\"") { inw[d] = 1; i = dq(i + 1); continue }   #M: lexer: double quotes
    if (c == "$") {
      c2 = substr(s, i + 1, 1)
      if (c2 == "'") { inw[d] = 1; i = ansic(i + 2); continue }
      if (c2 == "(") { i = lex(i + 2, ")"); cur[d] = cur[d] "$(...)"; inw[d] = 1; continue }   #M: lexer: $( ) unquoted
      if (c2 == "{") { j = brace(i + 2); cur[d] = cur[d] substr(s, i, j - i); inw[d] = 1; i = j; continue }
      cur[d] = cur[d] c; inw[d] = 1; i++; continue
    }
    if (c == "`") {
      if (term == "`") { emitcmd(); d--; return i + 1 }
      i = lex(i + 1, "`"); cur[d] = cur[d] "$(...)"; inw[d] = 1; continue
    }
    if ((c == "<" || c == ">" || c == "=") && substr(s, i + 1, 1) == "(" && (c != "=" || !inw[d])) {
      if (c != "=") flushword()
      i = lex(i + 2, ")"); cur[d] = cur[d] "$(...)"; inw[d] = 1; continue   #M: lexer: <( ) >( ) =( )
    }
    if (c == " " || c == "\t") { flushword(); i++; continue }
    if (c == "\n") {
      emitcmd(); newpipe()   #M: lexer: newline separates
      if (hstart <= hn) i = readheredocs(i)   #M: lexer: heredoc bodies set aside
      i++; continue
    }
    if (c == "#" && !inw[d]) { j = index(substr(s, i), "\n"); i = (j == 0) ? n + 1 : i + j - 1; continue }   #M: lexer: comments
    if (c == ";") {
      emitcmd(); newpipe(); i++   #M: lexer: ; separates
      while (substr(s, i, 1) == ";" || substr(s, i, 1) == "&" || substr(s, i, 1) == "|") i++
      continue
    }
    if (c == "&") {
      c2 = substr(s, i + 1, 1)
      if (c2 == ">") {
        op = "&>"; i += 2
        if (substr(s, i, 1) == ">") { op = "&>>"; i++ }
        if (substr(s, i, 1) == "!" || substr(s, i, 1) == "|") i++
        addop(op); continue
      }
      emitcmd(); newpipe(); i++
      if (c2 == "&" || c2 == "!" || c2 == "|") i++
      continue
    }
    if (c == "|") {
      c2 = substr(s, i + 1, 1)
      emitcmd(); i++
      if (c2 == "|") { newpipe(); i++ } else if (c2 == "&") i++
      continue
    }
    if (c == "(") {
      if (inw[d]) { j = matchparen(i); cur[d] = cur[d] substr(s, i, j - i + 1); i = j + 1; continue }   #M: lexer: ( inside a word
      emitcmd(); pd[d]++; i++; continue
    }
    if (c == ")") {
      if (pd[d] > 0) { emitcmd(); pd[d]--; i++; continue }
      if (term == ")") { emitcmd(); d--; return i + 1 }
      emitcmd(); i++; continue
    }
    if (c == "<" || c == ">") {
      if (inw[d] && cur[d] ~ /^[0-9]+$/) { cur[d] = ""; inw[d] = 0 } else flushword()   #M: lexer: fd number before >
      op = redirop(i); i += length(op)
      gsub(/[!|]/, "", op)   #M: lexer: zsh >! and >|
      addop(op)
      if (op == "<<" || op == "<<-") { hdp[d] = 1; hst[d] = (op == "<<-") }   #M: lexer: heredoc start
      if (op == "<<<") hsp[d] = 1   #M: lexer: here-string
      continue
    }
    cur[d] = cur[d] c; inw[d] = 1; i++
  }
  emitcmd(); d--; return i
}
AWK

# ---------------------------------------------------------------- messages
FOOTER='A permanent delete is Gavin'"'"'s call: stop and ask. Rules: OPERATIONAL_RULES.md "Deletion", docs/DELETION_SAFETY.md.
If the banned words are DATA here (a message, a pattern, prose), put them inside quotes or a heredoc and they are not read as a command.'

_msg() { # $1 = rule id -> what it does, then the safe route
  case "$1" in
    rm-path)        echo "rm called by path runs the real deleter and skips the Trash. SAFE ROUTE: bare rm (it resolves to the Trash-routed wrapper)." ;;
    rm-P)           echo "rm -P overwrites the bytes before unlinking; nothing recovers it. SAFE ROUTE: bare rm without -P." ;;
    safe-rm-off)    echo "SAFE_RM_OFF is the human-only bypass of the Trash wrapper. SAFE ROUTE: bare rm, or ask Gavin." ;;
    grm)            echo "grm is GNU rm; it bypasses the Trash shim. SAFE ROUTE: bare rm." ;;
    unlink)         echo "unlink deletes outside the Trash. SAFE ROUTE: bare rm." ;;
    shred)          echo "shred/srm/wipe overwrite and delete; nothing recovers it. SAFE ROUTE: bare rm, or ask Gavin." ;;
    truncate)       echo "truncate empties a file in place; no Trash copy. SAFE ROUTE: move it aside first (command mv f f.bak) or ask Gavin." ;;
    dd-of)          echo "dd of= overwrites its target. SAFE ROUTE: write to a new file, or ask Gavin." ;;
    redir-trunc)    echo "a redirection with no command (> f, : > f, cat /dev/null > f) empties the file; no Trash copy. SAFE ROUTE: move it aside first, or ask Gavin." ;;
    find-delete)    echo "find -delete unlinks outside the Trash. SAFE ROUTE: find ... -print to list, then find ... -exec rm {} + (bare rm)." ;;
    git-worktree-remove) echo "git worktree remove unlinks the whole worktree outside the Trash. SAFE ROUTE: rm -r <dir> (Trash-routed), then git worktree prune." ;;
    git-clean)      echo "git clean deletes untracked files outside the Trash. SAFE ROUTE: git clean -n to list, then rm the files (bare rm)." ;;
    git-reset-hard) echo "git reset --hard discards uncommitted work. SAFE ROUTE: git stash push -u (recoverable), or ask Gavin." ;;
    git-checkout-discard) echo "git checkout on paths (-- <path>, ., or a file) or with -f discards uncommitted work. SAFE ROUTE: git stash push -u (recoverable), or ask Gavin; for a branch use git switch <branch>." ;;
    git-restore)    echo "git restore without --staged overwrites the working tree. SAFE ROUTE: git stash push -u (recoverable), or ask Gavin; git restore --staged <f> only unstages." ;;
    git-switch-discard) echo "git switch -f / --discard-changes throws away uncommitted work. SAFE ROUTE: git stash push -u first, or ask Gavin." ;;
    git-branch-force) echo "git branch -D / --delete --force / -M / -C deletes or overwrites a branch even when unmerged. SAFE ROUTE: git branch -d (refuses unmerged work)." ;;
    git-stash-drop) echo "git stash drop / clear destroys stashed work. SAFE ROUTE: ask Gavin." ;;
    git-history-prune) echo "git reflog expire/delete, git gc --prune=now and git prune destroy the recovery trail. SAFE ROUTE: ask Gavin." ;;
    rsync-delete)   echo "rsync --delete* / --remove-source-files deletes outside the Trash. SAFE ROUTE: rsync without them (-n to preview), then rm extras (bare rm), or ask Gavin." ;;
    inline-code)    echo "inline code deletes files (os.remove, shutil.rmtree, Path.unlink, fs.rm, unlink, /bin/rm...) outside the Trash. SAFE ROUTE: delete with bare rm in the shell, or ask Gavin." ;;
    prune)          echo "docker/podman prune or volume rm, compose down -v, brew cleanup or --zap, pnpm store prune, uv cache clean/prune and bun pm cache rm destroy data or caches. SAFE ROUTE: ask Gavin." ;;
    rimraf)         echo "rimraf deletes outside the Trash. SAFE ROUTE: bare rm -r." ;;
    disk)           echo "diskutil erase/partition, mkfs, newfs and wipefs destroy whole volumes. SAFE ROUTE: ask Gavin." ;;
    tmutil)         echo "tmutil delete* removes backups or snapshots. SAFE ROUTE: ask Gavin." ;;
    trash-empty)    echo "emptying the Trash (trash-empty, trash-rm, Finder empty trash) makes every earlier delete permanent. SAFE ROUTE: ask Gavin." ;;
    *)              echo "this command destroys data outside the Trash. SAFE ROUTE: ask Gavin." ;;
  esac
}

# ---------------------------------------------------------------- state
REASON=""; REASON_ID=""; REASON_WHERE=""
PIDBASE=0
SI_KIND=()        # SI_KIND[pid] = shell|code : an interpreter in that pipeline reads stdin
AL_N=(); AL_V=(); ALIAS_VAL=""; SNAP_FILE=""; SNAP_DONE=0
CWD=""            # the payload's cwd; used to tell a path from a branch name
DEPTH=0

_deny() { # $1 = rule id, $2 = where it was found (optional)
  [ -n "$REASON_ID" ] && return 0
  REASON_ID="$1"; REASON_WHERE="${2:-}"; REASON="$(_msg "$1")"
}

# The newest shell snapshot: its alias table is what an agent's zsh expands.
# The lexer reads it (awk getline) and sends A records for aliases it meets.
_snapshot_file() {
  SNAP_DONE=1
  local f newest=""
  set +f
  for f in "$SNAP_DIR"/snapshot-*.sh; do
    [ -f "$f" ] || continue
    if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
  done
  set -f
  SNAP_FILE="$newest"
}

# Sets ALIAS_VAL, rc 0 when $1 is an alias the lexer reported.
_alias_of() {
  ALIAS_VAL=""
  local k=0
  while [ $k -lt ${#AL_N[@]} ]; do
    if [ "${AL_N[$k]}" = "$1" ]; then ALIAS_VAL="${AL_V[$k]}"; return 0; fi
    k=$((k + 1))
  done
  return 1
}

# Deletion calls in inline code (python, node, perl, ruby, osascript, and the
# heredoc bodies fed to them). Word boundaries are spelled out: macOS regex has
# no \b.
_code_deletes() {
  local code="${1//$RSC/$'\n'}"
  local nb='(^|[^A-Za-z0-9_$])'
  local re1="${nb}(unlink|rmtree|rmdir|removedirs|remove_tree|unlinkSync|rmSync|rmdirSync)([^A-Za-z0-9_]|\$)"
  local re2="${nb}rm[[:space:]]*\\("
  local re3='os\.remove[[:space:]]*\(|os\.truncate|\.truncate[[:space:]]*\(|File\.delete|Dir\.delete|FileUtils\.(rm|remove)'
  local re4='/bin/rm|/usr/bin/rm|(^|[^A-Za-z0-9_])(shred|srm)[[:space:]]'
  local re5='[eE][mM][pP][tT][yY][[:space:]]+([tT][hH][eE][[:space:]]+)?[tT][rR][aA][sS][hH]'
  [[ $code =~ $re5 ]] && { _deny trash-empty "inline code"; return 0; }                              #M: empty-trash in code
  [[ $code =~ $re1 || $code =~ $re2 || $code =~ $re3 || $code =~ $re4 ]] && _deny inline-code "inline code"   #M: inline-code patterns
  return 0
}

# Lex and classify a piece of shell text (the top-level command, or an
# `sh -c` / eval / env -S string, or a heredoc fed to a shell).
_shell_text() { # $1 = text
  [ -n "$REASON_ID" ] && return 0
  [ "$DEPTH" -ge "$MAX_DEPTH" ] && return 0
  DEPTH=$((DEPTH + 1))
  local recs rc
  [ "$SNAP_DONE" -eq 1 ] || _snapshot_file
  recs="$(printf '%s' "$1" | LC_ALL=C awk -v base="$PIDBASE" -v snap="$SNAP_FILE" -v nofilter="${DEL_GUARD_NOFILTER:-0}" "$LEXER" 2>/dev/null)"; rc=$?
  if [ $rc -ne 0 ] || [[ $recs != *"E$US"* ]]; then
    LEXER_FAILED=1; DEPTH=$((DEPTH - 1)); return 0
  fi
  local -a lines hpids hbodies
  local line oldifs="$IFS"
  IFS=$'\n'; lines=($recs); IFS="$oldifs"
  local -a f
  for line in "${lines[@]}"; do
    IFS="$US"; f=($line); IFS="$oldifs"
    case "${f[0]}" in
      C) CUR_PID="${f[1]}"; _simple "${f[@]:2}" ;;
      A) AL_N[${#AL_N[@]}]="${f[1]}"; AL_V[${#AL_V[@]}]="${f[2]//$RSC/$'\n'}" ;;   #M: alias records
      H) hpids[${#hpids[@]}]="${f[1]}"; hbodies[${#hbodies[@]}]="${f[2]:-}" ;;
      E) [ "${f[1]}" -gt "$PIDBASE" ] 2>/dev/null && PIDBASE="${f[1]}" ;;
    esac
    [ -n "$REASON_ID" ] && break
  done
  # stdin data (heredocs, here-strings, echo piped in) reaching an interpreter
  local k=0 kind
  while [ -z "$REASON_ID" ] && [ $k -lt ${#hpids[@]} ]; do
    kind="${SI_KIND[${hpids[$k]}]:-}"
    case "$kind" in
      shell) _shell_text "${hbodies[$k]//$RSC/$'\n'}" ;;       #M: heredoc to a shell
      code)  _code_deletes "${hbodies[$k]}" ;;                  #M: heredoc to an interpreter
    esac
    k=$((k + 1))
  done
  DEPTH=$((DEPTH - 1))
}

# One simple command: split its redirections out, then classify argv.
_simple() {
  [ -n "$REASON_ID" ] && return 0
  local -a a=()
  local w expect="" trunc=""
  for w in "$@"; do
    if [ -n "$expect" ]; then
      case "$expect" in
        '>'|'&>')
          case "$w" in
            /dev/null|/dev/stdout|/dev/stderr|/dev/tty|/dev/fd/*|'$(...)'*) ;;
            *) trunc="$w" ;;   #M: truncation target
          esac ;;
        '>&')
          case "$w" in
            [0-9]|-|/dev/null|/dev/stdout|/dev/stderr|/dev/tty|'$(...)'*) ;;
            *) trunc="$w" ;;
          esac ;;
      esac
      expect=""; continue
    fi
    if [[ $w == "$OPM"* ]]; then expect="${w#"$OPM"}"; continue; fi
    a[${#a[@]}]="$w"
  done
  TRUNC="$trunc"
  if [ ${#a[@]} -eq 0 ]; then
    [ -n "$TRUNC" ] && _deny redir-trunc "> $TRUNC"      #M: bare truncating redirection
    return 0
  fi
  _argv "$ALIAS_DEPTH_CTX" "${a[@]}"
}

RE_ASSIGN='^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?='
RE_RM_P='^-[A-Za-z]*P'
RE_RSYNC_DEL='^--(del|delete|delete-[a-z-]+|remove-source-files|remove-sent-files)(=.*)?$'
_is_assign() { [[ $1 =~ $RE_ASSIGN ]]; }

# Classify one argv. $1 = alias depth, then the words.
_argv() {
  [ -n "$REASON_ID" ] && return 0
  local adepth="$1"; shift
  # leading assignments: VAR=1 cmd
  while [ $# -gt 0 ] && [[ $1 == *=* ]] && _is_assign "$1"; do
    case "$1" in SAFE_RM_OFF=*|SAFE_RM_OFF+=*) _deny safe-rm-off "$1"; return 0 ;; esac   #M: SAFE_RM_OFF prefix
    shift
  done
  if [ $# -eq 0 ]; then
    [ -n "$TRUNC" ] && _deny redir-trunc "> $TRUNC"
    return 0
  fi
  local c="$1"; shift
  c="${c#=}"                      # zsh =cmd expands to the PATH hit   #M: zsh =cmd
  local base="${c##*/}"
  local w k letters

  # aliases, as zsh expands them: the command word, recursively
  if [ "$adepth" -lt 5 ] && [ ${#AL_N[@]} -gt 0 ] && _alias_of "$c"; then
    local exp="$ALIAS_VAL" first q qq
    first="${exp%%[[:space:]]*}"
    if [ "$first" != "$c" ] || [ "$adepth" -eq 0 ]; then
      local joined="$exp" save_trunc="$TRUNC"
      for q in "$@"; do printf -v qq '%q' "$q"; joined="$joined $qq"; done
      _shell_text_alias "$joined" $((adepth + 1))                                           #M: alias expansion
      TRUNC="$save_trunc"
      [ -n "$REASON_ID" ] && { REASON_WHERE="alias $c='$exp'"; return 0; }
      # an alias that resolves to itself (alias ls='ls -G') falls through below
      [ "$first" = "$c" ] || return 0
    fi
  fi

  case "$base" in
    # ---- reserved words and precommands: look past them
    '{'|'}'|'!'|if|then|else|elif|fi|do|done|while|until|end|always|coproc|']]')
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                                   #M: reserved-word look-through
      return 0 ;;
    '[['|for|foreach|select|case|function|esac) return 0 ;;
    -|nohup|noglob|nocorrect|builtin|unbuffer|chronic)
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                                   #M: precommand look-through
      return 0 ;;
    command)
      while [ $# -gt 0 ]; do
        case "$1" in -v|-V) return 0 ;; esac   #M: command -v is a lookup
        case "$1" in -*) shift ;; *) break ;; esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"; return 0 ;;
    exec)
      while [ $# -gt 0 ]; do
        case "$1" in -a) shift 2 || set -- ;; -c|-l|-cl|-lc) shift ;; --) shift; break ;; *) break ;; esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: exec look-through
      return 0 ;;
    time)
      while [ $# -gt 0 ]; do case "$1" in -o) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: time look-through
      return 0 ;;
    repeat)
      [ $# -gt 0 ] && shift
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: repeat N look-through
      return 0 ;;
    sudo|doas)
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -u|-g|-h|-p|-C|-D|-r|-t|-T|-U|-c) shift 2 || set -- ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                                   #M: sudo look-through
      return 0 ;;
    env)
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -u|-C|-P|--unset|--chdir) shift 2 || set -- ;;
          -S|--split-string) _shell_text "${2:-}"; shift 2 || set --; [ -n "$REASON_ID" ] && return 0 ;;   #M: env -S
          --split-string=*) _shell_text "${1#*=}"; shift; [ -n "$REASON_ID" ] && return 0 ;;
          -*) shift ;;
          *) if _is_assign "$1"; then
               case "$1" in SAFE_RM_OFF=*) _deny safe-rm-off "env $1"; return 0 ;; esac   #M: env SAFE_RM_OFF
               shift
             else break; fi ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                                   #M: env look-through
      return 0 ;;
    export|declare|typeset|local|readonly)
      for w in "$@"; do
        :
        case "$w" in SAFE_RM_OFF=*|SAFE_RM_OFF) _deny safe-rm-off "$base $w"; return 0 ;; esac   #M: export SAFE_RM_OFF
      done
      return 0 ;;
    nice)
      while [ $# -gt 0 ]; do case "$1" in -n) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: nice look-through
      return 0 ;;
    timeout|gtimeout)
      while [ $# -gt 0 ]; do case "$1" in -s|-k) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && shift                     # the duration
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: timeout look-through
      return 0 ;;
    caffeinate)
      while [ $# -gt 0 ]; do case "$1" in -t|-w) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: caffeinate look-through
      return 0 ;;
    stdbuf|gstdbuf)
      while [ $# -gt 0 ]; do case "$1" in -i|-o|-e) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$adepth" "$@"   #M: stdbuf look-through
      return 0 ;;
    watch)
      while [ $# -gt 0 ]; do case "$1" in -n|--interval) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _shell_text "$*"   #M: watch look-through
      return 0 ;;
    xargs|gxargs)
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          -I|-n|-P|-L|-s|-d|-E|-a|-J|-R|-S|--arg-file|--delimiter|--max-args|--max-procs|--max-lines|--max-chars|--process-slot-var) shift 2 || set -- ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                                   #M: xargs look-through
      return 0 ;;
    eval)
      [ $# -gt 0 ] && _shell_text "$*"   #M: eval
      return 0 ;;
    sh|bash|zsh|dash|ksh|mksh|yash|fish)
      _shell_cmd "$@"; return 0 ;;

    # ---- the deleters themselves
    rm)
      if [[ $c == */* ]] && [[ $c != */.local/bin/rm ]]; then _deny rm-path "$c"; return 0; fi   #M: rm by path
      for w in "$@"; do
        [ "$w" = "--" ] && break
        if [[ $w =~ $RE_RM_P ]]; then _deny rm-P "rm $w"; return 0; fi                           #M: rm -P
      done
      return 0 ;;
    grm) _deny grm "grm"; return 0 ;;   #M: grm
    unlink|gunlink) _deny unlink "$base"; return 0 ;;                                            #M: unlink
    shred|gshred|srm|wipe) _deny shred "$base"; return 0 ;;                                      #M: shred
    truncate|gtruncate) _deny truncate "$base"; return 0 ;;                                      #M: truncate
    dd|gdd)
      for w in "$@"; do
        :
        case "$w" in of=/dev/null) ;; of=*) _deny dd-of "dd $w"; return 0 ;; esac                #M: dd of=
      done
      return 0 ;;
    :|true|cat|gcat|cp|gcp)
      if [ -n "$TRUNC" ]; then
        case "$base" in
          :|true) [ $# -eq 0 ] && { _deny redir-trunc ": > $TRUNC"; return 0; } ;;               #M: colon truncation
          cat|gcat) [ "$*" = /dev/null ] && { _deny redir-trunc "cat /dev/null > $TRUNC"; return 0; } ;;   #M: cat /dev/null truncation
        esac
      fi
      { [ "$base" = cp ] || [ "$base" = gcp ]; } && [ "${1:-}" = /dev/null ] && [ $# -eq 2 ] && { _deny redir-trunc "cp /dev/null $2"; return 0; }   #M: cp /dev/null
      return 0 ;;
    find|gfind)
      _find_cmd "$adepth" "$@"; return 0 ;;
    fd|fdfind)
      while [ $# -gt 0 ]; do
        case "$1" in
          -x|--exec|-X|--exec-batch)
            shift
            local -a sub=()
            while [ $# -gt 0 ] && [ "$1" != ";" ]; do sub[${#sub[@]}]="$1"; shift; done
            [ ${#sub[@]} -gt 0 ] && _argv "$adepth" "${sub[@]}"   #M: fd -x body
            [ -n "$REASON_ID" ] && return 0 ;;
          *) shift ;;
        esac
      done
      return 0 ;;
    git)
      _git_cmd "$@"; return 0 ;;
    rsync)
      for w in "$@"; do
        :
        [[ $w =~ $RE_RSYNC_DEL ]] && { _deny rsync-delete "rsync $w"; return 0; }            #M: rsync delete
      done
      return 0 ;;
    rimraf|del-cli) _deny rimraf "$base"; return 0 ;;   #M: rimraf
    docker|podman|docker-compose)
      _container_cmd "$base" "$@"; return 0 ;;
    brew)
      case "${1:-}" in
        cleanup) _deny prune "brew cleanup"; return 0 ;;                                         #M: brew cleanup
        uninstall|remove|rm) for w in "$@"; do [ "$w" = --zap ] && { _deny prune "brew $1 --zap"; return 0; }; done ;;   #M: brew --zap
      esac
      return 0 ;;
    pnpm)
      if [ "${1:-}" = store ] && [ "${2:-}" = prune ]; then _deny prune "pnpm store prune"; return 0; fi   #M: pnpm store prune
      if [ "${1:-}" = dlx ] || [ "${1:-}" = exec ]; then shift; [ $# -gt 0 ] && _argv "$adepth" "$@"; fi   #M: pnpm dlx look-through
      return 0 ;;
    bun)
      if [ "${1:-}" = pm ] && [ "${2:-}" = cache ] && [ "${3:-}" = rm ]; then _deny prune "bun pm cache rm"; return 0; fi   #M: bun pm cache rm
      if [ "${1:-}" = x ]; then shift; [ $# -gt 0 ] && _argv "$adepth" "$@"; return 0; fi
      _interp_cmd node "$@"; return 0 ;;
    bunx|npx|pnpx)
      while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] && _argv "$adepth" "$@"; return 0 ;;
    uv)
      _uv_cmd "$adepth" "$@"; return 0 ;;
    python|python[0-9]*|pypy|pypy[0-9]*)
      _interp_cmd python "$@"; return 0 ;;
    node|nodejs|deno)
      if [ "$base" = deno ] && [ "${1:-}" = eval ]; then _code_deletes "${2:-}"; return 0; fi   #M: deno eval
      _interp_cmd node "$@"; return 0 ;;
    perl|ruby)
      _interp_cmd "$base" "$@"; return 0 ;;
    osascript)
      while [ $# -gt 0 ]; do
        [ "$1" = -e ] && { _code_deletes "${2:-}"; [ -n "$REASON_ID" ] && return 0; }   #M: osascript -e
        shift
      done
      return 0 ;;
    diskutil)
      case "${1:-}" in
        erase*|zeroDisk|randomDisk|secureErase|partitionDisk|reformat|apfs)
          if [ "${1:-}" != apfs ]; then _deny disk "diskutil $1"; return 0; fi   #M: diskutil erase
          case "${2:-}" in delete*|erase*) _deny disk "diskutil apfs $2"; return 0 ;; esac ;;
      esac
      return 0 ;;
    mkfs|mkfs.*|newfs|newfs_*|wipefs) _deny disk "$base"; return 0 ;;   #M: mkfs / newfs / wipefs
    tmutil)
      case "${1:-}" in delete|deletelocalsnapshots|thinlocalsnapshots|deleteinprogress) _deny tmutil "tmutil $1"; return 0 ;; esac   #M: tmutil delete
      return 0 ;;
    trash-empty|trash-rm) _deny trash-empty "$base"; return 0 ;;   #M: trash-empty
    # oh-my-zsh aliases that hide a reset --hard, denied BY NAME as well (Gavin,
    # 2026-09-23). The snapshot's alias table normally denies them by their
    # expansion above; this arm covers a hook that cannot read the snapshot.
    grhh|gwipe|gpristine) _deny git-reset-hard "alias $base (oh-my-zsh: git reset --hard$([ "$base" = grhh ] || echo ' && git clean'))"; return 0 ;;   #M: oh-my-zsh reset aliases by name
  esac
  return 0
}

# An alias expansion is shell text, classified with the alias depth carried.
_shell_text_alias() { # $1 = text, $2 = alias depth
  local save="$ALIAS_DEPTH_CTX"; ALIAS_DEPTH_CTX="$2"
  _shell_text "$1"
  ALIAS_DEPTH_CTX="$save"
}
ALIAS_DEPTH_CTX=0

_shell_cmd() { # sh/bash/zsh [opts] [-c CODE | script | -s]
  local code="" want_code=0 w
  while [ $# -gt 0 ]; do
    w="$1"
    case "$w" in
      --) shift; break ;;
      -o|+o|-O|+O) shift 2 || set --; continue ;;
      -|--noprofile|--norc|--login|--posix) shift; continue ;;
      --*) shift; continue ;;
      -*|+*)
        [[ $w == *c* ]] && want_code=1
        [[ $w == *s* ]] && SI_KIND[$CUR_PID]=shell
        shift; continue ;;
    esac
    break
  done
  if [ "$want_code" -eq 1 ]; then
    [ $# -gt 0 ] && _shell_text "$1"                                                 #M: sh -c
    return 0
  fi
  [ $# -eq 0 ] && SI_KIND[$CUR_PID]=shell   #M: shell reading stdin
  return 0
}

_interp_cmd() { # $1 = python|node|perl|ruby, then args
  local kind="$1"; shift
  local w
  while [ $# -gt 0 ]; do
    w="$1"
    case "$kind" in
      python)
        case "$w" in
          -c) _code_deletes "${2:-}"; return 0 ;;                                     #M: python -c
          -c*) _code_deletes "${w#-c}"; return 0 ;;
          -m) return 0 ;;
          -W|-X) shift 2 || set --; continue ;;
          -[A-Za-z]*c) _code_deletes "${2:-}"; return 0 ;;   #M: python -Xc cluster (a GLOB: letter, anything, c)
          -*) shift; continue ;;
          *) return 0 ;;                            # a script file: invisible
        esac ;;
      node)
        case "$w" in
          -e|--eval|-p|--print) _code_deletes "${2:-}"; return 0 ;;                  #M: node -e
          --eval=*|--print=*) _code_deletes "${w#*=}"; return 0 ;;
          -r|--require|--import|--loader) shift 2 || set --; continue ;;
          -*) shift; continue ;;
          *) return 0 ;;
        esac ;;
      perl|ruby)
        case "$w" in
          -e|-E) _code_deletes "${2:-}"; [ -n "$REASON_ID" ] && return 0; shift 2 || set --; continue ;;   #M: perl/ruby -e
          -[A-Za-z]*[eE]) _code_deletes "${2:-}"; [ -n "$REASON_ID" ] && return 0; shift 2 || set --; continue ;;
          -[A-Za-z]*[eE]?*) _code_deletes "${w#*[eE]}"; [ -n "$REASON_ID" ] && return 0; shift; continue ;;
          -) SI_KIND[$CUR_PID]=code; return 0 ;;
          -*) shift; continue ;;
          *) return 0 ;;
        esac ;;
    esac
  done
  # only options, or `-`, or nothing at all: the code arrives on stdin
  SI_KIND[$CUR_PID]=code   #M: interpreter reading stdin
  return 0
}

_uv_cmd() { # uv [global opts] run|cache|tool ...
  local adepth="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --directory|--project|--cache-dir|--config-file|--color|--python|-p) shift 2 || set -- ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  case "${1:-}" in
    cache)
      case "${2:-}" in clean|prune) _deny prune "uv cache $2"; return 0 ;; esac   #M: uv cache clean
      return 0 ;;
    run)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          --with|--with-editable|--with-requirements|--python|-p|--project|--directory|--package|--extra|--group|--only-group|--no-group|--env-file|--index|--default-index|--index-url|--extra-index-url|--find-links|-f|--upgrade-package|--reinstall-package|--cache-dir|--config-file|--exclude-newer|--python-platform|--color) shift 2 || set -- ;;
          -m|--module) return 0 ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] && _argv "$adepth" "$@"                                             #M: uv run look-through
      return 0 ;;
  esac
  return 0
}

_container_cmd() { # docker|podman|docker-compose, then args
  local tool="$1"; shift
  local -a pos=(); local w vol=0
  for w in "$@"; do
    case "$w" in
      -v|--volumes) vol=1 ;;
      -*) ;;
      *) pos[${#pos[@]}]="$w" ;;
    esac
  done
  local p0="${pos[0]:-}" p1="${pos[1]:-}"
  if [ "$p0" = prune ] || [ "$p1" = prune ]; then _deny prune "$tool ... prune"; return 0; fi      #M: docker prune
  if [ "$p0" = volume ] && { [ "$p1" = rm ] || [ "$p1" = remove ]; }; then _deny prune "$tool volume $p1"; return 0; fi   #M: docker volume rm
  { { [ "$tool" = docker-compose ] && [ "$p0" = down ]; } || { [ "$p0" = compose ] && [ "$p1" = down ]; }; } && [ "$vol" -eq 1 ] && { _deny prune "$tool compose down -v"; return 0; }   #M: compose down -v
  return 0
}

_find_cmd() { # find args: -delete, and -exec/-execdir/-ok/-okdir bodies
  local adepth="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -delete) _deny find-delete "find -delete"; return 0 ;;                          #M: find -delete
      -exec|-execdir|-ok|-okdir)
        shift
        local -a sub=()
        while [ $# -gt 0 ] && [ "$1" != ";" ] && [ "$1" != "+" ]; do sub[${#sub[@]}]="$1"; shift; done
        [ ${#sub[@]} -gt 0 ] && _argv "$adepth" "${sub[@]}"                           #M: find -exec body
        [ -n "$REASON_ID" ] && { REASON_WHERE="find -exec ${REASON_WHERE}"; return 0; }
        ;;
    esac
    [ $# -gt 0 ] && shift
  done
  return 0
}

_exists() { # $1 = path, $2 = directory it is relative to
  local p="$1" base="$2"
  [ -n "$p" ] || return 1
  case "$p" in /*) [ -e "$p" ]; return ;; esac
  [ -n "$base" ] || return 1
  [ -e "$base/$p" ]
}

# Short-option letters and long options of the current git call (dynamic scope).
_l() { [[ $letters == *"$1"* ]]; }
_o() { [[ $longs == *" $1 "* ]]; }

_git_cmd() {
  local gdir="$CWD" w
  # global options, and the directory they point at
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) case "${2:-}" in /*) gdir="${2:-}" ;; *) [ -n "$gdir" ] && gdir="$gdir/${2:-}" ;; esac; shift 2 || set -- ;;   #M: git -C
      -c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) shift 2 || set -- ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  local sub="${1:-}"; [ $# -gt 0 ] && shift
  local letters="" longs=" " args=() dd=0 after=()
  for w in "$@"; do
    if [ "$dd" -eq 1 ]; then after[${#after[@]}]="$w"; continue; fi
    case "$w" in
      --) dd=1 ;;
      --*) longs="$longs${w%%=*} " ; [[ $w == --prune=* ]] && longs="$longs$w " ;;
      -[A-Za-z]*) letters="$letters${w#-}" ;;
      *) args[${#args[@]}]="$w" ;;
    esac
  done
  case "$sub" in
    worktree)
      [ "${args[0]:-}" = remove ] && _deny git-worktree-remove "git worktree remove"          #M: git worktree remove
      ;;
    clean)
      _l n || _o --dry-run || _deny git-clean "git clean"                                     #M: git clean
      ;;
    reset)
      _o --hard && _deny git-reset-hard "git reset --hard"                                    #M: git reset --hard
      ;;
    checkout)
      if [ ${#after[@]} -gt 0 ] || _l f || _o --force; then _deny git-checkout-discard "git checkout"; return 0; fi   #M: git checkout --
      # -b/-B/--orphan take a branch name; that name is not a path
      local -a pos=(); local skip=0
      for w in "$@"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$w" in -b|-B|--orphan|--conflict) skip=1 ;; -*) ;; *) pos[${#pos[@]}]="$w" ;; esac
      done
      if [ ${#pos[@]} -ge 2 ]; then _deny git-checkout-discard "git checkout <ref> <path>"; return 0; fi   #M: git checkout <ref> <path>
      if [ ${#pos[@]} -eq 1 ]; then
        case "${pos[0]}" in
          .|./|:/|:/*|*'*'*|*'?'*) _deny git-checkout-discard "git checkout ${pos[0]}"; return 0 ;;   #M: git checkout .
        esac
        if _exists "${pos[0]}" "$gdir"; then _deny git-checkout-discard "git checkout ${pos[0]} (a path on disk)"; return 0; fi   #M: checkout path on disk
      fi ;;
    restore)
      if ! { _l S || _o --staged; } || _l W || _o --worktree; then _deny git-restore "git restore"; fi   #M: git restore
      ;;
    switch)
      if _l f || _o --force || _o --discard-changes; then _deny git-switch-discard "git switch"; fi      #M: git switch -f
      ;;
    branch)
      if _l D || _l M || _l C; then _deny git-branch-force "git branch -$letters"; return 0; fi   #M: git branch -D
      if { _l d || _o --delete || _l m || _o --move || _l c || _o --copy; } && { _l f || _o --force; }; then _deny git-branch-force "git branch --force"; fi   #M: git branch --delete --force
      ;;
    stash)
      case "${args[0]:-}" in drop|clear) _deny git-stash-drop "git stash ${args[0]}" ;; esac   #M: git stash drop
      ;;
    reflog)
      case "${args[0]:-}" in expire|delete) _deny git-history-prune "git reflog ${args[0]}" ;; esac   #M: git reflog expire
      ;;
    gc)
      case "$longs" in *' --prune=now '*|*' --prune=all '*) _deny git-history-prune "git gc --prune=now" ;; esac   #M: git gc --prune=now
      ;;
    prune)
      _deny git-history-prune "git prune"                                                     #M: git prune
      ;;
    submodule)
      if [ "${args[0]:-}" = foreach ]; then
        local -a rest=(); local seen=0
        for w in "$@"; do
          if [ "$seen" -eq 1 ]; then case "$w" in --recursive|-q|--quiet) ;; *) rest[${#rest[@]}]="$w" ;; esac; fi
          [ "$w" = foreach ] && seen=1
        done
        [ ${#rest[@]} -gt 0 ] && _shell_text "${rest[*]}"   #M: git submodule foreach
      fi ;;
  esac
  return 0
}

# Classify one whole command string. Sets REASON_ID / REASON / REASON_WHERE.
_classify() { # $1 = command, $2 = cwd (optional)
  REASON=""; REASON_ID=""; REASON_WHERE=""; PIDBASE=0; SI_KIND=(); DEPTH=0
  AL_N=(); AL_V=(); LEXER_FAILED=0; CWD="${2:-}"; TRUNC=""; CUR_PID=0
  _shell_text "$1"
  return 0
}

# ---------------------------------------------------------------- log
_redact() { # stdin -> stdout, capped, one line, token shapes removed
  LC_ALL=C sed -E \
    -e 's/(gh[pousr]_|github_pat_|glpat-|xox[abposr]-|sk-ant-|sk-)[A-Za-z0-9_-]{8,}/[redacted]/g' \
    -e 's/AKIA[0-9A-Z]{12,}/[redacted]/g' \
    -e 's/([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|_KEY|CREDENTIAL|PRIVKEY|PAT)[A-Za-z0-9_]*=)[^[:space:]]+/\1[redacted]/g' \
    | tr '\n\t' '  ' | cut -c1-400
}

_log() { # $1 = rule id, $2 = command
  local red; red="$(printf '%s' "$2" | _redact)"
  { mkdir -p "$(dirname "$LOG_FILE")" && \
    printf '[%s] BLOCKED %s "%s" "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HOOK_NAME" "$1" "$red" >> "$LOG_FILE"; } 2>/dev/null
  return 0
}

# ---------------------------------------------------------------- selftest
_selftest() {
  local fails=0 passes=0 self="$0"
  local fx; fx="$(mktemp -d "${TMPDIR:-/tmp}/del-guard-selftest.XXXXXX")" || { echo "cannot make a fixture dir"; return 1; }
  mkdir -p "$fx/repo/src" "$fx/snap"; : > "$fx/repo/src/app.c"; : > "$fx/repo/notes.txt"
  # a fixture snapshot: one alias that expands to a denied command, harmless ones, a self-alias
  cat > "$fx/snap/snapshot-zsh-1-fixture.sh" <<'SNAP'
alias -- gclean='git clean -fdx'
alias -- gwtrm='git worktree remove'
alias -- nuke='gclean'
alias -- ll='eza -l'
alias -- ls='ls -G'
alias -- gs='git status'
alias -- q='echo '\''git clean -fdx'\'''
rm () {
	if [[ -n "$SAFE_RM_OFF" ]]; then /bin/rm "$@"; else safe-rm "$@"; fi
}
SNAP
  local save_snap="$SNAP_DIR"; SNAP_DIR="$fx/snap"; SNAP_DONE=0

  # Every arm runs twice: with the lexer's prefilter, and with it off
  # (DEL_GUARD_NOFILTER=1). Both must give the expected answer, which proves
  # the filter never hides a command the rules would have denied.
  _must() { # $1 = expected rule id or - for allow, $2 = label, $3 = command, $4 = cwd
    local got got2
    _classify "$3" "${4:-$fx/repo}"; got="${REASON_ID:--}"
    DEL_GUARD_NOFILTER=1 _classify "$3" "${4:-$fx/repo}"; got2="${REASON_ID:--}"
    if [ "$got" = "$1" ] && [ "$got2" = "$1" ]; then passes=$((passes + 1)); printf 'ok    %-26s %s\n' "$1" "$2"
    else fails=$((fails + 1)); printf 'FAIL  %-26s %s  (got %s, unfiltered %s)\n' "$1" "$2" "$got" "$got2"; fi
  }

  echo "=== DENY arms: each must be refused by the named rule ==="
  _must git-worktree-remove 'git worktree remove'            'git worktree remove ../wt'
  _must git-worktree-remove 'worktree remove --force'        'git worktree remove --force .worktree/x'
  _must git-clean           'git clean -fdx'                  'git clean -fdx'
  _must git-clean           'git clean -f'                    'git clean -f'
  _must git-clean           'git clean -xfd -e keep'          'git clean -xfd -e keep'
  _must git-reset-hard      'git reset --hard'                'git reset --hard'
  _must git-reset-hard      'git reset --hard HEAD~1'         'git reset --hard HEAD~1'
  _must git-checkout-discard 'git checkout -- path'           'git checkout -- src/app.c'
  _must git-checkout-discard 'git checkout .'                 'git checkout .'
  _must git-checkout-discard 'git checkout HEAD -- f'         'git checkout HEAD -- notes.txt'
  _must git-checkout-discard 'git checkout <file on disk>'    'git checkout notes.txt'
  _must git-checkout-discard 'git checkout main <file>'       'git checkout main notes.txt'
  _must git-checkout-discard 'git checkout -f main'           'git checkout -f main'
  _must git-checkout-discard "git checkout '*.c'"             "git checkout '*.c'"
  _must git-restore         'git restore f'                   'git restore notes.txt'
  _must git-restore         'git restore .'                   'git restore .'
  _must git-restore         'git restore --staged --worktree' 'git restore --staged --worktree notes.txt'
  _must git-restore         'git restore -SW'                 'git restore -SW notes.txt'
  _must git-switch-discard  'git switch --discard-changes'    'git switch --discard-changes main'
  _must git-branch-force    'git branch -D'                   'git branch -D feature'
  _must git-branch-force    'git branch --delete --force'     'git branch --delete --force feature'
  _must git-branch-force    'git branch -df'                  'git branch -df feature'
  _must git-branch-force    'git branch -M (overwrite)'       'git branch -M old new'
  _must git-stash-drop      'git stash drop'                  'git stash drop'
  _must git-stash-drop      'git stash clear'                 'git stash clear'
  _must git-history-prune   'git reflog expire'               'git reflog expire --expire=now --all'
  _must git-history-prune   'git gc --prune=now'              'git gc --prune=now'
  _must git-history-prune   'git prune'                       'git prune'
  _must find-delete         'find -delete'                    'find . -name "*.o" -delete'
  _must rm-path             'find -exec /bin/rm'              'find . -name x -exec /bin/rm {} \;'
  _must unlink              'find -exec unlink'               'find . -type f -exec unlink {} +'
  _must rm-path             'fd -x /bin/rm'                   'fd -e tmp -x /bin/rm'
  _must rm-path             '/bin/rm'                         '/bin/rm -rf build'
  _must rm-path             '/usr/bin/rm'                     '/usr/bin/rm x'
  _must rm-path             'quoted /bin/rm as command'       '"/bin/rm" x'
  _must rm-path             'backslashed /bin/rm'             '\/bin/rm x'
  _must rm-path             'env rm by path'                  'env /bin/rm x'
  _must rm-P                'rm -P'                           'rm -P secret.txt'
  _must rm-P                'rm -rfP cluster'                 'rm -rfP dir'
  _must safe-rm-off         'SAFE_RM_OFF=1 rm'                'SAFE_RM_OFF=1 rm x'
  _must safe-rm-off         'export SAFE_RM_OFF'              'export SAFE_RM_OFF=1; rm x'
  _must safe-rm-off         'env SAFE_RM_OFF=1'               'env SAFE_RM_OFF=1 rm x'
  _must grm                 'grm (GNU rm)'                    'grm -rf x'
  _must unlink              'unlink'                          'unlink file'
  _must shred               'shred'                           'shred -u key'
  _must shred               'srm'                             'srm -rf dir'
  _must truncate            'truncate -s0'                    'truncate -s0 log.txt'
  _must dd-of               'dd of='                          'dd if=/dev/zero of=disk.img bs=1m count=1'
  _must redir-trunc         '> f (bare)'                      '> notes.txt'
  _must redir-trunc         ': > f'                           ': > notes.txt'
  _must redir-trunc         'true >| f'                       'true >| notes.txt'
  _must redir-trunc         'zsh >! f bare'                   '>! notes.txt'
  _must redir-trunc         'cat /dev/null > f'               'cat /dev/null > notes.txt'
  _must redir-trunc         'cp /dev/null f'                  'cp /dev/null notes.txt'
  _must redir-trunc         '2> f bare'                       '2> notes.txt'
  _must rsync-delete        'rsync --delete'                  'rsync -a --delete src/ dst/'
  _must rsync-delete        'rsync --delete-after'            'rsync -a --delete-after src/ dst/'
  _must rsync-delete        'rsync --del'                     'rsync -a --del src/ dst/'
  _must rsync-delete        'rsync --remove-source-files'     'rsync -a --remove-source-files src/ dst/'
  _must inline-code         'python3 -c os.remove'            "python3 -c 'import os; os.remove(\"x\")'"
  _must inline-code         'uv run python -c shutil.rmtree'  'uv run python -c "import shutil; shutil.rmtree(\"d\")"'
  _must inline-code         'uv run --with x python3 -c'      "uv run --with rich python3 -c 'from pathlib import Path; Path(\"x\").unlink()'"
  _must inline-code         'python3 -c os.unlink'            "python3 -c 'import os; os.unlink(\"x\")'"
  _must inline-code         'python3 -c rmdir'                "python3 -c 'import os; os.rmdir(\"d\")'"
  _must inline-code         'node -e fs.rmSync'               "node -e 'require(\"fs\").rmSync(\"d\",{recursive:true})'"
  _must inline-code         'node -e fs.unlinkSync'           "node -e 'require(\"fs\").unlinkSync(\"f\")'"
  _must inline-code         'node -e fs.rm'                   "node -e 'require(\"fs\").rm(\"d\", ()=>{})'"
  _must inline-code         'perl -e unlink'                  "perl -e 'unlink \"f\"'"
  _must inline-code         'ruby -e FileUtils.rm_rf'         "ruby -e 'require \"fileutils\"; FileUtils.rm_rf(\"d\")'"
  _must inline-code         'python heredoc (uv run -)'       $'uv run python3 - <<\'EOF\'\nimport os\nos.remove("x")\nEOF'
  _must inline-code         'python3 heredoc no args'         $'python3 <<EOF\nimport shutil; shutil.rmtree("d")\nEOF'
  _must inline-code         'cat heredoc | python3'           $'cat <<EOF | python3\nimport os; os.remove("x")\nEOF'
  _must inline-code         'here-string to python3'          "python3 <<< 'import os; os.remove(\"x\")'"
  _must inline-code         'echo code | python3'             "echo 'import os; os.remove(\"x\")' | python3"
  _must prune               'docker system prune'             'docker system prune -af'
  _must prune               'docker volume prune'             'docker volume prune -f'
  _must prune               'docker volume rm'                'docker volume rm pgdata'
  _must prune               'docker compose down -v'          'docker compose down -v'
  _must prune               'brew cleanup'                    'brew cleanup --prune=all'
  _must prune               'brew uninstall --zap'            'brew uninstall --zap --cask foo'
  _must prune               'pnpm store prune'                'pnpm store prune'
  _must prune               'uv cache clean'                  'uv cache clean'
  _must prune               'bun pm cache rm'                 'bun pm cache rm'
  _must rimraf              'pnpm dlx rimraf'                 'pnpm dlx rimraf dist'
  _must disk                'diskutil eraseDisk'              'diskutil eraseDisk APFS X disk4'
  _must disk                'mkfs.ext4'                       'mkfs.ext4 /dev/sdb1'
  _must tmutil              'tmutil deletelocalsnapshots'     'tmutil deletelocalsnapshots /'
  _must trash-empty         'trash-empty'                     'trash-empty'
  _must trash-empty         'osascript empty trash'           "osascript -e 'tell application \"Finder\" to empty the trash'"

  echo "=== DENY arms: every prefix and position the anchor must see through ==="
  _must git-worktree-remove 'after &&'                        'git status && git worktree remove x'
  _must git-worktree-remove 'after ||'                        'false || git worktree remove x'
  _must git-worktree-remove 'after ;'                         'echo hi; git worktree remove x'
  _must git-worktree-remove 'after |'                         'echo x | git worktree remove x'
  _must git-worktree-remove 'after newline'                   $'echo hi\ngit worktree remove x'
  _must git-worktree-remove 'inside ( )'                      '(git worktree remove x)'
  _must git-worktree-remove 'inside { }'                      '{ git worktree remove x; }'
  _must git-worktree-remove 'inside $( )'                     'echo "$(git worktree remove x)"'
  _must git-worktree-remove 'inside backticks'                'echo `git worktree remove x`'
  _must git-worktree-remove 'inside <( )'                     'cat <(git worktree remove x)'
  _must git-worktree-remove 'zsh =( )'                        'cat =(git worktree remove x)'
  _must git-worktree-remove 'VAR=1 prefix'                    'FOO=1 git worktree remove x'
  _must git-worktree-remove 'sudo'                            'sudo git worktree remove x'
  _must git-worktree-remove 'sudo -u root'                    'sudo -u root git worktree remove x'
  _must git-worktree-remove 'command'                         'command git worktree remove x'
  _must git-worktree-remove 'nohup'                           'nohup git worktree remove x'
  _must git-worktree-remove 'time'                            'time git worktree remove x'
  _must git-worktree-remove 'xargs'                           'echo x | xargs -n1 git worktree remove'
  _must git-worktree-remove 'env'                             'env -i FOO=1 git worktree remove x'
  _must git-worktree-remove 'git -C path'                     'git -C /tmp/repo worktree remove x'
  _must git-worktree-remove 'git -c k=v'                      'git -c core.x=1 worktree remove x'
  _must git-worktree-remove 'git --git-dir='                  'git --git-dir=/r/.git worktree remove x'
  _must git-worktree-remove 'path to git'                     '/usr/bin/git worktree remove x'
  _must git-worktree-remove 'zsh noglob'                      'noglob git worktree remove x'
  _must git-worktree-remove 'zsh nocorrect'                   'nocorrect git worktree remove x'
  _must git-worktree-remove 'zsh - precommand'                '- git worktree remove x'
  _must git-worktree-remove 'builtin/exec'                    'exec git worktree remove x'
  _must git-worktree-remove 'zsh &! then cmd'                 'sleep 1 &! git worktree remove x'
  _must git-worktree-remove 'zsh &| then cmd'                 'sleep 1 &| git worktree remove x'
  _must git-worktree-remove 'zsh |&'                          'echo x |& git worktree remove x'
  _must git-worktree-remove 'zsh repeat N'                    'repeat 2 git worktree remove x'
  _must git-worktree-remove 'if/then'                         'if true; then git worktree remove x; fi'
  _must git-worktree-remove 'sh -c'                           "sh -c 'git worktree remove x'"
  _must git-worktree-remove 'bash -lc'                        "bash -lc 'git worktree remove x'"
  _must git-worktree-remove 'zsh -c nested sudo'              "zsh -c 'sudo git worktree remove x'"
  _must git-worktree-remove 'eval'                            "eval 'git worktree remove x'"
  _must git-worktree-remove 'bash heredoc'                    $'bash <<EOF\ngit worktree remove x\nEOF'
  _must git-worktree-remove 'timeout 5'                       'timeout 5 git worktree remove x'
  _must git-worktree-remove 'nice -n'                         'nice -n 5 git worktree remove x'
  _must git-worktree-remove 'line continuation'               $'git worktree \\\nremove x'
  _must git-worktree-remove 'git submodule foreach'           "git submodule foreach 'git worktree remove x'"
  _must git-clean           'git -C path clean'               'git -C sub clean -fdx'
  _must rm-path             'sudo /bin/rm'                    'sudo /bin/rm -rf /opt/x'
  _must rm-path             'xargs /bin/rm'                   'ls | xargs /bin/rm'
  _must rm-path             'ANSI-C quoted path'              $'$\'\\x2fbin\\x2frm\' x'
  _must rm-path             'zsh =rm style path'              '=/bin/rm x'
  _must unlink              'zsh =unlink (= stripped)'        '=unlink x'
  _must shred               'command shred'                   'command shred x'
  _must git-clean           'git clean in sh -c after &&'     "cd_ok=1 && sh -c 'ls; git clean -fd'"
  _must git-clean           'alias gclean (fixture)'          'gclean'
  _must git-clean           'alias of alias (nuke->gclean)'   'nuke'
  _must git-worktree-remove 'alias gwtrm + args'              'gwtrm ../wt'
  _must git-clean           'alias after &&'                  'git status && gclean'
  _must git-reset-hard      'grhh by name (not in snapshot)'  'grhh'
  _must git-reset-hard      'gwipe by name'                   'gwipe'
  _must git-reset-hard      'gpristine by name, after &&'     'git fetch && gpristine'
  _must git-reset-hard      'sudo gpristine'                  'sudo gpristine'
  _must git-worktree-remove 'unquoted $( ) in an assignment'  'x=$(git worktree remove y)'
  _must git-worktree-remove '$( ) inside ${(f)...}'           'echo ${(f)"$(git worktree remove x)"}'
  _must git-worktree-remove 'backticks inside double quotes'  'echo "`git worktree remove x`"'
  _must git-worktree-remove 'after a <<- heredoc'             $'cat <<-EOF\n\tprose\n\tEOF\ngit worktree remove x'
  _must git-worktree-remove 'caffeinate'                      'caffeinate -i git worktree remove x'
  _must git-worktree-remove 'stdbuf'                          'stdbuf -oL git worktree remove x'
  _must git-worktree-remove 'watch'                           'watch -n 5 git worktree remove x'
  _must git-worktree-remove 'env -S string'                   "env -S 'git worktree remove x'"
  _must git-worktree-remove 'pnpm exec'                       'pnpm exec git worktree remove x'
  _must inline-code         'perl -ne cluster'                "perl -ne 'unlink \$_' list.txt"
  _must inline-code         'python3 -Ic cluster'             "python3 -Ic 'import os; os.remove(\"x\")'"
  _must inline-code         'deno eval'                       "deno eval 'Deno.removeSync(\"x\"); unlink(\"y\")'"
  _must inline-code         'node heredoc'                    $'node <<EOF\nrequire("fs").rmSync("d")\nEOF'
  _must inline-code         'node - heredoc'                  $'node - <<EOF\nrequire("fs").unlinkSync("f")\nEOF'
  _must git-clean           'zsh heredoc to sh -s'            $'sh -s <<EOF\ngit clean -fdx\nEOF'

  echo "=== ALLOW arms: each must pass untouched ==="
  _must - 'bare rm'                         'rm notes.txt'
  _must - 'rm -rf dir'                      'rm -rf build'
  _must - 'command rm'                      'command rm x'
  _must - '\rm'                             '\rm x'
  _must - 'rm -r dir'                       'rm -r dir'
  _must - 'rm -- -P (a file named -P)'      'rm -- -P'
  _must - 'zsh glob qualifier rm *(.)'      'rm *(.)'
  _must - 'zsh glob qualifier rm **/*(N.)'  'rm -f **/*.o(N.)'
  _must - 'git worktree list'               'git worktree list'
  _must - 'git worktree add'                'git worktree add ../wt -b x'
  _must - 'git worktree prune'              'git worktree prune'
  _must - 'git clean -n'                    'git clean -n'
  _must - 'git clean -nd'                   'git clean -nd'
  _must - 'git clean -fdn'                  'git clean -fdn'
  _must - 'git clean --dry-run -fd'         'git clean --dry-run -fd'
  _must - 'git branch -d'                   'git branch -d feature'
  _must - 'git branch -m rename'            'git branch -m old new'
  _must - 'git branch --list'               'git branch --list'
  _must - 'git checkout main'               'git checkout main'
  _must - 'git checkout -b x'               'git checkout -b feature/x'
  _must - 'git checkout -b x origin/x'      'git checkout -b x origin/x'
  _must - 'git switch main'                 'git switch main'
  _must - 'git restore --staged f'          'git restore --staged notes.txt'
  _must - 'git restore -S f'                'git restore -S notes.txt'
  _must - 'git stash push -u'               'git stash push -u -m tag'
  _must - 'git stash list'                  'git stash list'
  _must - 'git stash pop'                   'git stash pop'
  _must - 'git stash apply sha'             'git stash apply abc123'
  _must - 'git reset (soft default)'        'git reset HEAD notes.txt'
  _must - 'git reset --soft'                'git reset --soft HEAD~1'
  _must - 'git gc (default)'                'git gc'
  _must - 'git remote prune'                'git remote prune origin'
  _must - 'git fetch --prune'               'git fetch --prune'
  _must - 'git rm (tracked)'                'git rm notes.txt'
  _must - 'find -print'                     'find . -name x -print'
  _must - 'find -exec rm (bare)'            'find . -name "*.o" -exec rm {} +'
  _must - 'find -exec grep'                 'find . -exec grep -l delete {} \;'
  _must - 'fd -x rm (bare)'                 'fd -e tmp -x rm'
  _must - 'cmd > out.txt'                   'ls > out.txt'
  _must - 'cmd 2>&1 > out'                  'make 2>&1 > build.log'
  _must - '>> append bare'                  '>> notes.txt'
  _must - ': > /dev/null'                   ': > /dev/null'
  _must - 'exec > log (logging setup)'      'exec > run.log'
  _must - 'echo -n > f (output)'            'echo -n > f'
  _must - 'rsync -a'                        'rsync -a src/ dst/'
  _must - 'rsync --delay-updates'           'rsync -a --delay-updates src/ dst/'
  _must - 'rsync --max-delete'              'rsync -a --max-delete=0 src/ dst/'
  _must - 'dd of=/dev/null'                 'dd if=big of=/dev/null bs=1m'
  _must - 'dd without of='                  'dd if=/dev/urandom bs=16 count=1'
  _must - 'commit message with the words'   'git commit -m "note: git worktree remove and git clean -fdx are banned"'
  _must - 'commit heredoc with the words'   $'git commit -F - <<\'EOF\'\ngit worktree remove x\n/bin/rm -P x\nfind . -delete\nEOF'
  _must - 'echo prose'                      'echo "never run /bin/rm or git reset --hard"'
  _must - 'echo unquoted words'             'echo git worktree remove is banned'
  _must - 'rg pattern'                      "rg 'git clean' docs/"
  _must - 'rg unlink'                       'rg -n unlink src/'
  _must - 'decided add --body'              'decided add "x" --body "we shred nothing; unlink is banned"'
  _must - 'comment'                         'ls # then git worktree remove x'
  _must - 'comment holding a ;'             'ls # tidy up; git worktree remove x'
  _must - 'python3 -c reads only'           "python3 -c 'print(open(\"x\").read())'"
  _must - 'uv run python3 script.py'        'uv run python3 tools/census.py --control x y'
  _must - 'python heredoc reads only'       $'uv run python3 - <<\'EOF\'\nimport json; print(json.load(open("a")))\nEOF'
  _must - 'python -m module'                'python3 -m http.server'
  _must - 'node -e harmless'                "node -e 'console.log(1)'"
  _must - 'cat heredoc (not an interpreter)' $'cat <<EOF\nimport os; os.remove("x")\nEOF'
  _must - 'echo code, no interpreter'       "echo 'os.remove(x)' > notes.md"
  _must - 'command -v unlink (lookup)'      'command -v unlink'
  _must - 'which shred'                     'which shred'
  _must - 'man truncate'                    'man truncate'
  _must - 'zsh no word-split of $x'         'x="git clean -fd"; $x'
  _must - 'zsh ${(f)...} flags'             'for l in ${(f)"$(git status)"}; do echo $l; done'
  _must - 'docker ps'                       'docker ps -a'
  _must - 'docker compose down (no -v)'     'docker compose down'
  _must - 'brew install'                    'brew install jq'
  _must - 'pnpm install'                    'pnpm install'
  _must - 'bash script.sh'                  'bash ./install.sh --check'
  _must - 'sh -c harmless'                  "sh -c 'ls -la'"
  _must - 'trash command'                   'trash notes.txt'
  _must - 'mv (not a deleter here)'         'command mv a b'
  _must - 'alias ll (harmless, fixture)'    'll -d /tmp'
  _must - 'self alias ls=ls -G'             'ls notes.txt'
  _must - 'alias that echoes the words'     'q'
  _must - 'git status alias'                'gs'
  _must - 'look-alike grh (soft reset)'     'grh'
  _must - 'look-alike gwip (wip commit)'    'gwip'
  _must - 'look-alike gpr'                  'gpr'
  _must - 'the names as data'               'echo grhh gwipe gpristine'
  _must - 'the name inside a git grep'      'git log --grep=gpristine'
  _must - 'quoted alias name is data'       "echo 'gclean'"
  _must - 'SAFE_RM_OFF in prose'            'echo "SAFE_RM_OFF=1 is for humans"'
  _must - 'array assignment holding words'  'arr=(git worktree remove x)'
  _must - 'git checkout - (previous branch)' 'git checkout -'
  _must - 'heredoc to a non-shell after sh'  $'sh ./x.sh; cat <<EOF\ngit clean -fdx\nEOF'
  _must - 'control: harmless'               'echo control-ok'
  _must - 'empty command'                   ''

  SNAP_DIR="$save_snap"; SNAP_DONE=0

  echo "=== HOOK arms: the real payload envelope through stdin ==="
  local env_json out rc t0 t1 ms big logf
  # A REAL PreToolUse payload, captured by the conductor on 2.1.280 with a
  # throwaway headless session whose hook tee'd its stdin. Only the username
  # in the two paths is replaced (the leak scanner refuses it).
  env_json='{"session_id":"8b72042b-ac79-44e8-8bbc-4c5382fde5fa","transcript_path":"/Users/example/.claude/projects/-Users-example-CODE-Scaffoldings-fifty-shades-of-dotfiles/8b72042b-ac79-44e8-8bbc-4c5382fde5fa.jsonl","cwd":"/Users/example/CODE/Scaffoldings/fifty-shades-of-dotfiles","prompt_id":"8905fe60-96c3-42ca-888b-28d51a8a7853","permission_mode":"auto","effort":{"level":"medium"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo capture-test-for-del-guard","description":"Echo a capture-test marker string"},"tool_use_id":"toolu_01KPKbNj9PaHgAYhx9dpiin1"}'
  logf="$fx/security.log"
  _hook() { # $1 = command string, $2 = snapshot dir (default: the fixture) -> sets out, rc
    local p; p="$(printf '%s' "$env_json" | jq -c --arg c "$1" --arg cwd "$fx/repo" '.tool_input.command = $c | .cwd = $cwd')"
    out="$(printf '%s' "$p" | DEL_GUARD_LOG="$logf" DEL_GUARD_SNAPSHOT_DIR="${2:-$fx/snap}" "$self" 2>&1)"; rc=$?
  }
  _chk() { # $1 = label, $2 = condition result (0 ok)
    if [ "$2" -eq 0 ]; then passes=$((passes + 1)); printf 'ok    %-26s %s\n' hook "$1"
    else fails=$((fails + 1)); printf 'FAIL  %-26s %s\n' hook "$1"; fi
  }
  _hook 'echo capture-test-for-del-guard'
  [ "$rc" -eq 0 ] && [ -z "$out" ]; _chk 'real payload, harmless: exit 0, no output' $?
  _hook 'git worktree remove ../wt'
  [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = deny ]; _chk 'real payload, deny: JSON deny, exit 0' $?
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | grep -q 'git worktree prune'; _chk 'deny names the safe route' $?
  printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null | grep -qx PreToolUse; _chk 'deny carries hookEventName' $?
  grep -q "BLOCKED $HOOK_NAME \"git-worktree-remove\"" "$logf" 2>/dev/null; _chk 'denial logged in the sibling shape' $?
  # the fake token is assembled at run time so this file never holds one
  local tk="gh""p_""abcdefghijklmnopqrstuvwxyz0123456789"
  _hook "GH_TOKEN=$tk /bin/rm x"
  ! grep -q "${tk:0:14}" "$logf" 2>/dev/null && grep -q '\[redacted\]' "$logf" 2>/dev/null; _chk 'no token reaches the log' $?
  out="$(printf 'this is {not json' | DEL_GUARD_LOG="$logf" "$self" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]; _chk 'malformed JSON: exit 0, no decision' $?
  out="$(printf '' | DEL_GUARD_LOG="$logf" "$self" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]; _chk 'empty stdin: exit 0, no decision' $?
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":""}}' | DEL_GUARD_LOG="$logf" "$self" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]; _chk 'empty command: exit 0, no decision' $?
  out="$(printf '%s' '{"tool_name":"Bash"}' | DEL_GUARD_LOG="$logf" "$self" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]; _chk 'no tool_input: exit 0, no decision' $?
  # timing: 5 KB of dense ordinary work (about 330 simple commands, the worst
  # case for this design), end to end through the hook, against the REAL
  # snapshot when this machine has one (its alias table is read every run).
  # Best of three, timed by bash's own clock around the hook process alone:
  # the payload is built before the clock starts. Other sessions share this
  # machine, so one slow run is load, three slow runs are the hook.
  local tsnap="$save_snap" tlabel="real snapshot" best p1 p2 i secs
  set +f; ls "$tsnap"/snapshot-*.sh >/dev/null 2>&1 || { tsnap="$fx/snap"; tlabel="fixture snapshot"; }; set -f
  _time3() { # $1 = command -> sets best (ms) and rc/out of the last run
    local pl; pl="$(printf '%s' "$env_json" | jq -c --arg c "$1" --arg cwd "$fx/repo" '.tool_input.command = $c | .cwd = $cwd')"
    best=999999
    for i in 1 2 3; do
      secs="$( { TIMEFORMAT=%R; time out="$(printf '%s' "$pl" | DEL_GUARD_LOG="$logf" DEL_GUARD_SNAPSHOT_DIR="$tsnap" "$self" 2>&1)"; } 2>&1 )"
      ms=$(( 10#${secs%.*} * 1000 + 10#${secs#*.} ))
      [ "$ms" -lt "$best" ] && best=$ms
    done
    out="$(printf '%s' "$pl" | DEL_GUARD_LOG="$logf" DEL_GUARD_SNAPSHOT_DIR="$tsnap" "$self" 2>&1)"; rc=$?
  }
  big=""; while [ ${#big} -lt 5120 ]; do big="${big}git status && rg -n 'foo bar' src/ | head -5; echo \"done \$(date)\" >> out.log; "; done
  _time3 "$big"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$best" -lt 100 ]; _chk "5 KB dense command, $tlabel: best of 3 ${best} ms (< 100), allowed" $?
  _time3 "${big}git clean -fdx"
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = deny ] && [ "$best" -lt 100 ]; _chk "same 5 KB with a deny at the end: ${best} ms, denied" $?
  hd=$'git commit -F - <<\'EOF\'\n'; while [ ${#hd} -lt 5120 ]; do hd="${hd}prose that mentions git clean -fdx and /bin/rm -P and find . -delete"$'\n'; done; hd="${hd}EOF"
  _time3 "$hd"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$best" -lt 100 ]; _chk "5 KB heredoc commit message: ${best} ms (< 100), allowed" $?

  echo "=== SHIFT arms: a value flag given LAST must not stall the guard (W-20260923-A54) ==="
  # Found 2026-09-23: in bash a shift of 2 with one word left FAILS and shifts
  # nothing, so `while [ $# -gt 0 ]` spun forever, the harness killed the hook
  # at 5 s, and the command ran unchecked. Each arm runs the real hook under a
  # alarm (so an old copy that spins is a FAIL here, not a hung selftest) and
  # times that one run; a verdict must arrive within 1 s.
  local hb_ms hb_d hb_r f
  _hookb() { # $1 = command, $2 = DEL_GUARD_NOFILTER value, $3 = alarm s (default 2), then VAR=value env -> out, rc, hb_ms, hb_d, hb_r
    local pl s al="${3:-2}" nf="${2:-0}"; pl="$(printf '%s' "$env_json" | jq -c --arg c "$1" --arg cwd "$fx/repo" '.tool_input.command = $c | .cwd = $cwd')"
    shift 3 || set --
    # time's report goes to a fixture file so `out` and `rc` stay in this shell
    { TIMEFORMAT=%R; time { out="$(printf '%s' "$pl" | env DEL_GUARD_LOG="$logf" DEL_GUARD_SNAPSHOT_DIR="$fx/snap" DEL_GUARD_NOFILTER="${nf:-0}" "$@" perl -e 'alarm shift; exec @ARGV' "$al" "$self" 2>&1)"; rc=$?; }; } 2> "$fx/time.txt"
    s="$(tail -n 1 "$fx/time.txt")"; hb_ms=$(( 10#${s%.*} * 1000 + 10#${s#*.} ))
    hb_d="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
    hb_r="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  }
  # every wrapper flag that takes a value, given last; sudo/doas/env/git/uv
  # cover their option loops, the interpreters cover _interp_cmd, bash/zsh
  # cover _shell_cmd
  for f in 'time -o' 'nice -n' 'exec -a' 'echo x | xargs -n' 'echo x | xargs -I' 'echo x | gxargs --max-args' \
           'sudo -u' 'doas -u' 'env -u' 'env -C' 'env -S' 'env --split-string' 'timeout -s' 'gtimeout -k' \
           'caffeinate -t' 'stdbuf -o' 'watch -n' 'git -C' 'git -c' 'git --git-dir' \
           'python3 -W' 'python3 -X' 'node -r' 'node --require' 'perl -e' 'perl -ne' 'ruby -E' \
           'bash -o' 'zsh +o' 'sh -O' 'uv --project' 'uv -p' 'uv run --with' 'uv run -p' 'uv run --env-file'; do
    _hookb "$f; unlink f" 0
    [ "$hb_d" = deny ] && [[ $hb_r == *'(unlink)'* ]] && [ "$hb_ms" -lt 1000 ]; _chk "'$f; unlink f': denied as unlink in ${hb_ms} ms (< 1000)" $?
    _hookb "$f; unlink f" 1
    [ "$hb_d" = deny ] && [[ $hb_r == *'(unlink)'* ]] && [ "$hb_ms" -lt 1000 ]; _chk "same, prefilter off: ${hb_ms} ms, denied" $?
    _hookb "$f" 0
    [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$hb_ms" -lt 1000 ]; _chk "'$f' alone: allowed in ${hb_ms} ms (< 1000)" $?
  done
  # The class, not only the instances above: no shift of 2 or more in this
  # file may run unguarded. The positive arm (the guarded form IS found)
  # proves the scan read the file; a zero from a scan that read nothing is
  # not a pass.
  local sg su
  sg="$(awk '/shift [2-9] \|\| set --/ {n++} END {print n+0}' "$self")"
  su="$(awk '/shift [2-9]/ && !/shift [2-9] \|\| set --/ {n++} END {print n+0}' "$self")"
  [ "$sg" -ge 20 ] && [ "$su" -eq 0 ]; _chk "lint: $sg guarded multi-shifts (>= 20, the control), $su unguarded (must be 0)" $?

  # The fixture dir is left in $TMPDIR on purpose: deleting it would go to the
  # Trash (or fail inside the sandbox), and the OS clears $TMPDIR.
  echo
  echo "del-guard selftest: $passes passed, $fails failed (fixtures: $fx)"
  [ "$fails" -eq 0 ]
}

# ---------------------------------------------------------------- mutants
# Copies this file, deletes ONE line tagged `#M:`, runs the copy's selftest, and
# expects it to FAIL. A tagged line whose removal still passes is a rule no arm
# proves, which is the finding this mode exists to surface.
_mutants() {
  local self="$0" tmp n=0 caught=0 missed=0 broken=0 line tag ln mk only="${1:-}"
  mk='#''M: '              # built, so no line in this function carries the marker itself
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/del-guard-mutants.XXXXXX")" || return 1
  while IFS= read -r line; do
    ln="${line%%:*}"; tag="${line##*"$mk"}"
    [ -n "$only" ] && [[ $tag != *"$only"* ]] && continue
    n=$((n + 1))
    awk -v L="$ln" 'NR != L' "$self" > "$tmp/m.sh"; chmod +x "$tmp/m.sh"
    # a mutant that no longer PARSES proves nothing about the rule: say so
    if ! /bin/bash -n "$tmp/m.sh" 2>/dev/null; then
      broken=$((broken + 1)); printf 'BROKEN  line %-4s %s (syntax error, not a rule test)\n' "$ln" "$tag"; continue
    fi
    # a mutant whose LEXER no longer runs fails every deny arm for a reason
    # that has nothing to do with the rule removed
    if "$tmp/m.sh" --classify 'git clean -fdx' / 2>/dev/null | grep -q 'LEXER FAILED'; then
      broken=$((broken + 1)); printf 'BROKEN  line %-4s %s (lexer fails, not a rule test)\n' "$ln" "$tag"; continue
    fi
    # a removed line can loop forever; 300 s is five times a normal selftest
    if perl -e 'alarm shift; exec @ARGV' 300 "$tmp/m.sh" --selftest >/dev/null 2>&1; then
      missed=$((missed + 1)); printf 'MISSED  line %-4s %s\n' "$ln" "$tag"
    else
      caught=$((caught + 1)); printf 'caught  line %-4s %s\n' "$ln" "$tag"
    fi
  done < <(grep -n "$mk" "$self" | grep -v '^[0-9]*:#')
  echo "del-guard mutants: $caught caught, $missed missed, $broken broken, of $n"
  [ "$missed" -eq 0 ] && [ "$broken" -eq 0 ]
}

case "${1:-}" in
  --selftest) _selftest; exit $? ;;
  --mutants)  _mutants "${2:-}"; exit $? ;;   # optional: only tags containing this text
  --help|-h)
    sed -n '2,55p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  --classify) # debugging aid: prints the rule id and where, or "allow"
    _classify "${2:-}" "${3:-$PWD}"
    [ "${LEXER_FAILED:-0}" -eq 1 ] && echo "LEXER FAILED"
    echo "${REASON_ID:-allow}${REASON_WHERE:+ ($REASON_WHERE)}"; exit 0 ;;
esac

# ---------------------------------------------------------------- hook path
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"THE DELETION GUARD IS BROKEN: jq is not on PATH, so enforce-no-permanent-delete.sh cannot read the command. Nothing is being checked for permanent deletes. Install jq. Until then: bare rm only, and ask Gavin before any git clean / worktree remove / reset --hard."}}'
  exit 0
fi

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0
cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)"

_classify "$cmd" "$cwd"

if [ -z "$REASON_ID" ]; then
  if [ "${LEXER_FAILED:-0}" -eq 1 ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"The deletion guard (enforce-no-permanent-delete.sh) could not parse this command, so it was NOT checked for permanent deletes. Run its --selftest."}}'
  fi
  exit 0
fi

_log "$REASON_ID" "$cmd"
jq -n --arg r "$REASON" --arg w "$REASON_WHERE" --arg f "$FOOTER" --arg id "$REASON_ID" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: ("BLOCKED (" + $id + "): this command deletes or destroys data outside the Trash.\n\n" + (if $w != "" then "Found: " + $w + "\n" else "" end) + $r + "\n\n" + $f)}}'
exit 0
