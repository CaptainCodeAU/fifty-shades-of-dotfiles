#!/bin/bash
# enforce-pj-workers.sh -- DENY a Bash command that starts a plain Claude worker in
# a herdr pane. Deny only. Runs on PreToolUse for Bash. Registered for BOTH targets
# (user and project) in settings/claude/hooks.json: a conductor launched as plain
# claude (cb, lifeos) loads only the user target, a pj conductor the project one.
#
# WHY IT EXISTS (W-20260924-A59; rulings D-20260924-A04 layered, A05 pj-worker plus
# pane guard plus this hook). On 2026-09-24 four workers started with
# `herdr agent start --kind claude` ran as PLAIN claude: no pj system prompt, no
# project hooks, no Mods flag. A conductor starts a Claude worker ONLY with
# `pj-worker start`, and a clean-room one with `pj-worker start --cleanroom`.
#
# WHAT THIS IS, AND WHAT IT IS NOT. This hook is the EARLY, HONEST-SLIP layer: it
# refuses the conductor's own Bash call before anything reaches a pane, and names
# the route to use instead. It is NOT the floor. A Bash hook sees only the text of
# one Bash call, and redteam-3 H1 measured routes that never hold the pattern:
# `herdr pane send-text P "cla"` then `"ude"` in a second call, a script talking to
# herdr's socket, the Monitor tool (no Bash hook runs there, W-20260924-A71). The
# floor is the `claude()` guard in the pane's own zsh (.zshrc, HERDR_ENV=1),
# because herdr TYPES `claude` into that shell whatever route started it.
#
# WHAT IT DENIES (the rule lives in conv-shscan.awk, mode pjw):
#   herdr [--machine X] agent start ... --kind K, unless K (trimmed, lowercased) is
#     a known NON-claude kind; so claude, claude-code, Claude, an expansion, or no
#     readable --kind are all refused, and `-- --setting-sources ''` (the old
#     clean-room text exemption) is refused by name
#   herdr pane run|send-text|send-keys whose text, run the way the pane's zsh would
#     run it, has a command whose COMMAND WORD is claude or a .zshrc launcher (cb cr
#     ci cpr cd_ cskip ct lifeos claude-clean); claude's info forms pass
#     (--version, --help, agents, mcp, doctor, plugin, update, ...)
#   ...found anywhere: inside $(...), backticks, function bodies, and the string of
#     bash/sh/zsh -c, eval and ssh, which are re-scanned.
# ALLOWED: pj (Mods probe launches too), pj-worker, herdr-quick-task, other kinds,
#   claude as an argument, and prose: quotes, heredoc bodies, commit messages.
#
# ONE NAMED OVERRIDE (redteam-3 H6): a proof whose control needs a plain worker
# prefixes the herdr command with PJ_WORKERS_CONTROL=<W-YYYYMMDD-XNN>. It is
# allowed, logged to hooks-security.log, and named back in the hook's reply.
#
# FAILS CLOSED (redteam-3 H4). When jq is missing, the payload does not parse, or
# the command is not where it should be, and the RAW stdin mentions herdr with a
# launch verb, it denies by name. Every deny is permissionDecision "deny" with exit
# 0, so the `test -x ... || true` registration wrapper cannot swallow it. A missing
# scanner falls back to a crude word match, deny only.
#
# `--selftest` proves every arm: DENY and ALLOW arms are real transcript commands
# (source transcript named; the username in paths is replaced by "me" because the
# leak scan refuses it), plus synthetic arms for the spellings redteam-3 measured.
# CONV_HOOK_UNDER_TEST=<path> runs the same arms on another copy.

CONV_TAG=enforce-pj-workers
CONV_MODE_NAME=pjw
CONV_LIB_DIR="$(dirname "$0")"
CONV_LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log"
CONV_FALLBACK_ERE='herdr.*(agent[[:space:]]+start|pane[[:space:]]+(run|send-text|send-keys))'

PJW_ROUTE="A conductor starts a Claude worker ONLY with pj-worker start, and a clean-room one with pj-worker start --cleanroom (D-20260924-A04/A05)."

# Deny without jq: a fixed string, so it cannot fail to build.
pjw_deny_static() { # $1 why (no double quotes, no backslashes)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-pj-workers: %s, and the raw payload mentions a herdr launch, so it is refused rather than allowed unread. %s"}}\n' "$1" "$PJW_ROUTE"
  exit 0
}

