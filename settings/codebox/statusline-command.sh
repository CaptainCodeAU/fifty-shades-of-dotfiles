#!/bin/bash
# LifeOS Claude Code status line.
# Shows, on two lines:
#   model | effort level | working directory | git branch (+ dirty state) | context used %
#   session id [ name, only when the user set one ] | cost | prompt cache | Claude.ai rate limits (5h/7d) as bars with time to reset | agents
# `bash statusline-command.sh --selftest` proves each field (W-20260923-A08).
# Invoked as `bash ~/.claude/statusline-command.sh` from settings.json's
# statusLine.command, so this file does not need to be executable itself.

# `--selftest` proves every field against a real captured input (Claude Code
# 2.1.283) and real agent meta files, each arm with its negative. Layout follows
# hooks/enforce-no-permanent-delete.sh. HOME points at the fixture dir, so the
# capture gate below is exercised without touching the real ~/.cache.
if [ "${1:-}" = "--selftest" ]; then
    self="$0"
    fx=$(mktemp -d "${TMPDIR:-/tmp}/statusline-selftest.XXXXXX") || { echo "cannot make a fixture dir"; exit 1; }
    cat > "$fx/input.json" <<'EOF'
{"session_id":"8f3ea912-a349-4943-862e-6d47e3c27f13","transcript_path":"/Users/someone/.claude/projects/-Users-someone-CODE-Scaffoldings-fifty-shades-of-dotfiles/8f3ea912-a349-4943-862e-6d47e3c27f13.jsonl","cwd":"/Users/someone/CODE/Scaffoldings/fifty-shades-of-dotfiles","scratchpad_dir":"/private/tmp/claude-501/-Users-someone-CODE-Scaffoldings-fifty-shades-of-dotfiles/8f3ea912-a349-4943-862e-6d47e3c27f13/scratchpad","prompt_id":"8f3f9f37-7e67-47e4-83f9-6cb8a534cd87","effort":{"level":"high"},"session_name":"Statusline open items","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"/Users/someone/CODE/Scaffoldings/fifty-shades-of-dotfiles","project_dir":"/Users/someone/CODE/Scaffoldings/fifty-shades-of-dotfiles","added_dirs":[],"repo":{"host":"github.com","owner":"CaptainCodeAU","name":"fifty-shades-of-dotfiles"}},"version":"2.1.283","output_style":{"name":"pj-voice:pj-voice"},"cost":{"total_cost_usd":0.7571017999999999,"total_duration_ms":180913,"total_api_duration_ms":83596,"total_lines_added":8,"total_lines_removed":0},"context_window":{"total_input_tokens":83587,"total_output_tokens":3,"context_window_size":1000000,"current_usage":{"input_tokens":2,"output_tokens":3,"cache_creation_input_tokens":2778,"cache_read_input_tokens":80807},"used_percentage":8,"remaining_percentage":92},"exceeds_200k_tokens":false,"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1790486768,"requests":15,"misses":0,"expected_rebuilds":0,"hit_ratio":0.9552318883602365,"cache_write_tokens":49284,"miss_recache_tokens":0,"last_miss_at":null,"last_miss_cause":null,"miss_causes":{},"recache_tokens_if_cold":80809},"fast_mode":false,"thinking":{"enabled":true},"rate_limits":{"five_hour":{"used_percentage":9,"resets_at":1790493000},"seven_day":{"used_percentage":5,"resets_at":1791025200}}}
EOF
    mkdir -p "$fx/t/subagents"
    i=0
    while IFS= read -r meta; do
        i=$((i + 1))
        printf '%s\n' "$meta" > "$fx/t/subagents/agent-$i.meta.json"
        touch -t "2026010100$(printf '%02d' "$i")" "$fx/t/subagents/agent-$i.meta.json"
    done <<'EOF'
{"agentType":"hooks-project","description":"Inventory project hook scripts","name":"hooks-project","spawnDepth":0,"requestShape":"background","requestNonInteractive":true,"model":"claude-fable-5-1[1m]","taskKind":"in_process_teammate","teamName":"session-1e80ed4c","color":"blue","planModeRequired":false,"permissionMode":"bypassPermissions"}
{"agentType":"hooks-plugins","description":"Inventory plugin hooks and content","name":"hooks-plugins","spawnDepth":0,"requestShape":"background","requestNonInteractive":true,"model":"claude-fable-5-1[1m]","taskKind":"in_process_teammate","teamName":"session-1e80ed4c","color":"green","planModeRequired":false,"permissionMode":"bypassPermissions"}
{"agentType":"rules-pointers","description":"Rules files, pointers, worktree memory key","name":"rules-pointers","spawnDepth":0,"requestShape":"background","requestNonInteractive":true,"model":"claude-fable-5-1[1m]","taskKind":"in_process_teammate","teamName":"session-1e80ed4c","color":"yellow","planModeRequired":false,"permissionMode":"bypassPermissions"}
{"agentType":"Explore","description":"Map PAI audio notification architecture"}
EOF
    now=$(date +%s)
    # Times moved relative to now (the captured ones are in the past), paths
    # moved into the fixture dir; 30 s of slack keeps the countdowns stable.
    base=$(jq --arg t "$fx/t.jsonl" --arg d "$fx" --argjson now "$now" '
        .transcript_path = $t | .cwd = $d | .workspace.current_dir = $d
        | .prompt_cache.expires_at = ($now + 1830)
        | .rate_limits.five_hour.resets_at = ($now + 7350)
        | .rate_limits.seven_day.resets_at = ($now + 3 * 86400 + 3630)' "$fx/input.json")
    # HERDR_ENV/HERDR_PANE_ID are cleared so a selftest run inside a herdr pane
    # never reports fixture data onto that pane's sidebar row; hraw() sets them
    # with a fake herdr on PATH that records what it was asked.
    raw() { printf '%s' "$1" | env -u CLAUDE_CONFIG_DIR -u HERDR_ENV -u HERDR_PANE_ID HOME="$fx" bash "$self"; }
    mkdir -p "$fx/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/herdr-args"\n' "$fx" > "$fx/bin/herdr"
    chmod +x "$fx/bin/herdr"
    hraw() { printf '%s' "$1" | env -u CLAUDE_CONFIG_DIR HOME="$fx" HERDR_ENV=1 HERDR_PANE_ID=wT:p1 PATH="$fx/bin:$PATH" bash "$self" >/dev/null; }
    hargs() { # the fake herdr's arguments from the last hraw (it runs in the background)
        local n=0
        while [ ! -s "$fx/herdr-args" ] && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
        sleep 0.1
        cat "$fx/herdr-args" 2>/dev/null; command mv "$fx/herdr-args" "$fx/herdr-args.seen" 2>/dev/null
    }
    plain() { raw "$1" | sed $'s/\x1b\\[[0-9;]*m//g'; }
    alter() { printf '%s' "$base" | jq "$1"; }
    pass=0 fail=0
    check() { # $1 arm, $2 output, $3 needle, $4 yes|no (should it be there)
        if printf '%s' "$2" | grep -qF -- "$3"; then got=yes; else got=no; fi
        if [ "$got" = "$4" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: '$3' present=$got, wanted $4"; fi
    }
    out=$(plain "$base")
    check "two lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2" yes
    check "session id" "$out" "8f3ea912-a349-4943-862e-6d47e3c27f13" yes
    check "session id absent" "$(plain "$(alter 'del(.session_id)')")" "8f3ea912" no
    # Session name (Gavin 2026-09-29): shown only when the registry says the user set it.
    # Records trimmed from real ~/.claude/sessions/<pid>.json files (Claude Code 2.1.284).
    sid=8f3ea912-a349-4943-862e-6d47e3c27f13 reg="$fx/.claude/sessions"
    check "no registry: bare id" "$out" "$sid [" no
    mkdir -p "$reg"
    rec() { printf '{"pid":31632,"sessionId":"%s","kind":"interactive","entrypoint":"cli","name":"%s","status":"busy"%s}\n' "$1" "$2" "$3" > "$reg/31632.json"; }
    rec "$sid" "dotfiles-one" ',"nameSource":"user"'
    check "renamed: name in brackets" "$(plain "$base")" "$sid [ dotfiles-one ]" yes
    check "renamed: brackets bright white" "$(raw "$base")" $'\033[97m[ dotfiles-one ]' yes
    rec "$sid" "fifty-shades-of-dotfiles-main" ''
    check "pj automatic name: bare id" "$(plain "$base")" "$sid [" no
    rec "$sid" "some-derived-name" ',"nameSource":"derived"'
    check "derived name: bare id" "$(plain "$base")" "$sid [" no
    rec "9e770bda-0000-4000-8000-000000000000" "other-session" ',"nameSource":"user"'
    check "another session renamed: bare id" "$(plain "$base")" "$sid [" no
    rec "$sid" 'evil\u001b[31mred' ',"nameSource":"user"'
    check "control characters stripped" "$(raw "$base")" $'\033[31mred' no
    command mv "$reg" "$fx/sessions-off"
    check "ctx bar" "$out" "ctx ▰▱▱▱▱▱▱▱▱▱ 8%" yes
    check "ctx absent" "$(plain "$(alter 'del(.context_window)')")" "ctx " no
    check "5h bar + countdown" "$out" "5h ▰▱▱▱▱▱▱▱▱▱ 9% ↻2h02m" yes
    check "7d bar + countdown" "$out" "7d ▰▱▱▱▱▱▱▱▱▱ 5% ↻3d1h" yes
    check "limits absent" "$(plain "$(alter 'del(.rate_limits)')")" "5h " no
    check "cost" "$out" "\$0.76" yes
    check "cache warm shows its ttl" "$out" "cache warm 30m/1h · 96% hit" yes
    # The warning colour scales with the cache's own ttl: yellow in its last fifth
    # (12 min of a 1h cache, 1 min of a 5m cache), never a fixed 5 minutes.
    Y=$'\033[93mcache warm' C=$'\033[96mcache warm'
    h10=$(raw "$(alter ".prompt_cache.expires_at = $((now + 630))")")
    check "1h, 10m left: yellow" "$h10" "$Y" yes
    check "1h, 10m left: not cyan" "$h10" "$C" no
    h20=$(raw "$(alter ".prompt_cache.expires_at = $((now + 1230))")")
    check "1h, 20m left: cyan" "$h20" "$C" yes
    check "1h, 20m left: not yellow" "$h20" "$Y" no
    m3=$(raw "$(alter ".prompt_cache.ttl = \"5m\" | .prompt_cache.expires_at = $((now + 215))")")
    check "5m, 3m left: cyan" "$m3" "$C" yes
    check "5m, 3m left: not yellow" "$m3" "$Y" no
    check "5m, 3m left: shows 3m/5m" "$(printf '%s' "$m3" | sed $'s/\x1b\\[[0-9;]*m//g')" "cache warm 3m/5m" yes
    m0=$(raw "$(alter ".prompt_cache.ttl = \"5m\" | .prompt_cache.expires_at = $((now + 40))")")
    check "5m, 40s left: yellow" "$m0" "$Y" yes
    # Negative arms: no ttl, or one that cannot be read, fall back to the old
    # fixed 5-minute warning and show no /ttl.
    nt=$(plain "$(alter 'del(.prompt_cache.ttl)')")
    check "no ttl: countdown still shown" "$nt" "cache warm 30m" yes
    check "no ttl: no /ttl suffix" "$nt" "cache warm 30m/" no
    ntw=$(raw "$(alter "del(.prompt_cache.ttl) | .prompt_cache.expires_at = $((now + 200))")")
    check "no ttl, 3m left: yellow (fixed 5m fallback)" "$ntw" "$Y" yes
    bad=$(plain "$(alter '.prompt_cache.ttl = "soon"')")
    check "unreadable ttl: no suffix" "$bad" "cache warm 30m/" no
    check "unreadable ttl: countdown still shown" "$bad" "cache warm 30m" yes
    cold=$(plain "$(alter '.prompt_cache.warm = false')")
    check "cache cold" "$cold" "cache cold" yes
    check "cache cold not warm" "$cold" "cache warm" no
    check "cache misses" "$(plain "$(alter '.prompt_cache.misses = 3')")" "3 misses" yes
    check "agents capped at 3" "$out" "agents hooks-project, hooks-plugins, rules-pointers +1" yes
    check "agent colour" "$(raw "$base")" $'\033[94mhooks-project' yes
    command mv "$fx/t/subagents/agent-1.meta.json" "$fx/t/subagents/agent-2.meta.json" "$fx/t/subagents/agent-3.meta.json" "$fx/"
    check "unnamed agent shows type" "$(plain "$base")" "agents Explore" yes
    command mv "$fx/t/subagents" "$fx/subagents-off"
    check "no agents, no segment" "$(plain "$base")" "agents" no
    check "gradient red end at 85%" "$(raw "$(alter '.context_window.used_percentage = 85')")" "38;2;242;96;60m" yes
    check "gradient no red end at 8%" "$(raw "$base")" "38;2;242;96;60m" no
    cap="$fx/.cache/statusline-capture/8f3ea912-a349-4943-862e-6d47e3c27f13.json"
    raw "$base" >/dev/null
    check "capture gate closed" "$([ -e "$cap" ] && echo written || echo none)" "none" yes
    mkdir -p "$fx/.cache/statusline-capture"
    raw "$base" >/dev/null
    check "capture gate open" "$([ -e "$cap" ] && echo written || echo none)" "written" yes
    # herdr sidebar countdown (Gavin, 19 Oct, dotfiles-main Q70: 1).
    hraw "$base"; h=$(hargs)
    check "herdr: warm countdown reported" "$h" "--token cache_warm=◷ 30m" yes
    check "herdr: other buckets cleared" "$h" "--clear-token cache_low --clear-token cache_cold" yes
    check "herdr: this pane, own source" "$h" "pane report-metadata wT:p1 --source dotfiles-statusline-cache" yes
    hraw "$(alter ".prompt_cache.expires_at = $((now + 630))")"; h=$(hargs)
    check "herdr: last fifth is low" "$h" "--token cache_low=◷ 10m" yes
    hraw "$(alter '.prompt_cache.warm = false')"; h=$(hargs)
    check "herdr: cold" "$h" "--token cache_cold=◷ cold" yes
    sleep 0.3; command mv "$fx/herdr-args" "$fx/herdr-args.late" 2>/dev/null  # a late write from an arm above
    raw "$base" >/dev/null; sleep 0.3
    check "herdr: not called outside herdr" "$([ -e "$fx/herdr-args" ] && echo called || echo none)" "none" yes
    command mv "$fx/herdr-args" "$fx/herdr-args.late" 2>/dev/null
    hraw "$(alter 'del(.prompt_cache)')"; sleep 0.3
    check "herdr: not called before the first response" "$([ -e "$fx/herdr-args" ] && echo called || echo none)" "none" yes
    echo "statusline selftest: $pass passed, $fail failed (fixtures: $fx)"
    [ "$fail" -eq 0 ]
    exit
fi

input=$(cat)

# Fixture capture (W-20260923-A08): only while ~/.cache/statusline-capture
# exists, keep the latest raw input per session. Delete the dir to stop.
cap_dir="$HOME/.cache/statusline-capture"
if [ -d "$cap_dir" ]; then
    cap_sid=$(printf '%s' "$input" | jq -r '.session_id // "no-session"')
    printf '%s' "$input" 2>/dev/null > "$cap_dir/$cap_sid.json"
fi

model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')
# Live per-session reasoning-effort level (low/medium/high/xhigh/max). This
# comes straight from the statusLine JSON payload rather than being re-read
# from settings.json's effortLevel/modelSettings, since the payload's
# .effort.level is the actual live value for THIS session and model -- it
# can be switched mid-session and would otherwise drift from the static
# config file. Absent entirely on models that don't support reasoning effort.
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Show the working directory relative to $HOME (e.g. ~/.claude) instead of
# just the basename, so nested paths stay identifiable at a glance.
if [ -n "$cwd" ]; then
    case "$cwd" in
        "$HOME"/*) dir_display="~${cwd#"$HOME"}" ;;
        "$HOME")   dir_display="~" ;;
        *)         dir_display="$cwd" ;;
    esac
else
    dir_display="?"
fi

# Git branch + dirty-state (staged/modified file counts), if $cwd is inside a
# repo. Both git calls use --no-optional-locks so neither ever contends with
# a concurrent git process (e.g. a running commit/rebase). Dirty state is NOT
# in the statusLine JSON payload, so it's computed here directly from
# `git status --porcelain`: for each line, the first column is index (staged)
# status and the second is worktree (unstaged/modified) status; a line whose
# column is neither blank nor "?" counts toward that bucket. Untracked files
# ("??") are deliberately excluded from both counts.
branch=""
dirty_staged=""
dirty_modified=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    status_output=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    if [ -n "$status_output" ]; then
        dirty_staged=$(printf '%s\n' "$status_output" | awk 'substr($0,1,1) !~ /[ ?]/ {c++} END{print c+0}')
        dirty_modified=$(printf '%s\n' "$status_output" | awk 'substr($0,2,1) !~ /[ ?]/ {c++} END{print c+0}')
    fi
fi

used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
# The session's name, only when the user set it (/rename or --name). Claude Code's
# session registry records nameSource "user" for those; pj's automatic name
# (CLAUDE_CODE_SESSION_NAME) leaves nameSource out and an unnamed session records
# "derived", so both stay bare. The input's session_name cannot tell them apart: it
# carries the AI title when there is no custom one (measured 2026-09-29). grep picks
# the record first, so a registry file caught mid-write cannot break the jq call.
session_label=""
reg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
if [ -n "$session_id" ] && [ -d "$reg_dir" ]; then
    reg_files=()
    while IFS= read -r f; do reg_files+=("$f"); done < <(grep -lF -- "$session_id" "$reg_dir"/*.json 2>/dev/null)
    if [ "${#reg_files[@]}" -gt 0 ]; then
        session_label=$(jq -r --arg s "$session_id" 'select(.sessionId == $s and .nameSource == "user") | .name // empty' "${reg_files[@]}" 2>/dev/null | tail -1 | LC_ALL=C tr -d '\000-\037\177')
    fi
fi
# Prompt cache, one jq call: warm flag, expiry epoch, hit ratio, miss count, ttl.
# ttl is Claude Code's own "5m" or "1h" (it differs by model and setup); "none" when
# absent, so no tab-separated field is ever empty and read cannot shift the columns.
read -r cache_warm cache_exp cache_hit cache_miss cache_ttl <<< "$(printf '%s' "$input" | jq -r '
    .prompt_cache // {} | [(if has("warm") then .warm else "none" end),(.expires_at // 0), (.hit_ratio // -1), (.misses // 0), ((.ttl // "none") | tostring)] | @tsv')"
# The ttl in seconds, or 0 when it is missing or not of the form <digits>m / <digits>h.
cache_ttl_s=0
case "$cache_ttl" in
    *m) n=${cache_ttl%m}; [[ "$n" =~ ^[0-9]+$ ]] && cache_ttl_s=$((n * 60)) ;;
    *h) n=${cache_ttl%h}; [[ "$n" =~ ^[0-9]+$ ]] && cache_ttl_s=$((n * 3600)) ;;
esac

# ANSI colors. Claude Code renders the whole status line dimmed itself, so
# plain (non-bold) color codes are used here rather than manually-dimmed ones.
C_MODEL='\033[36m'   # cyan
C_EFFORT='\033[94m'  # bright blue
C_DIR='\033[37m'     # white (most terminal themes render this as a soft light gray -- legible without the glare of bright white)
C_GIT='\033[32m'     # green
C_DIRTY='\033[91m'   # bright red (uncommitted changes)
C_SEP='\033[90m'     # gray
RESET='\033[0m'

# Colour by level: green under 50%, yellow under 80%, red from 80%.
level_color() {
    if [ "$1" -ge 80 ]; then printf '\033[91m'
    elif [ "$1" -ge 50 ]; then printf '\033[93m'
    else printf '\033[92m'; fi
}
# Gradient bar ($1 = percent, $2 = cells), rounded up so any usage above 0
# fills a cell. Each filled cell takes the 24-bit colour of its POSITION on a
# smooth green (74,222,128) -> yellow (250,204,21) -> red (239,68,68) ramp, so
# the leading edge changes colour as it fills; empty cells stay dim grey.
# Idea from LifeOS LIFEOS_StatusLine.sh; picked as preview 11 (W-20260923-A08).
grad_bar() {
    local n=$(( ($1 * $2 + 99) / 100 )) s="" i pos r g
    [ "$n" -gt "$2" ] && n=$2
    for ((i = 0; i < $2; i++)); do
        if [ "$i" -lt "$n" ]; then
            pos=$(( (i + 1) * 100 / $2 ))
            if [ "$pos" -le 50 ]; then
                r=$(( 74 + (250 - 74) * pos / 50 )); g=$(( 222 - (222 - 204) * pos / 50 ))
            else
                r=$(( 250 - (250 - 239) * (pos - 50) / 50 )); g=$(( 204 - (204 - 68) * (pos - 50) / 50 ))
            fi
            s="${s}\033[38;2;${r};${g};60m▰"
        else
            s="${s}\033[38;2;75;82;95m▱"
        fi
    done
    printf '%b' "$s$RESET"
}

segments=()
segments+=("$(printf "${C_MODEL}%s${RESET}" "$model")")

if [ -n "$effort" ]; then
    segments+=("$(printf "${C_EFFORT}%s${RESET}" "$effort")")
fi

segments+=("$(printf "${C_DIR}%s${RESET}" "$dir_display")")

if [ -n "$branch" ]; then
    segments+=("$(printf "${C_GIT}⎇ %s${RESET}" "$branch")")

    dirty=""
    if [ -n "$dirty_staged" ] && [ "$dirty_staged" -gt 0 ]; then
        dirty="+${dirty_staged}"
    fi
    if [ -n "$dirty_modified" ] && [ "$dirty_modified" -gt 0 ]; then
        [ -n "$dirty" ] && dirty="$dirty "
        dirty="${dirty}~${dirty_modified}"
    fi
    if [ -n "$dirty" ]; then
        segments+=("$(printf "${C_DIRTY}%s${RESET}" "$dirty")")
    fi
fi

if [ -n "$used" ]; then
    used_int=$(printf '%.0f' "$used")
    segments+=("ctx $(grad_bar "$used_int" 10) $(printf "$(level_color "$used_int")%s%%${RESET}" "$used_int")")
fi

sep="$(printf "${C_SEP} | ${RESET}")"
join_segments() {
    local out="" i
    for i in "${!segments[@]}"; do
        if [ "$i" -eq 0 ]; then
            out="${segments[$i]}"
        else
            out="${out}${sep}${segments[$i]}"
        fi
    done
    printf '%s' "$out"
}
line1=$(join_segments)

# Second line (W-20260923-A08): full session id, cost, prompt cache, then
# each rate-limit window as the same gradient bar as ctx, percentage and time
# until it resets (picked as preview 3).
# Time until an epoch second: 43m, 2h43m or 6d6h.
until_str() {
    local d=$(( $1 - $(date +%s) ))
    [ "$d" -lt 0 ] && d=0
    if [ "$d" -ge 86400 ]; then printf '%dd%dh' $((d / 86400)) $((d % 86400 / 3600))
    elif [ "$d" -ge 3600 ]; then printf '%dh%02dm' $((d / 3600)) $((d % 3600 / 60))
    else printf '%dm' $((d / 60)); fi
}
window() {
    local label=$1 pct reset=$3
    pct=$(printf '%.0f' "$2")
    printf '%s %s %s%s%%%b' "$label" "$(grad_bar "$pct" 10)" "$(level_color "$pct")" "$pct" "$RESET"
    [ -n "$reset" ] && printf ' ↻%s' "$(until_str "$reset")"
}

C_SESSION='\033[97m' # bright white
segments=()
if [ -n "$session_id" ]; then
    sid_txt="$(printf "${C_SESSION}%s${RESET}" "$session_id")"
    [ -n "$session_label" ] && sid_txt="${sid_txt}$(printf " ${C_SESSION}[ %s ]${RESET}" "$session_label")"
    segments+=("$sid_txt")
fi
if [ -n "$cost" ]; then
    segments+=("$(printf "\033[37m\$%.2f${RESET}" "$cost")")
fi
# Cache: time until the prompt cache goes cold, then hit ratio and misses.
# Cyan while warm, yellow in the last fifth of the cache's own ttl (12 min of a 1h
# cache, 1 min of a 5m one), red once cold. With no readable ttl it falls back to a
# fixed last 5 minutes and shows no /ttl. Absent before the first API response.
if [ "$cache_warm" = "true" ] || [ "$cache_warm" = "false" ]; then
    cache_left=$(( ${cache_exp%.*} - $(date +%s) ))
    if [ "$cache_warm" = "true" ] && [ "$cache_left" -gt 0 ]; then
        if [ "$cache_ttl_s" -gt 0 ]; then warn_at=$((cache_ttl_s / 5)); ttl_sfx="/$cache_ttl"; else warn_at=300; ttl_sfx=""; fi
        if [ "$cache_left" -le "$warn_at" ]; then c_cache='\033[93m'; else c_cache='\033[96m'; fi
        cache_txt="cache warm $(until_str "${cache_exp%.*}")${ttl_sfx}"
    else
        c_cache='\033[91m'
        cache_txt="cache cold"
    fi
    if [ "$cache_hit" != "-1" ]; then
        cache_txt="$cache_txt · $(awk -v h="$cache_hit" 'BEGIN{printf "%.0f", h * 100}')% hit"
    fi
    if [ "${cache_miss%.*}" -gt 0 ] 2>/dev/null; then
        cache_txt="$cache_txt · $cache_miss miss"
        [ "${cache_miss%.*}" -gt 1 ] && cache_txt="${cache_txt}es"
    fi
    segments+=("$(printf "${c_cache}%s${RESET}" "$cache_txt")")
    # The same countdown on this session's row in herdr's agents list (Gavin,
    # 19 Oct, dotfiles-main Q70: 1), through herdr-cache-report from the
    # dotfiles repo, which engage's status line calls too. It sends nothing
    # outside herdr and reports in the background.
    if command -v herdr-cache-report >/dev/null 2>&1; then
        herdr-cache-report --warm "$cache_warm" --expires "${cache_exp%.*}" --ttl "$cache_ttl_s"
    fi
fi
rl=""
if [ -n "$five" ]; then
    rl=$(window 5h "$five" "$five_reset")
fi
if [ -n "$week" ]; then
    [ -n "$rl" ] && rl="$rl$(printf "${C_SEP} · ${RESET}")"
    rl="${rl}$(window 7d "$week" "$week_reset")"
fi
[ -n "$rl" ] && segments+=("$rl")

# Agents this session spawned. Claude Code does not pass them to the status
# line, but writes <transcript minus .jsonl>/subagents/agent-*.meta.json for
# each one (name, agentType, color). Oldest first, first 3 in their own
# colour (type when unnamed), then +N for the rest. One jq call for all.
agent_dir="${transcript%.jsonl}/subagents"
if [ -n "$transcript" ] && [ -d "$agent_dir" ]; then
    metas=()
    while IFS= read -r m; do metas+=("$m"); done < <(ls -tr "$agent_dir"/*.meta.json 2>/dev/null)
    agents="" n_agents=0
    if [ "${#metas[@]}" -gt 0 ]; then
        while IFS=$'\t' read -r a_name a_color; do
            n_agents=$((n_agents + 1))
            [ "$n_agents" -gt 3 ] && continue
            case "$a_color" in
                red) c_agent='\033[91m' ;; green) c_agent='\033[92m' ;;
                yellow) c_agent='\033[93m' ;; blue) c_agent='\033[94m' ;;
                purple) c_agent='\033[95m' ;; cyan) c_agent='\033[96m' ;;
                orange) c_agent='\033[38;5;208m' ;; pink) c_agent='\033[38;5;213m' ;;
                *) c_agent='\033[37m' ;;
            esac
            [ -n "$agents" ] && agents="${agents}${C_SEP}, ${RESET}"
            agents="${agents}${c_agent}${a_name}${RESET}"
        done < <(jq -r '[(.name // .agentType // "agent"), (.color // "")] | @tsv' "${metas[@]}" 2>/dev/null)
    fi
    if [ "$n_agents" -gt 0 ]; then
        [ "$n_agents" -gt 3 ] && agents="${agents} ${C_SEP}+$((n_agents - 3))${RESET}"
        segments+=("$(printf "\033[37magents${RESET} %b" "$agents")")
    fi
fi
line2=$(join_segments)

if [ -n "$line2" ]; then
    printf '%s\n%s' "$line1" "$line2"
else
    printf '%s' "$line1"
fi
