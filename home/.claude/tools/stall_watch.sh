#!/bin/sh
# stall_watch.sh -- wake the conductor when a worker's OUTPUT goes quiet, the worker dies, or every
# watched path says it is finished.
#
# Usage:
#   sh ~/.claude/tools/stall_watch.sh [--once] [--pidfile FILE] [--interval SECS] <quiet-minutes> <path>...
#
#   <path>...        files or dirs the worker writes to (name every dir in the worker's brief).
#                    ONE WATCH PER WORKER: under --once the first STALL on ANY path ends the whole watch
#                    and leaves the other paths unwatched.
#   --once           exit 0 on the first STALL, DEAD, NOPATH or "DONE all" line (the four lines that end it).
#                    Use this under plain background Bash: the exit is what wakes the parent. Without --once
#                    the script runs until every path is finished, and is meant for a line-notifying Monitor,
#                    piped through grep --line-buffered '^STALL\|^DEAD\|^NOPATH\|^DONE'.
#   --pidfile FILE   if FILE exists and its PID is no longer alive, emit DEAD (checked every interval,
#                    BEFORE any path is looked at, so DEAD never waits on a quiet window).
#                    The worker must be told to write its job PID there; a parent cannot discover it.
#   --interval SECS  poll interval, default 30.
#
# Finishing a path (A42): the worker marks each path it is done with, and that path stops being watched,
# so a finished worker no longer ends in a false STALL one quiet window later.
#   a file        its last non-blank line is exactly DONE or status: DONE, or a file <path>.done appears
#   a directory   a file <dir>/.done appears in it
# A marker must be newer than ARMED: one left over from an earlier run prints OLDDONE and is ignored until
# it is rewritten. When every path is finished the watch prints "DONE all" and exits 0, --once or not.
#
# Output lines (one per event):
#   ARMED <path> exists=yes|no HH:MM  printed once per path at start, so a wrong path is visible immediately
#   CHANGE <path> HH:MM              the path (or something one level under it) was modified, or a path
#                                    missing at ARMED appeared
#   NOTYET <path> since HH:MM        the path has NOT changed since ARMED for one quiet window (a publish
#                                    dir that the worker writes only at the end looks like this; not a stall).
#                                    Repeated at 2x; escalates to STALL at 3x the quiet window.
#   STALL <path> quiet since HH:MM   no modification for <quiet-minutes> AFTER at least one CHANGE (or NOTYET
#                                    for 3x the window); RE-ARMS after another window, so a second stall is reported too
#   NOPATH <path> HH:MM              the path does not exist (printed instead of STALL; re-checked each interval).
#                                    A path that existed and vanished: at once. A path missing at ARMED: only
#                                    when it is still missing one quiet window after ARMED (A30).
#   SKEW <path> HH:MM                a file's mtime is in the future; clamped to now so the watch cannot go mute
#   NOPID <pidfile> HH:MM            --pidfile given but the file has not appeared after one interval (once)
#   DEAD <pidfile> pid <n> HH:MM     the pidfile's process is gone
#   DONE <path> HH:MM                the path carries a finish marker; it is no longer watched
#   DONE all HH:MM                   every path is finished; the watch exits 0
#   OLDDONE <path> HH:MM             a finish marker older than ARMED; ignored until rewritten (once per path)
#
# Why this exists (2026-09-13, win_go_app_test, five stalls in one day, worst 26 min): a worker's idle
# notice fires when the WORKER goes idle, not when a job it started finishes. A "waiter" armed inside a
# turn dies with that turn. A finished result nobody reads is indistinguishable from a running one.
# The only reliable signal is the artefact. Watch the output, never the worker.
#
# Hardening 1 (2026-09-13, hand-off critique probes T1-T4): a STALL used to disarm the watch for good;
# a future mtime made "now - last" negative forever (permanent silence); a missing path printed the same
# STALL as a real stall; a pidfile that never appeared was a silent no-op. All four fixed.
#
# Hardening 2, H2-03 (2026-09-13, seeds W3-17 + H2-03b): a path that had never changed since ARMED
# (a publish dir written only at the very end) produced a STALL one quiet window after arming and woke
# the conductor into a still-running slice (18:26). Now: never-changed = NOTYET; the stall clock starts at
# the first CHANGE; NOTYET escalates to STALL at 3x the window (a worker that writes NOTHING for that long
# is worth a look). The mtime read is the dir node plus ONE level (a per-file find over a 326-tree scratch
# dir every 30 s was a stat storm); a worker's brief therefore names the dir it writes INTO, not an
# ancestor. DEAD is checked before any path on every tick.
#
# Finish signal, W-20260924-A42 and A30 (2026-09-24): of 101 background watches audited that day, 43 ended
# in STALL and about 17 of those fired after the worker had already finished; a watch armed in the same
# turn as the dispatch ended on its first tick with NOPATH because the worker had not written yet.
# Moved into the dotfiles repo the same day (D-20260920-A09); regression tests: stall_watch-selftest.
#
# Probe aid: STALL_WATCH_UNIT=<secs> makes one "minute" that many seconds (default 60). Probes only.
#
# Portability: macOS/BSD and GNU/Linux (stat and date differ; detected at start).
# Shell note: never name a variable `status` in zsh (read-only; silent failure).

