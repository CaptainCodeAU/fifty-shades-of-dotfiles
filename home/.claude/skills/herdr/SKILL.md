---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, tabs, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires HERDR_ENV=1."
---

# Herdr

Herdr organizes terminals into workspaces, tabs, and panes, recognizes coding agents running inside panes, and exposes the current session through the `herdr` CLI.

This file has a size budget, watched by `pj-health`'s `skill-budget` row, because it grows every time something here is measured and nothing else was counting. Every line in it carries three things: a rule, one number, and a date. A claim with no number cannot be re-verified and a number with no date cannot be re-measured, and a line missing either is the first thing to cut when the row turns yellow. Never cut a measurement to get under the budget; cut narrative and corrections of earlier versions, and if neither is left, raise the budget with a fresh count.

## Read this first

Rules first. Each points to the section holding its measurement.

1. Every `herdr` call needs `dangerouslyDisableSandbox: true`, background tasks included (sandbox paragraph below).
2. Read panes with `herdr-pane-read`, never a hand-picked `--lines`. On 0.8.2 a small `--lines` returned ZERO BYTES from a full pane; 0.9.1 fixed that, and the tool now earns its place by stating its denominator (Run an ordinary command: the floor).
3. One wait per Bash call, long waits in a background task, never a `while`/`sleep` loop around `agent wait` or `pane wait-output` (Wait for completion).
4. A `wait-output` sentinel must be a split string assembled at runtime; a literal you typed matches its own echo (Wait for completion).
5. Never close anything on `idle` alone; read the pane first. `idle` is reported early on a nested TUI (Start and coordinate; Safety).
6. Never `workspace rename`; it is a permanent, unclearable override (Workspace labels).
7. `agent prompt` could type the text and NOT submit it on 0.8.2. 21 of 21 landed on 0.9.1, but read the pane before retrying anyway; the fix is `pane send-keys <pane-id> enter` (Start and coordinate).
8. A timeout or a stall does not prove the prompt was not delivered; read before resending or the agent gets it twice (Start and coordinate).
9. `--no-focus` for background work (Safety).
10. Only `pane layout`, `pane current`, `pane split` accept `--pane`/`--current`; every other `pane` subcommand takes a bare positional id (Use IDs).
11. A registry entry is not a ready agent: a Claude session's entry appears before its name is applied (Name what you create).
12. Close only what you opened, and clear the labels you set; a pane label outlives its process (Name what you create).
13. `herdr agent start --kind claude` starts plain `claude`, NOT a pj session: no pj system prompt (OPERATIONAL_RULES, pj-global RULES), no project hooks, no Mods flag. 4 of 4 workers' command lines showed only `--permission-mode`, 2026-09-24 (W-20260924-A59). Until that is fixed, put every rule a worker needs into its brief.
14. One stall watch per worker, never several paths in one `--once` watch: it exits on the FIRST path's STALL and leaves the rest unwatched (twice on 2026-09-24). TaskStop each watch the moment its worker reports: of 101 watches in 30 sessions, 43 ended in STALL and about 17 of those fired after the worker was already done (W-20260924-A42).
15. Hand files between conductor and workers by absolute path (the scratchpad), never `$TMPDIR`: it is `/tmp/claude-501` sandboxed and `/var/folders/.../T` unsandboxed in the same session; one control arm was voided that way, 2026-09-24.
16. A side-by-side test session (a live mod, a UI check) goes in a separate herdr TAB, never a pane (Gavin, 2026-09-23); one Mods probe tab opened and closed cleanly that way, 2026-09-24.
17. Every worker brief carries a required edge-cases section and the VERIFIED / AGENT-REPORTED / ASSUMED labels (Gavin, 2026-09-24: "preferably all of them are"); re-check a worker's load-bearing claim yourself before relaying it. 4 of 4 checked claims held on 2026-09-24, and one conductor count (10 of 41 arms) was the conductor's own instrument error.

Before any control command, verify this agent is inside a Herdr-managed pane:

```bash
test "${HERDR_ENV:-}" = 1
```

If the check fails, do not inspect or control the user's focused Herdr session from outside Herdr: say that you are not running inside Herdr and stop, for that kind of work.

