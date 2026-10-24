# herdr — the left sidebar, colours, and what outside programs can change

herdr-verified: 0.9.5

**Re-checked 2026-10-18 against the installed 0.9.5** (client and server both 0.9.5).
Ran: `herdr config check` on the live config (`config: ok`) and on scratch copies with
planted faults (italic, underline, a named colour, a `text` rule, a rule naming another
token, a rule on `state_icon` and on `git_status` all refused; `align` reported as an
unknown key and ignored; rules on `machine`, `branch`, `tab` and a `$k` token accepted
with `equals`, `contains`, `starts_with`, `gt`, `lt`), `herdr --default-config`,
`herdr api schema --json`, the `--help` of report-metadata, rename, machine and plugin,
`herdr agent list`, `herdr machine list`, and strings in the 0.9.5 binary. Did NOT run:
anything on screen (colours, symbols, contrast, what `machine` shows with one machine),
the v0.9.5 source (file:line references below are still into v0.9.3), a plugin hook on
`pane.updated`, or a live report-metadata. A coverage audit of every 0.9.2 to 0.9.5
release-note bullet followed the same day, and the sidebar-related gaps it found are
added below, each marked release notes or measured.

Written 2026-10-16 in session dotfiles-main, from four research workers (herdr's
changelog and community, its API and plugins, every sidebar and colour option,
and Claude Code's titles) and checked against the v0.9.3 source
(`git clone --depth 1 --branch v0.9.3 https://github.com/herdrdev/herdr`) and the
installed binary. File:line references are into that source. What Gavin chose is
in `home/.config/herdr/config.toml`, each block with its reason; this doc holds the
facts behind the choices and the options not taken.

## What is set now (16 Oct, updated 19 Oct)

- **A stuck session is marked "⚠ stuck" in bold red** after its project name (Gavin, dotfiles-main
  Q91: 1, 20 Oct 2026, after e-b13b sat behind Claude Code's "Background work is running" exit box
  looking like any other row). `home/.local/bin/herdr-stuck-watch`, run every 15 s by launchd
  (`com.captaincodeau.herdr-stuck-watch`, installed by `install.sh`), reads herdr's pane list:
  every local Claude session's status line reports its cache timer on every run, idle or not,
  each report living 2 minutes, and a dialog that holds Claude Code stops the status line. So a
  Claude session that has shown a timer and now has none is marked, and cleared when the timer
  comes back. Never marked: a session that never had a timer (it is remembered only once it does),
  a pane herdr already shows as blocked, other agent kinds, and agents on another machine. A
  session already stuck when the watcher first runs is not judged, because it was never seen with
  a timer. `herdr-stuck-watch --selftest` (11 arms; four mutants of its key lines each caught).
- **Agents section since 19 Oct, 11:55 PM** (Gavin, dotfiles-main, Q88: 1). This supersedes the
  next bullet where they differ. Line 1: the state mark, the project name, a remote machine, the
  cache timer; no tab. The project name is **gold `#ffd75f` on the focused agent's row and white
  on the rest**: herdr cannot style a row by selection, so `herdr-plugins/state-words/focus-name.sh`
  (on `pane.focused` and both agent events) sets `$name_on` on the one focused agent pane and
  `$name_off` on the others, in place of herdr's `workspace` token. An agent on another machine is
  not in this server's pane list, so its row shows no project name. Line 2: the session name, a
  tad dimmer (`#8c8069` became `#736955`), then the state word, with no shape before it
  (`💭`, `your turn`, `💤`, `needs you`; `your turn` came back at 12:48 AM after 🫵 and 👉; `💭` stands where `thinking` was since 12:28 AM, `💤` where `resting` was since 12:35 AM; from 12:20 to 12:48 AM 🫵 and then 👉 stood where `your turn`
  is, Gavin's ask). The seen `your turn` ends in a zero-width
  space (U+200B; herdr keeps it, read back 19 Oct) so a rule can colour it alone, as the square
  corner did before. The cache timer reads `— 42` (since 20 Oct, 12:15 AM: an em-dash in place
  of the clock, no unit, every band bold; it read `◷ 42 m` from 11:55 PM) and has six bands by the
  minutes shown:
  50 or more green `#5fd75f`, 40s mint `#9ef0c8`, 30s aqua `#3fe0e8`, 20s orchid `#da70d6`, 10s
  tangerine `#ff9a3c`, under 10 crimson `#e8264a` in bold. Gavin asked for a blink under 10:
  `herdr config check` refuses `blink = true` exactly as it refuses an unknown key, so it is bold
  instead. engage's own words on its worker panes (`waiting on e-conductor`) are engage's; since
  20 Oct, 12:52 AM a rule here colours that word grey `#6e7a86`, and the unseen `your turn` takes
  the idle green `#00bb00` it had (Gavin).
- **Active pane border** gold `#ffd75f` (`ui.accent`); **inactive borders** a dim
  warm grey `#5c4a4a` (`theme.custom.overlay0`).
- **Agents section, two lines a row since 19 Oct** (Gavin: "two lines acceptable"):
  line 1 the state mark, the workspace in bold white, the tab in a dim periwinkle
  `#8186cf`, a remote machine name in soft teal `#7fb0a8` (hidden when "Local"), then
  the prompt-cache countdown (below); line 2 the state word, then the session name in
  a dimmer sand `#8c8069` (Gavin, 19 Oct: "reduce their brightness"; it was
  `#b0a084`). No gap between entries. The three-line form with the coloured bar line
  is kept commented in `config.toml`, to go back to; the state-words plugin still
  sets the `$bar_*` tokens it used (#3333). History: Q38 (v2): 1, Q40, Q41: 2,
  variation 5 of 6; swapped and recoloured 17 Oct, Q52 tried and undone, Q53: 1,
  Q54: 1, then Q55 (v3): 1 after six colours tried live; three lines 18 Oct (Q64,
  Q65); two lines 19 Oct.
- **No right-alignment:** a row's tokens are laid out left to right; herdr 0.9.3,
  0.9.5 and master (17 Oct) have no align setting, and a rule cannot pad (Q56: 4).
- **Spaces section:** the space name in white; the branch in light sand `#b0a084`
  (Q42: 1).
- **Selected row bar** a deep navy `#1a2233`, **navigate cursor** one step lighter
  `#24304a` (Gavin, 19 Oct: the copper "does not work at all", the navy "better,
  definitely"; until then `#33201f` and `#432a28`). Contrast on the navy: white
  15.9, sand 6.2, periwinkle 4.7, the working and resting grey 3.6. Each is ONE
  setting shared by the spaces and agents sections (`active_row_bg`,
  `selection_bg`), so the two sections cannot have different bars.
- **Panel background** `#170d0d`, Ghostty's own background (Gavin, 19 Oct). herdr
  draws a menu's highlighted row on the gold in `panel_bg`; left at the terminal's
  "reset" it used a mid grey (contrast 3.8), so "Rename pane" in the right-click menu
  read as a header. Now near-black on the gold, 13.8, in every menu, the focused tab
  and the settings screen. `panel_bg` also paints the tab bar, popups and herdr's own
  background; whether Ghostty's 0.95 background opacity still shows through there
  was not checked.

## The cache countdown and the prompt palette (19 Oct)

- **Cache countdown** (Gavin, dotfiles-main Q70: 1): line 1 of each agent row ends
  with the minutes left before that session's prompt cache goes cold. Since 19 Oct,
  11:55 PM it reads "— 42" in six colour bands (seven tokens, `$cache_m50` to
  `$cache_m0` and `$cache_cold`), as "What is set now" above says; until then it was
  "◷ 42m" in three tokens (`$cache_warm` cyan, `$cache_low` yellow, `$cache_cold`
  red). `herdr-cache-report` (home/.local/bin) sets one token and clears the rest.
  The token expires 2 min after the last report, and goes when Claude
  exits. The numbers come from Claude Code's own status-line input
  (`.prompt_cache.expires_at`, `.warm`, `.ttl`), so three status lines feed it:
  `~/.claude/statusline-command.sh` for plain sessions (dot-claude repo), every
  30 s; engage's status line for engage sessions (engage 75c1dda, #3319, live
  19 Oct: a test session's row read "◷ 51m" while its status line read "51:56
  left"); and makeitso's own status line for makeitso sessions, which run in their
  own Claude home `~/.claude_v2`. makeitso's copy was made on 16 Oct, before the
  call existed, so its rows had no timer until 24 Oct (Gavin's screenshot). Its
  status line refreshes every second, so it calls the report at most every 20 s
  per pane; makeitso wired it in its own repo, from a block written here, since it
  cannot read this repo. Read back the same evening: both makeitso panes held a
  cache token. A new status line that should show a timer has to make the same
  call. Silent outside herdr. `herdr-cache-report --selftest`.
- **Prompt palette** (Gavin, dotfiles-main Q69: 1): herdr's sidebar has exactly two
  sections and no plugin can draw in it, so the "third section of words" is a popup.
  `ctrl+Space` then `p`, or `ctrl+alt+p` in one press, or `cmd+option+p` in Ghostty
  (Q72: 1; Ghostty sends herdr's `ctrl+alt+p`), opens `herdr-palette` at 75% wide and
  70% tall over the focused pane. Its tabs come from `~/.config/herdr/palette.toml`
  (Reply, Ask, Do, Commands), plus an "Answer" tab first when the session's last reply
  ends on a 👉 line, one chip per option ("Q66: 3"). One click types a chip into that
  pane's Claude prompt through `herdr-type` (which re-reads the screen before every
  key and never approves a permission prompt); auto-submit adds Enter. The arrows,
  Enter and 1 to 9 work too, and the title bar has clear, edit, auto-submit and close.
  The palette's own words are still Gavin's to give (#3331), and its clear button
  waits for a try on a real draft (#3330).

## State words (18 Oct, dotfiles-main Q60, Q61)

- **Three lines per agent:** 1) the bold state icon, the project, the tab, the
  machine; 2) the session name; 3) the state word on its own line. herdr drops a
  line whose tokens are all empty or hidden, so a row with no word is two lines.
- **A bracket hanging under the project** (Q64: 1): line 2 is the plugin's
  `$session` token, "│ <session name>", and the words on line 3 start with "╰ ".
  herdr has no border or fixed text, and puts " · " between any two tokens
  except after the state icon (`src/ui/sidebar/tokens.rs`, separator), so the
  box characters live inside the token values. The token comes from its own
  source (`dotfiles-state-words-box`) and is re-sent on every status change; a
  `/rename` shows at the next one, because plugins cannot hook `pane.updated`.
  A pane the plugin has not reached shows no line 2. Seen live 18 Oct on the
  dotfiles pane; 50 plugin runs, all `succeeded`.
- **The bar takes the state's colour** (Q65: 1): one token per state
  (`$bar_working`, `$bar_done`, `$bar_idle`, `$bar_blocked`, `$bar_unknown`),
  each with its own fixed `fg` in `config.toml`; the plugin sets the one for the
  pane's state and clears the others on every event. A token's colour is fixed
  per name, and a separate token brings herdr's " · " before the session name,
  which Gavin accepted. The bar colours copy the state colours (Ghostty palette
  cyan, green, bright red; `theme.custom` yellow; `overlay0`), so a palette
  change needs the bar colours changed too. Checked 18 Oct on all six agent
  panes: each held exactly one bar token, the one matching its `agent_status`.
- **"your turn" only when a reply asks him** (Q66 (v2): 1): herdr's idle only
  means the prompt is empty. Network_Plan read idle on 18 Oct with "2 shells, 2
  monitors still running", waiting on its own workers. Gavin's reply style ends
  a reply with a 👉 line exactly when something waits on him, so for idle and
  done the plugin reads the session's transcript (found the way `herdr-type`
  finds it) and shows "╰ your turn" when the last reply's last line starts
  with 👉, and a grey "╰ resting" with a grey bar when it does not. No
  transcript means "your turn", never resting. Checked 18 Oct: four fixture
  arms (asks, no 👉 after an earlier 👉, a torn last line, no transcript) gave
  yes, no, yes, unknown; live, e-conductor (idle, no 👉) went to resting and
  Network_Plan, once its reply ended "👉 Tell me when uv cache prune has run",
  read your turn.
- **Colour only where Gavin is needed:** working is a cool slate grey
  (`theme.custom.yellow = "#6e7a86"`; orange and a warm grey were tried and
  dropped, the warm grey read as the session name's sand).
- **The words come from the `dotfiles.state-words` plugin**
  (`herdr-plugins/state-words/`): thinking; your turn or resting (done AND idle,
  by the 👉 rule above); needs you. Idle gets a word because herdr turns done
  into idle the moment Gavin looks at the tab, and he wants "your turn" to stay
  until he sends a prompt. e-conductor read a test tab on 19 Oct: panes with no
  engage label showed "╰ resting" for idle and done, as designed.
- **How herdr combines labels** (measured 2026-10-18 on 0.9.5, and
  `src/terminal/metadata.rs` effective_metadata_state_labels): per state the
  newest label wins, whichever `--source` sent it; a report replaces its own
  source's whole label set, so every report carries all its labels.
- **The contract with engage** (engage #3313): a source that labels idle owns
  that pane's words. The plugin labels a pane only when it has no idle label, so
  engage-worker's `idle="waiting on e-conductor"` (source `engage`, a draft
  wording) is never overwritten, whichever arrives first. Known limit: a server
  restart wipes all labels; the plugin sets its own again on the next status
  change, an engage label reported only at start does not come back.
- **Seen live 18 Oct:** linked at about 10:51 PM, the plugin labelled the
  dotfiles pane on its next status change and skipped it on the one after
  (log: 3 runs, all `succeeded`). Other panes are labelled on their own next
  status change, not at link time.

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
  (`config/sidebar.rs:101-104`, deny_unknown_fields). `fg` takes `#RGB`/`#RRGGBB`
  only; `fg = "red"` is refused (0.9.5). A refused token is not skipped: the whole
  config falls back to defaults. **No text size:** a terminal draws every character
  in one grid.
- **`row_gap` is whole lines.** 1 was too loose; there is no half line. 0 is 0.9.5's
  default, so `row_gap = 0` in the config only pins it.
- **Rules** (0.9.0+, `hide` 0.9.1+): a token can be restyled or hidden when its OWN
  value `equals`, `contains`, `starts_with`, or is `gt`/`lt` a number. A rule cannot
  replace the text, and cannot test another token. Not allowed on `state_icon` or
  `git_status` ("sidebar rules require a text-valued token"). At most 16 rules a token.
- **`tab`** shows only when the space has more than one tab or the tab has a custom
  name. **`machine`** is empty while one machine is attached; with a second one,
  local rows say "Local" (a rule `equals = "Local", hide = true` drops it).
- **State symbols:** blocked `×` red, working `◐` yellow, done `✓` teal, idle `○`
  green, unknown `·` overlay0 (`client/shell.rs:178-237`). The working yellow is
  close to the gold accent.
- **The Mac/GPU readout** in the tab bar is `overlay1`, pure white, the brightest
  text on screen.
- **Colours come from the host terminal** (`theme.name = "terminal"`,
  `auto_switch = false` in the config). Since 0.9.2, sending `SIGWINCH` to a herdr
  client makes it re-read the terminal's colours, so after a Ghostty theme change
  that sends no light/dark notice, `kill -WINCH <client pid>` refreshes the panes
  (per the 0.9.2 release notes, #4349; not tried here).
- **`branch` and `git_status`** in the spaces section come from Git lookups herdr
  runs per workspace. Before 0.9.2 a slow one could freeze typing; it no longer does
  (per the 0.9.2 release notes, #4492).

## Moving around: Go To, cycling, the collapse button

- **Go To is `prefix+g`**, herdr's default; this config does not rebind it
  (measured 2026-10-18 on 0.9.5: `herdr --default-config` lists `goto = "prefix+g"`,
  and `home/.config/herdr/config.toml` has no `goto` line). Since 0.9.2 it lists
  every agent and terminal as its own row, grouped by workspace, with its status and
  path, and Left/Right jump between workspaces (per the 0.9.2 release notes, #4384;
  not tried here).
- **Navigate mode on the `terminal` theme:** before 0.9.2 the workspace highlight
  could not be seen on this theme; it now can (#4300). Here `selection_bg` colours
  that row anyway. Session-navigator search matches each word on its own (#4408).
  Both per the 0.9.2 release notes.
- **Cycling agents** (`shift+up`/`shift+down` here, `previous_agent`/`next_agent`):
  since 0.9.2 the sidebar scrolls to show the agent picked by cycling or a shortcut,
  so the selection is never off screen (per the 0.9.2 release notes, #4273, #4535,
  #4355).
- **The collapse button** stays clickable when the agent list shows a scrollbar;
  before 0.9.4 the two overlapped (per the 0.9.4 release notes, #4692, #4734; not
  seen here).

## "Claude Code" in the sidebar, and naming

- Claude Code's terminal title is, in order: the custom name (`--name`, `/rename`,
  a hook's `sessionTitle`), the AI-made title, the `--agent` type, then the literal
  "Claude Code". So **"Claude Code" lasts only until the first typed prompt**.
- herdr shows the title as-is (`terminal_title_stripped` drops one spinner mark,
  `terminal/title.rs:1-22`) and cannot swap words in it. Seen 18 Oct in
  `herdr agent list`: `"◐ dotfiles-main"` stripped to `"dotfiles-main"`.
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
  state word, `--token k=v` a `$k` token (`--ttl-ms` to expire, at most 24 hours).
  The 0.9.5 schema: a pane holds up to 32 tokens, one report carries up to 16, a key
  is 1-32 of `[A-Za-z0-9_-]`; the `--source` id is at most 80 characters (the 80 was
  read as the value limit from the 0.9.3 source; not re-read). Values live until cleared, expired or the pane closes; a server restart
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
  #4912; from the 0.9.3 source, not re-tested on 0.9.5, whose notes do not mention
  #4912). A plugin cannot draw in the sidebar; it changes it through report-metadata.
  See [`HERDR_PLUGINS.md`](HERDR_PLUGINS.md).
- **A pane's own background:** a program in the pane can set its default background
  with OSC 11 (`printf '\e]11;#1a2a1a\a'`, reset `printf '\e]111\a'`). herdr keeps it
  per pane and paints it when it differs from the host's (`pane/terminal.rs:3518-3533`).
  Seen working 16 Oct: Gavin's plain shell pane in Ghostty turned dark green, the
  other panes kept the normal background.
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
- herdr 0.9.5 (installed 18 Oct) fixes Claude Code questions not showing as blocked
  in named sessions (#5192); every session here is named, so a question should now
  show `×`. Not yet seen on screen. herdr notices still say "claude needs attention"
  whatever the name (#4332; not in the 0.9.4/0.9.5 notes).

## codebox as a herdr machine (17 Oct, Q47: 1, Q48: 1)

A Claude session started inside a Mac pane that runs `ssh codebox.lan` is not an
agent to the Mac's herdr: herdr names a pane's agent from its foreground process
(`detect/mod.rs` lookup_agent), and that process is `ssh`. The supported route is a
saved machine: `herdr machine add codebox.lan` (Gavin ran it, about 2:01 AM). The
Mac's sidebar then also shows codebox's herdr server, its workspaces and its agents,
labelled with the machine; Claude must be started in a pane of that machine.

- Profile: label `codebox` (renamed from `codebox.lan` the same night), host codebox.lan, default remote session (the one `herdr --remote` uses).
  **18 Oct, `herdr machine list` shows TWO saved machines, both enabled, both host
  codebox.lan:** `codebox` and a second one labelled `codebox.lan`. Not known whether
  that is a re-add or a duplicate; each enabled machine may hold its own ssh path
  (trade-off below). Re-measured later on 2026-10-18 on 0.9.5: still the same two.
  Gavin then removed `codebox.lan` (dotfiles-main Q14), leaving `codebox` alone.
  Both had read `auth required` (Permission denied (publickey)): herdr's background
  ssh cannot prompt for the codebox-admin passphrase. `UseKeychain yes` and
  `AddKeysToAgent yes` on Host codebox.lan in ~/.ssh/config.local (Q17 v2: 1, on
  Network_Plan's advice) made it `reachable`. The sidebar still showed nothing,
  because codebox's server had 0 workspaces (the Mac had 11, same command); a
  refresh starts it empty. herdr.service now runs `herdr-ensure-workspace` as
  ExecStartPost, which opens one workspace when none is saved (Q18 v2: 1).
  It still did not show until a THIRD cause was found: `home/.zshrc` exported
  `HERDR_REMOTE_KEYBINDINGS=server` for every herdr start, and with it set the Mac's
  screen never joins saved machines (no "machines" section, no ssh helper, nothing in
  the debug log). `env -u HERDR_REMOTE_KEYBINDINGS herdr` showed Local and
  codebox.lan at once (18 Oct, Gavin's screenshot). The variable is now added only
  to `herdr --remote` (docs/HERDR.md, "Two machines: the keymap drifts too").
  The label is `Codebox` since the same evening (Gavin); the target stays `codebox.lan`.
- NP-2 checked it against codebox's lockdown (CB D-008): Mac -> codebox only, over the
  ssh connection's stdio, no forwards; the codebox.lan Host entry and its admin key,
  never the speak-relay key; decline any install or update prompt (codebox's herdr
  is pinned, a golden save is the only route that changes it).
- herdr writes its OWN ssh config ($TMPDIR/herdr-ssh-*/config, a 0700 folder) that
  Includes ~/.ssh/config and adds ControlMaster=auto, ControlPersist=600, BatchMode,
  StrictHostKeyChecking=yes, ServerAlive 15/4. ~/.ssh/config is not changed.
  Since 0.9.2 herdr also asks ssh for compression, so remote panes catch up faster
  on a slow link (per the 0.9.2 release notes, #4340). The 18 Oct audit found the
  newest generated config holding only the Includes and ServerAlive 15/4, so compression,
  like ControlMaster and BatchMode, is passed some other way, most likely the
  command line; not checked.
- Repeated `herdr --machine codebox ...` calls open far fewer ssh connections since
  0.9.2 (per the 0.9.2 release notes, #4252). The other half of that fix, forwarded
  ssh agents surviving a reconnect (#1931), does not apply: codebox's lockdown
  allows no forwards.
- **The trade-off Gavin accepted:** the ControlMaster socket (`/tmp/hssh-501/`, folder
  0700, socket 0600, both his) is a standing logged-in path to codebox while the
  machine is enabled, usable by any process running as him, even after his keys
  leave the ssh agent. `herdr machine disable <id>` turns it off.
- A codebox refresh drops the machine; herdr reconnects by itself. From 0.9.4 the
  sidebar width, collapsed groups and agent sorting for a remote machine survive the
  reconnect (#4364, #5019; release notes, not seen here yet), and switching
  workspaces quickly while changing machines is no longer cancelled (#4536, #5061;
  release notes).
