# pnpm setup guide

For AI coding agents and developers fixing or hardening pnpm installs in
client projects. This guide assumes you're an LLM agent dropping into a
machine with an unknown / partially broken / inherited pnpm setup, and you
need to (a) diagnose what's wrong, (b) clean it up, and (c) leave behind a
correct, reproducible install. Standalone — no external setup required.

Target: **pnpm 11.x** on macOS / Linux / WSL2.

---

## 0. Mental model — what pnpm 11 actually does

### Two config files in two locations

pnpm 11 splits its global config across two sibling files. You will get
confused if you don't internalise this:

| File          | Format | Purpose                                                                            | Key style      |
| ------------- | ------ | ---------------------------------------------------------------------------------- | -------------- |
| `config.yaml` | YAML   | Non-auth, non-registry settings (e.g. `minimumReleaseAge`, `verifyStoreIntegrity`) | **camelCase**  |
| `rc`          | INI    | Auth tokens, registry overrides, `approve-builds=true`                             | **kebab-case** |

The two coexist in the same directory. Editing one does not affect the
other. **Putting kebab-case keys in `config.yaml` is the #1 silent-failure
mode**: pnpm 11 reads the file but ignores keys it doesn't recognise — no
warning, no error, settings just don't apply. Empirically verified against
pnpm 11.1.2.

### Where pnpm reads from (THE confusing bit)

pnpm 11 looks up its config directory at runtime via this fallback chain
(source: `pnpm.mjs` `getConfigDir()`):

1. `$XDG_CONFIG_HOME/pnpm/` if `XDG_CONFIG_HOME` is set.
2. **macOS**: `~/Library/Preferences/pnpm/` (when XDG unset).
3. **Linux / other non-Windows**: `~/.config/pnpm/` (when XDG unset).
4. **Windows**: `%LOCALAPPDATA%/pnpm/config/`.

If a Linux-shaped dotfiles setup (`~/.config/pnpm/config.yaml`) is rsynced
or stowed to a Mac without setting `XDG_CONFIG_HOME`, **pnpm on that Mac
won't find it** — it'll look at `~/Library/Preferences/pnpm/` instead.
The config is silently dead.

### PNPM_HOME (data dir) ≠ config dir

`PNPM_HOME` is the **data** directory (binaries, store, global packages).
Different fallback:

1. `$PNPM_HOME` env var if set.
2. `$XDG_DATA_HOME/pnpm/` if `XDG_DATA_HOME` is set.
3. **macOS**: `~/Library/pnpm/`.
4. **Linux**: `~/.local/share/pnpm/`.
5. **Windows**: `%LOCALAPPDATA%/pnpm/`.

The standalone installer (`curl get.pnpm.io/install.sh | sh -`) sets up
PNPM_HOME and writes the `pnpm` binary inside it.

### Store layout v10 vs v11

pnpm 11 uses an SQLite-backed store at `$PNPM_HOME/store/v11/`. pnpm 10
used a different layout at `$PNPM_HOME/store/v10/`. They coexist — neither
prunes the other. A machine that upgraded mid-flight will have BOTH.

Global packages:

- pnpm 11: shims in `$PNPM_HOME/bin/`, packages in `$PNPM_HOME/global/v11/`.
- pnpm 10: loose shims directly in `$PNPM_HOME/` (root), packages in
  `$PNPM_HOME/global/5/`. Old layout — pnpm 11 won't replace these
  automatically.

Both layouts may be present after an upgrade. Both will run, but the loose
shims at root only resolve if `$PNPM_HOME` (not just `$PNPM_HOME/bin`) is
on PATH.

### Shell completion

pnpm provides zsh/bash/fish completion via `pnpm completion <shell>`,
which prints the completion script to stdout. The standalone install
does NOT install completion by default. Generate it manually:

```bash
pnpm completion zsh > "$PNPM_HOME/_pnpm"
# then in .zshrc:
[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"
```

### `pnpm setup` — handle with care

`pnpm setup` is pnpm's "fix my shell rc for me" command. It appends a
PNPM_HOME export block directly to your shell rc file. **Do not run it**
in a dotfiles/stow-managed environment — it silently mutates a tracked
file. Instead, wire PNPM_HOME by hand in your stowed rc.

