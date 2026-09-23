# `pj-ping` - the numbered attention signal

`pj-ping` is the one command every pj session and the `pj-question-ping.sh`
hook use to get Gavin's attention (D-20260921-A10): four sounds, then two
iMessages, each sent twice. Built 2026-09-23 after a real ping test in which
the messages were hard to tell apart. Every message now carries an id, so
Gavin and a session can confirm **which** ping arrived and **in what order**.

```sh
pj-ping <question|done|waiting|test> "<summary>" [--action "<what Gavin must do>"] [--detach]
pj-ping --help
pj-ping --selftest          # runs pj-ping-selftest beside it; fake afplay and imsg only
```

## What arrives

Sounds first (`afplay` Ping, Glass, Glass, Glass), then:

```
1: <icon> PJ <KIND> #<id> <HH:MM:SS> | <session> | <summary>
2: <icon> #<id> 2/2 | <action> | pane <HERDR_PANE_ID or ->
```

For example:

```
❓ PJ QUESTION #K3F9 17:30:41 | fifty-shades-of-dotfiles-main | Pick a delivery route
❓ #K3F9 2/2 | answer the popup | pane w1-p2
```

| Kind       | Icon | Default action                          |
| ---------- | ---- | --------------------------------------- |
| `question` | ❓   | answer the popup                        |
| `done`     | ✅   | nothing needed                          |
| `waiting`  | ⏳   | none: `--action` is required            |
| `test`     | 🧪   | confirm the id and order to the session |

- **The id** is 4 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. There is
  no 0, O, 1, I or L, so it survives being read aloud or typed on a phone. It
  is printed on stdout as `#K3F9`, and an id already in the log is never
  handed out again.
- **The time** is local time at the call.
- **The session** is `$CLAUDE_CODE_SESSION_NAME`, else the basename of the
  git toplevel of the current directory.
- **Each message is sent twice** (Gavin, 2026-09-23): message 1, one second,
  message 1 again, a pause of at least 5 seconds, message 2, one second,
  message 2 again. Four texts per ping. `PJ_PING_PAIR_GAP` can lengthen the
  pause; it can shorten it only in a selftest (when the `PJ_PING_IMSG` seam is
  set), so a real ping never pauses less than 5 seconds.

## Confirming which ping arrived, and in what order

Every call logs two tab-separated lines to `~/.local/state/pj/ping.log`
(`$PJ_PING_LOG` or `$PJ_PING_STATE_DIR` move it). The summary and action text
are never logged.

```
2026-09-23T17:30:41+1000  K3F9  question  fifty-shades-...-main  queued  -
2026-09-23T17:30:45+1000  K3F9  question  fifty-shades-...-main  sent    afplay=0000 imsg=0,0,0,0
```

`queued` is written at the call, with anything that was missing. `sent` is
written when the work is done, with the four `afplay` exit codes and both
`imsg` exit codes. So when Gavin quotes ids, a session checks them like this:

```sh
rg -w 'K3F9|7QHM' ~/.local/state/pj/ping.log
```

The order of the lines is the order they were sent. An `imsg` exit code of 0
means "handed to Messages", not "delivered" (see `docs/IMSG.md`).

## Exit codes

| Code | Meaning                                                                   |
| ---- | ------------------------------------------------------------------------- |
| 0    | the whole signal went out (with `--detach`: handed to the worker)         |
| 1    | something was missing or failed; stderr and the log name it               |
| 2    | usage error, or no unused id could be drawn: nothing sent, nothing logged |

`PJ_NO_PING=1` is the kill switch: exit 0, nothing sent, nothing logged.
Missing `afplay`, `imsg` or `$IMSG_TO`: the rest is still done, and the log
names what was missing.

## Untrusted text

Summary, action, session name and pane id are cleaned before they reach a
message. Control characters (C0, DEL, C1) and bidi or zero-width characters
become a space. Token-shaped strings (`ghp_`, `github_pat_`, `sk-`, `xox?-`,
`AKIA`, `glpat-`) become `[redacted]`. Whitespace is squeezed, and each part
is capped: session 40, summary 80, action 80, pane 40 characters. This code
used to live in `pj-question-ping.sh` and now exists only in `pj-ping`.

## `--detach`

Prints the id, then hands the sounds and messages to a double-forked worker
with stdin, stdout and stderr on `/dev/null`, and returns. Measured by the
selftest at about 0.06 s while the fake signal takes over 2.2 s. The hook
uses this so an `AskUserQuestion` popup is never delayed.

## The sandbox

`afplay` fails inside the Bash tool's sandbox (`AudioQueueStart failed
(-66680)`), Apple Events to Messages fail there too, and so does every child
of a sandboxed command. The log under `~/.local/state` is also outside the
sandbox's write set, so a sandboxed `pj-ping` says it could not write the log
and exits 1. From a Bash tool call, run `pj-ping` as its own call with the
sandbox lifted. Hooks run outside the sandbox.

## Selftest

`pj-ping-selftest` (41 arms) uses fake `afplay` and `imsg` only: every arm
pins `PJ_PING_AFPLAY` and `PJ_PING_IMSG` to fakes or to a missing path, and
the fakes are first on `PATH`. `PJ_PING_TOOL=<path>` tests another copy.
`PJ_PING_ALPHABET` narrows the id alphabet so the never-reuse rule can be
tested on 16 possible ids. It covers both messages for every kind, the order,
the 1 s gap, 50 distinct ids, the refusals, sanitising and caps, `--detach`
timing, the kill switch, missing tools and the log.
