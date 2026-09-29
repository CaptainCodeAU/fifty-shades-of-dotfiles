# pj temp cleanup: every session empties its own temp bin into the Trash

Item: W-20260929-A155. Ruled by Gavin on 2026-09-29 in two boxes in dotfiles-main: the scope
(7:18 PM, "yes, with the start-card sweep") and the four scoping answers below (same evening).
Sibling of `docs/PJ_WRAP_UP.md`, which owns the wrap-up routine this plugs into.

## Why

On 2026-09-29 the disk filled. Three temp leftovers, all made by test tools rather than typed by
an agent: engage's install test (about 4.7 GB across runs, A153), cc-warehouse's pytest (about
2 GB per kept run, A152), and mlbox-relay's selftest (240 MB, A154). Each owner fixes its own
tool. This document is the pj side: a session cleans up after itself even when a tool does not.

Measured the same evening: sandboxed `$TMPDIR` is `/tmp/claude-501`, one folder shared by every
session on the machine, holding 426 entries and 1.2 GB with no owner recorded. That backlog is
W-20260929-A206 and is not this design's job.

## Scope (Gavin, 7:18 PM)

- Each session keeps a list of the temp paths it creates.
- `/pj:wrap-up` has each worker it launched sweep and confirm its own list, then sweeps its own.
  Agent-tool helpers share their parent's list.
- A session that ended without wrap-up is swept at the next start (see T2 for where).
- Removal is Trash-only: bare `rm`, then `test -e` on every path. No permanent-delete carve-out;
  Gavin empties the Trash himself, so disk space comes back only when he does.
- Worker briefs send their reports to the project's records home, and herdr skill rule 15 is
  updated to match.
- Built by a builder with tests. Proven by one wrap-up that leaves no listed path behind.

## The four scoping rulings (all recommendations taken)

| #   | Question                                        | Ruling                                                                                                                                                              | Rejected                                                                                                                            |
| --- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| T1  | How a session records its temp paths            | A per-session temp folder: pj points `TMPDIR` at a folder named for the session, so every tool writes there. Paths outside it are registered by hand.               | a hook diffing the shared folder (misattributes with 12 live sessions); agent registration only (misses every tool-made file)       |
| T2  | Who sweeps a session that ended without wrap-up | The `pj` launcher, before the new session starts. It runs outside the sandbox, so it can check the old session is dead. The start card only reports what was swept. | a separate start hook (sandboxed, cannot check liveness); card lists, wrap-up sweeps (leftovers wait, which is how the disk filled) |
| T3  | Does the sweep include the scratchpad           | Yes, after wrap-up step 6 has moved every record out of it                                                                                                          | recorded list only                                                                                                                  |
| T4  | Anything else to rethink                        | No                                                                                                                                                                  |                                                                                                                                     |

T2 exists because the start card's contract (`home/.local/bin/pj-start-card`, lines 14-17) says
it writes nothing, makes no network call and finishes well under a second. A sweep breaks the
first promise, and a liveness check needs `ps`, which the sandbox blocks. The card keeps its
contract; it prints one line when the launcher swept something.


## T1 amended (Gavin, 2026-09-30, in his own box)

T1 as first ruled does not hold, measured below: nothing pj can export moves `$TMPDIR` for a
SANDBOXED Bash call. Gavin then chose, in two boxes relayed by dotfiles-main on 2026-09-30:

1. Option 1, a hook that points `$TMPDIR` at a per-session folder inside the sandbox's own temp
   tree, `/tmp/claude-<uid>/pj-<session id>`. (The first box timed out and applied the
   recommended default; Gavin then confirmed it in his own words.)
2. The hook is a **SessionStart hook writing `export TMPDIR=...` into `CLAUDE_ENV_FILE`**, not a
   PreToolUse rewrite. Reason: `docs/CLAUDE_HOOKS.md` Rule 2. A rewrite of EVERY Bash call
   collides with the uv, pnpm and no-cd rewrite hooks, and two rewrites of one call are
   non-deterministic (the last to finish wins), so either the TMPDIR or the slip fix would be
   lost at random. The env file needs no rewrite at all, so it composes by construction.

Everything else in T1 stands: paths outside the folder are registered by hand (`pj-temp add`).

## What was measured (2026-09-30, Claude Code 2.1.284)

