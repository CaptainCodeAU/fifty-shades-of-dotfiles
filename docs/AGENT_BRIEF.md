# fifty-shades-of-dotfiles — agent brief

**Audience:** an LLM agent running in a sibling project on the principal's Mac that needs to interact with files this repo manages — read config, edit shared overrides, or coordinate connections through SSH — without breaking the principal's environment. Self-contained; read only this file.

## What this repo is

- **Local path:** `<dotfiles-repo>` — the principal will tell you, or run `git -C ~ rev-parse --show-toplevel` from inside any stow-managed file's directory.
- **Public GitHub:** `github.com/CaptainCodeAU/fifty-shades-of-dotfiles`.
- **Default branch:** `master`.
- **What it manages:** the principal's `$HOME` configuration via [GNU Stow](https://www.gnu.org/software/stow/). Files committed under `home/<X>` are symlinked to `~/<X>` on install.

The implication for you: if you read `~/.zshrc`, you're following a symlink into this repo. Edits to `~/.zshrc` are edits to a tracked file. Read before you assume you may write.

## Stow topology — what's symlinked from $HOME

Authoritative listing: `git ls-tree HEAD home/` from inside the repo. As of 2026-05-03 the top-level entries are:

| Path in repo             | Symlink at            | Purpose                                                           |
| ------------------------ | --------------------- | ----------------------------------------------------------------- |
| `home/.zshrc`            | `~/.zshrc`            | shell entry; sources the `.zsh_*` partials below                  |
| `home/.zsh_*` (multiple) | `~/.zsh_*`            | partials: docker, node, python, tmux, welcome, onboarding, cursor |
| `home/.p10k.zsh`         | `~/.p10k.zsh`         | powerlevel10k theme                                               |
| `home/.ssh/config`       | `~/.ssh/config`       | strict base; ends with `Include ~/.ssh/config.local`              |
| `home/.gitconfig`        | `~/.gitconfig`        | public-safe; includes `~/.gitconfig.private` (not stowed)         |
| `home/.gitignore_global` | `~/.gitignore_global` | global git ignore                                                 |
| `home/.tmux.conf`        | `~/.tmux.conf`        | tmux + tilit                                                      |
| `home/.vimrc`            | `~/.vimrc`            | minimal vim                                                       |
| `home/.config/...`       | `~/.config/...`       | nested directory tree                                             |
| `home/.local/...`        | `~/.local/...`        | scripts subsystem                                                 |

**Editing rule.** If a file appears at both `~/<X>` and `home/<X>` and they're identical content, it's a stow symlink. Edits propagate into the repo working tree. To make a private edit that doesn't go upstream, use the documented local-override pattern (see SSH section below; analogous patterns exist for `~/.zshrc.private` and `~/.gitconfig.private`).

## Branch-switching hazard (most important section)

**Switching to a branch that does not contain a stow-tracked file leaves the matching `~/<X>` symlink dangling.** SSH (and zsh, etc.) read missing user-config files as "no user config" and silently fall through to system defaults — _no error, no warning_. The principal then starts seeing odd behaviour with no obvious cause.

Before any `git checkout <other-branch>` in this repo, run:

```sh
git ls-tree <other-branch> home/.ssh/ home/.zshrc home/.gitconfig home/.config/
```

Anything present on the current branch but absent on the target is a warning. Either don't switch, or accept the principal's live config will be degraded.

The right fix when you discover a degraded state is to restore HEAD to a branch that contains the missing file. Do **not** cherry-pick scope-expanding commits into the current branch as a "consistency" fix — that violates approved-plan boundaries.

## Privacy rules — what NEVER goes in committed files

The repo is publicly hosted. Treat anything committed as worldwide-readable forever.

**Hard prohibitions in any committed file (`README.md`, `docs/**`, `home/**`, etc.):**

- Real GitHub usernames. The principal operates multiple accounts; co-locating them in one public file _establishes a link_ between them that wasn't otherwise public.
- Real internal hostnames, IPs, ports of trusted-LAN remotes.
- Real cloud server hostnames.
- Real user-account names on remote machines.
- Backup-archive filenames that hint at internal topology.
- Local username paths (`/Users/<username>/…`).

**Use placeholders matching the README's `git-personal` / `git-work` style:**

- `git-<alias>` for SSH host aliases
- `<your-github-key>`, `<dedicated-host-key>` for key paths
- `<real-hostname-or-ip>`, `<trusted-lan-host>` for hosts
- `<real-user>` for usernames on remotes

The "is this name individually public?" test is **not sufficient.** The test is: "if a stranger reads this file, do they learn something about _which set_ of accounts/hosts the principal operates that they couldn't easily learn elsewhere?" If yes, it's a leak.

## ~/.ssh/config.local — the local-override contract

