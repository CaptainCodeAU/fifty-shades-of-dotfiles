# ci-watch — an escalating, un-ignorable CI-status line in the session dashboard

A red CI that nobody notices is as useless as no CI. This watcher puts the CI
status of repos you care about into the session-start dashboard — alongside the
[Zed-PR](ZED_PREVIEW_CHANGELOG.md) and [toolchain-CVE](TOOLCHAIN_CVE_CHECK.md)
watchers — and is built so a red result **cannot become wallpaper**.

## Why it exists

A sibling repo's CI was red for ~25 commits and nobody noticed — not because there
was no signal, but because the signal (GitHub "workflow failed" emails) was
**passive and identical every time**, so it habituated and got tuned out. Passive,
repeating alerts fail. The fix has to be **exception-based** (silent when fine, loud
when broken), **escalating** (louder the longer it stays broken), and
**dismiss-only-by-fixing** (you can't make it go away just by seeing it).

## What it does

| State                                     | Surface                                                 |
| ----------------------------------------- | ------------------------------------------------------- |
| **green**                                 | one dim, near-invisible line — no habituation surface   |
| **red, day 0–2** (tier 1)                 | a red banner                                            |
| **red, day 3–6** (tier 2)                 | a louder boxed banner **+ a spoken alert**              |
| **red, day 7+** (tier 3)                  | the strongest banner + a spoken alert every session     |
| **snoozed**                               | a single dim "snoozed Nd" line (deliberate, time-boxed) |
| **offline / unknown, but last-known red** | the banner persists (stale-flagged)                     |

Key properties:

- **Dismiss-only-by-fixing.** A red banner clears **only** when CI goes green, or when
  you run a deliberate `ci-watch --snooze`. Merely seeing it never clears it — that is
  the whole point (a persistence counter alone still habituates; "day 12, whatever").
- **Voice varies by day count** ("…red for 4 days") and fires on the green→red
  transition, so the audio itself doesn't become monotone wallpaper.
- **Offline-sticky.** A transient network/`gh` outage does not silence a known red —
  the last-known-red banner persists, flagged stale, until a definite green clears it.

## How it runs

- **Engine:** `home/.local/bin/ci-watch` (bash, stow-deployed to `~/.local/bin`).
  Read-only to your repos; the only writes are escalation state under
  `${XDG_STATE_HOME:-~/.local/state}/ci-watch/`. Queries `gh` live each session and
  falls back to a per-target cache when offline. The render path always exits 0.
- **Wiring (global, the active setup):** a `SessionStart` hook in **`~/.claude/settings.json`**
  runs `~/.local/bin/ci-watch` (guarded: `test -x … && … || true`), so the dashboard appears
  in **every** repo's session — not just this one. `~/.claude` is machine-local and untracked,
  so this hook is a one-time manual add, not versioned here.
- **Wiring (per-project, optional):** `.claude/hooks/ci-watch.sh` is a thin wrapper that
  locates the engine and runs it; drop it into any project's `.claude/settings.json`
  `SessionStart` if you want per-repo wiring instead of (or before) the global hook.
- **Self-suggest:** in any repo that has `.github/workflows` but isn't on the watchlist, the
  render adds one dim line — `untracked CI: <owner/repo> … add: ci-watch --add .` — so a
  coverage gap surfaces itself instead of relying on anyone to remember.

```bash
ci-watch                       # render the dashboard line (what the hook runs)
ci-watch --add .               # add the CURRENT repo (derives owner/repo@branch)
ci-watch --add <o/r@branch> "label"   # add a specific target
ci-watch --snooze <repo> <d>   # deliberately silence a red target for <d> days
ci-watch --list                # show the watchlist
ci-watch --json                # machine-readable status per target
```

`gh` advisory: the live query needs `gh` + `$GH_TOKEN`, which are present **inside
Claude Code sessions** (the read-only token from `_claude_launch`). In a plain shell
without them, the watcher reports a one-line _skipped_ and never errors — a skip is
never a false "green".

## The watchlist (privacy)

The engine is generic and committed. Your **real** repo list is machine-local and
**gitignored** — the repo is public, and real `owner/repo` names must never land in
it (the same rule as [`~/.ssh/config.local`](../docs/SECURITY.md)).

- Committed, placeholders only: `home/.config/ci-watch/watchlist.example`
- Real, gitignored, never committed: `~/.config/ci-watch/watchlist`

```text
# ~/.config/ci-watch/watchlist  (one target per line)
owner/repo@branch | optional label
owner/repo                       # omit @branch -> latest run on any branch
```

`home/.config/ci-watch/watchlist` is in `.gitignore`, so even a copy placed in the
stow source tree can't be committed by accident.

## Companion change: worktree hook fallback (`_audit-chain`)

Shipped in the same change: the global git-hook dispatcher
(`home/.config/git/hooks/_audit-chain`) now falls back to the **common-dir** hook when
a linked `git worktree` has no per-worktree hook. Previously a hook installed in the
main checkout silently did **not** run for commits made from a worktree (its
`--git-dir` is `.git/worktrees/<name>`, whose `hooks/` is empty). The fallback lets a
worktree **inherit** an explicitly-installed hook.

It only ever runs a hook you **deliberately installed** — it does **not** make the
dispatcher "pre-commit aware" (auto-running a repo's `.pre-commit-config.yaml` on
commit would execute any cloned repo's hook code = supply-chain RCE). The
explicit-install opt-in is a security property and is preserved.

## Related

- [`TOOLCHAIN_CVE_CHECK.md`](TOOLCHAIN_CVE_CHECK.md) — sibling session-start watcher
  (CVE exposure of pinned tool floors).
- [`ZED_PREVIEW_CHANGELOG.md`](ZED_PREVIEW_CHANGELOG.md) — the live "watched PRs"
  pattern this query path mirrors.
- [`CLAUDE_SESSION_ATTRIBUTION.md`](CLAUDE_SESSION_ATTRIBUTION.md) — the `_audit-chain`
  dispatcher whose worktree fallback shipped alongside this.
