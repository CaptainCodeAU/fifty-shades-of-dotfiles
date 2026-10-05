# /pj:wrap-up: rulings, state contract and the 2026-09-25 rewrite

The skill is `home/.claude/pj/skills/wrap-up/SKILL.md`; its helper is `home/.local/bin/pj-wrap`.
The routine itself was ruled in D-20260920-A03 (one table, one pop-up) and D-20260920-A06
(handoff). This document holds what came after: the eight rulings from the 2026-09-24 audit
(W-20260924-A46, ruling D-20260925-A01), the 5 Oct 2026 changes (no approval box; the
project's own wrap-up runs inside /pj:wrap-up), and the state files the tools share. Step
numbers in the 25 Sep table are that day's: the project step was step 8 then, 9 later, and
is step 6 since 5 Oct 2026.

Evidence: five audit reports in
drawer:pj-session-framework/reports/wrapup-audit-20260924/ (1-mechanics, 2-rulings,
3-this-session, 4-history, 5-redteam).

## The eight rulings (Gavin, 2026-09-25, all recommendations taken)

| #   | Question                                                    | Ruling                                                                                                                       | Rejected                                         |
| --- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| W1  | `pj-wrap push` publishes other sessions' dot-claude commits | Push, and name every commit whose `C-Sess-Id` is not this session, by session, in the output and the report                  | list and ask first; refuse unless all are ours   |
| W2  | Handoff owner when pj-homes names a project `wrap-up`       | That command owns the handoff when the file has no generated marker. pj skips its rewrite and hands its lines to step 8      | a new `handoff-owner:` key; a second pj file     |
| W3  | Handoff length                                              | 60 lines. `pj-wrap push` counts a generated handoff and warns above 60; detail moves into the records it points at          | about two screens; no cap                        |
| W4  | How wrap-up asks                                            | One pop-up approves the table. Each open decision is then its own question. Step 8 is a pop-up too, so the ping hook fires. **The table pop-up and the step 8 pop-up were both removed on 5 Oct 2026; see below** | everything in one pop-up; as before              |
| W5  | Step 8 declined (since 5 Oct 2026: stopped or failed)       | `pj-wrap done --owed "<command>"` leaves an owed record the start card shows until that command runs                         | `done` does not run; as before (the owe is lost) |
| W6  | Bare `pj-wrap done` (21 of 31 markers)                      | Allowed. The marker records `via: skill` or `via: bare`; pj-health lists bare ones                                           | refuse without the skill; as before              |
| W7  | Panes, worktrees, watches the session opened                | Wrap-up closes its own once merged and verified (watches first). Unmerged, dirty or another session's: listed, not touched   | list only                                        |
| W8  | A standing "audit the process" step                         | No. Audit on request; the sweep's "how Gavin wants things done" row covers the rest                                          | offer in the pop-up; always run                  |

Settled without asking, because a rule already covers it: this session's own unpushed project
commits are pushed at wrap-up (pj-global RULES.md, pinned: "push once a remote exists"), and a
tag the session created is pushed now, branch first (D-20260923-A12).

## No approval box: the session applies its verdicts, one command undoes them (5 Oct 2026)

Gavin's pick, 5 Oct 2026, in the S4 conductor session: "Only S4's fewer-boxes slice" (the
option read: wrap-up files loose ends for you with an undo, no approval table). The record
showed him approving wrap tables in 3 to 7 seconds, so the box was a stamp, not a check. This
replaces the table pop-up of W4; every other question W4 kept is still asked.

- The table is still shown, as a chat message of its own before anything is written. No pop-up
  approves it.
- Applied without asking: file here or for an owner, extend, close (the note names the
  evidence), park, drop, leave to a hook, save a lesson.
- Still asked, one question each: open decide rows, "record the ruling", "record as declined"
  (only his own no declines anything), unanswered questions, "create a drawer?". No answer
  files the row as an item; it is never decided for him.
- Every `open-items add`, `close` and `park` the wrap makes carries `--wrap`. `pj-wrap done`
  then PRINTS the block from that ledger itself: "Filed and closed for you (the session's choice,
  not yours):", one line per record (filed, closed or parked, ID, title), and
  `undo all: open-items undo-wrap <session-id>` with the real id. No ledger, or one already
  undone: it prints nothing. The report copies the block verbatim. Added the same day after the
  conductor's demo: a model-written block was left out of the demo report, and without the box
  that block is the only place he sees what was done, so it must not rest on the model.