---

## 1. Detect — what's wrong with this install?

Paste this block into a terminal. It runs read-only, prints a checklist.

```bash
#!/usr/bin/env bash
# pnpm-doctor.sh — read-only health check
set +e
OS=$(uname -s)
ISSUES=0
report() { printf "  %-7s %s\n" "$1" "$2"; [[ "$1" == "FAIL" ]] && ((ISSUES++)); }
echo "=== pnpm health check ==="

# 1. pnpm exists + version
if command -v pnpm &>/dev/null; then
    PNPM_VER=$(pnpm -v 2>/dev/null)
    report "OK" "pnpm $PNPM_VER at $(command -v pnpm)"
    [[ "${PNPM_VER%%.*}" -lt 11 ]] && report "WARN" "pnpm < 11 — many features in this guide need 11.x"
else
    report "FAIL" "pnpm not installed"
fi

# 2. Multiple pnpm binaries
if command -v pnpm &>/dev/null; then
    N=$(which -a pnpm 2>/dev/null | sort -u | wc -l | tr -d ' ')
    if (( N > 1 )); then
        report "FAIL" "Multiple pnpm binaries — first match wins:"
        which -a pnpm | sort -u | sed 's/^/         /'
    fi
fi

# 3. PNPM_HOME set + bin on PATH
if [[ -n "${PNPM_HOME:-}" ]]; then
    report "OK" "PNPM_HOME=$PNPM_HOME"
    [[ ":$PATH:" == *":$PNPM_HOME/bin:"* ]] || report "FAIL" "\$PNPM_HOME/bin not on PATH"
else
    report "WARN" "PNPM_HOME unset (using default)"
fi

# 4. Config dir + config.yaml
case "$OS" in
    Darwin) CFG_DIR="$HOME/Library/Preferences/pnpm" ;;
    Linux)  CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pnpm" ;;
esac
[[ -n "${XDG_CONFIG_HOME:-}" ]] && CFG_DIR="$XDG_CONFIG_HOME/pnpm"
if [[ -f "$CFG_DIR/config.yaml" ]]; then
    report "OK" "config.yaml at $CFG_DIR"
    # Detect silently-dead kebab keys
    if grep -qE '^[a-z]+(-[a-z]+)+:' "$CFG_DIR/config.yaml" 2>/dev/null; then
        report "FAIL" "kebab-case keys in config.yaml (silently ignored — must be camelCase):"
        grep -nE '^[a-z]+(-[a-z]+)+:' "$CFG_DIR/config.yaml" | head -5 | sed 's/^/         /'
    fi
else
    report "WARN" "No config.yaml at $CFG_DIR — no global settings active"
fi

# 5. Conflicting install sources
if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null && brew list pnpm &>/dev/null; then
    report "FAIL" "Homebrew pnpm installed — collides with standalone"
fi
if command -v dpkg &>/dev/null && dpkg -l 2>/dev/null | grep -qE '^ii\s+pnpm\s'; then
    report "FAIL" "apt pnpm installed — distro packages lag standalone"
fi
if command -v corepack &>/dev/null && corepack ls 2>/dev/null | grep -q pnpm; then
    report "FAIL" "corepack has pnpm enabled — may shadow standalone"
fi

# 6. v10 leftovers
DATA_DIR="${PNPM_HOME:-$HOME/Library/pnpm}"
[[ ! -d "$DATA_DIR" && -d "$HOME/.local/share/pnpm" ]] && DATA_DIR="$HOME/.local/share/pnpm"
[[ -d "$DATA_DIR/store/v10" ]] && report "WARN" "pnpm 10 store still present at $DATA_DIR/store/v10"
[[ -d "$DATA_DIR/global/5" ]] && report "WARN" "pnpm 10 globals layout at $DATA_DIR/global/5"

# 7. ~/.npmrc with auth/registry
if [[ -f "$HOME/.npmrc" ]] && grep -qE '^(registry=|//|_auth)' "$HOME/.npmrc" 2>/dev/null; then
    report "WARN" "~/.npmrc has registry/auth — may shadow pnpm's expected default"
fi

echo
[[ $ISSUES -eq 0 ]] && echo "✅ no critical issues" || echo "❌ $ISSUES critical issue(s)"
```

