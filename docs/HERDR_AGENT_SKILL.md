# herdr: Agent Skill (Group A)

**Audience: an AI coding agent, not a human.** Read this before issuing any
`herdr` command. It replaces reading https://herdr.dev/docs/agent-skill/.

herdr-verified: 0.9.1

Re-verified against **herdr 0.9.1** (Homebrew, macOS arm64) on 2026-09-22 (F9b),
against a RUNNING 0.9.1 server rather than the binary alone; against 0.8.2 on
2026-09-17; originally written against 0.7.5 on 2026-08-02 by executing every
command listed. Statements marked OBSERVED were produced by a real run;
statements marked DOC come from upstream docs and were not independently
confirmed.

**WHAT THE 0.9.1 RE-VERIFY DID, so the stamp is a claim of a known size.** It
re-probed every claim a release since 0.8.2 could have changed, the same scope
the 0.7.5 to 0.8.2 stamp was earned on. RE-RUN and unchanged: the whole
documented command surface, 47 of 47 subcommands across all four HERDR docs,
checked against 0.9.1's own group listings with a control that separates a real
subcommand from an invented one (an invented one prints the group listing, a
real one prints the top-level help); the sandbox socket denial, hit on every
`herdr` call in that session; the output-format map, with `pane read` still
printing text and `plugin list --json` still printing JSON; the `agent get` /
`agent list` result-key split; the id fields returned by `workspace create`,
`tab create` and `pane split`; `agent_pane_busy` on a pane still running its
shell startup; `status server --json`; and server errors as JSON on stderr at
exit 1. RE-MEASURED AND CHANGED: the pane-read blank-region floor is gone
(#3444), the `agent prompt` submit trap did not reproduce in 21 attempts, an
omitted `pane split` target now means the calling pane (#4123), and
`workspace_group_close_required` was captured live. NOT RE-RUN: nothing here
requires a server restart, and no claim in this document was left unchecked
because of one. Checked and found absent rather than assumed: this document
makes no claim about `--no-session`, `experimental.kitty_graphics` or event
replay, the three things 0.9.0 removed or renamed.

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

| Path                              | Read by                                           |
| --------------------------------- | ------------------------------------------------- |
| `~/.claude/skills/herdr/SKILL.md` | Claude Code (stowed)                              |
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

| Command                                                         | Output                                                  |
| --------------------------------------------------------------- | ------------------------------------------------------- |
| `pane split`                                                    | JSON -> `.result.pane.pane_id`                          |
| `pane list`, `agent list`, `workspace list`, `tab list`         | JSON                                                    |
| `pane wait-output`                                              | JSON, with an embedded `.result.read.text`              |
| `agent start`, `agent get`, `agent wait`                        | JSON -> `.result.agent`                                 |
| `agent send-keys`                                               | JSON `{"result":{"type":"ok"}}`                         |
| `plugin action list`, `plugin action invoke`, `plugin log list` | JSON                                                    |
| `plugin pane open`                                              | JSON -> `.result.plugin_pane.pane` (NOT `.result.pane`) |
| **`pane read`**                                                 | **PLAIN TEXT** -- piping to `jq` yields nothing         |
| **`agent read`**                                                | **PLAIN TEXT**                                          |
| **`agent explain`**                                             | **PLAIN TEXT** by default; add `--json`                 |
| **`plugin list`**                                               | **PLAIN TEXT**                                          |
| **`pane run`**                                                  | **EMPTY** on success, exit 0                            |

If a command returns nothing through `jq`, try it raw before assuming failure.

RE-CHECKED 0.8.2: every row above still holds, `agent explain` included.

A caution about checking, not about herdr. An earlier version of this line
claimed `agent explain` was missing from `herdr agent`. It is not: both `herdr
agent` and `herdr agent --help` list it, and the bare form prints two usage
lines for it. The claim came from piping that listing through `head -8`, which
cut the output two lines above the answer. **A truncated listing read as an
absence** -- the same failure as trusting a zero, wearing different clothes.
Do not conclude a command is gone from a listing you did not see all of.

### `<group> <sub> --help` CANNOT tell you whether a subcommand exists

OBSERVED 2026-09-22 on 0.9.1, and it invalidated a whole probe before a control
caught it. herdr answers an UNKNOWN subcommand by printing the group's listing,
exit 0. It answers a REAL one by printing the top-level help. Neither says "no
such subcommand", so the two outcomes are easy to read as the same thing, and a
probe built on `--help` reports every invented name as present:

```bash
herdr agent no-such-subcommand --help    # prints the agent group listing
herdr server no-such-thing --help        # prints "herdr server commands:"
herdr status no-such-thing --help        # prints "herdr status commands:"
```

**To test existence, check membership of the group's own listing instead**, and
run both arms so you can see they differ:

```bash
herdr agent > /tmp/agent.txt
grep -qE '^ *herdr agent list\b'                /tmp/agent.txt   # must HIT
grep -qE '^ *herdr agent no-such-subcommand\b'  /tmp/agent.txt   # must MISS
```

That probe verified all 47 subcommands these four documents claim, against 0.9.1.
Two caveats it also surfaced, both measured: `herdr status` prints status rather
than a listing and `herdr server` bare is the one form the skill forbids, so
those two groups need the `--help` form with the invented-sibling control instead
of a listing grep. This is the `workspace close --group` trap one level up: there,
a help text omitting a flag and the flag not existing looked identical; here, a
help text APPEARING and the subcommand not existing look identical.

**Exit codes** (OBSERVED, measured without a pipe):

| Code | Meaning                                 |
| ---- | --------------------------------------- |
| 0    | success                                 |
| 1    | server error, JSON error object emitted |
| 2    | CLI syntax error                        |

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

| Invocation                        | 0.7.5 (2026-08-02) | 0.8.2 (2026-09-17) |
| --------------------------------- | ------------------ | ------------------ |
| `recent-unwrapped --lines 400`    | 3209               | 3318               |
| `recent-unwrapped` (no `--lines`) | 2666               | 585                |
| `recent-unwrapped --lines 50`     | not measured       | 465                |
| **`recent-unwrapped --lines 15`** | **0**              | **325**            |
| `recent-unwrapped --lines 5`      | not measured       | 285                |
| `visible --lines 15`              | works              | 326                |
| `visible --lines 400`             | not measured       | 422                |

A small `--lines` now returns a **truncated tail**, degrading smoothly, instead
of nothing. The old warning -- that too small a value returns NOTHING and looks
exactly like "no output" -- is kept above only so nobody re-derives it from an
old transcript. It was true; it stopped being true.

**THAT RETRACTION IS WITHDRAWN. Re-measured 2026-09-20 on 0.8.2: the zero still
happens, and the 2026-09-17 trial could not have seen it.** That trial used a
pane running `seq 1 300`, which fills the screen and the scrollback. The real
variable is whether the content REACHES THE BOTTOM of the grid. `--lines N`
counts N rows up from the bottom of the terminal grid rather than from the
bottom of the content; blank rows below the content fill your N and are trimmed
before you see them. A pane whose program fills only the top returns zero bytes
for every N below `viewport_rows - content_rows + 1`. `seq 1 300` leaves no
blank rows, so its floor is 1 and nothing can go wrong.

Three panes, each with a failing arm and a passing arm in the same command:

| pane                  | viewport | content rows | floor | N=floor-1 | N=floor   |
| --------------------- | -------- | ------------ | ----- | --------- | --------- |
| idle Claude, 0 tokens | 90       | 24           | 67    | 0 bytes   | 209 bytes |
| busy Claude           | 90       | 89           | 2     | 0 bytes   | 52 bytes  |
| plain shell, no agent | 92       | 57           | 36    | 0 bytes   | 425 bytes |

Not the source, either: at `--lines 200` the idle pane returned the same 3070
bytes from all four of `visible`, `recent`, `recent-unwrapped` and `detection`.

The lesson is the one this file already teaches about void trials, pointed at a
RETRACTION rather than a finding. A fixture that fills the screen cannot
disprove a bug about screens that are not filled, and "it no longer reproduces"
was written from a single pane shape. Use
[`herdr-pane-read`](../home/.local/bin/herdr-pane-read), which sizes the request
itself, strips the blank region, and states positively what it showed of what.

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
  UI-focused pane, which can belong to the user or another client. **But only
  `pane layout`, `pane current` and `pane split` accept `--current`/`--pane` at
  all.** `pane read`, `run`, `send-keys`, `wait-output`, `close` and `move` take
  the id as a bare positional argument and reject both flags with
  `unknown option` and exit 2 -- one short line, no usage block, so it reads
  like a server fault rather than a syntax error. The calling pane is
  `herdr pane read "$HERDR_PANE_ID"`, never `herdr pane read --current`.
  Measured 2026-09-20 against herdr 0.8.2 from each subcommand's `--help`,
  after a session burned two round trips on the flag forms.
- Closed tab and pane IDs are never reused. After `pane move`, continue with
  `.result.move_result.pane.pane_id`.

Related: [`HERDR_AGENT_AUTOMATION.md`](HERDR_AGENT_AUTOMATION.md),
[`HERDR_PLUGINS.md`](HERDR_PLUGINS.md), [`HERDR.md`](HERDR.md).