# Does the raw text mention herdr with a launch verb? Pure bash: no jq, no grep.
pjw_raw_launch() {
  [[ "$1" == *herdr* ]] || return 1
  [[ "$1" =~ agent([[:space:]]|\\n)+start|pane([[:space:]]|\\n)+(run|send-text|send-keys) ]]
}

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  # Not even the plumbing is here: deny a likely launch by name, allow the rest.
  RAW=$(cat)
  pjw_raw_launch "$RAW" && pjw_deny_static "conv-hooklib.sh is missing beside the hook (restow home/.claude/hooks)"
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

pjw_main() {
  local input cmd sid out rc verdict msg id
  input=$(cat)
  if ! command -v jq >/dev/null 2>&1; then
    pjw_raw_launch "$input" && pjw_deny_static "jq is not on PATH, so the payload cannot be read"
    exit 0
  fi
  if ! printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1; then
    pjw_raw_launch "$input" && pjw_deny_static "the payload is not valid JSON"
    exit 0
  fi
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if [ -z "$cmd" ]; then
    pjw_raw_launch "$input" && pjw_deny_static "the payload has no tool_input.command"
    exit 0
  fi
  sid=$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null)
  out=$(printf '%s' "$cmd" | conv_scan ""); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    if printf '%s' "$cmd" | command grep -qE "$CONV_FALLBACK_ERE"; then
      conv_log BLOCKED "scanner unusable rc=$rc session=$sid" "$cmd"
      conv_deny "$CONV_TAG: its scanner conv-shscan.awk is missing or failed (rc=$rc), so it cannot tell a real launch from prose, and this command mentions a herdr launch. Restow the dotfiles (home/.claude/hooks) or fix the scanner. $PJW_ROUTE"
    fi
    exit 0
  fi
  verdict=${out%%$'\n'*}; msg=${out#*$'\n'}; msg=${msg%%$'\n'*}
  case "$verdict" in
    ALLOW) exit 0 ;;
    DENY)  conv_log BLOCKED "$msg session=$sid" "$cmd"; conv_deny "$msg" ;;
    CONTROL)
      id=${msg%% *}; msg=${msg#* }
      { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] CONTROL $CONV_TAG item=$id session=$sid \"$cmd\"" >> "${CONV_HOOK_LOG:-$CONV_LOG_FILE}"; } 2>/dev/null
      # No permissionDecision: the normal permission check still runs (conv-hooklib.sh rule 1).
      jq -n --arg id "$id" --arg m "$msg" '{
        systemMessage: ("enforce-pj-workers: override PJ_WORKERS_CONTROL=" + $id + " let a plain Claude worker launch through; logged to hooks-security.log."),
        hookSpecificOutput: {hookEventName: "PreToolUse",
          additionalContext: ("enforce-pj-workers: ALLOWED by the named override PJ_WORKERS_CONTROL=" + $id + " (logged). Without it this would be denied: " + $m)}}'
      exit 0 ;;
    *) conv_log BLOCKED "scanner said '$verdict' session=$sid" "$cmd"
       conv_deny "$CONV_TAG: its scanner returned '$verdict'; denying rather than guessing. $PJW_ROUTE" ;;
  esac
}

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  conv_selftest_begin "$0"

  # A raw stdin arm: bypasses conv_payload so the payload itself can be broken.
  raw_arm() { # $1 deny|allow, $2 label, $3 raw stdin, [$4 PATH override]
    local out got ok=0
    _st_n=$((_st_n + 1))
    if [ -n "${4:-}" ]; then
      out=$(printf '%s' "$3" | PATH="$4" CONV_HOOK_LOG=/dev/null /bin/bash "$_st_hook" 2>/dev/null)
    else
      out=$(printf '%s' "$3" | CONV_HOOK_LOG=/dev/null "$_st_hook" 2>/dev/null)
    fi
    case "$1" in
      deny)  case "$out" in *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*) ok=1 ;; esac ;;
      allow) [ -z "$out" ] && ok=1 ;;
    esac
    if [ "$ok" -eq 1 ]; then printf 'ok    %-7s %s\n' "$1" "$2"
    else printf 'FAIL  %-7s %s\n        got: %s\n' "$1" "$2" "$(printf '%s' "${out:-<no output>}" | head -c 300)"; _st_fails=$((_st_fails + 1)); fi
  }
  # The override arm: allowed (no decision), and the reply names the item.
  control_arm() { # $1 label, $2 command, $3 item id expected in the reply
    local out ok=0
    _st_n=$((_st_n + 1))
    out=$(conv_payload "$2" | CONV_HOOK_LOG=/dev/null "$_st_hook" 2>/dev/null)
    if printf '%s' "$out" | jq -e --arg id "$3" '(.hookSpecificOutput.permissionDecision == null)
         and (.hookSpecificOutput.additionalContext | contains($id))
         and (.systemMessage | contains($id))' >/dev/null 2>&1; then ok=1; fi
    if [ "$ok" -eq 1 ]; then printf 'ok    %-7s %s\n' control "$1"
    else printf 'FAIL  %-7s %s\n        got: %s\n' control "$1" "$(printf '%s' "${out:-<no output>}" | head -c 300)"; _st_fails=$((_st_fails + 1)); fi
  }

  # Fixtures are read with `read -r -d ''` from quoted heredocs: bash 3.2
  # mis-parses a quoted heredoc inside $( ). read returns 1 at EOF; harmless.
  echo "=== DENY arms: the two real conductor commands from redteam-3 H2 (verbatim) ==="
  # win-go-app-test/dc90f5bb: a function body, the launch on its own line
  read -r -d '' F <<'EOF'
