#!/bin/sh
# GPU + swap status for the mlbox-ubuntu 3090 box, shown in herdr's tab bar
# via a `command` status entry. Runs on the herdr server (the mini),
# reaches the GPU box over SSH on the LAN.
#
# Absolute path to nvidia-smi is required: on that WSL box, /usr/lib/wsl/lib
# only lands on PATH through the box's own interactive zsh profile, which a
# plain non-interactive `ssh host "command"` never sources -- confirmed
# live 2026-08-28 (`ssh mlbox-ubuntu nvidia-smi` fails with "command not
# found", but the absolute path works).
#
# Kept deliberately short: herdr hides the whole tab_bar_right status area
# when the tab row is too narrow to fit it alongside the tabs, so a long
# string can silently show nothing instead of wrapping or truncating.
#
# Prints "PC off" when the box is asleep/unreachable, rather than blanking
# the entry -- that read as broken/no-signal, not "asleep." Does not wake
# it -- that's the `wakeup` alias's job, run by hand when actually needed.
#
# A truly-off box doesn't refuse the connection, it just goes silent until
# the timeout fires -- confirmed by the `wakeup` alias's own probe log
# ("Operation timed out", never "Connection refused"). That means there is
# no faster protocol to check first: a ping would hang the same way SSH
# does. The real cost is paying that timeout on every single 5-second tick
# while it's off, so BACKOFF_FILE caches "it was off" for BACKOFF_SECONDS
# and skips the network entirely during that window, then tries again for
# real -- most ticks become near-instant instead of ~1s each.
BACKOFF_FILE=/tmp/.gpu-status-mlbox-backoff
BACKOFF_SECONDS=30
#
# herdr's server runs as a launchd/brew-services daemon with NO $HOME in
# its environment (confirmed via `launchctl print` 2026-08-28) -- so ssh
# can't find ~/.ssh/config, which is what makes "mlbox-ubuntu" resolve to
# anything at all. That's why this produced no output at all rather than
# an SSH error: `set -eu` plus `|| exit 0` on the ssh call turned that
# failure into a silent, empty result. Falling back to the password
# database (not hardcoding the path) keeps this working if ever run by a
# different user or on a different machine.
: "${HOME:=$(eval echo "~$(id -un)")}"
export HOME

set -eu

if [ -f "$BACKOFF_FILE" ]; then
  last_fail=$(cat "$BACKOFF_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$((now - last_fail))
  if [ "$age" -lt "$BACKOFF_SECONDS" ]; then
    printf 'PC off'
    exit 0
  fi
fi

output=$(ssh -o ConnectTimeout=1 -o BatchMode=yes mlbox-ubuntu \
  "/usr/lib/wsl/lib/nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits; free -m | grep '^Swap:'" \
  2>/dev/null) || { date +%s > "$BACKOFF_FILE" 2>/dev/null || true; printf 'PC off'; exit 0; }

[ -n "$output" ] || { date +%s > "$BACKOFF_FILE" 2>/dev/null || true; printf 'PC off'; exit 0; }

rm -f "$BACKOFF_FILE" 2>/dev/null || true

gpu_line=$(printf '%s\n' "$output" | sed -n '1p' | tr -d ',')
swap_line=$(printf '%s\n' "$output" | sed -n '2p')

read -r util mem_used mem_total <<EOF
$gpu_line
EOF

[ -n "${util:-}" ] || exit 0

swap_total=$(printf '%s' "$swap_line" | awk '{print $2}')
swap_used=$(printf '%s' "$swap_line" | awk '{print $3}')
swap_pct=0
if [ -n "${swap_total:-}" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
  swap_pct=$(awk -v u="$swap_used" -v t="$swap_total" 'BEGIN { printf "%.0f", (u/t)*100 }')
fi

title="GPU ${util}% | ${mem_used}M"

# Swap is worth mentioning only once it's actually eating into real memory;
# below 15% it's normal and adds noise. herdr's tab bar strips ANSI color
# codes (confirmed live 2026-08-28 -- a colored escape sequence rendered as
# literal "[93m...[0m" text), so a colored circle emoji stands in for real
# color: yellow from 15-44%, red from 45% up.
if [ "$swap_pct" -ge 45 ]; then
  title="$title | 🔴 SWAP ${swap_pct}%"
elif [ "$swap_pct" -ge 15 ]; then
  title="$title | 🟡 SWAP ${swap_pct}%"
fi

printf '%s' "$title"
