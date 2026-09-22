---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, tabs, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires HERDR_ENV=1."
---

# Herdr

Herdr organizes terminals into workspaces, tabs, and panes, recognizes coding agents running inside panes, and exposes the current session through the `herdr` CLI.

## Read this first

Ten rules, each of which has already cost this estate a session. Every one is
argued from a measurement further down; this list exists so you meet them
BEFORE the mistake rather than while diagnosing it.

1. **Every `herdr` call needs `dangerouslyDisableSandbox: true`.** The socket is
   denied even when `settings.local.json` grants it, in background tasks too.
2. **Read panes with `herdr-pane-read`, never a hand-picked `--lines`.** A small
   `--lines` returns ZERO BYTES from a pane full of text.
3. **One wait per call, handed to a background task.** `agent wait` and
   `pane wait-output` block on Herdr's events. Never wrap either in your own
   `while`/`sleep` loop.
4. **A `wait-output` match string must be impossible in the command you sent.**
   It searches the echoed command line too, so a literal you typed matches
   instantly, before anything ran. Assemble the sentinel at runtime.
5. **A registry entry is not a ready agent.** A Claude session's entry appears
   BEFORE its name is applied (F5d), and `agent_status: idle` is reported early
   on a nested TUI. Neither proves the pane will accept a prompt.
6. **Never close anything on `idle` alone.** Confirm the expected output is
   really there with a read. Work killed by a false idle is gone, not delayed.
7. **Never `workspace rename`.** It writes a PERMANENT override with no way
   back, including a rename to the value already showing.
8. **`agent prompt` can type the text and not submit it.** Read the pane and
   look at where the text sits; the fix is `pane send-keys <pane-id> enter`.
9. **A timeout or a stall does not prove the prompt was never delivered.** Read
   before you resend, or the agent gets it twice.
10. **Close only what you opened, and clear the labels you set.** A pane label
    outlives the process it described.

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
herdr machine
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

`idle` and `done` both mean the agent is ready for input. The CLI and API use the server's seen state to distinguish them; explicit focus commands mark the target seen, while reads do not. Each TUI client tracks viewed completions independently, so its Done badge can differ from the CLI or another client's badge (upstream rewrote this paragraph for 0.9.x; before that it was phrased as one tab being seen in one focused UI). `blocked` means Herdr recognized an approval or question UI. `unknown` means an agent is present but Herdr cannot classify it confidently; it does not prove completion.

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

**Only three `pane` subcommands accept a target FLAG at all.** For those three, prefer `--current` when the target is the calling pane, because omitting a target may use the UI-focused pane, which can belong to the user or another client. Every other `pane` subcommand takes the pane id as a BARE POSITIONAL argument and rejects both flags with `unknown option` and exit 2. Measured 2026-09-20 against herdr 0.8.2 by reading each subcommand's `--help`, and **re-measured 2026-09-22 against 0.9.1: unchanged, all nine subcommands identical**:

| subcommand                                                                               | how to name the target                                              |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `pane layout`, `pane current`, `pane split`                                              | `--current` or `--pane <id>` (`split` also accepts a positional id) |
| `pane read`, `pane run`, `pane send-keys`, `pane wait-output`, `pane close`, `pane move` | positional `<PANE_ID>` only                                         |