R=/Users/me/CODE/CaptainCodeAU/win_go_app_test
BRIEF=/private/tmp/claude-501/-Users-me-CODE-CaptainCodeAU-win-go-app-test/dc90f5bb-102c-42e3-824e-7ddde8deb3aa/scratchpad/AUDIT-BRIEF.md
start(){ n="$1"; p="$2"; f="$3"
  herdr agent start "$n" --kind claude --pane "$p" --timeout 90000 >/dev/null 2>&1 && echo "started $n in $p" || { echo "RETRY $n"; herdr agent start "$n" --kind claude --pane "$p" --timeout 90000 >/dev/null && echo "started $n in $p (2nd try)"; }
  herdr agent prompt "$n" "STOP. Read this file in full before anything else: ${BRIEF}

Then audit EXACTLY ONE file, end to end: ${R}/${f}

You are strictly READ-ONLY. Do not edit, write, create, delete, commit, push, or publish anything at all. Do not spawn sub-agents. Use PAI NATIVE mode, not ALGORITHM mode. Read every line of the file, then output ONLY the report block the brief specifies, ending with the line: === END REPORT ===" >/dev/null && echo "   prompt queued -> $n ($f)"
}
start aud05 w8:pJ "research-topics/assignment-of-benefit/aob-explainer.html"
start aud06 w8:pK "research-topics/assignment-of-benefit/aob-owner-briefing.html"
EOF
  conv_arm deny "H2a function body, retry chain (win-go-app-test dc90f5bb)" "$F"
  # win-go-app-test/6d0a874c: the launch INSIDE $(...) inside a function body
  read -r -d '' F <<'EOF'
start() { n=$1; p=$2; for i in 1 2 3 4 5; do out=$(herdr agent start "$n" --kind claude --pane "$p" 2>&1) && { echo "$n: started"; return 0; }; case "$out" in *agent_not_ready*|*agent_name_taken*) echo "$n: $out" | head -c 300; echo; return 0;; esac; sleep 4; done; echo "$n: FAILED: $out" | head -c 400; echo; }
start h2parser w2B:p1; start h2walker w2C:p1; start h2helper w2D:p1; herdr agent list | uv run python3 -c "import json,sys; [print(a['name'] if 'name' in a else a.get('pane_id'), a['agent_status'], a['pane_id']) for a in json.load(sys.stdin)['result']['agents']]"
EOF
  conv_arm deny "H2b \$(...) inside a function body (win-go-app-test 6d0a874c)" "$F"

  echo "=== DENY arms: more real launches (source transcript named) ==="
  # fifty-shades-of-dotfiles/d2df9205
  read -r -d '' F <<'EOF'
