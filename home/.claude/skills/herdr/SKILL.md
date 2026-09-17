---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, tabs, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires HERDR_ENV=1."
---

# Herdr

Herdr organizes terminals into workspaces, tabs, and panes, recognizes coding agents running inside panes, and exposes the current session through the `herdr` CLI.

Before issuing any control command, verify that this agent is running inside a Herdr-managed pane:

```bash
test "${HERDR_ENV:-}" = 1
```

If the check fails, do not inspect or control the user's focused Herdr session from outside Herdr -- say that you are not running inside Herdr and stop, for that kind of work.

The check gates control of the USER'S session, not the binary. Operating the CLI on another host over SSH for setup or diagnosis is legitimate (2026-09-06: proving a banner fix on a Linux box by creating one workspace, waiting on its pane, reading it, and closing it). Rules for that mode: prefer `status`, `list` and `read`; touch only workspaces, tabs and panes you created in the same command; close them when done; never `server stop`; and `--no-focus` everything, because the user may be attached. Two mechanics: `herdr` is not on PATH in a non-interactive ssh shell (only the interactive profile adds `~/.local/bin`), so call `~/.local/bin/herdr` or export PATH first; and never stop or restart the server from INSIDE one of its own panes -- the stop kills the pane before the next command runs, and the pane's workspace is saved into the session for the restart to restore (2026-09-06: had to start the unit by hand and close the orphan).

When the check passes, the `herdr` binary in `PATH` talks to the current session. Use it to inspect neighboring work, create terminal layout, start agents and commands, read output, and wait for state changes.

Running under Claude Code's sandbox blocks every `herdr` subcommand that touches the socket (`~/.config/herdr/herdr.sock`), even when that socket path is already granted `allowWrite` in `settings.local.json` -- the failure is `Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }`. Re-verified 2026-08-19: the grant does not fix it. Run every `herdr` command with `dangerouslyDisableSandbox: true`; do not spend a retry re-checking the grant first.

## Learn the current CLI

The installed binary is the authority for command syntax. Start with:

```bash
herdr --help
```

