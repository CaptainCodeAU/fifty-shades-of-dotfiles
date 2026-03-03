#!/usr/bin/env bash

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
B='\033[0;34m'
M='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[0;90m'
BOLD='\033[1m'
RST='\033[0m'

# Symbols
BAR_FULL="█"
BAR_EMPTY="░"
DOT="●"
ARROW="▸"

bar() {
  local pct=$1 width=${2:-30} color=$3
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  printf "${color}"
  for ((i=0; i<filled; i++)); do printf "$BAR_FULL"; done
  printf "${D}"
  for ((i=0; i<empty; i++)); do printf "$BAR_EMPTY"; done
  printf "${RST}"
}

divider() {
  printf "  ${D}"
  printf '%*s' 80 '' | tr ' ' '─'
  printf "${RST}\n"
}

header() {
  echo ""
  printf "  ${BOLD}${C}${1}${RST}  ${D}${2}${RST}\n"
  divider
}

# ── System Info ──────────────────────────────────────────
hostname=$(scutil --get ComputerName 2>/dev/null || hostname -s)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
uptime_str=$(uptime | sed 's/.*up //' | sed 's/,.*//')
os_ver=$(sw_vers -productVersion 2>/dev/null)

echo ""
printf "  ${C}┌──────────────────────────────────────────────────────────────────────┐${RST}\n"
printf "  ${C}│${RST}  ${W}${BOLD}⚡ System Monitor${RST}                                                   ${C}│${RST}\n"
printf "  ${C}│${RST}  ${D}%-70s${RST}${C}│${RST}\n" "${hostname} · macOS ${os_ver} · up ${uptime_str}"
printf "  ${C}└──────────────────────────────────────────────────────────────────────┘${RST}\n"

# ── Memory ───────────────────────────────────────────────
total_bytes=$(sysctl -n hw.memsize)
total_gb=$(echo "$total_bytes" | awk '{printf "%.1f", $1/1073741824}')

phys=$(top -l 1 | grep PhysMem | head -1)
used_gb=$(echo "$phys" | grep -oE '[0-9]+G used' | grep -oE '[0-9]+')
free_val=$(echo "$phys" | grep -oE '[0-9]+M unused' | grep -oE '[0-9]+')

if [ -z "$used_gb" ]; then
  used_mb=$(echo "$phys" | grep -oE '[0-9]+M used' | grep -oE '[0-9]+')
  used_gb=$(echo "$used_mb" | awk '{printf "%.1f", $1/1024}')
fi
free_gb=$(echo "$free_val" | awk '{printf "%.1f", $1/1024}')
mem_pct=$(echo "$used_gb $total_gb" | awk '{printf "%d", ($1/$2)*100}')

if [ "$mem_pct" -gt 90 ]; then
  mem_color=$R; mem_status="CRITICAL"
elif [ "$mem_pct" -gt 75 ]; then
  mem_color=$Y; mem_status="MODERATE"
else
  mem_color=$G; mem_status="HEALTHY"
fi

pressure_free=$(memory_pressure 2>/dev/null | grep "free percentage" | grep -oE '[0-9]+' | tail -1)

header "💾 Memory" "${total_gb} GB total"
printf "  ${ARROW} Used: ${W}${used_gb} GB${RST} ${D}/${RST} ${D}${total_gb} GB${RST}     Free: ${G}${free_gb} GB${RST}\n"
printf "  "
bar "$mem_pct" 44 "$mem_color"
printf "  ${mem_color}${mem_pct}%%  ${BOLD}${mem_status}${RST}\n"
printf "  ${ARROW} Pressure: ${G}${pressure_free}%% free${RST}   ${D}Swap: none${RST}\n"

# ── CPU ──────────────────────────────────────────────────
cpu_line=$(top -l 1 | grep "CPU usage" | head -1)
user_pct=$(echo "$cpu_line" | grep -oE '[0-9.]+% user' | grep -oE '[0-9.]+')
sys_pct=$(echo "$cpu_line" | grep -oE '[0-9.]+% sys' | grep -oE '[0-9.]+')
idle_pct=$(echo "$cpu_line" | grep -oE '[0-9.]+% idle' | grep -oE '[0-9.]+')
total_cpu=$(echo "$user_pct $sys_pct" | awk '{printf "%d", $1+$2}')
load_avg=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')

if [ "$total_cpu" -gt 80 ]; then
  cpu_color=$R
elif [ "$total_cpu" -gt 50 ]; then
  cpu_color=$Y
else
  cpu_color=$G
fi

header "🧠 CPU" "${chip}"
printf "  ${ARROW} User: ${C}${user_pct}%%${RST}   Sys: ${M}${sys_pct}%%${RST}   Idle: ${G}${idle_pct}%%${RST}\n"
printf "  "
bar "$total_cpu" 44 "$cpu_color"
printf "  ${cpu_color}${total_cpu}%%${RST}\n"
printf "  ${ARROW} Load avg: ${W}${load_avg}${RST}\n"

# ── Ollama ───────────────────────────────────────────────
header "🤖 Ollama" ""

