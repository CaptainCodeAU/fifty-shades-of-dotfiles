# Zed Preview — Changelog Tracker

<!-- ZED_PREVIEW_DOC_VERSION: 1.16.1 -->
<!-- LAST_UPDATED: 2026-08-19 -->

> **What this is.** A living record of notable **Zed Preview** changes, filtered to
> what Gavin cares about: **user interface**, **configuration / settings**, and
> **themes / appearance** — both new features and fixes.
>
> **How it stays current.** `.claude/hooks/zed-version-check.sh` runs at session start
> and does two checks: it compares the version recorded above (`ZED_PREVIEW_DOC_VERSION`)
> against the latest Zed Preview release on GitHub, and it polls the merge status of
> watched upstream PRs (currently **#58755**, per-window themes) live every session. If a
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
- **Per-project themes are wanted; now an open PR** (`project_zed_per_project_theme`).
  Tracked upstream at **zed#13300**; **PR #58755** (open, not merged) implements
  per-window themes, stored in Zed's DB rather than `settings.json`. Until it merges,
  the workaround is `zed --user-data-dir <path>`. (See standing watch-items below.)
  - _In plain English:_ Gavin wants a different color per open window; someone has now
    built it (PR #58755) and it's awaiting merge — watch for it landing.
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

| Item                               | Status as of 2026-08-19                | Why it matters                |
| ---------------------------------- | -------------------------------------- | ----------------------------- |
| Per-project themes (zed#13300)     | **Open PR #58755** — not merged/1.16.1 | Gavin's color-per-window goal |
| `theme_overrides` at project level | Still user-settings only               | PR #58755 sidesteps it (DB)   |
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

When refreshing this doc, re-check each row against the new release.

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
