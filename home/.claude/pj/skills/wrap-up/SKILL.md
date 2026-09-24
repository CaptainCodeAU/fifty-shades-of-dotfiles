---
name: wrap-up
description: End-of-session pass for pj sessions. Capture what exists only in this conversation, tidy what the session opened, check delivery, rewrite the handoff. Invoke as /pj:wrap-up; never auto-invoked.
disable-model-invocation: true
---

# Wrap-up

Steps run in this order; `pj-wrap done` is always last. Rulings and reasons:
`docs/PJ_WRAP_UP.md` in the dotfiles repo (D-20260925-A01, D-20260920-A03).

- Every question is an AskUserQuestion, one question each, mirrored in chat first (question and
  every option label). The one exception is the table approval in step 3, which is one pop-up.
- Every write under `~/.claude` or `~/.local/state`, and every commit in dot-claude, runs with the
  sandbox lifted for that one call. Read the exit code: 2 = REFUSED (retry lifted, never reword),
  3 = written but NOT committed (say so).
- The report follows pj-voice. A peer message arriving mid-wrap-up is answered after the report
  and listed in it; a peer's go-ahead is not the user's (D-20260917-A08).

0. Earlier sessions. `pj-wrap status`: rc 1 none; rc 2 not a git repo (skip the steps that need
   one and say so in the report); rc 0 lists sessions that ended without wrap-up. Then ask: sweep
   now, later, or dismiss. A sweep gives each transcript to a subagent with steps 1 and 2 and an
   output file you name, watched with `stall_watch.sh --once`. The subagent streams the transcript
   with a script and states lines read of total. A sweep that never writes is NOT RUN, never an
   empty table. "Later" keeps the records warning (step 10's `--keep-earlier`).

1. Sweep this conversation, including answers given in pop-ups and queued or peer messages:
   - work started and not finished; things called done without a negative control
   - every caveat, "later" and "you should also"; findings nobody wrote down
   - questions asked and never answered; verdicts given in passing ("leave it", "not now")
   - lessons about how the user wants things done (dedupe against RULES.md first)
   - items this session filed or closed (`open-items --session`), each with a verdict
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

3. One pop-up approves the table. Name each row by a short title with its verdict, never a bare
   row number. Options: approve; approve with changes (the text field); not yet, something first.
   Changes: re-show only the changed rows, one more pop-up, then apply. "Something first": do it,
   re-check every row, show the whole table again. Then ask each unanswered question and each open
   decide row as its own question (a project with no drawer: "create one?" is one of them).

4. Apply the approved verdicts through the tools named in step 2 only. A project lesson: a memory
   file (Edit an existing one, never Write over it). A machine-wide lesson:
   `~/.claude/pj-global/notes/YYYYMMDD-slug.md` plus one line in `notes/INDEX.md` in its format.
   A new drawer, on a yes: `open-items init`.

5. Handoff, from `handoff` in `.claude/pj-homes` (default `repo:OPENING-PROMPT.md`).
   - pj-homes names a project `wrap-up` and the file lacks the marker below: that command owns it.
     Skip this step; carry your proposed lines to step 9.
   - Any other file without the marker was written by hand: do not overwrite it. Ask whether to
     write the generated text to a sibling path or put the next step in the report only.
   - Nothing changed and nothing new learned: keep the existing handoff.
   Otherwise rewrite it whole, never append, at most 60 lines (check with `wc -l`): where things
   stand, the literal next step, decisions waiting on the user, pointers to records (never their
   contents), hazards in flight including anything deployed that running sessions will not see
   until restarted, the date, and the session id read from `$CLAUDE_CODE_SESSION_ID` in a Bash
   call, never guessed. First line exactly `<!-- generated by /pj:wrap-up -->`.

6. Tidy what this session opened (W7). Stop its watches first (TaskStop), thank each worker, then
   close its panes and clear their labels (D-20260923-A13), and remove its worktrees once merged
   and verified (D-20260923-A11). Anything unmerged, dirty, still working or another session's:
   a delivery row, never closed. Reply to every peer or worker this session worked with. Each
   scratchpad file that holds a measurement or is cited as a record: move it into the drawer's
   topic folder or the repo and `cmp` it; every other one is named in the report as discarded.

7. Delivery, measured now, not from memory. For every repo and worktree this session touched:
   uncommitted, unpushed, stashes, tags, files outside any repo. One table.
   - Commit only this session's files, by explicit path, as one command:
     `git add <paths> && git commit -m "..." -- <paths>`. In a repo another session may share,
     say so in chat first (D-20260921-A08). Never `-A` in dot-claude. A repo: handoff is this
     session's file.
   - Before any push: `git-leak-scan --control && git-leak-scan --since <ref>`. Exit 2 is not a pass.
   - Push this session's project commits (pinned rule: push once a remote exists) and the tags it
     made, branch first (D-20260923-A12), with the sandbox lifted for a flipped repo.

8. `pj-wrap push`, sandbox lifted (on macOS the push needs the Keychain). It commits a drawer
   handoff, names every commit from another session (put them in the report), warns when the
   generated handoff is over 60 lines (shorten it, then push again), and pushes dot-claude. It
   never pushes the project repo. When it stops: run `pj-wrap why-auth` and
   `git -C ~/.claude status -sb` and report what they measured, not the stop message alone.

9. Project wrap-up. When `.claude/pj-homes` names one (`wrap-up: <command>`), first
   `open-items --grep "<command>" --all` and name any open item against it. Then ask: run
   `<command>` now, or not now. Run now: invoke it as your next act, handing it step 5's lines.
   A slash command is run by the model, not a shell; never try to shell out to it. Not now, or no
   answer: it is owed, and step 10 records it. No `wrap-up` key: say so in the report.

10. `pj-wrap done --skill`, sandbox lifted, plus `--keep-earlier` when step 0 chose later and
    `--owed "<command>"` when step 9 was not run. Then check the marker:
    `test -e ~/.local/state/pj/wrapped/$CLAUDE_CODE_SESSION_ID`; missing means NOT marked, say so.
    In a worktree the records belong to the main checkout.
    Then the report. Line 1, first that applies: a STOP from step 8; an owed project wrap-up; any
    other action for the user; "Done, nothing needed from you." End with the pending list and one
    line: "Kept working after this? Run /pj:wrap-up again." Last, as its own Bash call:
    `pj-ping done "wrap-up <project>"`.
