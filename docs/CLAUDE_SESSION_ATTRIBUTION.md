# Claude-Session commit attribution (auto-stamp, global)

Automatically stamp every git commit made inside a Claude Code session with a
`Claude-Session:` trailer identifying the originating session (and fork name),
and hand each running session its own identity. Works in **every repo** with no
per-repo setup, because it rides the same global git-hook chainer used by the
pnpm-audit hook.

This is the hook-driven replacement for the old **manual** convention where the
model appended a `Claude-Session:` trailer by hand per its commit instructions.

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

- A **`SessionStart` hook** captures the session id and name (from the hook
  payload, which does contain them) and exposes them for the rest of the session.
- The existing **`_audit-chain`** git-hook chainer gains one `prepare-commit-msg`
  step that stamps a `Claude-Session:` trailer on every commit made inside a
  Claude session.

---

## How it works (data flow)

```
Claude session starts
   |
   v
SessionStart hook: ~/.config/git/hooks/claude-session-env   (registered in ~/.claude/settings.json)
   | reads JSON on stdin: { session_id, session_title?, ... }
   |-- writes  export CLAUDE_SESSION_ID=...     -> $CLAUDE_ENV_FILE
   |   writes  export CLAUDE_SESSION_NAME=...   -> $CLAUDE_ENV_FILE   (only if named)
   |-- prints  {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Session identity: ..."}}
   v
Claude Code sources $CLAUDE_ENV_FILE into every later Bash tool command this session
   |
   v
git commit  (run by the Bash tool, so it inherits CLAUDE_SESSION_ID / CLAUDE_SESSION_NAME)
   |
   v
git runs prepare-commit-msg from the GLOBAL core.hooksPath (~/.config/git/hooks)
   | that path is a symlink to _audit-chain
   v
_audit-chain step 3 (prepare-commit-msg only):
   if CLAUDE_SESSION_ID set and no existing "Claude-Session:" trailer:
       append  "Claude-Session: <id> (<name>)"   (or "<id>" alone if unnamed)
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

- reads `session_id` and (when the session is named) `session_title` with `jq`;
- appends `export CLAUDE_SESSION_ID=...` and `export CLAUDE_SESSION_NAME=...` to
  `$CLAUDE_ENV_FILE`;
- prints a `hookSpecificOutput.additionalContext` line so the model learns its own
  name/id.
  Fail-open: it never exits non-zero. Requires `jq`; if `jq` is missing it degrades
  quietly to no identity (no stamp), never an error. Read the file header for the
  full rationale.

### 2. `_audit-chain` step 3

An additive block in the existing chainer that runs **only** for
`prepare-commit-msg`. If `CLAUDE_SESSION_ID` is set and the message does not
already contain a `^Claude-Session:` line, it appends
`Claude-Session: <id> (<name>)` (id-only when unnamed) using
`git interpret-trailers --in-place` (falling back to a plain append). Steps 1
(delegate to the repo's own hook) and 2 (pre-push pnpm audit) are unchanged.

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

- **Trailer key:** `Claude-Session:` (automates the existing manual convention; do
  not invent a new key).
- **Trailer value:** `<session-id> (<fork-name>)`; when unnamed, `<session-id>`
  alone.
- **Idempotent:** if a `Claude-Session:` trailer is already present (manual add /
  amend / cherry-pick), do not add a second one.
- **Identity source:** `CLAUDE_SESSION_ID` / `CLAUDE_SESSION_NAME`, exported by
  the SessionStart hook via `CLAUDE_ENV_FILE`.
- **Fail-open:** the SessionStart hook never blocks a session from starting.
- **`core.hooksPath` is not touched by this feature.** It lives in per-machine
  `~/.gitconfig.private` (managed by `install.sh setup_pnpm_audit_hooks`). Do not
  move it; never write it into a tracked/stowed file.
- **ASCII only** in the script's display strings (the brief used Unicode em-dashes;
  they are written as `--` here, the repo convention).

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

**Status: confirmed working 2026-06-21.** In a fresh (unnamed) session,
`CLAUDE_SESSION_ID` was populated and a scratch-repo commit was auto-stamped
`Claude-Session: <id>` (id-only) by the hook, with no manual add. Not yet
exercised live: the named `<id> (<name>)` path (needs a named session) and
fork-distinct ids (needs two forked sessions sharing one branch). Re-run the
checks below on each new machine.

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
CLAUDE_SESSION_ID=demo123 CLAUDE_SESSION_NAME=falcon \
  git -C "$tmp" -c user.name="Test" -c user.email="test@example.com" \
    commit -q --allow-empty -m "test: verify trailer"
git -C "$tmp" log -1 --format='%(trailers:only,unfold)'   # -> Claude-Session: demo123 (falcon)
rm -rf "$tmp"
```

Expected matrix: named -> `Claude-Session: <id> (<name>)`; unnamed (no
`CLAUDE_SESSION_NAME`) -> `Claude-Session: <id>`; no `CLAUDE_SESSION_ID` -> no
trailer; message already carrying a `Claude-Session:` line -> not doubled.

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
   the `Claude-Session:` trailer is present, in the trailer block.

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
  `CLAUDE_SESSION_ID` is empty, so step 3 correctly skips and commits stay
  instruction-driven (the model still adds the manual trailer per its commit
  instructions). Both can coexist - idempotency prevents doubling.

- **Claude Code version.** `CLAUDE_ENV_FILE` (the load-bearing env handoff),
  the SessionStart stdin fields (`session_id`, `session_title`), and
  `hookSpecificOutput.additionalContext` are all documented Claude Code hook
  features available in recent versions. If `echo "$CLAUDE_SESSION_ID"` is empty in
  a fresh session on an old build, update Claude Code.

- **A PostToolUse formatter may reformat `~/.claude/settings.json` after an edit.**
  Re-validate with `jq -e . ~/.claude/settings.json` and re-check the hook is still
  present after editing.

- **Idempotency relies on the `^Claude-Session:` grep.** The check is
  case-insensitive and anchored to line start; keep the trailer key exactly
  `Claude-Session:` so manual and hook-driven trailers de-duplicate.

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
- Shipped: commit `64c9b76` (git-hooks half). The `~/.claude/settings.json` entry is per-machine and not in this repo.