Then print the relevant command group by running the group without a subcommand:

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
```

Do not run bare `herdr` for discovery; it launches or attaches the TUI. Do not probe a mutating nested command by omitting arguments. Commands such as `herdr workspace create` are valid with defaults and will execute.

Most control commands return JSON. Read identifiers and state from those responses instead of predicting them. The exceptions are the read commands: `pane read` and `agent read` print the pane text itself, not JSON -- piping them into `jq` fails with "Invalid numeric literal" (cost one round trip on 2026-09-06). `workspace create`, `tab create`, `pane split`, `*list`, `status`, and the `close` commands are JSON.

## Understand layout, panes, and agents

Choose the primitive that matches the job:

- Workspace, tab, and pane topology organize terminal locations.
- Pane commands control raw terminals, shells, tests, servers, input, and output.
- Agent commands control the recognized coding agent currently occupying a pane.

A pane exists whether or not it contains an agent. `agent start` requires an existing available shell pane and never creates, splits, or moves layout. Use pane commands for ordinary processes. Use agent commands when Herdr must validate agent identity or interpret `idle`, `working`, `blocked`, `done`, and `unknown` lifecycle states.

Agent commands accept either a unique live agent name or the pane ID currently hosting that agent. They do not accept terminal IDs or bare agent-kind labels. Names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents. A name follows the current pane occupant and is cleared when that agent exits, is released, or is replaced.

`idle` means the agent is ready for input and its tab has been seen in the focused Herdr UI. `done` is the same underlying idle state after unseen background work finishes. Focusing the tab or targeting the pane or agent with a focus command marks it seen. CLI reads do not mark it seen. `blocked` means Herdr recognized an approval or question UI. `unknown` means an agent is present but Herdr cannot classify it confidently; it does not prove completion.

## Use IDs and caller context

Public IDs are opaque stable handles:

- workspace: `w1`
- tab: `w1:t1`
- pane: `w1:p1`

Closed tab and pane IDs are not reused. A pane moved into another workspace receives a new workspace-qualified pane ID. After `pane move`, continue with `.result.move_result.pane.pane_id` or the live agent name. The old value is reported as `.result.move_result.previous_pane_id`; only the moved process's inherited caller context keeps resolving that old ID, so do not use it as a general agent target.

Herdr injects the caller's context into each managed pane:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

Prefer `--current` when a pane command should target the calling pane. Omitting a target may use the UI-focused pane, which can belong to the user or another client.

Discover live state with:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Creation responses expose the IDs to use next. `workspace create` returns `.result.workspace`, `.result.tab`, and `.result.root_pane`; the id fields inside those objects are `.result.workspace.workspace_id` (`wF`), `.result.tab.tab_id` (`wF:t1`) and `.result.root_pane.pane_id` (`wF:p1`) -- verified 2026-09-06. `tab create` returns `.result.tab` and `.result.root_pane`. `pane split` returns the new pane as `.result.pane`.

## Create a worktree

This estate keeps every git worktree inside the project it belongs to, at `<repo>/.worktree/<branch>`. Never herdr's shared default (`~/.herdr/worktrees`), and never the sidebar "New worktree" button, which always uses that shared default too.

Use the `hwt` wrapper instead of calling `herdr worktree create` directly:

```bash
hwt <branch-name>
```

Run it from inside the target repo (any subdirectory works). It resolves the repo root, then calls `herdr worktree create --branch <branch-name> --cwd <repo-root> --path <repo-root>/.worktree/<branch-name>`. Extra flags (`--base REF`, `--label TEXT`, `--focus`, `--no-focus`) pass straight through.

Never call `herdr worktree create` without `--path`. It defaults to the shared folder instead of the project, and `--path` requires an absolute path -- a relative one is rejected. `worktree list`, `worktree open`, and `worktree remove` are unaffected; use them directly.

`worktree remove --workspace ID` does three things in one call: deletes the git worktree, removes its checkout directory, and closes the associated workspace/pane/session -- no separate close step is needed.

## Start and coordinate an agent

Default to a sibling pane in the current tab and the current working directory. Do not create a workspace, tab, worktree, or different cwd unless the user explicitly requests that topology or location.

Honor a direction requested by the user. Otherwise inspect the caller pane:

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

Split a wide pane to the right and a narrow or tall pane down. Avoid repeated same-direction splits that create unusably narrow columns or short rows. Keep the user's focus in the calling pane and explicitly preserve the caller's working directory:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Replace `right` with `down` when appropriate. Read the new pane ID from `.result.pane.pane_id`.

A pane returned by a fresh `split` -- or the root pane returned by a fresh `workspace create` -- may still be running its own shell startup scripts (dotfiles onboarding, environment checks, `direnv` loading) and is not yet an available shell. `agent start` on a busy pane fails immediately with `agent_pane_busy` rather than waiting for it. This delay is short and bounded (observed: a few seconds), not open-ended -- do not guess a sleep duration for it. Retry with a short bounded backoff instead:

```bash
for i in 1 2 3 4; do
  herdr agent start reviewer --kind codex --pane <returned-pane-id> && break
  sleep 3
done
```

Stop the loop on `agent_not_ready` and `agent_name_taken` too, not only on success. Both mean the agent DID start on an earlier try; looping on will just burn the remaining attempts on a name that is now taken (measured 2026-09-06). `agent_not_ready` with `agent_status: blocked` right after start is usually a startup dialog -- read the pane. Claude's folder-trust prompt is the common one: it appears when the pane's cwd was never opened as a project, and accepting it writes trust into the user's own config. Do not accept it on the user's behalf; `send-keys esc`, close the pane, and split again with a cwd that is already trusted (the current project).

An available shell pane must be at its interactive prompt, with the shell itself in the foreground and no foreground command, editor, or agent running. Start a supported agent in that pane with a useful unique name:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id>
```

