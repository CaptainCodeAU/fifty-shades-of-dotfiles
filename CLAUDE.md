Default branch is `master`.

## Python

Use `uv run python3` instead of calling `python3` directly. (A shell wrapper intercepts bare `python`/`python3` and version-specific calls like `py313`/`py312` and redirects to `uv run` — but invoke `uv run` directly rather than relying on the wrapper, since non-interactive Bash-tool shells skip `.zshrc` and the wrapper is absent there.)
For standalone scripts needing third-party libs, use PEP 723 inline metadata (`# /// script` block) — `uv run` resolves it automatically.
Package management is `uv`, not pip/pipx: use `uv add` / `uv remove` (not `pip install` / `pip uninstall`), and `uv tool` (not `pipx`). The same wrapper-absence caveat applies — in the Bash tool, `pip install` hits real pip, so call `uv` directly.

## Node / JS package manager

Never use `npm` or `yarn`. Use `pnpm` (or `bun`). Pick by lockfile:

- `pnpm-lock.yaml` present → use pnpm.
- `bun.lockb` / `bun.lock` present → use bun.
- No lockfile → default to pnpm.
- Only `package-lock.json` or `yarn.lock` present → disregard them, use pnpm anyway (do not run npm/yarn to honor them).
  For one-off package execution prefer `pnpm dlx` over `npx`.

## Source files — encoding

Emit only ASCII punctuation in source code: straight quotes (`"` `'`), straight apostrophes, and hyphen-minus (`-`). Never write Unicode smart quotes (`“ ” ‘ ’`), en/em dashes (`– —`), or other Unicode punctuation into code files — they pass type-checks but break the build at transform time (the JS/TS build rejects them), and hunting them down afterward wastes a session. Unicode is fine in comments, docs, and string literals meant for display; never in identifiers, keys, or code tokens.

## Shell

Shell has `NULL_GLOB` + `nonomatch` — use `find -print` (not `ls glob*`) for file existence checks. Caveat: `find -print` exits 0 on an empty match only when the search root EXISTS; pointed at a missing path it still exits non-zero (1 on this BSD `find`). For a path that may not exist, use `test -e`/`test -d` (exits 0 either way, reports via its echo) or append `|| true` — otherwise the non-zero exit cancels batched siblings (see batching paragraph below).
For port listing use the `ports` function (OS-aware: `lsof` on macOS, `ss`/`netstat` on Linux/WSL) rather than calling those tools directly.

Never start a Bash command with `cd` — the harness hard-rejects any leading `cd` (it tells you to use `git -C <path>`, an absolute path, or `builtin cd`). This is a built-in Claude Code guard, not a repo hook. Treat the rejection as a signal to change the command _shape_ (reach for `git -C`/absolute paths), not to retry the same `cd`-prefixed command. A rejected `cd` exits non-zero, so if it was batched with sibling calls it cancels all of them (see next paragraph) — which reads as a "stuck loop" but is really one repeated mistake.

A non-zero exit from any Bash call cancels the other tool calls batched in the same message (Claude Code aborts parallel siblings on error). Never batch state-changing commands (`git add`/`commit`/`push`, file writes) in the same message as read-only probes — a probe that exits non-zero (e.g. `ls`/`grep`/`cat` on a missing path) silently cancels the mutation, so a commit can vanish with no error you'd notice. Sequence mutations as their own calls, and prefer `find -print` over `ls`/`grep` for existence checks (it exits 0 on an empty match — but only when the search root exists; for a possibly-missing path use `test -e` or append `|| true`, per the Shell-section caveat above).

## Editing

Before editing a file, run `grep -cP '\t' <file>` to detect tab indentation — match exactly or the Edit tool will fail.

## Deletion safety

`rm`, `cp`, and `mv` are shell-function wrappers with safety behavior (rm routes to trash; cp/mv default to `-i` overwrite prompts). These wrappers are usually ACTIVE in Bash tool calls — Claude Code snapshots the interactive shell's functions to `~/.claude/shell-snapshots/snapshot-zsh-*.sh` and sources that file before every command, so the rm-to-trash wrapper comes along even though `.zshrc` itself isn't read. Verified 2026-06-08: `type -a rm` reported the snapshot function and a delete printed `Trashed ... (recover: Finder, Put Back)`, recoverable via Finder or the `trash` CLI. Caveats: confirmed for `rm` only (cp/mv presumably share the mechanism, untested), and it depends on the snapshot having captured the function — not guaranteed on every machine/session, so run `type rm` before trusting reversibility. The discipline does NOT change: ALWAYS get explicit user confirmation before deleting or overwriting — treat Trash recovery as a safety net, never a license to delete freely. The `~/.config/safe-rm` denylist is a separate layer and may not protect you here — don't rely on it.

## GitHub CLI (`gh`)

Never run `gh auth login` / `gh auth setup-git` / `gh auth refresh` - they re-add HTTPS credential helpers and break SSH-only auth (a `gh()` shell wrapper and a PreToolUse hook block them). For GitHub API reads use `gh api` / `gh run` / `gh pr` / `gh issue` (or `curl` with `$GH_TOKEN`); a fine-grained read-only token is provided as `$GH_TOKEN` in Claude sessions, so any write call returns 403.
