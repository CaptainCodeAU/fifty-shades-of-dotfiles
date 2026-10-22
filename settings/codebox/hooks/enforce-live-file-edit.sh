#!/bin/bash
# CODEBOX'S COPY (23 Oct 2026, Gavin, dotfiles-main Q50: 1), from makeitso's hooks/enforce-live-file-edit.sh at 38bf349; it shares nothing with that file. Changed: its logs are under ~/.local/state/codebox-hooks; the shell snapshots it reads, and the home it reads, are codebox's own ~/.claude; repair hints name this repo's settings/codebox/hooks (fifty-shades-of-dotfiles), placed by ./install.sh --profile codebox. The makeitso lines about ~/.claude_v2 stay and do nothing on codebox, which has no such folder. Its history before that: MAKEITSO'S OWN (14 Oct 2026, #1469, engage-main Q11 (v2): 1). Not a copy of anything.
# enforce-live-file-edit.sh -- DENY Claude's file tools (Edit, Write, MultiEdit, NotebookEdit) on
# makeitso's locked live files: the same list validate-bash.sh locks against shell commands, asked
# through the same function (pp_protected in conv-shscan.awk, CONV_MODE=protected), so the two
# locks can never disagree. Deny only. Runs on PreToolUse for those four tools.
#
# WHY IT EXISTS. The lock read shell commands only. Shown 14 Oct 2026 in a makeitso session in
# auto mode: `echo demo > ~/.claude_v2/hooks/x` was denied by the lock, while the Write tool on the
# same path was stopped only by Claude's own auto-mode check, a model's judgment, which bypass
# mode skips.
#
# THE PATH. Claude resolves file_path the way Node's path.resolve does: "~" is home, a relative
# path is taken from the session's folder, and "." and ".." are taken out as text. This hook does
# the same, then asks the disk: links are followed (a link to settings.json IS settings.json), and
# the letter case is the one on disk (this Mac's disk ignores case, so ~/.CLAUDE_V2/Settings.json
# is the locked file). A part that does not exist yet is kept as written.
#
# An unreadable payload (jq missing, invalid JSON) is DENIED when its raw text mentions a locked
# place (.claude_v2, .claude/, .gitconfig, CLAUDE.md), and passes otherwise; the scanner missing or
# failing is denied the same way (D-20260925-A03). `--selftest` proves every arm;
# HOOK_UNDER_TEST=<path> runs them on a copy.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
SHSCAN="${CONV_SHSCAN:-$HOOKS_DIR/conv-shscan.awk}"
LOCKED_WORDS_ERE='\.claude_v2|\.claude/|\.gitconfig|CLAUDE\.md'

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null ||
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "Protected live file: $2"
  exit 0
}

# lexical PATH: "." and ".." taken out, as text, like Node's path.resolve (PATH is absolute)
lexical() {
  local part out="" parts=()
  IFS=/ read -r -a parts <<< "$1"   # read, not a bare $1: a "*" in a name must not expand
  for part in "${parts[@]}"; do
    case $part in
      ""|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  printf '%s\n' "${out:-/}"
}

