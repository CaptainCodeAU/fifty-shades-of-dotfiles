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

`add`, `close`, `park`, `decline`, `reopen`, `supersede`, `set`, `init`, `regen`, `migrate`,
and since A16 `watch`, `check`, `tick`, `pass`, `move`, `route` each (a move or route takes
two locks and makes ONE commit for both drawers; see "Across projects" below):

1. take a per-drawer lock (`items/.lock`, a directory; a dead holder is taken over),
2. write the item file (the ID comes from `pj-id claim`, which stamps it with this
   machine's letter, hands out `01`-`99` under it after scanning EVERY drawer, and claims
   it in `~/.local/state/pj/ids/`; the item file is then created with `noclobber`. No
   machine letter, no ID: `pj-id` refuses. A create that is refused, in the claim folder
   or in `items/open`, refuses by path and never loops, W-20260923-A25),
3. regenerate `OPEN.md`,
4. commit by explicit pathspec: this project's `items/` and `OPEN.md`, nothing else in
   dot-claude. A write left uncommitted by an earlier failure rides along with the next.

The commit happens only when the drawer's REAL path (`pwd -P`) is under
`<dot-claude>/projects/<key>/memory/`, or is the inbox `<dot-claude>/pj-inbox`. Anywhere else, the file is written and the tool
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

**Since 2026-09-23 an ID is unique across every drawer on the machine (D-20260923-A10,
W-20260923-A22).** Until then `add` passed only its own drawer to `pj-id`, so two projects
minted the same ID on the same day; 12 W- IDs exist twice or three times because of it.
Now `add` passes every drawer's `items/` and every legacy `OPEN.md`, and `pj-id claim`
CLAIMS the chosen ID with a `noclobber` create in one machine-wide folder,
`~/.local/state/pj/ids/` (one empty file per ID; machine state, never a repo, never synced,
because the letter already separates machines). Passing every drawer alone was not enough:
two adds in two projects released at the same instant both saw the same free number and
both created their own file, since `noclobber` only guards one folder (measured 20 of 20).
The shared folder makes the create itself the arbiter (0 of 20; `open-items-selftest`
section U and `pj-id --selftest` keep that race as a standing arm with a claim-off
control). The folder only adds to the scan and never replaces it, so an empty or wiped
folder still yields a free ID. No part of an ID comes from a project, repo or folder name.
The old duplicates are LEFT; lookups across drawers refuse them (below). Cost, measured
read-only over the five real stores with 32 of the day's IDs present (mean of 10): 435 ms
per allocation on the old scanner, 45 ms now, because the scan is one `find` per store
instead of one per candidate per store. Both return the same ID.

Test seams: `PJ_ID_CLAIMS_DIR` moves the folder, and `pj-id` REFUSES a fixture
`PJ_MACHINE_FILE` paired with the real folder, so no selftest can write it.
`PJ_ID_CLAIM=off` switches the claim off for the race control, honoured only with a
fixture folder.

**Every pre-P8a ID still resolves.** The 2026-09-21 migration renamed 76 files and their
`## ` header lines, but the ~680 citations inside reports, handoffs and committed docs were
deliberately left as history. So `open-items close|park|set|reopen|decline` accepts a bare
`W-YYYYMMDD-NN`, resolves it to the letter form, and SAYS which ID it resolved to. Two
items answering to one legacy ID (the same number under two letters) is REFUSED with both
named, never guessed. `decided` does the same for `D-` IDs.

## Reading one item, searching, JSON, supersede (W-20260923-A24, A21; 2026-09-23)

```
open-items show <W-ID> [--project p] [--json]      one item, any status, any drawer
open-items get <W-ID> <field> [--project p]        raw value; also id | title | body | file
open-items --grep "words" [--all] [--closed]       every word, case-insensitive
open-items [--all | --project p] [--closed] --json  the listing as one JSON object
open-items supersede <old> <new> [--project p]     decline old -> new, back-pointer on new
```

