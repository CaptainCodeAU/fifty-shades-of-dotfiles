#!/bin/sh
# CPU, GPU and memory for THIS Mac, shown in herdr's tab bar next to the 3090
# reading (gpu-status.sh) via a `command` status entry. Added 2026-09-27.
#
# The same config.toml is stowed on the Linux/WSL box, where this prints
# nothing and exits 0: the reading only means anything on macOS.
#
# herdr strips ANSI colour from status commands (0.9.1 CHANGELOG, #3001), so a
# coloured dot carries the level, on EVERY number so the row reads evenly:
# green below 70%, yellow from 70, red from 90. Memory is the exception: its
# dot is macOS's own pressure state (kern.memorystatus_vm_pressure_level:
# 1 normal, 2 warn, 4 critical), the one Activity Monitor's graph draws, and
# its number is 100 minus kern.memorystatus_level (percent available).
#
# Sources, all without root (measured 2026-09-27 on an M4):
#   CPU  iostat, one fresh 1 s sample (user + system). This is most of the
#        run time; the first iostat line is the since-boot average, so skip it.
#   GPU  ioreg IOAccelerator "Device Utilization %", about 0.01 s.
#   MEM  two sysctls, about 0.001 s.
#
# herdr's daemon has a minimal environment, so PATH is set here rather than
# trusted.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

[ "$(uname -s)" = Darwin ] || exit 0

dot() {
  if [ "$1" -ge 90 ] 2>/dev/null; then printf '🔴'
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf '🟡'
  else printf '🟢'
  fi
}

cpu=$(iostat -n0 -c 2 -w 1 2>/dev/null | tail -n 1 | awk '{print $1 + $2}')
gpu=$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null \
  | grep -o '"Device Utilization %"=[0-9]*' | head -n 1 | cut -d= -f2)
free_pct=$(sysctl -n kern.memorystatus_level 2>/dev/null)
level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)

case $level in
  1) mem_dot='🟢' ;;
  2) mem_dot='🟡' ;;
  4) mem_dot='🔴' ;;
  *) mem_dot='' ;;
esac

out="Mac"
[ -n "$cpu" ] && out="$out CPU $(dot "$cpu")${cpu}%" || out="$out CPU ?"
[ -n "$gpu" ] && out="$out GPU $(dot "$gpu")${gpu}%" || out="$out GPU ?"
if [ -n "$free_pct" ]; then
  out="$out MEM ${mem_dot}$((100 - free_pct))%"
else
  out="$out MEM ?"
fi

printf '%s' "$out"
