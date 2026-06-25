# Claude attribution commit trailers (auto-stamp, global)

Automatically stamp every git commit made inside a Claude Code session with five
independent, machine-parseable trailers identifying the originating session and its
commit context, and hand each running session its own identity. Works in **every
repo** with no per-repo setup, because it rides the same global git-hook chainer used
by the pnpm-audit hook.

```
C-Sess-Id:  <local session UUID>                  # from $CLAUDE_SESSION_ID; maps to the on-disk transcript
C-Web-Id:   https://claude.ai/code/session_<id>   # harvested from the harness-appended line; blank if unavailable
C-Branch:   <branch>                              # commit's branch (blank on detached HEAD)
C-Worktree: <folder name>                         # worktree directory name (distinguishes forks in separate worktrees)
C-Wt-Path:  ~/path/to/worktree                    # worktree path, recorded $HOME-relative; absolute only outside $HOME
```

This is the hook-driven successor to the old **manual** convention where the model
appended a single `Claude-Session: <url>` trailer by hand. That key is **retired
going forward** -- the hook migrates it into `C-Web-Id`; existing history keeps its
`Claude-Session:` lines (no rewrite).

Why hyphens, not `C_Sess_ID`? git trailer tokens accept only `[A-Za-z0-9-]`; an
underscore disqualifies the token, so git renders it with a doubled separator and
`git interpret-trailers --parse` cannot see it. Hyphens keep the keys real, separable
trailers. The web id and the local UUID are two different identifiers for the same
session (the web id is exposed to no hook or env var -- only as text in the agent's
system prompt -- hence the harvest), so they get distinct keys; the hook never
collapses keys into each other or decides what a blank means. `C-Wt-Path` is recorded
relative to `$HOME` (e.g. `~/CODE/...`) so a machine-local username/layout never lands
in permanent, possibly-public history.

