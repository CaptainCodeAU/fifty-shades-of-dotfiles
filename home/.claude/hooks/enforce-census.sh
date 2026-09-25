#!/bin/bash
# Fire at the MOMENT a grep is about to COUNT or LIST, and point the session at the census
# tool. A plain locate stays quiet (D-20260925-A02; the second gate below). Runs on
# PreToolUse for Bash. Sibling of enforce-uv / enforce-pnpm / enforce-gh-ssh-only:
# it never blocks, never edits the command, and always exits 0.
#
# WHY IT EXISTS — measured, not felt
#   A grep is a lower bound wearing a fact's clothes. In one working sitting, five ad-hoc
#   greps returned wrong answers while every purpose-built tool in the tree was right every
#   time. All five were one shape: A NEGATIVE OR A COUNT TAKEN FROM AN UNPROVEN INSTRUMENT.
#     · `\|` is BRE alternation. Under -E it matches a literal backslash-pipe, so a
#       three-way search silently became a search for nonsense. It returned 0.
#     · a dropped -i, against text reading "Patient-less". It returned 0.
#     · an unquoted shell variable holding nine paths, which grep read as ONE filename.
#       It returned 0 — and "no retired names anywhere" was one sentence from being stated.
#     · a pattern that exceeded the regex engine's complexity limit and errored, while the
#       string being searched for was present the whole time.
#     · a `head -12` that truncated away the very control row that would have caught it.
#
#   The tool alone is not the fix. In the same sitting that built it, grep was reached for
#   again within the hour — a note in a file did not fire. This does, at the only moment it
#   is useful.
#
# 🔴 WHY IT SHOUTS INSTEAD OF GOING QUIET
#   A retired sibling hook opened with `[ -f "$TOOL" ] || exit 0`. Had its tool ever gone
#   missing it would have produced SILENCE, not an error, and a session would have read the
#   silence as health. A missing instrument must never be indistinguishable from a clean
#   bill. So: tool present -> remind. Tool absent -> say so, loudly, every time.
#
# The tool is machine-global and stow-symlinked from the dotfiles repo, so there is exactly
# one copy on this box and nothing to keep in sync per project.

set -uo pipefail

TOOL="$HOME/.claude/tools/census.py"

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# jq is this hook's SECOND instrument, and it used to fail the way the header above
# condemns. `command -v jq || exit 0` is byte-for-byte the retired sibling's mistake:
# lose jq and the reminder stops in every project, forever, with no signal — silence
# read as a clean bill of health. The hook shouted about a missing census.py one screen
# below while doing exactly the wrong thing for jq one line up.
#
# Shout instead, for the same reason and in the same words. The message is emitted by
# hand here because building it needs the very tool that is missing.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE CENSUS REMINDER IS BROKEN: jq is not on PATH, so this hook cannot read the tool payload. It has been SILENT for every search in every project until now, and silence here is not a clean bill of health — it is a missing instrument. Install jq (brew install jq), then corroborate any count you already took. Do not treat a recent zero as evidence of absence."
  exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

# THE SHIFTED CONTROL (W-20260924-A48 item 6; Gavin 2026-09-25, option A of D-20260925-A02).
# `census.py --control $CTL T1 T2` with CTL empty or unset: zsh drops the unquoted word, so
# T1 becomes the control, T2 the only pattern, and census answers exit 0 with the wrong
# control. census cannot see it: its argv is byte-identical to a legitimate call (censusb
# REPORT.md, measured). The TYPED text still shows it, and this hook reads the typed text.
# "$CTL" quoted is safe: an empty value arrives as an empty control, which census refuses;
# so is --control=$CTL, which arrives as `--control=`. Only the bare space form is warned.
_ctlvar='(^|[[:space:]])--control[[:space:]]+\$(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*)'
case "$cmd" in
  *census*)
    if [[ "$cmd" =~ $_ctlvar ]]; then
      _v="${BASH_REMATCH[2]}"
      _ctlnote="⚠️ census --control is followed by an UNQUOTED variable (\$$_v). When it is empty or unset, zsh drops the word, the next word silently becomes the control, and census answers exit 0 with a control you never chose. census cannot detect this; its arguments look exactly like a real call. Quote it, --control \"\$$_v\", so an empty value reaches census as an empty control, which it refuses."
      jq -n --arg ctx "$_ctlnote" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}, suppressOutput: true}'
      exit 0
    fi ;;
