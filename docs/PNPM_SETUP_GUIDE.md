# pnpm setup guide

For AI coding agents and developers fixing or hardening pnpm installs in
client projects. It assumes you are dropping into a machine with an unknown,
partly broken or inherited pnpm setup and need to (a) find what is wrong,
(b) clean it up, and (c) leave a correct, reproducible install. Standalone: no
external setup required.

Target: **pnpm 12.x** on macOS / Linux / WSL2. Every fact below was measured on
**pnpm 12.9.0 on 2026-10-06** and sits next to the command that proves it.
On **2026-10-10** the box moved to **12.10.0**: `pnpm-guide-selftest` (40 checks,
the section 0 probes and the doctor among them) passed on it, and the
`preferFrozenLockfile` (Appendix) and `engineStrict` (7.0) facts were re-measured.
A fact that still names 12.9.0 was not re-run on 12.10.0.
**Run the command; do not trust the sentence.** pnpm changes behaviour inside a
major (this guide was first written about 11.1.2 and went wrong one release at
a time), so a fact you have not re-run on the installed version is a guess.
Section 7 is the history of this box's upgrades and is not re-measured.

> **How to probe safely.** Every probe below points pnpm at a scratch config,
> never the real one, so it cannot change anything and cannot be masked by it:
>
> ```bash
> S=$(mktemp -d "${TMPDIR:-/tmp}/pnpm-probe.XXXXXX"); mkdir -p "$S/home" "$S/cfg/pnpm"
> p() { env -i PATH="$PATH" HOME="$S/home" XDG_CONFIG_HOME="$S/cfg" pnpm "$@"; }
> printf 'fetchRetries: 7\n' > "$S/cfg/pnpm/config.yaml"; p config get fetchRetries   # 7
> ```
>
> `env -i` matters: an exported `PNPM_CONFIG_*` variable overrides the file
> (section 0), so a probe run in your normal shell can report the variable and
> look like the file.

---

## 0. Mental model: what pnpm 12 actually reads

### One settings file, one auth file

| File          | Format | Holds                                           | Key style     |
| ------------- | ------ | ----------------------------------------------- | ------------- |
| `config.yaml` | YAML   | Every setting, `registry` included              | **camelCase** |
| `auth.ini`    | INI    | Auth tokens and registry overrides              | kebab-case    |
| `rc`          | INI    | **Not read by pnpm 12.** pnpm 11 kept auth here | -             |

All three live in the same config directory. Measured:

```bash
printf 'registry=https://rc.invalid/\n'      > "$S/cfg/pnpm/rc";       p config get registry  # https://registry.npmjs.org/ (ignored)
printf 'registry=https://authini.invalid/\n' > "$S/cfg/pnpm/auth.ini"; p config get registry  # https://authini.invalid/
```

`~/.npmrc` and a project `.npmrc` are still read.

**Kebab-case keys in `config.yaml` are silently ignored**: no warning, no
error, the setting just does not apply. This is the most common silent
failure.

```bash
printf 'fetch-retries: 7\n' > "$S/cfg/pnpm/config.yaml"; p config get fetchRetries   # undefined
printf 'fetchRetries: 7\n'  > "$S/cfg/pnpm/config.yaml"; p config get fetchRetries   # 7
```

**Unknown keys are silently accepted; known keys are typed.** So "no warning"
proves nothing about a key, and a key that pnpm removed looks exactly like one
it honours:

```bash
printf 'bogusKeyXyz: banana\n'                  > "$S/cfg/pnpm/config.yaml"; p --version   # 12.10.0, exit 0
printf 'managePackageManagerVersions: banana\n' > "$S/cfg/pnpm/config.yaml"; p --version   # 12.10.0, exit 0 (removed key)
printf 'blockExoticSubdeps: banana\n'           > "$S/cfg/pnpm/config.yaml"; p --version   # exit 1, "load configuration"
```

A wrong type fails **every** pnpm command, so a typo in a known key breaks the
machine loudly. The parse error says "Failed to parse pnpm-workspace.yaml" even
for the global `config.yaml`; it is the global file.

### Environment variables beat the file

`PNPM_CONFIG_<SNAKE_CASE>` (either case) overrides `config.yaml`.
`npm_config_*` is **not** read by pnpm 12.

```bash
printf 'minimumReleaseAge: 99\n' > "$S/cfg/pnpm/config.yaml"
env -i PATH="$PATH" HOME="$S/home" XDG_CONFIG_HOME="$S/cfg" PNPM_CONFIG_MINIMUM_RELEASE_AGE=4320 pnpm config get minimumReleaseAge  # 4320
env -i PATH="$PATH" HOME="$S/home" XDG_CONFIG_HOME="$S/cfg" npm_config_fetch_retries=9 pnpm config get fetchRetries               # undefined
```

So on a machine that exports one, `pnpm config get` reports the variable and
cannot tell you whether the file is being read.

> **This box:** `home/.zshrc` exports `PNPM_CONFIG_MINIMUM_RELEASE_AGE` and
> `PNPM_CONFIG_TRUST_POLICY` as a backup beside the same keys in `config.yaml`,
> plus `PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS`, which the global file cannot pin (7.4).
> Both layers stay (Gavin, 2026-10-06, D-20261006-A09); `pnpm-config-check` fails
> when an export disagrees with the file, so a one-sided edit is caught.

### Where pnpm looks for its config directory

1. `$XDG_CONFIG_HOME/pnpm/` if `XDG_CONFIG_HOME` is set.
2. **macOS**: `~/Library/Preferences/pnpm/`.
3. **Linux / WSL**: `~/.config/pnpm/`.
4. **Windows**: `%LOCALAPPDATA%/pnpm/config/` (not measured here).

On macOS, `~/.config/pnpm/config.yaml` is **not read** unless
`XDG_CONFIG_HOME` is set. A Linux-shaped dotfiles setup stowed to a Mac is
silently dead:

```bash
H=$(mktemp -d); mkdir -p "$H/.config/pnpm" "$H/Library/Preferences/pnpm"
printf 'fetchRetries: 6\n' > "$H/.config/pnpm/config.yaml"
env -i PATH="$PATH" HOME="$H" pnpm config get fetchRetries        # undefined on macOS
printf 'fetchRetries: 5\n' > "$H/Library/Preferences/pnpm/config.yaml"
env -i PATH="$PATH" HOME="$H" pnpm config get fetchRetries        # 5
```

### `pnpm config get` shows what is SET, never the default

It reads `config.yaml` keys back (camelCase), but for a key nobody set it
prints `undefined`, including keys whose default is on:

```bash
: > "$S/cfg/pnpm/config.yaml"
for k in minimumReleaseAge verifyStoreIntegrity blockExoticSubdeps strictDepBuilds; do p config get "$k"; done   # undefined x4
```