**IDs minted before 2026-09-23 can repeat across drawers** (see above; new ones cannot).
`W-20260923-A01` was in three drawers on the day this was built, so `show`, `get` and `supersede` search EVERY drawer, and an ID found in two
is REFUSED (exit 2) with the projects named. They never prefer the current repo's copy:
that would be a guess that reads like an answer, and on a write it edits the wrong item.
`--project <name>` settles it. Two drawers with the SAME name cannot be told apart by it;
the refusal then prints their paths. A bare pre-P8a ID resolves as it does for `close`.

**`show`** prints the block on stdout and `<id> in <project> (<path>)` on stderr, so the
block pipes clean. It works on legacy drawers too, and stops at the next `## ` section. A
miss is exit 1 with the denominator: items searched, every status, and the drawers.

**`get`** prints one field's raw value. A field that repeats (`holds-in`, `supersedes`)
prints every value, one per line. An ABSENT field is exit 1 and names the fields that are
present, because an empty line on stdout reads the same as a field that is present and
empty. `body` is the prose after the header; `title`, `id` and `file` are derived.

**`--grep`** searches the title, the body and the free-text fields (`done-when`, `next`,
`holds-in` ...). It does NOT search the tool-owned lines `project`, `status`, `kind`,
`size`, `raised`: every item carries its project name and a session ID, so a search for
either would match the whole drawer. Scope follows the listing: the current drawer by
default, `--all`, `--project`, and `--closed`/`--status`. A miss prints the denominator,
for example `no match for "x" in 41 open item(s) across 1 drawer(s)`, and says which of
`--closed` and `--all` would widen it. Quote a phrase: the words are ANDed.

**`--json`** is jq-free and jq-valid (the selftest runs `jq .`, with a control proving jq
rejects a raw control character, and round-trips a body holding quotes, backslashes, a tab,
a 0x01 and non-ASCII). The escaper walks each string one character at a time instead of
using awk's `gsub`, because awks disagree on backslashes in a `gsub` replacement. Shape:

```
{"scope":"every project","status_filter":"open","grep":null,
 "drawers_searched":5,"items_searched":54,"count":54,"items":[
 {"id":"W-...","title":"...","project":"...","status":"open","drawer":"...",
  "layout":"items","fields":{"done-when":"...","holds-in":["repo:a","repo:b"]},"body":"..."}]}
```

The top-level `project` and `status` are the EFFECTIVE values (status defaults to open, as
the listing filter reads it). `fields` is raw: `holds-in` and `supersedes` are always
arrays, any other field is a string unless it repeats, and then an array, so nothing in the
file is dropped. A miss is exit 1 and still prints valid JSON with `count: 0`. `show --json`
prints the single item object.

**`supersede <old> <new>`** declines the old item, adds `superseded-by: <new>` to its
header and a dated `**DECLINED**` note naming the new title, moves it to `closed/`, and
adds `supersedes: <old>` to the new item (repeatable: one item can replace several). One
lock, one commit, through the same `finish_write` as `close`.

**It writes the CURRENT repo's drawer only** (conductor ruling, 2026-09-23, the
conservative default). Both IDs still resolve across every drawer, so an ambiguous ID is
refused exactly as `show` refuses it, and then both items must sit in the drawer of the
repo you are standing in. Two items in DIFFERENT drawers are REFUSED by name
(`<old> is in zeta and <new> is in omega -- DIFFERENT drawers`). Cross-drawer writes
arrive with the item-move build, W-20260923-A16 (`docs/OPEN_ITEMS_CROSS_PROJECT.md`), which
can do both sides under one design instead of two commits that are not atomic.

Also refused, with nothing changed: an old item that is already done or declined, a new
one that is declined, an item superseding itself, an unknown ID (a write never "misses"),
any item in a legacy drawer, and a pair in another project's drawer. `set` cannot write
either pointer field.

## Across projects: the write side (W-20260923-A28, 2026-09-23)

The design and its six cases are in [`OPEN_ITEMS_CROSS_PROJECT.md`](OPEN_ITEMS_CROSS_PROJECT.md)
(ruling D-20260923-A09); the twelve safety rules it cites as P1 to P12 are in
[`OPEN_ITEMS_CROSS_PROJECT_SAFETY.md`](OPEN_ITEMS_CROSS_PROJECT_SAFETY.md). This section is
what the tool now WRITES; the card side (Watching, Checks owed, Mandatory, the inbox line,
`seen`, `checks-run`) is described where it is built.

