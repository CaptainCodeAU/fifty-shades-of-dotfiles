# open-items -- what is still open, scoped to the project you are standing in

`open-items --help` is the usage. This file is the reasoning, moved out of the tool's
header on 2026-09-20 (P5.1) because a session was measured reading 71 lines of essay twice
to find the flags.

## Why a tool and not just a folder layout

What gets an item IN FRONT of Gavin is the SessionStart hook, not the file. A list he has
to remember to type is a list he will not see. So this tool is the query layer, and
`--session` is the surface that actually speaks. It is short on purpose: it feeds a
20-line start card (D-20260920-04), open items as a count then titles, parked as a count.

## Where the drawer lives

Each repo's drawer is `~/.claude/projects/<key>/memory/WORK/`, inside the harness memory
dir Claude Code already keeps for that repo (D-20260919-03). `<key>` is the repo's
toplevel path with every `/`, `.` and `_` turned into `-`, the harness's own encoding. It
is LOSSY, so a key is never decoded back into a path: the current repo is matched forward
from its toplevel, and `--all` reads each drawer's own `project:` field for its name.

Never put a drawer file loose in `memory/` itself (that level is scanned flat by LifeOS's
harvester) and never nest it as `memory/MEMORY/WORK/` (the global `MEMORY/` ignore rule
would un-version it). Research folders sit beside the items under `WORK/`.

## Two layouts, both read

| Layout                | On disk                                                                 | Written by                             |
| --------------------- | ----------------------------------------------------------------------- | -------------------------------------- |
| items (D-20260920-08) | `WORK/items/open/`, `parked/`, `closed/`, `notes/`; `OPEN.md` GENERATED | the tool only                          |
| legacy                | one hand-edited `WORK/OPEN.md`                                          | nobody any more; read-only to the tool |

A legacy drawer keeps working for reads (`--all`, `--session`, `--project`). Every write
command refuses on it. `open-items migrate` converts the CURRENT repo's drawer once, and
only when it resolves inside dot-claude. The `~/.claude` drawer itself belongs to LifeOS,
lives behind a symlink into lifeos-private, and stays legacy.

## The item model (D-20260920-05)

One file per item, `items/<folder>/W-YYYYMMDD-NN.md`, in the same block shape
`decided` already parses:

```
## W-20260920-10 -- short title

project: fifty-shades-of-dotfiles
status: open              open | parked | done | declined
kind: do                  do | decide
size: small               small | medium | large; do items only
done-when: what finished looks like      REQUIRED; add refuses without it
when: trigger                             optional
next: first step or command               optional
blocked-on: what it waits for             optional
holds-in: repo:docs/X.md                  root marker: repo: | drawer: | ~/; MAY REPEAT,
holds-in: ~/.local/bin/y                  one marked path per line (P5.3; `set` replaces
                                          the set, `set --add` appends one line)
raised: 2026-09-20 (session <id>)         tool-filled

Body prose.
```

`parked` means do not work it and do not re-ask until Gavin raises it; it covers
parked-by-Gavin and decision-withheld. `closed/` holds both `done` and `declined`.
`declined` is what the wrap-up writes for "leave it", so it is not asked again.

## Every write is a commit (D-20260920-08 c)

`add`, `close`, `park`, `decline`, `reopen`, `set`, `init`, `regen`, `migrate` each:

1. take a per-drawer lock (`items/.lock`, a directory; a dead holder is taken over),
2. write the item file (the NN comes from `pj-id`, which hands out this machine's slice
   of 01-99; the file is claimed with `noclobber`, next free number on a clash),
3. regenerate `OPEN.md`,
4. commit by explicit pathspec: this project's `items/` and `OPEN.md`, nothing else in
   dot-claude. A write left uncommitted by an earlier failure rides along with the next.

The commit happens only when the drawer's REAL path (`pwd -P`) is under
`<dot-claude>/projects/<key>/memory/`. Anywhere else, the file is written and the tool
prints `NOT COMMITTED, outside dot-claude` and exits 3. A failed commit (hook, lock that
never clears, a path a gitignore rule swallows) also exits 3 with `COMMIT FAILED`; the
file is never lost. A transient `index.lock` is retried.

Exit codes: `0` found or written, `1` nothing found (not an error), `2` REFUSED, `3`
written but not committed.

## OPEN.md is generated. A hand edit is rescued, never dropped

The tool keeps the hash of the last view it wrote in `items/.generated.sha256`. Before
every regeneration it compares. If `OPEN.md` differs, someone edited it by hand: the file
is copied to `items/notes/<timestamp>-hand-edit-rescued.md`, a warning names that file,
and the view is rebuilt. Move what you need into an item with `open-items add`. Rescued
files are committed with the write, and are not re-shown in the view.

## Known limitation (recorded 2026-09-20, not solved)

`OPEN.md` is a generated file tracked in git, so two machines adding items will conflict
on it at push time. `pj-wrap push` (P5.3) handles exactly that: on a conflict only in
`OPEN.md` or `items/.generated.sha256` it takes origin's copy and regenerates the view
with `open-items regen`, never merges it.

**Item IDs used to collide ACROSS machines** (measured by `pj-wrap-selftest` on
2026-09-20, W-20260921-01): the ID was claimed by creating the file, atomic on one machine
and blind to a clone that claimed the same `W-YYYYMMDD-NN` the same day. Since P5.5
(2026-09-21) the NN comes from `pj-id`, which reads `~/.config/pj/machine` (`name:` and
`range: 01-49` or `50-99`, written once by `install.sh`; an absent file means 01-49) and
refuses loudly when the range is exhausted. Measured before choosing 49: the most IDs
claimed in one day on this machine were 9 W and 11 D. The same allocator serves `decided
add`. `pj-wrap push` keeps its add/add collision STOP as the second line of defence; a
box that never wrote its machine file still sits on 01-49, so two such boxes can still
collide, and the stop is what catches that.

## The design point, borrowed from census and decided

AN EMPTY RESULT IS THE ANSWER THAT LIES. "No open items" reads identically to "the drawer
was never found" and to "this project has no drawer yet". Those are three different facts
and this tool says which one it means, every time, with the denominator attached. There is
deliberately no derived `INDEX.md`: `--all` is the machine-wide view, computed live.

## Selftest

`open-items --selftest` runs `open-items-selftest`: the original arms (the kinds of
nothing, filtering, per-repo resolution, scope, the session surface) plus, since P5.1,
every command, the required-field refusal with its passing control, twenty concurrent
adds all committed, a mixed machine (one legacy, one items), the symlinked drawer that
must not be committed, a commit refused by a hook that must not lose the write, a
transient index lock, hand-edit rescue with its control, regeneration, and migration
(dry run into scratch, then real).