So `undefined` means "not set", not "off". Defaults come from the docs
(<https://pnpm.io/settings>) or from a behaviour test (section 3). A few keys
read back `undefined` even when set: on 12.9.0, `blockExoticSubdeps`,
`supportedArchitectures`, `python` and `cargo`. Prove those by typed rejection
(above) or by behaviour.

### `PNPM_HOME` (data) is not the config dir

`PNPM_HOME` holds the binaries, store and global packages:

1. `$PNPM_HOME` if set.
2. `$XDG_DATA_HOME/pnpm/` if set.
3. **macOS**: `~/Library/pnpm/`. **Linux**: `~/.local/share/pnpm/`.

```bash
env -i PATH="$PATH" HOME="$S/home" pnpm store path                        # $S/home/Library/pnpm/store/v11 on macOS
env -i PATH="$PATH" HOME="$S/home" XDG_DATA_HOME="$S/d" pnpm store path   # $S/d/pnpm/store/v11
```

### Store layout

pnpm 12 still uses the **v11** layout: store at `$PNPM_HOME/store/v11/`,
global packages in `$PNPM_HOME/global/v11/`, shims in `$PNPM_HOME/bin/`. "v11"
names the layout, not the pnpm version. pnpm 12 also keeps downloaded pnpm
versions in `$PNPM_HOME/package-manager-store/v11/` (used when a project pins
another pnpm version).

Only `$PNPM_HOME/bin` belongs on PATH. pnpm 10 put shims in `$PNPM_HOME/`
itself; pnpm 12's `self-update` no longer writes them there (observed
12.6.0 -> 12.9.0), and since 12.8.0 `pnpm update --global` migrates pnpm 10
globals out of `global/5` and removes its root shims.

`pnpm link --global` no longer exists (`error: unexpected argument '--global'`).
Use `pnpm add -g .` to install a local project globally.

### pnpm runs as a native binary

pnpm 12 is a native executable, not a Node script, so a pnpm-pinned Node
version (`devEngines.runtime`) and nvm can both answer `node`. The
`globalShims` setting decides whether pnpm puts its own `node`/`npm` shims in
`$PNPM_HOME/bin`; section 7 explains why this box sets it `false`.

### A project can pin another pnpm version

A project's `devEngines.packageManager` (current form) or `packageManager`
(which the pnpm docs now call legacy) can name a pnpm version. By default pnpm
12 downloads that version into `package-manager-store/v11/` and runs it
instead, silently, so a project pinned to an old 11.x runs 11.x and ignores
every setting 11.x does not know. `pmOnFail` controls this (`ignore` = the old
`managePackageManagerVersions: false`; `warn` = say so). It is typed and is
honoured in the global `config.yaml`:

```bash
printf 'pmOnFail: banana\n' > "$S/cfg/pnpm/config.yaml"; p --version            # exit 1, typed
printf 'pmOnFail: ignore\n' > "$S/cfg/pnpm/config.yaml"; p config get pmOnFail  # ignore
```

> **This box:** `pmOnFail: warn` is set in the global file (Gavin, 2026-10-06,
> D-20261006-A02): a project pinned to another pnpm or package manager runs this
> machine's pnpm with one warning line. Never export `PNPM_CONFIG_PM_ON_FAIL`: an
> env value outranks a project's own `pmOnFail`. See 7.4.

### Shell completion

```bash
pnpm completion zsh > "$PNPM_HOME/_pnpm"     # 12.x script also covers `pn`
# in a shell rc you own:
[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"
```

Regenerate it after a major upgrade.

### `pnpm setup`: do not run it in a managed shell rc

It appends a `PNPM_HOME` block to your shell rc. In a dotfiles or stow setup
that silently edits a tracked file. Wire `PNPM_HOME` by hand (2.6).

---

## 1. Detect: what is wrong with this install?

Save as `pnpm-doctor.sh` and run `bash pnpm-doctor.sh`. Read-only; prints a
checklist and counts FAIL lines. Every check has a fixture that makes it fire
and a clean fixture that keeps it quiet (this repo's `pnpm-guide-selftest`
extracts this block from this file and runs them, so the script cannot drift
from what is proven).

**Run it outside any sandbox.** A sandbox that denies a file reports it as
missing (measured: Claude Code's sandbox denies `~/.npmrc`, and `ls` there says
"No such file or directory" whether or not it exists), so a denied check reads
as clean.

<!-- pnpm-doctor:begin -->

```bash
#!/usr/bin/env bash
# pnpm-doctor.sh -- read-only health check for pnpm 12 (macOS / Linux / WSL)
set +e
MIN_MAJOR=12
OS=$(uname -s)
ISSUES=0
report() { printf '  %-5s %s\n' "$1" "$2"; [[ "$1" == FAIL ]] && ISSUES=$((ISSUES + 1)); }
indent() { sed 's/^/          /'; }
echo "=== pnpm health check ==="

# 1. pnpm runs and prints a version (a binary-less release prints an error instead, see 3.5)
if command -v pnpm >/dev/null 2>&1; then
    PNPM_VER=$(pnpm -v 2>/dev/null)
    if [[ "$PNPM_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        report OK "pnpm $PNPM_VER at $(command -v pnpm)"
        (( ${PNPM_VER%%.*} < MIN_MAJOR )) && report WARN "pnpm major is below $MIN_MAJOR; this guide describes 12.x"
    else
        report FAIL "pnpm is on PATH but 'pnpm -v' prints no version (see 3.5, binary-less release)"
    fi
else
    report FAIL "pnpm not installed"
fi

# 2. More than one pnpm executable on PATH, and corepack shims. Only real files
#    count: a shell function named pnpm is not seen by this non-interactive bash.
PNPM_BINS=$(set -f; IFS=:; for d in $PATH; do
    [[ -n "$d" && -x "$d/pnpm" && ! -d "$d/pnpm" ]] && printf '%s\n' "$d/pnpm"
done | awk '!seen[$0]++')
N=$(printf '%s\n' "$PNPM_BINS" | awk 'NF' | wc -l | tr -d ' ')
if (( N > 1 )); then
    report FAIL "$N pnpm executables on PATH; the first one wins:"
    printf '%s\n' "$PNPM_BINS" | indent
fi
while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    real=$(readlink -f "$b" 2>/dev/null || printf '%s' "$b")
    case "$real" in
        */corepack/*) report FAIL "corepack shim on PATH: $b -> $real (corepack disable pnpm)" ;;
    esac
done <<< "$PNPM_BINS"

# 3. PNPM_HOME, and only its bin/ on PATH
if [[ -n "${PNPM_HOME:-}" ]]; then
    report OK "PNPM_HOME=$PNPM_HOME"
    [[ ":$PATH:" == *":$PNPM_HOME/bin:"* ]] || report FAIL '$PNPM_HOME/bin is not on PATH (global packages will not resolve)'
    [[ ":$PATH:" == *":$PNPM_HOME:"* ]] && report WARN '$PNPM_HOME itself is on PATH (v10 layout); only $PNPM_HOME/bin belongs there'
else
    report WARN "PNPM_HOME unset (pnpm uses its default data dir)"
fi

# 4. The config dir pnpm actually reads, and what is in it
if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then CFG_DIR="$XDG_CONFIG_HOME/pnpm"
elif [[ "$OS" == Darwin ]]; then CFG_DIR="$HOME/Library/Preferences/pnpm"
else CFG_DIR="$HOME/.config/pnpm"; fi
CFG="$CFG_DIR/config.yaml"
if [[ -f "$CFG" ]]; then
    report OK "config.yaml at $CFG_DIR"
    KEBAB=$(grep -nE '^[a-z]+(-[a-z]+)+:' "$CFG")
    if [[ -n "$KEBAB" ]]; then
        report FAIL "kebab-case keys in config.yaml are silently ignored; use camelCase:"
        printf '%s\n' "$KEBAB" | indent
    fi
    grep -qE '^managePackageManagerVersions:' "$CFG" &&
        report WARN "managePackageManagerVersions was removed in pnpm 11 and is ignored; the setting is now pmOnFail"
else
    report WARN "no config.yaml at $CFG_DIR, so no global settings are active"
fi
LINUX_CFG="$HOME/.config/pnpm/config.yaml"
if [[ "$OS" == Darwin && -z "${XDG_CONFIG_HOME:-}" && -f "$LINUX_CFG" ]] && ! [[ "$LINUX_CFG" -ef "$CFG" ]]; then
    report FAIL "$LINUX_CFG exists but pnpm on macOS reads $CFG; link one to the other"
fi
[[ -s "$CFG_DIR/rc" ]] && report WARN "$CFG_DIR/rc is not read by pnpm 12; auth and registry belong in $CFG_DIR/auth.ini"

# 5. Environment variables override config.yaml (names only; values may be secrets)
ENVS=$(env | cut -d= -f1 | grep -iE '^pnpm_config_')
if [[ -n "$ENVS" ]]; then
    report WARN "pnpm_config_* variables are set; each one overrides config.yaml:"
    printf '%s\n' "$ENVS" | indent
fi

# 6. Install sources that collide with the standalone install
if [[ "$OS" == Darwin ]] && command -v brew >/dev/null 2>&1 && brew list pnpm >/dev/null 2>&1; then
    report FAIL "Homebrew pnpm installed; collides with the standalone install"
fi
if command -v dpkg >/dev/null 2>&1 && dpkg -l 2>/dev/null | grep -qE '^ii[[:space:]]+pnpm[[:space:]]'; then
    report FAIL "apt pnpm installed; distro packages lag the standalone install"
fi

# 7. pnpm 10 leftovers in the data dir
if [[ -n "${PNPM_HOME:-}" ]]; then DATA_DIR="$PNPM_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then DATA_DIR="$XDG_DATA_HOME/pnpm"
elif [[ "$OS" == Darwin ]]; then DATA_DIR="$HOME/Library/pnpm"
else DATA_DIR="$HOME/.local/share/pnpm"; fi
for d in store/v10 global/5; do
    [[ -d "$DATA_DIR/$d" ]] && report WARN "pnpm 10 leftover: $DATA_DIR/$d"
done
for s in pnpm pnpx pn pnx; do
    [[ -e "$DATA_DIR/$s" && ! -d "$DATA_DIR/$s" ]] && report WARN "root-level shim $DATA_DIR/$s (v10 layout)"
done

# 8. ~/.npmrc is still read by pnpm 12, so a registry or auth line there applies
if [[ -f "$HOME/.npmrc" ]] && grep -qE '^(registry=|//|_auth)' "$HOME/.npmrc" 2>/dev/null; then
    report WARN "~/.npmrc sets a registry or auth; pnpm 12 reads it"
fi

echo
if (( ISSUES == 0 )); then echo "no critical issues"; else echo "$ISSUES critical issue(s)"; fi
```