for pair in a:w3X:p3D b:w3X:p3E c:w3X:p3F d:w3X:p3G; do n=cphang-${pair%%:*}; p=${pair#*:}
  for i in 1 2 3 4 5; do out=$(herdr agent start "$n" --kind claude --pane "$p" -- --permission-mode bypassPermissions 2>&1); rc=$?
    echo "$n try$i rc=$rc $(echo "$out" | head -c 200)"; [ $rc -eq 0 ] && break; echo "$out" | grep -qE 'agent_not_ready|agent_name_taken' && break; sleep 3; done
  herdr pane rename "$p" "$n" >/dev/null; done
EOF
  conv_arm deny "R1 nested loops, \$(...) (d2df9205)" "$F"
  read -r -d '' F <<'EOF'
out=$(herdr agent start cphang-a --kind claude --pane w3X:p3D -- --permission-mode bypassPermissions 2>&1); echo "rc=$? $(echo "$out" | head -c 160)"; herdr pane rename w3X:p3D cphang-a >/dev/null; herdr agent list | jq -c '.result.agents[] | select((.agent.name // "") | startswith("cphang")) | {n:.agent.name, s:.agent_status}'
EOF
  conv_arm deny "R2 out=\$(herdr agent start ...) (d2df9205)" "$F"
  read -r -d '' F <<'EOF'
R=/Users/me/CODE/Scaffoldings/fifty-shades-of-dotfiles; B=/private/tmp/claude-501/-Users-me-CODE-Scaffoldings-fifty-shades-of-dotfiles/d2df9205-4185-48ee-9639-bef571b81400/scratchpad/stage1
cat > $B/bg-brief.md <<'MD'
# Background arm (conductor: fifty-shades-of-dotfiles-main). Do ONLY this.
1. Run this as ONE Bash call with run_in_background: true, exactly as written (heredoc included):
   cat >/dev/null <<'X'
   heredoc
   X
2. Wait for its completion notification (do not poll).
MD
p=$(herdr pane split --current --direction right --cwd "$R" --no-focus | jq -r '.result.pane.pane_id'); echo $p > $TMPDIR/bg-pane
for t in 1 2 3 4 5 6 7 8; do out=$(herdr agent start s1-bg --kind claude --pane "$p" -- --permission-mode bypassPermissions 2>&1); rc=$?; [ $rc -eq 0 ] && break; echo "$out" | grep -qE 'agent_not_ready|agent_name_taken' && break; sleep 4; done
EOF
  conv_arm deny "R3 a launch AFTER a heredoc (d2df9205, brief trimmed, delimiter renamed)" "$F"
  # ~/.claude/e334dcd3: the clean-room text exemption, ruled out
  read -r -d '' F <<'EOF'
for i in 1 2 3 4; do
  out=$(herdr agent start cleanroom1 --kind claude --pane w33:p4 -- --setting-sources '' --strict-mcp-config 2>&1)
  rc=$?
  echo "attempt $i rc=$rc: $out"
  case "$out" in *agent_name_taken*|*agent_not_ready*) break;; esac
  [ $rc -eq 0 ] && break
  sleep 3
done
EOF
  conv_arm deny "R4 clean-room text exemption -- --setting-sources '' (e334dcd3)" "$F"
  # fifty-shades-of-dotfiles/af5d0494 (redteam-3's own probes)
  read -r -d '' F <<'EOF'
for a in "--kind=claude" "--kind Claude" "--kind claude"; do out=$(herdr agent start rt3x ${=a} --pane w3X:p999 2>&1); rc=$?; echo "[$a] rc=$rc $(printf '%s' "$out" | head -c 160)"; done
EOF
  conv_arm deny "R5 kind hidden in \${=a}: no readable --kind (af5d0494)" "$F"
  read -r -d '' F <<'EOF'
P=w3X:p4D; herdr pane send-keys $P c l a u d e space - - v i a - k e y s enter; echo "rc=$?"; herdr pane wait-output $P --match "argv=--via-keys" --timeout 8000 >/dev/null; echo "wait rc=$?"
EOF
  conv_arm deny "R6 send-keys spelling claude letter by letter (af5d0494)" "$F"
  read -r -d '' F <<'EOF'
