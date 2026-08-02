# herdr: Agent Skill (Group A)

**Audience: an AI coding agent, not a human.** Read this before issuing any
`herdr` command. It replaces reading https://herdr.dev/docs/agent-skill/.

Verified against **herdr 0.7.5** (Homebrew, macOS arm64) on 2026-08-02 by
executing every command listed. Statements marked OBSERVED were produced by a
real run; statements marked DOC come from upstream docs and were not
independently confirmed.

---

## 1. What this is

The agent skill is a single markdown instruction file. It contains no
executable code. It teaches you to drive the `herdr` CLI from inside a
herdr-managed pane so you can give yourself a side terminal: split a pane, run
a command there, read its output, and block until something appears.

Installed at `~/.claude/skills/herdr/SKILL.md` (user level, all projects).

**Install without npx and without tracking `master`:**

```bash
gh api repos/herdrdev/herdr/contents/skills/herdr/SKILL.md --jq '.content' \
  | base64 -d > ~/.claude/skills/herdr/SKILL.md
git hash-object ~/.claude/skills/herdr/SKILL.md   # compare to the blob sha from the API
```

OBSERVED: blob sha `fafea549c0c46b87bac6c7ae4ad22ef7ac635a5e` at tag v0.7.5,
10140 bytes. Verifying the sha is worthwhile; it is a cheap integrity check.

The upstream-documented `npx skills add herdrdev/herdr --skill herdr -g` pulls
from `master` unpinned. Do not use it in this environment.

---

## 2. Hard precondition

```bash
test "${HERDR_ENV:-}" = 1
```

If this fails you are not inside herdr. Say so and stop. Do not attempt to
control the focused herdr session from outside.

OBSERVED: inside a pane you also get `HERDR_PANE_ID`, `HERDR_TAB_ID`,
`HERDR_WORKSPACE_ID`, `HERDR_SOCKET_PATH`. Example: `wJ:p1`, `wJ:t1`, `wJ`.

---

## 3. THE SANDBOX TRAP (read this first)

OBSERVED: with Claude Code's Seatbelt sandbox enabled, **every** herdr command
that touches the socket fails:

```
Error: Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }
```

This is not a herdr fault and not a broken install. The socket lives at
`~/.config/herdr/herdr.sock` and the sandbox denies it.

Two fixes:

1. Add the socket to `allowWrite` in `.claude/settings.local.json`:
   ```json
   "allowWrite": ["~/.claude/MEMORY", "~/.config/herdr/herdr.sock"]
   ```
   OBSERVED: sandbox config is read at **session start**. Editing it mid-session
   does NOT take effect. Verify at the next session, not immediately.
2. Per-call `dangerouslyDisableSandbox: true` on the Bash tool. Works
   immediately but lifts the whole sandbox for that call.

Do NOT widen the grant to the whole `~/.config/herdr` directory without
thinking: on a stow-managed dotfiles setup `~/.config/herdr/config.toml` is a
**symlink into the tracked repo**, so a stray write lands in version control.

---

## 4. Output format map (the single biggest time sink)

herdr is NOT uniformly JSON. OBSERVED, per command:

| Command | Output |
|---|---|
| `pane split` | JSON -> `.result.pane.pane_id` |
| `pane list`, `agent list`, `workspace list`, `tab list` | JSON |
| `pane wait-output` | JSON, with an embedded `.result.read.text` |
| `agent start`, `agent get`, `agent wait` | JSON -> `.result.agent` |
| `agent send-keys` | JSON `{"result":{"type":"ok"}}` |
| `plugin action list`, `plugin action invoke`, `plugin log list` | JSON |
| `plugin pane open` | JSON -> `.result.plugin_pane.pane` (NOT `.result.pane`) |
| **`pane read`** | **PLAIN TEXT** -- piping to `jq` yields nothing |
| **`agent read`** | **PLAIN TEXT** |
| **`agent explain`** | **PLAIN TEXT** by default; add `--json` |
| **`plugin list`** | **PLAIN TEXT** |
| **`pane run`** | **EMPTY** on success, exit 0 |

If a command returns nothing through `jq`, try it raw before assuming failure.

**Exit codes** (OBSERVED, measured without a pipe):

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | server error, JSON error object emitted |
| 2 | CLI syntax error |

Measure exit codes without a pipe. `herdr ... | head` reports `head`'s status.

---

## 5. Command cheat sheet