The committed `home/.ssh/config` (stow-managed) deliberately contains zero `Host` blocks beyond a generic `Host *` hardening block. All real Host definitions — GitHub account aliases, trusted-LAN remotes with `ForwardAgent yes`, cloud hosts — live in `~/.ssh/config.local`, which is:

- **Gitignored** (the `home/.ssh/config.local` line in `.gitignore`).
- **Never stowed** (the file does not appear under `home/.ssh/` in the repo).
- **Mode 0600.**
- **Loaded via `Include ~/.ssh/config.local` at the top of `~/.ssh/config`**, before any `Host` directive. An `Include` placed after a non-matching `Host` block enters "parse-only" mode and silently never applies its directives — do not reorder.

You may edit `~/.ssh/config.local` directly when your project legitimately needs a Host block, an `IdentityFile`, or a connection tweak. **Surface every edit to the principal** — ideally before the fact, after-the-fact if you only realised mid-task. The "I had implicit go-ahead, just flagging this for review" pattern is the established baseline; reciprocate.

What lives in this file is the principal's territory. Do not encode real values in your own docs; consult at runtime via:

```sh
ssh -G <alias> | grep -iE "^user |^hostname |^port |^identityfile |^forwardagent "
```

## Strict SSH posture — implications for your connections

The committed `Host *` block sets:

```sshconfig
Host *
    AddKeysToAgent no
    UseKeychain no
    IdentitiesOnly yes
```

What this means for you:

1. **Every SSH operation prompts for the passphrase** unless the key has been explicitly loaded via `ssh-add -t <duration>` in the principal's interactive terminal. Do not assume keys are pre-loaded; if your tool needs key auth and the agent is empty, the call will block on a TTY prompt or fail under `BatchMode=yes`.
2. **No keys are silently cached by macOS Keychain.** A successful `ssh-add` in one terminal does not persist to a fresh terminal.
3. **`IdentitiesOnly yes` means SSH offers only the `IdentityFile` named in the matching Host block.** If your tool runs `ssh user@host` without a Host block, it falls through to `Host *`, which has no `IdentityFile` → SSH offers default `~/.ssh/id_*` files only. Pin the key explicitly with `-i`, or define a Host block in `~/.ssh/config.local`, or invoke through a documented alias.
4. **`BatchMode=yes` invocations silence host-key verification errors at default verbosity.** If a connection fails with no obvious reason, re-run with verbose flags and look for `Host key verification failed` first, then auth failures, then network.

Drift checks the principal can run to confirm posture is intact:

```sh
ssh -G git-<alias> | grep -iE "usekeychain|addkeystoagent|identitiesonly"
# Expected on Apple OpenSSH 10.2p1+: identitiesonly yes; addkeystoagent false
# UseKeychain is silently omitted from `ssh -G` when set to no — missing line is NOT drift.
```

## Defence-in-depth (five layers, current state)

Recap from `README.md` §Security:

1. **SSH config hardening** — strict `Host *` block above.
2. **Scoped URL rewrites** — only the principal's own GitHub repos are rewritten to SSH via `~/.gitconfig.private`; third-party HTTPS pass through. A blanket `insteadOf` would break Homebrew taps; do not suggest it.
3. **No credential helpers** — `~/.gitconfig` has zero `[credential]` sections. HTTPS auth fails closed rather than silently succeeding.
4. **Claude Code SSH isolation** — the `_claude_launch` zsh function (in `home/.zshrc`) spawns an ephemeral `ssh-agent` scoped to the Claude Code process. The key dies when Claude exits; a 4-hour timeout is a SIGKILL safety net.
5. **Per-host opt-in agent forwarding** — `~/.ssh/config.local` Host blocks may set `ForwardAgent yes` for trusted-LAN remotes. **Never set on `Host *`.** Lets VS Code / Cursor Remote-SSH (or plain `ssh`) reach back through the tunnel to the Mac's agent for GitHub auth on the remote — without copying private keys onto the remote.

Full rationale, alternative postures considered (Pragmatic-strict / Pragmatic-default / Hardware-backed), and revisit triggers: `docs/SECURITY.md`.

## gh CLI — auth commands are blocked

A `gh()` shell wrapper in `home/.zshrc` blocks `gh auth login`, `gh auth setup-git`, and `gh auth refresh`. Reason: those commands silently inject `[credential "https://github.com"]` helpers into `~/.gitconfig`, creating an HTTPS fallback that defeats the SSH-only model.

If your tool needs `gh` for API calls (PRs, issues, releases): the `GITHUB_PERSONAL_ACCESS_TOKEN` env var is exported from macOS Keychain by `home/.zshrc` and `gh` reads it automatically. **Never recommend `gh auth login`** to the principal — it will fail with an explanatory message anyway, but the recommendation itself is wrong.