P=w3X:p4D; herdr pane run $P "cb --via-alias-cb"; herdr pane wait-output $P --match "argv=" --regex 'argv=.*--via-alias-cb' --timeout 15000 >/dev/null 2>&1; echo "wait rc=$?"; herdr-pane-read $P -n 12 2>&1 | rg -v '^\s*$' | tail -8
EOF
  conv_arm deny "R7 pane run the cb alias (af5d0494)" "$F"
  # fifty-shades-of-dotfiles/9e9c8add
  conv_arm deny "R8 pane run claude --setting-sources '' (9e9c8add)" \
    "herdr pane run w3X:pF \"claude --name f5d-dup --setting-sources '' --strict-mcp-config\""
  # fifty-shades-of-dotfiles/cc5a37ff (command trimmed to its launch)
  conv_arm deny "R9 pane run claude --resume (cc5a37ff)" \
    'herdr pane run w3X:p4E "claude --resume 773a58aa-7267-437a-8504-637d553e4ef4 --permission-mode bypassPermissions"'
  # 64c95115 and ddd9aa3c
  conv_arm deny "R10 pane run \"cb\" (64c95115)"      'herdr pane run $P "cb"'
  conv_arm deny "R11 pane run \"lifeos\" (ddd9aa3c)"  'herdr pane run w1S:p5 "lifeos"; sleep 25; herdr pane read w1S:p5 --source visible --lines 60'
  # 32dc12b2: claude after a ; inside a single-quoted pane string
  read -r -d '' F <<'EOF'
herdr agent prompt ttydemo "/exit" >/dev/null 2>&1; sleep 4
herdr pane run w1S:pB 'clear; sh ~/.claude/hooks/LastCommitFiles.sh </dev/null; claude'
EOF
  conv_arm deny "R12 claude as the 3rd command in the pane string (32dc12b2)" "$F"

  echo "=== DENY arms: spellings and wrappers redteam-3 measured (synthetic) ==="
  conv_arm deny "--kind Claude (capitalised, herdr accepts it)"  'herdr agent start w --kind Claude --pane w3X:p9'
  conv_arm deny "--kind claude-code (herdr accepts it)"          'herdr agent start w --kind claude-code --pane w3X:p9'
  conv_arm deny "--kind \" claude\" (leading space)"             'herdr agent start w --kind " claude" --pane w3X:p9'
  conv_arm deny "--kind \"\$KIND\" (unreadable)"                 'herdr agent start w --kind "$KIND" --pane w3X:p9'
  conv_arm deny "no --kind at all"                               'herdr agent start w --pane w3X:p9'
  conv_arm deny "herdr --machine X agent start"                  'herdr --machine boxc agent start w --kind claude --pane w1:p1'
  conv_arm deny "absolute path to herdr"                         '~/.local/bin/herdr agent start w --kind claude --pane w1:p1'
  conv_arm deny "behind timeout (a wrapper eff() does not know)" 'timeout 60 herdr agent start w --kind claude --pane w1:p1'
  conv_arm deny "R=\$(...) form docs/HERDR_AGENT_AUTOMATION teaches" 'R=$(herdr agent start demo --kind claude --pane "$AP" --timeout 60000)'
  conv_arm deny "inside backticks"                               'r=`herdr agent start w --kind claude --pane w1:p1`'
  conv_arm deny "inside bash -c"                                 "bash -c 'herdr agent start w --kind claude --pane w1:p1'"
  conv_arm deny "inside zsh -lc"                                 'zsh -lc "herdr agent start w --kind claude --pane w1:p1"'
  conv_arm deny "inside eval"                                    "eval 'herdr agent start w --kind claude --pane w1:p1'"
  conv_arm deny "inside ssh's remote command"                    'ssh boxc herdr agent start w --kind claude --pane w1:p1'
  conv_arm deny "pane run: command claude"                       'herdr pane run w1:p1 "command claude"'
  conv_arm deny "pane run: env -i claude"                        'herdr pane run w1:p1 "env -i HOME=$HOME claude"'
  conv_arm deny "pane run: exec claude"                          'herdr pane run w1:p1 "exec claude --permission-mode bypassPermissions"'
  conv_arm deny "pane run: claude by path"                       'herdr pane run w1:p1 ~/.local/bin/claude'
  conv_arm deny "pane run: claude's versioned binary"            'herdr pane run w1:p1 ~/.local/share/claude/versions/2.1.281'
  conv_arm deny "pane run: claude -p (headless is a session too)" "herdr pane run w1:p1 \"claude -p 'hi'\""
  conv_arm deny "pane run: claude-clean (ruled: pj-worker --cleanroom)" 'herdr pane run w1:p1 "claude-clean"'
  conv_arm deny "pane run: __claude_launch claude"               'herdr pane run w1:p1 "__claude_launch claude --resume"'
  conv_arm deny "pane run: claude in \$(...) in the pane"        'herdr pane run w1:p1 "x=\$(claude -p hi)"'
  conv_arm deny "pane run: bash -c inside the pane string"       "herdr pane run w1:p1 \"bash -c 'cd /tmp && claude'\""
  conv_arm deny "send-text claude (typed, Enter later)"         'herdr pane send-text w1:p1 "claude --resume"; herdr pane send-keys w1:p1 enter'
  conv_arm deny "pane run with the command as several words"    'herdr pane run w1:p1 claude --model opus'
  conv_arm deny "PJ_WORKERS_CONTROL with a malformed id"        'PJ_WORKERS_CONTROL=please herdr agent start w --kind claude --pane w1:p1'
  conv_arm deny "PJ_WORKERS_CONTROL on ANOTHER command only"    'PJ_WORKERS_CONTROL=W-20260924-A59 true; herdr agent start w --kind claude --pane w1:p1'

  echo "=== ALLOW arms: real transcript commands (source transcript named) ==="
  # e8aae7dc: the Mods probe launch redteam-3 H7 names (CLAUDE twice, clear; first)
  conv_arm allow "A1 Mods probe: clear; CLAUDE_...=... pj --profile scratch (e8aae7dc)" \
    'herdr pane run w3X:pQ "clear; CLAUDE_CODE_SESSION_NAME=fifty-shades-of-dotfiles-scratch-f8a-ui CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 pj --profile scratch --plugin-dir $S/mods/f8a-ui"'
  read -r -d '' F <<'EOF'