ollama_running=$(pgrep -x ollama 2>/dev/null | head -1)
if [ -n "$ollama_running" ]; then
  printf "  ${DOT} ${G}Server running${RST}  ${D}PID: ${ollama_running}${RST}\n"

  ollama_ps=$(ollama ps 2>/dev/null | tail -n +2)
  if [ -n "$ollama_ps" ]; then
    model_count=$(echo "$ollama_ps" | wc -l | tr -d ' ')
    printf "  ${DOT} ${C}${model_count} model(s) loaded${RST}\n\n"
    echo -e "  ${D}$(printf '%-38s' 'NAME')$(printf '%8s' 'SIZE')$(printf '%13s' 'PROCESSOR')$(printf '%10s' 'CONTEXT')$(printf '%10s' 'UNTIL')${RST}"
    divider
    echo "$ollama_ps" | while IFS= read -r line; do
      name=$(echo "$line" | awk '{print $1}')
      size=$(echo "$line" | awk '{print $3, $4}')
      proc=$(echo "$line" | awk '{print $5, $6}')
      ctx=$(echo "$line" | awk '{print $7}')
      until=$(echo "$line" | awk '{print $8}')
      echo -e "  ${W}$(printf '%-38s' "$name")${RST}${M}$(printf '%8s' "$size")${RST}${C}$(printf '%13s' "$proc")${RST}${D}$(printf '%10s' "$ctx")${RST}${G}$(printf '%10s' "$until")${RST}"
    done
  else
    printf "  ${DOT} ${Y}No models loaded${RST}\n"
  fi
else
  printf "  ${DOT} ${R}Server not running${RST}\n"
fi

# ── App Memory Totals ────────────────────────────────────
header "📦 App Totals" "grouped memory"

ps -eo rss,comm | tail -n +2 | awk '{
  rss=$1; cmd=$2
  sub(".*/", "", cmd)
  if (cmd ~ /^Brave/) app="Brave"
  else if (cmd ~ /^Cursor/) app="Cursor"
  else if (cmd ~ /^claude/) app="Claude"
  else if (cmd ~ /^ollama/) app="Ollama"
  else if (cmd ~ /^iTerm/) app="iTerm2"
  else if (cmd ~ /^Finder/) app="Finder"
  else if (cmd ~ /^WindowServer/) app="WindowServer"
  else if (cmd ~ /^BDLDaemon/) app="Bitdefender"
  else app=""
  if (app != "") totals[app] += rss
}
END {
  for (app in totals) {
    mb = totals[app] / 1024
    if (mb > 1024)
      printf "%.0f|%s|%.1f GB\n", mb, app, mb/1024
    else
      printf "%.0f|%s|%d MB\n", mb, app, mb
  }
}' | sort -t'|' -k1 -rn | while IFS='|' read -r sortval app size; do
  if echo "$size" | grep -q "GB"; then
    c=$R
  else
    num=$(echo "$size" | grep -oE '[0-9]+')
    if [ "$num" -gt 500 ] 2>/dev/null; then
      c=$Y
    else
      c=$G
    fi
  fi
  echo -e "  ${W}$(printf '%-18s' "$app")${RST} ${c}$(printf '%10s' "$size")${RST}"
done

# ── Top Processes by Memory ──────────────────────────────
header "📊 Top Processes" "by memory"
printf "  ${D}$(printf '%-8s' 'PID')$(printf '%10s' 'MEM')  %-40s${RST}\n" "PROCESS"
divider

ps -eo pid,rss,comm | sort -k2 -rn | head -12 | while read -r pid rss cmd; do
  [ -z "$pid" ] && continue
  mb=$(echo "$rss" | awk '{printf "%d", $1/1024}')
  short_cmd=$(echo "$cmd" | sed 's|.*/||')

  if [ "$mb" -gt 1000 ]; then
    c=$R; size=$(echo "$mb" | awk '{printf "%.1f GB", $1/1024}')
  elif [ "$mb" -gt 500 ]; then
    c=$R; size="${mb} MB"
  elif [ "$mb" -gt 200 ]; then
    c=$Y; size="${mb} MB"
  else
    c=$G; size="${mb} MB"
  fi

  echo -e "  ${D}$(printf '%-8s' "$pid")${RST}${c}$(printf '%10s' "$size")${RST}  ${W}${short_cmd}${RST}"
done

# ── Top Processes by CPU ─────────────────────────────────
header "🔥 Top Processes" "by CPU"
printf "  ${D}$(printf '%-8s' 'PID')$(printf '%8s' 'CPU')  %-40s${RST}\n" "PROCESS"
divider

ps -eo pid,pcpu,comm -r | head -6 | tail -5 | while read -r pid cpu cmd; do
  [ -z "$pid" ] && continue
  short_cmd=$(echo "$cmd" | sed 's|.*/||')
  cpu_int=$(echo "$cpu" | awk '{printf "%d", $1}')

  if [ "$cpu_int" -gt 50 ]; then
    c=$R
  elif [ "$cpu_int" -gt 20 ]; then
    c=$Y
  else
    c=$G
  fi

  echo -e "  ${D}$(printf '%-8s' "$pid")${RST}${c}$(printf '%7s%%' "$cpu")${RST}  ${W}${short_cmd}${RST}"
done

# ── Services ─────────────────────────────────────────────
header "⚙️  LaunchAgents" "ollama"
launchctl list 2>/dev/null | grep ollama | while read -r pid status label; do
  if [ "$pid" != "-" ]; then
    printf "  ${DOT} ${G}running${RST}  ${W}%-35s${RST} ${D}PID: ${pid}${RST}\n" "$label"
  else
    if [ "$status" = "0" ]; then
      printf "  ${DOT} ${C}done${RST}     ${W}%-35s${RST} ${D}exit: ${status}${RST}\n" "$label"
    else
      printf "  ${DOT} ${R}error${RST}    ${W}%-35s${RST} ${D}exit: ${status}${RST}\n" "$label"
    fi
  fi
done

echo ""
printf "  ${D}Generated at $(date '+%Y-%m-%d %H:%M:%S')${RST}\n"
echo ""
