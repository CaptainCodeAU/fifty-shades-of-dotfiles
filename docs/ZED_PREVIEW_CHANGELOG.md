# Zed Preview — Changelog Tracker

<!-- ZED_PREVIEW_DOC_VERSION: 1.16.1 -->
<!-- LAST_UPDATED: 2026-09-18 -->

> **What this is.** A living record of notable **Zed Preview** changes, filtered to
> what Gavin cares about: **user interface**, **configuration / settings**, and
> **themes / appearance** — both new features and fixes.
>
> **How it stays current.** `.claude/hooks/zed-version-check.sh` runs at session start
> and does two checks: it compares the version recorded above (`ZED_PREVIEW_DOC_VERSION`)
> against the latest Zed Preview release on GitHub, and it polls the merge status of
> watched upstream PRs (**#58755**, per-window themes) live every session. **That PR was
> closed unmerged on 2026-09-07**, so this particular watch is spent; the hook will now
> report it closed every session until the row below is retired or replaced. If a
> newer release exists, or a watched PR merges/closes, it nudges the assistant to refresh
> this file. The hook only _detects_; the assistant does the _update_ (see
> [Update runbook](#update-runbook)).
>
> **Source of truth.** The Zed changelog itself, not memory:
> <https://zed.dev/releases/preview/latest> and the GitHub releases for
> `zed-industries/zed` (preview tags look like `v1.8.0-pre`).

---

## Current baseline

| Field                  | Value         |
| ---------------------- | ------------- |
| Latest Preview tracked | **1.16.1**    |
| Release date           | 2026-08-18    |
| GitHub tag             | `v1.16.1-pre` |
| Doc last refreshed     | 2026-08-19    |

---

## Why I track Zed Preview (Gavin's context)

These tie the changelog to Gavin's actual setup, so a relevant change gets flagged
rather than buried. (Cross-references are auto-memory slugs.)

- **`settings.json` is `skip-worktree` on the Mac** (`zed-settings-skip-worktree`).
  Its `ssh_connections` block holds LAN-private data; never propose committing it.
  Settings-**UI** changes in Zed don't touch this — only the JSON schema would.
  - _In plain English:_ Gavin's Zed settings file on the Mac is deliberately hidden
    from git because it holds private server info — leave it alone.
- **Per-project themes are wanted; the PR that would have delivered it was ABANDONED**
  (`project_zed_per_project_theme`). Tracked upstream at **zed#13300** (still open);
  **PR #58755 was closed WITHOUT merge on 2026-09-07**, verified live 2026-09-18 against
  the GitHub API with a known-merged PR as a control. It stored per-window themes in
  Zed's DB rather than `settings.json`. Nothing replaced it, so `zed --user-data-dir
  <path>` is now the only route and should be treated as permanent, not a stopgap.
  - _In plain English:_ someone built the colour-per-window feature and then it was
    dropped without going in. The workaround is what you have from now on.
- **`detect_venv` double-activates with direnv** (`zed-detect-venv`). Zed auto-runs
  `source .venv/bin/activate` in its terminal; the `.envrc` chain does too. Fix is
  `"terminal": { "detect_venv": "off" }`.
  - _In plain English:_ Zed and Gavin's shell setup both auto-start Python
    environments, doubling up — one setting turns Zed's copy off.

---

## What I watch for

1. **UI** — panels, tabs, breadcrumbs, titlebar, command palette, layout, gutter.
2. **Configuration** — new/changed/removed `settings.json` keys and defaults.
3. **Theme / appearance** — themes, `theme_overrides`, syntax colors, icon themes,
   fonts, visual styling.

Everything else (language servers, agent internals, platform plumbing) is noted only
when it visibly affects the above or Gavin's known setup.

---

## Release log (newest first)

### 1.16.1 — 2026-08-18

**Theme / appearance**

- _No theme, syntax, font, or visual-styling changes this cycle._

**Configuration**

- `git_gutter_width` (new in 1.15.0, below) is now exposed in the **Settings UI**, with two
  choices: default (scales with font size) or a custom fixed pixel width. Not set in your
  `settings.json`, so the default still applies.

**UI**

- Fixed a Cursor ACP agent startup failure. Not applicable — you run Claude Code, not Cursor.

**Fixes Gavin may feel**

- **GPG passphrase modal appearing repeatedly on commit — fixed, for users with a pinentry
  tool configured (e.g. `pinentry-mac`).** This is a second pass at the same class of bug
  1.13.0 fixed ("GPG signing prompting for the passphrase on every commit") — if you still saw
  it after 1.13.0, this cycle is the fix that should stick.
  - _In plain English:_ if Zed kept asking for your GPG password on every commit, that should
    now stop for good.
- Fixed: array merging for extensions; project search returning wrong results in non-Unicode
  files.

### 1.16.0 — 2026-08-12

**Theme / appearance**

- **New themeable `attribute.special` token** — highlights Python dunder variables
  (`__init__`, `__name__`, etc.) as a distinct syntax color. Second new theme slot this
  refresh window (after 1.13.0's `variable.parameter`).
- Markdown preview scrollbar visibility now respects your `scrollbar.show` setting.
  - _In plain English:_ Python's `__dunder__` names can now get their own theme color, and the
    Markdown-preview scrollbar behaves like the rest of the editor's scrollbars.

**Configuration**

- New `terminal.starts_open` — controls whether the Terminal Panel opens automatically in new
  workspaces. Not set in your `settings.json`, so the (unchanged) default applies.
- Default OpenAI model changed for subscription users. Not relevant — your Agent Panel is
  configured for Anthropic (Claude Opus 5, per the 1.13.1 entry above).
  - _In plain English:_ a new setting to control whether the terminal auto-opens; the
    OpenAI-model default change doesn't touch you since you use Claude in Zed.

**UI**

- **Mermaid diagrams in Markdown preview now support zooming and horizontal scrolling.**
  Directly builds on 1.14.1's fix for wide Mermaid diagrams getting squashed — this cycle
  gives you a way to navigate a wide diagram instead of just rendering it at full width.
- **Wide Markdown tables now get a horizontal scrollbar** instead of overflowing or wrapping —
  same family of fix as the Mermaid one, relevant to your `md-hardbreak` preview workflow.
- Git Panel: grouped change sections are now collapsible; new "Copy Path" / "Copy Relative
  Path" context-menu entries.
- Agent Panel terminals shrink back down after being cleared; loading spinners now rotate in
  sync; Text Finder highlights matches as regex when regex filtering is on; Helix mode gained
  Tab / Shift-Tab navigation through the code-actions menu.
  - _In plain English:_ wide Mermaid diagrams and wide tables in Markdown preview are both
    navigable now instead of cramped or overflowing — the biggest item for your workflow this
    cycle.

**Fixes Gavin may feel**

- None called out beyond the Markdown/Mermaid items above.

### 1.15.0 — 2026-08-05

**Theme / appearance**

- _No theme, syntax-color, font, or icon-theme changes this cycle._

**Configuration**

- New `git.diff_base` — choose whether gutter/file-status colors and git diffs compare against
  `"head"` (default) or `"default_branch"` (merge-base). Not set in your `settings.json`, so
  the default (`"head"`) still applies.
- New `gutter.git_gutter_width` — set the pixel width of the git-diff gutter indicators. Also
  not set; later exposed in the Settings UI by 1.16.1 (above).
  - _In plain English:_ two new knobs for how git changes are compared and drawn in the
    gutter — you haven't touched either, so nothing changes for you yet.

**UI**

- Project switcher can now close the currently-selected project and auto-switches to a
  neighboring project.
- New `multiple_selections` key context — lets you bind different keys for when multiple
  cursors/selections are active.
- Linked editing and Emmet completions extended to JSX/TSX.
- Files can be dragged from the Project Panel to external macOS apps (and external Linux
  Wayland apps).
- Extension listing shows provider-specific repo icons; dev extensions show their declared
  features.
- New "Diff Against Default Branch" option in the editor-controls menu — pairs with the new
  `git.diff_base` setting above.
  - _In plain English:_ closing a project tab is smarter about what it switches to, dragging
    files out to other Mac apps now works, and there's a menu option to diff against your
    default branch instead of HEAD.

**Fixes Gavin may feel**

- Fixed cursor placement after multi-key bindings in Vim/Helix mode; fixed misaligned Agent
  sidebar headers on Linux (not applicable to your Mac setup).

### 1.14.2 — 2026-08-02

**Theme / appearance**

- Fixed incorrect parameter colors in the Gruvbox theme. Not your theme — no effect.

**Configuration**

- Fixed the Zed Agent hanging when running `git` commands with a pager configured in system
  git settings.
  - _In plain English:_ if Zed's AI agent ever froze while running a git command, that was a
    pager-related bug, now fixed.

**UI**

- Fixed Option+Left (word-left) stopping short of punctuation between words.
- Fixed a crash when adding selections through tab-expanded column operations.

### 1.14.1 — 2026-07-29

**Theme / appearance**

- **No theme, syntax, font, or visual-styling changes this cycle.** The only font-adjacent
  movement is two new Agent-Panel font keys (below). The per-project-theme front stays silent
  across all three releases in this refresh — PR #58755 is still unmerged (see watch-items).
  - _In plain English:_ no colour or theme movement again, and your colour-per-window goal
    still hangs entirely on that one unmerged pull request.

**Configuration**

- **BREAKING: the default `base_keymap` changed from `VSCode` to `Zed`.** The inline assistant
  moves to `cmd-i` (macOS) / `ctrl-i`, and `f5` starts the debugger. **You are unaffected** —
  `home/.config/zed/settings.json` pins `"base_keymap": "VSCode"` explicitly.
  - _In plain English:_ Zed changed the default shortcut set for anyone who never picked one;
    you picked, so nothing moves for you.
- New `agent_ui_font_family` and `agent_buffer_font_family` — set the Agent Panel's UI and
  buffer fonts independently of the editor.
- New `agent.compaction_model` — choose which model performs context compaction.
  - _In plain English:_ the AI panel can now have its own fonts, and you can hand the
    conversation-summarising job to a cheaper model.

**UI**

- **Git Panel: new "Skip Hooks" toggle in the commit-button menu — it skips `pre-commit` AND
  `commit-msg` hooks.** Treat this as a footgun in your setup: committing from Zed's Git Panel
  with it on bypasses `git-leak-scan` (the staged-diff identity/secret gate) and the
  `_audit-chain` `commit-msg` trailer stamping. Leave it off; terminal commits are unaffected.
  - _In plain English:_ Zed added a one-click way to commit while skipping your safety checks —
    do not use it, or a secret could slip through unscanned.
- **Git Panel:** the deleted-file context menu and confirmation prompt now say "Restore File"
  instead of the misleading "Discard Changes".
- **Project Panel:** file operations (create / rename / move / delete) are now undoable and
  redoable.
- **Markdown preview:** a link to another Markdown file opens a preview scrolled to the linked
  heading; `alt`-click opens the raw source instead.
- **Read-only tabs:** tooltips and context menu now say "Tab" rather than "File".
- **Agent Panel:** reasoning-effort selector for Anthropic-compatible providers that support
  adaptive thinking.
  - _In plain English:_ clearer git wording, undo for file operations, smarter Markdown-preview
    links, and a thinking-effort dial in the AI panel.

**Fixes Gavin may feel**

- **Git Panel going stale** after heavy filesystem activity made the file watcher lose events —
  relevant given how much `install.sh` and stow churn this repo sees.
- Fixed: crash when copying/pasting with multiple cursors; input lag in large files; the cursor
  jumping to end-of-file when a language server formatted with CRLF; **wide Mermaid diagrams
  squashed in Markdown preview**; workspace-relative links with line/column suffixes rendering
  wrong; terminal processes surviving a closed terminal; keybindings swallowed by the git
  repository selector.
  - _In plain English:_ a stale git panel and a multi-cursor paste crash are both fixed, and
    wide Mermaid diagrams render at full width again.

> **There is no 1.14.0 preview.** The preview channel jumps 1.13.1 → 1.14.1; zed.dev serves no
> `preview/1.14.0` page (checked 2026-07-30). Nothing was missed in this refresh.

### 1.13.1 — 2026-07-27

**Theme / appearance**

- _No theme, syntax-colour, icon-theme, font, or visual-styling changes this cycle._

**Configuration**

- _No new, changed, or removed settings keys this cycle._

**UI**

- _No UI changes this cycle_ — a patch release only.
  - _In plain English:_ a small bug-fix release that changed nothing you can see or configure.

**Additions / fixes Gavin may feel**

- **Claude Opus 5 support added** for the Anthropic and Amazon Bedrock BYOK providers — the
  model you run Claude Code on is now selectable inside Zed's own agent panel.
- Fixed: project search returning hits from nested repositories that the containing repo
  excludes via `.git/info/exclude`; project settings failing to re-enable language servers;
  hover documentation rendering with too many line breaks.
  - _In plain English:_ Zed's built-in AI can now use Opus 5, and project search stops
    returning results from nested repos you excluded.

### 1.13.0 — 2026-07-23

**Theme / appearance**

- **New themeable `variable.parameter` syntax colour** — the first new theme colour slot in
  several cycles.
- Fixed: incorrect rainbow-bracket highlighting in some cases (a correctness follow-up to
  1.11.0's bracket-colorization work); static images ignoring EXIF orientation (JPEGs
  previewing rotated); Markdown emphasis delimiters dropped when joining lines.
  - _In plain English:_ themes gained one new colour slot, and the bracket-colour feature from
    two releases ago got a fix.

**Configuration**

- New `title_bar.show_worktree_name` (default `true`) — set `false` to hide the worktree-name
  picker in the title bar. Worth noting for your per-project-identity goal: the title bar is
  now growing real settings, though this one is visibility only — colour still lives in
  `theme_overrides.title_bar.background`, which remains user-level, not per-project.
- `file_finder::Toggle` keybindings now accept an `"include_ignored": true` argument.
- Removed: three deprecated Mistral models; Fast Mode deprecated for Opus 4.6 / 4.7.
  - _In plain English:_ you can hide the folder name in the title bar, and the file finder can
    be told to include ignored files.

**UI**

- **BREAKING keybinding: `cmd-alt-f` (macOS) now opens the Text Finder** instead of the
  replace / filter toggles. Safe for you — your `keymap.json` only claims `cmd-alt-b`,
  `cmd-alt-g`, and `cmd-alt-u`, so none of your `md-hardbreak` bindings are displaced.
- **Text Finder:** seeds its query from the focused item's selection (including the terminal)
  and gained default bindings (`cmd-alt-f` / `ctrl-alt-f`).
- **Git Panel:** better branch-picker filtering and grouping, branch-creation suggestions, and
  remote-provider icons; History entries stay highlighted while their context menu is open;
  solo diffs show the full file by default while keeping change indicators in the scrollbar.
- **Editor:** runnable gutter controls show run statuses (with a "Clear Run Status" menu item);
  buffer-symbols picker gained a preview pane; image-viewer zoom is editable from the toolbar.
- **Markdown preview:** hovering a link shows its destination bottom-left; relative links like
  `src/main.rs#L42` open at the referenced line (also in Agent responses).
  - _In plain English:_ one Mac shortcut changed meaning (harmless for you), search now picks up
    whatever you had selected, and the git branch picker is much easier to sift.

**Fixes Gavin may feel**

- **`commit-msg` hooks were being silently skipped — now fixed.** Load-bearing here: your
  `_audit-chain` chainer stamps the `C-*` attribution trailers from a `commit-msg` hook, so any
  commit you made through Zed's Git Panel before 1.13.0 could have landed without them
  (terminal commits were never affected).
- **Staging could corrupt the index with repeated diff lines**, staging/unstaging could apply to
  the wrong hunks, and partially-staged diff stats were wrong — all fixed. Also fixed: GPG
  signing prompting for the passphrase on every commit; ahead/behind counts not refreshing
  after a fetch; changes not reappearing after an uncommit.
- Fixed: the Zed window shrinking to the built-in display height after a screen lock on
  multi-monitor macOS; selection boxes not rendering with the cursor offscreen; multibuffer
  header clipping and text overlap in transparent themes; right-click menus intermittently
  failing at certain scroll positions; cursors blinking in unfocused editors.
  - _In plain English:_ the important one is that Zed's commit button was skipping git hooks —
    so commits made that way may be missing your attribution trailers, and it is now repaired.

### 1.12.0 — 2026-07-15

**Theme / appearance**

- **No theme, syntax, font, or visual-styling changes this cycle** (bracket colorization
  unmentioned/unchanged). Movement stays confined to 1.11.0; the per-project-theme front is
  still silent — PR #58755 remains unmerged (see watch-items).
  - _In plain English:_ nothing changed about colors or fonts this release, and your
    color-per-window goal still hangs on the unmerged PR.

**Configuration**

- New `format_on_save` options **`modifications`** / **`modifications_if_available`** — format
  only the Git-changed lines instead of the whole file (also importable from VS Code's
  `editor.formatOnSaveMode`).
  - _In plain English:_ Zed can now auto-format just the lines you touched on save, not the
    whole file — handy on large or legacy files.
- `reduce_motion` now accepts the value **`on`** (not just a boolean) to cut animations.
  - _In plain English:_ a stronger "reduce animations" setting — relevant to your
    accessibility-first setup (you already force the classic renderer).
- New `lsp_results_location` (global) + per-action `open_results_in` control where LSP result
  pickers open; new `supports_fast_mode` for custom Anthropic models.
  - _In plain English:_ minor knobs for where language-server results appear and for custom AI
    model config — unlikely to affect you directly.

**UI**

- **Git Panel:** new **Staging grouping** (separate Staged / Unstaged sections); History tab
  gains a Git-Graph context menu; Restore / Restore All buttons in the unstaged diff view; GPG
  passphrase prompts for commit-signing keys.
- **Finders:** multi-select in **File Finder and Text Finder** via cmd-click (macOS) + tab
  selection + a multi-select button in the search bar — directly relevant since you lean on the
  finder.
- **Editor:** new `workspace: toggle editor zoom` (maximize the active pane); in-progress MCP
  tool calls can now be expanded.
- **Markdown preview:** `cmd-shift-v` now toggles between preview and source — a new shortcut in
  your `md-hardbreak` workflow.
  - _In plain English:_ git staging is easier to read, you can pick multiple files/results at
    once, one key maximizes the editor, and Cmd-Shift-V flips Markdown preview/source.

**Fixes Gavin may feel**

- **Python venvs** now restore automatically when reopening a workspace (previously dropped) —
  adjacent to your `detect_venv`/direnv setup, though `detect_venv` itself is unchanged.
- Fixed: Agent Panel's sticky "awaiting confirmation" overlay covering the whole panel; selection
  rendering over inlay hints; branch-picker menu failing under nested popovers; Git-Panel
  filenames with newlines; focus following the mouse over blank Project-Panel space; Git Graph
  showing "0 Changed Files" for submodule commits.
  - _In plain English:_ a batch of Git-panel and agent-panel annoyances got cleared, and your
    Python environments come back on reopen.

### 1.11.0 — 2026-07-08

**Theme / appearance**

- **Improved bracket colorization** — now preserves the theme's accent colors and applies
  targeted contrast fixes. First theme-facing change in three cycles (1.9.0 and 1.10.0 had none).
  - _In plain English:_ matching-bracket colors now follow your theme better and are easier to
    read — the first actual color/theme change Zed has shipped in a while.

**Configuration**

- New `terminal.open_links_in_mouse_mode` — when off, Cmd/Ctrl-click forwards the click to the
  terminal app instead of opening the link (pairs with the terminal-link fix below).
- **Changed:** `markdown_preview_font_size` now falls back to the **UI font size** when unset.
  - _In plain English:_ another Markdown-preview knob relevant to your `md-hardbreak` workflow — if
    you never set a preview font size, it now tracks the UI font instead of a fixed default.

**UI**

- **View menu** gains **Agent Panel** + **Git Panel** entries; agent terminal threads are
  searchable (`cmd-f`); turn-end buttons became slash-commands in the message editor.
- **Git Panel / graph:** commit-history tag labels; toggleable git-graph columns; full commit
  message as Markdown in graph details; partially-staged commit multibuffers; diff-stat numbers.
- **Editor:** project-symbols picker gained a preview pane; middle-click a project-panel file opens
  it in a permanent (non-preview) tab; collapse per-file match groups in Text Finder; diff
  multibuffer headers show per-file added/removed counts.
- **Terminal:** Cmd/Ctrl-click opens links even with mouse reporting enabled.

**Fixes Gavin may feel**

- **Text Finder:** fixed a crash + high-memory-usage bug and a dismissal crash during workspace
  actions — directly relevant since you lean on the finder.
- Fixed: git-blame hover popover not appearing on first trigger; missing icons on non-terminal
  tabs while dragging; drag overlay not clearing on external drag end; vim-mode symbol rename
  dropping the last character.
  - _In plain English:_ several editor annoyances (search crashes, blame hover, a vim rename bug)
    are cleared this cycle.

### 1.10.0 — 2026-07-01

**Theme / appearance**

- _No theme, syntax-color, font, or icon-theme changes this cycle._
  - _In plain English:_ nothing changed about Zed's colors or themes in 1.10.0.

**Configuration**

- **Format-on-save is now OFF by default** (except languages that ship an official formatter).
  - _In plain English:_ Zed will stop auto-formatting most files on save unless you opt back in —
    check your settings if you relied on it.
- New `git.inline_blame.location` — render current-line git blame in the **status bar** instead of inline.
- New `markdown_preview_font_size` (+ separate scale actions) — size the Markdown preview text
  independently of the editor.
  - _In plain English:_ another Markdown-preview knob, relevant to your `md-hardbreak` workflow.
- New `agent.commit_message_include_project_rules` — exclude project rules from the commit-message prompt.
- Key agent settings (LLM providers, external agents, MCP servers) moved into the settings-editor UI.

**UI**

- Diff view: solo diff shows changed hunks by default (full-file toggle); diff-hunk line numbers now
  match version-control colors; Project Panel gained "Expand All" / "Collapse All".
- Text finder opens files at the matched **column**, and seeds the last query + filters.
- Helix mode: `z c` center-scroll, `alt-b`/`alt-e` syntax-node navigation, `*` search-selection.

### 1.9.0 — 2026-06-24

**Theme / appearance**

- _No theme, syntax-color, font, or icon-theme, or visual-styling changes this cycle._
  - _In plain English:_ nothing changed about Zed's colors or themes in 1.9.0.

**Configuration**

- New `markdown_preview.limit_content_width` and `markdown_preview.max_width` — constrain and
  center the Markdown preview content width.
  - _In plain English:_ you can now cap how wide the Markdown preview gets so long lines don't
    stretch edge-to-edge — directly relevant to your `md-hardbreak` preview workflow.
- New `agent.sandbox_permissions.enabled` — toggle the agent terminal sandbox on/off.
- New `git_panel.entry_primary_click_action` — set the default click behaviour on a Git Panel file.
- **Changed/removed:** `git_panel.sort_by_path` is REPLACED by `git_panel.sort_by` (`path`/`name`)
  plus `git_panel.group_by` (`none`/`status`).
  - _In plain English:_ if you ever set the old git-panel sort key, it's renamed — the old name
    silently stops working, so update it.

**UI**

- Picker modals (file finder etc.) gained draggable resizing and a side/below **preview** pane;
  new text-finder picker as an alternative project-search UI (searches shared between views).
- Named bookmarks; Agent Panel in-thread search (Ctrl/Cmd+F); quick "add remote MCP server".
- Git Panel: split Stage-All/Unstage-All header button; git-blame toggle in the gutter context
  menu; new View Options menu (list/tree, sort by path/name, group by status).
- Terminal Vim paragraph navigation (`shift-{` / `shift-}`); Helix-mode debugger keybindings.
- Fixes: Remote Projects modal is now keyboard-navigable; Git Panel selection visibility after a
  post-commit removal; Vim `cw` with a count preserves whitespace.

### 1.8.2 — 2026-06-22

**UI**

- Fix: the Copilot sign-in window no longer floats above all other applications — it's now
  scoped to Zed.

**Configuration / Theme**

- _No configuration or theme changes._ (Other fixes were platform plumbing: case-insensitive
  filesystem git-state sync, file-watcher performance on large worktrees, Cursor agent-mode compat.)

### 1.8.0 — 2026-06-17

**Theme / appearance**

- _No new theme features this cycle._ Only a fix: fallback fonts were missing
  weight/style on macOS — now corrected.
  - _In plain English:_ nothing changed about colors/themes; one fix makes backup
    fonts render bold/italic correctly on Mac.

**UI**

- New `workspace: reset pane sizes` command — equalizes all panes in the center group.
- Breadcrumbs now show file icons when the tab bar is hidden (if icons are enabled).
- Tab switcher truncates long filenames while keeping the extension visible.
- New `editor: select inside delimiters` / `editor: select around delimiters` actions
  — expand through nested brackets/quotes when repeated.
- Sidebar: create new worktrees directly from the new-thread button.
- Agent panel polish: better empty-state toolbar; single newlines now render as line
  breaks (GitHub-style); clearer sandbox permission dialogs (show exact commands +
  write paths); fixed dark shadow artifacts in panel headers on transparent backgrounds.

**Configuration**

- New `agent.terminal_init_command` — auto-runs a command when an agent terminal opens.
- New `dev_container_use_buildkit` — toggles classic Docker builder vs BuildKit.
- Fix: settings input fields now clear when reset to defaults while focused.

### 1.7.2 — 2026-06-12

**UI**

- Fixed: the Settings UI window could not be dragged on macOS.
- Fixed: close button could overflow inside a workspace-error popup.

### 1.7.1 — 2026-06-10

**UI**

- Cleaner, more legible Markdown preview styling.
- Agent skills management moved into the Settings UI.

**Adjacent fixes Gavin may feel**

- Python toolchains no longer leak between worktrees; Python splat-param highlighting
  fixed; remote-terminal env and SSH workspace-root handling fixed.
  - _Note:_ this is toolchain isolation, **not** `detect_venv` — the double-activation
    conflict above still stands.

---

## Standing watch-items (open threads)

| Item                               | Status as of 2026-09-18                | Why it matters                |
| ---------------------------------- | -------------------------------------- | ----------------------------- |
| Per-project themes (zed#13300)     | **PR #58755 CLOSED unmerged 2026-09-07** | Gavin's color-per-window goal |
| `theme_overrides` at project level | Still user-settings only; no fix coming | zed#13300 open, nothing building it |
| `detect_venv` default              | Still on by default (yours pins `off`) | direnv double-activation      |
| Title-bar settings surface         | New `title_bar.show_worktree_name`     | Visibility only, not colour   |

**PR #58755 "Add per-window theme overrides"** (author 42piratas; opened 2026-06-06;
open / not merged / not draft; last activity 2026-06-29; base `main`; no milestone;
9 files, +480/-39). Each window gets its own theme via new actions **`theme: project`**
and **`theme: clear project`**; choices persist in a new `window_theme_overrides` DB
table keyed by `WindowId` — **not** in `settings.json` or project files. That means it
won't collide with the skip-worktree'd settings file and needs no committed per-project
config. If merged, it obsoletes the `--user-data-dir` workaround. Gavin is on record
backing this on accessibility grounds in **discussion #24010** (comment 17160732,
2026-06-03). It's not the `title_bar.background` approach he proposed, but it meets the
core goal. Watch for merge.

**Re-checked 2026-08-19** (live, via the session-start PR poll): still open, still not merged,
no new activity since 2026-06-29. None of 1.14.2, 1.15.0, 1.16.0, or 1.16.1 shipped any
per-window or per-project theme capability — 1.13.0's `title_bar.show_worktree_name` remains the
only title-bar setting to appear, and it controls visibility, not colour. The
`zed --user-data-dir` workaround remains the only route to a colour-per-window setup.

**Re-checked 2026-09-18** (live, via the GitHub API, not the session poll alone):
**PR #58755 is CLOSED and was never merged** — `state=closed`, `merged=false`,
`closed_at=2026-09-07T18:38:00Z`. A known-merged PR was queried in the same breath as a
control and correctly reported `merged=true`, so the reading is not an artefact of the
instrument. Issue **zed#13300 remains open** with nothing building against it. The two
dated mentions in the 1.14.1 and 1.12.0 release-log entries above were accurate when
written and are deliberately left alone; this section carries current status.

The consequence for Gavin's goal: there is no upstream per-window or per-project theme
capability and none in progress. `zed --user-data-dir <path>` is the answer, and the
markdown-preview work below was designed around that permanence rather than waiting.

- _In plain English:_ the feature is not coming. Stop waiting for it.

When refreshing this doc, re-check each row against the new release.

---

## Markdown preview theming — what is actually possible (verified 2026-09-18)

Read from Zed's source at the **exact installed build**, tag `v1.21.0-pre`, sha
`808200ff7cc78214bb9a6040b52a4d6b35e80c78`. Not from docs, not from memory. Re-verify
against the binary or source before adding any key; a wrong key is accepted silently.

**The preview ignores `syntax.*` for markdown elements.** `syntax.*` reaches code blocks
only. Every markdown element colour comes from `colors.*`, in
`crates/markdown/src/markdown.rs` → `MarkdownStyle::themed_with_overrides()`.

| Preview element | The key that drives it |
| --- | --- |
| Body text **and h1-h5** | `text` — one key for all of them, they cannot differ |
| **h6** | `text.muted` — the one heading level that is separate |
| Page background **and** code block fill | `editor.background` — one key for both |
| Link text + underline | `text.accent` |
| Blockquote text | `text.muted` |
| Horizontal rules, table cell borders, quote border | `border` |
| Code block border **and the h1/h2 bottom rule** | `border.variant` — one key for both |
| **Table header row background** | `title_bar.background` (also the real title bar) |
| **Table zebra stripe, odd body rows** | `panel.background` (also the real panels) |
| Inline code background (8% opacity) | `editor.foreground` (also the editor's text colour) |
| GitHub alert blockquote borders | `status.info` / `success` / `warning` / `error` |

- _In plain English:_ the preview only looks at about ten colour settings. Anything you
  put in the syntax section is only used inside code blocks.

**Hardcoded in the renderer — no key reaches these.** Heading sizes (h1 `1.75rem`, h2
`1.4`, h3 `1.2`, h4 `1.0`, h5 `0.875`, h6 `0.85`), heading weight `SEMIBOLD`, heading line
height `1.25`, body line height `1.5`, paragraph spacing `16px`, list spacing `12px`,
table cell padding `point(px(10.), px(4.))`, code block padding `12px` with `16px` margins
and a `6px` corner radius, link underline thickness `1px`, and inline code font size
`0.875rem`. This is also why the `markdown_preview` keys for `line_height`,
`paragraph_spacing` and `headings` do not exist: the values they would set are compiled
in.

> **Correction, 2026-09-18 (same day).** An earlier version of this section said table
> cell padding was `point(px(4.), px(2.))` and paragraph line height `rems(1.3)`. Those
> are the `MarkdownStyle::default()` values. The preview runs
> `with_preview_overrides()` afterwards, which replaces both. Read the override function,
> not just the constructor.

**Tables DO have a header fill and zebra striping, contrary to what this section said
first.** `markdown.rs` paints header cells with `colors.title_bar_background` and every
odd body row with `colors.panel_background`, keyed off `builder.table.in_head` and
`row_index % 2 == 1`. The earlier claim came from reading the `MarkdownStyle` struct,
which has only `table_cell_padding` — but the table colours never pass through that
struct, they are read from the theme at render time. **A struct listing its fields is not
a list of what the renderer reads.**

**Bold takes no colour; inline code text takes no colour of its own.** Bold gets
`FontWeight::SEMIBOLD` and nothing else. Inline code is more specific than "inherits":
`with_preview_overrides()` explicitly assigns `self.inline_code.color = Some(colors.text)`,
so it is *forced* to body colour and cannot be separated from it. What inline code CAN
have is its own background chip, via `editor.foreground` at 8% opacity, and in the preview
that key drives nothing else — the link background is explicitly nulled on the next line.
So a Claude-Code-style "blue highlight, grey body" is achievable only via `text.accent`
on links, plus the inline code chip.

**The `markdown_preview.theme` trap.** Setting that key costs you live tuning.
`markdown_preview_view.rs` → `resolve_preview_theme()` fetches the theme with
`ThemeRegistry::global(cx).get(name)` and **never calls `apply_theme_overrides()`**, so
while the key is set, `experimental.theme_overrides` cannot reach the preview. Leave it
**unset**: the preview then falls back to the active theme, which does get overrides.

- _In plain English:_ pinning the preview to its own theme blocks live colour edits.
  Leave it unpinned.

**What is live and what is not.** `settings.json` edits apply **on save**, verified
repeatedly. Theme-file edits under `~/.config/zed/themes/` do **not**; they need a
restart. That asymmetry is the whole reason colours live in
`experimental.theme_overrides` (JSON key is dotted — from `#[serde(rename)]`) rather than
in the theme file. Cost of that choice: overrides apply to the **active** theme, so they
change the editor too. There is no preview-only *and* live option in this build.

**Font families must be REGISTERED, not merely present on disk.** `New York` and
`Iowan Old Style` have font files in `/System/Library/Fonts` but are **not** registered
families, so Zed silently falls back with no error. Check with
`system_profiler SPFontsDataType` and grep for `Family: <name>`, always with a
known-present family as a control. Registered serifs here: Charter, Georgia, Palatino,
Baskerville, Hoefler Text. Avoid Baskerville and Hoefler Text on dark backgrounds —
their hairlines thin out.

- _In plain English:_ a font file existing does not mean Zed can use it. Check the name
  first, or you change a setting and nothing happens.

**Only seven `markdown_preview` keys exist:** `theme`, `font_family`,
`code_font_family`, `font_size`, `limit_content_width`, `max_width`,
`open_markdown_files_in_preview`. `limit_content_width` **must** be `true` or `max_width`
is ignored and text renders edge to edge (`max_width` is `Option<Pixels>`; `None` means
edge to edge). Keys from discussion 43384 — `zoom`, `line_height`, `paragraph_spacing`,
`list_item_spacing`, `code_block_font_size_ratio`, `headings`, `table`, `inline_code`,
`link`, and every `*_ratio` / border / zebra key — **do not exist** and are silently
ignored. Do not re-propose them.

### The editor buffer is a different story: `syntax.*` DOES reach markdown there

Everything above is about the **preview pane**. The markdown **source** you type in is
highlighted by the normal Tree-sitter path, and that one reads `syntax.*` exactly as any
other language does. Two facts make it work, both verified 2026-09-18:

1. **The captures carry a `.markup` suffix.** `crates/grammars/src/markdown/highlights.scm`
   and `markdown-inline/highlights.scm` emit `@title.markup`, `@emphasis.markup`,
   `@emphasis.strong.markup`, `@text.literal.markup`, `@link_text.markup`,
   `@link_uri.markup`, `@punctuation.markup`, `@punctuation.embedded.markup`,
   `@punctuation.list_marker.markup` and `@strikethrough.markup`. Not the bare names.
2. **Dot-boundary prefix fallback resolves them anyway.**
   `crates/syntax_theme/src/syntax_theme.rs` → `highlight_id()` searches the theme's keys
   from the first dotted segment up to the full capture name and takes the **most specific
   key that matches on a dot boundary**. So `title.markup` finds a plain `title`, and
   `emphasis.strong.markup` correctly prefers `emphasis.strong` over `emphasis`.

The practical consequence: a `.markup` key styles **markdown only**, while the bare key
styles that capture in **every** language. That is the lever for making markdown source
look different from code without touching any other grammar.

**A syntax key accepts exactly four fields** — `color`, `background_color`, `font_style`,
`font_weight` (`crates/settings_content/src/theme.rs` → `HighlightStyleContent`). There is
**no** strikethrough or underline field, so `~~struck~~` can only be muted by colour, never
drawn with a line. `background_color` is real and usable: it is how inline code gets a chip
in the source buffer.

- _In plain English:_ the file you type in and the preview beside it are styled by two
  different systems. Keys ending in `.markup` only affect markdown.

> **Note on the version markers.** `ZED_PREVIEW_DOC_VERSION` is deliberately still
> `1.16.1` as of this refresh, even though 1.21.0 is installed. Releases 1.17 → 1.21 have
> **not** been written up yet. Bumping the marker would silence the session-start hook
> and the gap would never be noticed again.

---

## Update runbook

When the session-start hook flags a newer Preview (or on request):

1. **Fetch the live changelog** — `WebFetch https://zed.dev/releases/preview/latest`,
   plus any versions between the doc baseline and latest (e.g. `.../preview/1.8.1`).
2. **Filter to the three focus areas** — UI, configuration, theme/appearance —
   capturing both introduced and fixed items. Note explicitly when a cycle has _no_
   theme changes (silence is signal for Gavin's theming goal).
3. **Add a new `### <version> — <date>` section** at the top of the release log.
4. **Re-check the standing watch-items table** — especially zed#13300 and `detect_venv`.
5. **Bump the markers** — update `ZED_PREVIEW_DOC_VERSION`, `LAST_UPDATED`, and the
   Current baseline table to the new version.
6. Pair every technical note with a plain-English line (Gavin's standing preference).

---

## Sources

- Zed Preview releases — <https://zed.dev/releases/preview>
- Latest Preview — <https://zed.dev/releases/preview/latest>
- GitHub releases — <https://github.com/zed-industries/zed/releases>
- Releasebot mirror — <https://releasebot.io/updates/zed>
