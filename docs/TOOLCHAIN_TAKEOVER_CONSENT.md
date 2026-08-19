# Toolchain takeover consent

Before `install.sh` hands Python over to uv (bare `python`/`python3` become a
hard `return 1`) and enforces pnpm (bare `npm`/`npx`/`yarn` do the same), it
finds out what's actually on the machine, says so plainly, and requires a
real, typed confirmation for each of those two changes independently. On a
clean machine -- the owner's own, so far -- this adds zero friction: nothing
is asked, nothing is written.

## Why it exists

Both changes are unconditional the moment `stow_home` symlinks `.zshrc` --
with no disclosure first. That's invisible on a machine that already wants
this. It's a real surprise on a machine that doesn't: `npm install` stops
working, with no warning it was coming. This exists because the plan is to
eventually share this dotfiles repo with less-technical friends, whose
machines will have real, different, working Python/Node setups that this
repo would otherwise silently override.

See `Plans/sorted-brewing-brooks.md` for the full design conversation.

## What it does

`_gate_toolchain_takeover` (in `install.sh`) runs:

1. `toolchain-stocktake --verdict python` and `--verdict node` (separately --
   the two gates are independent). Clean on both → returns immediately, no
   output, nothing written.
2. If either is foreign: prints what was found, then runs
   `project-impact-scan` against the machine's existing projects and points
   at the durable report.
3. For each foreign subject, asks with `confirm_typed()` -- the person must
   type `UV` (Python) or `PNPM` (Node) exactly. A bare Enter, wrong word, or
   non-interactive stdin all decline; there is no default answer.
4. **Accept:** nothing further happens -- the hijacks in `.zshrc` take effect
   normally once stowed.
5. **Decline:** writes `DOTFILES_ALLOW_SYSTEM_PYTHON=1` or
   `DOTFILES_ALLOW_NPM=1` into `~/.zshrc.private.early` (machine-local,
   untracked, sourced _before_ the hijacks are even defined). `.zshrc` reads
   these near the end of the hijack block and `unset -f`s exactly that group
   -- a real opt-out, not a heavier prompt in front of the same unconditional
   action.
6. Either way, records the decision in
   `~/.local/state/dotfiles/toolchain-consent.json`, keyed by a sha256
   fingerprint of the stocktake findings. A later run with an unchanged
   fingerprint sees the existing record and doesn't re-ask.

Wired into every path that stows `home/.zshrc`: `main()` (between
`check_conflicts` and `stow_home`), `--stow-only`, `update()`, and
`force_adopt()` -- each bypasses `main()`'s flow on its own, so each needed
its own call. `--check` shows the stocktake findings next to Deploy Parity,
informationally -- it never affects the missing-tool count, since a foreign
toolchain isn't a fixable deployment problem the way a missing symlink is.
`--dry-run` surveys and prints but writes nothing. `--skip-preflight` skips
the _re-survey_ only when a consent record already exists; with none, it
still gates and says so ("answering blind") -- that flag exists to bypass
pnpm cleanup, not consent.

## The two tools

Both are standalone, read-only, reusable outside of `install.sh` (run them
directly any time). See `docs/STRUCTURE.md` for the one-line summary of each.

- **`toolchain-stocktake`** -- what Python/Node toolchain is already here
  (pyenv/conda/asdf/mise, pipx tools, npm globals, non-default registry).
  Exit 0 clean, 1 foreign, 2 could-not-determine (callers must treat as 1).
- **`project-impact-scan`** -- which of the machine's actual PROJECTS still
  depend on npm or a non-uv venv, with a one-line migration hint per
  project. Detects and reports only; migrating a project is real per-project
  judgment work for a later Claude Code session, one at a time. Report:
  `~/.local/state/dotfiles/project-impact-report.md` (durable, rotates the
  previous copy) -- hand that one path to a person or an agent.

Both were built by deliberately copying (not sharing) discovery logic
already in `home/.local/bin/pnpm-audit-tree`
(`os_default_root`/`discover_projects`/`nearest_lockfile`/`resolve_root`).
`pnpm-audit-tree` is wired into every `git push` on the machine via
`core.hooksPath`; refactoring its internals to share ~50 lines with two
brand-new tools was judged more risk than it was worth. **Extraction
trigger, if this comes up again:** a third caller wanting the same
discovery shape, or the first discovery bug that has to be fixed twice in
both places.

## Opt-out variables

| Variable                       | Effect                                                        |
| ------------------------------ | ------------------------------------------------------------- |
| `DOTFILES_ALLOW_NPM`           | Disables the `npm`/`npx`/`yarn` block                         |
| `DOTFILES_ALLOW_SYSTEM_PYTHON` | Disables the `python`/`python3`/`pip`/`pipx`/`pyNNN` takeover |

Written automatically by the gate on decline. Set by hand only in
`~/.zshrc.private.early` (never `~/.zshrc.private` -- that file is sourced
at the very end of `.zshrc`, after the hijacks already decided; see that
file's own guard-variable list). `pnpm()`'s `link --global` guard is a
correctness fix, not a takeover, and is never affected by either variable.

## Safety

Both tools are read-only: no network, no mutation, no subprocess into
npm/pnpm/git beyond version/listing queries. The gate itself only ever
writes to `~/.zshrc.private.early` and
`~/.local/state/dotfiles/toolchain-consent.json` -- never to a scanned
project, never to the repo.