P=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id'); echo "P=$P"; sleep 3; herdr pane run "$P" "pj"
EOF
  conv_arm allow "A2 split then pane run \"pj\" (f3f1e8ee, trimmed)" "$F"
  conv_arm allow "A3 command word from \${(j: :)envs}, then pj (5fccb14f)" 'herdr pane run "$pid" "${(j: :)envs} pj ${(j: :)pjargs}"'
  conv_arm allow "A4 pane run 'alias claude': claude is an argument (deb7e00a)" "herdr pane run w2S:p2 'alias claude'"
  conv_arm allow "A5 pane run \"c2 start f5dproof\" (9e9c8add)" 'herdr pane run w3X:pJ "c2 start f5dproof"'
  conv_arm allow "A6 _claude_launch sh probe.sh: runs sh, not claude (27645164)" \
    "herdr pane run wZ:pD \"clear; PROBE_LABEL='B1: via _claude_launch (the restart path)' _claude_launch sh \$D/probe.sh\""
  conv_arm allow "A7 send-text \"ude --split-text\" alone (af5d0494; the split route is the floor's)" \
    'herdr pane send-text w3X:p4D "ude --split-text"; herdr pane send-keys w3X:p4D enter'
  conv_arm allow "A8 claude agents --json, the agent's own Bash (AgentRelay skill)" 'claude agents --json 2>&1'
  conv_arm allow "A9 which claude; claude --version, the agent's own Bash"       'which claude 2>&1; claude --version 2>&1'
  # d2df9205: the pattern as PROSE in an open-items title
  read -r -d '' F <<'EOF'
r(){ out=$("$@" 2>&1); rc=$?; print -r -- "rc=$rc $(print -r -- "$out" | tail -1)"; }
r open-items add "Herdr workers started with 'herdr agent start --kind claude' are not pj sessions: no pj system prompt (OPERATIONAL_RULES, pj-global RULES), no project hook settings, no Mods flag" --kind decide --done-when "Gavin has decided"
EOF
  conv_arm allow "A10 the pattern as prose in an item title (d2df9205, trimmed)" "$F"
  # f210c4d2: the pattern inside a python heredoc that edits SKILL.md
  read -r -d '' F <<'EOF'