```bash
# --- orientation -----------------------------------------------------------
herdr --help                                   # resolved config + log paths
herdr status server                            # running? version? protocol?
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list
herdr agent list

# --- make yourself a side pane --------------------------------------------
herdr pane split --current --direction right --cwd "$PWD" --no-focus
#   -> read .result.pane.pane_id
herdr pane rename <pane> "demo-runner"
herdr pane layout --pane "$HERDR_PANE_ID"      # decide right vs down
herdr pane neighbor / edges / resize / zoom / swap / move

# --- run work there --------------------------------------------------------
herdr pane run <pane> 'echo hi; ls -1'         # returns NOTHING, exit 0
herdr pane send-text <pane> "staged, no Enter"
herdr pane send-keys <pane> ctrl+c
herdr pane wait-output <pane> --match "READY" --timeout 60000
herdr pane wait-output <pane> --regex '^done' --timeout 60000
herdr pane read <pane> --source visible --lines 400

# --- clean up (ONLY panes you created) -------------------------------------
herdr pane close <pane>
```

**NEVER** run `herdr server stop`, `herdr server reload-config` casually, or
`brew services stop herdr` while other agent sessions are live. Never run bare
`herdr` for discovery: it launches or attaches the TUI. Never probe a mutating
subcommand by omitting arguments; `herdr workspace create` executes on defaults.

---

## 6. `pane read` sources, and the `--lines` trap

Sources: `visible`, `recent`, `recent-unwrapped`, `detection`.

OBSERVED, same pane, same moment:

| Invocation | Bytes returned |
|---|---|
| `--source recent-unwrapped --lines 400` | 3209 |
| `--source recent-unwrapped` (no `--lines`) | 2666 |
| **`--source recent-unwrapped --lines 15`** | **0** |
| `--source visible --lines 15` | works |

**A `--lines` value that is too small returns NOTHING, not a truncated tail.**
This looks exactly like "the command produced no output" and will send you
debugging the wrong thing. Default to `--lines 400` and filter locally.

DOC says prefer `recent-unwrapped` for transcripts. OBSERVED: on a shell with a
heavy prompt, `recent` and `recent-unwrapped` frequently return empty at small
line counts while `visible` and `detection` work. Prefer `visible` first, then
`detection`; treat `recent-unwrapped` as the thing to try when `visible` is
truncated.

Use `--format ansi` only when colours are evidence.

---

## 7. Focus discipline

`--no-focus` on `pane split` is the whole point of the feature: the work
happens beside the user, not on top of them.

OBSERVED: `herdr pane split --current --direction right --cwd <dir> --no-focus`
returned `focused: false` and global focus stayed on the user's own pane in a
different workspace. Confirmed with:

```bash
herdr pane list | jq -r '.result.panes[] | select(.focused==true) | .pane_id'
```

Run that check after any layout change. See `HERDR_PLUGINS.md` section 6 for a
command that steals focus even without asking.

Reading never steals focus. `herdr pane read` / `agent read` do NOT mark a tab
as seen; `pane focus` / `agent focus` DO, and that changes `done` vs `idle`
semantics. Prefer reads.

---

## 8. Working recipe: wait for a slow server

OBSERVED end to end, 7 seconds wall clock for a server that sleeps ~6s:

```bash
P=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus \
      | jq -r '.result.pane.pane_id')
herdr pane run "$P" 'bash ./start-dev-server.sh'
herdr pane wait-output "$P" --match "READY" --timeout 60000
herdr pane read "$P" --source visible --lines 400 | tail -20
herdr pane close "$P"
```

`pane wait-output` searches the selected snapshot immediately, so output that
already exists will match straight away. Omitting `--timeout` waits forever --
always pass one.

---

## 9. Rules

- Do not close workspaces, tabs, panes or sessions you did not create.
- Never kill the main herdr process. Use a named test session for anything
  that needs an isolated server.
- Parse IDs out of JSON responses. Never guess them, never derive them from
  sidebar order.
- Prefer `--current` or an explicit pane ID. Omitting a target may hit the
  UI-focused pane, which can belong to the user or another client.
- Closed tab and pane IDs are never reused. After `pane move`, continue with
  `.result.move_result.pane.pane_id`.

Related: [`HERDR_AGENT_AUTOMATION.md`](HERDR_AGENT_AUTOMATION.md),
[`HERDR_PLUGINS.md`](HERDR_PLUGINS.md), [`HERDR.md`](HERDR.md).
