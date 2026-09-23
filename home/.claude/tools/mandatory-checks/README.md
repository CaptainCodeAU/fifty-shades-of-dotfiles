# mandatory-checks: the scripts behind `reach: mandatory` items

A `reach: mandatory` open item may name a script here with `check-script: <name>`. The
script measures whether ONE repo complies with the rule. Ruled 2026-09-23 (D-20260923-A09,
safety rules P3 to P6 in `docs/OPEN_ITEMS_CROSS_PROJECT_SAFETY.md` of the dotfiles repo).

**No real rule ships yet.** The first one is Gavin's to choose. This file is the contract.

## Where a script runs, and who runs it

- ONLY `open-items checks-run` runs one. `pj` starts it detached at launch, in the repo it
  launches in. The start card and `open-items --session` never run a script; they read the
  cache the runner leaves (P3).
- The runner trusts a name only when (P4): it matches `^[a-z0-9][a-z0-9-]{0,63}$`; its real
  path is a regular file directly inside THIS directory of the dotfiles repo that the running
  `open-items` lives in (never `~/.claude/tools`, never a path from an item); and its content
  equals the blob committed on `master`. A draft in a working tree or a worktree branch never
  runs anywhere.
- Environment (P5.4): `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin LANG=C.UTF-8`,
  cwd = the repo root, stdin `/dev/null`, stdout to a file, stderr discarded, a 5 s timeout
  with a kill 1 s later. No token, no shell snapshot, BSD tools on macOS. Write for that.

## The exit contract (P5)

| Exit                                               | Meaning                | Shown as                |
| -------------------------------------------------- | ---------------------- | ----------------------- |
| 0 and a stdout line `scanned: N` with N > 0        | passed                 | line drops off the card |
| 0 with no `scanned:` line, or N = 0                | scanned nothing        | unknown                 |
| 1                                                  | not passed             | check failed            |
| anything else (2, 124 timeout, 126, 127, a signal) | the check itself broke | unknown                 |

`scanned: N` is the control: a scan that ran from the wrong folder, or whose `grep` exited 2
inside a `!`, scans nothing and must not read as a pass.

## Fixtures are required (P5.3)

Every script `<name>` ships two folders beside it:

```
<name>.fixtures/pass/   a tiny repo tree that complies: the script must exit 0 with N > 0
<name>.fixtures/fail/   a tiny repo tree that violates: the script must exit 1
```

`mandatory-checks-selftest` runs every script here against both, in the runner's own
environment, and fails if either arm does not come out as stated. `open-items add
--check-script` refuses a name with no fixtures.

## The cache (P6)

One record per (repo, item ID, item file sha256, script blob on master, repo HEAD), under
`~/.local/state/pj/mandatory-cache/`: `v1 <exit> <scanned N or -> <utc time>`. Only
`v1 0 <N > 0> <time>` is a pass. The key sees HEAD, not the working tree, so an uncommitted
violation is invisible until it is committed (a known limit, stated in the review).