- `undo-wrap` declines what the wrap filed (note "withdrawn: wrap-up undo") and reopens what it
  closed or parked. An item filed and then closed in the same wrap goes back to before the first
  write: declined. If any record changed after the wrap, it refuses, names each one, and changes
  nothing. Extends and lessons are not in the batch; the report gives each its own undo.
  Mechanics: docs/OPEN_ITEMS.md, "Undoing a wrap-up's batch".

## The project's own wrap-up runs inside /pj:wrap-up (5 Oct 2026, W46)

Gavin's picks, 5 Oct 2026, in the engage-main conductor session (engage record #1014; ruling
D-20261005-A02 in the machine-wide register):

- "Let it run them": /pj:wrap-up runs a project's own wrap-up itself, before it marks the
  session wrapped. No question box, no typing. The project commands lose their manual-only
  flag (`disable-model-invocation: true`).
- Typed alone: "Hand over to /pj:wrap-up". A project wrap-up typed on its own hands over to
  /pj:wrap-up, which then runs the project steps. One path, always marked.
- Push: "Push all when green".
- Non-git folder: "warn plainly".

**The order.** The project step is now step 6: after the handoff (5), before tidy and the temp
sweep (7), delivery (8), `pj-wrap push` (9) and `pj-wrap done` (10). It used to run after all
of them, so the scratchpad was already swept before the project command could use it,
`~/.claude` commits the project command made stayed unpushed, and the report described the
state before the project wrap-up ran. Now every later step sees what it did.

**The hand-over.** Step 6 first prints, on a line of its own, exactly
`pj:wrap-up hands over to <command>` (for example `pj:wrap-up hands over to /wrap-up`). Then it
runs the command: the Skill tool with the command's name and the args `from-pj-wrap-up`
followed by step 5's handoff lines. If the Skill tool refuses (a command that still carries
`disable-model-invocation: true`, or one the session does not list), it Reads
`.claude/commands/<name>.md` (in a worktree: that checkout, then the main one) and follows
every step. Never a shell: a slash command is run by the model.

Three rules came from checking step 6 against real files on 5 Oct 2026 (W46 report):