once=0; pidfile=""; interval=30
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --pidfile) [ $# -ge 2 ] || { echo "stall_watch.sh: --pidfile needs a value" >&2; exit 2; }; pidfile="$2"; shift 2 ;;
    --interval) [ $# -ge 2 ] || { echo "stall_watch.sh: --interval needs a value" >&2; exit 2; }; interval="$2"; shift 2 ;;
    -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) echo "stall_watch.sh: unknown flag $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
usage="usage: stall_watch.sh [--once] [--pidfile FILE] [--interval SECS] <quiet-minutes> <path>..."
case "$interval" in ''|*[!0-9]*|0) echo "stall_watch.sh: --interval must be a whole number of seconds above 0" >&2; exit 2 ;; esac
quiet_min="$1"; shift
case "$quiet_min" in ''|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
[ $# -ge 1 ] || { echo "$usage" >&2; exit 2; }
unit="${STALL_WATCH_UNIT:-60}"
quiet=$((quiet_min * unit))

if stat -f %m / >/dev/null 2>&1; then
  mtime() { stat -f %m "$@" 2>/dev/null; }
  hhmm_at() { date -r "$1" '+%H:%M'; }
else
  mtime() { stat -c %Y "$@" 2>/dev/null; }
  hhmm_at() { date -d "@$1" '+%H:%M'; }
fi
stamp() { date '+%H:%M'; }
# newest mtime of the node itself plus its immediate children (one level, no recursion)
newest_mtime() {
  if [ -d "$1" ]; then
    { mtime "$1"; find "$1" -mindepth 1 -maxdepth 1 -exec sh -c 'stat -f %m "$@" 2>/dev/null || stat -c %Y "$@" 2>/dev/null' _ {} + ; } | sort -n | tail -1
  else
    mtime "$1"
  fi
}
# mtime of the path's finish marker, or nothing when it has none (see "Finishing a path" above)
marker_mtime() {
  _mp="${1%/}"
  if [ -d "$_mp" ]; then
    [ -f "$_mp/.done" ] && mtime "$_mp/.done"
    return 0
  fi
  if [ -e "$_mp.done" ]; then mtime "$_mp.done"; return 0; fi
  if [ -f "$_mp" ]; then
    _ml=$(tail -n 20 "$_mp" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)
    case "$_ml" in DONE|'status: DONE') mtime "$_mp" ;; esac
  fi
  return 0
}

check_pid() {
  [ -n "$pidfile" ] || return 0
  if [ -f "$pidfile" ]; then
    pid=$(head -1 "$pidfile" | tr -dc '0-9')
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "DEAD $pidfile pid $pid $(stamp)"
      [ "$once" = 1 ] && exit 0
      pidfile=""   # report once
    fi
  elif [ "$pid_warned" = 0 ] && [ "$ticks" -ge 1 ]; then
    echo "NOPID $pidfile $(stamp)"; pid_warned=1
  fi
}

armed=$(date +%s)
npaths=$#; ndone=0
i=0
for p in "$@"; do
  i=$((i+1)); eval "last_$i=$armed"; eval "changed_$i=0"; eval "notyet_$i=0"; eval "skewed_$i=0"; eval "raw_$i=unset"
  eval "seen_$i=0"; eval "done_$i=0"; eval "olddone_$i=0"
  # baseline mtime is read AT arming, so a write between ARMED and the first tick is a CHANGE, not the baseline
  if [ -e "$p" ]; then m0=$(newest_mtime "$p"); [ -z "$m0" ] && m0=0; eval "raw_$i=$m0"; eval "seen_$i=1"; echo "ARMED $p exists=yes $(stamp)"; else echo "ARMED $p exists=no $(stamp)"; fi