The check gates the USER'S session, not the binary. Driving the CLI on another host over SSH for setup or diagnosis is legitimate (2026-09-06: proved a banner fix on a Linux box by creating one workspace, waiting on its pane, reading it, closing it). In that mode: prefer `status`, `list` and `read`; touch only workspaces, tabs and panes you created in the same command; close them when done; never `server stop`; `--no-focus` everything, because the user may be attached. `herdr` is not on PATH in a non-interactive ssh shell (only the interactive profile adds `~/.local/bin`), so call `~/.local/bin/herdr` or export PATH first. Never stop or restart the server from INSIDE one of its own panes: the stop kills the pane before the next command runs, and that pane's workspace is saved into the session for the restart to restore (2026-09-06: had to start the unit by hand and close the orphan).

When the check passes, the `herdr` binary in `PATH` talks to the current session: inspect neighboring work, create layout, start agents and commands, read output, wait for state changes.

Claude Code's sandbox blocks every `herdr` subcommand that touches the socket (`~/.config/herdr/herdr.sock`), even with that path granted `allowWrite` in `settings.local.json`; the failure is `Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }`. Re-verified 2026-08-19 with the grant in place, and reconfirmed from inside a background task: a plain `herdr agent list` without the flag fails the same way. Run every `herdr` command with `dangerouslyDisableSandbox: true`; do not spend a retry re-checking the grant.

## Learn the current CLI

The installed binary is the authority for syntax. Start with:

```bash
herdr --help
```

Then print a command group by running it without a subcommand:

```bash
herdr agent
herdr pane
herdr workspace
herdr tab
herdr worktree
herdr terminal
herdr notification
herdr integration
herdr session
herdr machine
```

Do not run bare `herdr` for discovery; it launches or attaches the TUI. Do not probe a mutating nested command by omitting arguments: `herdr workspace create` is valid with defaults and will execute.

Most control commands return JSON; read identifiers and state from the responses instead of predicting them. `pane read` and `agent read` print the pane text itself, not JSON: piping them into `jq` fails with "Invalid numeric literal" (2026-09-06). `workspace create`, `tab create`, `pane split`, `*list`, `status`, and the `close` commands are JSON.

## Understand layout, panes, and agents

- Workspace, tab, and pane topology organize terminal locations.
- Pane commands control raw terminals, shells, tests, servers, input, and output.
- Agent commands control the recognized coding agent currently occupying a pane.

A pane exists whether or not it contains an agent. `agent start` requires an existing available shell pane and never creates, splits, or moves layout. Use pane commands for ordinary processes; use agent commands when Herdr must validate agent identity or interpret `idle`, `working`, `blocked`, `done`, and `unknown` lifecycle states.

Agent commands accept a unique live agent name or the pane ID hosting that agent, not terminal IDs or bare agent-kind labels. Names match `[a-z][a-z0-9_-]{0,31}` and are unique among live agents. A name follows the current pane occupant and is cleared when that agent exits, is released, or is replaced.

`idle` and `done` both mean ready for input. The CLI and API use the server's seen state to distinguish them: explicit focus commands mark the target seen, reads do not. Each TUI client tracks viewed completions independently, so its Done badge can differ from the CLI or another client's. (Upstream rephrased this paragraph for 0.9.x; before that it was phrased as one tab being seen in one focused UI. The clause is kept so the old reading is not silently lost.) `blocked` means Herdr recognized an approval or question UI. `unknown` means an agent is present but not confidently classified; it does not prove completion.

## Use IDs and caller context

Public IDs are opaque stable handles:

- workspace: `w1`
- tab: `w1:t1`
- pane: `w1:p1`

Closed tab and pane IDs are not reused. A pane moved into another workspace gets a new workspace-qualified pane ID. After `pane move`, continue with `.result.move_result.pane.pane_id` or the live agent name. The old value is `.result.move_result.previous_pane_id`; only the moved process's inherited caller context keeps resolving it, so do not use it as a general agent target.

Herdr injects the caller's context into each managed pane:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

Only three `pane` subcommands accept a target FLAG. For those, prefer `--current` when the target is the calling pane, because an omitted target may use the UI-focused pane, which can belong to the user or another client. Every other `pane` subcommand takes the pane id as a BARE POSITIONAL argument and rejects both flags with `unknown option` and exit 2, printing one short line with no usage block, so it reads like a Herdr fault. Measured 2026-09-20 on herdr 0.8.2 from each subcommand's `--help`; re-measured 2026-09-22 on 0.9.1, all nine unchanged:

| subcommand                                                                               | how to name the target                                              |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `pane layout`, `pane current`, `pane split`                                              | `--current` or `--pane <id>` (`split` also accepts a positional id) |
| `pane read`, `pane run`, `pane send-keys`, `pane wait-output`, `pane close`, `pane move` | positional `<PANE_ID>` only                                         |

So the calling pane is `herdr pane read "$HERDR_PANE_ID"`, NOT `herdr pane read --current`.

