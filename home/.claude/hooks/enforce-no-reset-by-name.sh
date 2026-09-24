#!/bin/bash
# enforce-no-reset-by-name.sh -- DENY a Bash command that removes a directory and
# then reuses the same path without checking the remove worked. Deny only.
# Runs on PreToolUse for Bash. Registered for BOTH targets (user and project) in
# settings/claude/hooks.json, because the rule is machine-wide: it belongs to the
# Deletion rules, like enforce-no-permanent-delete.sh.
#
# WHY IT EXISTS (W-20260924-A32, Stage 1, Gavin's ruling 2026-09-24: rm keeps
# failing loudly, no fallback; a hook blocks the pattern in every project).
# Agents write RESET-BY-NAME:
#     rm -rf "$S/mut4" 2>/dev/null; mkdir -p "$S/mut4"; cp ... "$S/mut4/"
# In the Claude sandbox the Trash-routed rm FAILS (rc 1, afpAccessDenied) and
# leaves the directory in place. 2>/dev/null hides that, `;` carries on, and
# the next step merges into STALE files: `mkdir -p` reuses it, `cp -f`, `tar`
# and `unzip` mix old and new silently, and `cp -i` prompts and can hang
# (2026-09-19, about 23 minutes). Measured in transcripts: about 120 distinct
# strings of this shape across the machine's projects.
#
# WHAT IT DENIES, WHAT IT ALLOWS: see "reset" in conv-shscan.awk, which holds
# the rule. In short: a recursive rm (or rmdir) of P, then a later mkdir, cd,
# cp/mv/ln/rsync destination, tar -C, unzip -d, git init, touch/tee or > into P,
# with no used check that P is gone in between. Allowed: an && chain from the rm
# (a failed rm stops it), a used test of P (`test ! -e P &&`, `[ -e P ] && exit`),
# `git clone ... P &&` or `git worktree add ... P &&` (both refuse a survivor),
# `|| exit` after the rm, a reassigned variable (D=$(mktemp -d ...)), set -e,
# and an rm of a path never reused. A single-file `rm -f f; cmd > f` is out of
# scope: overwriting a file cannot merge stale content.
#
# The scanning is conv-shscan.awk (CONV_MODE=reset) and the plumbing
# conv-hooklib.sh, both beside this file. If the scanner is missing the hook
# still denies a likely match, by name (same convention as enforce-uv.sh).
#
# `--selftest` proves every arm: DENY arms are real transcript commands
# (source file named on each; the username in their paths is replaced by "me"
# because the leak scan refuses it), ALLOW arms include the two safe routes the
# denial teaches. CONV_HOOK_UNDER_TEST=<path> runs the same arms on another copy.