---

## 2. Fix — remediation recipes

Apply in this order. Don't skip steps; each builds on the previous.

### 2.1 Remove conflicting install sources

```bash
# Homebrew (macOS)
brew list pnpm &>/dev/null && brew uninstall pnpm

# Distro packages (Linux)
command -v dpkg   &>/dev/null && dpkg -l    | grep -q pnpm && sudo apt remove pnpm
command -v dnf    &>/dev/null && dnf list installed | grep -q pnpm && sudo dnf remove pnpm
command -v pacman &>/dev/null && pacman -Qs '^pnpm$' &>/dev/null && sudo pacman -R pnpm
command -v snap   &>/dev/null && snap list pnpm &>/dev/null && snap remove pnpm

# Corepack
corepack disable pnpm 2>/dev/null || true

# npm-installed pnpm (rare — usually shadowed by standalone anyway)
npm ls -g pnpm 2>/dev/null | grep -q pnpm && npm uninstall -g pnpm
```

### 2.2 Back up stale configs (don't delete — back up)

```bash
TS=$(date +%Y%m%d-%H%M%S)

# ~/.npmrc with stale settings
[[ -f ~/.npmrc ]] && grep -qE '^(registry=|//|_auth)' ~/.npmrc && \
    mv ~/.npmrc ~/.npmrc.pre-cleanup.$TS.bak

# Stale config.yaml in either location
for f in ~/.config/pnpm/config.yaml ~/Library/Preferences/pnpm/config.yaml; do
    [[ -f "$f" && ! -L "$f" ]] && mv "$f" "$f.pre-cleanup.$TS.bak"
done
```

### 2.3 Remove v10 leftovers

Only after confirming no projects on the machine still pin <pnpm@10.x> in
their `packageManager` field. Check with:

```bash
grep -lR '"packageManager": "pnpm@10' ~/projects ~/Code ~/CODE 2>/dev/null | head
```

If clean:

```bash
DATA_DIR="${PNPM_HOME:-$HOME/Library/pnpm}"
[[ -d "$DATA_DIR" ]] || DATA_DIR="$HOME/.local/share/pnpm"
rm -rf "$DATA_DIR/store/v10" "$DATA_DIR/global/5"
pnpm store prune 2>/dev/null || true
```

### 2.4 Remove `pnpm setup` appends from shell rc

```bash
# Inspect first
grep -nE 'PNPM_HOME|pnpm completion' ~/.zshrc ~/.bashrc ~/.profile 2>/dev/null

# If they're outside a tracked dotfiles file, edit the rc manually and remove
# the auto-generated block (usually marked with a `# pnpm` comment).
```

### 2.5 Reinstall pnpm cleanly via standalone

```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

The installer creates `$PNPM_HOME` (e.g. `~/Library/pnpm` on macOS,
`~/.local/share/pnpm` on Linux) and drops the `pnpm` binary inside it.
It will also append to your shell rc — review and revert if your rc is
dotfiles-managed (see §2.6).

### 2.6 Wire PNPM_HOME and PATH by hand (preferred over `pnpm setup`)

In your zsh rc (or bashrc):

```bash
# macOS
export PNPM_HOME="$HOME/Library/pnpm"
# Linux/WSL
# export PNPM_HOME="$HOME/.local/share/pnpm"

# Both PNPM_HOME and PNPM_HOME/bin on PATH:
# - PNPM_HOME itself: legacy pnpm 10 shims (if any survive)
# - PNPM_HOME/bin:    pnpm 11 global package shims
export PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH"

# Shell completion (run once per machine to generate the file)
[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"
```

Then in a fresh shell:

```bash
pnpm completion zsh > "$PNPM_HOME/_pnpm"
```

### 2.7 Create / fix `config.yaml` with camelCase keys

On macOS:

```bash
mkdir -p ~/Library/Preferences/pnpm
cat > ~/Library/Preferences/pnpm/config.yaml <<'YAML'
# Refuse install of packages younger than N minutes. 4320 = 3 days.
minimumReleaseAge: 4320

# Block transitive deps that resolve from non-registry sources.
blockExoticSubdeps: true

# Validate store on each install.
verifyStoreIntegrity: true

# Refuse silent lockfile updates on `pnpm install`.
preferFrozenLockfile: true
YAML
```

On Linux:

```bash
mkdir -p ~/.config/pnpm
# same content; substitute path
```

If you want a single-source setup across macOS and Linux (e.g. dotfiles
that target both), keep the canonical file at `~/.config/pnpm/config.yaml`
and symlink it on macOS:

```bash
mkdir -p ~/Library/Preferences/pnpm
ln -sfn ~/.config/pnpm/config.yaml ~/Library/Preferences/pnpm/config.yaml
```

### 2.8 Reinstall any global packages

Old loose shims at `$PNPM_HOME/` root were pnpm 10 layout. Reinstall under
pnpm 11; new shims go to `$PNPM_HOME/bin/`:

```bash
pnpm install -g <pkg1> <pkg2> ...
```

Then verify they resolve from the new location:

```bash
ls "$PNPM_HOME/bin/"
which <pkg-binary>
```

If any package version was just published (< `minimumReleaseAge`), pnpm
will refuse with `ERR_PNPM_NO_MATURE_MATCHING_VERSION`. Pin to an older
mature version or wait.

---

## 3. Verify — prove it actually works

### 3.1 Check the config file is being read

```bash
# These all surface the path pnpm is actually using:
pnpm config list 2>&1 | head -5
ls -la "$([[ $(uname) == Darwin ]] && echo ~/Library/Preferences/pnpm || echo ~/.config/pnpm)/config.yaml"
```

### 3.2 `pnpm config get` does NOT show YAML values

This is a common pitfall: `pnpm config get` reads INI (`rc`, `.npmrc`)
only. It surfaces `registry`, `userAgent`, and similar — but NOT
`minimumReleaseAge` or other YAML keys. They return `undefined` even when
active. **Don't trust this command for YAML verification.**

### 3.3 Empirical enforcement test (the real verification)

```bash
SCRATCH=$(mktemp -d)
pnpm -C "$SCRATCH" init
# Pick a package version that's < your minimumReleaseAge old.
# Example: any recent canary release.
pnpm -C "$SCRATCH" add next@latest-canary 2>&1 | grep -E 'ERR_PNPM_NO_MATURE_MATCHING_VERSION|released'
```

If you see `ERR_PNPM_NO_MATURE_MATCHING_VERSION`, the setting is active.
If the package installs cleanly, `minimumReleaseAge` is NOT enforcing —
re-check your config file location and key case.

### 3.4 Global binary resolution

```bash
ls "$PNPM_HOME/bin/"
which <some-globally-installed-binary>  # should resolve to $PNPM_HOME/bin/
```

### 3.5 If install fails with `EBADF` / `ERR_PNPM_META_FETCH_FAIL` — check per-binary firewalls FIRST

Symptom:

```
[WARN] GET https://registry.npmjs.org/<pkg> error (EBADF). Will retry...
[ERR_PNPM_META_FETCH_FAIL] GET https://registry.npmjs.org/<pkg>: fetch failed
```

NODE_DEBUG=undici trace shows `connecting ... using https:undefined` →
`connection ... errored -` (empty error message after the dash) — the
socket FD was killed before TLS handshake started.

**Most common cause on macOS: a per-binary firewall (Little Snitch, LuLu,
Murus) is silently dropping pnpm's connections** while letting `curl`,
`node`, and `bun` through. The firewall's rule is keyed on the
executable path (`$PNPM_HOME/pnpm`), so a permissive rule for `node`
does NOT cover `pnpm` (and vice versa).

#### 4-probe diagnostic — isolates in under 30 seconds