esac

# The BUILT-IN Grep tool carries no `.command`, so the old `[ -n "$cmd" ] || exit 0` dropped
# it on the floor. It is ripgrep underneath and inherits every trap: it skips hidden files
# and honours .gitignore by default, and it answers a miss with the bare words "No matches
# found" — no denominator, no statement of what it searched. That is the most confident
# nothing in the whole toolkit, and it was the one route this hook never covered.
# STATUS OF THIS BRANCH, so nobody re-litigates it. The built-in Grep tool does not
# exist in Claude Code sessions on this machine — measured 2026-09-04 in a default-mode
# session that listed its own toolset: 13 live tools, 36 deferred, "Neither Grep nor Glob
# is in that list", with `Grep` and `Glob` sitting in permissions.allow the whole time.
# It is absent from the build, not permission-gated, so NO flag restores it.
#
# The branch is therefore correct but unexercised, and was proven by mechanism instead:
#   1. a settings.json matcher for a NON-Bash tool does route real calls to a hook —
#      a throwaway repo with a `Read` matcher logged "FIRED for tool_name=Read" from a
#      genuine Read tool call, with the right tool_name in the payload
#   2. this hook, fed {"tool_name":"Grep"}, fires with the right wording (truth table)
#   3. the Grep matcher entry is present and schema-valid in ~/.claude/settings.json
# Every link tested; only the tool itself is missing. If it ever appears, this fires.
#
# SUBAGENTS ARE COVERED — measured 2026-09-04, not assumed. A session was told to
# delegate a search; the Explore subagent it spawned ran `grep -rn`, and this hook
# fired FOUR times inside that subagent's own context. It went on to run
# `census.py --help` and two real census invocations, so the --help pointer reaches
# delegated work too. Subagent transcripts live one directory deeper than the
# session's, under `<session-id>/subagents/`; a glob that misses that level finds no
# search commands at all and reads exactly like proof of a gap.
#
# D-20260925-A02 narrowed it: the Grep tool's DEFAULT output_mode is files_with_matches, a
# LIST, and `count` is a COUNT, so both fire. `content` only locates lines, so it is quiet.
if [ "$tool_name" = "Grep" ]; then
  _gmode="$(printf '%s' "$payload" | jq -r '.tool_input.output_mode // "files_with_matches"' 2>/dev/null || true)"
  [ "$_gmode" = "content" ] && exit 0
  _search=1
  _trigger="output_mode $_gmode"
  _tool="Grep-tool search"
  _why="The Grep tool does none of that either: it skips hidden files and honours .gitignore
by default, and answers a miss with the bare words \"No matches found\" — no denominator, no
statement of what was actually searched."
fi
[ -n "$cmd" ] || [ "${_search:-0}" -eq 1 ] || exit 0