- **A command that predates the hand-over runs with no args.** win_go_app_test's
  `/vertical-wrap-up` (out of this change's scope) reads its args as a vertical name and never
  looks for `from-pj-wrap-up`. So a command whose file never mentions `from-pj-wrap-up` is run
  with no args, as if typed, and gets step 5's lines in chat.
- **The Read fallback is loud.** The real refusal for a manual-only command (measured in
  Network_Plan af6f0a6e, v2.1.289) says "Do not replicate this skill's workflow by other
  means". Gavin's pick is that his own commands run, so the fallback stays, but it is said in
  chat and the report asks him to remove the flag. The fix is the flag coming off, not the
  fallback.
- **An interrupted command leaves the session unmarked.** Steps 7 to 10 have not run. On the
  next message the skill asks one question: carry on at step 7 with the command owed, or leave
  the wrap-up unfinished.

**Typed alone (the project command's side, contract part 2, built in each project).** The
project command's first step: if its args start with `from-pj-wrap-up`, or the hand-over line
naming it appears after the user's last message, it carries on. Otherwise it says "Handing
over to /pj:wrap-up; it runs these steps at its project step." and Reads
`~/.claude/pj/skills/wrap-up/SKILL.md` and follows it from step 0. /pj:wrap-up stays
manual-only, so the Skill tool cannot start it; reading it can. Read-only modes may run
direct, and the command says which. The project command never runs `pj-wrap done`.

**Owed.** There is no "run now or not now" question any more, so nothing is declined. It is
owed (`pj-wrap done --owed "<command>"`) only when the project command stopped or failed: a
step refused, a test failed, the user stopped it, or the file pj-homes names is missing. The
report's first line says which step and why. Two consequences for clearing:

- pj-session-end never clears an owed record in the session that WROTE it. That session's run
  is the one that stopped, and it often lands in the same minute as the owe's `since:`, which
  the at-or-after rule would have counted as a clearing run. Measured red first:
  pj-session-end-selftest O10.
- A later full run clears it through the skill: when step 6 ran the command to the end and
  `pj-wrap owed` lists it, step 10 runs `pj-wrap owed --clear "<command>"`. This also covers the
  Read route, which leaves no `<command-name>` or Skill result in the transcript for
  pj-session-end to see.

The start card's owed line now reads `(since <date>, not finished at wrap-up)`; it said
"declined", which covers only the old records.

**Non-git folder.** `pj-wrap status` and `pj-wrap done` refuse with rc 2 outside a git repo,
because there is no project key to mark. The skill now makes the report's first line exactly
"This folder is not a git repo, so this session cannot be marked wrapped.", and `pj-wrap done`
refuses in the same words. Nothing else changed: pj-session-end already writes no flag outside
a repo, and the start card already says "not a git repo, so no project, no items", so no
warning is lost and none is owed.

## Before 5 Oct 2026: why the project step offered and never ran unasked (superseded)

Ruled at the P8b gate 2026-09-21, superseded by the section above. Running the project's own
wrap-up unasked was rejected because it is that project's ritual and can commit, tag, push and
edit a changelog, so `pj` would be deciding when another project's process runs. Handing it
back silently was rejected because it is the last step of a long session and the easiest thing
to lose. W4 made the offer a pop-up and W5 made a "no" durable. Gavin's 5 Oct pick answers the
first worry directly: he chose to let it run, and the user can still interrupt it.

## State contract (all under `${PJ_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/pj}`)

Nothing here is ever deleted; a cleared record is MOVED to a `handled/` folder with a timestamp.

| Path                                    | Written by                               | Read by                          | Format                                                                  |
| --------------------------------------- | ---------------------------------------- | -------------------------------- | ----------------------------------------------------------------------- |
| `no-wrap-up/<key>`                      | pj-session-end                           | pj-start-card, pj-wrap, pj-health | unchanged (pj-session-end header)                                       |
| `wrapped/<session-id>`                  | `pj-wrap done`                           | pj-session-end, pj-health         | `wrapped: <date>`, `project: <name>`, NEW `via: skill` or `via: bare`   |
| `owed/<key>` (NEW, W5)                  | `pj-wrap done --owed "<command>"` (the project command stopped or failed) | pj-start-card, pj-health          | records separated by a blank line: `owed: <command>`, `project: <name>`, `session: <id>`, `since: YYYY-MM-DD HH:MM` |
| `owed/handled/<key>.<YYYYmmdd-HHMMSS>`  | `pj-wrap owed --clear`, pj-session-end   | nobody (history)                  | the moved file                                                          |
| `wrap-batch/<session-id>.tsv` (5 Oct 2026) | `open-items add/close/park --wrap`     | `open-items undo-wrap`, `pj-wrap done` | one line per write: action, drawer, id, item file, sha256          |
| `wrap-batch/<session-id>.tsv.undone.<YYYYmmdd-HHMMSS>` | `open-items undo-wrap`                   | `open-items undo-wrap` (refuses a second undo) | the moved file                                              |

`<key>` is the project's encoded main-repo path, the same key `no-wrap-up/` uses.

- `pj-wrap done --skill` writes `via: skill`; without it, `via: bare`. The skill always passes it.
  It is a record, not a guard: W6 allows a bare run.
- An owed record clears two ways. `pj-wrap owed --clear [<command>]` moves it aside. And
  pj-session-end moves it aside when the ending session's transcript shows that command was
  invoked (a `<command-name>` for it), so running the project's wrap-up in any later session
  clears the card without a second step.
- How pj-session-end sees that a command ran, measured from real transcripts 2026-09-25 by worker
  wrap. Typed: a `user` line whose content is a string starting
  `<command-message>NAME</command-message>` then `<command-name>/NAME</command-name>`. Run by the
  model: a `Skill` tool call, then a `user` line with `toolUseResult: {success: true, commandName:
  "NAME"}`, and no `<command-name>` at all. Either route clears. The owed command's first word, one
  leading `/` dropped, must equal NAME exactly, so `pj:wrap-up` never clears `/wrap-up`. Only an
  invocation at or after the record's `since:` minute counts, so running the command early in the
  session that then declines it does not clear the owe. And never in the session that wrote
  the record (5 Oct 2026, above): its run is the stopped one. `pj-wrap owed --clear <cmd>` compares the
  whole command.
- `pj-wrap owed` with no flag lists the project's owed records (rc 1 when none).
- The start card prints one line per owed command while the record exists:
  `Owed: <command> (since <date>, not finished at wrap-up). Run it, or 'pj-wrap owed --clear'.`

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