<!-- pnpm-doctor:end -->

---

## 2. Fix: remediation recipes

Apply in order; each builds on the previous. **Look before you remove**, and
back up instead of deleting.

### 2.1 Remove conflicting install sources

Each one locks pnpm to a version it controls and cannot `self-update`.

```bash
# Homebrew (macOS)
brew list pnpm >/dev/null 2>&1 && brew uninstall pnpm
# Distro packages (Linux): match the package name exactly
dpkg -l 2>/dev/null | grep -qE '^ii[[:space:]]+pnpm[[:space:]]' && sudo apt remove pnpm
command -v dnf    >/dev/null && dnf list installed pnpm >/dev/null 2>&1 && sudo dnf remove pnpm
command -v pacman >/dev/null && pacman -Q pnpm >/dev/null 2>&1 && sudo pacman -R pnpm
command -v snap   >/dev/null && snap list pnpm >/dev/null 2>&1 && sudo snap remove pnpm
# Corepack shims
corepack disable pnpm 2>/dev/null || true
# npm-installed pnpm
npm ls -g pnpm 2>/dev/null | grep -q pnpm && npm uninstall -g pnpm
```

### 2.2 Back up stale configs

```bash
TS=$(date +%Y%m%d-%H%M%S)
[ -f ~/.npmrc ] && grep -qE '^(registry=|//|_auth)' ~/.npmrc && mv ~/.npmrc ~/.npmrc.pre-cleanup.$TS.bak
for d in ~/.config/pnpm ~/Library/Preferences/pnpm; do
    for f in "$d/config.yaml" "$d/rc"; do
        [ -f "$f" ] && [ ! -L "$f" ] && mv "$f" "$f.pre-cleanup.$TS.bak"
    done
done
```

An `rc` that holds a token: move the token to `auth.ini` in the same
directory, never into `config.yaml` or a tracked file.

### 2.3 pnpm 10 leftovers

```bash
pnpm update --global   # 12.8.0+: moves global/5 packages to global/v11 and removes v10 root shims
ls "$PNPM_HOME"        # then look before removing store/v10 by hand
```

### 2.4 Remove `pnpm setup` appends from shell rc

```bash
grep -nE 'PNPM_HOME|pnpm completion' ~/.zshrc ~/.bashrc ~/.profile 2>/dev/null
```

Edit the block out by hand (it is usually marked `# pnpm`). If the rc is
tracked by dotfiles, edit the tracked copy.

### 2.5 Reinstall pnpm cleanly via standalone

