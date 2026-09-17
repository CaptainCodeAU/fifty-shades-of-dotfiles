# herdr: Agent Skill (Group A)

**Audience: an AI coding agent, not a human.** Read this before issuing any
`herdr` command. It replaces reading https://herdr.dev/docs/agent-skill/.

herdr-verified: 0.8.2

Re-verified against **herdr 0.8.2** (Homebrew, macOS arm64) on 2026-09-17;
originally written against 0.7.5 on 2026-08-02 by executing every command
listed. Statements marked OBSERVED were produced by a real run; statements
marked DOC come from upstream docs and were not independently confirmed.

The `herdr-verified:` line above is machine-read by `herdr-skill-drift-check`,
which compares it to the installed binary and reports every doc that has fallen
behind. Six hand-typed version mentions used to do that job and all six went
stale without anyone noticing. Move the line only when the doc has actually
been re-checked -- a stamp is a claim, not decoration.

---

## 1. What this is

The agent skill is a single markdown instruction file. It contains no
executable code. It teaches you to drive the `herdr` CLI from inside a
herdr-managed pane so you can give yourself a side terminal: split a pane, run
a command there, read its output, and block until something appears.

### Where it lives (2026-09-17)

The file is **ours**: upstream's skill with a lot of locally measured findings
written into it. It lives in this repo at
`home/.claude/skills/herdr/SKILL.md`, and two symlinks point at it:

| Path | Read by |
|---|---|
| `~/.claude/skills/herdr/SKILL.md` | Claude Code (stowed) |
| `~/.agents/skills/herdr/SKILL.md` | Codex (skill root `r0`, discovered by convention) |

Codex finds `~/.agents/skills` on its own -- no config entry, nothing to grep
for. Before 2026-09-17 that copy was a separate file and the two had already
drifted apart by two behaviours. `install.sh` now creates both links.

### Getting upstream's copy (the old fetch recipe is retired)

**herdr 0.8.0 added `herdr --skill`**, which prints the skill bundled inside the
running binary. That is the merge base: offline, version-exact, no network, no
`npx skills add` pulling an unpinned `master`, no blob sha to chase. The old
`gh api ... | base64 -d` recipe that used to be here is gone because this
replaces it entirely.

```bash
herdr --skill > /tmp/upstream-new.md
```

### The merge runbook

Two files beside the skill hold the base:

```
home/.claude/skills/herdr/UPSTREAM.md         verbatim `herdr --skill` at the version last merged from
home/.claude/skills/herdr/UPSTREAM.version    the tag that capture came from
```

Our own edits are always recoverable as `diff UPSTREAM.md SKILL.md`. On a bump:

1. `herdr-skill-drift-check` reports `skill-drift ACTION` (it compares the live
   `herdr --skill` to the stored `UPSTREAM.md`).
2. Capture the new one, and diff it against the **stored** snapshot. That shows
   what herdr changed, which is the only question -- a diff against SKILL.md
   just shows everything we rewrote.
3. Merge those changes into SKILL.md in our own voice, beside the local findings.
4. Replace `UPSTREAM.md` and `UPSTREAM.version`, and commit all of it together.

Do not verify a merge by line count. After the 0.8.2 merge a line-level diff
still reported five upstream lines "missing", because those sentences were
rewritten rather than dropped. Verify by checking the FACTS are present.

0.8.2 refreshed the bundled skill wholesale to match the current CLI (#2847),
and that merge recovered two behaviours ours had lost: `agent start` keeps the
agent NAME usable after an `agent_not_ready`, and `agent prompt` refuses an
agent sitting at an approval dialog with `agent_blocked`. The second is a
safety rule. That is what the base snapshot exists to catch.

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

RE-CHECKED 0.8.2: every row above still holds, `agent explain` included.

A caution about checking, not about herdr. An earlier version of this line
claimed `agent explain` was missing from `herdr agent`. It is not: both `herdr
agent` and `herdr agent --help` list it, and the bare form prints two usage
lines for it. The claim came from piping that listing through `head -8`, which
cut the output two lines above the answer. **A truncated listing read as an
absence** -- the same failure as trusting a zero, wearing different clothes.
Do not conclude a command is gone from a listing you did not see all of.

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

**THE 0.7.5 TRAP NO LONGER REPRODUCES. Re-measured on 0.8.2, 2026-09-17**, one
pane running `seq 1 300`, every read taken at the same moment:

| Invocation | 0.7.5 (2026-08-02) | 0.8.2 (2026-09-17) |
|---|---|---|
| `recent-unwrapped --lines 400` | 3209 | 3318 |
| `recent-unwrapped` (no `--lines`) | 2666 | 585 |
| `recent-unwrapped --lines 50` | not measured | 465 |
| **`recent-unwrapped --lines 15`** | **0** | **325** |
| `recent-unwrapped --lines 5` | not measured | 285 |
| `visible --lines 15` | works | 326 |
| `visible --lines 400` | not measured | 422 |

A small `--lines` now returns a **truncated tail**, degrading smoothly, instead
of nothing. The old warning -- that too small a value returns NOTHING and looks
exactly like "no output" -- is kept above only so nobody re-derives it from an
old transcript. It was true; it stopped being true.

Two consequences of the new numbers:

- `--lines 400` is still the right default, but now because it returns MORE, not
  because smaller values break.
- The old advice to prefer `visible` over `recent-unwrapped` is withdrawn.
  At `--lines 400`, `recent-unwrapped` returned 3318 bytes against `visible`'s
  422 -- eight times more. Upstream's own advice (prefer `recent-unwrapped` for
  logs and transcripts) is the correct one again.

METHOD, because the first attempt at this measurement was void: a pane read
immediately after `workspace create` returned 0 bytes from EVERY source,
including ones known to work. All-arms-identical is not a finding, it is a
trial that did not happen -- the shell had not finished starting. The numbers
above come from a second run with an 18-second settle, where the sources
disagree with each other, which is what a real measurement looks like.

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
