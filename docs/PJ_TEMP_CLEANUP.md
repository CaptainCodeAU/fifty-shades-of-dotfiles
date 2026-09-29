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

## What the builder must MEASURE before building (T1 rests on it)

T1 is unproven. Herdr skill rule 15 records that `$TMPDIR` is `/tmp/claude-501` sandboxed and
`/var/folders/.../T` unsandboxed in the SAME session, so Claude Code sets it for sandboxed
commands and may ignore what pj exports. Before any build:

1. Launch a scratch session with pj exporting a per-session `TMPDIR`. Read `$TMPDIR` in a
   sandboxed Bash call AND an unsandboxed one. Control arm: the same reading with no export,
   which must show `/tmp/claude-501`.
2. Check whether that folder is writable from the sandbox. The sandbox's write list names
   `$TMPDIR`, resolved when the session starts; measure, do not infer.
3. Look for a Claude Code setting that moves the temp root (a `CLAUDE_CODE_TMPDIR`-style
   variable was not verified to exist). Name the source if one is found.

If the override does not hold in both arms, STOP and bring it back to Gavin. The fallback he
saw is T1's second option (a hook diffing the shared folder), with its misattribution risk.

## Design notes for the builder (proposals, not rulings)

- Session identity. pj does not pass `--session-id` today, so it does not know the Claude
  session id before launch. Name the folder by a launch id pj mints, record the Claude process
  id beside it for the liveness check, and let the session learn its folder from `$TMPDIR`.
- Liveness. A folder is swept only when its recorded process is gone. A folder whose process
  cannot be read is left alone and reported, never swept: a count it cannot take is a refusal.
- Trash from `/tmp`. A sandboxed `rm` fails with `afpAccessDenied` and leaves the file
  (CLAUDE.md, Deletion safety). Every sweep runs outside the sandbox and checks `test -e` after.
- Hand-registered paths. A small command on PATH appends a path to the session's list; the
  sweep refuses any path the trash guard refuses (D-20260929-A29).
- Report shape. The sweep prints what it moved, what it refused and why, and the size, stated
  positively even when it moved nothing.
- Selftest with positive and negative arms, per the repo's `--selftest` convention.
