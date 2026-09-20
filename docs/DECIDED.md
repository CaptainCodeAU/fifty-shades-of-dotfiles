# decided -- has this already been settled?

`decided --help` is the usage. This file is the reasoning: why the tool exists, where it
looks and why, and what changed when the register split on 2026-09-21 (P5.5, ruling
D-20260920-10).

## Why a tool

2026-09-17: a session spent an evening re-deriving a ruling that was already written
down, because the document it was reading did not point at the one holding the decision.
The rule "check the record first" existed and did not fire. This repo's answer to a rule
that keeps being broken is a tool, not a fourth restatement (see `census` and `peek`).

The design point, borrowed from `census`: AN EMPTY RESULT IS THE ANSWER THAT LIES. "No
decision found" reads identically to "the register was never searched", so the tool never
prints a bare nothing. Every run states the denominator, per home, and a miss says out
loud that a miss is not the same as "not decided".

## The block

One ruling per block, the same shape `open-items` uses:

```
## D-YYYYMMDD-NN -- short title

topic: the words someone would actually type      (the grep surface; overload it)
decided: YYYY-MM-DD
status: standing | deferred | superseded | withdrawn
holds-in: the document that carries the reasoning (this block is an index, never the argument)

Body: the ruling in a paragraph or two, evidence, riders, ties to other IDs.
```

A decision recorded only in a commit message does not exist: commit messages are not
greppable by topic and nobody reads them before proposing. Put the decision in a document,
add a block, and have the commit point at the document.

## Where it looks (D-20260920-10, D-20260920-06)

| Home         | Path                                                                                                                             | Shape                                |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| machine-wide | `~/.claude/pj-global/decisions/`                                                                                                 | one file per block, `<ID>-<slug>.md` |
| this project | `decisions:` in `.claude/pj-homes`; default `repo:docs/decisions/`, or `drawer:decisions/` when the file says `records: private` | one file per block                   |
| legacy       | `~/.local/share/decisions/DECISIONS.md` (this repo's old register, now a stub)                                                   | one file, many blocks                |

Default scope is this project plus machine-wide. `--all` adds every drawer's
`decisions/` folder on the machine (enumerated the way `open-items --all` does) and the
legacy file. Outside a git repo there is no project, so machine-wide only, and the output
says so. An ID given on its own (`decided D-20260919-03`) matches on the header line;
when it is not in the default scope the tool looks everywhere once and says where it found
it, so a citation never dangles.

A declared store the tool cannot read (Network_Plan's per-box ledgers, a JSONL file) is
named as "declared store in an unsupported format, not searched". It is never silently
skipped and no parser for other projects' formats lives here; those projects keep their
own tools (D-20260920-02).

## Writing

`decided add "title" --topic "..." --holds-in "<doc>" --global|--project [--body ..]`
allocates the next `D-` ID through `pj-id` (this machine's slice of 01-99, so two machines
never claim the same ID on one day; see `docs/OPEN_ITEMS.md`), writes the file into the
chosen home, and commits it by explicit path when that home is inside dot-claude. A
`repo:` store is written and reported NOT COMMITTED (exit 3): the project repo is yours to
commit, the way `pj-wrap push` never pushes it.

`decided withdraw <ID> "reason"` sets `status: withdrawn` and commits. The ID stays
claimed; IDs never change and never get reused.

## The split, for the record

Until 2026-09-21 every block sat in ONE file in this PUBLIC repo, stowed to
`~/.local/share/decisions/DECISIONS.md`. About a third of it was machine-wide. Under
D-20260920-10, 9 machine-wide blocks moved to `~/.claude/pj-global/decisions/` and 17 of
this project's own to its private drawer, one file per block, block text unchanged,
each verified by content hash (with a control that had to fail) before it left the public
file. Two blocks stay in the public stub: D-20260919-04 (LifeOS-owned) and D-20260920-11
(the pointer that bridged the gap). The moved blocks remain in this repo's git history;
that history was not rewritten and no scrub is proposed.

The stowed stub and the symlink stay: census with a control found only `decided` itself
and `CLAUDE.md` reading that path, and keeping it costs nothing while it lets `--all`
reach the two remaining blocks.

## Exit codes and the selftest

`0` match or written, `1` no match (not an error), `2` REFUSED (no readable home, bad
args, empty scope: none of these is "no decisions"), `3` written but not committed.
`decided --selftest` runs `decided-selftest` against a fixture (two repos, a fixture
dot-claude with the machine-wide home and two drawers, a legacy file): the original six
arms, each scope rule above, the unsupported-format line with its control, an ID found
outside scope, `--all` counting every home, outside-a-repo, `add` committing by explicit
path and refusing without its required fields, `withdraw`.
