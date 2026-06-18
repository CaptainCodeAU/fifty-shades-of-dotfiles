# Zed Preview — Changelog Tracker

<!-- ZED_PREVIEW_DOC_VERSION: 1.8.0 -->
<!-- LAST_UPDATED: 2026-06-18 -->

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

| Field                  | Value        |
| ---------------------- | ------------ |
| Latest Preview tracked | **1.8.0**    |
| Release date           | 2026-06-17   |
| GitHub tag             | `v1.8.0-pre` |
| Doc last refreshed     | 2026-06-18   |

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

| Item                               | Status as of 2026-06-18               | Why it matters                |
| ---------------------------------- | ------------------------------------- | ----------------------------- |
| Per-project themes (zed#13300)     | **Open PR #58755** — not merged/1.8.0 | Gavin's color-per-window goal |
| `theme_overrides` at project level | Still user-settings only              | PR #58755 sidesteps it (DB)   |
| `detect_venv` default              | Still on by default                   | direnv double-activation      |

**PR #58755 "Add per-window theme overrides"** (author 42piratas; opened 2026-06-06;
open / not merged / not draft; last activity 2026-06-07; base `main`; no milestone;
9 files, +480/-39). Each window gets its own theme via new actions **`theme: project`**
and **`theme: clear project`**; choices persist in a new `window_theme_overrides` DB
table keyed by `WindowId` — **not** in `settings.json` or project files. That means it
won't collide with the skip-worktree'd settings file and needs no committed per-project
config. If merged, it obsoletes the `--user-data-dir` workaround. Gavin is on record
backing this on accessibility grounds in **discussion #24010** (comment 17160732,
2026-06-03). It's not the `title_bar.background` approach he proposed, but it meets the
core goal. Watch for merge.

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
