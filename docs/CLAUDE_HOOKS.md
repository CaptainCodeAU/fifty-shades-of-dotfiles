# Claude Code hooks: how they get deployed

## The problem this solves

A Claude Code hook needs **three** things. This repo can only stow one of them.

| Part                        | Lives in                      | Deployed by                           |
| --------------------------- | ----------------------------- | ------------------------------------- |
| 1. The hook script          | `~/.claude/hooks/*.sh`        | **stow** (from `home/.claude/hooks/`) |
| 2. The registration         | `~/.claude/settings.json`     | **`claude-hooks-sync`** (this doc)    |
| 3. Whatever the hook guards | e.g. `~/.claude/skills/herdr` | nothing -- machine-local              |

Before 2026-09-05 only part 1 existed. `grep -n '\.claude' install.sh` returned
**zero** matches, so every newly added hook was stowed and inert on every machine
until somebody hand-edited a 44KB JSON file, which in practice nobody did.

It surfaced on the Intel MacBook Pro: the login banner reported 13 tracked files
not linked, the first three being `enforce-herdr-skill.sh`,
`mark-herdr-skill-read.sh` and `census-selftest`. Stowing them would have put the
scripts in place and changed nothing about whether they ran.

`~/.claude/settings.json` **cannot** be stowed. It is machine-local: the model,
MCP servers, voice config, permissions and the whole PAI hook set share that file.

## The pieces

| Path                                         | What it is                                       |
| -------------------------------------------- | ------------------------------------------------ |
| `settings/claude/hooks.json`                 | The manifest -- the registrations this repo owns |
| `home/.local/bin/claude-hooks-sync`          | The merger. Add-only.                            |
| `home/.local/bin/claude-hooks-sync-selftest` | 21 tests; proves the merger behaves              |
| `install.sh`                                 | Calls the merger. Three lines, three call sites. |

The manifest lives under `settings/`, not `home/`, because it is installer input
rather than a dotfile -- the same reason `settings/iterm2` and `settings/wezterm`
live there (`install.sh:975`: "NOT stow-managed").

## Using it

```sh
claude-hooks-sync --check              # what is unregistered? writes nothing
claude-hooks-sync --install            # register what is missing
claude-hooks-sync --install --dry-run  # say what would change
claude-hooks-sync-selftest             # 21 tests
```

Exit codes: `0` nothing pending / success, `1` pending (check) or write failed
(install), `2` cannot run (no jq, no manifest, no settings.json, malformed JSON).

`./install.sh` and `./install.sh --stow-only` both run `--install` after stow.
`./install.sh --check` runs `--check` and folds the result into Deploy Parity, so
an unregistered hook fails the audit exactly like a missing symlink does.

## Adding a hook

1. Put the script in `home/.claude/hooks/`.
2. Add an entry to `settings/claude/hooks.json`.
3. `./install.sh --stow-only`.
4. Restart Claude Code (or open `/hooks`) so it re-reads settings.

```json
{
  "event": "PreToolUse",
  "matcher": "Bash",
  "script": "my-hook.sh",
  "entry": {
    "type": "command",
    "command": "$HOME/.claude/hooks/my-hook.sh",
    "timeout": 5
  },
  "requires": ["$HOME/.claude/skills/something"],
  "why": "One line, printed when the entry is skipped"
}
```

Use `$HOME`, never a literal path -- the same JSON has to work on every machine.

## The two gates

An entry is registered only if **both** pass. Either failing is a skip with a
printed reason, never an error.

**The script must exist on disk.** Registering a hook whose file is missing turns
every matching tool call into an error -- strictly worse than not registering it.

**Every `requires` path must exist.** This one is load-bearing.
`enforce-herdr-skill.sh` _denies_ every `herdr` command until the herdr skill is
invoked in the session, and the only thing that lifts the block is the sibling
hook seeing that skill run. `~/.claude/skills/herdr` is a symlink into
`~/.agents/`, is not tracked here, and nothing deploys it. On a machine with the
hook registered and no skill, **herdr is blocked permanently with no way to
unlock it** -- and the laptop is precisely the box that drives herdr against the
mini.

## Why add-only

`claude-hooks-sync` never removes an entry and never edits one. A registration
pointing at a hook this repo has retired is left for a human.

The reason is blast radius. `settings.json` is not ours; an installer that can
delete from it is an installer that can lose your MCP servers. Pruning was
offered and deliberately declined on 2026-09-05.

## Why jq is safe here (measured, not assumed)

`jq '.' ~/.claude/settings.json` returned **byte-identical** output: 44335 bytes
in, 44335 out, `cmp` silent, 51 keys both sides. The file is strict JSON with no
`//` comments -- unlike the Cursor/VSCode settings, which `install.sh` has to
text-match for exactly that reason (`install.sh:185`) -- and it is 2-space
indented, which is jq's default.

Stronger still: a copy of the real 44KB file with one registration deleted, run
through `--install`, came back **byte-for-byte identical to the original**.

Re-check this if `settings.json` ever gains comments.

## Two traps worth keeping

**`IFS=$'\t' read` drops empty fields.** Tab is an IFS _whitespace_ character, so
bash collapses a run of tabs into one delimiter. An entry with no `requires`
emitted two adjacent tabs, every later field shifted left by one, `cmd` received
the `why` text, nothing ever looked registered, and each run appended a
duplicate. Measured: `already-there.sh` hit count=2 after one `--install`. Fixed
by joining with US (``), which is not whitespace.

**`mktemp -d` with no template ignores `$TMPDIR` on BSD/macOS.** It uses the
confstr default under `/var/folders`, which is not writable everywhere. Always
pass an explicit template. Same family as the `stat -f` / `stat -c` split.