Shares the hook substrate documented in
[`PNPM_AUDIT_PREPUSH_HOOK.md`](./PNPM_AUDIT_PREPUSH_HOOK.md) and
[`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md) (the `_audit-chain` chainer + the
global `core.hooksPath`). Read those first if the routing is unfamiliar.

---

## TL;DR (deploy on a fresh machine)

Two halves. The git-hook half is **automatic** once the dotfiles are stowed; the
Claude settings entry is a **manual per-machine** step (that file is not in these
dotfiles).

```sh
# 1. Prereqs (usually already true after install.sh):
command -v jq                                      # REQUIRED for all steps; no jq -> no stamp (silent)
git config --show-origin --show-scope --get-all core.hooksPath  # must resolve to ~/.config/git/hooks (empty/non-zero = not enabled yet)
ls -l ~/.config/git/hooks/claude-session-env       # must be a stow symlink, executable

# 2. Register the SessionStart hook in ~/.claude/settings.json (NOT in these dotfiles).
#    Add this command to hooks.SessionStart, preserving any existing hooks:
#        "$HOME/.config/git/hooks/claude-session-env"
#    Easiest: use the Claude Code "update-config" skill (additive merge). Manual JSON below.

# 3. Start a FRESH Claude session (hooks load at session start), then verify:
echo "$CLAUDE_SESSION_ID"                           # must be non-empty in the new session
```

If `core.hooksPath` does not resolve to `~/.config/git/hooks`, turn the chainer
on first (see [`PNPM_AUDIT_PREPUSH_HOOK.md`](./PNPM_AUDIT_PREPUSH_HOOK.md)):
`./install.sh` (answer yes) or
`git config --file ~/.gitconfig.private core.hooksPath ~/.config/git/hooks`.

---

## Why this exists

Several Claude Code sessions are often run in parallel by forking one session and
pointing every fork at the **same working directory and same git branch**. They
share files and history live. That creates two gaps:

1. **A running session cannot learn its own identity.** There is no env var,
   tool, or command that hands a live Claude Code session its own `session_id`
   from inside the conversation. So a fork cannot reliably label its own work.
2. **Commits on one shared branch are not attributable.** Git history is a single
   stream with no record of which fork produced which commit; different forks end
   up sincerely claiming the same commits.

This feature closes both gaps automatically, with no manual steps per commit:

- A **`SessionStart` hook** captures the session id (the payload contains the local
  UUID; a name only on a future resume, never at startup) and exposes it for the
  rest of the session.
- The existing **`_audit-chain`** git-hook chainer gains one `prepare-commit-msg`
  step that stamps `C-Sess-Id` (the local UUID) and `C-Web-Id` (the claude.ai URL,
  harvested from the harness-appended `Claude-Session:` line) on every commit made
  inside a Claude session.

---

## How it works (data flow)

```
Claude session starts
   |
   v
SessionStart hook: ~/.config/git/hooks/claude-session-env   (registered in ~/.claude/settings.json)
   | reads JSON on stdin: { session_id, transcript_path, cwd, source, model }   (NO session_title at startup, NO web id)
   |-- writes  export CLAUDE_SESSION_ID=...     -> $CLAUDE_ENV_FILE
   |   writes  export CLAUDE_SESSION_NAME=...   -> $CLAUDE_ENV_FILE   (only if a name is ever present, e.g. resume)
   |-- prints  {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Session identity: ..."}}
   v
Claude Code sources $CLAUDE_ENV_FILE into every later Bash tool command this session
   |
   v
git commit  (run by the Bash tool, so it inherits CLAUDE_SESSION_ID)
   |   the agent may still append a "Claude-Session: <url>" line per its harness directive
   v
git runs prepare-commit-msg from the GLOBAL core.hooksPath (~/.config/git/hooks)
   | that path is a symlink to _audit-chain
   v
_audit-chain step 3 (prepare-commit-msg only), when CLAUDE_SESSION_ID is set OR a URL is present:
   1. harvest the web URL from any "Claude-Session: <url>" line (strip only the key + spaces; the URL's ':' survives)
   2. delete the old "Claude-Session:" line (migrate the format; existing history is NOT rewritten)
   3. read commit context from git: branch (symbolic-ref), worktree name + $HOME-relative path (rev-parse)
   4. stamp, idempotent per key (skip a key already present):
          C-Sess-Id:  <CLAUDE_SESSION_ID, or blank>
          C-Web-Id:   <harvested URL, or blank>
          C-Branch:   <branch, or blank on detached HEAD>
          C-Worktree: <worktree folder name>
          C-Wt-Path:  <~/...-relative worktree path>
```

Key dependency: the env handoff is `CLAUDE_ENV_FILE`. A SessionStart hook appends
shell `export` lines to the file at `$CLAUDE_ENV_FILE`; Claude Code then makes
those vars available to the shell of every subsequent `Bash` tool call (and thus
to any `git` subprocess they spawn). That is why a git hook can see
`CLAUDE_SESSION_ID` even though git itself knows nothing about Claude.

---

## Components

Three pieces. The first two are **in these dotfiles** (canonical source - do not
duplicate their bodies here; read the files, they travel via stow on a fresh
clone). The third is **not** in these dotfiles.

| #   | Component                                                  | Where it lives                                                                          | Canonical source                                |
| --- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 1   | `claude-session-env` (SessionStart identity script)        | `home/.config/git/hooks/claude-session-env` -> `~/.config/git/hooks/claude-session-env` | the file itself (committed)                     |
| 2   | `_audit-chain` step 3 (`prepare-commit-msg` trailer stamp) | `home/.config/git/hooks/_audit-chain` (the `# 3.` block)                                | the file itself (committed)                     |
| 3   | SessionStart registration                                  | `~/.claude/settings.json` -> `hooks.SessionStart`                                       | **this doc** (PAI-managed; not in the dotfiles) |

### 1. `claude-session-env`

A SessionStart hook (its name is deliberately **not** a git-hook name, so git
never invokes it and `_audit-chain`'s basename dispatch ignores it). On stdin it
receives the SessionStart JSON payload. It:

- reads `session_id` (UUID) and `session_title` with `jq`. Verified 2026-06-22: the
  startup payload has NO `session_title` (a `/rename` happens _after_ SessionStart
  fires), so `CLAUDE_SESSION_NAME` is normally empty; the read is kept inert in case
  a future `resume` payload ever carries it;
- appends `export CLAUDE_SESSION_ID=...` (and `export CLAUDE_SESSION_NAME=...` only
  when a name is present) to `$CLAUDE_ENV_FILE`;
- prints a `hookSpecificOutput.additionalContext` line so the model learns its own
  name/id.
  Fail-open: it never exits non-zero. Requires `jq`; if `jq` is missing it degrades
  quietly to no identity (no stamp), never an error. Read the file header for the
  full rationale.

### 2. `_audit-chain` step 3

An additive block in the existing chainer that runs **only** for
`prepare-commit-msg`, and only when `CLAUDE_SESSION_ID` is set OR a `Claude-Session:`
URL is present (so non-Claude commits stay untouched). It: (1) **sources** the web
URL -- from `$CLAUDE_WEB_URL` if ever set, else harvested from a `^Claude-Session:`
line (stripping only the key + spaces so the URL's own `:` survives), else blank;
(2) **migrates** by deleting any old `^Claude-Session:` line (portable in-place
`sed`: GNU `-i`, BSD `-i ''`); (3) **reads commit context** from git (branch via
`symbolic-ref`, worktree name + `$HOME`-relative path via `rev-parse`); (4) **stamps**
`C-Sess-Id`, `C-Web-Id`, `C-Branch`, `C-Worktree`, `C-Wt-Path` with
`git interpret-trailers --in-place` (plain-append fallback), each guarded by its own
`^<key>:` grep so `--amend` never doubles. Empty values are emitted as-is
(blank-tolerant). Steps 1 (delegate to the repo's own hook) and 2 (pre-push pnpm
audit) are unchanged.

### 3. SessionStart registration in `~/.claude/settings.json`

This is the only artifact NOT carried by the dotfiles. Add the command to
`hooks.SessionStart`, **preserving every existing hook** (PAI ships its own
SessionStart hooks). The exact entry to add:

```json
{
  "type": "command",
  "command": "\"$HOME/.config/git/hooks/claude-session-env\""
}
```

Append it either as another entry in the existing SessionStart group's `hooks`
array, or as a new group object in the `SessionStart` array - both work. The
embedded double-quotes around `$HOME/...` tolerate spaces in the path; `$HOME`
expands via the shell, so the same entry works on every machine. Example shape
after the edit (existing PAI hooks shown abbreviated, MUST be preserved):

```json
"SessionStart": [
  {
    "hooks": [
      { "type": "command", "command": "${PAI_DIR}/hooks/KittyEnvPersist.hook.ts" },
      { "type": "command", "command": "${PAI_DIR}/hooks/LoadContext.hook.ts" },
      { "type": "command", "command": "bun ${PAI_DIR}/hooks/handlers/BuildCLAUDE.ts" },
      { "type": "command", "command": "\"$HOME/.config/git/hooks/claude-session-env\"" }
    ]
  }
]
```

Recommended: use the Claude Code **`update-config`** skill, which reads the file,
merges additively, and keeps it valid JSON. If you hand-edit, validate after:
`jq -e . ~/.claude/settings.json`.

---

## Decisions (locked - do not re-litigate)

- **Trailer keys (five):** `C-Sess-Id` (local UUID), `C-Web-Id` (claude.ai URL),
  `C-Branch` (commit's branch), `C-Worktree` (worktree folder name), `C-Wt-Path`
  (worktree path). Hyphens, never underscores: git trailer tokens are `[A-Za-z0-9-]`
  only, so `C_Sess_ID` is not a valid trailer (doubled separator, invisible to
  `git interpret-trailers --parse`). The retired `Claude-Session:` key is migrated
  into `C-Web-Id` going forward.
- **Trailer values:** `C-Sess-Id` = `$CLAUDE_SESSION_ID`; `C-Web-Id` = the harvested
  claude.ai URL; `C-Branch` / `C-Worktree` / `C-Wt-Path` = git commit context read at
  commit time. Any may be **blank** when unavailable (e.g. `C-Branch` on a detached
  HEAD) -- the hook emits the key with an empty value and makes NO semantic decision
  about what blank means (downstream decides). No fallback, no collapsing keys.
- **Web id is harvested, not env-sourced.** The claude.ai web id is exposed to no
  hook or env var (confirmed via the live SessionStart payload + Claude Code docs) --
  it exists only as text in the agent's system prompt. So the hook harvests it from
  the `Claude-Session: <url>` line the harness still has the agent append.
- **Idempotent per key:** each of the five keys is re-added only if its own `^<key>:`
  line is absent (`interpret-trailers` alone doubles on `--amend`; the per-key grep
  guard is the real mechanism).
- **`C-Wt-Path` is recorded `$HOME`-relative** (`~/CODE/...`), never the literal
  absolute path. The feature is global (every repo, including public ones), and an
  absolute path would write the local username + directory layout into permanent
  history, linking the local account to the public one -- the same linkage we avoid
  elsewhere. A path outside `$HOME` stays absolute. Context is read at commit time:
  `C-Wt-Path`/`C-Worktree` from `git rev-parse --show-toplevel`, `C-Branch` from
  `git symbolic-ref --short -q HEAD` (blank when detached).
- **Empty-value trailers** survive on git 2.50.1 (verified) -- no trailing-space hack
  needed; on older git that strips them, the `printf` fallback still writes the key.
- **Identity source:** `CLAUDE_SESSION_ID` (and `CLAUDE_SESSION_NAME` when present),
  exported by the SessionStart hook via `CLAUDE_ENV_FILE`.
- **Fail-open:** the SessionStart hook never blocks a session from starting.
- **`core.hooksPath` is not touched by this feature.** It lives in per-machine
  `~/.gitconfig.private` (managed by `install.sh setup_pnpm_audit_hooks`). Do not
  move it; never write it into a tracked/stowed file.
- **ASCII only** in the script's display strings (`--`, not Unicode em-dashes).

---

## Deployment on a fresh machine (full runbook)

### Automatic (comes with the dotfiles)

1. Clone the dotfiles and run `./install.sh` (stows `home/`). This brings:
   - `~/.config/git/hooks/claude-session-env` (the SessionStart script), and
   - the patched `~/.config/git/hooks/_audit-chain` (with step 3),
     both as stow symlinks into the repo.
2. During `install.sh`, accept the **pnpm-audit pre-push hook** prompt. That writes
   `core.hooksPath = ~/.config/git/hooks` into `~/.gitconfig.private` - the routing
   this feature needs. (Same enablement as
   [`PNPM_AUDIT_PREPUSH_HOOK.md`](./PNPM_AUDIT_PREPUSH_HOOK.md).) Two gotchas:
   - The prompt **defaults to No** (`[y/N]`) - type `y` explicitly; a blank Enter
     skips it and the feature is not wired.
   - The prompt only appears if `pnpm-audit-hook` is on PATH (stowed to
     `~/.local/bin`). If you never see it, check `command -v pnpm-audit-hook`, then
     either re-run `./install.sh` or set the routing directly:
     `git config --file ~/.gitconfig.private core.hooksPath ~/.config/git/hooks`.
3. Ensure `jq` is installed (Homebrew/apt) - a prerequisite for the identity hook,
   the `update-config` / `jq -e .` validation, and the verification commands below
   (install it FIRST if working top to bottom). Without it the stamp silently no-ops.

### Manual (per machine, not carried by the dotfiles)

4. Register the SessionStart hook in `~/.claude/settings.json` (see Component 3).
   Use the `update-config` skill or hand-edit + `jq -e .` validate. Preserve
   existing hooks.
5. Start a **fresh** Claude session. Hooks load at session start, so the feature
   is inert in the session that deployed it.

### Per-clone caveat

`core.hooksPath` is per-clone and not version-controlled. If a specific repo has a
**local** `core.hooksPath` (its own `.git/config`, e.g. husky/lefthook, or a stray
leftover), the global chainer is bypassed in that repo and neither the trailer nor
the pre-push audit fires there. Diagnose + fix per the Gotchas below.

---

## Verification

**Status: five-key scheme verified 2026-06-22** (scratch-repo tests against the real
hook). id-only commit -> `C-Sess-Id` + blank `C-Web-Id` + `C-Branch` / `C-Worktree` /
`C-Wt-Path`; a harness `Claude-Session: <url>` line -> migrated into `C-Web-Id` (URL
intact) with the old line removed; a linked worktree yields its own `C-Worktree` name
and `C-Branch`; `C-Wt-Path` renders `$HOME`-relative (`~/...`); detached HEAD -> blank
`C-Branch`; `--amend` does not double any key; a non-Claude commit is untouched;
pre-push delegation + audit still fire. The live SessionStart payload was captured to
confirm there is no web-id and no `session_title` field. Re-run the checks below on
each new machine.

### Pre-checks you can run in the CURRENT session (no fresh session needed)

Simulate the env the SessionStart hook would set, and exercise the real path.

```sh
# (a) The identity script itself, on a sample payload:
printf '%s' '{"session_id":"demo123","session_title":"falcon"}' \
  | CLAUDE_ENV_FILE=/tmp/cse.env ~/.config/git/hooks/claude-session-env
cat /tmp/cse.env        # -> export CLAUDE_SESSION_ID=demo123 / export CLAUDE_SESSION_NAME=falcon
rm -f /tmp/cse.env

# (b) The trailer end-to-end, in a throwaway repo that inherits the global chainer.
#     The -c user.name / -c user.email are REQUIRED, not cosmetic: a /tmp scratch
#     repo matches no `includeIf gitdir:` rule in ~/.gitconfig.private, so it has no
#     identity. Without them the commit aborts with `fatal: empty ident name` BEFORE
#     prepare-commit-msg runs - a false-fail that looks like the trailer is broken
#     when it never even got a chance to stamp.
tmp="$(mktemp -d)"; git -C "$tmp" init -q
# id-only: no Claude-Session line -> C-Sess-Id filled, C-Web-Id blank
CLAUDE_SESSION_ID=demo123 \
  git -C "$tmp" -c user.name="Test" -c user.email="test@example.com" \
    commit -q --allow-empty -m "test: id only"
git -C "$tmp" log -1 --format='%(trailers:only,unfold)'   # -> C-Sess-Id: demo123 / C-Web-Id: (blank) / C-Branch / C-Worktree / C-Wt-Path
# harvest: a harness Claude-Session: line is migrated into C-Web-Id, old line removed
CLAUDE_SESSION_ID=demo123 \
  git -C "$tmp" -c user.name="Test" -c user.email="test@example.com" \
    commit -q --allow-empty -m "test: harvest

Claude-Session: https://claude.ai/code/session_01ABC"
git -C "$tmp" log -1 --format='%(trailers:only,unfold)'   # -> C-Web-Id now = https://claude.ai/code/session_01ABC (plus C-Sess-Id / C-Branch / C-Worktree / C-Wt-Path)
rm -rf "$tmp"
```

Note: in a `/tmp` scratch repo `C-Wt-Path` is absolute (the repo is outside `$HOME`);
under `$HOME` it renders `~/...`. `C-Branch` reflects your `init.defaultBranch`.

Expected matrix (Claude commits always also carry `C-Branch` / `C-Worktree` /
`C-Wt-Path`): id set, no URL -> `C-Sess-Id: <id>` + blank `C-Web-Id:`; a
`Claude-Session: <url>` line present -> that line removed and `C-Web-Id: <url>` (URL
colons intact) plus `C-Sess-Id: <id>`; no `CLAUDE_SESSION_ID` and no `Claude-Session:`
line -> no `C-` trailers (non-Claude commit untouched); detached HEAD -> blank
`C-Branch`; linked worktree -> `C-Worktree` is its folder name; re-run / `--amend` ->
no key doubled.

Two output notes: (a) check (a)'s script also prints a `hookSpecificOutput` JSON
block to stdout (the model-context injection - expected) in addition to the
`export` lines it writes to `$CLAUDE_ENV_FILE`. (b) if check (b)'s final `git log`
prints NOTHING, the scratch repo is not routing through the chainer - your global
`core.hooksPath` is not `~/.config/git/hooks` yet (enable it, see the runbook).
Empty output here means "not enabled," not "broken."

### Live checks in a FRESH session (the real proof)

1. `echo "$CLAUDE_SESSION_ID"` -> must be populated (proves the SessionStart export
   reached the Bash environment; if empty, nothing downstream works).
2. The session should be able to state its own name/id (proves `additionalContext`
   injection).
3. Make a real commit and check `git log -1 --format='%(trailers:only,unfold)'` ->
   `C-Sess-Id:` (and `C-Web-Id:`) are present, in the trailer block.

---

## Gotchas, pitfalls, and things to check against

- **A brand-new machine has NO `~/.gitconfig.private` (it is gitignored, never
  committed) - so commits fail on IDENTITY before attribution is even reached.**
  Until you create that file, git has no `[user]` identity (it lives there, scoped
  per-account via `includeIf`, not in the public `~/.gitconfig`), so EVERY real
  commit aborts with `fatal: empty ident name`. That failure is independent of this
  feature: it happens before the `prepare-commit-msg` hook runs, so it is not a
  trailer bug. Order of operations on a new machine: create `~/.gitconfig.private`
  with your identity (and the `core.hooksPath` line, see the runbook) FIRST; only
  then do the live checks above mean anything. Note the scratch-repo pre-check (b)
  deliberately passes `-c user.name/-c user.email` so it can be run before the
  private file exists - a real repo gets no such shortcut.

- **`~/.claude/settings.json` is PAI-managed, NOT stow-managed by these dotfiles.**
  It is a real file (not a symlink into this repo). Consequences: (a) edit it
  directly (or via `update-config`), not a dotfiles "source"; (b) the SessionStart
  registration is a **separate per-machine step** and is NOT propagated by stow -
  every new machine needs the **Manual** runbook step (the settings.json
  registration) done by hand. Confirm it is hand/skill-maintained
  (not regenerated by a PAI build) before relying on a manual edit persisting.

- **`core.hooksPath` can have up to three definitions; `git config --get` hides
  all but the winner.** Sources, precedence LOCAL > global:
  1. `~/.gitconfig.private` (global; the legit install.sh value);
  2. `~/.gitconfig` (global; only ever appears as pollution - it is a stow symlink
     into the repo);
  3. `<repo>/.git/config` (LOCAL; wins).
     Always diagnose with `git config --show-origin --show-scope --get-all
core.hooksPath`, never a bare `--get` from inside a repo (it merges repo-local
     and the local value wins, masking the global state).

- **A repo-local `core.hooksPath` override silently disables this feature in that
  repo.** If a clone points git at its own `.git/hooks` (or husky/lefthook), the
  global chainer is bypassed -> no trailer, no pre-push audit there. To restore the
  global chainer for a repo you control:
  `git config --local --unset core.hooksPath` (per-clone; needed on each machine).
  **Do NOT auto-unset local overrides across repos** - husky/lefthook set them on
  purpose, and unsetting would break those projects.

- **Never write `core.hooksPath` (or any machine-specific path) into a tracked /
  stowed file.** `~/.gitconfig` is a stow symlink into `home/.gitconfig`, so
  `git config --global core.hooksPath ...` pollutes the tracked file with an
  absolute, machine-specific path. Use `git config --file ~/.gitconfig.private`.
  See [`feedback`-style note in] the SSH/credentials docs and the install.sh
  comment at `setup_pnpm_audit_hooks`.

- **`jq` is required by `claude-session-env`.** If absent, it degrades quietly to
  no identity (no stamp) rather than erroring. Install `jq` on every machine.

- **The script name must not be a git-hook name.** `claude-session-env` matches no
  hook name, so git never runs it and `_audit-chain` ignores it. Do not rename it
  to a hook name.

- **Edit the dotfiles SOURCE, then re-stow.** The hook files in
  `~/.config/git/hooks/` are symlinks into `home/.config/git/hooks/`. Edit the
  repo source and run `stow -R --no-folding -d <repo> -t "$HOME" home` (this is
  what `install.sh` does).

- **Hooks activate in the NEXT session.** A SessionStart/settings.json change does
  nothing for the session that made it. In a session that predates the feature,
  `CLAUDE_SESSION_ID` is empty, so step 3 runs only via the relaxed guard if the
  agent's manual `Claude-Session:` line is present -- harvesting it into `C-Web-Id`
  (and dropping the old line); otherwise the message is left untouched.

- **Claude Code version.** `CLAUDE_ENV_FILE` (the load-bearing env handoff), the
  SessionStart stdin `session_id`, and `hookSpecificOutput.additionalContext` are
  documented Claude Code hook features in recent versions. Note: `session_title` is
  NOT in the startup payload (a `/rename` is post-startup), and the claude.ai web id
  is in no payload or env var at all -- which is why `C-Web-Id` is harvested. If
  `echo "$CLAUDE_SESSION_ID"` is empty in a fresh session on an old build, update
  Claude Code.

- **Do NOT enable `attribution.sessionUrl` (Claude Code v2.1.183+).** That native
  Claude Code setting omits the `Claude-Session: <url>` line from commits/PRs (it
  targets web / Remote-Control sessions especially) -- but that line is exactly what
  step 3 harvests into `C-Web-Id`. Turn it on and `C-Web-Id` silently goes blank while
  the other four keys keep working. If a future commit shows a blank `C-Web-Id` where a
  URL was expected, check this setting first. `C-Sess-Id` is unaffected -- it comes from
  `CLAUDE_SESSION_ID`, not the harvested line.

- **A PostToolUse formatter may reformat `~/.claude/settings.json` after an edit.**
  Re-validate with `jq -e . ~/.claude/settings.json` and re-check the hook is still
  present after editing.

- **Idempotency relies on per-key `^C-Sess-Id:` / `^C-Web-Id:` greps**
  (case-insensitive, line-anchored) -- `interpret-trailers` alone re-adds on
  `--amend`, so the grep guard is what prevents doubling. Separately, the
  harvest+migrate step matches `^Claude-Session:` (case-insensitive) to pull the URL
  and delete the retired line. Keep all three key spellings exact.

---

## Troubleshooting (trailer not appearing)

Run, in order:

1. `echo "$CLAUDE_SESSION_ID"` empty? -> you are in a session that started before
   the SessionStart hook was registered/active, or the hook is not registered.
   Check `jq -e '.hooks.SessionStart' ~/.claude/settings.json` lists
   `claude-session-env`, then start a fresh session.
2. `git config --show-origin --show-scope --get-all core.hooksPath` -> winner must
   be `~/.config/git/hooks`. If a local `.git/config` value wins, unset it
   (`git config --local --unset core.hooksPath`).
3. `ls -l ~/.config/git/hooks/prepare-commit-msg` -> must symlink to `_audit-chain`.
   If missing, re-stow.
4. `command -v jq` -> if absent, install it (no jq = no identity = no stamp).
5. Confirm the script is executable: `test -x ~/.config/git/hooks/claude-session-env`.
6. Reproduce with the Verification pre-checks above (simulated id) to isolate
   script vs env-handoff vs routing.

---

## References

- Hook substrate / global routing: [`PNPM_AUDIT_PREPUSH_HOOK.md`](./PNPM_AUDIT_PREPUSH_HOOK.md), [`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md)
- Canonical code: `home/.config/git/hooks/claude-session-env`, `home/.config/git/hooks/_audit-chain`
- core.hooksPath pollution rationale: `home/.gitconfig` comments + `install.sh` `setup_pnpm_audit_hooks`
- Shipped: commit `64c9b76` introduced the single-key `Claude-Session:` hook; the
  2026-06-22 migration replaced it with five keys (`C-Sess-Id`, `C-Web-Id`, `C-Branch`,
  `C-Worktree`, `C-Wt-Path`; harvest + format migration). The `~/.claude/settings.json`
  entry is per-machine and not in this repo.
