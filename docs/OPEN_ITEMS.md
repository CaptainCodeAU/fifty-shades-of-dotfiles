# open-items -- what is still open, scoped to the project you are standing in

`open-items --help` is the usage. This file is the reasoning, moved out of the tool's
header on 2026-09-20 (P5.1) because a session was measured reading 71 lines of essay twice
to find the flags.

## Why a tool and not just a folder layout

What gets an item IN FRONT of Gavin is the SessionStart hook, not the file. A list he has
to remember to type is a list he will not see. So this tool is the query layer, and
`--session` is the surface that actually speaks. It is short on purpose: it feeds a
20-line start card (D-20260920-04), open items as a count then titles, parked as a count.

The card keeps only 10 titles, so `--session` lists PINNED items first (W-20260923-A23):
an open item whose header `when:` begins with `next session`, in any case, is printed first
and marked `[pinned]`, and the count line says `N pinned`. Everything else follows in ID
order as before. There is no pin/unpin command: `open-items set <ID> when "next session"`
pins, and changing `when` unpins. Without this, an item filed today for the very next session
has the newest ID and lands last; on 2026-09-23 eight of them were open and the card showed
none.

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

A project with NO drawer at all is a third case, and its fix is `open-items init`, not
`migrate`. A write there refuses and names `init` (W-20260923-A15); a write into a legacy
drawer refuses and names `migrate`. The two messages used to be one, which sent a brand-new
project to `migrate`, and `migrate` then refused for want of an `OPEN.md` to convert.
`add` does not run `init` for you: creating a drawer is a separate, visible step.

## The item model (D-20260920-05)

One file per item, `items/<folder>/W-YYYYMMDD-LNN.md` (L = the machine letter, P8a), in the same block shape
`decided` already parses:

```
## W-20260920-A10 -- short title

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

`set` REPLACES a field. On a non-empty text field (`next`, `when`, `done-when`,
`blocked-on`) that replace prints a WARNING naming how many characters it dropped and the
old text, unless the new value starts with the old one. To add rather than replace, use
`set --add` (or `--append`): a text field gets `; <value>` on the same line, and `body`
gets a new paragraph at the end of the file. `body` is append-only, because the same place
holds the `**DONE date.**` notes that `close`, `park` and `decline` write. `set --add
holds-in` is unchanged: one more line (W-20260923-A20).

`parked` means do not work it and do not re-ask until Gavin raises it; it covers
parked-by-Gavin and decision-withheld. `closed/` holds both `done` and `declined`.
`declined` is what the wrap-up writes for "leave it", so it is not asked again.

## Every write is a commit (D-20260920-08 c)

`add`, `close`, `park`, `decline`, `reopen`, `set`, `init`, `regen`, `migrate` each:

1. take a per-drawer lock (`items/.lock`, a directory; a dead holder is taken over),
2. write the item file (the ID comes from `pj-id`, which stamps it with this machine's
   letter and hands out `01`-`99` under it; the file is claimed with `noclobber`, next
   free number on a clash. No machine letter, no ID: `pj-id` refuses),
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
2026-09-20, W-20260921-A01): the ID was claimed by creating the file, atomic on one machine
and blind to a clone that claimed the same `W-YYYYMMDD-NN` the same day.

**Since P8a (2026-09-21) the ID names the machine that minted it: `W-20260921-A07`.**
`pj-id` reads the letter from `~/.config/pj/machine` (`name:` and `letter:`, written by
`install.sh`, which asks which machine this is) and hands out `01`-`99` under it. Gavin's
four: **A** the M4 Mac mini, **B** the Intel Mac laptop, **C** the PC's WSL2 Ubuntu,
**D** a Proxmox Linux VM. Two machines cannot produce the same item PATH at all, so the
collision is structurally gone rather than merely unlikely. The same allocator serves
`decided add`, and `pj-wrap push` keeps its add/add STOP as a second line of defence.

**There is NO DEFAULT LETTER, and that is the point.** `pj-id` REFUSES on a box whose
machine file is missing or letterless, so `open-items add` is dead there until
`./install.sh` runs. P5.5's interim scheme (`range: 01-49` / `50-99`) did default, and a
default was safe then because the worst case was a duplicate NUMBER. A default letter
would put another machine's name on this machine's work, which is a wrong record rather
than a clash, and a wrong record is the thing this whole store exists to prevent. The
`range:` key is retired; `pj-health`'s `machine-file` row FAILs on a file that still
carries it, naming the fix.

**Every pre-P8a ID still resolves.** The 2026-09-21 migration renamed 76 files and their
`## ` header lines, but the ~680 citations inside reports, handoffs and committed docs were
deliberately left as history. So `open-items close|park|set|reopen|decline` accepts a bare
`W-YYYYMMDD-NN`, resolves it to the letter form, and SAYS which ID it resolved to. Two
items answering to one legacy ID (the same number under two letters) is REFUSED with both
named, never guessed. `decided` does the same for `D-` IDs.

## Multi-drawer output: the blank line between drawers is load-bearing (X0, 2026-09-22)

`--all` used to GLUE the first header of each drawer onto the previous drawer's last body
line. Measured on the real drawers: `open-items --all` printed 28 `## W-` headers of which
only 26 started a line, and `--all --closed` 94 of which 91 did. The glue count was exactly
(drawers emitting minus 1) in both arms, so every boundary was affected, not some:

```
...exit 2.## W-20260920-A01 -- 331 of 335 files under lifeos-private...
```

Anything reading the output line by line, a session included, lost one item per boundary.

**The cause was the PRINTER, and that was measured rather than assumed.** `report()`
captured each drawer with `hits="$(blocks_from ...)"`, and `$(...)` strips every trailing
newline, so a bare `printf '%s'` emitted the drawer ending on its last body byte. The
obvious suspect, an item file saved without its final newline, was ruled out with a pair of
arms: such a file glues NOTHING inside a drawer, because `blocks_raw` already appends its
own `\n` after each `cat`, while two perfectly well formed drawers still glued. A writer
side normalisation would have fixed none of it. Gavin ruled printer only at the X0 gate.

`report()` now ends each drawer with `printf '%s\n\n'` and the footer no longer carries a
leading `\n` of its own. The second newline is the blank line BETWEEN drawers, which keeps
the boundary looking like every other join in the output.

**One cosmetic gap is knowingly left.** When an item file ends without a newline, the blank
line between it and the NEXT record in the same drawer is missing. The header still starts
its own line, so nothing is lost to a line-by-line reader, and the fix for it belongs on
the writer side. Filed, not solved.

Section H of the selftest holds the arms, with the three controls that make the absence
readable: a denominator drawn from the number of item FILES rather than from the text being
measured, a deliberately glued string that the instrument must still detect, and a single
drawer that was never glued before the fix or after.

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