done
pid_warned=0; ticks=0
check_pid

while :; do
  sleep "$interval"; ticks=$((ticks+1))
  check_pid
  i=0
  for p in "$@"; do
    i=$((i+1))
    eval "fin=\$done_$i"
    [ "$fin" = 1 ] && continue
    eval "last=\$last_$i"; eval "changed=\$changed_$i"; eval "notyet=\$notyet_$i"; eval "skewed=\$skewed_$i"; eval "raw=\$raw_$i"
    eval "seen=\$seen_$i"; eval "olddone=\$olddone_$i"
    now=$(date +%s)
    # a finish marker retires the path before anything else is read; a stale one is named once and ignored
    mm=$(marker_mtime "$p")
    if [ -n "$mm" ] && [ "$mm" -ge "$armed" ]; then
      echo "DONE $p $(stamp)"; eval "done_$i=1"; ndone=$((ndone+1))
      if [ "$ndone" -ge "$npaths" ]; then echo "DONE all $(stamp)"; exit 0; fi
      continue
    elif [ -n "$mm" ] && [ "$olddone" = 0 ]; then
      echo "OLDDONE $p $(stamp)"; eval "olddone_$i=1"
    fi
    if [ ! -e "$p" ]; then
      # missing since ARMED: the worker may not have written yet, so wait one quiet window (A30)
      if [ "$seen" = 0 ] && [ $((now - armed)) -lt "$quiet" ]; then continue; fi
      echo "NOPATH $p $(stamp)"
      [ "$once" = 1 ] && exit 0
      continue
    fi
    m=$(newest_mtime "$p"); [ -z "$m" ] && m=0
    # change detection uses the RAW newest mtime (a future-dated file counts once, not every tick);
    # the stall clock uses the mtime clamped to now, so a future mtime can never mute the watch
    if [ "$m" -gt "$now" ]; then
      [ "$skewed" = 0 ] && { echo "SKEW $p $(stamp)"; eval "skewed_$i=1"; }
      clamped=$now
    else
      clamped=$m
    fi
    if [ "$seen" = 0 ]; then
      # appeared after ARMED: that is the worker's first write
      eval "seen_$i=1"; eval "raw_$i=$m"; eval "last_$i=$now"; eval "changed_$i=1"; eval "notyet_$i=0"; echo "CHANGE $p $(stamp)"
      continue
    fi
    if [ "$raw" = unset ]; then eval "raw_$i=$m"; raw=$m; fi
    if [ "$m" != "$raw" ] && [ "$clamped" -ge "$last" ]; then
      eval "raw_$i=$m"; eval "last_$i=$clamped"; eval "changed_$i=1"; eval "notyet_$i=0"; echo "CHANGE $p $(stamp)"
    elif [ "$m" != "$raw" ]; then
      eval "raw_$i=$m"
    elif [ "$changed" = 0 ]; then
      # never changed since ARMED: NOTYET at 1x and 2x the window, STALL at 3x
      since=$((now - armed))
      if [ "$since" -ge $((3 * quiet)) ]; then
        echo "STALL $p quiet since $(hhmm_at "$armed") (never changed since ARMED, 3x window)"
        [ "$once" = 1 ] && exit 0
        eval "changed_$i=1"; eval "last_$i=$now"
      elif [ "$since" -ge $((2 * quiet)) ] && [ "$notyet" -lt 2 ]; then
        echo "NOTYET $p since $(hhmm_at "$armed") (2x window, no change yet)"; eval "notyet_$i=2"
      elif [ "$since" -ge "$quiet" ] && [ "$notyet" -lt 1 ]; then
        echo "NOTYET $p since $(hhmm_at "$armed")"; eval "notyet_$i=1"
      fi
    elif [ $((now - last)) -ge "$quiet" ]; then
      # first stall, or re-armed stall: report, then push `last` forward so the next report
      # comes after another full quiet window rather than every interval
      echo "STALL $p quiet since $(hhmm_at "$last")"
      [ "$once" = 1 ] && exit 0
      eval "last_$i=$now"
    fi
  done
done
