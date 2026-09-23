# Open items across projects, and IDs unique across the machine

Ruled by Gavin 2026-09-23 (15:47 to 16:05 +1000), in session `fifty-shades-of-dotfiles-main`,
closing the design half of W-20260923-A16 (cross-project items) and W-20260923-A22 (unique IDs).
Nothing in this document is built yet unless a section says so. The register blocks that point
here are found with `decided cross-project` and `decided unique ids`.

The per-project layout, the item file format and "every write is a commit" live in
[`OPEN_ITEMS.md`](OPEN_ITEMS.md). This document adds what happens when an item concerns more than
one project.

## Why this came up

A claude-switcher session found a bug in `open-items` (W-20260923-A15) and could only leave it for
Gavin to carry, because there was no way to file into another project. Separately, an item was
filed into `cc-claude-mods` by running `open-items` inside that repo, with no record of who filed
it. And item IDs turned out to be unique per drawer only: 12 W- IDs repeat across drawers today
(measured 2026-09-23 by the decided-filters worker; W-20260923-A01 appears three times).

## The design, on one page

```
 filing:   open-items add --for <one owner>  [--watch p] [--check p "done-when"]  [--inbox]
 item:     lives in the owner's drawer only; records filed-by (project + session)
           optional  reach: machine | mandatory
 cards:    owner      -> the item, as today
           watcher    -> a "Watching" line, flagged when the item changed, until marked seen
           check-p    -> that project's own check, until ticked or passed
           mandatory  -> every project, computed live, until its check passes there
           machine    -> the owner only; the tool refuses watchers and checks
           inbox      -> "Inbox: N unrouted" on every card, only when non-empty
 groups:   group: <name> in each repo's own .claude/pj-homes
 moves:    an agent may move an item within a group (history + notice); across groups = Gavin
```

## Gavin's six cases, and what each became

Every case was put to Gavin with 3 or 4 options; the rejected ones are listed so nobody
re-proposes them without new evidence.

### 1. An item belongs to one project, and others must stay across it

**Owner plus watchers, live, with a changed flag.** The owner's item carries one
`watch: <project>` header line per watcher (repeatable; settled 2026-09-23, earlier text here
said `watchers: <project>, <project>`). Each watcher's start card shows its watched items, read live
from the owner's drawer (never copied), and flags any that changed or closed since that project
last marked them seen. The seen/unseen state reuses the pattern the Mods API card line already
uses.

Rejected: a live line with no changed flag (a closed item just vanishes, which looks the same as
the check never running); a stub copied into each watcher's drawer (copies drift the first time
the owner edits or closes); a notice on change only (nothing reminds anyone the item is open).

### 2. A shared item that affects two or more projects equally

**One owner drives it; every other affected project gets a check.** A check is one line on the
item: a project plus its own done-when, ticked separately. It covers Gavin's "maybe the second
project only needs a simple test". The item closes only when the owner's work AND every check are
done.

Rejected: co-owned with several owners (when each owner thinks the other is driving, nobody
drives); separate linked items (the link gets missed); watchers only (the second project's check
is never tracked).

### 3. A small rule that is true in every repo must not list every project

Example: deleted files go to the Trash, built in the dotfiles, true everywhere.

**`reach: machine`, enforced by the tool.** The item stays with its owner and shows only on the
owner's card. `open-items` REFUSES to add watchers or checks to a `reach: machine` item, so a
session cannot "helpfully" fan it out. When it is done, the outcome is written ONCE into
pj-global as a rule or a note, which every session already loads.

Rejected: a plain item plus a written rule (relies on every session remembering); a separate
"machine" drawer (ownership thins out; the dotfiles session builds these anyway); a count line on
every card (the noise this case exists to prevent).

### 4. A rule every project must adopt, whether it wants to or not

Example: every project runs Python as `uv run python3`, never bare `python3`, assuming no wrapper.

**`reach: mandatory`, computed live.** No project list is stored on the item. Each project's card
works out, at read time, which mandatory items that project has not yet passed, so a project
created next month inherits every rule automatically. Each mandatory item carries a runnable
check where one can be written (a scan for bare `python3`, say); where none can, a manual tick
per project. It reuses the check mechanism from case 2.

Rejected: writing one check per project at creation (a later project never gets it); a pj-global
rule with no tracking (nobody knows who complies); ticks only (a pass becomes a claim, not a
measurement).

### 5. Umbrella groups of related repos, and moving an item to where it belongs

Example: several repos under one startup, for server deployments and app builds.

**5a. A group is declared by each repo, in its own `.claude/pj-homes`:** `group: <name>`. Same
shape as `session-alias`, so membership is always explainable from the repo's own files; there is
no central table to drift.

Rejected: a central groups file in pj-global (a second place to keep in sync); groups derived
from the folder layout (moving a folder silently changes the group).

**5b. An agent may move an item to another project in the SAME group.** The item keeps its
history (moved from, by which session, why), and the project it left gets a seen/unseen notice.
A move ACROSS groups stays Gavin's call.

This AMENDS D-20260918-A02, which said unclear routing is Gavin's call. It still is, except for a
move inside one group, where an agent may act and must leave the trail.

Rejected: every move is Gavin's (he carries every misfiling); an agent may move anything
anywhere (items drift away from where he expects them).

### 6. `--for` with more than one project, and a shared inbox

**6a. `--for` names exactly one owner.** Other projects are added with `--watch <p>` (case 1) or
`--check <p> "done-when"` (case 2). The item records the project and session that filed it.

Rejected: the first project named owns it (the order of names silently decides ownership); a
copy per project (the drift ruled out in case 1).