Every row is VERIFIED from a transcript's tool_result blocks or a direct run. Headless scratch
sessions, `env -i` so the measuring session's own `CLAUDE_*` variables could not leak in, one
sandboxed and one unsandboxed Bash call each (both confirmed in the tool_use input). Raw
evidence: the builder's report folder (`phase1.md`, `REPORT.md`, the `arm*`/`env-*` transcripts).

| Arm | What pj or the hook set                   | sandboxed `$TMPDIR`  | unsandboxed `$TMPDIR` | sandbox can write it |
| --- | ----------------------------------------- | -------------------- | --------------------- | -------------------- |
| C   | nothing (control)                         | `/tmp/claude-501`    | `/var/folders/.../T/` | n/a                  |
| A   | pj exports `TMPDIR=<folder in /private/tmp>` | `/tmp/claude-501` | `<folder>`            | no                   |
| B   | pj exports `CLAUDE_CODE_TMPDIR=<folder>`  | `/tmp/claude-501`    | `/var/folders/.../T/` | no                   |
| D   | pj exports `CLAUDE_TMPDIR=<folder>`       | `/tmp/claude-501`    | `/var/folders/.../T/` | no                   |
| E1  | SessionStart hook -> `CLAUDE_ENV_FILE`    | `/tmp/claude-501/<x>` | `/tmp/claude-501/<x>` | yes                  |
| L1  | the real `pj-temp session-start`          | `/tmp/claude-501/pj-<sid>` | same             | yes                  |

- **Why A to D fail.** Changelog 2.1.163: the sandbox pins `$TMPDIR` to `/tmp/claude-{uid}` on
  purpose, for sandboxed commands only. `CLAUDE_CODE_TMPDIR` moves Claude Code's OWN files
  (scratchpad, `cc-socks` messaging socket), not the tools'. Arm A also pulled every hook's
  6-hour cache (`*-check.verdict`, zed caches, `pj-relaunch.*`) into the per-session folder.
- **E2, `--resume`:** same session id, same folder, a NEW pid.
- **E3, `/clear`:** a NEW session id, the hook ran with it, and Bash KEPT THE OLD folder (headless
  stream-json). So liveness cannot key on the session id alone; see the record below.
- **L1, hook caches:** a fixture SessionStart hook writing `pjtc-fixture-check.verdict` into its
  own `$TMPDIR` landed in `/var/folders/.../T`, the hook's plain temp folder. Hooks run
  unsandboxed with Claude Code's own environment; the env file reaches only Bash tool calls.
- **Bare `mktemp -d` ignores `$TMPDIR` on macOS, in every arm.** It uses the Darwin user temp
  folder first (man page: `_CS_DARWIN_USER_TEMP_DIR`, `TMPDIR` only as a fallback). Sandboxed it
  then FAILS (`Operation not permitted`); unsandboxed it lands in `/var/folders/.../T`, outside
  any pj folder. `mktemp -d "$TMPDIR/name.XXXXXX"` follows the folder. Documented, not fixed here;
  the hook's context line tells the session.
- Node `os.tmpdir()` and Python `tempfile` followed `$TMPDIR` in every arm.

## As built (branch temp-cleanup)

```
pj launch ──> check_session_caps ──> pj-temp sweep-dead --claude-args "$@"  (unsandboxed)
                                        │  judges every /tmp/claude-<uid>/pj-* folder
                                        │  one line -> PJ_TEMP_SWEPT, details -> <state>/temp-sweep.log
                                        v
claude starts ──> SessionStart: pj-temp session-start
                    ├─ folder: the one this pid already owns (/clear), else pj-<sid> (new or --resume)
                    ├─ appends <sid> <pid> <lstart> <source> to <folder>/.pj-temp/owners
                    └─ appends `export TMPDIR=<folder>` to CLAUDE_ENV_FILE
                  SessionStart: pj-start-card prints PJ_TEMP_SWEPT (startup, resume)
work ──> Bash (sandboxed or not): TMPDIR=<folder>; `pj-temp add <path>` for anything outside it
/pj:wrap-up step 6 ──> workers `pj-temp sweep`, then own, then `--scratchpad` after records move
```

