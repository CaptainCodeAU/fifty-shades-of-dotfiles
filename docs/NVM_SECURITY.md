# nvm / Node.js security hardening

Layered hardening for nvm and the Node runtime, modeled on the pnpm posture
([`PNPM_AUDIT_TREE.md`](PNPM_AUDIT_TREE.md), `PNPM_SETUP_GUIDE.md`). nvm's attack
surface is smaller than pnpm's — one vendor (nodejs.org), checksummed downloads,
versus pnpm's thousands of third-party packages — so this is a focused subset, not
a 1:1 clone. Notably it deliberately does **not** add a `minimumReleaseAge`-style
cooldown: delaying a runtime's security patches would be counterproductive.

## Threat model

| Risk                                                                                                                                            | Mitigation here                                                            |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **nvm itself is vulnerable** (CVE-2026-10796, High 7.5: RCE via a malicious Node mirror's version strings; affects nvm <= 0.40.4, fixed 0.40.5) | `NVM_MIN_VERSION` floor + pinned installer (Layer 1)                       |
| **Malicious / planted download mirror** (the CVE vector)                                                                                        | Official-mirror pin (Layer 2) + independent verifier (Layer 5)             |
| **Running an end-of-life Node** (no security patches)                                                                                           | `NODE_MIN_MAJOR` EOL guard (Layer 3) + preflight sweep (Layer 4)           |
| **Tampered Node binary that passes nvm's own checksum** (mirror serves matching bad SHASUMS)                                                    | `nvm-verify-node` re-checks against official, GPG-signed SHASUMS (Layer 5) |

`.nvmrc` auto-switching is **not** a vector here: `load-nvmrc` (in `.zshrc`) only runs
`nvm use` for an already-installed version (`!= "N/A"`); walking into a cloned repo
never triggers an arbitrary Node download.

## Layer 1 — nvm version floor + pinned installer

- `NVM_MIN_VERSION` (currently `0.40.5`) is defined in **both** `install.sh` and
  `home/.zsh_onboarding` (kept in sync, like `PNPM_MIN_VERSION`).
- `install.sh` installs/upgrades nvm by pinning exactly `v${NVM_MIN_VERSION}` — never
  the mutable `master` ref the onboarding handler previously used. It now also
  **upgrades** an existing-but-below-floor nvm (the install block used to only ever
  install when `~/.nvm` was absent).
- Onboarding nudges (once per 24h, interactive only) when the installed nvm is below
  the floor, via `_ensure_nvm_current`.

Bump the floor by editing `NVM_MIN_VERSION` in both files (comments cross-reference).

## Layer 2 — official mirror pin

`home/.zshrc` exports `NVM_NODEJS_ORG_MIRROR` / `NVM_IOJS_ORG_MIRROR` to the official
HTTPS hosts **before** `nvm.sh` loads, so a stray or planted mirror env var can't
redirect downloads (the CVE-2026-10796 vector). To use a custom mirror (e.g. a
corporate proxy), set `NVM_ALLOW_CUSTOM_MIRROR=1` in `~/.zshrc.private`.

This pin is **interactive-shell-scoped**: it applies to shells that source `.zshrc`.
A non-interactive context that runs `nvm install` without sourcing `.zshrc` (a bare
`bash -c`, a CI step) is not covered by this layer — there, the default official
mirror still applies unless something sets a hostile one, and Layer 5
(`nvm-verify-node`) is the mirror-independent backstop.

## Layer 3 — Node end-of-life guard

- `NODE_MIN_MAJOR` (currently `22`) is defined in both `install.sh` and
  `home/.zsh_onboarding`. Node 20 reached EOL 2026-04; 22 is Active LTS (EOL 2027-04).
- The welcome banner flags the active Node line in red when its major is below the
  floor (`EOL — below Node 22`).
- Onboarding nudges (24h, interactive) via `_ensure_node_current`, offering
  `nvm install --lts && nvm alias default 'lts/*'`.

Bump `NODE_MIN_MAJOR` in both files as LTS lines age out.

## Layer 4 — preflight EOL Node sweep

`install.sh` `_preflight_node_eol_check` (runs alongside the pnpm preflight) detects
Node versions under `~/.nvm/versions/node` whose major is below `NODE_MIN_MAJOR` and
offers to remove them — read-only detection, confirm-gated per directory, never
touches an in-support version. Honors `--skip-preflight` and `--dry-run`.

## Layer 5 — `nvm-verify-node` (independent integrity / GPG verifier)

nvm checks SHA256 by default, but `SHASUMS256.txt` comes from the same mirror it
downloaded Node from, and nvm has **no native GPG verification**. `nvm-verify-node`
(`home/.local/bin/`) closes that gap. It is **opt-in** (nothing runs it automatically;
it downloads a full tarball per version).

For each version it:

1. Fetches `SHASUMS256.txt` (+ `.asc`) directly from `https://nodejs.org/dist/<ver>/`
   — hard-coded official source, ignoring any configured mirror.
2. Best-effort GPG-verifies the signature against Node's release keys.
3. Downloads the official tarball, confirms its sha256 is in the (signed) SHASUMS.
4. Compares the official `bin/node` to the installed `bin/node` — a match proves the
   installed binary is bit-identical to the signed official release.

```bash
nvm-verify-node                 # verify the active Node
nvm-verify-node v22.20.0        # verify a specific installed version
nvm-verify-node --all           # verify every installed version
nvm-verify-node --import-keys    # best-effort import of Node release GPG keys (keyserver)
```

Exit `0` = all verified, `1` = a mismatch/failure, `2` = usage/environment error.

**GPG note:** signature verification is best-effort. Without the Node release keys in
your keyring it prints `skipped` / `could not verify` and still runs the
official-SHASUMS + binary-identity checks (the primary mirror-independent defense).
`--import-keys` fetches the keys from public keyservers, which can be slow or
unreachable; importing them manually from <https://github.com/nodejs/release-keys>
is equivalent.

## Bumping the floors (summary)

| Constant          | Files (keep in sync)                 | When to bump             |
| ----------------- | ------------------------------------ | ------------------------ |
| `NVM_MIN_VERSION` | `install.sh`, `home/.zsh_onboarding` | new nvm security release |
| `NODE_MIN_MAJOR`  | `install.sh`, `home/.zsh_onboarding` | an LTS line reaches EOL  |