```bash
PKG='@scope/pkg-that-fails'

# 1. curl (libcurl HTTP stack)
curl -sI -m 5 "https://registry.npmjs.org/${PKG//\//%2F}" | head -3

# 2. Node native fetch (Node's built-in undici)
node -e "fetch('https://registry.npmjs.org/${PKG//\//%2F}').then(r=>console.log('node:',r.status)).catch(e=>console.error('node-fail:',e.code||e.cause?.code||e.message))"

# 3. Bun (entirely different HTTP stack — not undici)
bun add -g "$PKG"

# 4. pnpm
pnpm add -g "$PKG"
```

**If 1–3 pass and only 4 fails → it's a per-binary firewall.** The
network, DNS, IPv6, TLS, Node fetch, and Cloudflare are all fine on this
exact machine at this exact instant. Only pnpm's binary identity is
being blocked.

#### Fix

1. **Little Snitch**: open Network Monitor → search rules for `pnpm` or
   check the alert log for blocked connections to `registry.npmjs.org`.
   Add an Allow rule for `pnpm` to `*.npmjs.org` (and probably
   `*.cloudflare.com` for tarball CDN).
2. **LuLu**: same pattern via its rules UI.
3. **Tailscale exit node / Mullvad / WireGuard split-tunnel**: check
   whether pnpm traffic is being routed through a tunnel that's not
   reaching the registry.
4. **Corporate MDM / Zscaler / Netskope**: contact IT; they typically
   maintain per-binary allow-lists for development tools.

#### Things that look like the cause but aren't

The following will all FAIL to fix it (verified empirically) — don't
waste time on them:

- Changing `userAgent` via `pnpm_config_user_agent=...` — firewalls
  match on binary, not UA
- `pnpm_config_network_concurrency=1` — not a pool race
- `NODE_OPTIONS='--dns-result-order=ipv4first --no-network-family-autoselection'`
  — not Happy Eyeballs / IPv6
- `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` — not
  DNS cache
- `exec zsh -l` for a fresh shell — not shell state
- `pnpm store prune` — not local cache state
- Disabling `minimumReleaseAge` or any other `config.yaml` setting —
  policies run AFTER fetch; fetch is what's failing
- `pnpm self-update` — also uses pnpm's HTTP stack, fails the same way

If probes 1–3 also fail, the cause is genuinely network/DNS/registry
side. Use standard network diagnostics. But if curl + node fetch + bun
all succeed and pnpm specifically fails, **stop investigating other
hypotheses and check your firewall.**

---

## 4. Set up clean from scratch (no prior pnpm)

For a fresh machine:

```bash
# 1. Install pnpm (standalone)
curl -fsSL https://get.pnpm.io/install.sh | sh -

# 2. In your shell rc (zsh/bash):
case "$(uname -s)" in
    Darwin)  PNPM_HOME="$HOME/Library/pnpm" ;;
    *)       PNPM_HOME="$HOME/.local/share/pnpm" ;;
esac
export PNPM_HOME
export PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH"

# 3. Generate completion
pnpm completion zsh > "$PNPM_HOME/_pnpm"
echo '[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"' >> ~/.zshrc

# 4. Recommended config (camelCase!)
case "$(uname -s)" in
    Darwin) CFG_DIR="$HOME/Library/Preferences/pnpm" ;;
    *)      CFG_DIR="$HOME/.config/pnpm" ;;
esac
mkdir -p "$CFG_DIR"
cat > "$CFG_DIR/config.yaml" <<'YAML'
minimumReleaseAge: 4320     # 3-day supply-chain delay
blockExoticSubdeps: true
verifyStoreIntegrity: true
preferFrozenLockfile: true
YAML

# 5. Verify
exec zsh   # fresh shell to pick up env
pnpm -v    # should print version
ls "$PNPM_HOME/bin/" 2>/dev/null   # ready for global installs
```

---

## 5. Do's and don'ts

### DO

- **Install pnpm via the standalone installer** (`get.pnpm.io/install.sh`).
  It's the only path that supports `pnpm self-update`.
- **Use camelCase in `config.yaml`**. Kebab-case is for `.npmrc` / `rc`
  (INI), not for YAML.
- **Keep `rc` (auth/registry/`approve-builds=true`) separate from
  `config.yaml`**. They live in the same directory but never overlap.
