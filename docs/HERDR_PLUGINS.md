# herdr: Plugins (Group C)

**Audience: an AI coding agent, not a human.** This replaces reading
<https://herdr.dev/docs/plugins/>.

Verified against **herdr 0.7.5** on 2026-08-02 by authoring, linking, invoking
and unlinking a real plugin. OBSERVED = produced by a real run. DOC = upstream
claim not confirmed here.

Read [`HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md) sections 3 and 4 first --
the sandbox trap and the output-format map apply here too.

---

## 1. Security posture -- decide this before anything else

Upstream is explicit: _"A plugin is ordinary code that runs on your machine ...
with your environment, and can call the full herdr CLI"_, and herdr _"does not
review or sandbox what a plugin does."_

Three concrete escalation paths, all OBSERVED or structural:

1. `herdr plugin install <owner>/<repo>` **clones a GitHub repo and executes its
   `[[build]]` commands at install time**, before you have run anything.
2. `[[startup]]` commands run on **every herdr server start**, unattended,
   inheriting the server's environment. Under a launchd-managed Homebrew
   service that environment can include forwarded SSH agent sockets and any
   exported API tokens.
3. OBSERVED: a plugin action receives `HERDR_BIN_PATH` and `HERDR_SOCKET_PATH`
   and the full CLI works from inside it -- a plugin can enumerate, read and
   drive every agent on the machine.

**Rule for this environment: write your own plugins and register them with
`herdr plugin link`. Never `herdr plugin install`.** `link` points at a local
directory and skips `[[build]]` entirely, so no third-party code executes.

---

## 2. Anatomy

A plugin is a directory containing `herdr-plugin.toml` plus scripts or
binaries in any language.

Required manifest fields: `id`, `name`, `version`, `min_herdr_version`.
Optional: `description`, `platforms`.

Repeatable sections: `[[build]]`, `[[startup]]`, `[[actions]]`, `[[events]]`,
`[[panes]]`, `[[link_handlers]]`.

### Working manifest (OBSERVED to link and run cleanly on 0.7.5)

```toml
id = "demo.hello"
name = "Herdr Lab Hello"
version = "0.1.0"
min_herdr_version = "0.7.0"
description = "Throwaway plugin exercising actions, panes and link handlers"
platforms = ["macos", "linux"]

[[actions]]
id = "hello"
title = "Say hello"
contexts = ["workspace"]
command = ["bash", "hello.sh"]

[[panes]]
id = "clock"
title = "Lab clock"
placement = "overlay"
command = ["bash", "clock.sh"]

[[link_handlers]]
id = "github-issue"
title = "Inspect GitHub issue link"
pattern = "^https://github\\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+$"
action = "hello"
# TRIGGER IS ctrl+click -- ON macOS TOO. See "Link handlers" below before testing.

# [[events]]
# on = "worktree.created"
# command = ["bash", "on-worktree.sh"]

# --- NOT wired here, deliberately ---
# [[build]]
# command = ["npm", "ci"]          # runs on `install` ONLY; skipped by `link`
# [[startup]]
# command = ["bash", "startup.sh"] # runs on EVERY server start, unattended
```

`command` paths are relative to `HERDR_PLUGIN_ROOT`. Scripts must be `chmod +x`
or invoked through an explicit interpreter as above.

DOC: `worktree.created` is the only event name upstream documents. The full
event vocabulary is not published; enumerate empirically before relying on one.

---

## 3. Command cheat sheet

```bash
herdr plugin link <dir> [--enabled|--disabled]   # local; NO build, NO remote code
herdr plugin unlink <id>
herdr plugin install <owner>/<repo>[/<subdir>]   # AVOID: clones + runs [[build]]
herdr plugin uninstall <id-or-source>
herdr plugin list                                # PLAIN TEXT, not JSON
herdr plugin enable  <id>
herdr plugin disable <id>
herdr plugin config-dir <id>
herdr plugin action list   --plugin <id>
herdr plugin action invoke <plugin-id>.<action-id>
herdr plugin log list --plugin <id>              # where plugin stdout ACTUALLY goes
herdr plugin pane open  --plugin <id> --entrypoint <pane-id> [...]
herdr plugin pane focus <...>
herdr plugin pane close <...>
```

Action IDs are `<plugin.id>.<action.id>`, e.g. `demo.hello.hello`.

---

## 4. Where a plugin's output goes

OBSERVED: `plugin action invoke` does **not** print the script's stdout. It
returns JSON describing the action and its context. The actual stdout/stderr
lands in the plugin log:

```bash
herdr plugin action invoke demo.hello.hello >/dev/null
herdr plugin log list --plugin demo.hello \
  | jq -r '.result.logs[] | select(.action_id=="hello") | .stdout'
```

Log entries carry `status`, `exit_code`, `stdout`, `stderr`,
`started_unix_ms`, `finished_unix_ms`. This is the debugging surface -- reach
for it first when an action "does nothing".

---

## 5. THE CONTEXT TRAP (most important finding)

OBSERVED: a CLI-invoked action does **not** receive the calling pane's context.
It receives the **UI-focused pane** -- whatever the human is looking at.

Invoked from pane `wJ:p1`, the plugin saw:

```
HERDR_PANE_ID=wR:p1
HERDR_WORKSPACE_ID=wR
HERDR_PLUGIN_CONTEXT_JSON={"workspace_id":"wR","workspace_label":"Network_Plan",
  "focused_pane_id":"wR:p1","focused_pane_agent":"claude",
  "focused_pane_status":"blocked","invocation_source":"cli", ...}
```

`herdr plugin action invoke --help` offers **only** `--plugin`. There is no flag
to pin the context. So:

- A plugin action written to "operate on the current project" will operate on
  whatever workspace the user has focused, which may be a completely different
  repository.
- Scripted invocation is therefore **non-deterministic** with respect to target.
- If an action must act on a specific place, pass it explicitly through your own
  mechanism (config file, `--env` on a plugin pane, an argument baked into
  `command`) rather than trusting the injected context.

---

## 6. Injected environment (the whole plugin API)

OBSERVED, complete, for a CLI-invoked action:

```
HERDR_BIN_PATH=/opt/homebrew/opt/herdr/bin/herdr
HERDR_ENV=1
HERDR_PANE_ID=wR:p1
HERDR_PLUGIN_ACTION_ID=envdump
HERDR_PLUGIN_CONFIG_DIR=~/.config/herdr/plugins/config/demo.hello
HERDR_PLUGIN_CONTEXT_JSON={...}
HERDR_PLUGIN_ID=demo.hello
HERDR_PLUGIN_ROOT=<the linked directory>
HERDR_PLUGIN_STATE_DIR=~/.local/state/herdr/plugins/demo.hello
HERDR_SOCKET_PATH=~/.config/herdr/herdr.sock
HERDR_TAB_ID=wR:t1
HERDR_WORKSPACE_ID=wR
```

Context-dependent extras (DOC, plus OBSERVED where noted):
`HERDR_PLUGIN_EVENT` (`"startup"` for startup hooks) and
`HERDR_PLUGIN_EVENT_JSON` for event hooks;
`HERDR_PLUGIN_ENTRYPOINT_ID` for pane commands (OBSERVED);
`HERDR_PLUGIN_CLICKED_URL` and `HERDR_PLUGIN_LINK_HANDLER_ID` for link handlers.

### Link handlers: the trigger is `ctrl+click`, on macOS too

Recorded 2026-08-03 after a failed test wasted a round trip. The modifier is
**Control on every platform, including macOS** -- upstream's reason is that
captured terminal mouse reports do not expose Command/Super separately from a
plain click, so herdr cannot tell a `cmd+click` from an ordinary one.

`cmd+click` therefore does NOT reach the plugin. On macOS it is worse than
merely inert: iTerm2 binds `cmd+click` to "open URL", so the browser opens and
the test _looks_ like herdr declining to intercept when herdr never saw the
event at all. A negative result from `cmd+click` says nothing about the plugin.

Verify a handler fired by its side-effects, not by the browser staying shut:

```bash
herdr plugin log list --limit 1     # a new entry, action = the handler's `action`
```

The action additionally receives `invocation_source = "link_click"`,
`clicked_url` and `link_handler_id` inside `HERDR_PLUGIN_CONTEXT_JSON`; shell
plugins can read `HERDR_PLUGIN_CLICKED_URL` / `HERDR_PLUGIN_LINK_HANDLER_ID`
directly. Absence of `clicked_url` in a log entry means the action was invoked
some other way. Handlers are tested in manifest order within a plugin, and
`pattern` is a Rust regex matched against the whole URL -- the anchored example
above will not match a URL with a trailing `)` or `.` picked up from prose.

Note `HERDR_BIN_PATH` is the Cellar path, not the `/opt/homebrew/bin` symlink.
Use the variable, never a hardcoded path.

Self-documenting probe worth keeping in any new plugin:

```bash
env | grep '^HERDR_' | sort
```

---

## 7. Plugin panes

```bash
herdr plugin pane open --plugin <id> --entrypoint <pane-id> \
  --placement <overlay|split|tab|zoomed> \
  [--workspace <id>] [--target-pane <pane>] [--direction right|down] \
  [--cwd <path>] [--env KEY=VALUE] [--focus]
