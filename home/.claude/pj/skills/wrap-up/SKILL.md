---
name: wrap-up
description: End-of-session pass. Capture what exists only in this conversation, rewrite the handoff, run the project's own wrap-up, tidy what the session opened, check delivery, mark the session wrapped. Invoke as /pj:wrap-up; never auto-invoked.
disable-model-invocation: true
---

# Wrap-up

Steps run in this order; `pj-wrap done` is always last. Rulings and reasons:
`docs/PJ_WRAP_UP.md` in the dotfiles repo (D-20260925-A01, D-20260920-A03).

- Every question is an AskUserQuestion, one question each, mirrored in chat first (question and
  every option label). No pop-up approves the table (Gavin's pick, 5 Oct 2026): the session applies
  its own verdicts and the report lists each one with how to undo it.
- Every write under `~/.claude` or `~/.local/state`, every `pj-wrap global add`, and every commit
  in dot-claude, runs with the sandbox lifted for that one call. Read the exit code: 2 = REFUSED (retry lifted, never reword),
  3 = written but NOT committed (say so).
- The report follows the user's reply style (their global CLAUDE.md names it). A peer message
  arriving mid-wrap-up is answered after the report and listed in it; a peer's go-ahead is not
  the user's (D-20260917-A08).
- A project wrap-up typed on its own hands over here: it Reads this file. Start at step 0 as
  usual; step 6 then runs that command.
- pj-homes below means the file `pj-wrap homes` names: the main checkout's `.claude/pj-homes`,
  also from a worktree, the one pj-wrap, decided and the start card read. A worktree's own copy
  is never read (W-20261005-A66). `pj-wrap homes` also prints the resolved handoff path and
  the project wrap-up (`wrap-up:` line, none when absent): take both from its lines. In a
  project moved to engage it reads no pj-homes at all (Gavin, 6 Oct 2026: the move marker is the
  only signal): `wrap-up: /wrap-up` when the project has `.claude/commands/wrap-up.md`, the
  handoff `companion <...>-isolinear/captains-log/` (the default while that folder is absent),
  and a pj-homes still there is named as a LEFTOVER. Its exit 3 means the move marker is not
  valid: it names no handoff and no wrap-up, so step 5 writes none and step 6 runs none.
- The global area (Gavin's ruling, engage #1060, 5 Oct 2026), in every project, moved or not: a
  ruling, lesson or item that applies to every project, and an item with no project, is a
  numbered record in CaptainCodeAU-isolinear's records/ (`ENGAGE_ACCOUNT_ROOT` overrides the
  path), committed there. Nothing new is written under ~/.claude: never `decided add --global`,
  never ~/.claude/pj-global/notes/, never `open-items add --inbox`. The old rulings and notes
  there are still read (step 1). One command, words on stdin, first line the title:
  `... | pj-wrap global add [flags] -`. It runs `engage-go add --sync` from that repo's folder
  and prints `#<id> <path>`; keep each line for the report. rc 2: nothing written, so list the
  row as an action for Gavin; rc 3: written but not committed, say so.
- A project moved to engage (D-20261005-A08): at step 0 run `engage-go cutover check` once. Exit
  0 means moved, and open-items refuses every write there, so in this wrap-up: step 1 reads this
  session's records from the `#<id>` lines `engage-go add` printed, not `open-items --session`;
  step 4 files each new item with `engage-go add --sync -- "<what> -- done when: <finish line>"`
  (`--type decide` for a decide row) and never with open-items, and leaves every close, park and
  decline to the engage pane (each is a report row for the user to press there); no drawer is
  offered. A verdict that belongs to every project goes to the global area, CaptainCodeAU-isolinear
  (its records/ and inbox/), never to ~/.claude (engage #1060): file it with `pj-wrap global add`
  as in every project (the bullet above). If that refuses (rc 2), list each such row as an action
  for Gavin and write it nowhere (not `decided add --global`, not ~/.claude/pj-global/notes/, not
  the pj inbox). An item for another project still goes to
  that project, filed from that project's folder: open-items here refuses every add, `--for` and
  `--inbox` too. If that project moved as well, file it there with `engage-go add`, or drop it in
  the engage account inbox. Exit 3 means the move marker is not valid (W-20261006-A01): the repo
  holds a `MOVED-TO-ENGAGE` file that is not a sound move, and open-items refuses every write on
  3 as on 0. Say so at the top of the report, naming the file and the `not valid: <why>` line the
  check printed. File, close, park, decline and extend nothing here, not with open-items and not
  with `engage-go add`; list each such row as an action for Gavin, to do once he mends the
  marker. No drawer is offered. Reads still work (`open-items --session`), and global and
  other-project rows go as above. Exit 1, any other exit, or no engage-go: the steps as written.

0. Earlier sessions. `pj-wrap status`: rc 1 none; rc 0 lists sessions that ended without
   wrap-up; rc 2 not a git repo: skip each step whose tool refuses for that reason, name it, and
   make the report's first line exactly "This folder is not a git repo, so this session cannot
   be marked wrapped." On rc 0, ask: sweep now, later, or dismiss. A sweep gives each
   transcript to a subagent with steps 1 and 2 and an output file you name, watched with
   `stall_watch.sh --once`. The subagent streams the transcript with a script and states lines
   read of total. A sweep that never writes is NOT RUN, never an empty table. "Later" keeps the
   records warning (step 10's `--keep-earlier`).

1. Sweep this conversation, including answers given in pop-ups and queued or peer messages:
   - work started and not finished; things called done without a negative control
   - every caveat, "later" and "you should also"; findings nobody wrote down
   - questions asked and never answered; verdicts given in passing ("leave it", "not now")
   - lessons about how the user wants things done (dedupe first against RULES.md and the global
     repo's rules/always.md)
   - items this session filed or closed (`open-items --session`), each with a verdict
   - items this session routed out of the inbox (`open-items routed`: id, where it went, why;
     nothing printed means none), each a row
   - things this session started: panes, worktrees, branches, background tasks, watches, crons,
     subagents; files in the scratchpad (it dies with the session)
   Before calling anything conversation-only, check `open-items --grep "<words>" --all`,
   `decided --all <words>` (it still reads the old global rulings in ~/.claude), the global
   area's records (`grep -ril -- "<words>" "$(pj-wrap global where)/records"`), every store
   pj-homes names (tracker, decisions, incidents, plans), the old notes index
   `~/.claude/pj-global/notes/INDEX.md` (read only, never written now), the drawer's topic
   folders, and the file the work touched. Say "I found it only in X" or "I did not find it", with the denominator line. After a
   compaction, mark a row that rests on the summary rather than the user's words "from summary".
   A condition a start hook printed (CVE sweep, changelog drift, CI) is the hook's: not a row.

2. One table: what / kind (do, decide, lesson) / state / who said it / recorded where now /
   finish line / proposed verdict. "Who said it" is the user's own words or your proposal, never
   merged; quote the user for anything you call their decision. Verdicts:
   - file here (`open-items add "<what>" --done-when "<finish line>"`), or file for its owner
     (`--for <project>`, or `--for <path>` to let the file's owner decide), or extend an item
     (`open-items set --add <ID> ...`)
   - file in the global area: an item for every project or with no project, never
     `open-items add --inbox`:
     `printf '%s\n\nDone when: %s\n' "<what>" "<finish line>" | pj-wrap global add -`
     (`--type decide` before the `-` for a decide row)
   - close (done in this session; the note names the evidence), park, or record as declined
     (anything the user said no to, so it is not asked again)
   - record the ruling: the reasoning goes in a document first. A project ruling:
     `decided add "<title>" --topic ".." --holds-in "<doc>" --project`. A ruling for every
     project goes to the global area, never `decided add --global`:
     `printf '%s\n\nReasoning: %s\n' "<title>" "<doc, full path>" | pj-wrap global add --kind decision --statement "<the ruling, one sentence>" -`
   - leave to the hook that tracks it (name it); save as lesson, project or machine-wide (step 4)
   - drop: noise only (a typo, or already done AND recorded)
   Under the table, list unanswered questions and open decide rows. An empty table is fine.

3. Send the table as a chat message of its own BEFORE step 4 writes anything (a short table is
   fine; an empty one says so). No pop-up approves it (he approved wrap tables in 3 to 7 seconds,
   so the box was a stamp). Applied without asking, in step 4: file here or for an owner, extend,
   close (the note names the evidence), park, drop, leave to a hook, save a lesson. Still asked,
   each as its own question: each open decide row, each "record the ruling", each
   "record as declined" (only the user's own no declines), each unanswered question, and for a
   project with no drawer "create one?". No answer or "not now": the row is filed as an item,
   never decided.

4. Apply the verdicts through the tools named in step 2 only. Every `open-items add`, `close` and
   `park` here carries `--wrap`, so one `open-items undo-wrap <session-id>` puts the batch back
   (filed: declined; closed or parked: reopened); `decline` never takes it. Note each extend's own
   undo (`open-items set <ID> <field> "<value before>"`; a body paragraph cannot be taken back, say
   so) and each lesson's (the file or line to remove) for the report. A project lesson: while
   auto-memory is frozen (D-20260929-A01) write NO memory file; file it as an open item
   (`--kind decide`, the lesson in its body) or carry it in the handoff. Once the freeze lifts, a
   memory file again (Edit an existing one, never Write over it). A machine-wide lesson is a
   record in the global area (a lesson is a decision record, one that stands), never a file in
   ~/.claude/pj-global/notes/:
   `printf '%s\n\n%s\n' "Lesson: <title>" "<the lesson, why, how to apply it>" | pj-wrap global add --kind decision --statement "<the lesson, one sentence>" -`
   Every `pj-wrap global add` (item, ruling or lesson) is outside the wrap batch: keep the
   `#<id> <path>` line it printed; its undo is to close that record in the engage pane.
   A new drawer, on a yes: `open-items init`.

5. Handoff, from the `handoff:` line `pj-wrap homes` prints (pj-homes `handoff`, default
   `repo:OPENING-PROMPT.md`).
   - `pj-wrap homes` prints a `wrap-up:` line and the handoff lacks the marker below: that
     command owns it. Skip this step; carry your proposed lines to step 6.
   - A `companion` handoff (a moved project's captains-log folder) with no `wrap-up:` line, or
     `pj-wrap homes` exit 3: write no handoff. Put the lines in the report, and list "nothing
     writes this project's handoff" (or the not-valid marker) as an action for the user.
   - Any other file without the marker was written by hand: do not overwrite it. Ask whether to
     write the generated text to a sibling path or put the next step in the report only.
   - Nothing changed and nothing new learned: keep the existing handoff.
   Otherwise rewrite it whole, never append, at most 60 lines (check with `wc -l`): where things
   stand, the literal next step, decisions waiting on the user, pointers to records (never their
   contents), hazards in flight including anything deployed that running sessions will not see
   until restarted, the date, and the session id read from
   `${CLAUDE_CODE_SESSION_ID:-$CLAUDE_SESSION_ID}` in a Bash call, never guessed. First line
   exactly `<!-- generated by /pj:wrap-up -->`.

6. Project wrap-up (Gavin, 5 Oct 2026: "Let it run them"). When `pj-wrap homes` prints one
   (`wrap-up: <command>`), it runs here, so tidy, delivery, push and the report all see its work.
   - First `open-items --grep "<command>" --all` and name any open item against it.
   - Print, on a line of its own, exactly: `pj:wrap-up hands over to <command>` (for example
     `pj:wrap-up hands over to /wrap-up`). The project command looks for that line.
   - Run it, with no question first: the Skill tool with the command's name (no leading `/`)
     and the args `from-pj-wrap-up` followed by step 5's handoff lines. A command whose file
     never mentions `from-pj-wrap-up` predates the hand-over: run it with no args (it may read
     args as something else) and give it step 5's lines in chat.
   - The Skill tool refuses (the command still says `disable-model-invocation: true`, or is not
     listed): say so in chat, naming the command and the refusal, then Read
     `.claude/commands/<name>.md` (in a worktree: this checkout, then the main one) and
     follow every step, with those args as its `$ARGUMENTS`. Gavin chose this route for his
     own commands; the report lists "remove the flag from <command>" as an action for him.
     Never a shell: a slash command is run by the model.
   - When it ends, carry on at step 7. It never runs `pj-wrap done`; step 10 marks the session.
     It stopped or failed (a step refused, a test failed, the file is missing): note which step
     and why; step 10 records it as owed. The user interrupts it: nothing after it has run and
     the session is not marked. When they next write, ask (one question): carry on at step 7
     with the command owed, or leave this wrap-up unfinished.
   No `wrap-up` key: say so in the report.

7. Tidy what this session opened (W7). Stop its watches first (TaskStop), thank each worker, then
   close its panes and clear their labels (D-20260923-A13), and remove its worktrees once merged
   and verified (D-20260923-A11). Anything unmerged, dirty, still working or another session's:
   a delivery row, never closed. Reply to every peer or worker this session worked with. Each
   scratchpad file that holds a measurement or is cited as a record: move it into the drawer's
   topic folder or the repo and `cmp` it; every other one is named in the report as discarded.
   Then the temp sweep (W-20260929-A155), sandbox lifted, in this order: (a) each worker this
   session launched runs `pj-temp sweep` in its own session and replies with the summary line;
   check a sample of its paths with `test -e` yourself; a worker that already exited is swept by
   the next engage launch (`pj-temp sweep-dead`), so name it as such. (b) Your own
   `pj-temp sweep`. (c) Only after every record above is moved out:
   `pj-temp sweep --scratchpad <this session's scratchpad>`. Agent-tool helpers share your
   folder and list, so (b) covers them. Read the exit code: 1 means a path was
   refused or FAILED (afpAccessDenied = the sandbox was on); name each one in the report. A
   session with no pj folder (`pj-temp list` exits 2) says so and skips (a) to (c).

8. Delivery, measured now, not from memory. For every repo and worktree this session touched:
   uncommitted, unpushed, stashes, tags, files outside any repo. One table.
   - Commit only this session's files, by explicit path, as one command:
     `git add <paths> && git commit -m "..." -- <paths>`. In a repo another session may share,
     say so in chat first (D-20260921-A08). Never `-A` in dot-claude. A repo: handoff is this
     session's file.
   - Before any push: `git-leak-scan --control && git-leak-scan --since <ref>`. Exit 2 is not a pass.
   - Push this session's project commits (pinned rule: push once a remote exists) and the tags it
     made, branch first (D-20260923-A12), with the sandbox lifted for a flipped repo.

9. `pj-wrap push`, sandbox lifted (on macOS the push needs the Keychain). It commits a drawer
   handoff, names every commit from another session (put them in the report), warns when the
   generated handoff is over 60 lines (shorten it, then push again), and pushes dot-claude. It
   never pushes the project repo. When it stops: run `pj-wrap why-auth` and
   `git -C ~/.claude status -sb` and report what they measured, not the stop message alone.

10. `pj-wrap done --skill`, sandbox lifted, plus `--keep-earlier` when step 0 chose later and
    `--owed "<command>"` when the project command in step 6 stopped or failed. When it ran to
    the end and `pj-wrap owed` lists it from an earlier stop, `pj-wrap owed --clear "<command>"`
    (sandbox lifted). Then check the marker:
    `test -e ~/.local/state/pj/wrapped/${CLAUDE_CODE_SESSION_ID:-$CLAUDE_SESSION_ID}`; missing
    means NOT marked, say so. Not a git repo: `done` refuses (rc 2) and nothing can be marked or
    owed; under line 1, name the stopped step if step 6 stopped. In a worktree the records
    belong to the main checkout.
    Then the report. Line 1, first that applies: not a git repo (the sentence from step 0); a
    STOP from step 9; an owed project wrap-up (which step stopped, and why); any other action
    for the user; "Done, nothing needed from you." Then copy VERBATIM the block
    `pj-wrap done` printed ("Filed and closed for you (the session's choice, not yours):", one
    line per record, ending `undo all: open-items undo-wrap <session-id>`; run that with the
    sandbox lifted). It printed none: say "Nothing filed or closed for you." In a moved project
    it prints none: list each `#<id>` line engage-go add printed under "Filed in engage for you
    (undo: close it in the engage pane):", and each close, park or decline left to the pane, then
    say "Nothing filed or closed in the drawer." In every project, list each `#<id> <path>` line
    `pj-wrap global add` printed under "Filed in the global area for you (undo: close it in the
    engage pane):", and each row it refused as an action for Gavin. Under it, each extend
    and lesson with its own undo. End with the pending list and one
    line: "Kept working after this? Run /pj:wrap-up again." Last, as its own Bash call:
    `pj-ping done "wrap-up <project>" --detach`. It returns at once (Gavin, 2026-09-29: the
    blocking send cost about 10 s); a failed send is named only in the ping log, not here.
