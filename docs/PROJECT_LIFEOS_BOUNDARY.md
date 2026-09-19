# Project / LifeOS boundary for this repo

**Status:** DECIDED 2026-09-19, NOT EXECUTED. Four rulings (D-20260919-02 to -05 in the
decisions register). No file has been moved, deleted or symlinked as a result of this
document yet. The sequencing section says what execution would involve and in what order.

**Written to stand alone.** Assume no memory of the session that produced it.

## The question Gavin asked

LifeOS (the `c` launcher) was used for a few days on project work and project material
ended up copied and pointed into LifeOS's private store. The `pj` launcher was then created
as a project-level lane. Which things now inside LifeOS belong to this repo instead, and
where should they live?

## What was measured, 2026-09-19

Two sessions measured one half each, read-only, every count with a control. The overseer
session took their reports as given.

**A `pj` session** (`--setting-sources project,local`, appends `OPERATIONAL_RULES.md`):

- User-level hooks: 0 of 14 fired. Project hooks: 7 of 7 fired (the control).
- `autoMemoryEnabled` is set only in the user settings file, which `pj` excludes. So the
  harness default applies and auto-memory is ON. The harness injects this repo's memory
  index at startup and instructs the session to write to
  `~/.claude/projects/<encoded-repo-path>/memory/`.
- Everything that reaches `pj` from LifeOS: the appended rules file (about 8 KB, 90 lines),
  two `LIFEOS_*` env vars, and two plugin dirs under `~/.claude/skills`. No LifeOS hook runs.
- Inside this repo, only `.claude/commands/refresh.md` computes the harness memory path.
- `open-items` reads `${OPEN_ITEMS_DIR:-$HOME/.claude/MEMORY/WORK}` and REFUSES with exit 2
  if that path is missing. A move breaks it loudly, not silently.

**A `c` session** (appends `LIFEOS_SYSTEM_PROMPT.md` only):

- `autoMemoryEnabled: false`, so the harness memory dir for this repo is never loaded.
- Static load per session about 55 KB: the system prompt, LifeOS `CLAUDE.md`, and six
  imports. Five of those imports are prefixed with `#` to disable them and STILL LOAD.
- `LoadContext.hook.ts` scans `lifeos-private/MEMORY/WORK` and `~/.claude/MEMORY/WORK` for
  directories named `YYYYMMDD-HHMMSS_slug`. No such directory exists in either tree, so
  the active-work block injects nothing today. This is a coincidence of names, not a
  filter (caveat raised by the measuring session and accepted).