# physical PATH: links followed, the case as it is on disk; a missing tail kept as written
physical() {
  local p="$1" tail="" n=0 t d name real
  while [ "$n" -lt 40 ]; do
    if [ -L "$p" ]; then
      t="$(readlink "$p")"; n=$((n + 1))
      case $t in /*) ;; *) t="$(dirname "$p")/$t" ;; esac
      p="$(lexical "$t")"; continue
    fi
    if [ -d "$p" ]; then
      p="$(builtin cd "$p" 2>/dev/null && /bin/pwd -P)" || return 1
      break
    fi
    d="$(dirname "$p")"; name="$(basename "$p")"
    if [ -e "$p" ]; then
      # the name as the disk spells it (the folder part is fixed by /bin/pwd -P above)
      real="$(ls -a "$d" 2>/dev/null | grep -ixF -- "$name" | head -n 1)"
      [ -n "$real" ] && name="$real"
    fi
    tail="/$name$tail"; p="$d"
    [ "$p" = / ] && break
  done
  [ "$n" -ge 40 ] && return 1
  p="${p%/}"; printf '%s\n' "$p$tail"
}

judge() {
  local raw tool p cwd out rc verdict msg
  raw="$(cat)"
  [ -n "$raw" ] || exit 0
  if ! tool="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null)" ||
     ! p="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)" ||
     ! cwd="$(printf '%s' "$raw" | jq -r '.cwd // ""' 2>/dev/null)"; then
    [[ $raw =~ $LOCKED_WORDS_ERE ]] &&
      deny "Protected live file (D-20260929-A14): this file-tool call could not be read, and it mentions a locked place (~/.claude_v2, ~/.claude, ~/.gitconfig or a CLAUDE.md), so it is denied. Retry it; if it repeats, check that jq works." "unreadable call"
    exit 0
  fi
  case $tool in Edit|Write|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
  [ -n "$p" ] || exit 0
  case $p in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) p="${cwd:-$PWD}/$p" ;;
  esac
  p="$(lexical "$p")"
  p="$(physical "$p")" || deny "Protected live file (D-20260929-A14): the path $p could not be followed to a real file (a loop of links?), so it is denied." "$p"
  out="$(printf '%s' "$p" | CONV_MODE=protected CONV_HOW="the $tool tool" LC_ALL=C awk -f "$SHSCAN" 2>/dev/null)"; rc=$?
  verdict="${out%%$'\n'*}"; msg="${out#*$'\n'}"
  if [ "$rc" -ne 0 ] || { [ "$verdict" != ALLOW ] && [ "$verdict" != DENY ]; }; then
    [[ $p =~ $LOCKED_WORDS_ERE ]] &&
      deny "Protected live file (D-20260929-A14): its scanner conv-shscan.awk is missing or failed (rc=$rc), and this $tool call names a locked place ($p), so it is denied. Restore makeitso's hooks folder (~/CODE/CaptainCodeAU/v2/makeitso/hooks) and install it." "$p"
    exit 0
  fi
  [ "$verdict" = DENY ] && deny "$msg" "$p"
  exit 0
}

selftest() {
  local hook="${HOOK_UNDER_TEST:-$0}" F pass=0 fail=0 old=".claude"
  F="$(mktemp -d "${TMPDIR:-/tmp}/live-file-edit.XXXXXX")"
  F="$(builtin cd "$F" && /bin/pwd -P)"
  mkdir -p "$F/.claude_v2/hooks/makeitso" "$F/.claude_v2/projects/p/memory/WORK" "$F/$old/hooks" "$F/work/sub"
  : > "$F/.claude_v2/settings.json"; : > "$F/.claude_v2/CLAUDE.md"; : > "$F/.gitconfig"
  : > "$F/.claude_v2/hooks/makeitso/validate-bash.sh"; : > "$F/.claude_v2/projects/p/memory/MEMORY.md"
  ln -s "$F/.claude_v2/settings.json" "$F/work/link-to-settings"
  ln -s "$F/.claude_v2/hooks" "$F/work/link-to-hooks"
  ln -s "loop-b" "$F/work/loop-a"; ln -s "loop-a" "$F/work/loop-b"
  # arm WANT TOOL PATH [CWD] -- WANT is deny or allow
  arm() {
    local want="$1" tool="$2" path="$3" cwd="${4:-$F/work}" key=file_path got
    [ "$tool" = NotebookEdit ] && key=notebook_path
    got="$(jq -n --arg t "$tool" --arg k "$key" --arg p "$path" --arg c "$cwd" \
      '{tool_name: $t, tool_input: {($k): $p}, cwd: $c, session_id: "t"}' | HOME="$F" bash "$hook" 2>/dev/null |
      jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "  ok   $want  $tool $path"
    else fail=$((fail + 1)); echo "  FAIL wanted $want, got $got: $tool $path (cwd $cwd)"; fi
  }
  raw_arm() {
    local want="$1" text="$2" got
    got="$(printf '%s' "$text" | HOME="$F" bash "$hook" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
    got="${got:-allow}"
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "  ok   $want  raw: $text"
    else fail=$((fail + 1)); echo "  FAIL wanted $want, got $got: raw: $text"; fi
  }
  echo "enforce-live-file-edit.sh selftest: $hook"
  arm deny  Write        "$F/.claude_v2/settings.json"
  arm deny  Edit         "$F/.claude_v2/CLAUDE.md"
  arm deny  MultiEdit    "$F/.claude_v2/hooks/makeitso/validate-bash.sh"
  arm deny  Write        "$F/.claude_v2/hooks/new-folder/new.sh"
  arm deny  NotebookEdit "$F/.claude_v2/hooks/n.ipynb"
  arm deny  Write        "$F/.claude_v2/projects/p/memory/MEMORY.md"
  arm deny  Write        "$F/.gitconfig"
  arm deny  Write        "$F/$old/hooks/x.sh"
  arm deny  Write        "$F/$old/CLAUDE.md"
  arm deny  Write        "~/.claude_v2/settings.json"
  arm deny  Write        "../.claude_v2/settings.json"
  arm deny  Write        "$F/work/no-such-folder/../../.claude_v2/settings.json"
  arm deny  Write        "$F/work/./sub/../../.claude_v2/CLAUDE.md"
  arm deny  Write        "$F/work/link-to-settings"
  arm deny  Edit         "$F/work/link-to-hooks/makeitso/validate-bash.sh"
  arm deny  Write        "$F/work/link-to-hooks/brand-new.sh"
  arm deny  Write        "$F/work/loop-a"
  if [ -e "$F/.CLAUDE_V2/SETTINGS.JSON" ]; then   # only on a disk that ignores case, like this Mac's
    arm deny Write "$F/.CLAUDE_V2/Settings.JSON"
    arm deny Write "$F/.Claude_V2/Hooks/new.sh"
  fi
  arm allow Write        "$F/work/notes.md"
  arm allow Edit         "$F/work/sub/a.txt"
  arm allow Write        "notes.md"
  arm allow Write        "$F/.claude_v2/projects/p/memory/WORK/item.md"
  arm allow Write        "$F/.claude_v2/projects/p/transcript.jsonl"
  arm allow Write        "$F/.claude_v2/settings.json.bak"
  arm allow Read         "$F/.claude_v2/settings.json"
  raw_arm deny  '{"tool_name":"Write","tool_input":{"file_path":"/x/.claude_v2/settings.json"'
  raw_arm allow '{"tool_name":"Write","tool_input":{"file_path":"/x/notes.md"'
  raw_arm allow ''
  # the scanner missing: a locked path is denied, any other passes
  local saved="${CONV_SHSCAN-}"; export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  arm deny  Write "$F/.claude_v2/settings.json"
  arm allow Write "$F/work/notes.md"
  if [ -n "$saved" ]; then export CONV_SHSCAN="$saved"; else unset CONV_SHSCAN; fi
  echo "enforce-live-file-edit.sh selftest: $pass passed, $fail failed"
  echo "  (fixtures left in $F; it is a temp folder)"
  [ "$fail" -eq 0 ]
}

if [ "${1-}" = --selftest ]; then selftest; exit $?; fi
judge