| Piece | What it does |
| ----- | ------------ |
| `home/.local/bin/pj-temp` | `session-start` (the hook), `add`, `list`, `sweep [--scratchpad DIR] [--dry-run]`, `sweep-dead [--dry-run] [--oneline] [--log F] [--claude-args ...]`, `--selftest [--mutants] [--e2e]` |
| `settings/claude/hooks.json` | registers `pj-temp session-start`, SessionStart, `targets: ["project"]` (pj only), class alarm |
| `home/.local/bin/pj` | `temp_sweep_at_launch`: once per invocation, after the cap check, never in the relaunch loop; `--temp-sweep` runs it alone; `PJ_NO_TEMP_SWEEP` skips it |
| `home/.local/bin/pj-worker` | `count --json` machine rows carry `sid` and `start` (the registry's procStart) |
| `home/.local/bin/pj-start-card` | one `Temp sweep ...` line from `PJ_TEMP_SWEPT`; still writes nothing |
| wrap-up `SKILL.md` step 6, herdr `SKILL.md` rule 15 | the wrap-up order; reports go to the records home |

**Liveness.** A folder is LIVE when any owner pid is a live registry entry with the SAME start
time (so a reused pid cannot pass), or any owner session id is held by a live registry entry, or
this launch resumes it (`--resume <id>`, `-r <id>`, `--resume=<id>`). The registry is read through
`pj-worker count --json`. **Nothing is swept** when the registry and ps disagree, when a parked
session (`claude --bg-pty-host`) cannot be placed, when pj-worker fails or is too old to carry
`sid`/`start`, or when this launch is a `--continue` or a bare `--resume` (target unknown). A
folder whose record is missing, unreadable, a symlink or not yours is LEFT and reported.

**Deletion.** Trash only. `trash-guard --check` judges every path, then the rm PATH shim, which
pj-temp resolves and checks for the shim's marker before anything moves (a PATH where `rm` is
`/bin/rm` refuses the whole sweep). `test -e` after every path: a path still there is FAILED by
name (`afpAccessDenied` = the sandbox was on), exit 1. The folder root and non-`pj-*` entries in
it are never targets. Registered paths are refused, at add and at sweep, when blank, relative,
holding a newline, a symlink, `/`, a temp root or an ancestor of one, outside `/private/tmp` and
`/private/var/folders` (so everything under `$HOME`), a repo root, inside another session's
folder, or inside this session's own folder (already swept with it).

## Evidence (2026-09-30)

| Check | This branch | master |
| ----- | ----------- | ------ |
| `pj-temp --selftest` | 59 passed, 0 failed | no pj-temp |
| `pj-temp --selftest --mutants` (one-fault: liveness x6, path refusal x5, `test -e`) | 12 caught, 0 missed | |
| `pj-temp --selftest --e2e`, sandboxed / unsandboxed | FAILED + afpAccessDenied, rc 1 / MOVED, gone | |
| `pj-worker-selftest` (arm C1g) | 138/0 | 137/1, C1g fails |
| `pj --selftest` (arms 29a-f) | 155/0 | a paired real launch: master hands claude no `PJ_TEMP_SWEPT` |
| `pj-start-card-selftest` (arms TS) | 223/0 | 219/4, the 4 positive TS arms fail |
| `claude-hooks-sync-selftest` | 74/3 | 74/3 (the same 3 sandbox-Trash prune arms) |
| real registry + real Trash, fixture root | live session and a `/clear` shape kept; an exited session and a reused pid swept | |
| launch cost, 3 runs | 0.23 to 0.40 s | |

## Limits, measured or stated

- Bare `mktemp -d`, and anything else that ignores `$TMPDIR`, still writes to the shared folders.
- Only Bash tool calls get the folder. Hooks, MCP servers and Claude Code itself keep their own.
- A worker that exits before wrap-up is swept by the next pj launch on this machine, not by
  wrap-up. A folder is swept only when a `pj` launch runs; a machine where nobody launches pj
  keeps them.
- Linux: the registry's procStart is a tick count there, so the pid + start test never matches
  and only the session-id test keeps a folder live. Not measured; macOS only.
- `/clear` stayed on the old folder in a HEADLESS session (E3); an interactive `/clear` was not
  measured. Both cases are handled: the hook reuses the folder its pid already owns.
- The start card's `--json` does not carry the sweep line yet.
- The existing backlog in `/tmp/claude-501` (W-20260929-A206) is untouched: only `pj-*` folders
  are ever judged.