## Cross-agent etiquette

When operating in shared territory (`~/.ssh/config.local`, `~/.ssh/known_hosts`, anything not wholly inside your own project tree):

| Action                                        | Pattern                                                                                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Edit you knew about ahead of time             | Surface intent first; act after acknowledgement.                                                                                      |
| Edit you realised was needed mid-task         | Surface immediately after; "I made X change for Y reason; here's how to revert."                                                      |
| Reading shared files                          | No surfacing required.                                                                                                                |
| Diagnosing this repo's state                  | Use read-only tools (`git ls-tree`, `ssh -G`, `ssh -vvv`); do not modify anything in this repo's tree.                                |
| Found a footgun in this repo                  | Brief the principal with the diagnosis; let this repo's agent act on the fix.                                                         |
| Need to fix an operational outage you observe | Prefer minimum-blast-radius (restore prior HEAD, no commits touched) over rewriting commits to make a branch "internally consistent." |

Established norm: good-faith collaborators surface after-the-fact when prior briefing was missed, accept architectural pushback, and update their own tracking documents to reflect cross-agent decisions. Reciprocate.

## Operational signals — what you might observe

| Symptom                                                                          | Likely cause                                                                                 | What to do                                                                                                                       |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `ssh -G <alias>` returns generic defaults (`port 22`, all default IdentityFiles) | Stow symlink to `~/.ssh/config` is dangling — repo is on a branch lacking `home/.ssh/config` | Tell the principal; suggest restoring HEAD to a branch with the file (`git -C <dotfiles-repo> branch --show-current` to confirm) |
| `ForwardAgent` resolves to `no` for an alias that should have `yes`              | Either `~/.ssh/config.local` was edited or the symlink chain is broken                       | `ssh -vvv -G <alias> 2>&1 \| grep "Reading configuration data"` — both `~/.ssh/config` and `~/.ssh/config.local` should appear   |
| `BatchMode` SSH calls failing silently                                           | Host-key verification, auth, or sshd issue masked by `BatchMode=yes`                         | Re-run with verbose flag; search stderr for `Host key verification failed`                                                       |
| `ssh-add -l` returns "agent has no identities"                                   | Strict posture — keys are not auto-loaded                                                    | Have the principal run `ssh-add -t <h> ~/.ssh/<key>` in their terminal; do not auto-load via your tool                           |
| A file you wrote to this repo got reformatted between Write and the next read    | A formatter hook ran on PostToolUse; content unchanged but markdown style normalised         | Re-read before any subsequent Edit                                                                                               |
| Untracked `MEMORY/` directory at repo root                                       | Other agents' session logs                                                                   | Leave alone; not part of this repo                                                                                               |

## Where to find ground truth

| Question                                     | Source                                                          |
| -------------------------------------------- | --------------------------------------------------------------- |
| Why strict posture?                          | `docs/SECURITY.md` (in repo)                                    |
| Five defence-in-depth bullets                | `README.md` §Security                                           |
| Multi-account GitHub setup pattern           | `README.md` §Multiple GitHub Accounts                           |
| Stow conflict / install behaviour            | `README.md` §FAQ + `install.sh`                                 |
| What's actually committed under `home/.ssh/` | `git ls-tree HEAD home/.ssh/`                                   |
| Effective SSH config for an alias            | `ssh -G <alias>`                                                |
| Which config files SSH actually reads        | `ssh -vvv -G <alias> 2>&1 \| grep "Reading configuration data"` |

If the live state contradicts this brief (`ssh -G` output, `git ls-tree`, file contents differ), trust the live state. Memory and documentation are point-in-time; the repo is authoritative. Surface contradictions to the principal so this brief can be updated.

## Stability and lifecycle

- **Master is the default branch.** Feature work on `feat/*`, doc work on `docs/*`. Default workflow is rebase-and-fast-forward; merge commits avoided where possible.
- **Don't push to master directly** unless the principal explicitly asks. Default flow is review-then-push, often via PRs on GitHub.
- **`Plans/`** is gitignored — implementation specs and planning notes for the principal's reference, not part of the public repo.
- **`MEMORY/`** at repo root (when present) is other agents' session logs. Not committed.
- **`.zshrc.private`, `~/.gitconfig.private`** — the `*.private` pattern is for files the principal sources but never commits. Same gitignore protection as `~/.ssh/config.local`.

## What this brief is not

- Not the README. Cloning, installing, customising for a new user is README territory.
- Not a security tutorial. `docs/SECURITY.md` is.
- Not a full file inventory. `git ls-tree HEAD` is the authoritative discovery endpoint.
- Not exhaustive on `home/.zshrc` internals. If your tool needs a specific zsh helper, ask the principal or `grep` for it.