- `SCOPES/scopes.json` in lifeos-private has one writer (`ScopesGenerate.ts`) and no reader.
- Cortex (LifeOS's memory system) is inert: hot-layer files are empty templates, no
  reviewer, writer or proposal evidence exists, and the health log has warned on every
  turn since 2026-09-07. The proposal scope gate has therefore never run on a real proposal.
- Dotfiles work does not reach a `c` session opened in another project by any measured path.
  The `open-items --session` hook is scoped to the current repo.

**Where dotfiles material sits inside LifeOS today:**

| Location                                    | What                                                                     | Versioned |
| ------------------------------------------- | ------------------------------------------------------------------------ | --------- |
| `lifeos-private/SCOPES/dotfiles/notes/`     | 11 files, a 2026-09-18 copy of the drawer                                | yes       |
| `lifeos-private/MEMORY/WORK/`               | ci-watch-observability, github-credential-lanes, memory-store-separation | yes       |
| `lifeos-private/MEMORY/LEARNING/INCIDENTS/` | 3 incidents drawn from dotfiles work                                     | yes       |
| `lifeos-private/MEMORY/UPGRADES/records/`   | 13 records mentioning this repo                                          | yes       |
| `~/.claude/MEMORY/WORK/`                    | 18 files, the live drawer `open-items` reads                             | NO        |
| `OPERATIONAL_RULES.md`                      | one line citing a dotfiles doc                                           | yes       |

## The finding that reframes it

**The separation already exists at the launcher level.** `pj` reads and writes this repo's
harness memory natively; `c` never loads it. No LifeOS hook runs under `pj`. So `pj` is the
project lane and `c` is the global lane by construction. The mess is three hand-made copies
and pointers, not the loaders. The earlier five-step separation plan (recorded in
`lifeos-private/MEMORY/WORK/memory-store-separation/FINDINGS.md`, steps a to e) was built on
a loader leak that does not occur today and a registry nothing reads. Step a was executed
and produced `scopes.json`; steps b to e are retired by D1 below.

## The decisions

### D1. Memory home is the harness dir in `dot-claude` (D-20260919-02)

`~/.claude/projects/<encoded-repo-path>/memory/` is the single source for this project's
notes. Not `lifeos-private/SCOPES/dotfiles/notes/`.

- **Why.** `pj` already reads and writes it natively. It is versioned in `dot-claude`. `c`
  never loads it, so there is nothing to un-pollute. Moving it into lifeos-private would put
  project notes inside LifeOS's own store, exactly the coupling being removed, and would
  need the unbuilt resolver to be safe.
- **Trade-offs accepted.** `dot-claude` holds every project's memory in one clone, so
  cross-project isolation remains a convention. A repo rename silently orphans the dir and
  needs a manual move. Both were already true.
- **Ties.** Fixes D2's destination. Makes the SCOPES copy redundant (D3). Retires steps c, d
  and e of the earlier plan.

### D2. The drawer moves under the harness memory dir (D-20260919-03)

The dotfiles-owned folders in `~/.claude/MEMORY/WORK/` move to a `WORK/` folder inside this
repo's harness memory dir. The one LifeOS-owned file there
(`per-project-work-scoping/DECISION.md`) moves to lifeos-private. `open-items` is taught to
resolve the drawer per repo BEFORE anything moves.

- **Why.** The drawer is the only unbacked project material on the machine. LifeOS's own
  `KnowledgeHarvester.ts` already walks `projects/<key>/memory/WORK`, so the destination is a
  path LifeOS recognises rather than a new convention.
- **Trade-offs.** `open-items --all` needs a way to enumerate repos instead of one flat
  directory. The public `CLAUDE.md` must keep saying "run open-items" with no path, so no
  private layout is committed to a public repo.
- **Ties.** Depends on D1. `open-items` change must land first or the `c`-side SessionStart
  hook breaks on every session (it fails loudly, which is the safe direction).

### D3. Residue in lifeos-private: delete the copies, keep the learning (D-20260919-04)

After D2 lands and a hash comparison shows nothing unique remains: delete
`SCOPES/dotfiles/` and the dotfiles folders under `MEMORY/WORK/`. Keep the incidents, the
upgrade records and the single citation in `OPERATIONAL_RULES.md`.

- **Why.** The copies are backups whose original will be versioned. Incidents and upgrade
  records are LifeOS's own lessons that happen to cite this repo; deleting evidence to tidy a
  boundary is the wrong trade. The rules citation is a pointer, not project doctrine.
- **Trade-offs.** Some duplication of history remains in git. Nothing loads it, so the cost
  is clarity only.
- **Ties.** Gated on D2 completing and on a hash check, never on a date.

### D4. `pj` keeps appending the whole `OPERATIONAL_RULES.md` (D-20260919-05)

No split into a project rules file.

- **Why.** Measured, the file is global doctrine (deletion, verification, reporting,
  security) with one citation of this repo. A split creates two copies of doctrine that
  drift, which is the failure the decisions register exists to prevent.
- **Trade-offs.** `pj` depends on lifeos-private existing at that path. The file carries
  LifeOS-only sections (vendors, model rungs) that cost tokens in `pj` and change nothing.
- **Ties.** Independent of D1 to D3. Reversible later without touching them.

## Sequencing, if and when execution is approved

1. `open-items`: resolve the drawer per repo, keep the loud refusal, add a cross-repo
   enumeration for `--all`. Self-test both arms.
2. Move the dotfiles folders into the harness memory dir under `WORK/`; commit in
   `dot-claude`; verify from a fresh clone.
3. Move `per-project-work-scoping/DECISION.md` to lifeos-private; commit and push there.
4. Repoint the seven known pointers (this repo's `CLAUDE.md`, four docs, `refresh.md`,
   `OPERATIONAL_RULES.md`). Public files carry no path.
5. Hash-compare, then delete the lifeos-private copies (D3). Trash-routed, confirmed first.
6. Delete `~/.claude/MEMORY/WORK` last, after `open-items` no longer reads it.

Each step is its own gate. None has been started.

## Follow-ups that belong to LifeOS, not this repo

- The five `#`-prefixed imports in the LifeOS `CLAUDE.md` still load. Fix the disabling
  mechanism or delete the lines.
- `LoadContext.hook.ts` has no cwd filter. It injects nothing today only because no
  timestamped WORK directory exists. Add a guard or a test before anyone creates one.
- Cortex is inert. Decide whether to repair it or accept `c` as an identity-and-doctrine
  lane. Until then the proposal scope gate protects nothing.
- `SCOPES/scopes.json` has no reader. Retire it or give it one; do not leave a registry
  that looks authoritative and is consulted by nothing.

## Provenance

Overseer session: https://claude.ai/code/session_01Mq3HL9uEAFwbw9Fj62wTh1.
Measurements by two peer sessions on 2026-09-19, one launched with `pj`, one with `c`, both
read-only. Prior research: `lifeos-private/MEMORY/WORK/memory-store-separation/FINDINGS.md`
and `lifeos-private/SCOPES/README.md`.