# Only fire on an actual search. `git grep` counts — same dialect, same case traps.
#
# `rg` was MISSED for as long as this hook has existed, because the substring test below
# looks for the letters "grep" and `rg` does not contain them. Measured 2026-09-04: a bare
# `rg -c safe-rm README.md` produced no reminder at all, while `grep` produced one every
# time. That is the wrong way round — ripgrep is the MORE trap-prone of the two here, since
# it skips dotfiles unless `--hidden` is passed, so an empty `rg` in a dotfiles repo is not
# a not-found. The reminder was firing on the safer tool and staying silent on the sharper one.
#
# `rg` needs a WORD BOUNDARY; a substring test would fire on merge, large, target, org,
# argv and rgb. A reminder that fires on `git merge` is a reminder that gets ignored on
# `rg`. Word characters here exclude `/` and `|` on purpose, so `/usr/bin/rg` and `… | rg`
# both fire, while `rg.py` and `rgb` do not.
# ripgrep is tested FIRST: "ripgrep" contains "grep", so the substring test would claim it
# and the notice would open "a grep is about to run" over an rg. Name the tool that actually
# ran — a notice that looks like a misfire stops being read.
#
# A word boundary alone was still too loose. `rg` is two letters, so it turns up inside
# ordinary English the moment a command carries any: measured false fires on
# `echo "the large rg thing"` and `cat CHANGELOG.md # mentions rg`. Firing on prose is
# how a reminder becomes wallpaper.
#
# So `rg` must appear in COMMAND POSITION — at the start, or straight after something
# that starts a new command: a pipe, a semicolon, && or ||, a subshell, a backtick, or a
# runner such as xargs/time/sudo/command/env/exec. An optional /path/to/ prefix is
# allowed so /usr/bin/rg still fires. Quotes and comments are stripped first, so the
# word cannot reach the test from inside a string or after a `#` at all.
#
# `find ... -exec grep ... \;` WAS ANOTHER MISS OF THE SAME SHAPE. `-exec`/`-execdir`
# are find(1) flags, not shell runner words, so they were not in the runner list, and
# the leading `-` meant they could never match a bare word there anyway. Measured
# 2026-09-10: `find /tmp -name "*.txt" -exec grep -l "foo" {} \;` produced no reminder
# at all, while the piped equivalent (`find ... | xargs grep ...`) fired correctly.
# Adding `-exec`/`-execdir` as runner words closes it for both `rg` and `grep`.
#
# THE SINGLE-QUOTE STRIPPER WAS DEAD CODE. `${cmd//\'*\'/ }` returned the string
# untouched — measured 2026-09-04 by printing _bare at each stage: `echo 'rg here' and
# "rg there" # and rg comment` came out of that line byte-identical, and only the sed
# below ever removed anything. The escaping never produced the pattern it reads as.
# `rg` survived the defect because the command-position anchor rejects a word that
# merely follows a quote character; `grep` would NOT have, the moment it was handed the
# same _bare — `echo 'ls | grep foo'` carries `| grep` in command position inside the
# string. So the stripper had to actually work before grep could use it. Both span
# kinds are now removed by one sed, and a case asserts the single-quoted one.
#
# A HEREDOC BODY IS DATA, NOT COMMANDS, and it was being read as commands. Once a
# NEWLINE was added to the command-position set, every line of a heredoc became a
# command start — so any line of prose beginning with the letters `rg ` fired the
# reminder. Measured 2026-09-04, and not by looking for it: the commit that fixed the
# grep branch was written with `git commit -F - <<EOF`, its body contained a line
# starting "rg survived that because…", and the hook fired "A ripgrep is about to run"
# over a commit. That is the most common multi-line command in this repo by a wide
# margin, which makes it the most expensive possible place to be wrong.
#
# So heredoc bodies are dropped before anything else looks at the text. The introducer
# LINE is kept, because a real search can live on it (`grep foo <<EOF`). `<<<` here-
# strings and `$((1<<3))` arithmetic are left alone — the tag must start with a letter
# or underscore, and neither of those does. `<<-` and an indented terminator are
# handled. Same accepted trade as the quoted-argument case above: a search written
# INSIDE a heredoc (`bash <<EOF` … `grep foo` … `EOF`) is now missed. Prose in a commit
# message outnumbers that by orders of magnitude.
_hd='BEGIN{inhd=0}
inhd==0{
  if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
    tag=substr($0,RSTART,RLENGTH); sub(/^<<-?[ \t]*/,"",tag); gsub(/["\047]/,"",tag)
    inhd=1; hd=tag
  }
  print; next
}
{ t=$0; sub(/^[ \t]+/,"",t); if (t==hd) { inhd=0; hd="" } ; next }'
_strip() { sed -e "s/'[^']*'/ /g" -e 's/"[^"]*"/ /g' -e 's/#.*$//'; }
_nohd="$(printf '%s' "$cmd" | awk "$_hd")"
_bare="$(printf '%s' "$_nohd" | _strip)"

# THE ONE QUOTED STRING THAT IS READ AS COMMANDS: the script handed to a shell's `-c`.
# D-20260925-A02 made the reminder depend on a count flag, and `bash -c 'rg -c foo'` then
# asked two questions at once. The `-c` there is BASH's flag, never rg's, so it must not
# count; and the rg inside the string is a real search, so its own `-c` should. Stripping the
# whole span (above) answered neither. So the script of `bash|sh|zsh|dash|ksh -c '...'` in
# command position is lifted out and scanned as extra lines, after the same stripping.
# `bash -c "echo grep"` (s06) stays quiet: its grep is not in command position there either.
# A script with a quote of the other kind nested inside is cut at that quote; a miss.
_shc='(^|[|;&(`'$'\n''[:space:]])([A-Za-z0-9_./-]*/)?(bash|sh|zsh|dash|ksh)[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+('"'"'([^'"'"']*)'"'"'|"([^"]*)")'
_rest="$_nohd"
_inner=""
while [[ "$_rest" =~ $_shc ]]; do
  _inner="$_inner"$'\n'"${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
  _rest="${_rest#*"${BASH_REMATCH[0]}"}"
done
if [ -n "$_inner" ]; then
  _bare="$_bare"$'\n'"$(printf '%s' "$_inner" | _strip)"
fi
# A NEWLINE starts a command too, and leaving it out of the set below made the whole
# reminder dead for multi-line commands — which is nearly all of them. Measured
# 2026-09-04: `rg` on line 3 of a three-line command was SILENT while `grep` on line 3
# fired, because the grep test is a plain substring and this one is anchored. Bash `=~`
# has no multiline flag, so `^` means start-of-string, not start-of-line; the newline
# has to be spliced into the character class by hand.
_NL=$'\n'
_cmdpos='(^|[|;&(`'"$_NL"']|&&|\|\||\$\(|(^|[[:space:]])(xargs|time|sudo|command|env|exec|nohup|-exec|-execdir)[[:space:]]+)[[:space:]]*([A-Za-z0-9_./-]*/)?(rg|ripgrep)([[:space:]]|$)'

# `grep` GOT NONE OF THAT GUARD, and it was the noisier half of the traffic. Its test was
# `case "$cmd" in *grep*)` — the RAW command, a bare substring, no command position, no
# word boundary, no quote or comment stripping. Reported by another project's agent, who
# had it fire twice in one session on a `mkdir`. Re-measured here 2026-09-04 against the
# unfixed hook: SIX false fires, and not one search among them.
#   echo "the word telegrep as prose only"    grep inside a double-quoted string
#   echo 'ls | grep foo'                      grep inside a single-quoted string
#   cat CHANGELOG.md # mentions grep          grep after a comment marker
#   mkdir grep-vs-census-decision             grep inside a directory NAME
#   touch notes-about-grep.md                 grep inside a FILENAME
#   bash -c "echo grep"                       grep inside a quoted -c argument
# The guard three screens up was written for `rg` and never applied to the tool sitting
# beside it. "Firing on prose is how a reminder becomes wallpaper" is this hook's own
# sentence, written while the other branch did exactly that on every command that
# happened to carry the letters.
#
# The family is spelled `[A-Za-z]*grep`, so egrep/fgrep/rgrep/zgrep/ugrep/pcregrep/bzgrep
# all fire; `git` joins the runner list so `git grep` still does. The matched binary names
# itself in the notice — a notice that calls a ugrep "a grep" is a notice that looks like
# a misfire, and one of those stops being read.
#
# KNOWN AND DELIBERATE: a search hidden inside a quoted argument — `watch "grep -c foo ."` —
# is silent. (A shell's `-c` script is the one exception, lifted out above since
# D-20260925-A02, so `bash -c "grep -c foo ."` is seen.) Deleting the span is what kills
# the five prose cases; merely blanking the quote characters instead brings the
# single-quoted false fire straight back (measured both ways). A miss on a wrapped search
# is the cheaper error of the two, and it is the trade `rg` has been making all along.
_greppos='(^|[|;&(`'"$_NL"']|&&|\|\||\$\(|(^|[[:space:]])(xargs|time|sudo|command|env|exec|nohup|git|-exec|-execdir)[[:space:]]+)[[:space:]]*([A-Za-z0-9_./-]*/)?([A-Za-z]*grep)([[:space:]]|$)'

_search="${_search:-0}"
_tool="${_tool:-search}"
if [ "$_search" -eq 1 ]; then
  :                                      # already settled by the Grep-tool branch above
elif [[ "$_bare" =~ $_cmdpos ]]; then
  _search=1
  _tool="ripgrep"
elif [[ "$_bare" =~ $_greppos ]]; then
  _search=1
  _tool="${BASH_REMATCH[5]:-grep}"
fi
[ "$_search" -eq 1 ] || exit 0

# ── SECOND GATE: does the search COUNT or LIST? (D-20260925-A02, option D of W-20260924-A48)
# The reminder fired on every rg and grep, including the ones that only LOCATE a line to
# read (`rg -n foo file`). A48 measured it firing on every search in two sessions; a notice
# that fires on every locate is wallpaper by the time a count arrives. What census corrects
# is a NUMBER or a LIST read as complete, so that is when it fires:
#   -c --count --count-matches -l --files-with-matches -L(grep, git grep) --files-without-match
#   --stats --name-only(git grep) --files(rg)  or the search piped into `wc`
#   -q --quiet --silent: a yes/no test. Its "no" is an absence claim, the answer census
#     exists for, and `grep -q foo || echo absent` is exactly the unproven zero. So it fires.
# Quiet: a plain locate, `-o` without a count, and every non-search command.
#
# Measured traps this gate is written around:
#   · rg `-L` is --follow (symlinks), NOT files-without-match as in grep and git grep.
#   · a short flag that takes a value swallows the rest of its cluster or the next word:
#     `rg -e -c` searches for the pattern "-c"; `rg -g*.c` is a glob. So each family has
#     its list of value-taking letters, and a value is never read as a flag.
#   · `--` ends the options; `rg -- -c` searches for "-c".
#   · a flag belongs to ITS command: `ls -c ; rg foo` and `bash -c '...'` are not counts.
# `rg --files` lists every file and fires; `fd` never reaches this gate, because the first
# gate only knows grep and rg. They share the dotfile blind spot, but fd is not a search
# and is outside the ruling (brief D). That is a scope line, not an oversight.
#
# Command separators become newlines and pipes stay pipes, so each line is one pipeline.
# Redirections carrying `&` (2>&1, >&2, &>) are dropped first so they do not split a command.
_countflag() {
  local fam="$1" cl vl t rest ch
  shift
  case "$fam" in
    rg)  cl="clq";  vl="ABCEefgjMmrTtd" ;;
    git) cl="clLq"; vl="ABCefm" ;;
    *)   cl="clLq"; vl="ABCDdefm" ;;
  esac
  while [ $# -gt 0 ]; do
    t="$1"; shift
    case "$t" in
      --) return 1 ;;
      --count|--count-matches|--files-with-matches|--files-without-match|--stats|--quiet|--silent)
        printf '%s' "$t"; return 0 ;;
      --name-only) [ "$fam" = git ] && { printf '%s' "$t"; return 0; } ;;
      --files) [ "$fam" = rg ] && { printf '%s' "$t"; return 0; } ;;
      --regexp|--file|--glob|--iglob|--type|--type-not|--replace|--max-count|--after-context|--before-context|--context)
        [ $# -gt 0 ] && shift ;;
      --*) ;;
      -?*)
        rest="${t#-}"
        while [ -n "$rest" ]; do
          ch="${rest:0:1}"; rest="${rest:1}"
          case "$cl" in *"$ch"*) printf '%s' "$t"; return 0 ;; esac
          case "$vl" in *"$ch"*) [ -z "$rest" ] && [ $# -gt 0 ] && shift; break ;; esac
        done ;;
    esac
  done
  return 1
}
_isrunner() {
  case "$1" in xargs|time|sudo|command|env|exec|nohup|-exec|-execdir) return 0 ;; esac
  return 1
}
_trigger="${_trigger:-}"
if [ -z "$_trigger" ]; then
  _norm="$(printf '%s' "$_bare" | sed -E -e 's/[0-9]*[<>]&[0-9-]*//g' -e 's/&>>?//g' -e 's/\|&/|/g')"
  _norm="${_norm//&&/$_NL}"
  _norm="${_norm//||/$_NL}"
  for _sep in ';' '&' '(' ')' '`' '{' '}'; do
    _norm="${_norm//"$_sep"/$_NL}"
  done
  while IFS= read -r _line; do
    [ -n "$_trigger" ] && break
    IFS='|' read -ra _cmds <<< "$_line"
    _insearch=0
    # `${a[@]+"${a[@]}"}`: macOS /bin/bash is 3.2, where an EMPTY array under `set -u` is
    # "unbound" and kills the hook. Measured on the first probe of this gate: the blank line
    # left by `bash -c '...'` crashed it, and a crashed hook prints nothing, which is silence.
    for _c in ${_cmds[@]+"${_cmds[@]}"}; do
      read -ra _w <<< "$_c"
      [ "${#_w[@]}" -gt 0 ] || continue
      # A later stage of the same pipeline that is `wc` counts the search's output.
      _j=0
      while [ "$_j" -lt "${#_w[@]}" ] && _isrunner "${_w[$_j]}"; do _j=$((_j + 1)); done
      if [ "$_insearch" -eq 1 ] && [ "$_j" -lt "${#_w[@]}" ] && [ "${_w[$_j]##*/}" = "wc" ]; then
        _trigger="| wc"; break
      fi
      # Find the search word in command position: first word, or straight after a runner,
      # or `grep` straight after `git`. Mirrors the first gate's _cmdpos/_greppos.
      _i=0; _prev=""; _fam=""
      while [ "$_i" -lt "${#_w[@]}" ]; do
        _t="${_w[$_i]##*/}"
        if [ "$_i" -eq 0 ] || _isrunner "$_prev" || [ "$_prev" = "git" ]; then
          case "$_t" in
            rg|ripgrep) _fam=rg ;;
            *grep) [[ "$_t" =~ ^[A-Za-z]*grep$ ]] && { [ "$_prev" = "git" ] && _fam=git || _fam=grep; } ;;
          esac
        fi
        [ -n "$_fam" ] && break
        _prev="$_t"; _i=$((_i + 1))
      done
      [ -n "$_fam" ] || continue
      _insearch=1
      if _hit="$(_countflag "$_fam" "${_w[@]:$((_i + 1))}")"; then
        _trigger="$_hit"; break
      fi
    done
  done <<< "$_norm"
