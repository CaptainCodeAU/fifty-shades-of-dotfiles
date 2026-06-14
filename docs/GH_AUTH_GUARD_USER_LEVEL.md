# GitHub API read-only token + `gh` auth guard (user-level install)

How the read-only GitHub API lane for Claude sessions is wired, and how to
install / test / roll back the **user-level** `gh auth` guard hook on this Mac.

> **Status: macOS only.** Linux/WSL consumer boxes are NOT yet covered - that
> needs a separate discussion (parked, not pressing). The hook script itself is
> portable bash; only the Keychain-backed `$GH_TOKEN` wiring and the `~/.claude/`
> install path are macOS-specific so far.

## What this is

GitHub git auth here is SSH-only. `gh auth login` / `setup-git` / `refresh`
silently re-add HTTPS credential helpers to `~/.gitconfig` and break that model,
so they are blocked. For GitHub API reads (issues, PRs, Actions/CI) a
fine-grained **read-only** token is exposed as `$GH_TOKEN` only inside Claude
sessions.

Three layers block `gh auth login` / `setup-git` / `refresh`:

1. `gh()` shell wrapper in `home/.zshrc` - interactive terminals.
2. Project-level hook in this repo's `.claude/settings.json` - Claude sessions in this repo.
3. **User-level hook in `~/.claude/settings.json` - every Claude session on this Mac (this doc).**

Related pieces (all tracked in the dotfiles repo):

- `home/.zshrc` `_claude_launch()` reads the token from Keychain, exports
  `$GH_TOKEN` for the Claude process, and refreshes the banner status cache.
- `home/.zsh_welcome` shows a `GH API:` status line (reads the cache only; shows `pending (launch Claude once)` until the first launch populates the cache).
- `.claude/hooks/export_transcript.sh` redacts `github_pat_`/`ghp_` patterns.
- Token lives in macOS Keychain item `github-api-readonly` (fine-grained,
  read-only, no `Contents`/source).

## Install (user level, macOS)

Adjust the repo path if yours differs (dev Mac: `~/CODE/Scaffoldings/fifty-shades-of-dotfiles`).

```bash
# 1. Copy the tracked hook script into the global Claude hooks dir
cp ~/CODE/Scaffoldings/fifty-shades-of-dotfiles/.claude/hooks/enforce-gh-ssh-only.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/enforce-gh-ssh-only.sh

# 2. Back up global settings, then register the hook (PreToolUse -> Bash)
cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d_%H%M%S)
jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/enforce-gh-ssh-only.sh"}]}]' \
  ~/.claude/settings.json > /tmp/cc.json \
  && jq -e . /tmp/cc.json >/dev/null \
  && mv /tmp/cc.json ~/.claude/settings.json
```

Notes:

- If `~/.claude/settings.json` is tab-indented, add `--tab` to the `jq` call.
- The `mv` may prompt to overwrite (the `mv -i` safety wrapper); answer `y`.
- Takes effect in the **next** Claude session (settings are read at launch).

## Test / check

```bash
# Valid JSON?
jq -e . ~/.claude/settings.json >/dev/null && echo "valid JSON"

# Hook registered?
jq -r '.hooks.PreToolUse[].hooks[].command' ~/.claude/settings.json | grep enforce-gh-ssh-only

# Only the intended block was added? (compare to the backup)
BAK=$(ls -t ~/.claude/settings.json.bak.* | head -1)
diff <(jq -S . "$BAK") <(jq -S . ~/.claude/settings.json)

# Hook behaves: should BLOCK (prints a deny JSON)
echo '{"tool_input":{"command":"gh auth login"}}' | ~/.claude/hooks/enforce-gh-ssh-only.sh
# Hook behaves: should ALLOW (no output)
echo '{"tool_input":{"command":"gh run list"}}' | ~/.claude/hooks/enforce-gh-ssh-only.sh

# Verify the token itself works (read-only):
T=$(security find-generic-password -a "$USER" -s github-api-readonly -w 2>/dev/null)
GH_TOKEN="$T" gh auth status
GH_TOKEN="$T" gh issue list -R CaptainCodeAU/<some-repo>
unset T
```

Live check: open a new terminal, launch Claude (`cb`); in-session `gh auth login`
is blocked, `gh run list` / `gh api ...` work, and `echo "${GH_TOKEN:+present}"`
prints `present`.

## Rollback

```bash
# Restore the previous global settings
cp "$(ls -t ~/.claude/settings.json.bak.* | head -1)" ~/.claude/settings.json

# Remove the user-level hook script
rm ~/.claude/hooks/enforce-gh-ssh-only.sh
```

The dotfiles-repo changes (project-level hook, `_claude_launch`, banner,
redaction, removed global export) are reverted with `git restore` / `git revert`.
To disable API access entirely, revoke the `github-api-readonly` token on GitHub
and delete the Keychain item:
`security delete-generic-password -a "$USER" -s github-api-readonly`.