CONV_TAG=enforce-no-reset-by-name
CONV_MODE_NAME=reset
CONV_LIB_DIR="$(dirname "$0")"
CONV_LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log"
CONV_FALLBACK_ERE='(^|[^A-Za-z0-9_./-])(rm[[:space:]]+-[A-Za-z]*[rR]|rmdir[[:space:]]).*(mkdir|cp|mv|tar|unzip|ln|git init)[[:space:]]'

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  # Not even the plumbing is here: deny a likely match by name, allow the rest.
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-no-reset-by-name: conv-hooklib.sh is missing beside the hook, so it cannot check this command; restow the dotfiles (home/.claude/hooks). Meanwhile use d=$(mktemp -d \"$TMPDIR/name.XXXXXX\") or rm -rf P && test ! -e P && mkdir -p P."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  conv_selftest_begin "$0"
  # Fixtures are read with `read -r -d ''` from quoted heredocs: bash 3.2
  # mis-parses a quoted heredoc inside $( ). read returns 1 at EOF; harmless.

  echo "=== DENY arms: real transcript commands (trimmed; source transcript named) ==="
  # fifty-shades-of-dotfiles/74089952 (THE incident, 2026-09-19, cp -i hung ~23 min)
  read -r -d '' F <<'EOF'
S=/private/tmp/claude-501/-Users-me-CODE-Scaffoldings-fifty-shades-of-dotfiles/74089952-e208-469d-b568-4e33fc9c94d4/scratchpad
R=/Users/me/CODE/Scaffoldings/fifty-shades-of-dotfiles
rm -rf "$S/mut4" 2>/dev/null; mkdir -p "$S/mut4"
cp "$R/home/.local/bin/vulnlib.py" "$R/home/.local/bin/vulnlib-selftest" "$S/mut4/"
chmod +x "$S/mut4/vulnlib-selftest"
EOF
  conv_arm deny "R1 incident: rm 2>/dev/null; mkdir -p; cp into it (74089952)" "$F"
  # fifty-shades-of-dotfiles/437f9ca1
  read -r -d '' F <<'EOF'
W="$TMPDIR/f5b-gitprobe"; rm -rf "$W" 2>/dev/null; mkdir -p "$W"
git -C "$W" init -q 2>&1 | peek 3
echo hello > "$W/a.txt"; git -C "$W" add a.txt
EOF
  conv_arm deny "R2 the commonest shape, \"\$W\" (437f9ca1)" "$F"
  # win-go-app-test worktree exp-w4-spine/511dfb58
  read -r -d '' F <<'EOF'
SC=$(cat /tmp/spine_scratch_path.txt); W=/Users/me/CODE/CaptainCodeAU/win_go_app_test/.worktree/record/exp-w4-spine; cd "$W"; rm -rf "$SC/p4-without" "$SC/p4-with"; mkdir -p "$SC/p4-without" "$SC/p4-with"; git archive phase4-hardening-2 | tar -x -C "$SC/p4-without"; git archive phase4-hardening-2 | tar -x -C "$SC/p4-with"; mkdir -p "$SC/p4-with/spine"; cp spine/*.md "$SC/p4-with/spine/"
EOF
  conv_arm deny "R3 two paths, then tar -x -C into them (511dfb58)" "$F"
  # cc-warehouse/5ffa4a01
  read -r -d '' F <<'EOF'
command rm -rf $SP/enum.git 2>/dev/null; git init -q --bare $SP/enum.git
git -C $SP/enum.git remote add origin https://github.com/CaptainCodeAU/cc-warehouse.git
EOF
  conv_arm deny "R4 command rm, then git init onto it (5ffa4a01)" "$F"
  # win-go-app-test worktree exp-wave3-t4/3c783520
  read -r -d '' F <<'EOF'
for k in k1b k2 k3 k3b k4 k4noack; do rm -rf $O/c-$k; cp -R $O/base $O/c-$k; done
# K1b: B1's amended page
git -C $W show record/exp-wave3-b1:$AOB > $O/c-k1b/$AOB
EOF
  conv_arm deny "R5 in a loop, cp -R onto it: a survivor gets base/ nested inside (3c783520)" "$F"
  read -r -d '' F <<'EOF'
R=$O/vb-repo; rm -rf $R; cp -R $O/base $R; git -c user.name=t4 -c user.email=t4@x.invalid -C $R init -q; mkdir -p $O/no-hooks
EOF
  conv_arm deny "R6 unquoted \$R, cp -R onto it (3c783520)" "$F"
  # docbrain/dd944173
  read -r -d '' F <<'EOF'
rm -rf "$WT" 2>/dev/null; git worktree prune
git worktree add -b tmp-hooktest2 "$WT" HEAD 2>&1 | tail -1
printf 'import os\nx=1\n' > "$WT/_hooktest.py"
git -C "$WT" add _hooktest.py
EOF
  conv_arm deny "R7 worktree add fails on a survivor, then > writes into it (dd944173)" "$F"
  # ~/.claude/e334dcd3
  read -r -d '' F <<'EOF'
rm -rf "$SRC"
ln -s "$DST" "$SRC"
echo "=== after ==="
stat -f '  type=%HT' "$SRC"; ls -ld "$SRC" | sed 's|.*memory|  memory|'
EOF
  conv_arm deny "R8 ln -s onto it: a survivor gets the link INSIDE it (e334dcd3)" "$F"
  # cleaner-temp/30a7a988
  read -r -d '' F <<'EOF'
rm -rf siri-tts-cli 2>/dev/null
git clone --depth 1 https://github.com/maximilianromer/siri-tts-cli.git 2>&1 | tail -3
cd siri-tts-cli
echo "=== repo shape ==="
EOF
  conv_arm deny "R9 clone fails on a survivor, then cd into the stale tree (30a7a988)" "$F"
  # DIB-governor/21ed3bbd
  read -r -d '' F <<'EOF'
\rm -rf "$SB/redtest" 2>/dev/null; git clone --quiet --local . "$SB/redtest"
\cp -f clerk/check-records.py clerk/events.py clerk/schema/orchestration-event.schema.json "$SB/redtest/clerk/" 2>/dev/null
EOF
  conv_arm deny "R10 \\rm, then \\cp -f into it (21ed3bbd)" "$F"

  echo "=== DENY arms: normalisation and verbs (synthetic) ==="
  conv_arm deny "quote, brace and trailing slash differ" 'rm -rf $S/mut4/ ; cp -R x "${S}/mut4"'
  conv_arm deny "rm -fr, reuse by mkdir of a child"      'rm -fr "$D"; mkdir -p "$D/state"'
  conv_arm deny "rm -r -f split flags"                   'rm -r -f out || true; mkdir out'
  conv_arm deny "rm P/* then write into P"               'rm -rf build/* 2>/dev/null; cp -R src/. build/'
  conv_arm deny "rmdir, then mkdir"                      'rmdir "$L/lock" 2>/dev/null; mkdir "$L/lock"'
  conv_arm deny "unzip -d"                               'rm -rf "$X"; unzip -q a.zip -d "$X"'
  conv_arm deny "a ; after the check ignores it"         'rm -rf P; test ! -e P; mkdir P'
  conv_arm deny "&& chain broken by ;"                   'rm -rf P && echo ok; mkdir P'
  conv_arm deny "sudo rm"                                'sudo rm -rf /opt/x; sudo mkdir -p /opt/x'

  echo "=== ALLOW arms: the two safe routes the denial teaches ==="
  conv_arm allow "safe route 1: fresh mktemp -d per run" 'd=$(mktemp -d "$TMPDIR/name.XXXXXX"); mkdir -p "$d/sub"; cp a "$d/sub/"'
  conv_arm allow "safe route 2: rm && test ! -e && mkdir" 'rm -rf "$S/mut4" && test ! -e "$S/mut4" && mkdir -p "$S/mut4"; cp x "$S/mut4/"'

  echo "=== ALLOW arms: real transcript commands (source transcript named) ==="
  # DIB-governor/96fcdd9c
  read -r -d '' F <<'EOF'
SP=/private/tmp/claude-501/-Users-me-CODE-CaptainCodeAU-DIB-governor/96fcdd9c-f843-49b0-a72b-80982dbe00c4/scratchpad; rm -rf "$SP/t3" && mkdir -p "$SP/t3/design" && \cp -f design/PARKED-IDEAS.md "$SP/t3/design/"
EOF
  conv_arm allow "A1 && chain from the rm: a failed rm stops it (96fcdd9c)" "$F"
  # fifty-shades-of-dotfiles/5df4e61d
  read -r -d '' F <<'EOF'
W=/Users/me/CODE/Scaffoldings/fifty-shades-of-dotfiles/.worktree/lint-staged/home; R=$(mktemp -d "$TMPDIR/dbg.XXXXXX"); mkdir -p $R/bin $R/r/bin; ln -s $W/.local/bin/shift-lint $R/bin/shift-lint; git -C $R/r init -q
EOF
  conv_arm allow "A2 mktemp -d, no rm at all (5df4e61d)" "$F"
  # UMBRELLA-DIB-governor/29876fbd
  read -r -d '' F <<'EOF'
mkdir -p $S/f5 && cd $S/f5 && rm -rf store reg.md 2>/dev/null; true
cp /Users/me/CODE/CaptainCodeAU/UMBRELLA/DIB/governor/design/04-OPEN-QUESTIONS.md reg.md
EOF
  conv_arm allow "A3 rm -rf of a FILE, cp (no -R) onto it: no merge (29876fbd)" "$F"
  # .claude memory WORK/df09e408
  read -r -d '' F <<'EOF'
S="$TMPDIR/sa"; cd "$S/a" && rm -rf node_modules pnpm-lock.yaml; echo "== engineStrict true"; out=$(pnpm install --no-frozen-lockfile --config.engineStrict=true 2>&1); echo "rc=$?"
EOF
  conv_arm allow "A4 rm of paths no known verb reuses (df09e408)" "$F"
  read -r -d '' F <<'EOF'
cd /tmp && rm -rf o13demo && mkdir o13demo && cd o13demo && git init -q -b master .
EOF
  conv_arm allow "A5 && chain, then cd into it (a real governor transcript)" "$F"
  # DIB-governor/...2327efe1c53f
  read -r -d '' F <<'EOF'
mkdir -p "$SP/probe" && cd "$SP/probe" && rm -rf g 2>/dev/null; git clone --quiet --local /Users/me/CODE/CaptainCodeAU/DIB/governor g && cd g && git log --oneline -1
EOF
  conv_arm allow "A6 git clone P && cd P: clone refuses a survivor, && stops (2327efe1c53f)" "$F"

  echo "=== ALLOW arms: gates and look-alikes (synthetic) ==="
  conv_arm allow "[ -e P ] && exit between"             'rm -rf P 2>/dev/null; [ -e P ] && exit 1; mkdir P'
  conv_arm allow "[[ -d P ]] && { ...; exit 1; }"        'rm -rf P; [[ -d P ]] && { echo left; exit 1; }; mkdir P'
  conv_arm allow "if [ -e P ]; then ... fi"              'rm -rf P; if [ -e P ]; then echo left >&2; exit 1; fi; mkdir P'
  conv_arm allow "rm || exit 1"                          'rm -rf "$W" || exit 1; mkdir -p "$W"'
  conv_arm allow "variable reassigned between"          'rm -rf "$D" 2>/dev/null; D=$(mktemp -d "$TMPDIR/d.XXXXXX"); mkdir "$D/x"'
  conv_arm allow "set -e earlier"                        'set -e; rm -rf P; mkdir P'
  conv_arm allow "rm -f single file, then > it"          'rm -f out.txt; echo hi > out.txt'
  conv_arm allow "rm -rf, never reused"                  'rm -rf "$S/old" 2>/dev/null; ls "$S"'
  conv_arm allow "a different path reused"               'rm -rf "$S/a"; mkdir -p "$S/ab"'
  conv_arm allow "the pattern as DATA in a commit message" 'git commit -m "fix: rm -rf \"$S/mut4\" 2>/dev/null; mkdir -p \"$S/mut4\" merged stale files"'
  read -r -d '' F <<'EOF'
cat > notes.md <<'MD'
rm -rf "$W" 2>/dev/null; mkdir -p "$W"
MD
EOF
  conv_arm allow "the pattern inside a heredoc body"    "$F"
  conv_arm allow "mv P away first (rename frees the name)" 'command mv "$S/mut4" "$S/mut4.old.$$" && mkdir -p "$S/mut4"'

  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  "scanner missing: a one-line reset is denied by name" 'rm -rf "$W" 2>/dev/null; mkdir -p "$W"'
  conv_arm allow "scanner missing: an unrelated command passes"      'ls -la'
  unset CONV_SHSCAN
  conv_selftest_end
fi

conv_hook_main