Use the kind requested by the user. Run `herdr agent` to inspect the installed kind list and options. Pass native agent arguments only after `--`:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id> -- <agent-args...>
```

`agent start` returns only after Herdr detects the expected agent in the same pane and considers it ready for interactive input. It defaults to a 30-second startup timeout.

Submit work through the agent surface:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings." --wait --timeout 120000
```

`agent prompt` atomically submits text and encoded Enter while honoring the pane's live bracketed-paste mode. For normal agent work, `--wait` is enough: it waits for the first settled `idle`, `done`, or `blocked` state. Do not repeat those defaults with `--until`.

A prompt sent from a non-working state must produce an observed lifecycle change within five seconds. Otherwise Herdr returns `agent_prompt_stalled` instead of waiting indefinitely. This wait tracks lifecycle state, not an individual turn; if the agent is already working, completion of the active turn may satisfy it.

That five-second window is tight in an environment with heavy per-turn overhead (session-start hooks, skill loading, a custom status line) -- confirmed reproducible here, not a one-off: the visible "working" transition can take longer than five seconds even though the prompt was accepted and did run. `agent_prompt_stalled` on an otherwise-healthy target does not mean the prompt failed; check with `agent read` before retrying anything. To avoid the stall check entirely, decouple submit from wait instead of using the combined flag:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings."
herdr agent wait reviewer --timeout 120000
```

The first call only submits -- no five-second grace-period check applies without `--wait`. The second call is a plain wait with whatever timeout the task actually needs.

Use `--until` only for a state-specific workflow, such as waiting for an already-running agent to request input:

```bash
herdr agent wait reviewer --until blocked --timeout 120000
```

Without `--until`, standalone `agent wait` uses the same settled-state defaults as `agent prompt --wait`.

`agent wait` and `agent_status` can be unreliable when the pane holds a nested TUI on top of another agent (for example, a coding-agent session started inside a pane Herdr already recognizes as hosting a different agent). Observed 2026-08-19: `agent_status` reported `idle` immediately and repeatedly while the pane was still visibly working (climbing elapsed-time counter, unchanged `revision` across two `wait` calls). Corroborate with a direct `herdr pane read --source visible` before trusting `idle` on a nested pane.

Use logical keys for interactive agent UI controls:

```bash
herdr agent send-keys reviewer esc
herdr agent send-keys reviewer ctrl+c
```

Herdr validates all keys before writing any bytes. Read the result through the resolved agent:

```bash
herdr agent get reviewer
herdr agent read reviewer --source recent-unwrapped --lines 120
```

`agent get`'s result key is `agent` (singular, one object) -- the status field is `.result.agent.agent_status`, not `.result.agent_status`. This differs from `agent list`, whose `.result.agents[]` array has `agent_status` as a sibling of `agent`, not nested under it. Confirmed cause of a wasted debugging session: a script checking the wrong (shallower) path saw `null` on every call, foreground and background alike, and that false signal was briefly mistaken for a real Herdr behavior. Verify any status-reading jq filter against a real `agent get` response before trusting it.

If a wait fails or returns `blocked`, inspect `agent get` and `agent read` before deciding what input to send. Use the pane surface only when raw terminal control is intentional.

## Start a clean-room Claude in a pane

For measuring front-loaded context (CLAUDE.md, memory, skills, MCP) piece by piece, the user may ask for a Claude with none of it. Split a sibling pane with `--cwd` set to a NEW empty folder (project CLAUDE.md and auto-memory are keyed by folder), then:

```bash
herdr agent start cleanroom --kind claude --pane <returned-pane-id> -- --setting-sources '' --strict-mcp-config
```

Measured 2026-09-06 on Claude Code 2.1.263: that session sees no CLAUDE.md from any path (the global one included), no memory, no PAI, zero MCP tools. `--bare` is NOT usable here: it never reads OAuth or the keychain and fails "Not logged in" on the user's Max account; a fresh `CLAUDE_CONFIG_DIR` is logged out for the same reason. The folder-trust dialog will appear once because the folder is new; accepting it for an empty scratch folder is harmless (unlike accepting it for `$HOME`). Add context with `--append-system-prompt-file <file>`, or drop a `CLAUDE.md` in the folder and relaunch without `--setting-sources ''`; `/context` inside the session is the token meter. The dotfiles ship `claude-clean` (in `.zshrc`) as the one-word interactive form.

## Run an ordinary command in another pane

Create a sibling pane with the same geometry rule, preserve the caller's working directory, and keep user focus unchanged:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Read the new pane ID from `.result.pane.pane_id`, then run and inspect the command:

```bash
herdr pane run <returned-pane-id> "just test"
herdr pane wait-output <returned-pane-id> --match "test result" --timeout 120000
herdr pane read <returned-pane-id> --source recent-unwrapped --lines 120
```

`pane run` atomically sends command text and Enter. `pane wait-output` searches the selected snapshot immediately, so output that already exists can match. Use `--match <text>` for a literal substring or `--regex <pattern>` for a Rust regular expression. Omitting `--timeout` allows an indefinite wait.

Use the read source that matches the task:

- `visible`: the currently rendered viewport.
- `recent`: recent rendered output, including soft wraps.
- `recent-unwrapped`: recent output with soft wraps joined; prefer it for logs and transcripts.
- `detection`: the plain-text bottom-buffer snapshot used for agent detection.

`recent` and `recent-unwrapped` come back EMPTY right after the pane ran `clear` (reproduced twice 2026-09-06, by two different sessions); `visible` still has everything on screen. Fall back to `visible` before concluding the pane is blank.

Use `--format ansi` when colors and terminal styling are evidence. Otherwise use text.

`--lines` asks Herdr for more rows from the pane's available screen and host scrollback. If increasing it does not reveal more of a completed response, the pane is probably running the agent on the terminal's alternate screen. Rows that leave the alternate screen do not enter Herdr's host scrollback, so a larger line count cannot recover them.

After that failed read, ask the agent to write its complete response as Markdown in a temporary directory and reply only with the file path, then read the file directly. Use this only as a fallback; do not request file output in the initial prompt.

## Wait for completion without polling

`agent wait`, `agent prompt --wait`, and `pane wait-output` block on Herdr's own event system; they do not poll. Never wrap any of them in your own `while`/`until` + `sleep` loop -- it is redundant, and the calling harness's own anti-polling guard will likely block a hand-rolled sleep loop anyway.

To wait without holding the calling turn open, hand the wait off to a single background monitor task instead of polling in the foreground: one blocking `herdr agent wait <target> --timeout N` (or `pane wait-output`) call inside that task, not a loop inside it. This delivers exactly one notification when the state actually changes, instead of you re-checking manually.

If a monitor script's `herdr` calls fail unexpectedly, look for a bug in the script itself before suspecting Herdr or the sandbox -- confirmed cause once: a shell variable named `status` (read-only in zsh, the failure is silent: `read-only variable: status`). Rename the variable. Every `herdr` call needs `dangerouslyDisableSandbox: true`, background monitor task or not -- re-tested directly and reconfirmed: a plain `herdr agent list` from inside a background task, with the flag omitted, still fails with the same `Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }` described above. An earlier version of this note claimed background calls work without the flag; that was wrong (or true only under conditions not reproduced here) and has been corrected.

`pane wait-output --match`/`--regex` searches all recent pane text, including the TYPED command line the instant it is echoed, before the command has run. A match string that also appears in the command you sent can match immediately on the echo, not on the real result. Pick a match string that can only exist in genuine output -- e.g. assembled at runtime (`printf "%s%s" "A_" "B"`) rather than typed as one literal substring in the command -- and prefer measuring real elapsed time (`date +%s` before/after) when you need to be certain a wait actually blocked rather than false-matching instantly.

This compounds with the nested-TUI `idle`-unreliability warning above: corroborate a wait that settled unexpectedly fast with a direct `pane read --source visible` before trusting it. Reproduced 2026-09-06 on a Claude Code pane: `agent wait` returned 0 one second into a turn that ran fifteen more. The reliable pattern for a nested Claude is a sentinel: ask the agent to end its reply with a word spelled backwards (the reversed form never appears in the echoed prompt), then `pane wait-output --match <reversed-word>`.

## Workspace labels: rename is permanent, do not use it to "refresh" a title

A workspace's sidebar label auto-tracks its live pane cwd -- until you call `herdr workspace rename <id> <label>`. That call writes a permanent override (`custom_name` in herdr's session state) that from then on always wins over the real cwd, even after a later `cd`. There is no supported way to clear it and go back to auto-tracking (upstream herdr#3252, closed `not_planned` -- only panes have a reset action, not workspaces).

Never call `workspace rename` as a trick to force a stale value to refresh (for example, working around herdr#3200's stuck outer-window-title copy by renaming a workspace to its own current label). That "no-op" rename still permanently pins the workspace. Confirmed live 2026-08-28: a plugin doing exactly this pinned a workspace to a stale creation-time name within seconds, because the 0.5s delay it used before reading the "current" label was shorter than the shell's real startup race.

Never pass an empty label either: `herdr workspace rename <id> ""` has no CLI guard and silently sets a permanently blank, equally unclearable name.

If a stale title/label needs correcting without renaming, rebuild the display value from a fresh `herdr api snapshot`'s pane `foreground_cwd`/`cwd` instead, and set it through a channel that isn't sticky (e.g. `herdr terminal title set`, not `workspace rename`).

## Safety and coordination rules

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current`, an explicit pane ID, or a unique agent name. Do not rely on another client's focused pane.
- Parse IDs from JSON responses. Do not derive them from sidebar order or examples.
- Do not close workspaces, tabs, panes, or sessions you did not create unless the user explicitly asked.
- Never close a pane, workspace, tab, or session on `agent_status: idle` alone. Confirm the actual expected output is present first -- a direct `pane read`/`agent read`, not just the status field. `idle` can be reported early on a nested-TUI pane (see above); closing on a false idle kills whatever was still genuinely running, and that work is not recoverable, not merely delayed.
- `pane close` takes the pane ID as a bare positional argument (`herdr pane close <pane_id>`), unlike most other `pane` subcommands which accept a `--pane` flag. `herdr pane close --pane <id>` is a syntax error (exit 2). `workspace close <workspace_id>` is the same shape and returns `{"result":{"type":"ok"}}` (verified 2026-09-06).
- Never run `herdr server stop` from an active session unless the user explicitly intends to stop the server and its pane processes.
- Never run bare `herdr server` either. The server is service-managed on every box in this estate: `systemctl --user {start,restart,status} herdr.service` on Linux/WSL, `brew services {start,restart} herdr` on macOS. A hand-started server inherits the launching shell's environment (which made every pane skip the dotfiles welcome banner on the Linux box, 2026-09-06) and dies with that session. A `herdr()` function in `.zshrc` refuses the bare form and prints the service command; on Linux it also starts the unit before an attach, because attach silently spawns its own server when none is running. Why and how: `docs/HERDR.md` in the dotfiles repo.
- `herdr status server --json` is the canonical "is a server running" probe: `.running` (bool) and `.restart_needed` (true when the binary on disk is newer than the running server). It works with no server up (`"status":"not_running"`) and never starts one.
- Config gotcha: a `tab_bar_right` `command` entry in `config.toml` runs on the SERVER host, under the server's environment, every `interval_seconds`. A path that exists only on one machine fails every tick on the other and floods `herdr-server.log` (12188 of 12641 lines on the Linux box before it was noticed). Use paths that are the same on every box and resolve the host inside the script.
- Never kill the main Herdr process. Use named test sessions for experiments that need an isolated server.
- CLI server errors are JSON on stderr with exit status 1. CLI syntax errors exit with status 2.