**6b. Yes, a shared inbox, for UNROUTED items only.** `open-items add --inbox` when the owner is
unclear. The inbox is a normal drawer, tracked in dot-claude. It is NOT pj-global: pj-global
holds rules, notes and rulings, never items. Every card shows one line,
`Inbox: N unrouted, yours to route`, and only when the inbox is not empty. Gavin routes; the item
then moves to its owner with its history, like a case 5 move.

Rejected: no inbox, flag the item where filed (it sits in the wrong list); one inbox per group
(an item with no group has nowhere to go).

## Unique IDs (W-20260923-A22)

Gavin: "all IDs should be unique ... maybe not adding the project's name because a repo name or a
project folder name could also change". So no part of an ID comes from a project, repo or folder
name.

**The scheme: every drawer passed to `pj-id`, plus a machine-wide claim folder.**

- `open-items add` passes EVERY drawer (and every legacy OPEN.md) to `pj-id`, not only its own.
  `decided add` already passes every D- store, which is why no D- ID repeats today.
- Before writing, the tool CLAIMS the ID with a no-clobber create in one folder,
  `~/.local/state/pj/ids/`. Machine state, never a repo. The machine letter already separates
  machines, so the folder never needs to sync.
- Measured by the decided-filters worker in `$TMPDIR` fixtures, both processes released at the
  same instant (the worst case): passing every drawer alone, 20 of 20 races produced a duplicate,
  because no-clobber only catches a clash inside one folder. With the claim folder, 0 of 20.
- Cost measured: 126 ms per allocation over one drawer, 285 ms over all four (mean of 5).
  `pj-id` runs one `find` per candidate per store; one listing pass would flatten that.
- The 12 duplicates already on disk are LEFT. Any lookup that crosses drawers (`show`, `get`,
  `supersede`, and the moves above) REFUSES an ambiguous ID and names every drawer holding it.
  Re-keying with an alias stays possible later; it would mean editing about 13 files in 4 drawers
  plus their citations.

Rejected: passing every drawer without a claim (simultaneous adds still collide); a machine-wide
lock (race-proof too, but a session that dies holding it needs stale-lock recovery).

The unique IDs come first: every watcher list, check and move above names items across drawers,
and an ID that means two things breaks all of them.

## Safety rules (accepted by Gavin 2026-09-23, all twelve)

A read-only safety review of the build spec proposed twelve rules; Gavin accepted every one
before the build started. They bind the build as firmly as the design above. The full text,
with each risk, scenario, rule and selftest arm, and the options considered and rejected, is
[`OPEN_ITEMS_CROSS_PROJECT_SAFETY.md`](OPEN_ITEMS_CROSS_PROJECT_SAFETY.md). Two holes were
proven by test there before any rule was written: `add` accepted a newline that forged header
lines, and a terminal escape in a title reached the start card intact.

| #   | Rule, one line                                                                                                                                               |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| P1  | Header values refuse control characters; every cross-project field is read from the header only                                                              |
| P2  | `tick`, `pass`, `seen` write only the current project's own state; no manual pass when a script exists; ticks record who                                     |
| P3  | The start card never runs a script and never writes; a detached runner that `pj` starts fills a cache the card reads                                         |
| P4  | A check-script runs only if its name is plain, its real path is inside the dotfiles repo, and its content equals master                                      |
| P5  | Exit 0/1/other = passed/not passed/unknown; a pass must print `scanned: N` with N > 0; each script ships pass and fail fixtures; clean environment           |
| P6  | The pass cache key includes the item hash and the script's committed blob; only an explicit positive record is a pass                                        |
| P7  | Another project's text is data: controls and bidi stripped, length capped, source labelled                                                                   |
| P8  | `reach: mandatory` only from the dotfiles project or a human at a terminal; at most 5 watch and 5 check lines; 5 card lines kept for the project's own items |
| P9  | Project names compared as exact tokens; a name shared by two drawers is refused; `inbox` and `none` reserved                                                 |
| P10 | A `repo:` line counts only if it matches the drawer's own key and resolves; back-fill never overwrites                                                       |
| P11 | The moved-out notice is built; groups read from committed `pj-homes`; no move back to a former owner; `route` needs a human at a terminal                    |
| P12 | Two-drawer writes lock in a fixed order, never overwrite a destination ID, commit both drawers together, and the inbox is committable                        |

P3 changes WHEN a mandatory check is computed (by a runner after the card, read from cache),
not WHETHER: "computed live" in case 4 now means "measured by the runner, never stored as a
claim". P8 and P11 make two of the ruling's "Gavin's call" points enforced by a terminal check,
since an agent's Bash has no terminal (measured by the reviewer).

## What is built, and what is not (as of 2026-09-23)

- Merged 2026-09-23: `show`, `get`, `--json` and a current-drawer `supersede` refuse an
  ambiguous ID (W-20260923-A24, 4f629df).
- Merged 2026-09-23: the unique-ID scheme, `pj-id claim` with the claim folder, used by
  `open-items add` and `decided add` (W-20260923-A22, 249e1b5..fda6fe7), and the `add` hang fix
  (W-20260923-A25).
- Merged 2026-09-23 (Gavin's go given): the A16 design above with all twelve safety rules
  (W-20260923-A28): write side a4f8026, read side 7408125. Stowed and live.
- Read side built 2026-09-23 on branch `a16-read` (not merged when written): `--session`
  Watching / Checks owed / Mandatory / Moved out / Inbox, `seen`, `checks-run` started
  detached by `pj`, the card's own-title floor, `mandatory-checks-selftest`. What it does:
  [`OPEN_ITEMS.md`](OPEN_ITEMS.md), section "Other projects' items on your card".
