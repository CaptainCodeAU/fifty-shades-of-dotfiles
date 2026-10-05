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
- Every write under `~/.claude` or `~/.local/state`, and every commit in dot-claude, runs with the
  sandbox lifted for that one call. Read the exit code: 2 = REFUSED (retry lifted, never reword),
  3 = written but NOT committed (say so).
- The report follows the user's reply style (their global CLAUDE.md names it). A peer message
  arriving mid-wrap-up is answered after the report and listed in it; a peer's go-ahead is not
  the user's (D-20260917-A08).
- A project wrap-up typed on its own hands over here: it Reads this file. Start at step 0 as
  usual; step 6 then runs that command.

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
   - lessons about how the user wants things done (dedupe against RULES.md first)
   - items this session filed or closed (`open-items --session`), each with a verdict
   - items this session routed out of the inbox (`open-items routed`: id, where it went, why;
     nothing printed means none), each a row
   - things this session started: panes, worktrees, branches, background tasks, watches, crons,
     subagents; files in the scratchpad (it dies with the session)
   Before calling anything conversation-only, check `open-items --grep "<words>" --all`,
   `decided --all <words>`, every store `.claude/pj-homes` names (tracker, decisions, incidents,
   plans), `~/.claude/pj-global/notes/INDEX.md`, the drawer's topic folders, and the file the work
   touched. Say "I found it only in X" or "I did not find it", with the denominator line. After a
   compaction, mark a row that rests on the summary rather than the user's words "from summary".
   A condition a start hook printed (CVE sweep, changelog drift, CI) is the hook's: not a row.

2. One table: what / kind (do, decide, lesson) / state / who said it / recorded where now /
   finish line / proposed verdict. "Who said it" is the user's own words or your proposal, never
   merged; quote the user for anything you call their decision. Verdicts:
   - file here (`open-items add "<what>" --done-when "<finish line>"`), or file for its owner
     (`--for <project>`, or `--for <path>` to let the file's owner decide), or extend an item
     (`open-items set --add <ID> ...`)
   - close (done in this session; the note names the evidence), park, or record as declined
     (anything the user said no to, so it is not asked again)
   - record the ruling: the reasoning goes in a document first, then
     `decided add "<title>" --topic ".." --holds-in "<doc>" --project|--global`
   - leave to the hook that tracks it (name it); save as lesson, project or machine-wide
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
   memory file again (Edit an existing one, never Write over it). A machine-wide lesson:
   `~/.claude/pj-global/notes/YYYYMMDD-slug.md` plus one line in `notes/INDEX.md` in its format.
   A new drawer, on a yes: `open-items init`.

5. Handoff, from `handoff` in `.claude/pj-homes` (default `repo:OPENING-PROMPT.md`).
   - pj-homes names a project `wrap-up` and the file lacks the marker below: that command owns it.
     Skip this step; carry your proposed lines to step 6.
   - Any other file without the marker was written by hand: do not overwrite it. Ask whether to
     write the generated text to a sibling path or put the next step in the report only.
   - Nothing changed and nothing new learned: keep the existing handoff.
   Otherwise rewrite it whole, never append, at most 60 lines (check with `wc -l`): where things
   stand, the literal next step, decisions waiting on the user, pointers to records (never their
   contents), hazards in flight including anything deployed that running sessions will not see
   until restarted, the date, and the session id read from
   `${CLAUDE_CODE_SESSION_ID:-$CLAUDE_SESSION_ID}` in a Bash call, never guessed. First line
   exactly `<!-- generated by /pj:wrap-up -->`.

6. Project wrap-up (Gavin, 5 Oct 2026: "Let it run them"). When `.claude/pj-homes` names one
   (`wrap-up: <command>`), it runs here, so tidy, delivery, push and the report all see its work.
   - First `open-items --grep "<command>" --all` and name any open item against it.
   - Print, on a line of its own, exactly: `pj:wrap-up hands over to <command>` (for example
     `pj:wrap-up hands over to /wrap-up`). The project command looks for that line.
   - Run it, with no question first (the user can interrupt): the Skill tool with the command's
     name (no leading `/`) and the args `from-pj-wrap-up` followed by step 5's handoff lines. If
     the Skill tool refuses (the command still says `disable-model-invocation: true`, or is not
     listed), Read `.claude/commands/<name>.md` (in a worktree: this checkout, then the main
     one) and follow every step, with those args as its `$ARGUMENTS`. Never a shell: a slash
     command is run by the model.
   - When it ends, carry on at step 7. It never runs `pj-wrap done`; step 10 marks the session.
     It stopped or failed (a step refused, a test failed, the user stopped it, the file is
     missing): note which step and why; step 10 records it as owed.
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
    (sandbox lifted). Then check the marker: `test -e ~/.local/state/pj/wrapped/${CLAUDE_CODE_SESSION_ID:-$CLAUDE_SESSION_ID}`;
    missing means NOT marked, say so. Not a git repo: `done` refuses (rc 2) and nothing can be
    marked. In a worktree the records belong to the main checkout.
    Then the report. Line 1, first that applies: not a git repo (the sentence from step 0); a
    STOP from step 9; an owed project wrap-up (which step stopped, and why); any other action
    for the user; "Done, nothing needed from you." Then copy VERBATIM the block
    `pj-wrap done` printed ("Filed and closed for you (the session's choice, not yours):", one
    line per record, ending `undo all: open-items undo-wrap <session-id>`; run that with the
    sandbox lifted). It printed none: say "Nothing filed or closed for you." Under it, each extend
    and lesson with its own undo. End with the pending list and one
    line: "Kept working after this? Run /pj:wrap-up again." Last, as its own Bash call:
    `pj-ping done "wrap-up <project>" --detach`. It returns at once (Gavin, 2026-09-29: the
    blocking send cost about 10 s); a failed send is named only in the ping log, not here.