New header fields, all optional, all read from the HEADER only (a body line never counts, P1):

```
filed-by: alpha (session <name>) 2026-09-23        every add; "none" outside any repo
watch: beta                                        one line per watcher, at most 5
check: gamma [open] gamma runs its smoke test      at most 5; ticked in place to
check: gamma [done 2026-09-23 by <session> in gamma] gamma runs its smoke test
reach: machine | mandatory
check-script: no-bare-python                       reach: mandatory only
passed: beta 2026-09-23 by <session>               a manual pass, script-less items only
moved-from: alpha 2026-09-23 by <session> (group g -> g, head 1a2b3c4 -> 5d6e7f8): <why>
```

`<session>` is `CLAUDE_CODE_SESSION_NAME`, else `PJ_SESSION_NAME`, else `unknown`.
`items/.project` gains a second line, `repo: <absolute repo root>`: `init` writes it, a write
from inside that repo adds it when missing, and it is never overwritten (P10).

| Command | What it writes | Refuses when |
| --- | --- | --- |
| `add --for <project\|path/>` | the item in THAT project's drawer; a path (anything with a `/`) resolves to its repo | a second `--for`; an unknown or shared name (P9); no drawer (names `init`); a legacy drawer |
| `add --inbox` | the item in `~/.claude/pj-inbox/`, created on first use | it cannot create the inbox (says so by path) |
| `add --watch p`, `watch <ID> p` | a `watch:` line | a 6th; the owner itself; a duplicate; a `reach:` item |
| `add --check p "dw"`, `check <ID> p "dw"` | a `check: p [open] dw` line | same as watch |
| `tick <ID> p` | ticks p's check, recording who | you are not standing in p's repo (P2) |
| `close <ID>` | as before | any check is still `[open]`; the refusal says each is ticked from inside its project |
| `add --reach machine` | `reach: machine` | combined with any watch or check |
| `add --reach mandatory [--check-script n]` | `reach:` and `check-script:` | the owner is not the dotfiles project and no human confirms at a terminal (P8); the script name is not plain, not a regular file inside `home/.claude/tools/mandatory-checks/`, not committed on master or edited since, or has no committed `n.fixtures/pass/` and `fail/` (P4, P5) |
| `pass <ID> p` | `passed: p ...` | not reach: mandatory; the item has a check-script (only the script can pass it); not inside p |
| `move <ID> --to p --why ".."` | moves the file, keeps the ID, appends `moved-from:`, writes `items/moved-out/<ID>.md` in the old drawer, ONE commit for both | not run from the owner; groups differ or are unknown; p held the item before; p already has that ID anywhere; `--to inbox`. The first three pass only for a human at a terminal typing the ID |
| `route <ID> --to p` | the same, out of the inbox | always, unless a human at a terminal types the ID back |
| `init [--name n]` | `.project` with name and `repo:` | the name is `inbox` or `none`, or another drawer answers to it |

Groups come from `group: <name>` in each repo's COMMITTED `.claude/pj-homes`
(`git show HEAD:`); a group line only in the working tree refuses the move with "commit the
group line first" (P11). A group needs a valid `repo:` line on both drawers (P10).

"Gavin's call" is enforced, not just written: `route`, a cross-group move, a move back, and
`reach: mandatory` outside the dotfiles project read a typed answer from a TERMINAL on stdin.
An agent's Bash has no terminal, so it is refused. There is no environment override; one would
be the bypass. The selftest drives a real terminal with `expect`; inside the Claude sandbox,
which denies a pty, those arms print NOT MEASURED instead of passing.

A move takes both drawer locks in sorted real-path order (P12). If its commit fails, both
drawers get an empty marker dir `items/.pending-move/<ID>@<other drawer key>/`, and the next
write in EITHER drawer commits both halves together and clears it. The inbox is the only
committable place outside `projects/*/memory/WORK`, and `all_drawers` lists it explicitly.

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
(dry run into scratch, then real). Sections Q to T (2026-09-23) cover `show`, `get`,
`--json`, `--grep` and `supersede` on a fixture with the same ID in two drawers plus a
legacy drawer, including the cross-drawer and not-this-repo supersede refusals.