fi
[ -n "$_trigger" ] || exit 0

# Why THIS instrument cannot be trusted for a zero. Set by the Grep-tool branch; this is the
# shell-command wording.
if [ -z "${_why:-}" ]; then
  _why="Neither grep nor rg does any of that, and rg additionally SKIPS DOTFILES unless
--hidden is passed, so an empty rg is not a not-found."
fi

# Already corroborating? Say nothing. A reminder that fires when it is not needed is how a
# reminder gets ignored when it is. (Empty for the Grep tool, which carries no command and
# cannot invoke census itself.)
case "$cmd" in *census.py*) exit 0 ;; esac

# STAND DOWN where a project already carries its own census reminder. Some repos are governed
# by a standard that requires a project-level copy and byte-checks it; firing on top of that
# would state the same rule twice, and two copies of a rule go unnoticed and only drift.
# The project's own copy is the one that fires there; this one covers everywhere else.
#
# ⚠️ The fallback is the REPO ROOT, never $PWD. Measured while building this: a $PWD fallback
# made the stand-down leak — the hook was invoked from one project's directory while pointed
# at another, found that directory's copy, and went silent for a project that had none. A
# stand-down that fires in the wrong place is worse than no stand-down, because its failure
# mode is silence.
_root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$_root" ] || _root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$_root" ] && [ -f "$_root/.claude/hooks/grep-census-reminder.sh" ]; then
  exit 0