**From 0.9.1 an omitted `pane split` target means the CALLING pane** when `HERDR_PANE_ID` is available, falling back to the focused pane otherwise (upstream #4123). That is NOT true of 0.8.2 and earlier, where an omitted target meant the UI-focused pane, which can belong to the user or another client. Every other `pane` subcommand still follows the old rule, so keep naming the target explicitly and do not rely on the new default.

So the calling pane is `herdr pane read "$HERDR_PANE_ID"`, NOT `herdr pane read --current`. This split is written out rather than left to "prefer" because an earlier version of this line said only "prefer `--current`", and a session reading it spent two round trips on `--pane` then `--current` before running `pane read --help` (2026-09-20). A rejected flag prints one short line with no usage block, so it reads like a Herdr fault rather than the syntax error it is.

Discover live state with:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Creation responses expose the IDs to use next. `workspace create` returns `.result.workspace`, `.result.tab`, and `.result.root_pane`; the id fields inside those objects are `.result.workspace.workspace_id` (`wF`), `.result.tab.tab_id` (`wF:t1`) and `.result.root_pane.pane_id` (`wF:p1`) -- verified 2026-09-06. `tab create` returns `.result.tab` and `.result.root_pane`. `pane split` returns the new pane as `.result.pane`.

## Control a saved SSH machine (0.9.1 and later)

Nothing on this estate has a saved machine yet, so none of this is measured here. It is upstream's text, kept verbatim in substance so the merge base stays comparable.

IDs and live agent names are scoped to one server. Two saved SSH machines can both have `w1:p1` or an agent named `reviewer`. Selecting a machine in the TUI does not retarget commands running in your pane: without `--machine`, they still use the inherited session and socket context.

To control a saved SSH machine, use the same global prefix for discovery and every later command:

```bash
herdr --machine <label-or-id> agent list
herdr --machine <label-or-id> pane list
herdr --machine <label-or-id> agent prompt <remote-agent-name> "Reply with your current status." --wait --timeout 120000
```

The selector must be an enabled saved profile ID or a unique, case-sensitive label, not an arbitrary SSH hostname. Commands use that profile's remote session without an open TUI. Do not combine `--machine` with `--session` or `--remote`. Discover IDs on that machine; inherited local IDs and `--current` do not identify remote panes.

Both installations must support machine API forwarding, and the remote server must already be running and API-compatible. Forwarding never installs, starts, or restarts a server and never falls back to Local. Local configuration, session management, installation commands, and interactive attachment are not forwarded. Remote worktree paths must be absolute, `~`, or start with `~/`; plugin link paths must be absolute. A connection failure does not prove a mutation was not applied: inspect remote state before retrying.

`herdr machine list` lists saved connection profiles, not a cross-machine pane inventory; add `--json` for scripts. Only add, remove, enable, or disable profiles when the user asks. Removing a profile disconnects the client but does not stop remote sessions. Adding a machine uses the remote default session unless `--remote-session` is explicitly supplied. Setup asks before stopping an incompatible server and defaults to No; do not approve replacement without the user's consent. Experimental handoff is not part of `machine add`.

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

`agent start` returns only after Herdr detects the expected agent in the same pane and considers it ready for interactive input. It defaults to a 30-second startup timeout. When the agent is blocked during startup it returns `agent_not_ready` immediately, but the name stays usable for `agent read` and `agent send-keys` -- so read the pane and clear the dialog rather than treating the start as failed, and wait for idle before prompting it.

Submit work through the agent surface:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings." --wait --timeout 120000
```

`agent prompt` sends text followed by encoded Enter as ONE ORDERED SUBMISSION, honoring the pane's live bracketed-paste mode. From 0.9.x upstream states the contract precisely, and the precision matters: it reports successful submission only after BOTH have been written, and **that alone does not prove the agent started a turn**. For Codex on Windows it sends a paste boundary before Enter so submission does not depend on prompt size. It refuses an agent already waiting at an approval or question dialog, returning `agent_blocked` before sending any input: inspect the blocked UI and ask the user before answering it, because that answer is theirs to give. For normal agent work, `--wait` is enough: it waits for the first settled `idle`, `done`, or `blocked` state. Do not repeat those defaults with `--until`.

With `--wait`, a prompt sent from a non-working state must produce observed `working` or `blocked` activity. After submission Herdr waits up to five seconds for that activity; unrelated `idle`, `done` or session changes do NOT satisfy the gate (0.9.0 tightened this, #3685: before it, any lifecycle change could complete the wait). It returns `agent_prompt_stalled` if no activity is observed, or `timeout` if the caller's timeout expires first, and the caller timeout includes submission time. Without a timeout the settled-state wait is indefinite once activity is observed. This wait tracks lifecycle state, not an individual turn; if the agent is already working, completion of the active turn may satisfy it.

That five-second window is tight in an environment with heavy per-turn overhead (session-start hooks, skill loading, a custom status line) -- confirmed reproducible here, not a one-off: the visible "working" transition can take longer than five seconds even though the prompt was accepted and did run. `agent_prompt_stalled` on an otherwise-healthy target does not mean the prompt failed; check with `agent read` before retrying anything. To avoid the stall check entirely, decouple submit from wait instead of using the combined flag:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings."
herdr agent wait reviewer --timeout 120000
```

The first call only submits -- no five-second grace-period check applies without `--wait`. The second call is a plain wait with whatever timeout the task actually needs.

**`agent prompt` can type the text and NOT submit it.** Hit twice on 2026-09-22 (F8a, W-20260922-A11): the call returned `agent_prompted`, `agent wait` then returned, and the pane showed the prompt sitting IN THE INPUT BOX after the `>` rather than above it as a sent turn; no hook fired. This is a different trap from the stall and the false idle above: the submit itself did not happen. The check is to read the pane (`herdr-pane-read <target>`) and look at where the text sits; the fix is an explicit `herdr pane send-keys <pane-id> enter`. The same swallowed-keystroke shape hits `pane run` on a pane whose shell is still printing its startup banner: the first character can be eaten (measured 2026-09-22: `pj --profile p10` ran as `j --profile p10`), so read the pane after any `pane run` into a freshly split pane before trusting that the command ran.

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
herdr-pane-read reviewer -n 120
herdr agent read reviewer --source recent-unwrapped --lines 120   # raw form: pass a GENEROUS --lines
```

`agent get`'s result key is `agent` (singular, one object) -- the status field is `.result.agent.agent_status`, not `.result.agent_status`. This differs from `agent list`, whose `.result.agents[]` array has `agent_status` as a sibling of `agent`, not nested under it. Confirmed cause of a wasted debugging session: a script checking the wrong (shallower) path saw `null` on every call, foreground and background alike, and that false signal was briefly mistaken for a real Herdr behavior. Verify any status-reading jq filter against a real `agent get` response before trusting it.

If a wait fails or returns `blocked`, inspect `agent get` and `agent read` before deciding what input to send. **A timeout or a stalled response does not prove the prompt was never delivered; do not blindly submit it again.** That is the refusal-is-not-an-answer rule aimed at your own retry: a resend after a delivered prompt puts the text into the agent twice. Use the pane surface only when raw terminal control is intentional.

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
herdr-pane-read <returned-pane-id> -n 120
herdr pane read <returned-pane-id> --source recent-unwrapped --lines 120   # raw form: pass a GENEROUS --lines
```

`pane run` atomically sends command text and Enter. `pane wait-output` searches the selected snapshot immediately, so output that already exists can match. Use `--match <text>` for a literal substring or `--regex <pattern>` for a Rust regular expression. Omitting `--timeout` allows an indefinite wait.

Use the read source that matches the task:

- `visible`: the currently rendered viewport.
- `recent`: recent rendered output, including soft wraps.
- `recent-unwrapped`: recent output with soft wraps joined; prefer it for logs and transcripts.
- `detection`: the plain-text bottom-buffer snapshot used for agent detection.

**`visible` FOLLOWS THE USER'S SCROLL POSITION; `recent` DOES NOT.** Measured 2026-09-20 with both sources read at the same instant on a pane scrolled up 177 rows: `visible` returned the scrolled-to region from the middle of the history, `recent` returned the newest rows. So a `visible` read of a scrolled pane hands you an OLD screen, and nothing in the output says so -- the read looks completely normal, it is just answering about a different moment. Check `.result.pane.scroll.offset_from_bottom` from `pane get` (0 means pinned to the bottom), or use `herdr-pane-read`, which reads that field and says on stderr when a pane is scrolled and whether the chosen source cares.

**A SMALL `--lines` RETURNS NOTHING WHEN THE CONTENT DOES NOT REACH THE BOTTOM OF THE PANE.** `--lines N` counts N rows up from the bottom of the terminal GRID, not from the bottom of the CONTENT. A pane whose program fills only the top of its screen has blank rows below; those blank rows fill your N and are trimmed before you see them, so a pane full of text reads as empty. The floor is `viewport_rows - content_rows + 1`, and any N below it returns zero bytes.

Measured 2026-09-20 on herdr 0.8.2, three panes, each with a failing arm and a passing arm in the same command:

| pane                  | what it was | viewport | content | floor | N=floor-1 | N=floor   |
| --------------------- | ----------- | -------- | ------- | ----- | --------- | --------- |
| idle Claude, 0 tokens | agent pane  | 90       | 24      | 67    | 0 bytes   | 209 bytes |
| busy Claude           | agent pane  | 90       | 89      | 2     | 0 bytes   | 52 bytes  |
| plain shell, no agent | shell pane  | 92       | 57      | 36    | 0 bytes   | 425 bytes |

It is NOT the source. At `--lines 200` that idle pane returned the same 3070 bytes from all four of `visible`, `recent`, `recent-unwrapped` and `detection`. An earlier note here said `recent` and `recent-unwrapped` "come back EMPTY right after the pane ran `clear`" while `visible` still worked; that is almost certainly this same floor, misattributed. After a `clear` the content sits in the top rows, and the two reads that disagreed differed in their `--lines` value as well as their source.

**Use [`herdr-pane-read`](../../../.local/bin/herdr-pane-read) instead of hand-picking a number.** It asks for more rows than the pane can hold, strips the blank region itself, shows the last N rows of real content, and always states on stderr what it showed of what -- including the case where the pane really is empty, which it says out loud rather than returning silence. `herdr-pane-read --selftest` proves its six arms. A raw `herdr pane read` is still fine when you pass a generous `--lines` (400 or more).

Use `--format ansi` when colors and terminal styling are evidence. Otherwise use text.

`--lines` asks Herdr for more rows from the pane's available screen and host scrollback. If increasing it does not reveal more of a completed response, the pane is probably running the agent on the terminal's alternate screen. Rule out the blank-region floor above FIRST: a read that returns nothing at all is the floor, not the alternate screen, and that misdiagnosis was made twice in one session on 2026-09-20 before the floor was measured. Alternate-screen rows do not enter ordinary host scrollback. **From 0.9.x this is no longer flatly unrecoverable:** for supported IDLE agents Herdr can collect application-owned history and restore the viewport afterwards, though not every application or response can be recovered that way. So a bigger `--lines` is worth one more try on an idle agent before falling back.

Herdr itself knows when it dropped rows: `PaneReadResult` carries a `truncated` field (herdr 0.8.0, #1717), confirmed 2026-09-17 in `herdr api schema --json` under both `success_response` and `subscription_event`. The plain CLI read prints pane text, not JSON, so that field is not visible in normal use; `pane read --raw` is the likely way to see it, NOT verified here (the throwaway pane used to test it produced no output yet, so the trial was void rather than negative). Treat the flag as a real signal to look for, not as a recipe.

If a larger recent read still does not reveal the completed response, ask the agent to write it as Markdown in a temporary directory and reply only with the file path, then read that file ON THE SAME MACHINE. Use this only as a fallback; do not request file output in the initial prompt.

## Wait for completion without polling

`agent wait`, `agent prompt --wait`, and `pane wait-output` block on Herdr's own event system; they do not poll. Never wrap any of them in your own `while`/`until` + `sleep` loop -- it is redundant, and the calling harness's own anti-polling guard will likely block a hand-rolled sleep loop anyway.

To wait without holding the calling turn open, hand the wait off to a single background monitor task instead of polling in the foreground: one blocking `herdr agent wait <target> --timeout N` (or `pane wait-output`) call inside that task, not a loop inside it. This delivers exactly one notification when the state actually changes, instead of you re-checking manually.

If a monitor script's `herdr` calls fail unexpectedly, look for a bug in the script itself before suspecting Herdr or the sandbox -- confirmed cause once: a shell variable named `status` (read-only in zsh, the failure is silent: `read-only variable: status`). Rename the variable. Every `herdr` call needs `dangerouslyDisableSandbox: true`, background monitor task or not -- re-tested directly and reconfirmed: a plain `herdr agent list` from inside a background task, with the flag omitted, still fails with the same `Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }` described above. An earlier version of this note claimed background calls work without the flag; that was wrong (or true only under conditions not reproduced here) and has been corrected.

`pane wait-output --match`/`--regex` searches all recent pane text, including the TYPED command line the instant it is echoed, before the command has run. A match string that also appears in the command you sent can match immediately on the echo, not on the real result. Pick a match string that can only exist in genuine output -- e.g. assembled at runtime (`printf "%s%s" "A_" "B"`) rather than typed as one literal substring in the command -- and prefer measuring real elapsed time (`date +%s` before/after) when you need to be certain a wait actually blocked rather than false-matching instantly.

This compounds with the nested-TUI `idle`-unreliability warning above: corroborate a wait that settled unexpectedly fast with a direct `pane read --source visible` before trusting it. Reproduced 2026-09-06 on a Claude Code pane: `agent wait` returned 0 one second into a turn that ran fifteen more. The reliable pattern for a nested Claude is a sentinel: ask the agent to end its reply with a word spelled backwards (the reversed form never appears in the echoed prompt), then `pane wait-output --match <reversed-word>`.

## Name what you create: workspace, tab, pane

One convention on this estate, ruled 2026-09-22 (F5d). It exists so a sidebar and a
`ListAgents` listing read as the same world rather than two.

| Level         | Name it?                     | Shape                               | Example                                |
| ------------- | ---------------------------- | ----------------------------------- | -------------------------------------- |
| **workspace** | **no** — leave it alone      | it auto-tracks the repo already     | `fifty-shades-of-dotfiles`             |
| **tab**       | yes, at creation (`--label`) | the PURPOSE                         | `main`, `scratch/f5d`, `f5d-control`   |
| **pane**      | yes (`pane rename`)          | the session's own name, or its ROLE | `fifty-shades-of-dotfiles-f5d-control` |

A pane running a `pj` session is labelled by `pj` itself at launch, with that session's
`CLAUDE_CODE_SESSION_NAME`. You do not need to do it. Label the panes **you** open — a
build pane, a log tail, a control session — and clear them when you close the work:
`herdr pane rename <id> --clear`.

**Why the pane and not the tab or the workspace.** Measured 2026-09-22 against herdr 0.8.2:
`herdr agent list` does **not** carry a pane or tab label at all. It carries
`terminal_title`, and Claude Code overwrites that with the current task summary while it
works and with the shell prompt after it exits — so a session's name is visible there only
while nothing is happening, which is exactly the property that cannot distinguish anything.
The pane label is the one stable join between the two listings.

A pane label **survives the pane's process exiting** (measured: a pane kept `control` after
its Claude was exited and the title reverted to the shell prompt). So a label you set is a
claim that stays on screen after the thing it described is gone. Clear it.

## Workspace labels: rename is permanent, do not use it to "refresh" a title

A workspace's sidebar label auto-tracks its live pane cwd -- until you call `herdr workspace rename <id> <label>`. That call writes a permanent override (`custom_name` in herdr's session state) that from then on always wins over the real cwd, even after a later `cd`. There is no supported way to clear it and go back to auto-tracking (upstream herdr#3252, closed `not_planned` -- only panes have a reset action, not workspaces).

Never call `workspace rename` as a trick to force a stale value to refresh (for example, working around herdr#3200's stuck outer-window-title copy by renaming a workspace to its own current label). That "no-op" rename still permanently pins the workspace. Confirmed live 2026-08-28: a plugin doing exactly this pinned a workspace to a stale creation-time name within seconds, because the 0.5s delay it used before reading the "current" label was shorter than the shell's real startup race.

Never pass an empty label either: `herdr workspace rename <id> ""` has no CLI guard and silently sets a permanently blank, equally unclearable name.

If a stale title/label needs correcting without renaming, rebuild the display value from a fresh `herdr api snapshot`'s pane `foreground_cwd`/`cwd` instead, and set it through a channel that isn't sticky (e.g. `herdr terminal title set`, not `workspace rename`).

## Safety and coordination rules

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current`, an explicit pane ID, or a unique agent name. Do not rely on another client's focused pane.
- Parse IDs from JSON responses. Do not derive them from sidebar order or examples.
- Do not close workspaces, tabs, panes, or sessions you did not create unless the user explicitly asked. `workspace close --group` closes the primary workspace AND its linked worktree workspaces; never add it merely to bypass `workspace_group_close_required`. That refusal (new in 0.9.0, #2874) is Herdr telling you the close would take more than you named, which is a finding, not an obstacle.
- Use `--trust-repository` only after the USER has verified the repository. It grants per-request Git trust; it is not a routine retry for a failed worktree command.
- Client and server versions can differ after an update. Check `herdr status` before relying on new server features. A missing method is not permission to stop or upgrade a server.
- **Read panes with `herdr-pane-read`, not a hand-picked `--lines`.** It sizes the request itself, strips the blank rows below the content, states positively what it showed of what, says exit 3 out loud when a pane is genuinely empty, and warns when a pane is scrolled and the chosen source follows that scroll. It takes a pane id, a live agent name, or `--current`. The raw `herdr pane read` / `agent read` are fine with a generous `--lines` (400 or more) and dangerous with a small one; see the floor rule above.
- Never close a pane, workspace, tab, or session on `agent_status: idle` alone. Confirm the actual expected output is present first -- a direct `herdr-pane-read`, not just the status field. `idle` can be reported early on a nested-TUI pane (see above); closing on a false idle kills whatever was still genuinely running, and that work is not recoverable, not merely delayed.
- **`workspace close --group` EXISTS on 0.9.1 but its own `--help` does not list it.** `herdr workspace close --help` prints `Usage: herdr workspace close <workspace_id>` and nothing else, so reading that help is how you conclude the flag was never shipped. Measured 2026-09-22 with three arms in one breath: a bare `close <id>` reached the server (exit 1, a server error), `close <id> --group` ALSO reached the server (exit 1, so it parsed), and `close <id> --close-group` was rejected at parse time with **exit 2 and the real usage line, `usage: herdr workspace close <workspace_id> [--group]`**. So the syntax error is a better reference than the help. The same trap as everything else here: `--help` omitting a flag and the flag not existing look identical, and only the rejected sibling separates them.
- `pane close` takes the pane ID as a bare positional argument (`herdr pane close <pane_id>`), and so do most other `pane` subcommands -- only `layout`, `current` and `split` accept `--pane`/`--current` (see the target-form table above; the earlier claim here that a `--pane` flag was the norm was measured false on 2026-09-20). `herdr pane close --pane <id>` is a syntax error (exit 2). `workspace close <workspace_id>` is the same shape and returns `{"result":{"type":"ok"}}` (verified 2026-09-06).
- Never run `herdr server stop` from an active session unless the user explicitly intends to stop the server and its pane processes.
- Never run bare `herdr server` either. The server is service-managed on every box in this estate: `systemctl --user {start,restart,status} herdr.service` on Linux/WSL, `brew services {start,restart} herdr` on macOS. A hand-started server inherits the launching shell's environment (which made every pane skip the dotfiles welcome banner on the Linux box, 2026-09-06) and dies with that session. A `herdr()` function in `.zshrc` refuses the bare form and prints the service command; on Linux it also starts the unit before an attach, because attach silently spawns its own server when none is running. Why and how: `docs/HERDR.md` in the dotfiles repo.
- `herdr status server --json` is the canonical "is a server running" probe: `.running` (bool) and `.restart_needed` (true when the binary on disk is newer than the running server). It works with no server up (`"status":"not_running"`) and never starts one.
- Config gotcha: a `tab_bar_right` `command` entry in `config.toml` runs on the SERVER host, under the server's environment, every `interval_seconds`. A path that exists only on one machine fails every tick on the other and floods `herdr-server.log` (12188 of 12641 lines on the Linux box before it was noticed). Use paths that are the same on every box and resolve the host inside the script.
- Never kill the main Herdr process. Use named test sessions for experiments that need an isolated server.
- CLI server errors are JSON on stderr with exit status 1. CLI syntax errors exit with status 2.