From 0.9.1 an omitted `pane split` target means the CALLING pane when `HERDR_PANE_ID` is available, else the focused pane (upstream #4123). On 0.8.2 and earlier it meant the UI-focused pane. OBSERVED 2026-09-22 on a live 0.9.1 server, both arms in one breath from the same NON-focused pane: with `HERDR_PANE_ID` set the new pane landed directly below the CALLING pane in the calling pane's tab; the same command under `env -u HERDR_PANE_ID` landed in the FOCUSED pane's tab instead. The variable is the mechanism, not the tab. Every other `pane` subcommand still follows the old rule, so keep naming the target explicitly.

Discover live state with:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Creation responses expose the IDs to use next. `workspace create` returns `.result.workspace`, `.result.tab`, and `.result.root_pane`; the id fields are `.result.workspace.workspace_id` (`wF`), `.result.tab.tab_id` (`wF:t1`) and `.result.root_pane.pane_id` (`wF:p1`), verified 2026-09-06. `tab create` returns `.result.tab` and `.result.root_pane`. `pane split` returns the new pane as `.result.pane`.

## Control a saved SSH machine (0.9.1 and later)

Nothing on this estate has a saved machine yet, so none of this is measured here; it is upstream's text, kept close to upstream's wording so the merge base stays comparable.

IDs and live agent names are scoped to one server: two saved SSH machines can both have `w1:p1` or an agent named `reviewer`. Selecting a machine in the TUI does not retarget commands running in your pane; without `--machine` they use the inherited session and socket context.

Use the same global prefix for discovery and every later command:

```bash
herdr --machine <label-or-id> agent list
herdr --machine <label-or-id> pane list
herdr --machine <label-or-id> agent prompt <remote-agent-name> "Reply with your current status." --wait --timeout 120000
```

The selector is an enabled saved profile ID or a unique, case-sensitive label, not an arbitrary SSH hostname. Commands use that profile's remote session without an open TUI. Do not combine `--machine` with `--session` or `--remote`. Discover IDs on that machine; inherited local IDs and `--current` do not identify remote panes.

Both installations must support machine API forwarding, and the remote server must already be running and API-compatible. Forwarding never installs, starts, or restarts a server and never falls back to Local. Local configuration, session management, installation commands, and interactive attachment are not forwarded. Remote worktree paths must be absolute, `~`, or start with `~/`; plugin link paths must be absolute. A connection failure does not prove a mutation was not applied: inspect remote state before retrying.

`herdr machine list` lists saved connection profiles, not a cross-machine pane inventory; add `--json` for scripts. Only add, remove, enable, or disable profiles when the user asks. Removing a profile disconnects the client but does not stop remote sessions. Adding a machine uses the remote default session unless `--remote-session` is supplied. Setup asks before stopping an incompatible server and defaults to No; do not approve replacement without the user's consent. Experimental handoff is not part of `machine add`.

## Create a worktree

Every git worktree on this estate lives inside its project at `<repo>/.worktree/<branch>`. Never herdr's shared default (`~/.herdr/worktrees`), and never the sidebar "New worktree" button, which always uses that shared default.

Use the `hwt` wrapper, not `herdr worktree create` directly:

```bash
hwt <branch-name>
```

Run it from inside the target repo (any subdirectory). It resolves the repo root, then calls `herdr worktree create --branch <branch-name> --cwd <repo-root> --path <repo-root>/.worktree/<branch-name>`. Extra flags (`--base REF`, `--label TEXT`, `--focus`, `--no-focus`) pass straight through.

Never call `herdr worktree create` without `--path`: it defaults to the shared folder, and `--path` requires an absolute path (a relative one is rejected). `worktree list`, `worktree open`, and `worktree remove` are unaffected; use them directly.

`worktree remove --workspace ID` deletes the git worktree, removes its checkout directory, and closes the associated workspace/pane/session in one call; no separate close step.

## Start and coordinate an agent

Default to a sibling pane in the current tab and the current working directory. Do not create a workspace, tab, worktree, or different cwd unless the user explicitly requests it.

Honor a direction requested by the user. Otherwise inspect the caller pane:

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

Split a wide pane to the right and a narrow or tall pane down; avoid repeated same-direction splits that leave unusably narrow columns or short rows. Keep the user's focus in the calling pane and preserve the caller's working directory (this same command also creates the pane for an ordinary command in the next-but-one section):

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Replace `right` with `down` when appropriate. Read the new pane ID from `.result.pane.pane_id`.

A pane fresh from `split`, or the root pane from a fresh `workspace create`, may still be running shell startup scripts (dotfiles onboarding, environment checks, `direnv` loading) and is not yet an available shell. `agent start` on a busy pane fails immediately with `agent_pane_busy`. The delay is short and bounded (observed: a few seconds); do not guess a sleep, retry with a short bounded backoff:

```bash
for i in 1 2 3 4; do
  herdr agent start reviewer --kind codex --pane <returned-pane-id> && break
  sleep 3
done
```

Stop the loop on `agent_not_ready` and `agent_name_taken` too: both mean the agent DID start on an earlier try, and looping on burns the remaining attempts on a taken name (measured 2026-09-06). `agent_not_ready` with `agent_status: blocked` right after start is usually a startup dialog; read the pane. Claude's folder-trust prompt is the common one: it appears when the pane's cwd was never opened as a project, and accepting it writes trust into the user's own config. Do not accept it on the user's behalf; `send-keys esc`, close the pane, and split again with a cwd that is already trusted (the current project).

An available shell pane is at its interactive prompt, shell in the foreground, no foreground command, editor, or agent. Start a supported agent there with a useful unique name:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id>
```

Use the kind the user requested; `herdr agent` lists installed kinds and options. Native agent arguments go after `--`:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id> -- <agent-args...>
```

`agent start` returns once Herdr detects the expected agent in that pane and considers it ready for input; default startup timeout 30 seconds. If the agent is blocked during startup it returns `agent_not_ready` immediately, but the name stays usable for `agent read` and `agent send-keys`: read the pane, clear the dialog, wait for idle before prompting.

Submit work through the agent surface:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings." --wait --timeout 120000
```

`agent prompt` sends text followed by encoded Enter as ONE ORDERED SUBMISSION, honoring the pane's live bracketed-paste mode. From 0.9.x it reports successful submission only after BOTH have been written, and that alone does not prove the agent started a turn. For Codex on Windows it sends a paste boundary before Enter so submission does not depend on prompt size. It refuses an agent already at an approval or question dialog, returning `agent_blocked` before sending any input: inspect the blocked UI and ask the user, because that answer is theirs. For normal work `--wait` is enough: it waits for the first settled `idle`, `done`, or `blocked`. Do not repeat those defaults with `--until`.

With `--wait`, a prompt sent from a non-working state must produce observed `working` or `blocked` activity within five seconds; unrelated `idle`, `done` or session changes do not satisfy the gate (0.9.0, #3685). It returns `agent_prompt_stalled` if nothing is observed, or `timeout` if the caller's timeout expires first; the caller timeout includes submission time. Without a timeout the settled-state wait is indefinite once activity is observed. The wait tracks lifecycle state, not one turn; if the agent is already working, completion of the active turn may satisfy it.

That five-second window is tight here (session-start hooks, skill loading, a custom status line) and the miss is reproducible: the visible `working` transition can take longer than five seconds while the prompt was accepted and ran. `agent_prompt_stalled` on a healthy target does not mean the prompt failed; check with `agent read` before retrying. To skip the stall check, decouple submit from wait:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings."
herdr agent wait reviewer --timeout 120000
```

The first call only submits; no five-second grace check applies without `--wait`. The second is a plain wait with whatever timeout the task needs.

`agent prompt` COULD type the text and not submit it on 0.8.2 (W-20260922-A11, F8a). Hit twice 2026-09-22: the call returned `agent_prompted`, `agent wait` returned, and the pane showed the prompt sitting IN THE INPUT BOX after the `>` rather than above it as a sent turn; no hook fired.

**RE-MEASURED 2026-09-22 on a live 0.9.1 server: it did not reproduce in 21 attempts.** Ten prompts to a named `claude` agent (five `--wait`, five bare), ten to a settled `pj --profile scratch` session on the same split, and one to a fresh `pj` session on its first ever turn. All 21 returned `agent_prompted` and all 21 produced the agent's reply, verified by a reversed-word sentinel that cannot appear in the echoed prompt. `agent_prompt_stalled` fired ZERO times, including under pj's per-turn hook overhead, which is the condition the five-second gate was said to miss. Control in the same runs: prompting a pane whose agent is not yet detected returns `agent_not_found` (exit 1), a clean refusal rather than a silent non-submission.

So 0.9.0's #3506 and #3685 hold here. The check survives at lower cost: upstream still says success reports submission rather than a started turn, so on a prompt that matters read the pane (`herdr-pane-read <target>`) and look at where the text sits; the fix is `herdr pane send-keys <pane-id> enter`. `pane run` into a pane whose shell is still printing its startup banner can lose the first character (2026-09-22: `pj --profile p10` ran as `j --profile p10`), so read the pane after any `pane run` into a freshly split pane before trusting that the command ran.

Use `--until` only for a state-specific workflow, such as waiting for a running agent to request input:

```bash
herdr agent wait reviewer --until blocked --timeout 120000
```

Without `--until`, standalone `agent wait` uses the same settled-state defaults as `agent prompt --wait`.

`agent wait` and `agent_status` are unreliable when the pane holds a nested TUI on top of another agent (a coding-agent session started inside a pane Herdr already recognizes as hosting a different agent): 2026-08-19, `agent_status` reported `idle` immediately and repeatedly while the pane was visibly working (climbing elapsed-time counter, unchanged `revision` across two `wait` calls). Corroborate with a direct `herdr pane read --source visible` before trusting `idle` on a nested pane.

Logical keys for interactive agent UI controls; Herdr validates all keys before writing any bytes:

```bash
herdr agent send-keys reviewer esc
herdr agent send-keys reviewer ctrl+c
```

Read the result through the resolved agent:

```bash
herdr agent get reviewer
herdr-pane-read reviewer -n 120
herdr agent read reviewer --source recent-unwrapped --lines 120   # raw form: pass a GENEROUS --lines
```

`agent get`'s result key is `agent` (singular): the status field is `.result.agent.agent_status`, not `.result.agent_status`. `agent list` differs: its `.result.agents[]` array has `agent_status` as a sibling of `agent`, and `.agent` there is only the KIND string (`"claude"`), with NO agent name field (keys measured 2026-09-24: agent, agent_session, agent_status, cwd, focused, foreground_cwd, pane_id, revision, state_change_seq, tab_id, terminal_id, terminal_title, terminal_title_stripped, workspace_id); `.agent.name` errors. Match a worker by `pane_id`, or use `agent get <name>`. A jq filter on the wrong (shallower) path returns `null` on every call, foreground and background alike; verify any status filter against a real `agent get` response first.

If a wait fails or returns `blocked`, inspect `agent get` and `agent read` before deciding what to send. A timeout or a stalled response does not prove the prompt was never delivered; a resend after a delivered prompt puts the text into the agent twice. Use the pane surface only when raw terminal control is intentional.

## Start a clean-room Claude in a pane

For measuring front-loaded context (CLAUDE.md, memory, skills, MCP) piece by piece, the user may ask for a Claude with none of it. Split a sibling pane with `--cwd` set to a NEW empty folder (project CLAUDE.md and auto-memory are keyed by folder), then:

```bash
herdr agent start cleanroom --kind claude --pane <returned-pane-id> -- --setting-sources '' --strict-mcp-config
```

Measured 2026-09-06 on Claude Code 2.1.263: that session sees no CLAUDE.md from any path (global included), no memory, no PAI, zero MCP tools. `--bare` is NOT usable: it never reads OAuth or the keychain and fails "Not logged in" on the user's Max account; a fresh `CLAUDE_CONFIG_DIR` is logged out for the same reason. The folder-trust dialog appears once because the folder is new; accepting it for an empty scratch folder is harmless (unlike for `$HOME`). Add context with `--append-system-prompt-file <file>`, or drop a `CLAUDE.md` in the folder and relaunch without `--setting-sources ''`; `/context` inside the session is the token meter. The dotfiles ship `claude-clean` (in `.zshrc`) as the one-word interactive form.

## Run an ordinary command in another pane

Create a sibling pane with the same split command and geometry rule as in "Start and coordinate an agent" (preserves cwd, keeps focus), read the new pane ID from `.result.pane.pane_id`, then run and inspect:

```bash
herdr pane run <returned-pane-id> "just test"
herdr pane wait-output <returned-pane-id> --match "test result" --timeout 120000
herdr-pane-read <returned-pane-id> -n 120
herdr pane read <returned-pane-id> --source recent-unwrapped --lines 120   # raw form: pass a GENEROUS --lines
```

`pane run` atomically sends command text and Enter. `pane wait-output` searches the selected snapshot immediately, so existing output can match. `--match <text>` is a literal substring, `--regex <pattern>` a Rust regular expression. Omitting `--timeout` waits indefinitely.

Read sources:

- `visible`: the currently rendered viewport.
- `recent`: recent rendered output, including soft wraps.
- `recent-unwrapped`: recent output with soft wraps joined; prefer it for logs and transcripts.
- `detection`: the plain-text bottom-buffer snapshot used for agent detection.

`visible` FOLLOWS THE USER'S SCROLL POSITION; `recent` DOES NOT. Measured 2026-09-20, both sources read at the same instant on a pane scrolled up 177 rows: `visible` returned the scrolled-to region from mid-history, `recent` the newest rows. A `visible` read of a scrolled pane hands you an old screen and looks normal. Check `.result.pane.scroll.offset_from_bottom` from `pane get` (0 means pinned to the bottom), or use `herdr-pane-read`, which reads that field and says on stderr when a pane is scrolled and whether the chosen source cares.

THE BLANK-REGION FLOOR IS FIXED IN 0.9.1 (upstream #3444). Both worlds, so the fix is legible rather than asserted.

**On 0.8.2 and earlier**, `--lines N` counted N rows up from the bottom of the terminal GRID, not the CONTENT; blank rows below the content filled your N and were trimmed, so a pane full of text read as empty. The floor was `viewport_rows - content_rows + 1` and any N below it returned zero bytes. Measured 2026-09-20 on herdr 0.8.2, three panes, a failing arm and a passing arm each. Idle Claude pane with 0 tokens: viewport 90, content 24, floor 67, N=66 returned 0 bytes, N=67 returned 209 bytes. A busy Claude pane (floor 2) and a plain shell pane with no agent (floor 36) behaved the same; their numbers are listed in the rewrite's `removals.md`. It was NOT the source: at `--lines 200` that idle pane returned the same 3070 bytes from all four of `visible`, `recent`, `recent-unwrapped` and `detection`. A pane that had just run `clear` had its content in the top rows and hit the same floor.

**On 0.9.1 the floor is gone, and `--lines N` counts CONTENT rows.** RE-MEASURED 2026-09-22 on a live 0.9.1 server against a plain shell pane holding 16 content rows in a 92-row grid, so 76 blank rows below the content and an 0.8.2 floor of 77. Every arm returned bytes: `N=500` 1095, `N=77` (the old floor) 1095, `N=76` (below it, the arm that returned 0 on 0.8.2) 1095, and `N=5` 1029, which is exactly the last five CONTENT rows rather than five grid rows. Control in the same session: a pane deliberately cleared so its content sat in the top rows returned 476 bytes at `N=3`, where 0.8.2 returned zero.

Trailing blank rows are gone from the response too. Four panes read at `--lines 500` on 0.9.1, including the deliberately cleared one, returned ZERO trailing blank rows, so the blank-stripping a reader used to have to do is now upstream's job.

Use [`herdr-pane-read`](../../../.local/bin/herdr-pane-read) anyway, for what #3444 did NOT replace. Its over-sized request and its blank-stripping are now no-ops, measured above. What is still live and has no equivalent in the raw command: it states on stderr what it showed OF WHAT (`showed 5 of 99 content rows -- 94 HIDDEN`, or `showed all N (nothing hidden)`), so a short read cannot be mistaken for a complete one; it says exit 3 OUT LOUD when a pane is genuinely empty instead of returning silence; it warns when a pane is scrolled and the chosen source follows that scroll; and it takes a live agent NAME as well as a pane id or `--current`. The agent-name path was OBSERVED 2026-09-22 (`resolved agent 'f9bagent' to pane w3X:p24`), with a nonexistent name failing loudly at exit 1 and the pane-id path printing the identical accounting line. `herdr-pane-read --selftest` proves its six arms. Raw `herdr pane read` / `agent read` are now safe at any `--lines` on 0.9.1, and still report nothing about completeness. On 0.8.2 they were fine only with a generous `--lines` (400 or more) and dangerous with a small one.

Use `--format ansi` when colors and styling are evidence; otherwise text.

`--lines` asks for more rows from the pane's screen and host scrollback. If increasing it does not reveal more of a completed response, the pane is probably running the agent on the terminal's alternate screen, whose rows do not enter host scrollback. On 0.8.2 the floor had to be ruled out FIRST, because a read returning nothing at all was the floor rather than the alternate screen (misdiagnosed twice in one session on 2026-09-20); on 0.9.1 that confound is gone, so an empty read is now evidence about the pane rather than about `--lines`. From 0.9.x, for supported IDLE agents Herdr can collect application-owned history and restore the viewport afterwards, though not every application or response can be recovered; a bigger `--lines` is worth one more try on an idle agent before falling back.

Herdr knows when it dropped rows: `PaneReadResult` carries a `truncated` field (herdr 0.8.0, #1717), confirmed 2026-09-17 in `herdr api schema --json` under both `success_response` and `subscription_event`. The plain CLI read prints text, so the field is not visible in normal use; `pane read --raw` is the likely way to see it, NOT verified (the trial pane produced no output, so the trial was void, not negative). Treat the flag as a signal to look for, not a recipe.

If a larger recent read still does not reveal the completed response, ask the agent to write it as Markdown in a temporary directory and reply only with the file path, then read that file ON THE SAME MACHINE. Fallback only; do not request file output in the initial prompt.

## Wait for completion without polling

`agent wait`, `agent prompt --wait`, and `pane wait-output` block on Herdr's own event system. Never wrap any of them in your own `while`/`until` + `sleep` loop: it is redundant, and the calling harness's anti-polling guard will likely block it.

To wait without holding the calling turn open, hand one blocking `herdr agent wait <target> --timeout N` (or `pane wait-output`) call to a single background monitor task, not a loop inside it. That delivers exactly one notification when the state changes.

If a monitor script's `herdr` calls fail unexpectedly, look for a bug in the script before suspecting Herdr or the sandbox. Confirmed cause once: a shell variable named `status` (read-only in zsh, silent failure: `read-only variable: status`). Rename it. The sandbox flag is still required inside a background task (measurement in Read this first).

`pane wait-output --match`/`--regex` searches all recent pane text, including the TYPED command line the instant it is echoed, before the command runs. A match string that also appears in the command you sent matches immediately on the echo. Pick a string that can only exist in genuine output, assembled at runtime (`printf "%s%s" "A_" "B"`) rather than typed as one literal, and measure real elapsed time (`date +%s` before/after) when you need to be certain a wait blocked rather than false-matched.

This compounds with the nested-TUI `idle` warning: corroborate a wait that settled unexpectedly fast with a direct `pane read --source visible`. Reproduced 2026-09-06 on a Claude Code pane: `agent wait` returned 0 one second into a turn that ran fifteen more. The reliable pattern for a nested Claude is a sentinel: ask the agent to end its reply with a word spelled backwards (the reversed form never appears in the echoed prompt), then `pane wait-output --match <reversed-word>`.

## Name what you create: workspace, tab, pane

One convention on this estate, ruled 2026-09-22 (F5d), so a sidebar and a `ListAgents` listing read as one world:

| Level         | Name it?                     | Shape                               | Example                                |
| ------------- | ---------------------------- | ----------------------------------- | -------------------------------------- |
| **workspace** | **no**, leave it alone       | it auto-tracks the repo already     | `fifty-shades-of-dotfiles`             |
| **tab**       | yes, at creation (`--label`) | the PURPOSE                         | `main`, `scratch/f5d`, `f5d-control`   |
| **pane**      | yes (`pane rename`)          | the session's own name, or its ROLE | `fifty-shades-of-dotfiles-f5d-control` |

A pane running a `pj` session is labelled by `pj` itself at launch with that session's `CLAUDE_CODE_SESSION_NAME`. Label the panes you open (a build pane, a log tail, a control session) and clear them when you close the work: `herdr pane rename <id> --clear`.

Why the pane: measured 2026-09-22 on herdr 0.8.2, `herdr agent list` carries no pane or tab label, only `terminal_title`, which Claude Code overwrites with the current task summary while working and with the shell prompt after it exits, so a session's name is visible there only while nothing is happening. The pane label is the one stable join between the two listings. A Claude session's registry entry appears before its name is applied, so the entry alone does not prove the pane will accept a prompt.

A pane label survives the pane's process exiting (measured: a pane kept `control` after its Claude was exited and the title reverted to the shell prompt). A label you set is a claim that stays on screen after the thing it described is gone. Clear it.

## Workspace labels: rename is permanent, do not use it to "refresh" a title

A workspace's sidebar label auto-tracks its live pane cwd until you call `herdr workspace rename <id> <label>`. That writes a permanent override (`custom_name` in herdr's session state) that always wins over the real cwd, even after a later `cd`. There is no supported way to clear it (upstream herdr#3252, closed `not_planned`; only panes have a reset action).

Never `workspace rename` as a trick to refresh a stale value (for example, working around herdr#3200's stuck outer-window-title copy by renaming a workspace to its own current label). That "no-op" rename still pins the workspace permanently. Confirmed 2026-08-28: a plugin doing this pinned a workspace to a stale creation-time name within seconds, because its 0.5s delay before reading the "current" label was shorter than the shell's startup race.

Never pass an empty label: `herdr workspace rename <id> ""` has no CLI guard and silently sets a permanently blank, equally unclearable name.

To correct a stale title without renaming, rebuild the display value from a fresh `herdr api snapshot`'s pane `foreground_cwd`/`cwd` and set it through a non-sticky channel (`herdr terminal title set`, not `workspace rename`).

## Safety and coordination rules

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current`, an explicit pane ID, or a unique agent name. Do not rely on another client's focused pane.
- Parse IDs from JSON responses, not sidebar order or examples.
- Do not close workspaces, tabs, panes, or sessions you did not create unless the user explicitly asked. `workspace close --group` closes the primary workspace AND its linked worktree workspaces; never add it merely to bypass `workspace_group_close_required`. That refusal (0.9.0, #2874) means the close would take more than you named: a finding, not an obstacle.
- Use `--trust-repository` only after the USER has verified the repository. It grants per-request Git trust; it is not a routine retry for a failed worktree command.
- Client and server versions can differ after an update. Check `herdr status` before relying on new server features. A missing method is not permission to stop or upgrade a server.
- Read panes with `herdr-pane-read`, not a hand-picked `--lines`. The 0.8.2 floor it worked around is fixed in 0.9.1; what it still adds is a positive statement of what it showed of what, a spoken exit 3 on an empty pane, a scroll warning, and agent-name targeting (Run an ordinary command).
- Never close a pane, workspace, tab, or session on `agent_status: idle` alone. Confirm the expected output with a direct `herdr-pane-read`, not the status field. `idle` can be reported early on a nested-TUI pane; closing on a false idle kills work that is not recoverable, not merely delayed.
- `workspace close --group` EXISTS on 0.9.1 but `herdr workspace close --help` prints `Usage: herdr workspace close <workspace_id>` and nothing else. Measured 2026-09-22: bare `close <id>` reached the server (exit 1, server error), `close <id> --group` ALSO reached the server (exit 1, so it parsed), and `close <id> --close-group` was rejected at parse time with exit 2 and the real usage line, `usage: herdr workspace close <workspace_id> [--group]`. The syntax error is a better reference than the help: `--help` omitting a flag and the flag not existing look identical, and only a rejected sibling separates them.
- **The group refusal fires on the PRIMARY only, and a lone worktree workspace closes normally.** OBSERVED 2026-09-22 on a live 0.9.1 server against a throwaway repo with one primary workspace and one linked worktree workspace, three arms in order. Closing the PRIMARY while the worktree workspace was open: exit 1 and, verbatim,

  ```text
  {"error":{"code":"workspace_group_close_required","message":"workspace has linked worktree workspaces; use --group (close_group=true in the API) to close the group"},"id":"cli:workspace:close"}
  ```

  Then closing the LONE WORKTREE workspace: exit 0, `{"result":{"type":"ok"}}`. Then closing the primary again, now childless: exit 0. The second and third arms are the controls, and they are what prove the refusal is about the group rather than about that workspace. Note the payload key is `code`, not `type`.

- `pane close` takes the pane ID as a bare positional (`herdr pane close <pane_id>`), like most `pane` subcommands; only `layout`, `current` and `split` accept `--pane`/`--current` (table in Use IDs). `herdr pane close --pane <id>` is a syntax error (exit 2). `workspace close <workspace_id>` is the same shape and returns `{"result":{"type":"ok"}}` (verified 2026-09-06).
- Never run `herdr server stop` from an active session unless the user explicitly intends to stop the server and its pane processes.
- Never run bare `herdr server`. The server is service-managed on every box: `systemctl --user {start,restart,status} herdr.service` on Linux/WSL, `brew services {start,restart} herdr` on macOS. A hand-started server inherits the launching shell's environment (made every pane skip the dotfiles welcome banner on the Linux box, 2026-09-06) and dies with that session. A `herdr()` function in `.zshrc` refuses the bare form and prints the service command; on Linux it also starts the unit before an attach, because attach silently spawns its own server when none is running. Details: `docs/HERDR.md` in the dotfiles repo.
- `herdr status server --json` is the canonical "is a server running" probe: `.running` (bool) and `.restart_needed` (true when the binary on disk is newer than the running server). It works with no server up (`"status":"not_running"`) and never starts one.
- Config gotcha: a `tab_bar_right` `command` entry in `config.toml` runs on the SERVER host, under the server's environment, every `interval_seconds`. A path that exists on only one machine fails every tick on the other and floods `herdr-server.log` (12188 of 12641 lines on the Linux box before it was noticed). Use paths that are the same on every box and resolve the host inside the script.
- Never kill the main Herdr process. Use named test sessions for experiments that need an isolated server.
- CLI server errors are JSON on stderr with exit status 1. CLI syntax errors exit with status 2.