fi

if [ -f "$TOOL" ]; then
  # The second line is the only discovery path a first-time reader has. Measured
  # 2026-09-04: a fresh session solved a hidden-file case correctly using census, and
  # never once ran --help — it learned --include-ignored from census's own output at
  # the moment it mattered, and learned nothing about any other flag. One line here
  # costs nothing and names the door.
  # W-20260921-A03. UV_CACHE_DIR IS NOT OPTIONAL DECORATION, it is what makes this
  # line RUNNABLE where it is printed. uv's default cache is ~/.cache/uv, which
  # contains a `.git` entry, and the Claude Bash sandbox denies reads there:
  #
  #   error: Failed to initialize cache at `~/.cache/uv`
  #     cause: failed to open file `~/.cache/uv/sdists-v9/.git`: Operation not permitted
  #
  # So the hint this hook prints on every grep was a command that could not run in
  # the place it was being printed. Measured again on 2026-09-21: the first census
  # call of that session failed exactly this way. A hint that fails teaches you to
  # ignore the hint, which is the whole mechanism this hook exists to protect.
  #
  # ${TMPDIR:-/tmp} is inside the sandbox's writable set, and a cold cache costs a
  # few seconds once per session. Outside a sandbox the line is still correct.
  invocation="UV_CACHE_DIR=\${TMPDIR:-/tmp}/uvcache uv run python3 \$HOME/.claude/tools/census.py --control <a-token-you-KNOW-is-present> [--under PATH] PATTERN...
    \$HOME/.claude/tools/census.py --help   # every flag: hidden files, JSON, regex, case, scoping
    (UV_CACHE_DIR is what lets this run inside the Bash sandbox; uv's default cache is denied there)"
  missing=""
else
  invocation="(THE CENSUS TOOL IS MISSING FROM THIS MACHINE — see below)"
  missing="

🔴 \`$TOOL\` DOES NOT EXIST. This hook is deployed but its tool is not, so nothing here can
corroborate a grep right now. That is a broken install, not a clean bill of health: report it
rather than working around it. Fix: re-run stow from the dotfiles repo, which symlinks
home/.claude/tools/census.py into place."
fi

# The UNIT and the CASE lines are D-20260925-A02. A48 measured census answering 37 where every
# grep said 12 to 14 for the same word in the same file: census counts every OCCURRENCE and
# ignores case by default, while `-c` counts matching LINES, case-sensitively. Lined up, the
# two agreed exactly across 4,317 files. So a mismatch is usually the unit or the case, and
# the reminder has to say which number to compare with which. Ruled 2026-09-25: census keeps
# its case-insensitive default and prints the case-sensitive count beside it.
read -r -d '' NOTE <<EOF
⚠️ A $_tool is about to run. It COUNTS or LISTS ($_trigger). Before trusting a ZERO, a COUNT or a LIST from it, corroborate:

    $invocation

Census requires a control hit first, prints the denominator and how the population was drawn,
and never truncates. $_why
A zero from a search is not evidence of absence until a control has hit in the same breath.
Census counts OCCURRENCES, not lines: \`grep -c\` and \`rg -c\` count matching LINES, so a line
holding the word twice is 1 to them and 2 to census (\`rg --count-matches\` counts occurrences).
Census ignores case by default and prints the case-sensitive count beside it; compare that one
with a grep or rg, which match case exactly unless given -i.
Use the search to LOCATE; use census to CONCLUDE.$missing
EOF

jq -n --arg ctx "$NOTE" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}, suppressOutput: true}'
exit 0
