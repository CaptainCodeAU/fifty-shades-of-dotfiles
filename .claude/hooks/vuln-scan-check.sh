#!/usr/bin/env bash
# SessionStart hook (read-only): are any INSTALLED packages carrying known CVEs?
#
# WHY THIS IS NOT JUST A PRINTED WARNING
#   Gavin's stated problem: "sometimes I may forget to scroll up and see the result,
#   and I might miss it." A line printed at session start competes with six other
#   startup lines and loses. So on a HIGH/CRITICAL finding this hook does not merely
#   print -- it INSTRUCTS the assistant to raise the finding as a tracked task before
#   doing anything else. Startup text is skimmed; a task survives the scroll.
#
# WHY IT NEVER SCANS INLINE
#   A cold database is 231 packages at a few seconds each. `vuln-scan --fast` checks
#   at most a dozen inline and detaches anything larger, so this hook is bounded to
#   roughly a second in the normal case. A session-start check that stalls the
#   session is a check that gets removed.
#
# GUARANTEES (mirrors toolchain-cve-check.sh)
#   - read-only    : no repo writes; the scan DB and briefing live under ~/.local/state
#   - never blocks : always exits 0, degrades cleanly when the tool or network is absent
#   - exception-only: silent when there is nothing to act on
set -uo pipefail

command -v vuln-scan >/dev/null 2>&1 || exit 0

# --fast is the shell-safe door: bounded inline work, background for the rest.
# NO_COLOR because this output is parsed here and read by the assistant, not a tty.
out=$(NO_COLOR=1 timeout 90 vuln-scan --fast --no-progress 2>/dev/null)
rc=$?
[ -z "$out" ] && exit 0

# A backlog was deferred to a detached scan. Say so plainly -- an absent verdict is
# not an all-clear, and the assistant must not read silence as "nothing to worry about".
if printf '%s' "$out" | grep -qE 'need checking|already running'; then
  printf '🔐 %s\n' "$(printf '%s' "$out" | head -1)"
  echo "    (results land in a later session; this session has no complete verdict yet)"
  exit 0
fi

# Gate on the EXIT CODE alone, never on a string in the output. rc=1 IS "something is
# actionable" -- that is the tool's contract. The previous `grep -q 'EXPOSED'` broke the
# moment vuln-scan split its banner into ACTION NEEDED + EXPOSED, BELOW ACTION THRESHOLD:
# when everything actionable is high-severity there is no "EXPOSED" line at all, so the
# grep failed and this whole guidance block silently vanished while rc was still 1.
# A watcher keyed to wording dies the day the wording changes, and reports healthy.
if [ "$rc" -eq 1 ]; then
  briefing="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vuln-briefing.md"
  echo "🔐 Installed packages with known vulnerabilities:"
  printf '%s\n' "$out" | grep -v '^vuln-scan:' | sed 's/^/   /'
  echo
  echo "    ASSISTANT — ACT ON THIS BEFORE OTHER WORK:"
  echo "    1. Create a task for each ACTION NEEDED package above so it survives the scroll."
  echo "       Gavin has said he misses startup output; a printed line alone is not enough."
  echo "       Anything under 'EXPOSED, BELOW ACTION THRESHOLD' is LIVE and UNFIXED too --"
  echo "       it is merely under CVSS 7.0 and so absent from the briefing. Quieter, not safe."
  echo "    2. Read $briefing for CVSS scores, descriptions and blast radius."
  echo "    3. For a package whose Homebrew revision is > 0, the fix may ALREADY be applied:"
  echo "       Homebrew backports patches without changing the upstream version, so NVD"
  echo "       keeps reporting it vulnerable. The briefing lists the patch commits that"
  echo "       could not be matched to a CVE -- read them before telling Gavin to upgrade."
  echo "       Telling him to fix what he already fixed is how this alert stops being read."
  echo "    4. Only then recommend an action. \`vuln-scan --ack <name> <CVE>\` records an"
  echo "       accepted risk for 30 days; it expires deliberately."
elif printf '%s' "$out" | grep -q 'UNVERIFIED'; then
  # Not an exposure, but NOT an all-clear either. Reported quietly, never hidden.
  n=$(printf '%s' "$out" | grep -oE 'UNVERIFIED +[0-9]+' | grep -oE '[0-9]+' | head -1)
  echo "🔐 vuln-scan: no exposures; ${n:-some} package(s) could not be verified (no CPE published)."
fi
exit 0
