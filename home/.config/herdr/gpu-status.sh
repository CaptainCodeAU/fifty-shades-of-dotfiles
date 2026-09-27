#!/bin/sh
# GPU + swap status for the mlbox-ubuntu 3090 box, shown in herdr's tab bar
# via a `command` status entry. Runs on whichever host the herdr server is on:
#
#   - on the 3090 box itself (WSL2, herdr under systemd --user): reads
#     nvidia-smi LOCALLY. SSH-ing to itself would be pointless and, under
#     systemd, has no agent to authenticate with anyway.
#   - anywhere else (the mini): reaches the GPU box over SSH on the LAN.
#
# The switch is the presence of the WSL nvidia-smi at its absolute path.
# Absolute path to nvidia-smi is required in BOTH branches: on that WSL box,
# /usr/lib/wsl/lib only lands on PATH through the box's own interactive zsh
# profile, which neither a plain non-interactive `ssh host "command"` nor a
# systemd service ever sources -- confirmed live 2026-08-28 (`ssh mlbox-ubuntu
# nvidia-smi` fails with "command not found", but the absolute path works).
#
# Kept deliberately short: herdr hides the whole tab_bar_right status area
# when the tab row is too narrow to fit it alongside the tabs, so a long
# string can silently show nothing instead of wrapping or truncating.
#
# Prints "PC off" when the box is asleep/unreachable, rather than blanking
# the entry -- that read as broken/no-signal, not "asleep." Does not wake
# it -- that's the `wakeup` alias's job, run by hand when actually needed.
#
# "PC off" is printed ONLY on positive evidence of a sleeping box (a timeout,
# "Host is down", "No route to host"). Until 2026-09-27 every ssh failure
# printed it, so a refused key, a changed host key or a config ssh could not
# find all read as "asleep". Now ssh's exit 255 (its own errors, never the
# remote command's) is split three ways from its stderr:
#
#   ⚪ PC off    timed out / host down / no route -- the box is asleep
#   🔑 3090 key "Permission denied" -- mlbox refused the key, or it is locked
#   3090 ssh?   anything else -- read the message by running this by hand
#
# "3090 ?" means ssh got through (or this is the box itself) but nvidia-smi
# returned no numbers.
#
# The white dot on "PC off" (2026-09-27) keeps the row the same shape as the
# green/yellow/red dots on a live reading.
#
# A truly-off box doesn't refuse the connection, it just goes silent until
# the timeout fires -- confirmed by the `wakeup` alias's own probe log
# ("Operation timed out", never "Connection refused"). That means there is
# no faster protocol to check first: a ping would hang the same way SSH
# does. The real cost is paying that timeout on every single 5-second tick
# while it's off, so BACKOFF_FILE caches "it was off" for BACKOFF_SECONDS
# and skips the network entirely during that window, then tries again for
# real -- most ticks become near-instant instead of ~1s each. Every failure
# backs off, not just a sleeping box, so a refused key does not hammer sshd
# every 5 seconds. The file holds "<epoch> <message>" so the window repeats
# the real reason; a bare "<epoch>" (the pre-2026-09-27 format) reads as
# "PC off".
#
# mlbox-gpu is a Host alias in ~/.ssh/config.local for a key that can do
# nothing but this query: its authorized_keys line on mlbox is
# `restrict,command="<the nvidia-smi + free line below>"`, so mlbox runs that
# whatever is asked (`ssh mlbox-gpu whoami` prints GPU numbers) and the key
# needs no passphrase. The main mlbox key has one and is never used here;
# IdentityAgent=none keeps the agent's keys out. The query is still sent so a
# test against an unrestricted host works too. Setup and restart notes:
# docs/HERDR.private.md (untracked, docs/*.private.md is gitignored).
#
# GPU_STATUS_HOST and GPU_STATUS_BACKOFF_FILE exist for testing each arm by
# hand; herdr sets neither.
GPU_HOST=${GPU_STATUS_HOST:-mlbox-gpu}
BACKOFF_FILE=${GPU_STATUS_BACKOFF_FILE:-/tmp/.gpu-status-mlbox-backoff}
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

NVSMI=/usr/lib/wsl/lib/nvidia-smi
NVSMI_ARGS="--query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits"

