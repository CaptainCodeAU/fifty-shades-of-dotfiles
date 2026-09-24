# /pj:wrap-up: rulings, state contract and the 2026-09-25 rewrite

The skill is `home/.claude/pj/skills/wrap-up/SKILL.md`; its helper is `home/.local/bin/pj-wrap`.
The routine itself was ruled in D-20260920-A03 (one table, one pop-up) and D-20260920-A06
(handoff). This document holds what came after: the eight rulings from the 2026-09-24 audit
(W-20260924-A46, ruling D-20260925-A01), the step 8 reasoning that used to sit
inside the skill, and the state files the tools share.

Evidence: five audit reports in
drawer:pj-session-framework/reports/wrapup-audit-20260924/ (1-mechanics, 2-rulings,
3-this-session, 4-history, 5-redteam).

## The eight rulings (Gavin, 2026-09-25, all recommendations taken)

| #   | Question                                                    | Ruling                                                                                                                       | Rejected                                         |
| --- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| W1  | `pj-wrap push` publishes other sessions' dot-claude commits | Push, and name every commit whose `C-Sess-Id` is not this session, by session, in the output and the report                  | list and ask first; refuse unless all are ours   |
| W2  | Handoff owner when pj-homes names a project `wrap-up`       | That command owns the handoff when the file has no generated marker. pj skips its rewrite and hands its lines to step 8      | a new `handoff-owner:` key; a second pj file     |
| W3  | Handoff length                                              | 60 lines. `pj-wrap push` counts a generated handoff and warns above 60; detail moves into the records it points at          | about two screens; no cap                        |
| W4  | How wrap-up asks                                            | One pop-up approves the table. Each open decision is then its own question. Step 8 is a pop-up too, so the ping hook fires | everything in one pop-up; as before              |
| W5  | Step 8 declined                                             | `pj-wrap done --owed "<command>"` leaves an owed record the start card shows until that command runs                         | `done` does not run; as before (the owe is lost) |
| W6  | Bare `pj-wrap done` (21 of 31 markers)                      | Allowed. The marker records `via: skill` or `via: bare`; pj-health lists bare ones                                           | refuse without the skill; as before              |
| W7  | Panes, worktrees, watches the session opened                | Wrap-up closes its own once merged and verified (watches first). Unmerged, dirty or another session's: listed, not touched   | list only                                        |
| W8  | A standing "audit the process" step                         | No. Audit on request; the sweep's "how Gavin wants things done" row covers the rest                                          | offer in the pop-up; always run                  |

Settled without asking, because a rule already covers it: this session's own unpushed project
commits are pushed at wrap-up (pj-global RULES.md, pinned: "push once a remote exists"), and a
tag the session created is pushed now, branch first (D-20260923-A12).

## Step 8, why it offers and never runs unasked (moved here from the skill)

Ruled at the P8b gate 2026-09-21. Running the project's own wrap-up unasked was rejected because
it is that project's ritual and can commit, tag, push and edit a changelog, so `pj` would be
deciding when another project's process runs. Handing it back silently was rejected because it
is the last step of a long session and the easiest thing to lose. A slash command is executed by
the MODEL, not a shell: "run it" means the model invokes it next, which the user can interrupt.
Do not try to shell out to it. W4 makes the offer a pop-up and W5 makes a "no" durable.

## State contract (all under `${PJ_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/pj}`)

Nothing here is ever deleted; a cleared record is MOVED to a `handled/` folder with a timestamp.