```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

For 12.x the installer fetches `@pnpm/exe.<os>-<arch>` from the npm registry
and checks its signature. It runs `pnpm setup --force`, so it **does append to
your shell rc**: review and revert that (2.4) if the rc is managed.

### 2.6 Wire `PNPM_HOME` and PATH by hand

```bash
# macOS
export PNPM_HOME="$HOME/Library/pnpm"
# Linux/WSL
# export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME/bin:$PATH"      # bin only; $PNPM_HOME itself is NOT on PATH
[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"
```

If you use nvm, keep nvm's bin **before** `$PNPM_HOME/bin` on PATH (section 7).

### 2.7 Create or fix `config.yaml` (camelCase)

```bash
case "$(uname -s)" in Darwin) D="$HOME/Library/Preferences/pnpm" ;; *) D="$HOME/.config/pnpm" ;; esac
mkdir -p "$D" && cat > "$D/config.yaml" <<'YAML'
minimumReleaseAge: 4320     # 3 days; see the Appendix
blockExoticSubdeps: true
verifyStoreIntegrity: true
trustPolicy: no-downgrade
globalShims: false          # only if nvm (or another manager) owns `node`; section 7
YAML
```

Sharing one file across macOS and Linux: keep it at `~/.config/pnpm/config.yaml`
and link it on macOS (`ln -sfn ~/.config/pnpm/config.yaml
~/Library/Preferences/pnpm/config.yaml`). Do not export `XDG_CONFIG_HOME`
globally for this: helm, gh, kubectl, neovim and others move their config too.

> **This box:** `supportedArchitectures` (and `python`, `cargo`) were removed from
> the global file on 2026-10-06: pnpm 12 ignores them there, and the defaults are
> what we wanted. Pin them per project in `pnpm-workspace.yaml` if one needs it.
> `pnpm-config-check` names any key the global file holds that pnpm ignores. 7.4.

### 2.8 Reinstall global packages

```bash
pnpm add -g <pkg1> <pkg2> ...
ls "$PNPM_HOME/bin/"
```

---

## 3. Verify: prove it works

### 3.1 The config file is read

Set a harmless key in the real file, read it back with the environment
cleared, then remove it:

```bash
env -i PATH="$PATH" HOME="$HOME" pnpm config get minimumReleaseAge
```

A number means the file is read. `undefined` means the file is not where pnpm
looks (section 0), or the key is spelt kebab-case. Without `env -i`, an exported
`PNPM_CONFIG_*` answers instead and the check proves nothing.

### 3.2 The cooldown is enforced (two arms)

`minimumReleaseAge` makes a **range** (`next@canary`, `^1.2.0`) quietly resolve
to an older, mature version: no error, nothing to see. Only an **exact** pin
of a too-young version fails. So test with an exact pin, and run the same
install with the setting overridden as the control:

```bash
T=$(mktemp -d "${TMPDIR:-/tmp}/pnpm-cooldown.XXXXXX"); printf '{"name":"t","version":"1.0.0"}\n' > "$T/package.json"
cp -R "$T" "$T-ctl"
YOUNG=$(pnpm view next dist-tags.canary)           # next ships a canary most days
pnpm -C "$T"     add "next@$YOUNG" --lockfile-only --ignore-scripts                              # expect ERR_PNPM_NO_MATURE_MATCHING_VERSION
pnpm -C "$T-ctl" add "next@$YOUNG" --lockfile-only --ignore-scripts --config.minimumReleaseAge=0  # expect success
```

The error names the publish time and the cutoff. Both succeed: the canary is
older than your window; pick another fast-moving package. Both fail: the
problem is not the cooldown. Measured 2026-10-06: `next@16.4.0-canary.61`
failed under 4320 and installed under the override, while `next@canary`
resolved silently to `16.4.0-canary.58`. (`--config.<key>=<value>` applies
every setting since 12.8.0.)

### 3.3 Global binaries resolve

```bash
ls "$PNPM_HOME/bin/"
command -v <some-global-binary>    # should be under $PNPM_HOME/bin/
```

### 3.4 Install fails with `EBADF` / `ERR_PNPM_META_FETCH_FAIL`: check per-binary firewalls first

Not re-measured on 12.x; written against 11.x.

```
[WARN] GET https://registry.npmjs.org/<pkg> error (EBADF). Will retry...
[ERR_PNPM_META_FETCH_FAIL] GET https://registry.npmjs.org/<pkg>: fetch failed
```

**Most common cause on macOS: a per-binary firewall** (Little Snitch, LuLu,
Murus) dropping pnpm's connections while letting `curl`, `node` and `bun`
through. Rules key on the executable path, so a rule for `node` does not cover
pnpm. Note pnpm 12 is a native binary, so its path is the `pnpm` executable
under `$PNPM_HOME`, not `node`.

Four probes, in under 30 seconds:

```bash
PKG='@scope/pkg-that-fails'
curl -sI -m 5 "https://registry.npmjs.org/${PKG//\//%2F}" | sed -n 1p                 # 1. curl
node -e "fetch('https://registry.npmjs.org/${PKG//\//%2F}').then(r=>console.log(r.status)).catch(e=>console.error(e.cause?.code||e.message))"  # 2. node
bun add -g "$PKG"                                                                    # 3. bun
pnpm add -g "$PKG"                                                                   # 4. pnpm
```

1-3 pass and only 4 fails: a per-binary firewall. Allow pnpm to
`*.npmjs.org` in the firewall's rules; check VPN split tunnels and corporate
MDM allow-lists. Changing `userAgent`, network concurrency, DNS order, the
store or the cooldown does **not** fix it (fetch fails before any policy runs).

### 3.5 `pnpm -v` prints an error instead of a version: a binary-less release

pnpm ships its native binary in a per-platform package and swaps it over a
placeholder at install time. Twice (11.12.0 and 11.13.0, fixed in 11.13.1) a
release was published **without** the binary, leaving a 34-byte placeholder:

```text
.../pnpm: line 1: This: command not found   # exit 127
```

`self-update` still printed "Successfully updated". The doctor (section 1)
reports it as "prints no version".

Check a version before taking it. The package name changed in 12.x:

| pnpm | Platform package (macOS arm64 shown)                                              |
| ---- | --------------------------------------------------------------------------------- |
| 12.x | `@pnpm/exe.darwin-arm64` (also `linux-x64`, `linux-x64-musl`, `linux-arm64`, ...) |
| 11.x | `@pnpm/macos-arm64` (also `linux-x64`, `linuxstatic-x64`, ...)                    |

```bash
curl -s https://registry.npmjs.org/@pnpm/exe.darwin-arm64/<version> | jq -r '.dist.unpackedSize'
```

A real binary is tens of MB (12.4.2-12.10.0: about 36-45 MB, 12.10.0 is
40.3 MB; 11.x: about 141 MB); a broken one is about 2 KB. Anything under 1 MB is broken. pnpm
12.9.0's binary contains an `ERR_PNPM_BROKEN_PNPM_RELEASE` error code, which
suggests pnpm now guards this itself; not tested.

**Recover**: the broken pnpm cannot update itself. Find a good binary already
on disk (for 12.x: `$PNPM_HOME/global/v11/*/node_modules/pnpm/pnpm`, and older
ones under `$PNPM_HOME/package-manager-store/v11/`), run its `self-update
<good-version>` directly, or reinstall with the standalone installer (2.5).

> **This box:** `pnpm_update` runs this check against the version it then passes
> to `pnpm self-update` by name, so the checked version is the installed one; if
> pnpm lands anywhere else it exits 1 with the roll-back command (D-20261006-A01,
> section 7.3).

### 3.6 Running pnpm inside a sandbox (Claude Code and similar)

Reported by this round's sandbox investigation on 12.9.0, not re-measured
here: installs and `dlx` fail at the store lock before any network call,
because the lock is a fixed `/tmp/pnpm-store-operation-locks-<uid>/` that
only `XDG_RUNTIME_DIR` (an existing directory) moves; `dlx` also needs
`PNPM_CONFIG_CACHE_DIR`. The proxy certificate failure seen on 11.x/12.4
(`OSStatus -26276`) no longer occurs on 12.9.

> **This box:** the `pnpm()` function in `home/.zshrc` sets both, for that one
> command, only when `/tmp` is not writable, pointing at one per-user directory
> `/tmp/claude-$UID/pnpm-runtime` (D-20261006-A07). Measured in a fresh session:
> `command pnpm dlx semver@7.6.3 1.2.3` exit 1, `pnpm dlx ...` exit 0. Section 7.6.

---

## 4. Set up clean from scratch

```bash
# 1. Install (standalone). It appends to your shell rc; revert that if the rc is managed (2.4).
curl -fsSL https://get.pnpm.io/install.sh | sh -
# 2. In a shell rc you own (or the tracked copy of it):
#      export PNPM_HOME="$HOME/Library/pnpm"        # Linux: $HOME/.local/share/pnpm
#      export PATH="$PNPM_HOME/bin:$PATH"
#      [ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"
# 3. Completion
pnpm completion zsh > "$PNPM_HOME/_pnpm"
# 4. Config: recipe 2.7
# 5. Verify, in a fresh shell
pnpm -v && bash pnpm-doctor.sh
```

Then run 3.1 and 3.2.

---

## 5. Do's and don'ts

### DO

- **Install via the standalone installer.** It is the only source that
  supports `pnpm self-update`.
- **Use camelCase in `config.yaml`.** Kebab-case belongs in `auth.ini` and
  `.npmrc`.
- **Put auth tokens in `auth.ini`,** never in `config.yaml` or a tracked file.
- **Verify by behaviour** (3.2), and read config back with `env -i` (3.1).
- **Put only `$PNPM_HOME/bin` on PATH.**
- **Bridge the macOS path with a symlink** if one file serves Mac and Linux.

### DON'T

- **Don't run `pnpm setup`** in a managed shell rc.
- **Don't read `undefined` from `pnpm config get` as "off".** It means "not
  set" (section 0).
- **Don't trust "no warning" for a key.** Unknown and removed keys are
  silently accepted.
- **Don't keep auth in `rc`.** pnpm 12 does not read it.
- **Don't set `managePackageManagerVersions`.** It was removed in pnpm 11 and
  is ignored. Its replacement is `pmOnFail` (`pmOnFail: ignore` = the old
  `false`), typed and honoured on 12.9.0.
- **Don't install pnpm via Homebrew, apt, dnf, pacman, snap, npm or Corepack.**
- **Don't export `XDG_CONFIG_HOME` globally** to unify pnpm's path on macOS.

---

## 6. References

- Installation: <https://pnpm.io/installation>
- Settings (defaults live here, not in `pnpm config get`): <https://pnpm.io/settings>
- `pnpm self-update` (accepts `[VERSION]`; picks by the global
  `minimumReleaseAge`): <https://pnpm.io/cli/self-update>
- `pnpm config`: <https://pnpm.io/cli/config>
- Completion: <https://pnpm.io/completion>
- Release notes: <https://github.com/pnpm/pnpm/releases>
- Binary-less-release bug (3.5), all closed 2026-07:
  <https://github.com/pnpm/pnpm/issues/12955>,
  <https://github.com/pnpm/pnpm/issues/12962>,
  <https://github.com/pnpm/pnpm/issues/13067>.

---

## Appendix: `config.yaml` reference

Defaults from <https://pnpm.io/settings> (2026-10-06); `pnpm config get`
cannot show them.

```yaml
# Refuse versions younger than N minutes. Default 1440 (1 day) since v11.
# Exact pins fail; ranges quietly resolve older (3.2).
minimumReleaseAge: 4320

# Refuse transitive deps from git or tarball URLs. Default true. Typed
# (a bad value is rejected) but reads back undefined.
blockExoticSubdeps: true

# Re-check store contents on install. Default true; pin it anyway.
verifyStoreIntegrity: true

# Refuse a version whose publish trust is weaker than earlier ones. Default off.
trustPolicy: no-downgrade

# Keep pnpm's own node/npm shims out of $PNPM_HOME/bin when another manager owns node.
globalShims: false
```

Not here:

- `preferFrozenLockfile`: default **true**; it means "skip resolution when the
  lockfile already matches", not "refuse lockfile updates". Measured on 12.10.0
  (2026-10-10) with a `package.json` edited after the lockfile was written:
  on a developer machine `true` and unset both rewrite the lockfile (exit 0);
  with `CI=true` both fail `ERR_PNPM_OUTDATED_LOCKFILE`, and only `false` lets
  CI rewrite it. So an explicit `true` is the same as the default. (Before
  12.8.0 an explicit `true` let CI update the lockfile.) To refuse lockfile
  changes on a developer machine, use `pnpm install --frozen-lockfile`.
  > **This box:** the global file pins `true` like the other defaults it pins;
  > its comment said it refused lockfile updates until 2026-10-10.
- `managePackageManagerVersions`: removed; use `pmOnFail`.
- Anything in kebab-case.
- Auth tokens: `auth.ini`.

## 7. pnpm 12 on this box (2026-09-19, ruling D-20260919-06)

> **7.0 Read this history against 12.9.0 (re-checked 2026-10-06).** Sections 7
> to 7.2 are kept as written on 12.4.1, because six rulings (D-20260919-A06,
> -A08 to -A11, D-20260920-A01) name them as where their reasoning lives. What
> has moved since, so nobody acts on the old line:
>
> - **The box runs 12.10.0** (since 2026-10-10, section 7.3). "12.4.2 is the
>   next target" and "12.5.x not a target yet" are past.
> - **Floor `12.10.0`** since 2026-10-10 (section 7.8). Before that it was 12.8.2
>   from 2026-10-06, and 12.3.2, below the 12.4.2 security patch. A floor only
>   rises (section 7.5).
> - **`blockExoticSubdeps`** reads back `undefined` because pnpm 12 IGNORES it in
>   the global file (a global `false` still blocks). It is on by default, and is
>   now pinned by `PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS=true` (section 7.4).
> - **7.1 "Known keys are typed"** no longer covers `supportedArchitectures`:
>   12.9.0 accepts `os: banana`. 12.9.0 also accepts the 12.5 list form. On
>   12.9.0 the **global** pin did not change what installed; the same key in a
>   project's `pnpm-workspace.yaml` did. Removed from the global file (section 7.4).
> - **7.1 "`--config.engineStrict=true` did nothing"**: it works since 12.8.0.
>   Re-measured on 12.10.0 (2026-10-10): the file key, `--engine-strict` and
>   `--config.engineStrict=true` all fail the `engines.node: "<1"` probe with
>   `ERR_PNPM_UNSUPPORTED_ENGINE`; unset, it installs.
> - **7.1 "a mutant ... fails 3 of 10"** cannot be reproduced. Since 2026-10-06
>   `zsh-node-functions-selftest` has 38 checks, passes inside and outside the
>   sandbox, and refuses by name (exit 2) when it cannot make its temp dir.
> - **7.1 "entry 1 versus entry 22"**: on 2026-10-06 nvm's bin was entry 18 and
>   pnpm's entry 23. The order still holds; the numbers were never stable.
> - **"Three class projects under ~/CODE pin engines"**: on 2026-10-06, 0 of
>   124 `package.json` files used `devEngines.runtime` or `engines.runtime`
>   (6 pin `engines.node` only, which does not switch Node).
>   `globalShims: false` still stands on the one-owner-per-name argument.
> - **7.2 has a third blind spot**: `pnpm_update` names one version and
>   `self-update` lands on another (12.8.2 named, 12.9.0 installed on
>   2026-10-06). Fixed the same day (section 7.3).

The v12 jump was deliberately deferred on 2026-09-04 (11.25.0 taken, major skipped) until
two prerequisites were met. On 2026-09-19 Gavin took **12.4.1** by hand with `pnpm_update`,
and the records were brought in line afterwards. State as measured that evening:

| Prerequisite                                     | State                                                                                     |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `globalShims: false` (nvm owns `node`)           | Was UNSET (default on). Now set in `home/.config/pnpm/config.yaml`; pnpm reports `false`. |
| HTTPS -> SSH url rewrites (SSH-only box)         | Already present: four per-organisation `url.<alias>.insteadOf` entries in git config.     |
| No unknown keys in project `pnpm-workspace.yaml` | Not re-audited. A project pinning a pnpm version fails loudly on one, so it self-reports. |

**Floor: `12.3.2`**, in `install.sh` and `home/.zsh_onboarding`, and they must agree. It is the
lowest SANE v12, not the lowest v12:

- `12.3.0` breaks global `node`/`npm`/`yarn` after self-update (`unexpected argument '--shim'`); `12.3.1` fixes it. Never land on 12.3.0.
- `12.3.2` fixed the npm wrapper so a v11 install can reach v12 through the version store.

**Why `globalShims: false` rather than testing the interaction.** Inside any project that pins
a runtime via `devEngines.runtime` or `engines.runtime`, the default makes `node` run pnpm's
own downloaded Node instead of nvm's. Three class projects under `~/CODE` pin engines today.
Two systems answering one command name is the failure class this repo keeps meeting
(shell function vs PATH shim, `gh` wrapper vs binary); one owner per name, and nvm was here
first. A project that wants pnpm-managed Node opts in per-project.

**The comments in `config.yaml` that say "pnpm 11 default" are kept as history.** Measured
under 12.4.1 with `pnpm config get` on all 11 keys: 10 read back their configured value and
`pnpm --version` prints no warning. **One does not: `blockExoticSubdeps` reads `undefined`
and is absent from `pnpm config list`** (control: `trustPolicy` present). Resolved the same
evening from the docs, not from a probe: the setting was added in v10.26.0 and its DEFAULT is
`true` in v12 (pnpm.io/settings/dependency-resolution), so the guard is in force whether or
not the explicit pin is honoured, and the `undefined` is a read-back gap in `pnpm config get`,
not a removed key. There is no per-package exception (pnpm discussions #10413); the workarounds
are `overrides` or a pnpmfile. Strength: "in force by default per docs". Nobody has run an
install with an exotic subdep against 12.4.1 on this box; do that if it ever matters.

**12.x after the upgrade (researched 2026-09-19).** `12.4.2` (Sep 15) is a SECURITY patch:
dependency executables could take over another package's POSIX bin shim through its shell
helpers, and GitHub Actions links could leak server credentials. No CVE id was published.
Reinstalling dependencies replaces the vulnerable shims. It clears the 3-day cooldown, so it
is the next `pnpm_update` target. `12.5.0`/`12.5.1` (Sep 18) add a Python ecosystem,
`supportedArchitectures` platform names, `concurrencyGroups` and a `tools` block; one day
old and a large surface, not a target yet.

### 7.1 Hardening round two (approved 2026-09-19, landed 2026-09-20, rulings D-20260919-08 to -11)

Four items approved in one round the evening 12.4.1 went live. Each has its own register
block and its own commit. Everything below was measured on 12.4.1; `pnpm config get` reads
several of these keys back as `undefined`, so each key names the POSITIVE arm that proved
acceptance. Two facts about the 12.x config parser that the probes turned up:

- **Unknown keys are silently accepted** (`bogusKeyXyz: banana` -> `pnpm --version` exits 0).
  "No warning" therefore proves nothing about a key.
- **Known keys are typed.** A wrong type fails EVERY pnpm command with `load configuration ...
invalid boolean` (or `did not match any variant of untagged enum`). A typed rejection is a
  positive arm: the schema knows the key.

**Platform and ecosystem pins (D-20260919-08).**

| Key                      | Value                      | Arm                                                                                                                                       |
| ------------------------ | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `supportedArchitectures` | `{os,cpu,libc: [current]}` | Typed (`os: banana` rejected); behaviour: os:[linux] pin installed `@esbuild/linux-x64` only, `current` installed `@esbuild/darwin-arm64` |
| `python.enabled`         | `false`                    | Typed (`enabled: banana` -> invalid boolean) on 12.4.1, before the 12.5 Python ecosystem exists                                           |
| `cargo.enabled`          | `false`                    | Typed, same probe                                                                                                                         |

The 12.5.0 platform-list form (`- darwin-arm64`) is REJECTED by 12.4.1 at parse time and
would break every pnpm command on this box, so the object form stays until the floor passes
12.5. The literal `current` is what keeps one stowed file correct on macOS, Linux and WSL.

**Policy knobs (D-20260919-09).** All four read back through `pnpm config get`.

| Key                       | Value                                   | What changes for `pnpm install` in an existing project                                                                                                                                                   |
| ------------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `trustPolicyExcludePrune` | `true`                                  | After a lockfile rewrite, `trustPolicyExclude` name@version entries no longer in the lockfile are dropped (`@scope/*` patterns kept).                                                                    |
| `audit.ignorePrune`       | `true`                                  | Nothing on install; `pnpm audit --fix` drops `audit.ignore` entries no longer reported.                                                                                                                  |
| `sideEffectsCache`        | `read: true, write: true, remote: null` | Nothing; local build cache as before, no pnpr server. `remote: false` is rejected by the parser, `null` accepted.                                                                                        |
| `engineStrict`            | `true`                                  | **Can fail.** A dependency whose `engines` excludes the running Node aborts with `ERR_PNPM_UNSUPPORTED_ENGINE` instead of a warning. Per-project relief: `engineStrict: false` in `pnpm-workspace.yaml`. |

The engineStrict behaviour arm: a `file:` dependency declaring `engines.node: "<1"` installed
with the key unset and failed with the key set. `--config.engineStrict=true` on the command
line did nothing; `--engine-strict` and the file key both work.

**`pnpm_update` deny list (D-20260919-10).** A floor says "not below"; it cannot say "never
this one". `PNPM_DENY_VERSIONS` in `home/.zsh_node_functions` holds `version|reason` entries
(first: `12.3.0`, the global node/npm/yarn breakage fixed in 12.3.1) and is consulted at both
places the function can land on a version: before the eligible-version download (refuse, print
the reason, exit 1, no `self-update`) and after the blind fallback `self-update` that runs when
the eligible version is unknown (the landed version is checked and a roll-back command printed).
The floor is unchanged. Selftest:

```bash
zsh-node-functions-selftest   # 17 checks; the deny-list arms: denied refused, allowed passes, empty list passes, fallback
```

It sources the real file with pnpm and the network stubbed; a mutant with the gates
disconnected fails 3 of 10.

**PATH-order banner check (D-20260919-11).** `globalShims: false` keeps `node` with nvm only
while nvm's bin precedes `$PNPM_HOME/bin` on PATH (entry 1 versus entry 22 in a login shell
on 2026-09-19). `__welcome_pnpm_path_check` in `home/.zsh_welcome` runs beside the nvm block
of the full banner and is exception-based: nothing when the order is right, one red line when
pnpm's bin comes first, one red line when no nvm bin is on PATH at all. Selftest:

```bash
zsh-welcome-selftest          # 8 checks: correct order silent, reversed warns, nvm missing warns, Linux bin dir
```

It extracts the real function from the file by name (the file runs the banner at source time)
and drives it with fixture PATH strings.

### 7.2 Two blind spots in `pnpm_update`, found taking 12.4.2 (2026-09-20, ruling D-20260920-01)

`pnpm_update` said "12.4.1 is the latest eligible version" twice while 12.4.2, a security
patch, had been on the registry for four days. Both causes were measured and fixed the same
night; both have arms in `zsh-node-functions-selftest`.

| Blind spot                                                                                                                                                                                                  | Fix                                                                                                                                                                                                                                                                                       |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The version cache (`~/.cache/dotfiles/pnpm_latest3`) is trusted for `PNPM_CHECK_TTL_DAYS` (7). It was written on 15 Sep, hours before 12.4.2 shipped, so nothing asked the registry again.                  | `pnpm_update` now calls `__pnpm_live_dist_tag` (one 5-second registry call) every run and, when it disagrees with the cached raw, runs `__pnpm_refresh_latest_sync` in the FOREGROUND before choosing a target. The banner keeps the cheap cached path. Offline: the cache still answers. |
| `__pnpm_platform_pkg` returned the pnpm 11 artifact name (`@pnpm/macos-arm64`). pnpm 12 ships `@pnpm/exe.<os>-<arch>[-musl]`. The metadata GET 404'd, the guard answered `unknown`, and unknown fails OPEN. | The helper takes the target version and picks the naming by major: `@pnpm/exe.darwin-arm64` for 12.x, `@pnpm/macos-arm64` for 11.x (both verified live: binary=ok). Fail-open on `unknown` stays; offline must not block an update.                                                       |

The refresh body is now one function (`__pnpm_refresh_latest_body`) with a background wrapper
(`&!`) and a foreground wrapper, so the two paths cannot drift.

```bash
zsh-node-functions-selftest   # 17 checks: deny list, live dist-tag gate (stale / agrees / offline), platform names v12 vs v11
```

### 7.3 A third blind spot: the target it named was not the version it installed (2026-10-06, W-20261006-A29)

On 6 Oct `pnpm_update` printed `Updating pnpm 12.6.0 -> 12.8.2` and then installed 12.9.0. Two
causes, both measured, both fixed the same day:

| Cause                                                                                                                                                                           | Fix                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| It ran a bare `pnpm self-update`, so pnpm chose its own target (the newest version past the cooldown, 12.9.0). The deny list and the binary guard had checked 12.8.2.           | It now runs `pnpm self-update "$eligible"`, so the version the gates check is the version that installs. pnpm still applies `minimumReleaseAge` to a named version.              |
| The cache went stale only when the NEWEST release cleared the cooldown (12.9.1, next day). 12.9.0 cleared it at 9:27 AM with the newest release unchanged, and nothing noticed. | The cache records `next_eligible_at`, the earliest moment ANY version newer than `eligible` clears the cooldown, and `pnpm_update` refreshes in the foreground once that passes. |

**Ruled by Gavin 2026-10-06:** `pnpm_update` names the version it checked. If pnpm still lands on a
different version, it FAILS (exit 1): it names both versions, checks the landed one against the deny
list, and prints the roll-back command. It also sets `pmOnFail=ignore` for its own calls, so it always
updates the machine's pnpm even when run inside a project that pins another version. The cooldown
reader honours `PNPM_CONFIG_MINIMUM_RELEASE_AGE` before `config.yaml`, as pnpm does.

```bash
zsh-node-functions-selftest   # 31 checks; replays 6 Oct (12.6.0, eligible 12.8.2, pnpm's own pick 12.9.0)
```

**Measured 2026-10-10, the first real named `self-update`:** `pnpm_update` printed
`Updating pnpm 12.9.0 -> 12.10.0`, pnpm printed `Switching pnpm from v12.9.0 to v12.10.0`, and
`pnpm -v` then printed `12.10.0` (exit 0). The version it named is the version that installed. It
skipped 12.9.1 because 12.10.0 (published 4:24 PM Tue 6 Oct) had also cleared the 3-day wait at
4:24 PM Fri 9 Oct. The welcome banner seen just before the update still offered `↑12.9.1`. When
that banner was drawn is not known, and the update rewrote the cache it read, so whether the banner
was stale is not settled.

### 7.4 Keys pnpm 12 ignores in the global config, and `pmOnFail` (2026-10-06, W-20261006-A33, A42)

**pnpm 12 silently ignores some keys in the global `config.yaml`.** Measured on 12.3.4, 12.6.0 and
12.9.0 against a scratch copy, with the `PNPM_CONFIG_*` variables removed:

| Key                               | Evidence it is ignored globally                                                                                           | What we do now                                                                               |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `supportedArchitectures`          | a global `os: [linux]` still installed `@esbuild/darwin-arm64`; the same pin in `pnpm-workspace.yaml` installed linux-x64 | removed; the default (`current`) is what we wanted                                           |
| `python.enabled`, `cargo.enabled` | read back `undefined`; 11.1.2 warns they "cannot be set in the global config file"                                        | removed; the defaults (`false`) are what we wanted                                           |
| `blockExoticSubdeps`              | a global `false` still blocks; a project's `false` wins over a global `true`                                              | pinned by `PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS=true` in `home/.zshrc`, which outranks a project |

So the 7.1 table's `supportedArchitectures`, `python.enabled` and `cargo.enabled` rows, and 7's
"read-back gap, not a removed key" for `blockExoticSubdeps`, were wrong: the original arms were
project pins, never the global file. **`undefined` from `pnpm config get` is the tell:** every key
proven honoured by behaviour reads back its value, every key proven ignored reads `undefined`.

```bash
pnpm-config-check            # exit 0 = every key honoured; 1 = names each ignored key; 2 = INVALID
pnpm-config-check --selftest # 6 arms, including "an env value does not mask an ignored key"
```

**`pmOnFail: warn` is set globally (Gavin's pick).** pnpm 12.9.0 honours it in the global file (the
old note saying pnpm rejects it there was pnpm 11). Unset, a project pinned to `pnpm@11.1.2` downloaded
and ran 11.1.2, which carries 17 advisories, ignores six of our keys and skips `pnpm_update`'s cooldown,
deny list and floor. With `warn`, it runs the machine's pnpm and prints one line
(`This project is configured to use 11.1.2 of pnpm`). Measured in a scratch project: 12.9.0, exit 0,
no lockfile written. It is NOT exported as `PNPM_CONFIG_PM_ON_FAIL`, because an env value outranks a
project's own `pmOnFail`.

**`updateNotifier: false`.** pnpm's own "Update available" notice ignores `minimumReleaseAge` and
points at a bare `self-update`. Measured with a fresh state dir: the notice printed once without the
key and not at all with it. The welcome banner reports updates with the cooldown applied.

### 7.5 The floor moves to 12.8.2, and only ever rises (2026-10-06, W-20261006-A36, W-20260923-A51)

> **Superseded 2026-10-10:** the floor is now `12.10.0` (section 7.8). The rule below, that a floor
> only rises, still stands.

**Floor: `12.8.2`** (Gavin's pick), in `install.sh` and `home/.zsh_onboarding`, which must agree. It is
the lowest v12 with every security fix that matters on these machines and none of the known
regressions:

| Version | Security fix                                                                                                                   | Regression                                                            |
| ------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| 12.4.2  | a dependency could take over another package's bin shim (not WSL)                                                              | --                                                                    |
| 12.6.0  | the same shim fix for WSL (`cygpath`), which reaches mlbox                                                                     | could hang on SIGTERM as PID 1 (fixed 12.8.2)                         |
| 12.7.0  | env leak through a `userAgent` placeholder; `storeDir` inside the workspace skipped build approval; injected hard-link rewrite | forced full reinstall with injected workspace packages (fixed 12.8.2) |
| 12.8.0  | --                                                                                                                             | dropped the executable bit on `file:` deps (fixed 12.8.1)             |

None of these has a GHSA or CVE, so `toolchain-cve-check` reports 12.3.2 and 12.8.2 alike as clean;
the floor follows the release notes, not the advisory feeds. Moving the floor with the installed
version was rejected: a bare self-update can land below a floor that has not cleared the cooldown.

**A floor only ever rises.** `home/.zsh_onboarding` used `${PNPM_MIN_VERSION:-12.3.2}`, so an older
value inherited from a parent shell or a long-running session won silently (measured: an inherited
12.3.2 stayed 12.3.2). It now keeps the HIGHER of the inherited value and the file's, numerically
(`is-at-least`, so 12.10.0 beats 12.8.2), and an unparseable value loses. The same applies to
`NVM_MIN_VERSION`. `install.sh` assigns its floor and never inherits one.

```bash
zsh-node-functions-selftest   # 36 checks; section 7 proves the floor only rises (old code fails 3)
```

A session started before this change still carries the old value in its environment until it is
restarted; `toolchain-cve-check` reads the floor from there.

### 7.6 pnpm inside a sandboxed Claude session (2026-10-06, W-20260921-A41)

Inside the Claude Bash sandbox, `pnpm install` and `pnpm dlx` died before any network call with
`ERR_PNPM_STORE_DIR_OPEN_OPERATION_LOCK`. pnpm 12 keeps its store operation locks in a literal
`/tmp/pnpm-store-operation-locks-<uid>/`, and the sandbox only lets a command write under
`/tmp/claude*`. No pnpm setting or `PNPM_*` variable moves it; `--store-dir` and `--state-dir` do
not. Only `XDG_RUNTIME_DIR` does, and it must name a directory that already exists. `dlx` then also
needs a writable cache (`PNPM_CONFIG_CACHE_DIR`).

**The fix (Gavin's pick):** the `pnpm()` function in `home/.zshrc` sets both, for that one command,
only when `[[ -w /tmp ]]` is false (it is false sandboxed and true outside). They point at ONE
stable per-user directory, `/tmp/claude-$UID/pnpm-runtime`, not a per-session one: two sessions
sharing the sandbox's fallback store must still lock each other out. A terminal and an
unsandboxed run are untouched. Rejected: exporting both from a SessionStart hook (it changes
unsandboxed runs too, which would stop sharing the lock with the terminal on the real store), a
sandbox `allowWrite` entry (does not fix `dlx`, and is tied to one machine's paths), and
`excludedCommands` for pnpm (runs third-party `dlx` code with no sandbox).

Measured 2026-10-06 on 12.9.0, sandboxed: `command pnpm dlx semver@7.6.3 1.2.3` exit 1 at the
cache, the function exit 0 printing `1.2.3`; `pnpm install --lockfile-only` through the function
wrote its lockfile, and the lock files appeared under the per-user dir. Live A/B in a fresh
session in a herdr tab gave the same two answers. The `OSStatus -26276` certificate failure that
used to follow the cache fix is gone on 12.9.0. A hook that runs pnpm under `sh -c` does not see
the zsh function.

### 7.7 Intel Macs use the standalone pnpm too (2026-10-06)

Gavin: "whatever you are doing on the current machine which is the silicon M4 mac mini, do the
same for the Intel Mac (if the intel architecture allows that)". It does:

- pnpm publishes a native Intel build, `@pnpm/exe.darwin-x64` (12.8.2 and 12.9.0 both present, a
  `Mach-O 64-bit executable x86_64`). The reason Intel used Homebrew was pnpm 11's standalone
  executable, a Node.js SEA binary that segfaulted on Intel (nodejs/node#62893, pnpm#11423), closed
  fixed in May; pnpm 12's binary is native, not Node.
- 12.9.0's Intel build ran on the M4 under Rosetta and printed `12.9.0` (exit 0); the arm64 build
  forced to x86_64 refused with `Bad CPU type` (the control). Rosetta runs a subset of what real
  Intel hardware does, so a binary that runs under it should run on machine B. Not yet run ON B.
- Homebrew pnpm skipped the cooldown, the deny list and the binary check (it shipped 12.9.1 while
  12.9.1 was still inside the 3-day wait).

What changed: `_pnpm_use_homebrew` in `install.sh` is always false, so on B the pre-flight plans
the Homebrew pnpm's removal and HOLDS it until the standalone pnpm runs (W-20261005-A75).
`pnpm_update` and the onboarding prompt no longer run `brew upgrade pnpm`; while a Homebrew pnpm
is still the one on PATH they point at `./install.sh` instead (`__pnpm_is_homebrew_bin`).

```bash
zsh-node-functions-selftest   # 38 checks; section 8 is the Intel path, brew stubbed to record
```

### 7.8 The floor moves to 12.10.0 (2026-10-10, ruling D-20261010-A02)

**Floor: `12.10.0`** (Gavin's pick, 2026-10-10), in `install.sh` and `home/.zsh_onboarding`, which
must agree. Same rule as 7.5: the lowest v12 with every security fix that matters and no known
regression. The box took 12.10.0 the same morning (7.3). Security fixes in 12.10.0, from its
release notes (none has a GHSA or CVE, so `toolchain-cve-check` cannot see them):

- `pnpm install` stops a dependency version with path traversal from writing files outside the
  global virtual store.
- Locked config dependencies are checked against their registry, and must come from an npm
  registry; the lockfile can no longer replace a pinned config dependency's integrity.
- Tarballs inside a `variations` resolution are checked against the registry; an empty
  `variations` resolution is rejected.
- `pnpm audit signatures` checks against the integrity recorded in the lockfile.
- Archive metadata over 64 MiB is rejected before it is read into memory.
- Two URL or path dependencies that differ only in `+ # : ?` versus `/` no longer share a
  virtual store directory.
- The warning about an ignored project `.npmrc` registry setting no longer prints a URL-scoped
  username and password.

**No known regression.** 12.10.1 (published 4:37 AM Wed 7 Oct, clears the 3-day wait 4:37 AM
Sat 10 Oct) fixes the experimental `nodeLinker: { type: loaded }`, which this box does not use,
and bugs its notes do not say 12.10.0 introduced. One change to expect: the registry metadata
cache moved to `<cache-dir>/v12/`, so the first install after the upgrade downloads metadata again.

A machine below the floor is told to update at login. A shell or session started before the bump
still carries 12.8.2 until it is restarted (7.5); `toolchain-cve-check` reads the floor from there.