if [ -x "$NVSMI" ]; then
  # Local branch: this IS the GPU box. No network, so no backoff file and no
  # "PC off" -- an empty result here means the driver, not the LAN.
  output=$({ "$NVSMI" $NVSMI_ARGS; free -m | grep '^Swap:'; } 2>/dev/null) || output=""
  [ -n "$output" ] || { printf '3090 ?'; exit 0; }
else
  if [ -f "$BACKOFF_FILE" ]; then
    last_fail=0 last_msg=""
    { read -r last_fail last_msg < "$BACKOFF_FILE"; } 2>/dev/null || true
    case $last_fail in ''|*[!0-9]*) last_fail=0 ;; esac
    if [ $(( $(date +%s) - last_fail )) -lt "$BACKOFF_SECONDS" ]; then
      printf '%s' "${last_msg:-⚪ PC off}"
      exit 0
    fi
  fi

  rc=0
  output=$(ssh -o ConnectTimeout=1 -o BatchMode=yes -o IdentityAgent=none "$GPU_HOST" \
    "$NVSMI $NVSMI_ARGS; free -m | grep '^Swap:'" 2>&1) || rc=$?

  if [ "$rc" -eq 255 ]; then
    case $output in
      *'timed out'*|*'Host is down'*|*'No route to host'*) msg='⚪ PC off' ;;
      *'Permission denied'*) msg='🔑 3090 key' ;;
      *) msg='3090 ssh?' ;;
    esac
    printf '%s %s\n' "$(date +%s)" "$msg" > "$BACKOFF_FILE" 2>/dev/null || true
    printf '%s' "$msg"
    exit 0
  fi

  [ -e "$BACKOFF_FILE" ] && { rm -f "$BACKOFF_FILE" 2>/dev/null || true; }
fi

# Pick the two lines by shape, not position: stderr is merged above so it can
# be classified, and a success can still carry an ssh warning line first.
gpu_line=$(printf '%s\n' "$output" | grep -E '^ *[0-9]+, *[0-9]+, *[0-9]+ *$' | head -n 1 | tr -d ',')
swap_line=$(printf '%s\n' "$output" | grep '^Swap:' | head -n 1)

read -r util mem_used mem_total <<EOF
$gpu_line
EOF

[ -n "${util:-}" ] || { printf '3090 ?'; exit 0; }

swap_total=$(printf '%s' "$swap_line" | awk '{print $2}')
swap_used=$(printf '%s' "$swap_line" | awk '{print $3}')
swap_pct=0
if [ -n "${swap_total:-}" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
  swap_pct=$(awk -v u="$swap_used" -v t="$swap_total" 'BEGIN { printf "%.0f", (u/t)*100 }')
fi

# herdr's tab bar strips ANSI color codes (confirmed live 2026-08-28 -- a
# colored escape sequence rendered as literal "[93m...[0m" text; the 0.9.1
# CHANGELOG, #3001, strips them outright), so a colored circle emoji stands in
# for real color. Since 2026-09-27 EVERY number carries one, matching
# mac-status.sh beside it: green below 70%, yellow from 70, red from 90. VRAM's
# dot is its share of total VRAM. No " | " inside the reading: herdr's
# separator between this and the Mac reading is a bar.
dot() {
  if [ "$1" -ge 90 ] 2>/dev/null; then printf '🔴'
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf '🟡'
  else printf '🟢'
  fi
}

vram_pct=0
if [ -n "${mem_total:-}" ] && [ "$mem_total" -gt 0 ] 2>/dev/null; then
  vram_pct=$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN { printf "%.0f", (u/t)*100 }')
fi
if [ "$mem_used" -ge 1024 ] 2>/dev/null; then
  vram=$(awk -v u="$mem_used" 'BEGIN { printf "%.1fG", u/1024 }')
else
  vram="${mem_used}M"
fi

title="3090 $(dot "$util")${util}% $(dot "$vram_pct")${vram}"

# Swap is worth mentioning only once it's actually eating into real memory;
# below 15% it's normal and adds noise: yellow from 15-44%, red from 45% up.
if [ "$swap_pct" -ge 45 ]; then
  title="$title 🔴SWAP ${swap_pct}%"
elif [ "$swap_pct" -ge 15 ]; then
  title="$title 🟡SWAP ${swap_pct}%"
fi

printf '%s' "$title"
