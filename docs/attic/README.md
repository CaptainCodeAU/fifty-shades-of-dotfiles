# docs/attic -- code that was removed on purpose, kept for reading

Nothing in this directory runs. Every file is `.txt`, mode 644, and deliberately
**outside `home/`** so that stow never links it into `~`. That placement is the whole
point: an archived copy of a former PATH command, parked under `home/.local/bin/`,
would be stowed into `~/.local/bin` and become a live command again. An attic that
executes is not an attic.

Git history holds all of this anyway. These copies exist so a future session can read
retired code without knowing which commit to look in.

## `ccw-watch-doctor-era.sh.txt` + `ccw-watch-selftest-doctor-era.sh.txt`

Archived 2026-09-07 from `9fb3a59`, the last commit before `ccw-watch` was narrowed.

**What it was.** `ccw-watch` ran `ccw doctor` at every session start, parsed the prose
report for an `Uncaptured: N` count, and escalated when capture looked broken. The
selftest was 346 lines and 37 passing cases, most of them exercising that parser and the
timeout wrapped around the doctor call.

**Why it went.** The `cc-warehouse` plugin now runs its own SessionStart freshness check,
which owns capture HEALTH from inside the tool that owns the data. Two tools asking the
same question produced two escalating spoken alarms that could disagree -- theirs allowed
`doctor` 45s, ours 20s, so a legitimately slow doctor (a cold walk of 27,277 files right
after an archive sweep) would have gone red here and stayed quiet there.

Narrowing deleted the disagreement rather than negotiating it. `ccw-watch` now answers
only the question nothing else can: **is capture INSTALLED and switched on**, which their
hook cannot report because a hook that never runs raises no error.

**What is worth reading here.** Three fixes from 2026-09-06 whose reasoning outlives the
code, all with their comments intact:

- `handle_ok`'s `${gap:-0}` bug -- a failed parse rendered as "capture working, 0 sessions
  pending". A confident wrong answer, not a degraded one.
- The doctor timeout, including the watchdog that killed the pid but left CHILDREN alive,
  so a surviving grandchild held the command-substitution pipe open and the caller still
  waited the full 300s. `set -m` plus `kill -- -$pid` was the fix.
- The two-counts case: an ambiguous report escalates instead of silently taking the first
  reading.

The escalation engine, the state file, the snooze and the voice paths were NOT retired --
they carried over into the narrowed tool unchanged.