- **Bridge the macOS path with a symlink** if you share dotfiles across
  Mac + Linux: `~/Library/Preferences/pnpm/config.yaml ->
~/.config/pnpm/config.yaml`.
- **Verify settings empirically** by trying to install a package that
  should fail (e.g. one published in the last hour with
  `minimumReleaseAge: 4320` set). Don't trust `pnpm config get` for YAML
  values.
- **Add both `$PNPM_HOME` and `$PNPM_HOME/bin`** to PATH. pnpm 11 global
  shims go into `bin/`; legacy v10 shims (if any survive) sit at the root.

### DON'T

- **Don't run `pnpm setup`** if your shell rc is tracked by dotfiles or
  Stow. It silently appends a PNPM_HOME block and breaks reproducibility.
- **Don't trust `pnpm config get` for YAML settings.** The CLI only reads
  INI files. YAML values return `undefined` even when active.
- **Don't put kebab-case keys in `config.yaml`** — silently ignored,
  produces zero warnings. The most common silent failure.
- **Don't install pnpm via Homebrew, apt, dnf, pacman, snap, npm, or
  Corepack**. Each one locks pnpm to a version it controls, can't
  self-update, and conflicts with the standalone install if both are
  present.
- **Don't try to set `managePackageManagerVersions: false` in global
  `config.yaml`.** pnpm 11 explicitly rejects this key from global config
  with a warning. To stop pnpm from auto-installing itself + `@pnpm/exe`
  into every new project, put `managePackageManagerVersions: false` in
  each project's `pnpm-workspace.yaml`, or use pnpm 11 config
  dependencies. There is no global escape.
- **Don't delete `$PNPM_HOME/store/v10/` while pnpm 10–pinned projects
  exist.** They need that store to satisfy their lockfiles.
- **Don't export `XDG_CONFIG_HOME` globally just to unify pnpm's config
  path on macOS.** Many other tools respect that variable (helm, gh,
  kubectl, neovim, atuin, starship, zellij) and changing it shifts their
  config-file lookups too. The symlink approach is contained.

---

## 6. References

- pnpm installation: <https://pnpm.io/installation>
- pnpm settings reference: <https://pnpm.io/settings>
- pnpm `.npmrc` / config: <https://pnpm.io/npmrc>
- pnpm completion: <https://pnpm.io/completion>
- pnpm config dependencies (sharing settings across projects):
  <https://pnpm.io/config-dependencies>
- pnpm `devEngines.packageManager` semantics:
  <https://pnpm.io/package_json#devenginespackagemanager>
- Source-code path resolution: in any pnpm 11.x install, see
  `getConfigDir()` and `getDataDir()` in
  `<PNPM_HOME>/.tools/@pnpm+exe/<ver>_tmp_*/node_modules/@pnpm/exe/dist/pnpm.mjs`.
  Grepping the binary for `Library/Preferences` and `XDG_CONFIG_HOME`
  reveals the platform fallback chain.

---

## Appendix — minimal `config.yaml` reference

Copy-paste, edit values to taste:

```yaml
# Refuse install of packages younger than N minutes. 4320 = 3 days.
# Widens the detection window for publish-and-grab supply-chain attacks.
# Bypass per-package via minimumReleaseAgeExclude in pnpm-workspace.yaml.
# Default: 1440 (1 day).
minimumReleaseAge: 4320

# Block transitive dependencies that resolve from non-registry sources
# (git repos, direct tarballs). Top-level deps can still use exotic
# sources — this only restricts subdeps. Default: true.
blockExoticSubdeps: true

# Validate the package store on each install. Catches corruption or
# tampering of cached tarballs. Default: false.
verifyStoreIntegrity: true

# Refuse to update pnpm-lock.yaml on `pnpm install` unless explicitly
# asked (--no-frozen-lockfile, pnpm update, pnpm add). Matches CI default.
# Default: false in dev, true in CI.
preferFrozenLockfile: true
```

Keys NOT to put here (will be rejected or silently ignored by pnpm 11):

- `managePackageManagerVersions` — rejected from global config; use per-project `pnpm-workspace.yaml`.
- Anything in kebab-case — silently ignored; use camelCase.
- `registry`, auth tokens, `_auth`, `//` — those go in `rc` (INI), not here.