| Path                                    | Written by                               | Read by                          | Format                                                                  |
| --------------------------------------- | ---------------------------------------- | -------------------------------- | ----------------------------------------------------------------------- |
| `no-wrap-up/<key>`                      | pj-session-end                           | pj-start-card, pj-wrap, pj-health | unchanged (pj-session-end header)                                       |
| `wrapped/<session-id>`                  | `pj-wrap done`                           | pj-session-end, pj-health         | `wrapped: <date>`, `project: <name>`, NEW `via: skill` or `via: bare`   |
| `owed/<key>` (NEW, W5)                  | `pj-wrap done --owed "<command>"`        | pj-start-card, pj-health          | records separated by a blank line: `owed: <command>`, `session: <id>`, `since: YYYY-MM-DD HH:MM` |
| `owed/handled/<key>.<YYYYmmdd-HHMMSS>`  | `pj-wrap owed --clear`, pj-session-end   | nobody (history)                  | the moved file                                                          |

`<key>` is the project's encoded main-repo path, the same key `no-wrap-up/` uses.

- `pj-wrap done --skill` writes `via: skill`; without it, `via: bare`. The skill always passes it.
  It is a record, not a guard: W6 allows a bare run.
- An owed record clears two ways. `pj-wrap owed --clear [<command>]` moves it aside. And
  pj-session-end moves it aside when the ending session's transcript shows that command was
  invoked (a `<command-name>` for it), so running the project's wrap-up in any later session
  clears the card without a second step.
- `pj-wrap owed` with no flag lists the project's owed records (rc 1 when none).
- The start card prints one line per owed command while the record exists:
  `Owed: <command> (since <date>, declined at wrap-up). Run it, or 'pj-wrap owed --clear'.`

## `pj-wrap` changes in the rewrite

- `done`: `--skill`, `--owed "<command>"`; the marker write is checked, and a refused write is a
  REFUSAL, never "marked wrapped" (W-20260924-A25).
- `push`: before pushing, list every commit in `@{u}..HEAD` whose `C-Sess-Id` trailer is not
  this session (or missing), grouped by session (W1). Count a generated handoff (first line
  `<!-- generated by /pj:wrap-up -->`, drawer: or repo:) and warn above 60 lines (W3). Check
  branch and upstream BEFORE committing the handoff (audit E8). "Everything up-to-date" is not
  an auth failure (W-20260924-A12). A machine with no `security` binary says "no Keychain on
  this OS", never "the Keychain DOES answer" (audit A10).
- `pj-wrap-selftest` blanks `CLAUDE_SESSION_ID` as well, so it passes inside a session (M16).

## Finding dispositions

Every High finding in the five reports is fixed by the new skill text, the tools above, or
declined here. Deferred ones are filed as items.

| Finding                                                        | Where it is handled                                        |
| -------------------------------------------------------------- | ---------------------------------------------------------- |
| No `decided add` route for rulings (5:A7, 1:M3)                | skill step 4 verdict "record the ruling"                   |
| repo: handoff written after the only commit step (5:A4, 1:M2)  | skill: handoff before delivery; delivery commits it        |
| No leak scan before a push (5:B1)                              | skill delivery step                                        |
| Several pop-ups vs one (5:A1, 2:F14)                           | W4                                                         |
| Workers, panes, worktrees left open (2:F2, 3:F2)               | W7, skill tidy step                                        |
| No finish ping (2:F3)                                          | skill: `pj-ping done` last                                 |
| Scratchpad records die with the session (3:F1)                 | skill tidy step: move or name as discarded                 |
| Sweep misses pop-up answers and queued messages (3:F5)         | skill step 1 names them                                    |
| Owed project wrap-up is lost (4:H1)                            | W5                                                         |
| Two writers on one handoff (4:H2, 2:F7)                        | W2                                                         |
| Step 4 writes refused in the sandbox (1:M1)                    | skill: lift per call, read the exit code                   |
| Session tags unpushed (2:F1)                                   | skill delivery step, D-20260923-A12                        |
| `done` moves records written after step 0 (4:H13)              | deferred, filed                                            |
| Concurrent wrap-ups clobber the handoff (5:E6)                 | deferred, filed                                            |
| Pin clearing at wrap-up (2:F15)                                | declined: not chosen in W-20260923-A26                     |
| open-items-selftest reads the real inbox (1:M17)               | fixed 2026-09-24, dotfiles 967014a                         |
