# herdr — the left sidebar, colours, and what outside programs can change

herdr-verified: 0.9.3

Written 2026-10-16 in session dotfiles-main, from four research workers (herdr's
changelog and community, its API and plugins, every sidebar and colour option,
and Claude Code's titles) and checked against the v0.9.3 source
(`git clone --depth 1 --branch v0.9.3 https://github.com/herdrdev/herdr`) and the
installed binary. File:line references are into that source. What Gavin chose is
in `home/.config/herdr/config.toml`, each block with its reason; this doc holds the
facts behind the choices and the options not taken.

## What is set now (16 Oct)

- **Active pane border** gold `#ffd75f` (`ui.accent`); **inactive borders** a dim
  warm grey `#5c4a4a` (`theme.custom.overlay0`).
- **Agents section:** line 1 the state mark and the session's pane title in white;
  line 2 machine, workspace and tab in warm grey `#c0ac90`, not bold; no gap
  between entries (Q38 (v2): 1, Q40, Q41: 2, variation 5 of 6).
- **Spaces section:** the space name in white; the branch in light sand `#b0a084`
  (Q42: 1).
- **Selected row bar** `#33201f`, **navigate cursor** `#432a28`. Each is ONE setting
  shared by the spaces and agents sections (`active_row_bg`, `selection_bg`), so the
  two sections cannot have different bars.

## Facts that decided the choices

- **Agent names and the tab number are drawn in `overlay0`**, the same colour as
  inactive borders (`client/shell/agent_sidebar.rs:343`, `ui/sidebar.rs:266-270`).
  Making the borders dim made the names dim too, and on the terminal theme's grey
  `#555555` selected-row bar they nearly vanished. The fix is an explicit `fg` on
  those tokens, which leaves the borders alone.
- **`overlay0` is wide:** inactive borders and their titles, the sidebar headers,
  separators, secondary text, the unknown state, scrollbars, toasts. **`teal`**
  paints only the done state and **`active_row_bg`** only the selected rows, so
  those are the safe ones to change. `accent`, `panel_bg` and `overlay0` reach far.
- **`ui.accent` applies only while `theme.custom.accent` is unset** (`app/mod.rs:261-269`).
- **Token styles are `fg`, `bold` and `dim` only.** No italic, no underline
  (`config/sidebar.rs:101-104`, deny_unknown_fields). **No text size:** a terminal
  draws every character in one grid.
- **`row_gap` is whole lines.** 1 was too loose; there is no half line.
- **Rules** (0.9.0+, `hide` 0.9.1+): a token can be restyled or hidden when its OWN
  value `equals`, `contains`, `starts_with`, or is `gt`/`lt` a number. A rule cannot
  replace the text, and cannot test another token. Not allowed on `state_icon` or
  `git_status`.
- **`tab`** shows only when the space has more than one tab or the tab has a custom
  name. **`machine`** is empty while one machine is attached; with a second one,
  local rows say "Local" (a rule `equals = "Local", hide = true` drops it).
- **State symbols:** blocked `×` red, working `◐` yellow, done `✓` teal, idle `○`
  green, unknown `·` overlay0 (`client/shell.rs:178-237`). The working yellow is
  close to the gold accent.
- **The Mac/GPU readout** in the tab bar is `overlay1`, pure white, the brightest
  text on screen.

## "Claude Code" in the sidebar, and naming

- Claude Code's terminal title is, in order: the custom name (`--name`, `/rename`,
  a hook's `sessionTitle`), the AI-made title, the `--agent` type, then the literal
  "Claude Code". So **"Claude Code" lasts only until the first typed prompt**.
- herdr shows the title as-is (`terminal_title_stripped` drops one spinner mark,
  `terminal/title.rs:1-22`) and cannot swap words in it.
- **The fix taken (Q39 (v7): 1):** name the session at launch. `engage` already does
  (`<repo>-<role>[-<topic>]`, `engage/bin/engage` build_session_name).
  `makeitso` now does the same with role `makeitso` (makeitso L13, commit 279cb46).
  A bare `claude` in a shell and Claude on `codebox` still start unnamed; they show
  "Claude Code" only until the first prompt.
- **Not taken, but possible:** a herdr plugin on `pane.focused` that sets a token for
  every agent; or a Claude Code hook on SessionStart and UserPromptSubmit that reports
  `session_title` (present only for a custom name) or "Nameless" as a `$name` token,
  with the title hidden by a rule. `herdr agent rename` cannot do it: names must be
  lowercase `[a-z][a-z0-9_-]{0,31}` and unique.

## What an outside program can change

- **`herdr pane report-metadata <pane> --source <id>`:** `--display-agent` becomes the
  `agent` token, `--title` the `pane` token, `--state-label done="your turn"` the
  state word, `--token k=v` a `$k` token (32 keys, 80 characters, `--ttl-ms` to
  expire). Values live until cleared, expired or the pane closes; a server restart
  loses them (`persist/restore.rs:430`). Values reported with `--agent claude` are
  wiped when Claude exits.
- **`herdr workspace report-metadata`** feeds `$k` tokens in the spaces section.
- **Events:** newline-delimited JSON on `~/.config/herdr/herdr.sock`;
  `{"id":"s1","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.updated"}]}}`.
  Events arrive with underscores (`pane_updated`). `pane.updated` fires when the
  stripped title changes. Any extra byte or EOF from the client ends the
  subscription. A slow reader gets `events_lost`.
- **Plugins** (`herdr-plugin.toml`, `herdr plugin link`): `[[startup]]`, `[[actions]]`,
  `[[events]]`. Event hooks can take `pane.focused`, `pane.agent_detected` and
  `pane.agent_status_changed`, but NOT `pane.updated` (title changes; herdr issue
  #4912). A plugin cannot draw in the sidebar; it changes it through report-metadata.
  See [`HERDR_PLUGINS.md`](HERDR_PLUGINS.md).
- **A pane's own background:** a program in the pane can set its default background
  with OSC 11 (`printf '\e]11;#1a2a1a\a'`, reset `printf '\e]111\a'`). herdr keeps it
  per pane and paints it when it differs from the host's (`pane/terminal.rs:3518-3533`).
  Read in the code, not yet seen on screen (16 Oct).
- **A changed key command needs `herdr server reload-config`**; `prefix+r` reloads
  only the client.

## Ideas not built (16 Oct)

- Spoken alerts: a plugin hook on `pane.agent_status_changed` saying "NP-2 is waiting
  for you" through `speak-clipboard`. Public speech plugins exist (herdr-speak,
  herdr-announcer, herdr-tts), unread.
- A "waiting since 4:52 PM" token set by a Claude Code Stop hook, cleared on the next
  prompt; a context-left token from the status line.
- `agent.view.set` to show only blocked or done agents, for a shorter list to read.
- A tint per project or for `codebox` panes, through OSC 11 at launch.
- Hide the `master`/`main` branch in the spaces section with a rule, so a branch
  shows only when it is unusual.
- herdr 0.9.5 fixes Claude Code questions not showing as blocked in named sessions
  (#5192); herdr notices still say "claude needs attention" whatever the name (#4332).