S=~/.claude/skills/herdr/SKILL.md
uv run python3 - "$S" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
new = """```bash
herdr agent start cleanroom --kind claude --pane <returned-pane-id> -- --setting-sources '' --strict-mcp-config
```"""
PY
EOF
  conv_arm allow "A11 the pattern inside a heredoc body (f210c4d2, trimmed)" "$F"
  conv_arm allow "A12 the pattern as a search pattern (af5d0494-style rg)" \
    "rg -n -- '--kind claude|agent start .*claude|herdr pane run .*(pj|claude)' docs/HERDR.md"

  echo "=== ALLOW arms: the routes the denial teaches, and look-alikes (synthetic) ==="
  conv_arm allow "pj-worker start"                              'pj-worker start --name hook --cwd "$PWD"'
  conv_arm allow "pj-worker start --cleanroom"                  'pj-worker start --cleanroom --name probe'
  conv_arm allow "herdr-quick-task (routes claude via pj-worker)" 'herdr-quick-task . "run the tests"'
  conv_arm allow "--kind codex"                                 'herdr agent start reviewer --kind codex --pane w1:p2'
  conv_arm allow "--kind \"Gemini\" (normalised, not claude)"   'herdr agent start g --kind "Gemini" --pane w1:p2'
  conv_arm allow "pane run: claude --version"                   'herdr pane run w1:p1 "claude --version"'
  conv_arm allow "pane run: claude agents --json"               'herdr pane run w1:p1 "claude agents --json"'
  conv_arm allow "pane run: claude mcp list"                    'herdr pane run w1:p1 "claude mcp list"'
  conv_arm allow "pane run: echo claude"                        'herdr pane run w1:p1 "echo claude is here"'
  conv_arm allow "pane run: an ordinary command"                'herdr pane run w1:p1 "just test"'
  conv_arm allow "herdr agent list / read / pane read"          'herdr agent list; herdr agent read w --lines 40; herdr pane read w1:p1'
  conv_arm allow "commit message naming the pattern"            'git commit -m "docs: never herdr agent start --kind claude; use pj-worker start"'
  conv_arm allow "echo of the pattern in quotes"                'echo "herdr pane run P \"claude\" is refused"'

  echo "=== CONTROL arms: the one named override (redteam-3 H6) ==="
  control_arm "PJ_WORKERS_CONTROL=W-20260924-A59 prefix on agent start" \
    'PJ_WORKERS_CONTROL=W-20260924-A59 herdr agent start ctl --kind claude --pane w1:p1' W-20260924-A59
  control_arm "the override on a pane run of claude" \
    'PJ_WORKERS_CONTROL=W-20260924-A59 herdr pane run w1:p1 "claude"' W-20260924-A59
  control_arm "the override through env" \
    'env PJ_WORKERS_CONTROL=W-20260924-A77 herdr agent start ctl --kind claude --pane w1:p1' W-20260924-A77

  echo "=== FAIL-CLOSED arms: the payload cannot be read (redteam-3 H4) ==="
  GOOD=$(conv_payload 'herdr agent start w --kind claude --pane w1:p1')
  raw_arm deny  "truncated JSON that mentions a herdr launch"   "${GOOD:0:$((${#GOOD} - 40))}"
  raw_arm deny  "the command under the wrong key"               "$(printf '%s' "$GOOD" | jq -c '.tool_input = {cmd: .tool_input.command}')"
  raw_arm allow "truncated JSON with no herdr in it"            '{"tool_input":{"command":"ls -la'
  # A PATH holding only the tools the hook needs, jq left out. One fixed folder,
  # refreshed in place (ln -sf), so reruns do not pile up temp dirs.
  NOJQ="${TMPDIR:-/tmp}/pjw-selftest-nojq"; mkdir -p "$NOJQ"
  for t in dirname cat awk grep date mkdir; do p=$(whence -p "$t" 2>/dev/null || type -P "$t" 2>/dev/null) && ln -sf "$p" "$NOJQ/$t"; done
  [ -e "$NOJQ/jq" ] && { echo "FAIL  setup   $NOJQ holds a jq; the no-jq arms would test nothing"; _st_fails=$((_st_fails + 1)); }
  raw_arm deny  "PATH without jq, a herdr launch"               "$GOOD" "$NOJQ"
  raw_arm allow "PATH without jq, an unrelated command"         "$(conv_payload 'ls -la')" "$NOJQ"
  # The registration wrapper: `test -x X && X || true` must not swallow a deny.
  _st_n=$((_st_n + 1))
  wout=$(printf '%s' "$GOOD" | CONV_HOOK_LOG=/dev/null bash -c 'test -x "$1" && "$1" || true' _ "$_st_hook" 2>/dev/null); wrc=$?
  if [ "$wrc" -eq 0 ] && printf '%s' "$wout" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    printf 'ok    %-7s %s\n' wrapper "test -x ... || true still carries the deny (exit 0 + JSON)"
  else printf 'FAIL  %-7s %s\n' wrapper "the || true wrapper swallowed the deny"; _st_fails=$((_st_fails + 1)); fi

  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  "scanner missing: a herdr launch is denied by name" 'herdr agent start w --kind claude --pane w1:p1'
  conv_arm allow "scanner missing: an unrelated command passes"      'ls -la'
  unset CONV_SHSCAN
  conv_selftest_end
fi

pjw_main