```

OBSERVED placement rules -- these are enforced and the errors are exact:

| Placement          | Requirement                                                                                                          |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `overlay`, `popup` | target the **active pane**; passing `--workspace` fails with `overlay and popup plugin panes target the active pane` |
| `split`, `zoomed`  | require `--target-pane`; else `split and zoomed plugin panes target an existing pane; use target_pane_id`            |
| `tab`              | workspace-level                                                                                                      |

`popup` is a **manifest-only** value; the CLI `--placement` accepts only
`overlay`, `split`, `tab`, `zoomed`.

**OBSERVED HAZARD: `plugin pane open` takes focus even without `--focus`.** The
response reported `"focused": true` and global focus moved off the user's pane
in another workspace. There is no `--no-focus` flag, unlike `pane split`.
Capture focus before opening and restore it after:

```bash
BEFORE=$(herdr pane list | jq -r '.result.panes[]|select(.focused==true)|.pane_id')
herdr plugin pane open --plugin demo.hello --entrypoint clock \
  --placement split --target-pane <p> --direction down
herdr pane focus "$BEFORE"
```

Because `overlay` follows the _active_ pane, opening one while a human is
working elsewhere will cover **their** screen. Prefer `split --target-pane` for
anything scripted.

Success response is `.result.plugin_pane.pane` -- **not** `.result.pane`.

---

## 8. enable / disable semantics

OBSERVED:

- `herdr plugin disable <id>` flips the flag in `plugin list` (`enabled` ->
  `disabled`).
- `herdr plugin action list --plugin <id>` **still lists all actions while
  disabled** -- it is a static manifest read, not a liveness check.
- `herdr plugin action invoke` on a disabled plugin correctly refuses:
  `{"error":{"code":"plugin_disabled","message":"plugin demo.hello is disabled"}}`
  with exit 1.

So the off switch is real, but do not use `action list` to test whether a plugin
is active. Use `plugin list`.

---

## 9. `[[build]]` and `[[startup]]` -- why neither can be demonstrated safely

- `[[build]]` runs **only** on `herdr plugin install`. A `link`ed plugin never
  fires it. Since `install` is prohibited here, `[[build]]` is unreachable by
  design -- which is the point: linking is the safe path precisely because it
  skips arbitrary build execution.
- `[[startup]]` fires **only on herdr server start**. Triggering it requires
  restarting the server, which kills every live agent pane. With other sessions
  running, that is unacceptable. Test `[[startup]]` in an isolated named test
  session (`herdr --session <name>`) or not at all.

If you ever do wire `[[startup]]`, remember it becomes permanent unattended code
on every boot. `herdr plugin unlink <id>` is the removal.

---

## 10. Full lifecycle recipe

```bash
mkdir -p /tmp/lab/myplugin && cd /tmp/lab/myplugin
# write herdr-plugin.toml + scripts; chmod +x scripts
herdr plugin link /tmp/lab/myplugin
herdr plugin list                                   # confirm enabled + local: path
herdr plugin action list --plugin my.plugin
herdr plugin action invoke my.plugin.myaction >/dev/null
herdr plugin log list --plugin my.plugin | jq -r '.result.logs[-1].stdout'
# ... iterate: edit scripts, re-invoke; no re-link needed for script edits
herdr plugin unlink my.plugin                        # ALWAYS tear down
herdr plugin list
```

Manifest changes need a re-`link`; script body changes do not.

---

## 11. Gotcha summary

1. `plugin list` is plain text; most other plugin commands are JSON.
2. Action stdout goes to `plugin log list`, not the terminal.
3. CLI-invoked actions get the **focused** pane's context, not the caller's,
   and it cannot be pinned.
4. `plugin pane open` steals focus; no `--no-focus` exists.
5. `overlay`/`popup` cannot be pinned to a workspace; `split`/`zoomed` require
   `--target-pane`.
6. `popup` is manifest-only, not a CLI placement.
7. `action list` ignores enabled state; `invoke` does not.
8. Response key is `.result.plugin_pane.pane`, not `.result.pane`.
9. `install` executes third-party build commands; `link` does not.

Related: [`HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md),
[`HERDR_AGENT_AUTOMATION.md`](HERDR_AGENT_AUTOMATION.md), [`HERDR.md`](HERDR.md).
