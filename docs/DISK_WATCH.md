# disk-watch: a ping before the disk fills

Record #3989. Asked for by Gavin in dotfiles-main on 25 Oct 2026, after makeitso's sessions left
31 test folders, about 8.8 GB, in the shared temp folder `/tmp/claude-501`, and free space fell
to 4.3 GB before anyone noticed.

## What it does

Every 15 minutes, launchd runs `disk-watch` once. It reads two numbers:

- **Free space** on `/System/Volumes/Data`, from `df -k`. It pings under 6 GB, Gavin's limit
  for starting workers. That is 6 GiB, because e-conductor reads the same number with `df -h`.
- **The shared temp folder** `/private/tmp/claude-<uid>`, from `du`. Its limit waits for
  Gavin's answer to Q2 in dotfiles-main; until then the size is measured and logged, and never
  pings.

When a limit is crossed, it pings once through `engage-ping alarm`. The ping gives the size of
the Trash beside the temp folder's, and names the biggest folders in the shared temp folder and
the session that made each. The Trash is there because on the evening of 25 Oct 2026 it, not the
temp folder, was what filled the disk: engage's test runs move their folders there, and it grew
by half a gigabyte in 40 seconds. A Trash the job is not allowed to read shows as "not readable",
never as a size. It pings again only when
things get 1 GB worse, after 6 hours still over the limit, or when the last ping reached no
phone. Coming back needs 512 MB of room past the limit, and that is logged, not pinged.

**It moves and deletes nothing.** Deletes go only through the Trash, and only with Gavin's word.
`disk-watch report` prints the line that would move a folder to the Trash; it never runs one. It
prints one only for a folder or file it looked up and found ended, or searched for and found no
maker: never for a live session's folder, a shared cache, Claude Code's own folder, a row it did
not look up, or a group of loose files (a pattern can catch files outside the group). Moving to
the Trash frees no space until the Trash is emptied, and every ping says so.

A ping that reaches no phone is tried again once an hour, not on every pass, so a broken send
cannot turn into four alarm sounds every 15 minutes.

## Who made a folder

The watch gives one of three answers, never a guess:

- **found:** a session's own folder (`pj-<session id>`, with engage's owners record), Claude
  Code's own project folder, a known shared cache, or the earliest transcript line that names the
  folder, from an hour before the folder was made to two minutes after.
- **unknown:** it searched the transcripts changed since then and none names the folder. Said
  only when the same search found a known session id first (the control).
- **not searched:** the search could not run. Retried next time, never remembered.

The names come from the live session file, else the transcript's own title, else "unnamed".

## Using it

```
disk-watch report              # the biggest 20 rows, the top 8 looked up
disk-watch report --all        # every row, every one looked up (slower)
disk-watch report --cached     # the last pass's measurement, no new du
disk-watch --selftest          # 47 arms, each with a control
```

The log is `~/.local/state/dotfiles/disk-watch/watch.log`, one line a pass, kept to its last 500
lines. The state of each limit is in `alerts` beside it.

## The ping

`engage-ping alarm` from the dotfiles repo, so the title starts with "dotfiles". Push and the
Mac's sounds only, no iMessage: a launchd job has no iMessage address, so the watch sets
`ENGAGE_PING_PUSH_ONLY=1`. It also sets `ENGAGE_PING_NO_FOLD=1`, so its run leaves even
engage-ping's own pending file alone.

## Installed by

`install.sh`, in the link step: `_install_disk_watch` writes
`~/Library/LaunchAgents/com.captaincodeau.disk-watch.plist` (every 900 s, background priority)
and loads it, only for this account's real home. Uninstall stops it and renames the plist.
