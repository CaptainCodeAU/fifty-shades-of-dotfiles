#!/usr/bin/env bash
# ==============================================================================
#  Dotfiles Installer — fifty-shades-of-dotfiles
# ==============================================================================
#  Usage:
#    ./install.sh              # Full install (interactive)
#    ./install.sh --check      # Check prerequisites + deploy parity (no changes)
#    ./install.sh --stow-only  # Just run stow (skip prereqs)
#    ./install.sh --uninstall  # Remove all symlinks
#    ./install.sh --update     # Pull latest changes and restow
#    ./install.sh --dry-run    # Show what would be done without changing anything
#    ./install.sh --force      # Adopt existing files into repo (stow --adopt)
#    ./install.sh --verbose    # Show detailed diagnostic output
#    ./install.sh --help       # Show help
#
#  Modifiers (--verbose, --dry-run) can be combined with any action:
#    ./install.sh --verbose --check
#    ./install.sh --verbose --dry-run
#
#  Profiles, skip flags and the no-questions mode (docs/INSTALL_PROFILES.md):
#    ./install.sh --profile codebox            # a named bundle of the flags below
#    ./install.sh --no-questions               # every prompt takes its recorded answer
#    ./install.sh --no-sudo                    # a step that needs sudo is named, never run
#    ./install.sh --skip-claude --skip-ssh ... # leave one optional part out
# ==============================================================================

set -euo pipefail

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Resolve the repo root (where this script lives) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# --- Deletions go to the Trash, never to /bin/rm ---
# This script deletes things the user cares about: their EXISTING dotfiles when it resolves
# a stow conflict, old pnpm installs, corepack shims. It runs under bash and never loads
# .zshrc, so the interactive rm() wrapper cannot protect any of it -- every one of those was
# a permanent, unrecoverable delete. Use the repo copy by PATH rather than the command name:
# on a fresh machine this script runs BEFORE stow has put anything in ~/.local/bin.
# safe-rm refuses (exit 1) when no trash tool is present rather than falling back to rm, and
# a real trash is already a checked prerequisite -- see the "real trash" check (trash-guard
# --real-trash on macOS) and check_command trash-put on Linux.
# A script's own mktemp scratch is deliberately NOT routed here; see safe-rm's header.
SAFE_RM="$REPO_DIR/home/.local/bin/safe-rm"

# --- Ensure tool paths are visible to bash ---
# Tools installed via standalone installers (pnpm, bun, uv) land outside
# /usr/bin and may not be on PATH in a bash login shell. Root PNPM_HOME is
# included here so install.sh can find a pre-migration v10-layout pnpm to
# upgrade — the permanent PATH (in .zshrc) only includes bin/.
# Apple Silicon Homebrew can be missing from a bare bash login PATH (brew's
# shellenv runs from .zshrc/.zprofile, which this script does not source), so
# `brew`/`stow`/etc. must be found even when install.sh is launched oddly.
[[ -d "/opt/homebrew/bin" ]]             && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# ~/.local/bin unconditionally: on a fresh box it does not exist when this script
# starts, and uv, herdr, lazygit and glow are installed INTO it during the run. With
# the `-d` guard the other lines use, the re-check after installing them could not
# see them and stopped at "still missing" (the codebox dry run, 2026-10-10).
export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/.local/share/pnpm" ]]       && export PATH="$HOME/.local/share/pnpm:$PATH"
[[ -d "$HOME/.local/share/pnpm/bin" ]]   && export PATH="$HOME/.local/share/pnpm/bin:$PATH"
[[ -d "$HOME/Library/pnpm" ]]            && export PATH="$HOME/Library/pnpm:$PATH"
[[ -d "$HOME/Library/pnpm/bin" ]]        && export PATH="$HOME/Library/pnpm/bin:$PATH"
[[ -d "$HOME/.bun/bin" ]]                && export PATH="$HOME/.bun/bin:$PATH"
[[ -d "$HOME/.cargo/bin" ]]              && export PATH="$HOME/.cargo/bin:$PATH"

# --- Mode flags ---
DRY_RUN=false
# pnpm cleanup steps held until the replacement pnpm runs; filled by
# _preflight_pnpm_check, applied by _pnpm_deferred_cleanup. Declared for `set -u`.
PNPM_DEFERRED_PLAN=(); PNPM_DEFERRED_ACT=()
# Set by _preflight_cc_toolchain_check; read by _offer_brew_sweep, which must not
# offer a source-build sweep to a machine that cannot compile C++. Declared here
# so `set -u` cannot bite when the check is skipped (Linux, or --skip-preflight).
CC_TOOLCHAIN_OK=true
# Filled in by the C++ pre-flight so the closing summary can state the operator's
# actual numbers instead of telling them to go and look them up.
CC_CLANG_MAJOR=""
CC_SDK_VER=""
VERBOSE=false
SKIP_PREFLIGHT=false

# --- Profiles, skip flags, no-questions, no-sudo (Gavin's design, Q24 of the codebox
# build, 2026-10-10; docs/INSTALL_PROFILES.md) ---
# Every OPTIONAL part of this installer has a skip flag; without it the part asks its
# yes/no question as before. A profile is a named bundle of these flags, applied before
# the flags typed on the command line, so a typed flag always wins. The first profile is
# `codebox`: a throwaway Ubuntu box whose user has no sudo, no ~/.claude and no ~/.ssh.
PROFILE=""
# --no-questions: confirm() takes each prompt's RECORDED no-questions answer (its third
# argument; the interactive default when none is recorded) and never reads stdin. A
# typed gate (confirm_typed) is always DECLINED in this mode: nobody typed the word.
NO_QUESTIONS=false
# --no-sudo: run_cmd refuses any command that starts with `sudo`, prints it, and returns
# 0 exactly like --dry-run does for that one command, so a step that needs root is
# named in the output and in the closing summary instead of failing or hanging on a
# password prompt. Nothing here ever escalates by another route.
NO_SUDO=false
NO_SUDO_SKIPPED=()
# Skip flags. Each one leaves out ONE optional part; the part's own checks still gate
# it when the flag is off. The stow skips (claude, ssh, tmux, docker) also keep the
# matching home/ paths out of stow, the conflict check, the link manifest and parity.
SKIP_CLAUDE=false            # home/.claude, Claude hook registration, pj settings and pj checks
SKIP_SSH=false               # home/.ssh
SKIP_SYSTEM_PACKAGES=false   # the package-manager (apt/dnf/pacman/zypper/brew) tool installs
SKIP_TMUX=false              # home/.tmux.conf, home/.zsh_tmux, TPM
SKIP_DOCKER=false            # home/.zsh_docker_functions, lazydocker
SKIP_RUST=false              # rustup
SKIP_YAZI=false              # yazi
SKIP_FONTS=false             # Nerd Font
SKIP_GIT_HOOKS=false         # the pnpm-audit pre-push hook (core.hooksPath)
SKIP_NVM=false               # nvm and the default Node
SKIP_PNPM=false              # pnpm (standalone)
SKIP_BUN=false               # bun
SKIP_UV=false                # uv and Python 3.13
SKIP_HERDR=false             # herdr (install, pin, service, plugin)
SKIP_OMZ=false               # Oh My Zsh, its plugins and Powerlevel10k
SKIP_GIT_IDENTITY=false      # the user.name / user.email prompt

# --- Node.js default version ---
# nvm alone leaves a box with no Node at all (measured: install.sh installed nvm and
# never a Node, so `node` was "command not found" until someone ran `nvm install` by
# hand). After nvm is present, post_install installs this major and makes it the
# default when nvm holds no Node yet. Node 24 is the Active LTS (since 2025-10); keep
# it >= NODE_MIN_MAJOR. An existing Node is never replaced here.
NODE_DEFAULT_VERSION="24"

# Group-level confirm state. When a section is approved/declined as a whole, this
# is set to "yes"/"no" so confirm() auto-answers the prompts inside it; "ask"
# (the default) prompts normally. Always reset to "ask" after a section.
SECTION_DECISION=ask

# --- pnpm version policy ---
# Minimum acceptable pnpm. If pnpm is missing OR below this, install/upgrade
# is offered. Keep in sync with PNPM_MIN_VERSION in home/.zsh_onboarding.
# 11.21.0 (2026-08-19): full changelog review of 11.16.0-11.21.0. NO pnpm CVE
# over 11.11.0 (OSV-clean at both 11.15.1 and 11.21.0). Bump is hardening, not
# a required patch: 11.18.0 locks self-update against project-controlled
# overrides of minimumReleaseAge/trustPolicy/registry; 11.20.0 fixes a
# named-registry lockfile package-substitution bug (namedRegistries not used
# here) plus a path-traversal fix in `pnpm rebuild`. Verified real ~141MB
# macOS-arm64 binary at every version in range (no repeat of the 11.12/11.13
# binary-less incident). SKIP 11.12.0/11.13.0 -- binary-less.
# 12.3.2 (2026-09-19): Gavin took pnpm 12 by hand (12.4.1 via pnpm_update). The
# floor is the lowest SANE v12, not the lowest v12: 12.3.0 breaks global
# node/npm/yarn after self-update (`unexpected argument '--shim'`, fixed 12.3.1)
# and 12.3.2 fixed the npm wrapper so v11 can install v12 through the version
# store. Prerequisites: globalShims:false in home/.config/pnpm/config.yaml (nvm
# owns `node`), and the HTTPS->SSH url rewrites already in git config.
# Ruling D-20260919-06; reasoning in docs/PNPM_SETUP_GUIDE.md section 7.
# 12.8.2 (2026-10-06, Gavin's pick): every security fix that matters here (12.4.2
# bin-shim takeover, 12.6.0 WSL shim fix, 12.7.0 userAgent env leak and storeDir
# build-approval bypass) and none of the 12.6-12.8.0 regressions. Assigned, never
# inherited, so an older value in the environment cannot lower it.
# Ruling D-20261006-A06; reasoning in docs/PNPM_SETUP_GUIDE.md section 7.5.
# 12.10.0 (2026-10-10, Gavin's pick): adds seven security fixes, among them a
# dependency writing files outside pnpm's global virtual store (path traversal)
# and locked config dependencies checked against the registry. No known
# regression (12.10.1 fixes only the experimental `loaded` linker and older
# bugs). Ruling D-20261010-A02; reasoning in docs/PNPM_SETUP_GUIDE.md section 7.8.
PNPM_MIN_VERSION="12.10.0"

# --- nvm version policy ---
# Minimum acceptable nvm. Three CVEs set this floor: CVE-2026-10796
# (RCE via a malicious mirror's version strings; affects <= 0.40.4, fixed 0.40.5),
# CVE-2026-15921 (startup-file overwrite via LTS-alias path traversal;
# affects 0.32.1-0.40.5, fixed 0.40.6) and CVE-2026-94185 (arbitrary file read
# via a malicious .nvmrc's alias path traversal on `nvm use`; affects <= 0.40.7,
# fixed 0.40.8). If nvm is missing OR below this,
# install/upgrade is offered; the installer pins exactly this tag. Keep in sync
# with NVM_MIN_VERSION in home/.zsh_onboarding.
NVM_MIN_VERSION="0.40.8"

# --- Node.js version policy ---
# Lowest Node major still receiving security support. Node 20 reached end-of-life
# 2026-04; 22 (Active LTS, EOL 2027-04) is the floor. Used to flag/offer-removal
# of EOL Node versions. Keep in sync with NODE_MIN_MAJOR in home/.zsh_onboarding.
NODE_MIN_MAJOR="22"

# --- bun version policy ---
# Minimum acceptable bun. The bunfig `minimumReleaseAge` supply-chain cooldown
# (home/.bunfig.toml, 3 days) is only honored by bun >= 1.3.0 (added 2025-10-10
# via oven-sh/bun#22801); older bun silently ignores the key, so the cooldown is
# a no-op until this floor is met. Keep in sync with BUN_MIN_VERSION in
# home/.zsh_onboarding.
BUN_MIN_VERSION="1.3.0"

# --- herdr release-cooldown policy ---
# Days a herdr release must age before this estate adopts it. herdr has no
# native cooldown knob (unlike pnpm minimumReleaseAge / bun minimumReleaseAge /
# uv UV_EXCLUDE_NEWER), AND it ships a self-updater plus two default-on calls to
# herdr.dev -- update.version_check, and update.manifest_check which reloads
# remote agent-detection manifests into the RUNNING server. Both risks stand
# regardless of who runs the bump, so the gate is still enforced externally:
# keep the Homebrew formula PINNED so a routine `brew upgrade` cannot move it,
# and `herdr-cooldown-check` reports (read-only, self-tested) when a release
# has aged past this many days. On macOS, _preflight_herdr_bump_check in this
# script now runs that same three-step upgrade automatically once the report
# says ELIGIBLE -- no separate script to remember, install.sh is the one thing
# you run. The commands below remain valid for a manual/ad-hoc check or bump:
#   herdr-cooldown-check
#   brew unpin herdr; HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade herdr; brew pin herdr
#   then re-grant Full Disk Access to the NEW /opt/homebrew/Cellar/herdr/<v>/bin/herdr
#   (System Settings > Privacy & Security); the grant names the versioned path, so an
#   upgrade drops it silently (W-20261007-A16, _herdr_fda_regrant_note)
# Raised from 3 to 7 (2026-08-20) after checking herdr's actual disclosed-vuln
# history: one real report took ~5.8 days to reach a shipped fix, and a second
# was auto-closed by their triage bot in 8 seconds with no human ever seeing
# it -- 3 days wasn't the right lever regardless, but 7 buys more of the
# window that DOES sometimes work (community/maintainer response) without
# pretending the gate alone solves a triage-process gap. See docs/HERDR.md.
#
# LOWERED from 7 to 5 (2026-09-22, D-20260922-A10, ruled by Gavin at the F9
# gate). The 2026-08-20 reasoning above is NOT overturned; the ruling is that a
# FOLLOWING POINT RELEASE carries more signal than the extra two days of
# waiting. v0.9.0 shipped 2026-09-07 and v0.9.1 followed on 2026-09-16, which
# is the shape this shorter gate is priced for. herdr ONLY: pnpm's
# minimumReleaseAge, bun's, uv's UV_EXCLUDE_NEWER and the SHA-pinned GitHub
# Actions are untouched. The mechanism is unchanged too -- the formula stays
# pinned, herdr-cooldown-check stays read-only and self-tested, and
# _preflight_herdr_bump_check still does the unpin/upgrade/re-pin itself once
# the verdict reads ELIGIBLE. Only the number moves. `decided D-20260922-A10`.
HERDR_COOLDOWN_DAYS="5"

# --- herdr pinned release (Linux/WSL only) ---
# macOS gets herdr from Homebrew, whose formula hashes the SOURCE tarball and
# ships a checksummed bottle. Linux has no such route: homebrew-core publishes
# only an arm64_tahoe bottle, there is no apt/dnf/pacman package, and every
# remaining method (vendor curl|sh, mise via aqua, raw download) fetches the
# same GitHub release asset -- and upstream publishes NO .sha256 and NO .sig
# alongside it, so none of them can verify anything.
#
# The gate is therefore the same one used everywhere else in this estate: pin
# the exact artefact and assert it. These hashes were computed from the real
# release assets (the dated note above HERDR_VERSION says which and how).
# install.sh REFUSES to install on mismatch, so a silently
# re-uploaded asset fails loudly instead of landing.
#
# This is trust-on-first-use, not upstream provenance -- it cannot tell you the
# binary was good originally. What it does guarantee is that every box gets
# BYTE-IDENTICAL to the artefact that was vetted here, which is exactly the
# guarantee `brew pin` provides on macOS.
#
# To bump (deliberate, never automatic -- after the cooldown has elapsed):
#   1. herdr-cooldown-check confirms the release has aged past HERDR_COOLDOWN_DAYS
#   2. curl -fsSL -O https://github.com/herdrdev/herdr/releases/download/<tag>/herdr-linux-x86_64
#      curl -fsSL -O https://github.com/herdrdev/herdr/releases/download/<tag>/herdr-linux-aarch64
#   3. shasum -a 256 herdr-linux-*   (sha256sum on Linux)
#      and compare with GitHub's own per-asset digest, which the release API
#      now carries (GitHub computes it at upload; it is not an upstream
#      signature): curl -fsS https://api.github.com/repos/herdrdev/herdr/releases/tags/<tag>
#      | jq -r '.assets[] | "\(.name) \(.digest)"'. Do not take
#      herdr-linux-pin-check's hash alone: on 2026-09-27 it printed a wrong
#      x86_64 hash once, with no error (W-20260927-A32).
#   4. update HERDR_VERSION + both hashes below in ONE commit
#   5. push, pull on each box, re-run ./install.sh
#
# v0.9.3 (2026-10-07): published 2026-09-29, 7.7 days old, past the 5-day
# cooldown. Both hashes agree across herdr-linux-pin-check, an independent
# Mac download, and GitHub's API digest. Not yet re-downloaded on the WSL box.
HERDR_VERSION="v0.9.3"
HERDR_SHA256_LINUX_X86_64="18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7"
HERDR_SHA256_LINUX_AARCH64="4de7aa3e25678812e92960de64f7c2aaa1bca1f0f80a3c5e559837e231e1f5c0"

# --- Helpers ---
info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}" >&2; }
step()    { echo -e "\n${BOLD}${MAGENTA}━━━ $* ━━━${RESET}"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "  ${DIM}$*${RESET}" || true; }

# Compare two semver-ish versions. Prints -1 (a<b), 0 (==), or 1 (a>b).
_vercmp() {
    local a="$1" b="$2"
    [[ "$a" == "$b" ]] && { echo 0; return; }
    local lower
    lower=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)
    if [[ "$lower" == "$a" ]]; then echo -1; else echo 1; fi
}

# Compare two settings.json files IGNORING the per-machine color lines that
# direnvrc injects into "workbench.colorCustomizations" (titleBar/statusBar/
# panel/sideBar/terminal keys — see home/.config/direnv/direnvrc). Returns 0
# (same) when the ONLY difference is those machine colors, so the macOS settings
# sync can skip a pointless backup+overwrite on a re-run. JSONC-safe: it strips
# matching lines as TEXT, because the files carry // comments that jq can't parse.
_settings_same_ignoring_colors() {
    local re='"(titleBar\.(active|inactive)(Background|Foreground)|panel\.border|sideBar\.border|statusBar\.(background|foreground)|terminal\.(inactiveSelectionBackground|selectionBackground))"[[:space:]]*:'
    cmp -s <(grep -Ev "$re" -- "$1") <(grep -Ev "$re" -- "$2")
}

# PNPM_HOME: where pnpm keeps its globals + store, and (on most platforms) where
# the standalone binary installs. ~/Library/pnpm on macOS, ~/.local/share/pnpm on
# Linux/WSL. Used for globals/residue on every platform — even on Intel macOS,
# where the binary itself comes from Homebrew.
_pnpm_standalone_home() {
    case "$(check_os)" in
        macos) echo "$HOME/Library/pnpm" ;;
        *)     echo "$HOME/.local/share/pnpm" ;;
    esac
}

# Always false since 2026-10-06 (Gavin: "whatever you are doing on the M4, do the
# same for the Intel Mac"; D-20261006-A08). It was true on Intel macOS, where pnpm
# 11's standalone executable was a Node.js SEA binary that segfaulted (upstream
# nodejs/node#62893 / pnpm#11423, both closed fixed in May). pnpm 12 ships a native
# Intel build (@pnpm/exe.darwin-x64, a Mach-O x86_64; 12.9.0 ran under Rosetta), and
# Homebrew pnpm skipped the cooldown, the deny list and the binary check. Kept as a
# function so every caller reads the same answer; with it false, the pre-flight
# plans the Homebrew pnpm's removal and holds it until the standalone one RUNS
# (W-20261005-A75), so an Intel machine is never left without a pnpm.
_pnpm_use_homebrew() {
    return 1
}

# True (0) if the active pnpm resolves to the standalone install (under its
# PNPM_HOME), as opposed to a corepack shim or an npm-global pnpm. Those other
# flavors can't be `pnpm self-update`d into the standalone layout.
_pnpm_is_standalone() {
    local p home
    p=$(command -v pnpm 2>/dev/null) || return 1
    home=$(_pnpm_standalone_home)
    [[ "$p" == "$home"/* ]]
}

# True (0) if pnpm comes from the *supported* provider for this platform: a
# Homebrew install on Intel macOS, otherwise a standalone install. Anything else
# (corepack shim, npm-global, or no pnpm) counts as unsupported → (re)install.
_pnpm_is_supported() {
    if _pnpm_use_homebrew; then
        command -v brew &>/dev/null && brew list pnpm &>/dev/null
    else
        _pnpm_is_standalone
    fi
}

# True (0) if the supported pnpm is missing OR below PNPM_MIN_VERSION.
_pnpm_needs_install_or_upgrade() {
    _pnpm_is_supported || return 0
    local v cmp
    v=$(pnpm -v 2>/dev/null) || return 0
    cmp=$(_vercmp "$v" "$PNPM_MIN_VERSION") || return 0
    [[ "$cmp" == "-1" ]]
}

# The pnpm the dotfiles mean to keep: Homebrew's on Intel macOS, the standalone one
# everywhere else. Prints its path; it may not exist yet.
_pnpm_supported_bin() {
    if _pnpm_use_homebrew; then
        echo "$(brew --prefix 2>/dev/null || echo /usr/local)/bin/pnpm"
    else
        echo "$(_pnpm_standalone_home)/bin/pnpm"
    fi
}

# True (0) only when the pnpm we mean to keep RUNS and is at or above the floor.
# "It exists" is not enough: a binary-less release leaves a 34-byte text file there
# that execs as `This: command not found` (PNPM_SETUP_GUIDE 3.6). Used to hold back
# every cleanup that would take away the pnpm a user has now (W-20261005-A75).
_pnpm_replacement_verified() {
    local bin v cmp
    bin=$(_pnpm_supported_bin)
    [[ -x "$bin" && ! -d "$bin" ]] || return 1
    v=$("$bin" -v 2>/dev/null) || return 1
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
    cmp=$(_vercmp "$v" "$PNPM_MIN_VERSION") || return 1
    [[ "$cmp" != "-1" ]]
}

# Cleanup actions that take away a pnpm (or the globals/launchers an old pnpm owns).
# They run only once the replacement is verified; until then they are kept, not lost.
_pnpm_action_removes_a_pnpm() {
    case "${1%%|*}" in
        corepack_disable|npm_global_rm|brew_rm_pnpm|apt_rm_pnpm|dnf_rm_pnpm|pacman_rm_pnpm|snap_rm_pnpm|rm_v10_globals|rm_root_launchers) return 0 ;;
        *) return 1 ;;
    esac
}

# Installed nvm version (e.g. "0.40.5"), or empty if nvm isn't present. install.sh
# runs in bash where nvm isn't sourced, so source nvm.sh --no-use in a subshell.
_nvm_installed_version() {
    [[ -s "$HOME/.nvm/nvm.sh" ]] || return 1
    ( export NVM_DIR="$HOME/.nvm"; \. "$NVM_DIR/nvm.sh" --no-use >/dev/null 2>&1; nvm --version 2>/dev/null )
}

# True (0) if nvm is installed but below NVM_MIN_VERSION (CVE-2026-10796 floor).
# Missing nvm is handled separately (offered as a fresh install), so this is
# false when nvm is absent.
_nvm_needs_upgrade() {
    local v cmp
    v=$(_nvm_installed_version) || return 1
    [[ -n "$v" ]] || return 1
    cmp=$(_vercmp "$v" "$NVM_MIN_VERSION") || return 1
    [[ "$cmp" == "-1" ]]
}

# --- pnpm conflict helpers (used by the pre-flight check) --------------------
# These make no assumptions about how many Node installs exist or where pnpm
# comes from. bash 3.2-safe: every array expansion is count-guarded.

# Print every Node "bin" directory on this machine, one per line, de-duplicated:
# each installed nvm version (~/.nvm/versions/node/*/bin) plus any node on PATH
# (system / Homebrew / distro). Empty output is fine — callers guard.
_pnpm_node_bindirs() {
    local -a dirs=()
    local d
    local nvm_root="${NVM_DIR:-$HOME/.nvm}/versions/node"
    if [[ -d "$nvm_root" ]]; then
        for d in "$nvm_root"/*/bin; do
            [[ -d "$d" ]] && dirs+=("$d")
        done
    fi
    while IFS= read -r d; do
        [[ -n "$d" ]] && dirs+=("$(dirname "$d")")
    done < <(which -a node 2>/dev/null || true)
    (( ${#dirs[@]} > 0 )) || return 0
    printf '%s\n' "${dirs[@]}" | awk '!seen[$0]++'
}

# True (0) if the file at $1 is a corepack-managed shim: a symlink whose target
# path contains "corepack".
_pnpm_is_corepack_shim() {
    local f="$1" tgt
    [[ -L "$f" ]] || return 1
    tgt=$(readlink "$f" 2>/dev/null) || return 1
    [[ "$tgt" == *corepack* ]]
}

# Apply one planned cleanup action ("type|arg"). Called from inside an `if` in
# the executor, so set -e is suppressed in this body — a failing step won't abort
# the whole install; the executor reports it and moves on.
_pnpm_apply_action() {
    local spec="$1" type arg
    type="${spec%%|*}"
    arg="${spec#*|}"
    case "$type" in
        corepack_disable)
            # Disable corepack in this Node's bin dir. PATH-prepend the Node so
            # corepack's `env node` shebang resolves to it; --install-directory
            # targets the exact dir. Fall back to removing any surviving shims.
            if [[ -x "$arg/corepack" ]]; then
                run_cmd env PATH="$arg:$PATH" "$arg/corepack" disable --install-directory "$arg" || true
            elif command -v corepack &>/dev/null; then
                run_cmd corepack disable --install-directory "$arg" || true
            fi
            local s
            for s in pnpm pnpx yarn; do
                if _pnpm_is_corepack_shim "$arg/$s"; then run_cmd "$SAFE_RM" -f "$arg/$s"; fi
            done
            true
            ;;
        npm_global_rm)
            # The one place install.sh needs npm: removing an npm-installed pnpm.
            # npm-guard refuses npm everywhere else, so say so (D-20261006-A10).
            if [[ -x "$arg/npm" ]]; then
                run_cmd env DOTFILES_ALLOW_NPM=1 PATH="$arg:$PATH" "$arg/npm" rm -g pnpm
            elif command -v npm &>/dev/null; then
                run_cmd env DOTFILES_ALLOW_NPM=1 npm rm -g pnpm
            else
                run_cmd "$SAFE_RM" -rf "$arg/../lib/node_modules/pnpm"
            fi
            ;;
        rm_v10_globals)
            # Record what was installed globally under v10 so the user can
            # reinstall under v11, then remove the v10 globals directory.
            local manifest="$arg/global/5/package.json"
            if [[ -f "$manifest" ]]; then
                local deps=""
                if command -v jq &>/dev/null; then
                    deps=$(jq -r '.dependencies // {} | keys[]' "$manifest" 2>/dev/null || true)
                else
                    deps=$(grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*"[^"]+"' "$manifest" 2>/dev/null \
                        | sed -E 's/^"([^"]+)".*/\1/' | grep -vxE '(name|version|private)' || true)
                fi
                if [[ -n "$deps" ]]; then
                    info "  v10 globals recorded — reinstall under v11 (after this install) with:"
                    printf '%s\n' "$deps" | sed 's/^/      pnpm add -g /'
                fi
            fi
            run_cmd "$SAFE_RM" -rf "$arg/global/5"
            ;;
        rm_root_launchers)
            # Remove v10 root-level launchers at $PNPM_HOME root: the canonical
            # pnpm shims plus any executable text launcher that points into
            # global/5 (e.g. `wt`) — identified by content, not by guessing names.
            local f base
            for f in "$arg"/*; do
                [[ -f "$f" && -x "$f" ]] || continue
                base=$(basename "$f")
                case "$base" in
                    pnpm|pnpx|pn|pnx) run_cmd "$SAFE_RM" -f "$f" ;;
                    *) if grep -Iq 'global/5' "$f" 2>/dev/null; then run_cmd "$SAFE_RM" -f "$f"; fi ;;
                esac
            done
            true
            ;;
        rm_v10_tools)
            # Remove dead pnpm v10 managed binaries from .tools: the old-layout
            # pnpm-exe/ dir (all v10) + any 10.* version inside the v11-layout
            # @pnpm+* dirs (auto-downloaded by projects pinning pnpm@10.x). v11
            # entries are left untouched. Safe: pnpm re-downloads on demand.
            local home="$arg" d e
            [[ -d "$home/.tools/pnpm-exe" ]] && run_cmd "$SAFE_RM" -rf "$home/.tools/pnpm-exe"
            for d in "$home"/.tools/@pnpm+*; do
                [[ -d "$d" ]] || continue
                while IFS= read -r e; do
                    [[ -n "$e" ]] && run_cmd "$SAFE_RM" -rf "$e"
                done < <(find "$d" -mindepth 1 -maxdepth 1 -name '10.*' 2>/dev/null)
            done
            true
            ;;
        rm_path)        run_cmd "$SAFE_RM" -rf "$arg" ;;
        brew_rm_pnpm)   run_cmd brew uninstall pnpm ;;
        apt_rm_pnpm)    run_cmd sudo apt remove -y pnpm ;;
        dnf_rm_pnpm)    run_cmd sudo dnf remove -y pnpm ;;
        pacman_rm_pnpm) run_cmd sudo pacman -R --noconfirm pnpm ;;
        snap_rm_pnpm)   run_cmd snap remove pnpm ;;
        pkill_pnpm)     run_cmd pkill -x pnpm || true ;;
        backup_npmrc)   run_cmd mv "$HOME/.npmrc" "$HOME/.npmrc.pre-stow.$(date +%Y%m%d-%H%M%S).bak" ;;
        backup_yaml)    run_cmd mv "$arg" "${arg}.pre-stow.$(date +%Y%m%d-%H%M%S).bak" ;;
        *)              warn "  Unknown action: $type"; return 1 ;;
    esac
}

# Pre-flight: detect existing pnpm setups that conflict with the dotfiles model
# (a single standalone install at $PNPM_HOME/bin, camelCase YAML config, no
# corepack/distro/brew/npm-global pnpm) and remediate them. Three phases:
# DETECT (read-only; builds a plan) -> PLAN (numbered list) -> EXECUTE (confirm
# each item individually; decline any). --dry-run prints the plan only.
# See docs/PNPM_SETUP_GUIDE.md for the mental model.
_preflight_pnpm_check() {
    if [[ "$SKIP_PREFLIGHT" == true ]]; then
        info "Skipping pre-flight pnpm check (--skip-preflight)"
        return 0
    fi
    step "Pre-flight pnpm conflict check"

    local os pnpm_home
    os=$(check_os)
    pnpm_home=$(_pnpm_standalone_home)

    # PLAN[] = human descriptions; ACT[] = parallel "type|arg" action specs.
    # NOTES[] = informational findings with no automatic fix.
    local -a PLAN=() ACT=() NOTES=()
    local bindir shim

    # --- DETECT (read-only) ---------------------------------------------------

    # Multiple pnpm on PATH (diagnostic; the cleanup below resolves it).
    if command -v pnpm &>/dev/null; then
        local pcount
        pcount=$(which -a pnpm 2>/dev/null | sort -u | grep -c . 2>/dev/null || true)
        if [[ "${pcount:-0}" -gt 1 ]]; then
            NOTES+=("Multiple pnpm on PATH (first wins) — resolved by the cleanup below.")
        fi
    fi

    # Corepack-managed pnpm/pnpx/yarn shims in every Node.
    while IFS= read -r bindir; do
        [[ -n "$bindir" ]] || continue
        local found_shims=()
        for shim in pnpm pnpx yarn; do
            if _pnpm_is_corepack_shim "$bindir/$shim"; then found_shims+=("$shim"); fi
        done
        if (( ${#found_shims[@]} > 0 )); then
            PLAN+=("Disable corepack (${found_shims[*]}) in Node: $(pretty_path "$bindir")")
            ACT+=("corepack_disable|$bindir")
        fi
    done < <(_pnpm_node_bindirs)

    # Dormant npm-global pnpm in every Node.
    while IFS= read -r bindir; do
        [[ -n "$bindir" ]] || continue
        if [[ -d "$bindir/../lib/node_modules/pnpm" ]]; then
            local gv=""
            gv=$(grep -m1 '"version"' "$bindir/../lib/node_modules/pnpm/package.json" 2>/dev/null \
                | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
            PLAN+=("Remove npm-global pnpm ${gv:-?} from Node: $(pretty_path "$bindir")")
            ACT+=("npm_global_rm|$bindir")
        fi
    done < <(_pnpm_node_bindirs)

    # Homebrew pnpm collides with the standalone install — except on Intel macOS,
    # where Homebrew IS the supported provider (standalone is upstream-broken).
    if ! _pnpm_use_homebrew && command -v brew &>/dev/null && brew list pnpm &>/dev/null; then
        PLAN+=("Uninstall Homebrew pnpm (brew uninstall pnpm)")
        ACT+=("brew_rm_pnpm|")
    fi

    # Distro pnpm (Linux/WSL).
    if [[ "$os" == "linux" || "$os" == "wsl" ]]; then
        if command -v dpkg &>/dev/null && dpkg -l 2>/dev/null | grep -qE '^ii[[:space:]]+pnpm[[:space:]]'; then
            PLAN+=("Remove apt pnpm (sudo apt remove pnpm)"); ACT+=("apt_rm_pnpm|")
        fi
        if command -v dnf &>/dev/null && dnf list installed 2>/dev/null | grep -q '^pnpm\.'; then
            PLAN+=("Remove dnf pnpm (sudo dnf remove pnpm)"); ACT+=("dnf_rm_pnpm|")
        fi
        if command -v pacman &>/dev/null && pacman -Qs '^pnpm$' &>/dev/null; then
            PLAN+=("Remove pacman pnpm (sudo pacman -R pnpm)"); ACT+=("pacman_rm_pnpm|")
        fi
        if command -v snap &>/dev/null && snap list pnpm &>/dev/null 2>&1; then
            PLAN+=("Remove snap pnpm (snap remove pnpm)"); ACT+=("snap_rm_pnpm|")
        fi
    fi

    # Running pnpm daemons (may hold store locks).
    if pgrep -x pnpm &>/dev/null; then
        PLAN+=("Stop running pnpm processes (pkill -x pnpm)")
        ACT+=("pkill_pnpm|")
    fi

    # v10 standalone residue under $PNPM_HOME (store/v3 + .tools/pnpm are kept).
    if [[ -d "$pnpm_home/global/5" ]]; then
        PLAN+=("Record + remove v10 globals: $(pretty_path "$pnpm_home/global/5") (you'll get reinstall commands)")
        ACT+=("rm_v10_globals|$pnpm_home")
    fi
    if [[ -d "$pnpm_home/store/v10" ]]; then
        local s10; s10=$(du -sh "$pnpm_home/store/v10" 2>/dev/null | awk '{print $1}' || true)
        PLAN+=("Remove v10 store: $(pretty_path "$pnpm_home/store/v10") (${s10:-?})")
        ACT+=("rm_path|$pnpm_home/store/v10")
    fi
    # Dead pnpm v10 managed binaries in .tools: the old-layout pnpm-exe/ dir
    # (all v10) PLUS any 10.* version inside the v11-layout @pnpm+* dirs
    # (auto-downloaded by projects pinning pnpm@10.x). v11 entries are kept.
    if [[ -d "$pnpm_home/.tools" ]]; then
        local -a v10_tools=()
        [[ -d "$pnpm_home/.tools/pnpm-exe" ]] && v10_tools+=("$pnpm_home/.tools/pnpm-exe")
        local _d _e
        for _d in "$pnpm_home"/.tools/@pnpm+*; do
            [[ -d "$_d" ]] || continue
            while IFS= read -r _e; do
                [[ -n "$_e" ]] && v10_tools+=("$_e")
            done < <(find "$_d" -mindepth 1 -maxdepth 1 -name '10.*' 2>/dev/null)
        done
        if (( ${#v10_tools[@]} > 0 )); then
            local v10sz
            v10sz=$(printf '%s\0' "${v10_tools[@]}" | xargs -0 du -ch 2>/dev/null | tail -1 | awk '{print $1}')
            PLAN+=("Remove ${#v10_tools[@]} dead pnpm v10 managed-binary entries from $(pretty_path "$pnpm_home/.tools") (${v10sz:-?})")
            ACT+=("rm_v10_tools|$pnpm_home")
        fi
    fi
    # Root-level v10 launchers at $PNPM_HOME root: canonical pnpm shims + any
    # executable text launcher that points into global/5 (e.g. `wt`).
    if [[ -d "$pnpm_home" ]]; then
        local rootlaunchers=() f base
        for f in "$pnpm_home"/*; do
            [[ -f "$f" && -x "$f" ]] || continue
            base=$(basename "$f")
            case "$base" in
                pnpm|pnpx|pn|pnx) rootlaunchers+=("$base") ;;
                *) if grep -Iq 'global/5' "$f" 2>/dev/null; then rootlaunchers+=("$base"); fi ;;
            esac
        done
        if (( ${#rootlaunchers[@]} > 0 )); then
            PLAN+=("Remove v10 root-level launchers from $(pretty_path "$pnpm_home"): ${rootlaunchers[*]}")
            ACT+=("rm_root_launchers|$pnpm_home")
        fi
    fi

    # ~/.npmrc with registry/auth (can shadow pnpm's defaults).
    if [[ -f "$HOME/.npmrc" ]] && grep -qE '^(registry=|//|_auth)' "$HOME/.npmrc" 2>/dev/null; then
        PLAN+=("Back up + remove ~/.npmrc (registry/auth overrides pnpm)")
        ACT+=("backup_npmrc|")
    fi

    # Real config.yaml file where a stow symlink belongs (Linux XDG path; both OSes).
    if [[ -f "$HOME/.config/pnpm/config.yaml" && ! -L "$HOME/.config/pnpm/config.yaml" ]]; then
        PLAN+=("Back up real ~/.config/pnpm/config.yaml so stow can link the repo version")
        ACT+=("backup_yaml|$HOME/.config/pnpm/config.yaml")
    fi
    if [[ "$os" == "macos" && -f "$HOME/Library/Preferences/pnpm/config.yaml" && ! -L "$HOME/Library/Preferences/pnpm/config.yaml" ]]; then
        PLAN+=("Back up real ~/Library/Preferences/pnpm/config.yaml (install bridges it to a symlink)")
        ACT+=("backup_yaml|$HOME/Library/Preferences/pnpm/config.yaml")
    fi

    # --- informational NOTES (no automatic fix) ---
    local active_cfg=""
    if [[ "$os" == "macos" && -e "$HOME/Library/Preferences/pnpm/config.yaml" ]]; then
        active_cfg="$HOME/Library/Preferences/pnpm/config.yaml"
    elif [[ -e "$HOME/.config/pnpm/config.yaml" ]]; then
        active_cfg="$HOME/.config/pnpm/config.yaml"
    fi
    if [[ -n "$active_cfg" ]] && grep -qE '^[a-z]+(-[a-z]+)+:' "$active_cfg" 2>/dev/null; then
        NOTES+=("kebab-case keys in $(pretty_path "$active_cfg") are ignored by pnpm 11 (YAML needs camelCase). Edit manually.")
    fi
    local rcfile
    for rcfile in "$HOME/.zshrc.local" "$HOME/.zshrc.private" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [[ -f "$rcfile" ]] && grep -qE '^export PNPM_HOME|^export PATH.*PNPM_HOME' "$rcfile" 2>/dev/null; then
            NOTES+=("PNPM_HOME export in $(pretty_path "$rcfile") may double-up PATH (stowed .zshrc sets it). Edit manually.")
        fi
    done
    if [[ "$os" == "wsl" ]]; then
        if [[ -n "${PNPM_HOME:-}" && "$PNPM_HOME" == /mnt/[a-z]/* ]]; then
            NOTES+=("PNPM_HOME points to a Windows mount ($PNPM_HOME) — NTFS breaks pnpm symlinks. Set it to \$HOME/.local/share/pnpm.")
        fi
        if command -v pnpm &>/dev/null; then
            local pp; pp=$(command -v pnpm 2>/dev/null || true)
            if [[ "$pp" == /mnt/[a-z]/* ]]; then
                NOTES+=("Active pnpm is a Windows install ($pp) — reorder PATH to put the WSL pnpm first.")
            fi
        fi
    fi

    # --- PLAN (present findings) ---------------------------------------------
    if (( ${#NOTES[@]} > 0 )); then
        echo
        warn "Findings (informational — no automatic change):"
        local n
        for n in "${NOTES[@]}"; do echo -e "    ${DIM}- ${n}${RESET}"; done
    fi

    if (( ${#PLAN[@]} == 0 )); then
        echo
        success "Pre-flight pnpm check: nothing to change."
        return 0
    fi

    echo
    warn "Planned pnpm changes (${#PLAN[@]}) — review, then approve (or decline) the whole group below:"
    local i
    for i in "${!PLAN[@]}"; do
        printf "    ${BOLD}%2d.${RESET} %s\n" "$((i + 1))" "${PLAN[$i]}"
    done
    echo

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to apply (one yes applies them all)."
        return 0
    fi

    if ! confirm "Apply all ${#PLAN[@]} planned change(s)?" "y"; then
        warn "Skipped pnpm cleanup. Re-run install.sh when ready (or --skip-preflight to bypass)."
        return 0
    fi

    # --- EXECUTE (group-approved: apply all) ---------------------------------
    # A step that takes a pnpm away waits for the replacement to be verified. If it is
    # not verified yet, the approved step is held in PNPM_DEFERRED_* and applied by
    # _pnpm_deferred_cleanup after the install step (W-20261005-A75).
    local applied=0 failed=0 held=0 have_replacement=false
    _pnpm_replacement_verified && have_replacement=true
    PNPM_DEFERRED_PLAN=(); PNPM_DEFERRED_ACT=()
    for i in "${!ACT[@]}"; do
        echo
        info "${PLAN[$i]}"
        if [[ "$have_replacement" != true ]] && _pnpm_action_removes_a_pnpm "${ACT[$i]}"; then
            PNPM_DEFERRED_PLAN+=("${PLAN[$i]}"); PNPM_DEFERRED_ACT+=("${ACT[$i]}")
            held=$((held + 1))
            info "  Held until the replacement pnpm is installed and runs (after the install step)."
            continue
        fi
        if _pnpm_apply_action "${ACT[$i]}"; then
            applied=$((applied + 1))
        else
            failed=$((failed + 1))
            warn "  Action reported a problem; continuing with the rest."
        fi
    done

    # Clear bash's command-location cache so a just-removed shim isn't still
    # reported by `command -v pnpm` in the standalone-install step that follows.
    hash -r 2>/dev/null || true

    echo
    success "pnpm cleanup complete: $applied applied, $failed failed, $held held until the replacement runs."
    return 0
}

# Apply the steps _preflight_pnpm_check held back, now that the install step has run.
# Applied only if the replacement pnpm runs and meets the floor; otherwise every held
# step is named and left undone, so the pnpm the user has is never taken away for one
# that does not work.
_pnpm_deferred_cleanup() {
    (( ${#PNPM_DEFERRED_ACT[@]} > 0 )) || return 0
    hash -r 2>/dev/null || true
    step "Held pnpm cleanup"
    if ! _pnpm_replacement_verified; then
        warn "The replacement pnpm ($(pretty_path "$(_pnpm_supported_bin)")) is missing, does not run, or is below ${PNPM_MIN_VERSION}."
        warn "Kept, not applied (${#PNPM_DEFERRED_ACT[@]}):"
        local p
        for p in "${PNPM_DEFERRED_PLAN[@]}"; do echo -e "    ${DIM}- ${p}${RESET}"; done
        info "Fix the pnpm install, then re-run ./install.sh."
        return 0
    fi
    local i applied=0 failed=0
    for i in "${!PNPM_DEFERRED_ACT[@]}"; do
        echo
        info "${PNPM_DEFERRED_PLAN[$i]}"
        if _pnpm_apply_action "${PNPM_DEFERRED_ACT[$i]}"; then
            applied=$((applied + 1))
        else
            failed=$((failed + 1))
            warn "  Action reported a problem; continuing with the rest."
        fi
    done
    hash -r 2>/dev/null || true
    success "Held pnpm cleanup: $applied applied, $failed failed."
    return 0
}

# Pre-flight: offer to remove end-of-life Node majors installed under nvm. EOL
# Node lines stop receiving security patches; NODE_MIN_MAJOR is the lowest still
# in support. Detection is read-only; each removal is confirm-gated individually
# and a version >= NODE_MIN_MAJOR is never touched. Honors --skip-preflight/--dry-run.
_preflight_node_eol_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    local node_root="${NVM_DIR:-$HOME/.nvm}/versions/node"
    [[ -d "$node_root" ]] || return 0

    local -a eol=()
    local d base major
    for d in "$node_root"/v*; do
        [[ -d "$d" ]] || continue
        base=$(basename "$d")          # e.g. v20.18.1
        major=${base#v}; major=${major%%.*}
        [[ "$major" =~ ^[0-9]+$ ]] || continue
        (( major < NODE_MIN_MAJOR )) && eol+=("$d")
    done
    (( ${#eol[@]} > 0 )) || return 0

    step "Pre-flight Node EOL check"
    warn "End-of-life Node version(s) found (below Node ${NODE_MIN_MAJOR} — no security patches):"
    local e
    for e in "${eol[@]}"; do echo "    $(pretty_path "$e")"; done

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to remove EOL Node versions."
        return 0
    fi
    for e in "${eol[@]}"; do
        if confirm "Remove EOL Node $(basename "$e")?"; then
            run_cmd "$SAFE_RM" -rf "$e"
        fi
    done
    return 0
}

# Pre-flight: warn when a repo tool with a `#!/usr/bin/env python3` shebang would break
# on the oldest python3 the bare name can resolve to (Apple's 3.9.6 on macOS, which
# cannot be removed and which a login non-interactive shell already picks TODAY --
# measured 2026-09-07). Such a script dies WHILE BEING PARSED, above its own error
# handling: no log line, no alert. A sibling project lost its capture hook for ten days
# to exactly that. census.py is one of these files, and it is the instrument this repo
# uses to decide what is true, so a silent death there is expensive.
# Read-only; never modifies anything. Honors --skip-preflight.
_preflight_env_python_floor_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    local tool="$REPO_DIR/home/.local/bin/env-python-floor-check"
    [[ -x "$tool" ]] || return 0

    # `|| rc=$?`, NOT `; rc=$?`. This script runs under `set -euo pipefail` with NO trap
    # (verified: 0 traps in this file), and a plain assignment from a failing command
    # substitution exits the shell AT THE ASSIGNMENT -- `rc=$?` and the whole case below
    # are never reached. Reproduced: a Linux box with no /usr/bin/python3 makes the tool
    # exit 2, which would have killed install.sh mid-run, silently, before every step
    # after this one. An "advisory, never blocking" check that aborts the installer is
    # worse than no check, and the comment above it would have said the opposite.
    local out rc=0
    out="$("$tool" 2>&1)" || rc=$?
    case "$rc" in
        0) return 0 ;;
        2)  warn "env-python3 floor check could not run -- nothing was verified (not a pass)."
            printf '%s\n' "$out" | sed 's/^/    /' >&2 ;;
        *)  warn "A repo tool will NOT run on the oldest python3 the bare name resolves to."
            printf '%s\n' "$out" | sed 's/^/    /' >&2
            # `warn` only, deliberately. NOTES is `local -a` inside _preflight_pnpm_check;
            # this function is called from main(), where that array does not exist -- so a
            # NOTES+=() here would create a global nobody ever prints and the warning would
            # vanish. The sibling checks at this call site use warn/info for the same reason.
            ;;
    esac
    return 0
}

_preflight_pnpm_floor_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # Present-but-below-floor UPGRADE only. A MISSING pnpm is deliberately left to
    # the prerequisite installer so it still passes check -> install -> re-check.
    # Corepack/npm-global pnpm is handled by _preflight_pnpm_check.
    command -v pnpm &>/dev/null || return 0
    _pnpm_is_supported || return 0
    _pnpm_needs_install_or_upgrade || return 0   # supported + present => below floor

    local cur; cur=$(pnpm -v 2>/dev/null || echo "?")
    step "Pre-flight pnpm floor check"
    warn "pnpm ${cur} is below ${PNPM_MIN_VERSION} (security floor)."
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to upgrade pnpm."
        return 0
    fi
    # A security floor is not a suggestion -- upgrade unconditionally, no y/N.
    # An install must never silently continue with a below-floor pnpm; that's
    # exactly the known-vulnerable-range risk the floor exists to catch.
    # --skip-preflight remains the one deliberate, explicit bypass.
    info "This is a security floor, not optional -- upgrading now."
    if _pnpm_use_homebrew; then
        run_cmd brew upgrade pnpm
    elif _pnpm_is_standalone; then
        run_cmd pnpm self-update
    fi
    hash -r 2>/dev/null || true
    if _pnpm_needs_install_or_upgrade; then
        error "pnpm is still below ${PNPM_MIN_VERSION} after the upgrade attempt."
        error "Refusing to continue with a below-floor pnpm. Fix manually and re-run."
        exit 1
    fi
    return 0
}

# --- Homebrew health: "cannot answer" is NOT "no" -----------------------------
# Measured 2026-09-18. An Xcode 27 update left its licence unaccepted, so EVERY
# brew command exited 1 with its message on stderr. The three herdr pre-flights
# below each began with:
#
#     brew list --versions herdr &>/dev/null || return 0
#
# and `brew list --versions <formula>` exits 1 with EMPTY stdout in BOTH of
# these cases: the formula genuinely is not installed, and Homebrew is broken.
# So that line could not tell them apart, `&>/dev/null` threw away the only
# evidence that could, and all three guards switched themselves off in silence:
# no pin check, no cooldown auto-bump, not one line of output saying so.
#
# `brew list --formula` is used instead because it is SELF-CONTROLLING: a
# non-empty roster is itself proof that brew can answer, so "herdr is not in
# the roster" is a conclusion the probe actually supports.
#
# Returns: 0 brew is healthy (roster in $_BREW_ROSTER)
#          1 brew is absent -- genuinely nothing to check
#          2 brew EXISTS but FAILED -- unknown, and must be reported LOUDLY
_BREW_ROSTER=""
_BREW_HEALTH_DETAIL=""
_BREW_UNUSABLE_REPORTED=""
_brew_health() {
    _BREW_ROSTER=""; _BREW_HEALTH_DETAIL=""
    command -v brew &>/dev/null || return 1
    local out="" rc=0
    out=$(brew list --formula 2>&1) || rc=$?
    if [[ $rc -eq 0 && -n "$out" ]]; then
        _BREW_ROSTER="$out"
        return 0
    fi
    _BREW_HEALTH_DETAIL="${out%%$'\n'*}"
    [[ -n "$_BREW_HEALTH_DETAIL" ]] || \
        _BREW_HEALTH_DETAIL="\`brew list --formula\` exited ${rc} with no output"
    return 2
}

# Is $1 in the roster? Only meaningful after _brew_health returned 0.
_brew_has() {
    local f
    for f in $_BREW_ROSTER; do
        if [[ "$f" == "$1" ]]; then return 0; fi
    done
    return 1
}

# Say it once in full, then briefly for each further guard that had to skip.
_warn_brew_unusable() {
    if [[ -n "$_BREW_UNUSABLE_REPORTED" ]]; then
        warn "${1} also SKIPPED — Homebrew is still unusable."
        return 0
    fi
    _BREW_UNUSABLE_REPORTED=1
    warn "Homebrew is installed but CANNOT ANSWER — ${1} SKIPPED."
    warn "  ${_BREW_HEALTH_DETAIL}"
    info "This is NOT the same as 'herdr is not managed by Homebrew'. While it lasts,"
    info "the herdr pin guard and the ${HERDR_COOLDOWN_DAYS}-day cooldown auto-bump both do nothing —"
    info "a release that has genuinely cleared the cooldown will never be adopted."
    info "Check with ${CYAN}brew list --formula${RESET}, then re-run ${CYAN}./install.sh${RESET}."
}

_preflight_herdr_pin_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # herdr is only gated if it is actually installed AND managed by Homebrew --
    # a direct install has no pin concept, and `herdr update` would bypass the
    # cooldown anyway (that case is reported by `herdr-cooldown-check`, not here).
    command -v herdr &>/dev/null || return 0
    local _bh=0; _brew_health || _bh=$?
    if [[ $_bh -eq 1 ]]; then return 0; fi
    if [[ $_bh -eq 2 ]]; then
        step "Pre-flight herdr cooldown guard"
        _warn_brew_unusable "herdr pin check"
        return 0
    fi
    _brew_has herdr || return 0
    # Already pinned => the gate is intact, stay silent.
    if brew list --pinned 2>/dev/null | grep -qx "herdr"; then
        return 0
    fi

    step "Pre-flight herdr cooldown guard"
    warn "herdr is NOT pinned — a routine 'brew upgrade' would adopt a same-day release."
    info "The ${HERDR_COOLDOWN_DAYS}-day gate is enforced by pinning; ${CYAN}./install.sh${RESET} bumps it"
    info "automatically once a release clears cooldown (see _preflight_herdr_bump_check)."
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to pin herdr."
        return 0
    fi
    confirm "Run 'brew pin herdr'?" y && run_cmd brew pin herdr
    return 0
}

# herdr is server/client: replacing the binary on disk never touches an already
# running server process (Unix keeps the old inode mapped) -- on macOS the
# server has to be stopped (`herdr server stop`) and the next `herdr` starts
# the new build; on Linux the systemd unit is restarted. Nothing does either
# for you. That's
# deliberate: nobody should auto-restart a server other live sessions are
# attached to. This just makes the resulting skew VISIBLE instead of silent,
# using herdr's own restart_needed field (it already tracks protocol
# compatibility between the running server and the installed binary) rather
# than guessing from file paths. Never restarts anything itself.
# Echoes "yes:<running-version>" (restart recommended), "no" (in sync), or
# nothing (server not running / herdr or jq missing / status query failed).
_herdr_server_restart_status() {
    command -v herdr &>/dev/null || return 0
    command -v jq &>/dev/null || return 0
    local status_json=""
    status_json=$(herdr status server --json 2>/dev/null) || true
    [[ -n "$status_json" ]] || return 0
    [[ "$(jq -r '.running // false' <<<"$status_json" 2>/dev/null)" == "true" ]] || return 0
    if [[ "$(jq -r '.restart_needed // false' <<<"$status_json" 2>/dev/null)" == "true" ]]; then
        echo "yes:$(jq -r '.version // "unknown"' <<<"$status_json" 2>/dev/null)"
    else
        echo "no"
    fi
}

# --- Offering to restart a herdr server left behind by an upgrade ------------
#
# An upgrade swaps the binary but the running server keeps the old one, and from
# 0.9.x a newer client refuses to talk to an older server at all
# (protocol_mismatch), so `herdr plugin link` and every other command fail until
# it restarts. Measured on mlbox 2026-09-27: 0.8.2 -> 0.9.1 left the server on
# 0.8.2, `enable --now` (a no-op on an active unit) did not restart it, and the
# plugin link failed with herdr's raw JSON error.
#
# Restarting ends every pane process, so the rule above still holds: NEVER
# silently. Ruled by Gavin 2026-09-27: show what is running inside herdr, then
# restart only on a TYPED "restart". Refused outright when this installer is
# itself running in a herdr pane (HERDR_ENV=1): the restart would kill it
# mid-run. Not interactive, or dry-run: print the command, never act.
#
# --stop-only is the macOS form. Homebrew removed herdr's service definition
# on 2026-09-24 (homebrew-core fe0006641fba), so there is no launchd job to
# restart and herdr has no `server start`: the server is stopped, and the next
# `herdr` starts the new build and restores the saved workspaces (measured
# 2026-10-07: 0.9.1 stopped, 0.9.3 came up with all 13 workspaces).
#
# Usage: _herdr_offer_restart [--stop-only] <restart command...>
_herdr_server_pid() {
    # systemd's MainPID on Linux; otherwise whoever holds herdr's socket. On macOS
    # the 0.9.x server detaches (ppid 1), so launchd does not know its PID, and a
    # `pgrep -f 'herdr server$'` found nothing on the Mac while `lsof -t` on the
    # socket named the server and only the server (measured 2026-09-27).
    local pid=""
    if command -v systemctl &>/dev/null; then
        pid=$(systemctl --user show -p MainPID --value herdr.service 2>/dev/null) || pid=""
        [[ "$pid" == 0 ]] && pid=""
    fi
    if [[ -z "$pid" ]] && command -v lsof &>/dev/null; then
        local p
        for p in $(lsof -t "$HOME/.config/herdr/herdr.sock" 2>/dev/null || true); do
            # Attached clients may hold the socket too; only the server's argv ends in "server".
            if [[ "$(ps -o args= -p "$p" 2>/dev/null)" =~ herdr[[:space:]]+server[[:space:]]*$ ]]; then
                pid=$p; break
            fi
        done
    fi
    printf '%s' "$pid"
}
_herdr_pane_processes() {
    # "pid elapsed command" for everything under the server, minus the tab bar's
    # own status commands (they run every few seconds and are not anyone's work).
    local root queue=() all=() p kids k
    root=$(_herdr_server_pid)
    [[ -n "$root" ]] || return 0
    queue=("$root")
    while ((${#queue[@]})); do
        p=${queue[0]}; queue=("${queue[@]:1}")
        kids=$(pgrep -P "$p" 2>/dev/null) || kids=""
        for k in $kids; do all+=("$k"); queue+=("$k"); done
    done
    ((${#all[@]})) || return 0
    ps -o pid=,etime=,command= -p "$(IFS=,; echo "${all[*]}")" 2>/dev/null \
        | grep -v -E 'gpu-status|mac-status|nvidia-smi|iostat|ioreg|sysctl -n' \
        | cut -c1-110 || true
}
_herdr_offer_restart() {
    local stop_only=""
    if [[ "${1:-}" == --stop-only ]]; then stop_only=1; shift; fi
    local st have cmd_str="$*" procs ans i
    st=$(_herdr_server_restart_status)
    [[ "$st" == yes:* ]] || return 0
    have=$(herdr --version 2>/dev/null | awk '{print $2}') || have=""
    warn "The running herdr server is still ${st#yes:}; the installed herdr is ${have:-newer}. herdr commands (plugin link among them) fail until it restarts."
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would list what runs inside herdr and offer to restart it: ${CYAN}${cmd_str}${RESET}"
        return 0
    fi
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
        warn "This installer is running INSIDE a herdr pane, so restarting herdr would kill it mid-run. Not asking."
        info "From a plain terminal, when nothing in herdr needs to survive: ${CYAN}${cmd_str}${RESET}"
        return 0
    fi
    procs=$(_herdr_pane_processes)
    if [[ -n "$procs" ]]; then
        info "Running inside herdr now; a restart ends ALL of these:"
        printf '%s\n' "$procs" | sed 's/^/      /'
    else
        info "Nothing runs inside herdr apart from its own tab-bar status commands."
    fi
    if [[ ! -t 0 || "$NO_QUESTIONS" == true ]]; then
        info "Not asking (no terminal, or --no-questions). Restart it yourself: ${CYAN}${cmd_str}${RESET}"
        return 0
    fi
    read -rp "$(echo -e "${YELLOW}Type 'restart' to restart herdr now; anything else skips: ${RESET}")" ans || ans=""
    if [[ "$ans" != restart ]]; then
        info "Skipped. Restart it later: ${CYAN}${cmd_str}${RESET}"
        return 0
    fi
    if ! run_cmd "$@"; then
        warn "Restart failed: ${CYAN}${cmd_str}${RESET}"
        return 0
    fi
    if [[ -n "$stop_only" ]]; then
        # Only a positive "running": false counts as stopped. An empty or failed
        # status call is not that answer, so it is reported as unconfirmed.
        local running=""
        for i in 1 2 3 4 5 6 7 8 9 10; do
            running=$(herdr status server --json 2>/dev/null | jq -r '.running' 2>/dev/null) || running=""
            if [[ "$running" == false ]]; then
                success "herdr server stopped. Open ${CYAN}herdr${RESET} to start ${have} with your workspaces restored."
                return 0
            fi
            sleep 1
        done
        warn "herdr server stop ran but a stopped server was not confirmed (running=${running:-no answer}). Check: ${CYAN}herdr status server${RESET}"
        return 0
    fi
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if [[ "$(_herdr_server_restart_status)" == no ]]; then
            success "herdr server restarted and now matches the installed herdr ${have}."
            return 0
        fi
        sleep 1
    done
    warn "herdr was restarted but does not report a matching server yet. Check: ${CYAN}herdr status server${RESET}"
    return 0
}

# A herdr upgrade silently drops herdr's Full Disk Access (W-20261007-A16). macOS
# stores the grant against the VERSIONED Cellar path the opt symlink resolved to
# (plus the binary's code hash), so the new keg is not covered, and every
# herdr-hosted session gets EPERM on network volumes while Terminal and Finder
# still work. The grant is a System Settings click no script can make, so this
# says it with the exact path, and runs Network_Plan's read-only checker when that
# repo is on this box. Measured 2026-10-07 on 0.9.3: no herdr restart was needed.
_herdr_fda_regrant_note() {
    [[ "$(check_os)" == "macos" ]] || return 0
    local bin=""
    bin=$(readlink -f "$(brew --prefix herdr 2>/dev/null)/bin/herdr" 2>/dev/null) || bin=""
    [[ -n "$bin" ]] || bin="$(brew --prefix 2>/dev/null)/Cellar/herdr/<version>/bin/herdr"
    warn "herdr's Full Disk Access does not follow an upgrade: herdr-hosted sessions cannot read network volumes until it is re-granted."
    info "System Settings > Privacy & Security > Full Disk Access > +, add: ${CYAN}${bin}${RESET}"
    info "Then remove the old herdr entries. No herdr restart is needed."
    local checker="$HOME/CODE/CaptainCodeAU/Network_Plan/tools/check-herdr-fda.py"
    if [[ -f "$checker" ]] && command -v uv &>/dev/null; then
        info "Checking the grant (${checker} --check):"
        uv run "$checker" --check || true
    fi
    return 0
}

_preflight_herdr_bump_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # macOS/Homebrew path only -- Linux/WSL bumps ship via _preflight_herdr_release_check.
    # Mirrors _preflight_pnpm_floor_check: once the cooldown has genuinely elapsed, upgrade
    # unconditionally, no y/N -- "lazy option", install.sh is the only thing you run.
    # Reuses herdr-cooldown-check's own (self-tested) version/age math via --json instead of
    # re-deriving it here in bash: one place decides ELIGIBLE, and its self-test gates this
    # too (a broken detector never triggers a bump, it just skips).
    command -v herdr &>/dev/null || return 0
    local _bh=0; _brew_health || _bh=$?
    if [[ $_bh -eq 1 ]]; then return 0; fi
    if [[ $_bh -eq 2 ]]; then
        step "Pre-flight herdr cooldown bump"
        _warn_brew_unusable "herdr cooldown auto-bump"
        return 0
    fi
    _brew_has herdr || return 0
    command -v herdr-cooldown-check &>/dev/null || return 0
    command -v jq &>/dev/null || return 0

    local report=""
    report=$(herdr-cooldown-check --json --cooldown-days "$HERDR_COOLDOWN_DAYS" 2>/dev/null) || true
    [[ -n "$report" ]] || return 0

    local self_test cooldown_state
    self_test=$(jq -r '.self_test // ""' <<<"$report" 2>/dev/null) || return 0
    [[ "$self_test" == "pass" ]] || return 0
    cooldown_state=$(jq -r '.subjects[]? | select(.subject=="cooldown") | .state' <<<"$report" 2>/dev/null) || return 0
    [[ "$cooldown_state" == "ACTION" ]] || return 0

    local have latest
    have=$(jq -r '.installed // "unknown"' <<<"$report" 2>/dev/null)
    latest=$(jq -r '.latest // "the newest release"' <<<"$report" 2>/dev/null)

    step "Pre-flight herdr cooldown bump"
    info "herdr ${have} has cleared the ${HERDR_COOLDOWN_DAYS}-day cooldown — ${latest} is ELIGIBLE. Upgrading."
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to upgrade herdr."
        return 0
    fi
    # unpin/upgrade/pin as three separate checks (not a bare &&-chain): an upgrade failure
    # must still re-pin whatever is currently installed, or a transient failure here would
    # leave herdr permanently unguarded instead of merely behind.
    # HOMEBREW_NO_INSTALL_CLEANUP=1 IS THE RETURN PATH (W-20260922-A22, ruled by
    # Gavin at the F9b gate: guard it AND say it is not permanent).
    #
    # Without it, Homebrew cleans up around an upgrade and that cleanup removes
    # BOTH the outgoing keg under /opt/homebrew/Cellar/herdr/<old> AND the cached
    # bottle under $(brew --cache)/downloads. Those two ARE the way back: there is
    # no versioned herdr@X.Y.Z formula, homebrew-core is not cloned on this box
    # (API mode) so `brew extract` would mean a several-hundred-MB clone, and the
    # cached bottle is the only artefact that reconstitutes the old version
    # offline. So the routine that exists to take a one-way step had no guard on
    # the step being one-way. F9's upgrade survived only because it was run BY
    # HAND with this variable in front of it.
    #
    # Read from Homebrew's own env_config.rb on 2026-09-22, with a control:
    #   HOMEBREW_NO_INSTALL_CLEANUP          if set, upgrade never auto-cleans
    #   HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS  default 30: every 30 days an upgrade
    #                                        cleans ALL formulae, not just this one
    #   HOMEBREW_CLEANUP_MAX_AGE_DAYS        default 120: cached downloads older
    #                                        than that are removed regardless
    #
    # THE GUARD IS NOT A PROMISE OF PERMANENCE. It stops THIS upgrade eating the
    # bottle. The 120-day cache expiry still applies, and so does any `brew
    # cleanup` a human runs, so a rollback that depends on the cache has a shelf
    # life rather than being permanent. To keep a version past that, copy the
    # bottle out of the cache somewhere of your own before the clock runs down.
    #
    # `run_cmd env VAR=1 cmd` rather than a `VAR=1 run_cmd` prefix: run_cmd execs
    # "$@", which would take the assignment as the command name, and this form
    # also prints the variable in --dry-run instead of hiding it.
    if run_cmd brew unpin herdr; then
        if ! run_cmd env HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade herdr; then
            warn "brew upgrade herdr failed — re-pinning the current version; will retry next run."
        fi
        run_cmd brew pin herdr
        hash -r 2>/dev/null || true
        local now=""
        if command -v herdr &>/dev/null; then
            now=$(herdr --version 2>/dev/null | awk '{print $2}')
            success "herdr now ${now} (pinned)"
        fi
        [[ -n "$now" && "$now" != "$have" ]] && _herdr_fda_regrant_note
        # Never automatic; a typed "restart" at most (see _herdr_offer_restart).
        _herdr_offer_restart --stop-only herdr server stop
    else
        warn "brew unpin herdr failed — leaving the current pin in place."
    fi
    return 0
}

# Homebrew removed herdr's service definition on 2026-09-24 (homebrew-core
# fe0006641fba: `herdr: remove service definition`), so `brew services` no
# longer manages herdr and the server is started by herdr itself on attach.
# A Mac that ran `brew services start herdr` BEFORE that date can still carry
# the old LaunchAgent: launchd keeps running it with keep_alive, so
# `herdr server stop` is undone within milliseconds (docs/HERDR.md, "A
# leftover LaunchAgent"). This only reports it. Removing it ends every pane,
# so the commands are printed, never run.
_preflight_herdr_service_health_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v herdr &>/dev/null || return 0
    local plist="$HOME/Library/LaunchAgents/homebrew.mxcl.herdr.plist"
    [[ -e "$plist" ]] || return 0

    step "Pre-flight herdr leftover LaunchAgent"
    warn "Found ${plist} from before Homebrew dropped herdr's service (2026-09-24)."
    info "launchd restarts herdr on every exit while it is loaded, so ${CYAN}herdr server stop${RESET} cannot stop it."
    info "When nothing in herdr needs to survive, remove it yourself:"
    info "  ${CYAN}launchctl bootout gui/\$(id -u)/homebrew.mxcl.herdr${RESET}"
    info "  ${CYAN}rm ${plist}${RESET}   (goes to the Trash)"
    return 0
}

# Linux/WSL probes shared by _post_stow_herdr_systemd_service and the
# prerequisites summary, so both print the same answer for the same fact.
# _herdr_unit_state: systemctl's own word (active / inactive / failed / ...),
# or "unavailable" when the user manager cannot even be reached.
_herdr_unit_state() {
    local st
    st=$(systemctl --user is-active herdr.service 2>/dev/null) || true
    echo "${st:-unavailable}"
}
_herdr_linger() {
    local l
    l=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null) || true
    echo "${l:-?}"
}

# Linux/WSL counterpart of the launchd management above. The unit file is
# stowed from home/.config/systemd/user/herdr.service; this enables it, and
# turns on linger so the server outlives the SSH session that ran install.sh.
#
# Why this exists: crash-restart and survival across logout -- on the Linux
# box every herdr server had been hand-started from an SSH shell and died with
# it. The clean environment is a side benefit that fixed the visible symptom
# (the inherited once-only banner flags from home/.zshrc made every pane skip
# the welcome banner). Measured 2026-09-06.
#
# Must run AFTER stow_home: it keys off the stowed symlink, and a unit that is
# not on disk cannot be enabled. Never touches a server that is already
# running -- an unmanaged server holds the socket, a second one exits 1, and
# Restart= would then loop (see docs/HERDR.md, "respawn loop"). That case is
# reported and left for the user, exactly like the macOS "stop any running
# server FIRST" hint.
_post_stow_herdr_systemd_service() {
    local os
    os=$(check_os)
    [[ "$os" == "linux" || "$os" == "wsl" ]] || return 0
    command -v herdr &>/dev/null || return 0
    command -v systemctl &>/dev/null || return 0

    local unit="$HOME/.config/systemd/user/herdr.service"
    [[ -L "$unit" ]] || return 0

    # `is-system-running` for the USER manager: "running" or "degraded" both
    # mean it is up (degraded = some unrelated unit failed). Anything else --
    # including the "Failed to connect to bus" WSL gives when /etc/wsl.conf
    # lacks [boot] systemd=true -- means there is nothing to enable into.
    local mgr_state
    mgr_state=$(systemctl --user is-system-running 2>/dev/null) || true
    case "$mgr_state" in
        running|degraded) ;;
        *)
            warn "systemd user manager not available (state: ${mgr_state:-unknown}) — herdr.service not enabled."
            info "On WSL: set ${CYAN}[boot] systemd=true${RESET} in /etc/wsl.conf, then ${CYAN}wsl --shutdown${RESET} from Windows."
            return 0 ;;
    esac

    step "herdr systemd user service"

    # Refuse to enable over an unmanaged running server. A hand-started server
    # owns the socket; the unit's first start would exit 1 and Restart= would
    # keep retrying until the start limit. _herdr_server_restart_status echoes
    # nothing when no server answers, so any output means one is running.
    local unit_state
    unit_state=$(_herdr_unit_state)
    if [[ "$unit_state" != "active" && -n "$(_herdr_server_restart_status)" ]]; then
        warn "A herdr server is already running outside systemd — NOT enabling the unit over it (would respawn-loop on the socket)."
        info "When no session needs it: ${CYAN}herdr server stop && systemctl --user enable --now herdr.service${RESET}"
        return 0
    fi

    # enable --now is idempotent: already enabled + active is a silent no-op.
    run_cmd systemctl --user daemon-reload || true
    if run_cmd systemctl --user enable --now herdr.service; then
        success "herdr.service enabled and running (clean environment; restarts on crash)."
    else
        warn "systemctl --user enable --now herdr.service failed — see ${CYAN}journalctl --user -u herdr.service${RESET}"
        return 0
    fi

    # Linger: without it the user manager -- and this service -- stops when the
    # last session for the user ends, which is every SSH logout on a headless
    # box. `loginctl enable-linger` for one's OWN user goes through polkit and
    # normally needs no sudo; if it does, say so rather than fail the install.
    if [[ "$(_herdr_linger)" == "yes" ]]; then
        success "linger already on for $USER (server survives logout)."
    elif run_cmd loginctl enable-linger "$USER" 2>/dev/null; then
        success "linger enabled for $USER (server survives logout)."
    else
        warn "Could not enable linger — server will stop at your last logout. Run: ${CYAN}sudo loginctl enable-linger $USER${RESET}"
    fi

    # `enable --now` never restarts an ACTIVE unit, so a server started before
    # this run's herdr upgrade is still the old build. Offer, never force.
    _herdr_offer_restart systemctl --user restart herdr.service
    return 0
}

# Everything herdr needs AFTER stow that stow itself cannot do. Three jobs,
# all idempotent, none fatal -- a herdr problem must never fail the install.
#
# 1. PLUGIN REGISTRATION. home/.config/herdr/plugins/window-title-fix is stowed,
#    but herdr only knows a plugin exists once `herdr plugin link` has recorded
#    it in ~/.config/herdr/plugins.json -- machine-local state this repo does
#    NOT track (it holds absolute paths, and tracking it would put a real
#    username in a committed file). So on a fresh box the plugin FILES arrive
#    and the window title silently stays broken. This closes that gap.
#    `link`, never `install`: link points at a local directory and skips
#    [[build]] entirely, so no third-party code runs (docs/HERDR_PLUGINS.md).
#
# 2. THE AGENT SKILL, SHARED. Codex discovers ~/.agents/skills as a skill root
#    by convention -- no config entry, nothing to grep for. Measured 2026-09-17:
#    its session log listed `r0 = ~/.agents/skills` and loaded herdr/SKILL.md
#    from it, while Claude read the stowed copy, and the two had already drifted
#    apart by two behaviours. One symlink keeps both agents on the file in git.
#
# 3. CONFIG VALIDATION. 0.8.2 made `herdr config check` report unknown built-in
#    theme names instead of silently accepting them, which makes it worth running
#    at install time: a bad config.toml becomes a loud line here rather than a
#    quiet oddity at runtime. Reported, never repaired -- config.toml is a
#    tracked file and an installer that edits it is an installer that can lose
#    your keybindings.
_post_stow_herdr_plugins_and_skill() {
    command -v herdr &>/dev/null || return 0

    local plugin_dir="$HOME/.config/herdr/plugins/window-title-fix"
    local skill_src="$REPO_DIR/home/.claude/skills/herdr/SKILL.md"
    local agents_skill="$HOME/.agents/skills/herdr/SKILL.md"
    local did_step=false

    # --- 1. plugin ---
    # Only when stow actually placed it; a missing manifest means link would
    # fail, and a failure here should never look like a herdr problem.
    if [[ -e "$plugin_dir/herdr-plugin.toml" ]]; then
        # `plugin list` is PLAIN TEXT, not JSON (docs/HERDR_PLUGINS.md) -- grep it.
        if herdr plugin list 2>/dev/null | grep -q "dotfiles.window-title-fix"; then
            verbose "herdr plugin dotfiles.window-title-fix already registered"
        elif [[ "$(_herdr_server_restart_status)" == yes:* ]]; then
            # A server older than the binary refuses every command (protocol_mismatch),
            # so linking now would only print herdr's raw JSON error. Say why instead.
            step "herdr plugin registration"
            did_step=true
            warn "Skipped: the running herdr server is older than the installed herdr, so it would refuse the link."
            info "After restarting the server: ${CYAN}herdr plugin link $plugin_dir --enabled${RESET} (or re-run ./install.sh)"
        else
            step "herdr plugin registration"
            did_step=true
            if run_cmd herdr plugin link "$plugin_dir" --enabled; then
                success "window-title-fix linked and enabled"
            else
                warn "herdr plugin link failed — is the herdr server running? Retry: ${CYAN}herdr plugin link $plugin_dir --enabled${RESET}"
            fi
        fi
    fi

    # --- 2. shared skill ---
    if [[ -f "$skill_src" ]]; then
        if [[ -L "$agents_skill" && "$(readlink "$agents_skill")" == "$skill_src" ]]; then
            verbose "Codex skill root already points at the repo skill"
        else
            [[ "$did_step" == true ]] || { step "herdr agent skill (shared with Codex)"; did_step=true; }
            run_cmd mkdir -p "$(dirname "$agents_skill")"
            # A REAL file there is someone's copy (or a `skills` CLI reinstall).
            # Back it up rather than overwrite: it may hold edits this repo has
            # never seen, and losing those is the whole failure we are fixing.
            if [[ -f "$agents_skill" && ! -L "$agents_skill" ]]; then
                run_cmd mv "$agents_skill" "${agents_skill}.pre-stow.$(date +%Y%m%d-%H%M%S).bak"
                warn "Backed up a real ~/.agents herdr skill — diff it against the repo copy before discarding."
            fi
            run_cmd ln -sfn "$skill_src" "$agents_skill"
            success "Codex and Claude now read the same herdr skill"
        fi
    fi

    # --- 3. config check ---
    if [[ -e "$HOME/.config/herdr/config.toml" ]]; then
        local check_out
        if check_out=$(herdr config check 2>&1); then
            verbose "herdr config check clean"
        else
            [[ "$did_step" == true ]] || step "herdr config check"
            warn "herdr config check reported a problem:"
            echo "$check_out" | sed 's/^/    /'
            info "Fix it in ${CYAN}home/.config/herdr/config.toml${RESET} and re-run — nothing here edits that file."
        fi
    fi
    return 0
}

_preflight_herdr_release_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # Linux/WSL only -- macOS herdr is Homebrew-managed, see _preflight_herdr_pin_check.
    # install_herdr_release() is only reached from install_linux_prerequisites(), which
    # main() calls solely when check_prerequisites() reports a MISSING required tool --
    # a present-but-wrong-version herdr never counts as missing, so a box that already
    # has herdr installed never picks up a pin bump. Same gap _preflight_pnpm_floor_check
    # closes for pnpm; this closes it for herdr on Linux/WSL. Confirmed live 2026-08-19:
    # re-running ./install.sh on an already-provisioned WSL box left herdr untouched at
    # the old version despite the "re-run ./install.sh" hint in check_prerequisites.
    local os; os="$(check_os)"
    [[ "$os" == "linux" || "$os" == "wsl" ]] || return 0
    [[ "$SKIP_HERDR" == true ]] && return 0
    command -v herdr &>/dev/null || return 0

    local have want
    have=$(herdr --version 2>/dev/null | awk '{print $2}')
    want="${HERDR_VERSION#v}"
    [[ "$have" == "$want" ]] && return 0

    step "Pre-flight herdr release check"
    info "herdr ${have:-unknown} installed; pinned release is ${HERDR_VERSION}"
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to update herdr."
        return 0
    fi
    install_herdr_release
    return 0
}

pretty_path() {
    echo "${1/#$HOME/~}"
}

# confirm PROMPT [DEFAULT] [NO_QUESTIONS_ANSWER]
#   DEFAULT              y|n: what bare Enter means at the prompt (n when omitted).
#   NO_QUESTIONS_ANSWER  y|n: what --no-questions answers (DEFAULT when omitted).
# The third argument is where a prompt's unattended answer is RECORDED, next to the
# question, so it can be read and reviewed in one place. The rule used when recording
# them: an install the dotfiles depend on answers yes; anything that removes, replaces
# or reaches outside this repo's remit keeps the safe no.
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local unattended="${3:-$default}"
    # Group-level auto-answer: a section approved/declined as a whole answers its
    # inner prompts here (echoed, so the user still sees what's covered).
    case "${SECTION_DECISION:-ask}" in
        yes) echo -e "  ${DIM}↳ ${prompt} → yes${RESET}"; return 0 ;;
        no)  echo -e "  ${DIM}↳ ${prompt} → skipped${RESET}"; return 1 ;;
    esac
    if [[ "$DRY_RUN" == true ]]; then
        # A dry run always declines (it must not wander into code that is not
        # dry-run safe), but a real run with no terminal takes the DEFAULT -- say
        # so, or the dry run silently previews a different run (red team, 2026-10-05).
        local would="answer it at the prompt"
        if [[ "$NO_QUESTIONS" == true ]]; then
            [[ "$unattended" == "y" ]] && would="go ahead (no-questions answer: yes)" || would="skip (no-questions answer: no)"
        elif [[ ! -t 0 ]]; then
            [[ "$default" == "y" ]] && would="go ahead (default yes, no terminal)" || would="skip (default no, no terminal)"
        fi
        echo -e "  ${DIM}[dry-run] Would ask: $prompt -- a real run would $would${RESET}"
        return 1
    fi
    if [[ "$NO_QUESTIONS" == true ]]; then
        # Echoed with the answer, so a log of an unattended run still shows every
        # decision that was taken on the operator's behalf.
        if [[ "$unattended" == "y" ]]; then
            echo -e "  ${DIM}[no-questions] ${prompt} → yes${RESET}"; return 0
        fi
        echo -e "  ${DIM}[no-questions] ${prompt} → no${RESET}"; return 1
    fi
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${YELLOW}$prompt [Y/n]: ${RESET}")" yn
        yn="${yn:-y}"
    else
        read -rp "$(echo -e "${YELLOW}$prompt [y/N]: ${RESET}")" yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy]$ ]]
}

# A confirm for changes a re-run cannot undo (the toolchain-takeover gate).
# Deliberately does NOT consult SECTION_DECISION -- a group "yes" answered
# elsewhere in this run must never be able to answer this one. No bare-Enter
# default; the word must be typed. Non-interactive stdin is a REFUSAL, never
# a silent yes. The caller is responsible for handling DRY_RUN (this helper
# doesn't, unlike confirm() -- a takeover gate declining under --dry-run and
# an ordinary confirm declining under --dry-run mean different things: this
# one must never be mistaken for "answered no" by code that then writes an
# opt-out marker).
confirm_typed() {
    local word="$1" prompt="$2" ans
    if [[ "$NO_QUESTIONS" == true ]]; then
        # Nobody typed the word. A no-questions run can never accept a typed gate.
        warn "--no-questions -- '${prompt}' treated as DECLINED (a typed gate is never answered unattended)."
        return 1
    fi
    if [[ ! -t 0 ]]; then
        warn "Not interactive -- '${prompt}' treated as DECLINED."
        return 1
    fi
    echo -e "  ${DIM}(type ${BOLD}${word}${RESET}${DIM} to accept; anything else, including Enter, declines)${RESET}"
    read -rp "$(echo -e "${YELLOW}${prompt} [type ${word}]: ${RESET}")" ans || return 1
    [[ "$ans" == "$word" ]]
}

run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would run: $*${RESET}"
        return 0
    fi
    # --no-sudo: the one place every `run_cmd sudo ...` in this file passes through.
    # Treated exactly like --dry-run for that command (printed, return 0) rather than
    # as a failure: this script runs under `set -e`, and a non-zero return from a bare
    # `run_cmd sudo apt ...` would abort the whole install instead of skipping a step.
    # The command is recorded so the closing summary can list what root still owes.
    if [[ "$NO_SUDO" == true && "${1:-}" == sudo ]]; then
        echo -e "  ${DIM}[no-sudo] NOT run (needs root): $*${RESET}"
        NO_SUDO_SKIPPED+=("$*")
        return 0
    fi
    verbose "Running: $*"
    "$@"
}

# The home/ paths a skip flag keeps out of stow, one basename per line. Stow's
# --ignore takes a Perl regex matched against the BASENAME (measured with stow 2.4.1,
# 2026-10-10: `--ignore='^\.claude$'` dropped every LINK under .claude and never
# descended into it; the slash-anchored `^/\.claude$` ignored nothing). The same
# names drive _conflict_check_ignored, so the conflict check, the link manifest and
# the parity check all agree with what stow was told.
_stow_skip_names() {
    [[ "$SKIP_CLAUDE" == true ]] && echo ".claude"
    [[ "$SKIP_SSH" == true ]]    && echo ".ssh"
    [[ "$SKIP_TMUX" == true ]]   && { echo ".tmux.conf"; echo ".zsh_tmux"; }
    [[ "$SKIP_DOCKER" == true ]] && echo ".zsh_docker_functions"
    return 0
}

# `--ignore=...` arguments for stow, one per skipped name (empty when nothing is skipped).
_stow_ignore_args() {
    local n
    while IFS= read -r n; do
        [[ -n "$n" ]] && printf -- '--ignore=^%s$\n' "$(printf '%s' "$n" | sed 's/\./\\./g')"
    done < <(_stow_skip_names)
    return 0
}

# True when a home/-relative path is under a skipped top-level name.
_stow_skipped_rel() {
    local rel="$1" n
    while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        [[ "$rel" == "$n" || "$rel" == "$n"/* ]] && return 0
    done < <(_stow_skip_names)
    return 1
}

# ==============================================================================
# OS Detection
# ==============================================================================

check_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if [[ "$(uname -r)" =~ [Ww][Ss][Ll] || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} $name ($(command -v "$cmd"))"
        return 0
    else
        echo -e "  ${RED}✗${RESET} $name — not found"
        return 1
    fi
}

check_command_optional() {
    local cmd="$1"
    local name="${2:-$cmd}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} $name ($(command -v "$cmd"))"
        return 0
    else
        echo -e "  ${YELLOW}~${RESET} $name — not installed (optional)"
        return 1
    fi
}

# --- iTerm2 dynamic profiles: deploy, or report on, one mapping ------------
#
# These are NOT stow-managed: they live under settings/, not home/, because they
# deploy into ~/Library and stow only maps home/ -> ~/. README documented the
# symlinking as a MANUAL step, so a fresh box got none of them (found 2026-08-01,
# the third file in two days added to the repo with its deploy left to memory).
#
# ONE function, TWO modes, deliberately. `deploy-parity-check` deliberately holds
# no hardcoded paths and no OS branching -- its whole value is that home/X -> ~/X
# is derivable. This mapping is NOT derivable, it is macOS-only, and it is
# conditional on iTerm2 being installed. Teaching the generic checker all three
# would give it the exception table its simplicity depends on not having. So the
# code that OWNS the mapping reports on it instead.
#
#   apply  - create missing symlinks (stow_platform)
#   check  - report only, create nothing; returns 1 if any are missing (--check)
#
# Symlinks, not copies: iTerm2 watches the directory and reloads on change, so a
# link means editing the repo file updates the live profile with no reinstall.
# A REAL file at a target is left alone in BOTH modes -- it may be a profile made
# in the GUI, and replacing it would lose the owner's work.
_iterm_profiles_sync() {
    local mode="${1:-check}"
    local src="$REPO_DIR/settings/iterm2/DynamicProfiles"
    local dst="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

    [[ "$(check_os)" == "macos" ]] || { [[ "$mode" == "check" ]] && echo -e "  ${DIM}-${RESET} iTerm2 profiles — not macOS, N/A"; return 0; }
    [[ -d "$src" ]] || return 0
    if [[ ! -d "$HOME/Library/Application Support/iTerm2" ]]; then
        [[ "$mode" == "check" ]] && echo -e "  ${DIM}-${RESET} iTerm2 profiles — iTerm2 not installed, N/A"
        [[ "$mode" == "apply" ]] && info "iTerm2 not installed. Skipping dynamic profiles."
        return 0
    fi

    local linked=0 already=0 blocked=0 missing=0
    local f name target
    [[ "$mode" == "apply" ]] && run_cmd mkdir -p "$dst"
    for f in "$src"/*.json; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f")
        target="$dst/$name"
        if [[ -L "$target" ]]; then
            already=$((already+1))
        elif [[ -e "$target" ]]; then
            blocked=$((blocked+1))
            [[ "$mode" == "apply" ]] && warn "iTerm2 profile ${name} exists as a REAL file - left as-is (move it aside to adopt the repo version)"
            [[ "$mode" == "check" ]] && echo -e "  ${YELLOW}~${RESET} iTerm2 profile ${CYAN}${name}${RESET} — real file where a link belongs"
        elif [[ "$mode" == "apply" ]]; then
            run_cmd ln -s "$f" "$target"
            linked=$((linked+1))
        else
            missing=$((missing+1))
            echo -e "  ${RED}✗${RESET} iTerm2 profile not deployed — ${CYAN}${name}${RESET}"
        fi
    done

    if [[ "$mode" == "apply" ]]; then
        success "iTerm2 dynamic profiles: ${linked} linked, ${already} already linked, ${blocked} skipped"
        return 0
    fi
    if (( missing == 0 && blocked == 0 )); then
        echo -e "  ${GREEN}✓${RESET} iTerm2 profiles — all ${already} linked"
        return 0
    fi
    (( missing > 0 )) && info "Fix: ${CYAN}./install.sh${RESET} (the platform step relinks them)"
    return 1
}

# --- Deploy parity: delegated to the canonical checker -----------------------
# The logic lives in home/.local/bin/deploy-parity-check, which self-tests its
# own detectors on every run. It is called from the REPO path, not ~/.local/bin
# -- on a fresh box this function runs before stow has deployed anything, which
# is precisely the situation it exists to report on.
# --- rm reach: plain shells must reach the Trash-routed rm (W-20260929-A126) ---
# Interactive shells put ~/.local/bin first, so `rm` is the Trash shim. Plain zsh
# (`ssh host 'cmd'`, `zsh -c`) does not, and gets the REAL, permanent rm -- measured
# 2026-09-29 on the Mac and on mlbox, the day a foreign `safe-rm` package nearly took
# a permanent delete on mlbox (W-20260929-A125). Called from the REPO path (like
# _check_deploy_parity) AFTER stow, so ~/.local/bin/rm exists for the probe. Adds the
# marked ~/.zshenv block with consent, then runs the full check so the result is SHOWN
# (the probe resolves rm in a plain zsh), never assumed. Foreign look-alikes are named
# with their remove command; nothing is uninstalled here. cron, launchd and bash
# scripts stay NOT covered, and the checker says so on every run.
_check_rm_reach() {
    local checker="$REPO_DIR/home/.local/bin/rm-reach-check" state
    if [[ ! -x "$checker" ]]; then
        echo -e "  ${YELLOW}~${RESET} rm reach — checker not found at $checker, skipped"
        return 0
    fi
    step "rm reach (plain shells and the Trash)"
    state=$("$checker" --zshenv-state 2>/dev/null)
    case "$state" in
        absent)
            info "Plain zsh (ssh 'cmd', zsh -c) runs the REAL rm: ~/.local/bin is not on its PATH."
            info "A marked 3-line block in ~/.zshenv fixes that; your existing lines stay."
            if confirm "Add the ~/.local/bin block to ~/.zshenv?" "y"; then
                "$checker" --fix-zshenv >/dev/null || warn "rm-reach-check --fix-zshenv failed; run it by hand to see why"
            fi
            ;;
        broken)
            warn "~/.zshenv has a half fifty-shades block (markers not one each); fix it by hand, then re-run."
            ;;
    esac
    [[ "$DRY_RUN" == true ]] && { echo -e "  ${DIM}[dry-run] Would run: $checker${RESET}"; return 0; }
    "$checker" || warn "rm reach has findings above; each line names its fix."
    # zsh remembers where it found a command, so a terminal opened before this stow keeps
    # running Apple's trash with no guard until `rehash` or a new terminal (measured
    # 2026-09-29, W-20260929-A184). rm-reach-check cannot see another shell's memory.
    info "Terminals that were already open keep the OLD rm and trash (no guard) until you open a new one or type: rehash"
    return 0
}

_check_deploy_parity() {
    local checker="$REPO_DIR/home/.local/bin/deploy-parity-check"
    if [[ ! -x "$checker" ]]; then
        echo -e "  ${YELLOW}~${RESET} deploy parity — checker not found at $checker, skipped"
        return 0
    fi
    if ! command -v uv &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} deploy parity — uv not installed yet, skipped"
        return 0
    fi
    # The checker is told the same skips stow was told (DOTFILES_STOW_SKIP, one
    # basename per entry, colon-separated), so a skipped tree is not a parity gap.
    DOTFILES_REPO="$REPO_DIR" DOTFILES_STOW_SKIP="$(_stow_skip_names | paste -sd ':' -)" "$checker"
}

# --- Toolchain takeover: survey, disclose, gate (must precede stow_home) ----
# The two big changes this repo makes -- Python taken over by uv, pnpm
# enforced with npm/npx/yarn hard-blocked -- are not conveniences: they break
# commands a foreign machine's EXISTING projects may depend on
# (home/.zshrc's python3()/npm() etc.). Called from the REPO path, same
# reasoning as _check_deploy_parity above -- stow hasn't run yet on a fresh
# box. See Plans/sorted-brewing-brooks.md and
# docs/TOOLCHAIN_TAKEOVER_CONSENT.md. Idempotent by design: a clean box, or
# a box already consented at an unchanged fingerprint, adds zero friction.
_toolchain_consent_file() { echo "$HOME/.local/state/dotfiles/toolchain-consent.json"; }

_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

_gate_toolchain_takeover() {
    local stock="$REPO_DIR/home/.local/bin/toolchain-stocktake"
    command -v uv &>/dev/null || return 0
    [[ -x "$stock" ]] || return 0

    local consent_file; consent_file=$(_toolchain_consent_file)
    local have_consent=false
    [[ -s "$consent_file" ]] && command -v jq &>/dev/null && have_consent=true

    if [[ "$SKIP_PREFLIGHT" == true ]]; then
        if [[ "$have_consent" == true ]]; then
            return 0   # already decided once; --skip-preflight just skips re-surveying
        fi
        warn "toolchain takeover: --skip-preflight given, but no prior consent record."
        warn "  Surveying anyway -- consent cannot be skipped, only the routine re-check can."
    fi

    local py_rc=0 node_rc=0 py_out node_out
    py_out=$("$stock" --verdict python --quiet 2>&1) || py_rc=$?
    node_out=$("$stock" --verdict node --quiet 2>&1) || node_rc=$?
    # exit 2 (could not determine) escalates to 1 -- an unrun survey is not a
    # clean survey, same posture as toolchain-cve-check's false-all-clear guard.
    [[ "$py_rc" == 2 ]] && py_rc=1
    [[ "$node_rc" == 2 ]] && node_rc=1
    local py_foreign=false node_foreign=false
    [[ "$py_rc" == 1 ]] && py_foreign=true
    [[ "$node_rc" == 1 ]] && node_foreign=true

    if [[ "$py_foreign" == false && "$node_foreign" == false ]]; then
        return 0
    fi

    local fingerprint; fingerprint=$(printf '%s\n%s' "$py_out" "$node_out" | _sha256)
    if [[ "$have_consent" == true ]]; then
        local prior_fp; prior_fp=$(jq -r '.stocktake_fingerprint // empty' "$consent_file" 2>/dev/null)
        if [[ -n "$prior_fp" && "$prior_fp" == "$fingerprint" ]]; then
            info "toolchain takeover: unchanged since last consent, not re-asking."
            return 0
        fi
    fi

    step "Toolchain takeover: what's already on this machine"
    "$stock" --verdict any || true

    local impact="$REPO_DIR/home/.local/bin/project-impact-scan"
    local impact_report=""
    if [[ -x "$impact" && "$DRY_RUN" != true ]]; then
        if "$impact" --yes --quiet >/dev/null 2>&1; then :; fi
        impact_report="$HOME/.local/state/dotfiles/project-impact-report.md"
        [[ -f "$impact_report" ]] && info "Existing-project impact report: $(pretty_path "$impact_report")"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would ask for consent here. No changes made, nothing written."
        return 0
    fi

    local py_decision="unchanged" node_decision="unchanged"
    local early_file="$HOME/.zshrc.private.early"

    if [[ "$py_foreign" == true ]]; then
        echo
        warn "Python: this machine has its own setup (see above). install.sh normally"
        warn "  takes Python over completely via uv -- bare python/python3 stop working."
        if confirm_typed "UV" "Let uv take over Python on this machine?"; then
            py_decision="accepted"
            [[ -f "$early_file" ]] && sed -i.bak '/^export DOTFILES_ALLOW_SYSTEM_PYTHON=/d' "$early_file" 2>/dev/null && rm -f "$early_file.bak"
        else
            py_decision="declined"
            echo "export DOTFILES_ALLOW_SYSTEM_PYTHON=1  # written by install.sh's takeover gate; see docs/TOOLCHAIN_TAKEOVER_CONSENT.md" >> "$early_file"
            info "Declined -- your existing Python setup is left alone. python/python3 stay real."
        fi
    fi

    if [[ "$node_foreign" == true ]]; then
        echo
        warn "Node: this machine has its own npm setup (see above). install.sh normally"
        warn "  hard-blocks npm/npx/yarn -- they print a message and do nothing."
        if confirm_typed "PNPM" "Let pnpm replace npm on this machine?"; then
            node_decision="accepted"
            [[ -f "$early_file" ]] && sed -i.bak '/^export DOTFILES_ALLOW_NPM=/d' "$early_file" 2>/dev/null && rm -f "$early_file.bak"
        else
            node_decision="declined"
            echo "export DOTFILES_ALLOW_NPM=1  # written by install.sh's takeover gate; see docs/TOOLCHAIN_TAKEOVER_CONSENT.md" >> "$early_file"
            info "Declined -- npm/npx/yarn keep working. pnpm is still installed alongside them."
        fi
    fi

    if command -v jq &>/dev/null; then
        mkdir -p "$(dirname "$consent_file")"
        jq -n \
            --arg decided_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg host "$(hostname 2>/dev/null || echo unknown)" \
            --arg py "$py_decision" --arg node "$node_decision" \
            --arg fp "$fingerprint" --arg report "$impact_report" \
            '{schema: 1, decided_at: $decided_at, host: $host,
              python_uv_takeover: $py, node_pnpm_enforcement: $node,
              stocktake_fingerprint: $fp, impact_report: $report}' \
            > "$consent_file" 2>/dev/null || warn "Could not write consent record to $consent_file"
    fi
    return 0
}

check_prerequisites() {
    step "Checking Prerequisites"

    local os
    os=$(check_os)
    info "Detected OS: $os"
    echo

    local missing=0

    echo -e "${BOLD}Essential:${RESET}"
    check_command git      "git"      || missing=$((missing+1))
    check_command zsh      "zsh"      || missing=$((missing+1))
    check_command stow     "GNU Stow" || missing=$((missing+1))
    check_command jq       "jq"       || missing=$((missing+1))
    echo

    echo -e "${BOLD}Shell Framework:${RESET}"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        echo -e "  ${GREEN}✓${RESET} Oh My Zsh ($HOME/.oh-my-zsh)"
    else
        echo -e "  ${RED}✗${RESET} Oh My Zsh — not installed"
        missing=$((missing+1))
    fi

    local omz_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    for plugin in zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do
        if [[ -d "$omz_custom/plugins/$plugin" ]]; then
            echo -e "  ${GREEN}✓${RESET} $plugin"
        else
            echo -e "  ${YELLOW}~${RESET} $plugin — not installed (optional but recommended)"
        fi
    done

    if [[ -d "$omz_custom/themes/powerlevel10k" ]]; then
        echo -e "  ${GREEN}✓${RESET} Powerlevel10k theme"
    else
        echo -e "  ${YELLOW}~${RESET} Powerlevel10k — not installed (optional)"
    fi
    echo

    echo -e "${BOLD}Core Tools:${RESET}"
    if [[ "$SKIP_UV" == true ]]; then check_command_optional uv "uv (--skip-uv)" || true
    else check_command uv "uv" || missing=$((missing+1)); fi
    check_command direnv   "direnv"   || true
    check_command fzf      "fzf"      || true
    check_command eza      "eza"      || true
    check_command zoxide   "zoxide"   || true
    check_command tmux     "tmux"     || true
    check_command rg       "ripgrep"  || true
    check_command aria2c   "aria2c"   || true
    check_command ffmpeg   "ffmpeg"   || true
    if ! check_command fd "fd"; then
        check_command fdfind "fd (as fdfind)" || missing=$((missing+1))
    fi
    check_command gh       "GitHub CLI (gh)" || missing=$((missing+1))
    check_command nvim     "neovim"   || true
    check_command glow     "glow"     || true
    check_command lazygit  "lazygit"  || missing=$((missing+1))
    if [[ "$SKIP_DOCKER" == true ]]; then check_command_optional lazydocker "lazydocker (--skip-docker)" || true
    else check_command lazydocker "lazydocker" || missing=$((missing+1)); fi
    if [[ "$(check_os)" == "macos" ]]; then
        # The question safe-rm asks, answered by the repo copy (this runs before stow). Not
        # `command -v trash`: with the shim stowed that finds the shim, so it passed with no
        # real trash at all (W-20260929-A170). macOS 15 and later ship /usr/bin/trash.
        local _rt
        if _rt=$("$REPO_DIR/home/.local/bin/trash-guard" --real-trash 2>/dev/null); then
            echo -e "  ${GREEN}✓${RESET} real trash ($_rt)"
        else
            echo -e "  ${RED}✗${RESET} real trash — none (macOS 15 and later ship /usr/bin/trash; rm refuses every delete without it)"
            missing=$((missing+1))
        fi
    else
        check_command trash-put "trash-cli (Linux)" || missing=$((missing+1))
    fi
    # herdr is REQUIRED on every platform. macOS gets it from Homebrew (formula
    # hashes the source tarball, checksummed bottle); Linux/WSL gets the pinned
    # release binary verified against HERDR_SHA256_* by install_herdr_release.
    # Both routes refuse an unverified artefact, so neither box is held to a
    # standard the other escapes.
    if [[ "$SKIP_HERDR" == true ]]; then check_command_optional herdr "herdr (--skip-herdr)" || true
    else check_command herdr "herdr" || missing=$((missing+1)); fi
    # Where herdr exists, its guards ARE the policy and must be observable:
    # the pin enforces the release cooldown, config.toml keeps the two
    # phone-home paths closed, and on Linux the systemd unit is what makes the
    # session server survive a crash. Report all three rather than assuming a past run
    # set them -- a lapsed pin looks identical to a healthy one until checked.
    if command -v herdr &>/dev/null; then
        if [[ "$(check_os)" == "macos" ]]; then
            if [[ -e "${HOMEBREW_PREFIX:-/opt/homebrew}/var/homebrew/pinned/herdr" ]]; then
                echo -e "      ${GREEN}✓${RESET} pinned — ${HERDR_COOLDOWN_DAYS}-day release cooldown enforced"
            else
                echo -e "      ${YELLOW}~${RESET} not pinned — run ${CYAN}brew pin herdr${RESET} (cooldown NOT enforced)"
            fi
        else
            # On Linux the pin IS the version constant: install.sh will not
            # deploy anything whose sha256 differs from the recorded hash.
            local _herdr_have
            _herdr_have=$(herdr --version 2>/dev/null | awk '{print $2}')
            if [[ "$_herdr_have" == "${HERDR_VERSION#v}" ]]; then
                echo -e "      ${GREEN}✓${RESET} pinned to ${HERDR_VERSION} — sha256-verified at install"
            else
                echo -e "      ${YELLOW}~${RESET} version ${_herdr_have:-unknown} != pinned ${HERDR_VERSION} — re-run ${CYAN}./install.sh${RESET}"
            fi
        fi
        if [[ -L "$HOME/.config/herdr/config.toml" ]]; then
            echo -e "      ${GREEN}✓${RESET} config.toml stow-linked from the repo"
        else
            echo -e "      ${YELLOW}~${RESET} config.toml not stow-linked — re-run stow (phone-home may be live)"
        fi
        if [[ "$(check_os)" == "macos" ]]; then
            # No service manager on macOS since Homebrew dropped herdr's service
            # (2026-09-24): herdr starts its own server on attach, and nothing
            # restarts it after a crash. A leftover plist is the one wrong state.
            if [[ -e "$HOME/Library/LaunchAgents/homebrew.mxcl.herdr.plist" ]]; then
                echo -e "      ${YELLOW}~${RESET} leftover brew-services LaunchAgent — ${CYAN}herdr server stop${RESET} will respawn (see the pre-flight note)"
            else
                echo -e "      ${GREEN}✓${RESET} server self-started on attach (no launchd job; no crash-restart)"
            fi
        elif command -v systemctl &>/dev/null; then
            # Linux/WSL: the stowed user unit. Report the real state, not the
            # file's presence: a stowed unit can still be down.
            local _unit_state
            _unit_state=$(_herdr_unit_state)
            if [[ "$_unit_state" == "active" ]]; then
                echo -e "      ${GREEN}✓${RESET} server managed by systemd --user and running (crash-restart; linger=$(_herdr_linger))"
            elif [[ -L "$HOME/.config/systemd/user/herdr.service" ]]; then
                echo -e "      ${YELLOW}~${RESET} herdr.service stowed but ${_unit_state} — ${CYAN}systemctl --user enable --now herdr.service${RESET} (stop any hand-started server FIRST)"
            else
                echo -e "      ${YELLOW}~${RESET} server not managed — re-run ${CYAN}./install.sh${RESET} to stow + enable herdr.service"
            fi
        fi
        # Surfaces skew from ANY upgrade path (this script's bump, a manual brew
        # upgrade, the Linux release pin) -- not just one this run just performed.
        # Never restarts anything; see _herdr_server_restart_status.
        local _herdr_restart_status
        _herdr_restart_status=$(_herdr_server_restart_status)
        if [[ "$_herdr_restart_status" == yes:* ]]; then
            echo -e "      ${YELLOW}~${RESET} server still running ${_herdr_restart_status#yes:} (installed build is newer) — restart when convenient:"
            if [[ "$(check_os)" == "macos" ]]; then
                echo -e "        ${CYAN}herdr server stop${RESET}, then open ${CYAN}herdr${RESET} (ends every pane; workspaces are restored; never automatic)"
            else
                echo -e "        ${CYAN}systemctl --user restart herdr.service${RESET} (disrupts every attached session; never automatic)"
            fi
        elif [[ "$_herdr_restart_status" == "no" ]]; then
            echo -e "      ${GREEN}✓${RESET} server running the currently installed build"
        fi
    fi
    echo

    echo -e "${BOLD}Git Extras:${RESET}"
    if command -v git-lfs &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} git-lfs ($(git-lfs version 2>/dev/null | head -1))"
    else
        echo -e "  ${YELLOW}~${RESET} git-lfs — not installed (needed by .gitconfig LFS filter)"
    fi
    echo

    echo -e "${BOLD}Node.js Ecosystem:${RESET}"
    if [[ -d "$HOME/.nvm" ]]; then
        echo -e "  ${GREEN}✓${RESET} nvm ($HOME/.nvm)"
    else
        echo -e "  ${YELLOW}~${RESET} nvm — not installed"
    fi
    if [[ "$SKIP_PNPM" == true ]]; then check_command_optional pnpm "pnpm (--skip-pnpm)" || true
    else check_command pnpm "pnpm" || missing=$((missing+1)); fi
    check_command_optional node "node" || true
    check_command_optional bun  "bun"  || true
    echo

    echo -e "${BOLD}Python (via uv):${RESET}"
    if [[ "$SKIP_UV" == true ]]; then
        echo -e "  ${DIM}-${RESET} Python 3.13 via uv — skipped (--skip-uv)"
    elif command -v uv &>/dev/null; then
        local uv_python
        uv_python=$(uv python list 2>/dev/null | grep "cpython-3.13" | grep -v "download available" | awk '{print $1}' | head -1 || true)
        if [[ -n "$uv_python" ]]; then
            echo -e "  ${GREEN}✓${RESET} Python 3.13 available via uv"
        else
            echo -e "  ${RED}✗${RESET} Python 3.13 not installed — required (run: uv python install 3.13)"
            missing=$((missing+1))
        fi
    fi
    echo

    echo -e "${BOLD}Tmux:${RESET}"
    if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
        echo -e "  ${GREEN}✓${RESET} TPM (Tmux Plugin Manager)"
    else
        echo -e "  ${YELLOW}~${RESET} TPM — not installed (needed for tmux plugins)"
    fi
    echo

    echo -e "${BOLD}Fonts:${RESET}"
    local has_nerd_font=false
    if [[ "$os" == "macos" ]]; then
        local nerd_font_count
        nerd_font_count=$(find ~/Library/Fonts /Library/Fonts \( -iname "*NerdFont*" -o -iname "*Nerd*Font*" \) 2>/dev/null | wc -l || true)
        if (( nerd_font_count > 0 )); then
            has_nerd_font=true
        fi
    else
        local fc_count
        fc_count=$(fc-list 2>/dev/null | grep -ci "nerd" || true)
        if (( fc_count > 0 )); then
            has_nerd_font=true
        fi
    fi
    if [[ "$has_nerd_font" == true ]]; then
        echo -e "  ${GREEN}✓${RESET} Nerd Font detected"
    else
        echo -e "  ${YELLOW}~${RESET} Nerd Font — not found (needed for Powerlevel10k icons)"
    fi
    echo

    echo -e "${BOLD}Optional:${RESET}"
    check_command_optional claude "Claude Code CLI" || true
    check_command_optional yazi     "yazi"     || true
    check_command_optional rustup   "rustup"   || true
    check_command_optional cargo    "cargo"    || true

    echo

    # Deploy parity. A tool that was never linked stays invisible until the day
    # you reach for it -- which, for the guard scripts in home/.local/bin, is
    # exactly the day it matters.
    #
    # It must NOT count toward `missing` during an install run. `missing` gates the
    # prerequisite installer, and a non-zero count after that step aborts with
    # "install them manually" -- BEFORE stow ever runs. Since stow is what deploys
    # these files, folding parity into `missing` deadlocks the installer against
    # itself: it refuses to run the step that fixes the thing it is complaining
    # about, while printing "Fix: ./install.sh". Observed on the Intel MacBook
    # 2026-08-02 after a pull brought in new files; introduced 2026-08-01.
    #
    # In --check (audit) mode there is no stow step to reach, so a parity failure
    # SHOULD make the exit code non-zero -- that is the whole point of the audit.
    echo -e "${BOLD}Deploy Parity:${RESET}"
    local parity=0
    _check_deploy_parity || parity=1
    # settings/ is outside the generic checker's home/ -> ~/ rule; the owner reports.
    _iterm_profiles_sync check || parity=1
    # A hook script that IS linked but is not registered in settings.json is just
    # as undeployed as one that was never linked -- it does nothing either way.
    # Same reporting path, for the same reason. Read-only; writes nothing.
    # The pj settings file is in the same class: present but out of date with the
    # repo is as undeployed as absent, and nothing else would ever say so.
    if [[ "$SKIP_CLAUDE" == true ]]; then
        echo -e "  ${DIM}-${RESET} Claude hooks and pj settings — skipped (--skip-claude)"
    else
        _render_project_settings check || parity=1
        _claude_hooks_sync check || parity=1
    fi
    if (( parity )); then
        if [[ "$ACTION" == "check" ]]; then
            missing=$((missing+1))
        else
            info "The stow steps below deploy these -- continuing."
        fi
    fi

    echo

    # Informational only -- a foreign Python/Node toolchain is disclosed, not
    # something --check can or should fail on (unlike deploy parity above,
    # which represents an actual, fixable deployment problem). Never touches
    # $missing, in any ACTION.
    local stock="$REPO_DIR/home/.local/bin/toolchain-stocktake"
    if [[ -x "$stock" ]] && command -v uv &>/dev/null; then
        echo -e "${BOLD}Toolchain (existing setup, informational):${RESET}"
        "$stock" --verdict any --quiet || true
        echo
    fi

    if (( missing > 0 )); then
        warn "$missing required tool(s) missing"
        return 1
    else
        success "All required prerequisites met"
        return 0
    fi
}

# ==============================================================================
# Installation: Prerequisites
# ==============================================================================

# check_prerequisites() treats Python 3.13 as REQUIRED (missing it aborts the
# whole install), but the only code that installed it used to live in
# post_install() -- reached by main() only AFTER check_prerequisites() passes.
# On a genuinely fresh box (uv just installed this same run, zero managed
# Pythons) that is a dead end: the check can never pass on its own. Confirmed
# live on a clean Mac 2026-08-21 -- install aborted at "Some prerequisites
# are still missing" with Python 3.13 as the sole blocker, one step before
# post_install() would have installed it. Extracted so install_prerequisites()
# can provision it in the SAME pass that installs uv itself, before the
# re-verification; post_install() still calls this too (idempotent, prints
# "already available" the second time) as a harmless safety net.
_ensure_python_313() {
    command -v uv &>/dev/null || return 0
    local has_python
    has_python=$(uv python list 2>/dev/null | grep "cpython-3.13" | grep -v "download available" | head -1 || true)
    if [[ -z "$has_python" ]]; then
        if confirm "Install Python 3.13 via uv?" n y; then
            run_cmd uv python install 3.13
        fi
    else
        success "Python 3.13 already available via uv"
    fi
}

install_prerequisites() {
    local os
    os=$(check_os)

    step "Installing Prerequisites"

    if [[ "$os" == "macos" ]]; then
        install_macos_prerequisites
    elif [[ "$os" == "wsl" || "$os" == "linux" ]]; then
        install_linux_prerequisites
    else
        error "Unsupported OS"
        return 1
    fi

    # Provision Python 3.13 now, not only in post_install() -- see the
    # function comment above for why this must happen before the
    # check_prerequisites() re-verification that follows install_prerequisites().
    _ensure_python_313
}

# Install rustup + stable Rust toolchain. Linux/WSL only — macOS users get
# rust via Homebrew if they need it. Idempotent: returns early if rustup is
# already installed. If apt's old cargo/rustc 1.75 is detected (too old for
# cargo-binstall), offers to remove them with confirm — never silent.
install_rust_toolchain() {
    if command -v rustup &>/dev/null; then
        success "rustup already installed ($(rustup --version 2>/dev/null | head -1))"
        return 0
    fi

    # Detect apt's old cargo/rustc and offer removal — never silent.
    if command -v apt &>/dev/null && dpkg -s cargo &>/dev/null 2>&1; then
        local apt_cargo_version
        apt_cargo_version=$(dpkg -s cargo 2>/dev/null | awk '/^Version:/ {print $2}')
        warn "apt-installed cargo detected ($apt_cargo_version). This is too old for cargo-binstall (needs ≥1.79)."
        if confirm "Remove apt cargo + rustc before installing rustup?" "y"; then
            run_cmd sudo apt remove -y cargo rustc
        else
            warn "Keeping apt cargo/rustc — rustup will install alongside; PATH order will determine which wins."
        fi
    fi

    info "Installing rustup (official Rust toolchain manager)..."
    run_cmd bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default"

    # Source cargo env so the rest of this script sees cargo/rustc immediately.
    if [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi

    if command -v cargo &>/dev/null; then
        success "Rust toolchain ready ($(rustc --version 2>/dev/null))"
    else
        warn "rustup install completed but cargo not on PATH — open a new shell or run: source ~/.cargo/env"
    fi
}

# Install yazi from the latest GitHub release zip. Linux/WSL only.
# Decoupled from rust — yazi binaries don't need a rust toolchain at runtime.
# Avoids cargo install entirely because yazi-fm and yazi-cli on crates.io
# (as of v26.5.6) ship with broken build.rs guards and missing Lua presets.
install_yazi_release() {
    if command -v yazi &>/dev/null; then
        success "yazi already installed ($(yazi --version 2>/dev/null | head -1))"
        return 0
    fi

    if ! command -v unzip &>/dev/null; then
        warn "unzip not found — required to extract yazi release. Install it first (e.g., sudo apt install -y unzip)."
        return 1
    fi

    local arch_triple
    case "$(uname -m)" in
        x86_64)         arch_triple="x86_64-unknown-linux-gnu" ;;
        aarch64|arm64)  arch_triple="aarch64-unknown-linux-gnu" ;;
        *) warn "Unsupported architecture for yazi release: $(uname -m)"; return 1 ;;
    esac

    # Resolve latest release tag by following the /releases/latest redirect.
    # No API call, no auth, no rate limit.
    local latest_url tag
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/sxyazi/yazi/releases/latest" 2>/dev/null || true)
    tag="${latest_url##*/}"
    if [[ -z "$tag" || "$tag" == "latest" ]]; then
        warn "Could not resolve latest yazi release tag from GitHub"
        return 1
    fi
    info "Latest yazi release: $tag"

    local asset="yazi-${arch_triple}.zip"
    local url="https://github.com/sxyazi/yazi/releases/download/${tag}/${asset}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    info "Downloading $asset..."
    if ! run_cmd curl -fL --proto '=https' --tlsv1.2 -o "$tmp_dir/$asset" "$url"; then
        warn "yazi download failed from $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    run_cmd unzip -q "$tmp_dir/$asset" -d "$tmp_dir"

    mkdir -p "$HOME/.local/bin"
    run_cmd mv -f "$tmp_dir/yazi-${arch_triple}/yazi" "$HOME/.local/bin/yazi"
    run_cmd mv -f "$tmp_dir/yazi-${arch_triple}/ya"   "$HOME/.local/bin/ya"
    chmod +x "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya"

    rm -rf "$tmp_dir"

    if command -v yazi &>/dev/null; then
        success "yazi installed: $(yazi --version 2>/dev/null | head -1)"
    else
        warn "yazi install completed but not on PATH — ensure ~/.local/bin is on PATH"
    fi
}

install_herdr_release() {
    # Linux/WSL only. macOS takes the Homebrew path in install_macos_prerequisites.
    #
    # Deliberately unlike install_yazi_release(), which resolves "latest": herdr
    # is version-PINNED and hash-VERIFIED. herdr ships a self-updater and two
    # default-on calls to herdr.dev, so an unpinned install would walk itself
    # past the cooldown. The pin here is what the Homebrew pin is on macOS.

    local arch_key asset expected
    case "$(uname -m)" in
        x86_64)         arch_key="x86_64";  expected="$HERDR_SHA256_LINUX_X86_64" ;;
        aarch64|arm64)  arch_key="aarch64"; expected="$HERDR_SHA256_LINUX_AARCH64" ;;
        *) warn "Unsupported architecture for herdr release: $(uname -m)"; return 1 ;;
    esac
    asset="herdr-linux-${arch_key}"

    # Already at the pinned version? Nothing to do. `herdr --version` prints
    # "herdr 0.7.5"; HERDR_VERSION carries the leading v, so compare on the tail.
    if command -v herdr &>/dev/null; then
        local have want
        have=$(herdr --version 2>/dev/null | awk '{print $2}')
        want="${HERDR_VERSION#v}"
        if [[ "$have" == "$want" ]]; then
            success "herdr already at pinned ${HERDR_VERSION}"
            return 0
        fi
        info "herdr ${have:-unknown} installed; pinned release is ${HERDR_VERSION}"
    fi

    if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
        warn "Neither shasum nor sha256sum found — cannot verify herdr download. Refusing to install."
        return 1
    fi

    local url tmp_dir
    url="https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/${asset}"
    tmp_dir=$(mktemp -d)

    info "Downloading herdr ${HERDR_VERSION} (${asset})..."
    if ! run_cmd curl -fL --proto '=https' --tlsv1.2 -o "$tmp_dir/$asset" "$url"; then
        warn "herdr download failed from $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    # In dry-run nothing was downloaded, so there is nothing to verify.
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would verify sha256 ${expected:0:16}... and install to ~/.local/bin/herdr"
        rm -rf "$tmp_dir"
        return 0
    fi

    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')
    fi

    if [[ "$actual" != "$expected" ]]; then
        error "herdr checksum MISMATCH — refusing to install."
        warn  "  asset:    $asset (${HERDR_VERSION})"
        warn  "  expected: $expected"
        warn  "  actual:   $actual"
        warn  "The pinned artefact does not match what this repo vetted. Do NOT"
        warn  "work around this by loosening the pin. Either the release was"
        warn  "re-uploaded, or the download was tampered with in transit."
        rm -rf "$tmp_dir"
        return 1
    fi
    success "herdr checksum verified (sha256 ${actual:0:16}...)"

    mkdir -p "$HOME/.local/bin"
    run_cmd mv -f "$tmp_dir/$asset" "$HOME/.local/bin/herdr"
    chmod +x "$HOME/.local/bin/herdr"
    rm -rf "$tmp_dir"

    if command -v herdr &>/dev/null; then
        success "herdr installed: $(herdr --version 2>/dev/null | head -1)"
    else
        warn "herdr installed to ~/.local/bin but not on PATH — ensure ~/.local/bin is on PATH"
    fi
}

# --- Purge an installed yt-dlp -----------------------------------------------
#
# yt() now runs yt-dlp on demand via `uvx` -- nothing is installed, so it is
# always current. A yt-dlp left over from before this switch is stale and
# redundant. Force-remove anything package-managed (trivially reinstallable).
# On Linux, also force-remove any loose yt-dlp binary found on PATH -- yt-dlp's
# own upstream install method is a raw curl-to-/usr/local/bin (or /usr/bin)
# download with no package manager involved, so a loose binary is the common
# case there, not the exception. Only a system-Python pip install is left for
# the user to remove by hand (never touch site-packages from this installer).
#
# Called unconditionally from main() (like _preflight_herdr_release_check and
# friends), NOT from inside install_macos_prerequisites/install_linux_prerequisites
# -- those only run when check_prerequisites() finds a REQUIRED tool missing,
# so a fully-provisioned box (the common case: aria2/ffmpeg already installed,
# nothing else missing) would otherwise never reach the purge at all. Confirmed
# live on mlbox-ubuntu 2026-08-21: a real apt-installed yt-dlp survived a full
# `./install.sh` run untouched until this moved to the unconditional path.
# ==============================================================================
# Pre-flight: is the C/C++ toolchain actually usable?
# ==============================================================================
# WHY THIS EXISTS. On 2026-09-05 the Intel MacBook failed to build ten Homebrew
# formulae -- aom, libde265, libheif, simdjson, sevenzip, ffmpegthumbnailer,
# pandoc, gcc, fonttools, pnpm -- every one of them dying on a missing C++
# header ('string', 'algorithm', 'new', 'cstddef' file not found). Homebrew
# blamed Intel in a footer it prints after EVERY failure, which is not a
# diagnosis, and finding the real cause took most of a session by hand.
#
# The real cause: clang 17 searched
#   /Library/Developer/CommandLineTools/usr/include/c++/v1        <- absent
# while the 193 C++ headers sat in the SDK instead. C headers WERE on the search
# path, which is exactly why C formulae built fine and C++ formulae did not --
# the split that made the Intel warning look plausible when it was irrelevant.
#
# THE PROBE IS A COMPILE, NOT A VERSION COMPARISON. Comparing clang and SDK
# versions would need a table of which pairings Apple considers valid. Asking
# the compiler to compile something asks the same question Homebrew asks, and
# cannot be fooled. Measured at ~440ms -- nothing beside the brew work above.
#
# NEVER BLOCKS. A broken compiler does not stop stow, hook registration or
# anything else this installer does. An installer that refused to do the work it
# CAN do would be worse than the bug it is reporting. Always returns 0.
_preflight_cc_toolchain_check() {
    [[ "${SKIP_PREFLIGHT:-false}" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v clang++ &>/dev/null || return 0

    if printf '#include <string>\nint main(){return 0;}\n' \
         | clang++ -x c++ -fsyntax-only - 2>/dev/null; then
        CC_TOOLCHAIN_OK=true
        return 0        # healthy -- say nothing, like every other parity check
    fi
    # Recorded so _offer_brew_sweep can refuse to offer a source-build sweep on a
    # machine that provably cannot compile C++.
    CC_TOOLCHAIN_OK=false

    echo
    echo -e "${BOLD}━━━ Pre-flight C++ toolchain check ━━━${RESET}"
    warn "The C++ toolchain cannot compile a one-line program."

    # Gather the three facts that actually identify the fault. Each guarded:
    # a diagnostic that aborts the installer is a worse bug than the one it reports.
    local cc_ver="" sdk_path="" sdk_ver="" want=""
    cc_ver=$(clang++ --version 2>/dev/null | head -1) || true
    sdk_path=$(xcrun --show-sdk-path 2>/dev/null | tail -1) || true
    sdk_ver=$(xcrun --show-sdk-version 2>/dev/null | tail -1) || true
    # The C++ include directory clang actually searches, straight out of -v.
    # One pipeline: the intermediate search-list was only ever read once.
    want=$(printf '#include <string>\n' | clang++ -x c++ -fsyntax-only -v - 2>&1 \
           | sed -n '/#include <...> search starts here/,/End of search list/p' \
           | grep -m1 'c++/v1' | sed 's/^[[:space:]]*//') || true

    # Kept for the closing summary, which repeats the manual step long after
    # these locals have gone out of scope. Printing facts the script already
    # knows is the difference between "match your macOS version" (a lookup the
    # operator has to perform) and a line they can act on directly.
    CC_CLANG_MAJOR=$(printf '%s' "$cc_ver" | grep -oE 'version [0-9]+' | grep -oE '[0-9]+') || true
    CC_SDK_VER="$sdk_ver"

    [[ -n "$cc_ver"   ]] && echo -e "      compiler: ${CYAN}${cc_ver}${RESET}"
    [[ -n "$sdk_ver"  ]] && echo -e "      SDK:      ${CYAN}${sdk_ver}${RESET}  ${DIM}${sdk_path}${RESET}"
    if [[ -n "$want" ]]; then
        if [[ -d "$want" ]]; then
            echo -e "      C++ headers: ${DIM}${want}${RESET} (exists -- fault is elsewhere)"
        else
            echo -e "      ${RED}MISSING${RESET}  ${want}"
            echo -e "      ${DIM}clang looks there for C++ headers; the directory is not present.${RESET}"
        fi
    fi
    echo -e "      ${DIM}C compiles, C++ does not -- typically a compiler and SDK from${RESET}"
    echo -e "      ${DIM}different Command Line Tools releases.${RESET}"
    echo
    echo -e "  ${YELLOW}Effect:${RESET} Homebrew cannot build anything from source that uses C++."
    echo -e "  ${DIM}Bottled formulae still install fine, so this stays invisible until a build.${RESET}"
    echo

    # OFFERED, never automatic. Installing Command Line Tools needs sudo and can
    # run past twenty minutes -- not a decision an installer gets to make while
    # the operator is away.
    if confirm "Look for a Command Line Tools update now?"; then
        _offer_clt_install "$cc_ver"
    else
        info "Skipped. To fix later:  softwareupdate --list"
    fi
    info "Re-test with:  echo '#include <string>' | clang++ -x c++ -fsyntax-only -"
    echo
    return 0    # never fatal
}

# Run a command with a wall-clock limit, degrading to no limit when `timeout` is
# absent. `timeout` is coreutils, NOT stock macOS (/usr/bin/timeout does not
# exist), so a bare call would break the very machines this script targets.
# Written after `softwareupdate --list` sat for over ten minutes during
# development -- an installer that can hang forever on a network call is an
# installer people learn to kill.
_run_limited() {
    local secs="$1"; shift
    if command -v timeout &>/dev/null; then timeout "$secs" "$@"
    elif command -v gtimeout &>/dev/null; then gtimeout "$secs" "$@"
    else "$@"
    fi
}

# Find and offer a Command Line Tools install.
#
# WHAT CANNOT BE AUTOMATED, and why this is an offer rather than a fix:
# the standalone package on developer.apple.com is behind an Apple ID login, so
# no script can fetch it. That leaves `softwareupdate`, which on the affected
# Intel MacBook listed NO Command Line Tools item at all (verified there
# 2026-09-05: it offered only Safari and macOS 15.7.9).
#
# The `installondemand` marker below is the documented way to make softwareupdate
# surface the CLT package when it otherwise will not. It was NOT verifiable on the
# development machine -- the sandbox refused to create the marker -- so it is
# written to fail soft: if no CLT item appears, the operator gets the download
# page instead, which is exactly where they were headed anyway.
# Remove the installondemand marker, but ONLY if we were the ones who made it.
# Leaving it behind makes macOS believe a Command Line Tools install is in
# progress; removing someone else's would break whatever put it there.
_clt_marker_cleanup() {
    local created="$1" marker="$2"
    [[ "$created" == true ]] && rm -f "$marker" 2>/dev/null
    return 0
}

# $1 (optional) = the clang version line, used to spot a downgrade offer.
_offer_clt_install() {
    local cc_ver="${1:-}"
    local marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    local created=false list="" label=""

    if [[ ! -e "$marker" ]]; then
        # `touch`, not `: > "$marker" 2>/dev/null`. A FAILED REDIRECT is reported by
        # the shell itself, before the redirection it was asked to apply, so the
        # 2>/dev/null does not suppress it and "Operation not permitted" leaks into
        # the output of a check whose whole job is to be readable.
        if touch "$marker" 2>/dev/null; then created=true; fi
    fi

    info "Asking Software Update (up to 90s)..."
    list=$(_run_limited 90 softwareupdate --list 2>&1) || true

    label=$(printf '%s\n' "$list" \
            | grep -iE '^\s*\*\s*Label:.*Command Line Tools' \
            | head -1 | sed 's/^[^:]*:[[:space:]]*//') || true

    if [[ -n "$label" ]]; then
        success "Software Update is offering: ${label}"

        # WARN WHEN THE OFFER IS OLDER THAN WHAT IS INSTALLED. Measured on the
        # Intel MacBook 2026-09-05: with clang 17 already present, the marker
        # surfaced "Command Line Tools for Xcode-16.2" -- an OLDER release --
        # and `--install` then answered "No such update". An offer that would
        # downgrade the compiler is not the fix for a compiler that is too old
        # for its SDK, so say so rather than let it look like the answer.
        local offer_major="" cc_major=""
        offer_major=$(printf '%s' "$label" | grep -oE '[0-9]+' | head -1) || true
        cc_major=$(printf '%s' "${cc_ver:-}" | grep -oE 'version [0-9]+' | grep -oE '[0-9]+') || true
        if [[ -n "$offer_major" && -n "$cc_major" ]] && (( offer_major < cc_major )); then
            warn "That offer (Xcode-${offer_major}) is OLDER than your installed clang ${cc_major}."
            echo -e "  ${DIM}Installing it would be a downgrade, and Software Update often refuses${RESET}"
            echo -e "  ${DIM}such an offer with 'No such update'. The download page below is the${RESET}"
            echo -e "  ${DIM}reliable route -- pick the newest Command Line Tools for your macOS.${RESET}"
        else
            echo -e "  ${DIM}This needs sudo and can take a long time. It will not run unattended.${RESET}"
            if confirm "Install it now with softwareupdate (requires sudo)?"; then
                # The installondemand marker must still EXIST while --install runs.
                # It was removed right after --list in the first version of this
                # function, and the install then failed with "No such update" on the
                # very label the listing had just produced. Cleanup happens below,
                # after the attempt, on every path.
                if run_cmd sudo softwareupdate --install "$label"; then
                    _clt_marker_cleanup "$created" "$marker"
                    return 0
                fi
                warn "The install did not complete. Falling back to the download page."
            else
                info "Skipped. To install later:"
                echo -e "    ${CYAN}sudo softwareupdate --install \"${label}\"${RESET}"
                _clt_marker_cleanup "$created" "$marker"
                return 0
            fi
        fi
    else
        warn "Software Update is not offering Command Line Tools on this machine."
    fi

    _clt_marker_cleanup "$created" "$marker"
    info "The standalone package is behind an Apple ID login, so no script can fetch it."
    local _os_ver="" _os_major=""
    _os_ver=$(sw_vers -productVersion 2>/dev/null) || true
    _os_major="${_os_ver%%.*}"
    echo -e "  ${DIM}This machine: macOS ${_os_ver:-unknown}${cc_ver:+, ${cc_ver}}${RESET}"
    echo -e "  Take the ${BOLD}newest${RESET} \"Command Line Tools for Xcode\" listed for macOS ${_os_major:-your version}."
    echo -e "  ${DIM}It installs over the top -- nothing needs deleting first.${RESET}"
    # Default YES. Opening a page is free and reversible, and it is what the
    # operator is going to do next anyway -- making them type 'y' to reach the
    # only remaining route is friction with no safety value.
    if command -v open &>/dev/null && confirm "Open the download page now?" y n; then
        run_cmd open "https://developer.apple.com/download/all/?q=command+line+tools" || true
    fi
    return 0
}

# ==============================================================================
# Offer to sweep up outdated Homebrew formulae
# ==============================================================================
# DELIBERATELY NOT AUTOMATIC, and deliberately gated on the compiler.
#
# A blanket `brew upgrade` is not a dotfiles concern and is not cheap: the Intel
# MacBook had 76 outdated packages, several of which build from source for
# tens of minutes each. Wiring that into every ./install.sh would make an
# ordinary restow occasionally take hours, which is how people stop running the
# installer at all.
#
# It is ALSO gated on the C++ toolchain being healthy. Offering the sweep on a
# machine whose compiler is broken would simply reproduce the same ten build
# failures that started this whole thread -- an offer that is guaranteed to
# waste the operator's evening is worse than no offer.
_offer_brew_sweep() {
    [[ "${SKIP_PREFLIGHT:-false}" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v brew &>/dev/null || return 0
    # Only when the compiler works. CC_TOOLCHAIN_OK is set by the C++ pre-flight.
    [[ "${CC_TOOLCHAIN_OK:-true}" == true ]] || {
        info "Skipping the Homebrew sweep -- the C++ toolchain is broken, so source builds would fail again."
        return 0
    }

    # ASK AT MOST ONCE A WEEK. There are almost always SOME outdated formulae, so
    # an unconditional offer would appear on every single run -- identical every
    # time, which is precisely how a prompt stops being read and starts being
    # dismissed reflexively. Same 7-day marker shape as the pnpm store prune.
    local marker_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
    local marker="$marker_dir/brew_sweep_offered"
    if [[ -f "$marker" ]]; then
        local now mtime age
        now=$(date +%s)
        mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null) || mtime=""
        if [[ -n "$mtime" ]]; then
            age=$(( now - mtime ))
            (( age < 604800 )) && return 0
        fi
    fi

    local n=0
    n=$( { _run_limited 30 brew outdated --formula 2>/dev/null || true; } | grep -c . ) || true
    (( n == 0 )) && return 0

    # Claim the weekly slot BEFORE asking, so declining does not re-ask tomorrow.
    [[ -d "$marker_dir" ]] || mkdir -p "$marker_dir" 2>/dev/null || true
    touch "$marker" 2>/dev/null || true

    echo
    echo -e "${BOLD}━━━ Outdated Homebrew formulae ━━━${RESET}"
    info "${n} formula(e) are outdated."
    echo -e "  ${DIM}A full upgrade can run for a long time -- some formulae build from source.${RESET}"
    if confirm "Run 'brew upgrade' now?"; then
        run_cmd brew upgrade || warn "brew upgrade did not finish cleanly; re-run it when convenient."
    else
        info "Skipped. Run it yourself anytime:  brew upgrade"
    fi
    echo
    return 0
}

# ==============================================================================
# Pre-flight: is another Homebrew already running?
# ==============================================================================
# WHY. On 2026-09-05 two terminals ran at once: one `./install.sh`, one
# `brew upgrade`. The installer's herdr upgrade died twice on
# "A `brew upgrade herdr` process has already locked /usr/local/Cellar/cmake",
# and its yt-dlp removal was undone by the other tab reinstalling yt-dlp over
# nineteen minutes. Both wasted, and neither message said "something else is
# running" in a way that pointed at the real cause.
#
# LOCK FILES ARE NOT A LIVENESS SIGNAL -- measured, and this is the trap.
# $(brew --prefix)/var/homebrew/locks on this machine holds ~100 lock files
# including aom.formula.lock dated 31 August, with no brew running at all.
# Homebrew leaves them behind and re-uses them via flock; presence means
# "was locked once", never "is locked now". So this looks for a live PROCESS.
_preflight_brew_busy_check() {
    [[ "${SKIP_PREFLIGHT:-false}" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v brew &>/dev/null || return 0
    command -v pgrep &>/dev/null || return 0

    # Match the real work, not any brew invocation: `brew list` in a prompt hook
    # is harmless and must not trip this. Our own subprocesses are excluded by
    # checking against this script's process group.
    local busy=""
    busy=$(pgrep -fl 'brew (install|upgrade|uninstall|reinstall|autoremove)' 2>/dev/null \
           | grep -v "^$$ " || true)
    [[ -z "$busy" ]] && return 0

    echo
    echo -e "${BOLD}━━━ Pre-flight Homebrew concurrency check ━━━${RESET}"
    warn "Another Homebrew job is running right now:"
    printf '      %s\n' "${busy}" | head -3
    echo
    echo -e "  ${DIM}Two brew runs fight: one takes a formula lock the other needs, and each${RESET}"
    echo -e "  ${DIM}can undo the other's work. Observed 2026-09-05 -- a herdr upgrade failed${RESET}"
    echo -e "  ${DIM}twice on a cmake lock while the other tab rebuilt a package this script${RESET}"
    echo -e "  ${DIM}had just removed.${RESET}"
    echo
    if confirm "Continue anyway (brew steps will probably fail)?"; then
        warn "Continuing with a concurrent brew. Expect lock errors."
        return 0
    fi
    error "Stopped. Let the other Homebrew job finish, then re-run ./install.sh"
    exit 1
}

# ==============================================================================
# Pre-flight: untrusted Homebrew taps
# ==============================================================================
# Homebrew now IGNORES formulae from untrusted taps. That is silent in the sense
# that matters: a formula you believe is installed simply stops being offered.
#
# PER-FORMULA ONLY, DELIBERATELY. `brew trust <tap>` trusts every current AND
# FUTURE formula, cask and command from that tap -- a standing grant to a third
# party. `brew trust --formula <tap>/<name>` grants exactly one. This repo's
# standing policy is the narrow one, and this function must never print the
# broad form even though `brew` itself offers it.
_preflight_brew_tap_trust_check() {
    [[ "${SKIP_PREFLIGHT:-false}" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v brew &>/dev/null || return 0

    # `brew tap-info --json` carries NO trust field -- checked 2026-09-05, the key
    # simply is not there. The only machine-readable signal Homebrew gives is the
    # warning it prints, so parse that. `brew tap` costs 16ms here, which is the
    # cheapest command that still emits it.
    local out="" taps="" narrow=""
    out=$(brew tap 2>&1) || true
    printf '%s\n' "$out" | grep -q "The following taps are not trusted:" || return 0

    taps=$(printf '%s\n' "$out" \
           | sed -n '/The following taps are not trusted:/,/^$/p' \
           | sed '1d;/^$/d;s/^[[:space:]]*//') || true
    [[ -z "$taps" ]] && return 0

    # Surface Homebrew's OWN per-formula suggestions rather than inventing them --
    # brew already knows which formula from each tap is actually installed, and
    # guessing that mapping ourselves would be wrong the moment it changes.
    narrow=$(printf '%s\n' "$out" \
             | grep -E '^[[:space:]]*brew trust --(formula|cask) ' \
             | sed 's/^[[:space:]]*//') || true

    echo
    echo -e "${BOLD}━━━ Pre-flight Homebrew tap trust ━━━${RESET}"
    warn "$(printf '%s\n' "$taps" | grep -c .) tap(s) untrusted -- Homebrew is IGNORING their formulae."
    # Indent with sed rather than an unquoted printf. Unquoted expansion would
    # word-split AND glob-expand each line; tap names are owner/name so nothing
    # would break today, but a name is data and data should not reach a glob.
    printf '%s\n' "$taps" | sed 's/^/      /'
    echo
    if [[ -n "$narrow" ]]; then
        info "Trust only what you actually use, one at a time:"
        printf '%s\n' "$narrow" | sed "s/^/    ${CYAN}/;s/\$/${RESET}/"
    else
        info "Trust only what you actually use:  brew trust --formula <tap>/<formula>"
    fi
    # Homebrew's own output ALSO offers `brew trust <tap>` (whole-tap). That form is
    # deliberately filtered out above and must never be echoed here: it is standing
    # trust for every CURRENT AND FUTURE formula, cask and command from a third
    # party. The narrow grant is this repo's standing policy.
    echo -e "  ${DIM}Not 'brew trust <tap>' -- that trusts every future formula from it too.${RESET}"
    echo
    return 0
}

_preflight_purge_ytdlp() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    local removed=false

    if [[ "$(check_os)" == "macos" ]] && command -v brew &>/dev/null && brew list yt-dlp &>/dev/null; then
        info "Removing yt-dlp (installed via Homebrew) — yt() now runs it via uvx."
        run_cmd brew uninstall --force yt-dlp
        removed=true
    fi

    if command -v uv &>/dev/null && uv tool list 2>/dev/null | grep -q '^yt-dlp '; then
        info "Removing yt-dlp (installed via uv tool) — yt() now runs it via uvx."
        run_cmd uv tool uninstall yt-dlp
        removed=true
    fi

    if command -v pipx &>/dev/null && pipx list --short 2>/dev/null | grep -q '^yt-dlp '; then
        info "Removing yt-dlp (installed via pipx) — yt() now runs it via uvx."
        run_cmd pipx uninstall yt-dlp
        removed=true
    fi

    if [[ "$(check_os)" != "macos" ]]; then
        if command -v dpkg &>/dev/null && dpkg -s yt-dlp &>/dev/null; then
            info "Removing yt-dlp (installed via apt) — yt() now runs it via uvx."
            run_cmd sudo apt remove -y yt-dlp
            removed=true
        elif command -v rpm &>/dev/null && rpm -q yt-dlp &>/dev/null; then
            info "Removing yt-dlp (installed via dnf) — yt() now runs it via uvx."
            run_cmd sudo dnf remove -y yt-dlp
            removed=true
        elif command -v pacman &>/dev/null && pacman -Q yt-dlp &>/dev/null; then
            info "Removing yt-dlp (installed via pacman) — yt() now runs it via uvx."
            run_cmd sudo pacman -R --noconfirm yt-dlp
            removed=true
        fi
    fi

    # Never touch a system Python's site-packages -- warn with the exact
    # removal command instead.
    if command -v pip &>/dev/null && pip show yt-dlp &>/dev/null; then
        warn "yt-dlp is also installed via pip — yt() no longer needs it. Remove manually: pip uninstall yt-dlp"
    fi

    if [[ "$(check_os)" == "macos" ]]; then
        # macOS: package managers above cover the normal case. A loose binary
        # here is rare and its location unpredictable -- warn rather than guess.
        if command -v yt-dlp &>/dev/null; then
            warn "yt-dlp binary still on PATH at $(command -v yt-dlp) — yt() no longer needs it. Remove manually."
        fi
    else
        # Linux: force-remove every loose yt-dlp found on PATH, not just the
        # first `command -v` hit -- a duplicate like /usr/bin + /bin (often the
        # same file via a symlinked dir, but not guaranteed) must not leave one
        # behind. None of these are owned by a package manager (that case was
        # already handled above), so this is the only place they get removed.
        local -a loose_paths=()
        local dir lp
        local old_ifs="$IFS"
        IFS=':'
        for dir in $PATH; do
            [[ -n "$dir" ]] || continue
            lp="$dir/yt-dlp"
            [[ -f "$lp" && -x "$lp" ]] || continue
            loose_paths+=("$lp")
        done
        IFS="$old_ifs"

        for lp in "${loose_paths[@]}"; do
            [[ -e "$lp" ]] || continue   # already gone (e.g. same file via a symlinked dir)
            info "Removing yt-dlp binary at $lp — yt() now runs it via uvx."
            run_cmd sudo rm -f "$lp"
            removed=true
        done
    fi

    if [[ "$removed" == true ]]; then
        success "System yt-dlp removed — yt() runs it via uvx from here on."
    fi
}

install_macos_prerequisites() {
    # --- Homebrew ---
    if ! command -v brew &>/dev/null; then
        if confirm "Homebrew not found. Install it?"; then
            run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ -d /opt/homebrew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        else
            error "Homebrew is required on macOS. Aborting."
            return 1
        fi
    fi
    success "Homebrew ready"

    # --- Core formulae ---
    # herdr is core on macOS only. It has no apt/dnf/pacman package, and its
    # vendor installer performs NO checksum or signature verification, so the
    # Linux path is deliberately left manual rather than automated around a
    # supply chain we would not otherwise accept. See docs/HERDR.md.
    # No `trash` formula (Gavin, 2026-09-29, W-20260929-A170): it is hasseg's tool, keg-only
    # since macOS ships /usr/bin/trash, so it never lands on PATH, and its -e/-s mean "empty
    # the Trash". The dotfiles use Apple's /usr/bin/trash only.
    local -a formulae=(stow uv direnv jq fzf eza zoxide neovim tmux ripgrep fd gh git-lfs glow herdr aria2 ffmpeg)
    local to_install=()

    if [[ "$SKIP_SYSTEM_PACKAGES" == true ]]; then
        info "Homebrew formula installs skipped (--skip-system-packages)."
        formulae=()
    fi
    for formula in "${formulae[@]+"${formulae[@]}"}"; do
        [[ "$SKIP_HERDR" == true && "$formula" == herdr ]] && continue
        [[ "$SKIP_TMUX" == true && "$formula" == tmux ]] && continue
        [[ "$SKIP_UV" == true && "$formula" == uv ]] && continue
        if ! brew list "$formula" &>/dev/null; then
            to_install+=("$formula")
        fi
    done

    if (( ${#to_install[@]} > 0 )); then
        info "Core tools to install: ${to_install[*]}"
        if confirm "Install these core tools via Homebrew?" n y; then
            run_cmd brew install "${to_install[@]}"
        fi
    elif [[ "$SKIP_SYSTEM_PACKAGES" != true ]]; then
        success "Core formulae already installed"
    fi

    # Pin herdr the moment it exists. The pre-flight guard runs BEFORE this
    # point, so on a fresh box it finds no herdr and returns clean -- leaving a
    # freshly installed, unpinned formula that the next `brew upgrade` could
    # walk straight past the cooldown. Close that window here.
    _preflight_herdr_pin_check

    # --- Required CLI tools (lazygit, lazydocker — installed unconditionally) ---
    local -a required_cli=(lazygit lazydocker)
    [[ "$SKIP_DOCKER" == true ]] && required_cli=(lazygit)
    [[ "$SKIP_SYSTEM_PACKAGES" == true ]] && required_cli=()
    local req_install=()
    for formula in "${required_cli[@]+"${required_cli[@]}"}"; do
        brew list "$formula" &>/dev/null || req_install+=("$formula")
    done
    if (( ${#req_install[@]} > 0 )); then
        info "Installing required CLI tools: ${req_install[*]}"
        run_cmd brew install "${req_install[@]}"
    elif [[ "$SKIP_SYSTEM_PACKAGES" != true ]]; then
        success "lazygit + lazydocker already installed"
    fi

    # --- Optional CLI tools ---
    local -a optional=(tree fastfetch yazi)
    [[ "$SKIP_YAZI" == true ]] && optional=(tree fastfetch)
    [[ "$SKIP_SYSTEM_PACKAGES" == true ]] && optional=()
    local opt_install=()

    for formula in "${optional[@]+"${optional[@]}"}"; do
        if ! brew list "$formula" &>/dev/null; then
            opt_install+=("$formula")
        fi
    done

    if (( ${#opt_install[@]} > 0 )); then
        echo
        info "Optional CLI tools not yet installed: ${opt_install[*]}"
        if confirm "Install optional CLI tools (tree, fastfetch, yazi)?"; then
            # Install individually + non-fatal: a discontinued or renamed optional
            # formula must never abort the whole install (these are non-essential).
            local opt
            for opt in "${opt_install[@]}"; do
                run_cmd brew install "$opt" || warn "Optional '$opt' not installed (skipped)."
            done
        fi
    fi

    # --- pnpm ---
    # macOS provider: the standalone pnpm (get.pnpm.io) on every Mac since
    # 2026-10-06 (D-20261006-A08); _pnpm_use_homebrew is always false and its
    # branch below is kept only so every caller reads one answer.
    if [[ "$SKIP_PNPM" == true ]]; then
        verbose "pnpm skipped (--skip-pnpm)"
    elif _pnpm_needs_install_or_upgrade; then
        if _pnpm_use_homebrew; then
            # Intel macOS: Homebrew is the supported pnpm provider.
            local cur_pnpm=""
            command -v pnpm &>/dev/null && cur_pnpm=$(pnpm -v 2>/dev/null || echo "unknown")
            if brew list pnpm &>/dev/null; then
                # Below-floor is enforced (not optional) by _preflight_pnpm_floor_check,
                # which always runs earlier in main() and exits if it can't fix it -- so
                # a below-floor pnpm never reaches this branch on a normal run. This
                # confirm only still fires under --skip-preflight (a deliberate bypass).
                if confirm "pnpm ${cur_pnpm} is below ${PNPM_MIN_VERSION}. Run 'brew upgrade pnpm'?"; then
                    run_cmd brew upgrade pnpm
                fi
            elif confirm "pnpm not found. Install it via Homebrew (standalone is broken on Intel macOS)?"; then
                run_cmd brew install pnpm
            fi
            hash -r 2>/dev/null || true
            # Globals + completion still live under PNPM_HOME; the config bridge
            # below applies regardless of provider, so supply-chain settings hold.
            export PNPM_HOME="$HOME/Library/pnpm"
            if command -v pnpm &>/dev/null; then
                mkdir -p "$PNPM_HOME"
                pnpm completion zsh > "$PNPM_HOME/_pnpm" 2>/dev/null || true
            fi
        else
            local cur_pnpm="" prompt=""
            command -v pnpm &>/dev/null && cur_pnpm=$(pnpm -v 2>/dev/null || echo "unknown")
            if _pnpm_is_standalone; then
                # Below-floor is enforced (not optional) by _preflight_pnpm_floor_check,
                # which always runs earlier in main() and exits if it can't fix it -- so
                # this branch's confirm below only still fires under --skip-preflight.
                prompt="pnpm ${cur_pnpm} is below required ${PNPM_MIN_VERSION}. Run 'pnpm self-update' now?"
            elif [[ -n "$cur_pnpm" ]]; then
                prompt="Active pnpm ${cur_pnpm} is not the standalone install (corepack/npm-global). Install standalone pnpm now?"
            else
                prompt="pnpm not found. Install it (standalone)?"
            fi
            if confirm "$prompt" n y; then
                # self-update only works on a real standalone; for a corepack shim
                # or npm-global pnpm it can't create $PNPM_HOME/bin — curl instead.
                if _pnpm_is_standalone; then
                    run_cmd pnpm self-update
                else
                    run_cmd bash -c 'curl -fsSL https://get.pnpm.io/install.sh | sh -'
                fi
                export PNPM_HOME="$HOME/Library/pnpm"
                export PATH="$PNPM_HOME/bin:$PATH"
                # Regenerate zsh completion so .zshrc's `source "$PNPM_HOME/_pnpm"`
                # picks up the just-installed pnpm version. Sourced at .zshrc:255.
                if command -v pnpm &>/dev/null; then
                    pnpm completion zsh > "$PNPM_HOME/_pnpm" 2>/dev/null || true
                fi
                # pnpm self-update always regenerates shims at BOTH root and bin/.
                # Root shims trigger "Detected a pnpm v10 installation layout"
                # warnings. Remove them — only $PNPM_HOME/bin is on PATH.
                if [[ -f "$PNPM_HOME/pnpm" ]]; then
                    local shim
                    for shim in pnpm pnpx pn pnx; do
                        [[ -f "$PNPM_HOME/$shim" ]] && "$SAFE_RM" "$PNPM_HOME/$shim"
                    done
                    info "Root-level shims removed (v11 layout: \$PNPM_HOME/bin/ only)."
                fi
            fi
        fi
    fi

    # --- pnpm config (macOS native path bridge) ---
    # pnpm 11 reads global config from ~/Library/Preferences/pnpm/ on macOS
    # (when XDG_CONFIG_HOME is unset). The repo stows config.yaml to
    # ~/.config/pnpm/ — Linux-native. Bridge the macOS path to the stowed
    # file so a single source of truth applies on both platforms.
    # Source: pnpm.mjs getConfigDir().
    local mac_pref_dir="$HOME/Library/Preferences/pnpm"
    local mac_yaml="$mac_pref_dir/config.yaml"
    local stow_yaml="$HOME/.config/pnpm/config.yaml"
    if [[ -f "$stow_yaml" ]]; then
        mkdir -p "$mac_pref_dir"
        if [[ -L "$mac_yaml" ]]; then
            local existing_target
            existing_target=$(readlink "$mac_yaml")
            if [[ "$existing_target" != "$stow_yaml" ]]; then
                run_cmd ln -sfn "$stow_yaml" "$mac_yaml"
            fi
        elif [[ -f "$mac_yaml" ]]; then
            run_cmd mv "$mac_yaml" "${mac_yaml}.pre-stow.$(date +%Y%m%d-%H%M%S).bak"
            run_cmd ln -sfn "$stow_yaml" "$mac_yaml"
        else
            run_cmd ln -sfn "$stow_yaml" "$mac_yaml"
        fi
    fi
    # NOTE: ~/Library/Preferences/pnpm/rc (kebab-INI) is a separate file pnpm
    # writes for auth/registry/approve-builds defaults. Leave it alone.

    # --- Oh My Zsh ---
    if [[ "$SKIP_OMZ" == true ]]; then
        verbose "Oh My Zsh skipped (--skip-omz)"
    elif [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            # CHSH=no: the installer otherwise runs chsh when $SHELL is not zsh, and chsh
            # asks for a password -- a read no flag of ours can answer. Changing the
            # login shell is root's (or the user's own) step, not this installer's.
            run_cmd env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        fi
    fi
}

install_linux_prerequisites() {
    local pkg_mgr=""
    if command -v apt &>/dev/null; then pkg_mgr="apt";
    elif command -v dnf &>/dev/null; then pkg_mgr="dnf";
    elif command -v pacman &>/dev/null; then pkg_mgr="pacman";
    elif command -v zypper &>/dev/null; then pkg_mgr="zypper";
    fi

    if [[ -z "$pkg_mgr" ]]; then
        warn "Could not detect package manager. Install dependencies manually."
    elif [[ "$SKIP_SYSTEM_PACKAGES" == true ]]; then
        info "Package-manager installs skipped (--skip-system-packages): $pkg_mgr is not run. Anything still missing above is for root to add."
    else
        info "Detected package manager: $pkg_mgr"

        # --- Core tools ---
        # glow is NOT on the apt line: it is not an Ubuntu 24.04 package, and apt
        # fails the WHOLE command on one unknown name, so every core tool on this
        # line went uninstalled on plain Ubuntu (found on the codebox build,
        # 2026-10-10). Linux gets glow from its GitHub release instead, below.
        if confirm "Install core tools (stow, jq, fzf, direnv, eza, zoxide, tmux, ripgrep, fd, gh, git-lfs, trash-cli, neovim, glow, aria2, ffmpeg)?" n y; then
            case "$pkg_mgr" in
                apt)
                    run_cmd sudo apt update
                    run_cmd sudo apt install -y stow jq fzf direnv zoxide tmux ripgrep fd-find git-lfs trash-cli neovim unzip aria2 ffmpeg
                    # (fd-find installs as fdfind; the ~/.local/bin/fd link is made below,
                    # outside this branch, so it also happens when root did the apt step.)
                    # eza and gh need special repos on Ubuntu/Debian
                    if ! command -v eza &>/dev/null; then
                        info "eza requires a separate install on Debian/Ubuntu."
                        info "See: https://github.com/eza-community/eza#installation"
                    fi
                    if ! command -v gh &>/dev/null; then
                        if [[ "$NO_SUDO" == true ]]; then
                            warn "gh not installed: adding GitHub's apt repo needs root (--no-sudo). Ask root for: apt install gh (after adding https://cli.github.com/packages)."
                        else
                            info "Installing GitHub CLI via official repo..."
                            run_cmd sudo mkdir -p -m 755 /etc/apt/keyrings
                            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
                            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                            run_cmd sudo apt update && run_cmd sudo apt install -y gh
                        fi
                    fi
                    ;;
                dnf)    run_cmd sudo dnf install -y stow jq fzf direnv eza zoxide tmux ripgrep fd-find gh git-lfs trash-cli glow neovim aria2 ffmpeg ;;
                pacman) run_cmd sudo pacman -S --noconfirm stow jq fzf direnv zoxide tmux ripgrep fd github-cli git-lfs trash-cli glow neovim aria2 ffmpeg ;;
                zypper) run_cmd sudo zypper install -y stow jq fzf direnv zoxide tmux ripgrep fd git-lfs trash-cli glow neovim aria2 ffmpeg ;;
            esac
        fi
    fi

    # --- fd: Debian/Ubuntu ship it as fdfind. Linked here, outside the apt branch, so a
    # root-installed fd-find gets its `fd` name under --skip-system-packages too. ---
    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
        run_cmd mkdir -p "$HOME/.local/bin"
        run_cmd ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        info "Symlinked fdfind → ~/.local/bin/fd"
    fi

    # --- glow (Linux: GitHub release to ~/.local/bin; no distro package on Ubuntu).
    # User-level, so it is NOT gated on --skip-system-packages, like lazygit. ---
    if ! command -v glow &>/dev/null; then
        if confirm "Install glow (markdown viewer) from its GitHub release to ~/.local/bin?" y y; then
            install_glow_release || warn "glow not installed — see https://github.com/charmbracelet/glow#installation"
        fi
    fi

    # --- lazygit (required — latest GitHub release, to ~/.local/bin, no sudo) ---
    # ~/.local/bin rather than /usr/local/bin: a user without sudo (the codebox
    # profile) can still have it, and ~/.local/bin is first on PATH in every shell
    # these dotfiles set up. A lazygit already at /usr/local/bin is left alone.
    if command -v lazygit &>/dev/null; then
        success "lazygit already installed"
    else
        info "Installing lazygit from GitHub release..."
        local lg_arch=""
        case "$(uname -m)" in
            x86_64)  lg_arch="x86_64" ;;
            aarch64) lg_arch="arm64"  ;;
        esac
        if [[ -z "$lg_arch" ]]; then
            warn "Unsupported arch — see https://github.com/jesseduffield/lazygit#installation"
        else
            local lg_ver lg_tmp
            lg_ver=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" 2>/dev/null \
                | grep -Po '"tag_name": "v\K[^"]*' || true)
            if [[ -z "$lg_ver" ]]; then
                warn "Could not detect lazygit latest version — see https://github.com/jesseduffield/lazygit#installation"
            else
                lg_tmp=$(mktemp -d)
                if run_cmd curl -fsSL -o "$lg_tmp/lazygit.tar.gz" \
                    "https://github.com/jesseduffield/lazygit/releases/download/v${lg_ver}/lazygit_${lg_ver}_Linux_${lg_arch}.tar.gz"; then
                    run_cmd tar -xf "$lg_tmp/lazygit.tar.gz" -C "$lg_tmp" lazygit
                    run_cmd mkdir -p "$HOME/.local/bin"
                    run_cmd install -m 755 "$lg_tmp/lazygit" "$HOME/.local/bin/lazygit"
                    success "lazygit ${lg_ver} installed to ~/.local/bin"
                else
                    warn "lazygit release download failed — see https://github.com/jesseduffield/lazygit#installation"
                fi
                rm -rf "$lg_tmp"
            fi
        fi
    fi

    # --- lazydocker (required unless --skip-docker — official script → ~/.local/bin) ---
    if [[ "$SKIP_DOCKER" == true ]]; then
        verbose "lazydocker skipped (--skip-docker)"
    elif command -v lazydocker &>/dev/null; then
        success "lazydocker already installed"
    else
        info "Installing lazydocker via official install script..."
        run_cmd bash -c 'curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | DIR="$HOME/.local/bin" bash'
    fi

    if [[ -n "$pkg_mgr" && "$SKIP_SYSTEM_PACKAGES" != true ]]; then
        # --- Optional CLI tools ---
        if confirm "Install optional CLI tools (tree, fastfetch, yazi)?"; then
            # Non-fatal: a missing/renamed optional package must not abort the install.
            case "$pkg_mgr" in
                apt)    run_cmd sudo apt install -y tree fastfetch || warn "Some optional tools not installed (skipped)."
                        info "yazi may need manual install on Debian/Ubuntu."
                        info "  yazi:   installer offers a GitHub release download below; or see https://github.com/sxyazi/yazi#installation"
                        ;;
                dnf)    run_cmd sudo dnf install -y tree fastfetch yazi || warn "Some optional tools not installed (skipped)." ;;
                pacman) run_cmd sudo pacman -S --noconfirm tree fastfetch yazi || warn "Some optional tools not installed (skipped)." ;;
                zypper) run_cmd sudo zypper install -y tree fastfetch || warn "Some optional tools not installed (skipped)." ;;
            esac
        fi
    fi

    # --- uv ---
    # INSTALLER_NO_MODIFY_PATH: uv's installer otherwise appends a PATH line to the
    # shell rc files it finds. ~/.zshrc is a stow link into this repo once stow has
    # run, and the stowed .zshrc already puts ~/.local/bin first, so an appended
    # line would be repo pollution with nothing to show for it.
    if [[ "$SKIP_UV" == true ]]; then
        verbose "uv skipped (--skip-uv)"
    elif ! command -v uv &>/dev/null; then
        if confirm "uv not found. Install it?" n y; then
            run_cmd bash -c 'curl -LsSf https://astral.sh/uv/install.sh | INSTALLER_NO_MODIFY_PATH=1 sh'
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    # --- pnpm (standalone) ---
    if [[ "$SKIP_PNPM" == true ]]; then
        verbose "pnpm skipped (--skip-pnpm)"
    elif _pnpm_needs_install_or_upgrade; then
        local cur_pnpm="" prompt=""
        command -v pnpm &>/dev/null && cur_pnpm=$(pnpm -v 2>/dev/null || echo "unknown")
        if _pnpm_is_standalone; then
            # Below-floor is enforced (not optional) by _preflight_pnpm_floor_check,
            # which always runs earlier in main() and exits if it can't fix it -- so
            # this branch's confirm below only still fires under --skip-preflight.
            # Applies on every OS (Linux/WSL included) -- same shared function.
            prompt="pnpm ${cur_pnpm} is below required ${PNPM_MIN_VERSION}. Run 'pnpm self-update' now?"
        elif [[ -n "$cur_pnpm" ]]; then
            prompt="Active pnpm ${cur_pnpm} is not the standalone install (corepack/npm-global). Install standalone pnpm now?"
        else
            prompt="pnpm not found. Install it (standalone)?"
        fi
        if confirm "$prompt" n y; then
            # self-update only works on a real standalone; for a corepack shim or
            # npm-global pnpm it can't create $PNPM_HOME/bin — curl-install instead.
            if _pnpm_is_standalone; then
                run_cmd pnpm self-update
            else
                run_cmd bash -c 'curl -fsSL https://get.pnpm.io/install.sh | sh -'
            fi
            export PNPM_HOME="$HOME/.local/share/pnpm"
            export PATH="$PNPM_HOME/bin:$PATH"
            # Regenerate zsh completion so .zshrc's `source "$PNPM_HOME/_pnpm"`
            # picks up the just-installed pnpm version. Sourced at .zshrc:255.
            if command -v pnpm &>/dev/null; then
                pnpm completion zsh > "$PNPM_HOME/_pnpm" 2>/dev/null || true
            fi
            # pnpm self-update always regenerates shims at BOTH root and bin/.
            # Root shims trigger "Detected a pnpm v10 installation layout"
            # warnings. Remove them — only $PNPM_HOME/bin is on PATH.
            if [[ -f "$PNPM_HOME/pnpm" ]]; then
                local shim
                for shim in pnpm pnpx pn pnx; do
                    [[ -f "$PNPM_HOME/$shim" ]] && "$SAFE_RM" "$PNPM_HOME/$shim"
                done
                info "Root-level shims removed (v11 layout: \$PNPM_HOME/bin/ only)."
            fi
        fi
    fi

    # --- Rust toolchain (rustup) — optional ---
    if [[ "$SKIP_RUST" == true ]]; then
        verbose "rustup skipped (--skip-rust)"
    elif ! command -v rustup &>/dev/null; then
        if SECTION_DECISION=ask confirm "Install Rust toolchain (rustup)? Needed for cargo-binstall and other rust CLI tools."; then
            install_rust_toolchain
        fi
    fi

    # --- yazi (terminal file manager) via GitHub release zip ---
    if [[ "$SKIP_YAZI" == true ]]; then
        verbose "yazi skipped (--skip-yazi)"
    elif ! command -v yazi &>/dev/null; then
        if confirm "Install yazi (terminal file manager) from GitHub release?"; then
            install_yazi_release
        fi
    fi

    # --- herdr (agent multiplexer) via PINNED + hash-verified GitHub release ---
    # Not gated behind `command -v herdr` like yazi above: the function itself
    # compares the installed version against HERDR_VERSION, so re-running
    # install.sh after a deliberate version bump actually deploys the bump.
    if [[ "$SKIP_HERDR" == true ]]; then
        verbose "herdr skipped (--skip-herdr)"
    else
        install_herdr_release || warn "herdr not installed — see docs/HERDR.md"
    fi

    # --- Oh My Zsh ---
    if [[ "$SKIP_OMZ" == true ]]; then
        verbose "Oh My Zsh skipped (--skip-omz)"
    elif [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            # CHSH=no: the installer otherwise runs chsh when $SHELL is not zsh, and chsh
            # asks for a password -- a read no flag of ours can answer. Changing the
            # login shell is root's (or the user's own) step, not this installer's.
            run_cmd env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        fi
    fi
}

# Install glow from its latest GitHub release into ~/.local/bin. Linux only; macOS
# has the Homebrew formula. Same shape as install_yazi_release: resolve the tag
# through the /releases/latest redirect, download, unpack, move one binary.
install_glow_release() {
    if command -v glow &>/dev/null; then
        success "glow already installed ($(glow --version 2>/dev/null | head -1))"
        return 0
    fi
    local arch
    case "$(uname -m)" in
        x86_64)         arch="x86_64" ;;
        aarch64|arm64)  arch="arm64" ;;
        *) warn "Unsupported architecture for glow release: $(uname -m)"; return 1 ;;
    esac
    local latest_url tag ver
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/charmbracelet/glow/releases/latest" 2>/dev/null || true)
    tag="${latest_url##*/}"
    if [[ -z "$tag" || "$tag" == "latest" ]]; then
        warn "Could not resolve latest glow release tag from GitHub"
        return 1
    fi
    ver="${tag#v}"
    local asset="glow_${ver}_Linux_${arch}.tar.gz"
    local url="https://github.com/charmbracelet/glow/releases/download/${tag}/${asset}"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    info "Downloading $asset..."
    if ! run_cmd curl -fL --proto '=https' --tlsv1.2 -o "$tmp_dir/$asset" "$url"; then
        warn "glow download failed from $url"
        rm -rf "$tmp_dir"
        return 1
    fi
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would unpack $asset and install glow to ~/.local/bin"
        rm -rf "$tmp_dir"
        return 0
    fi
    run_cmd tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
    local bin
    bin=$(find "$tmp_dir" -type f -name glow -perm -u+x 2>/dev/null | head -1)
    if [[ -z "$bin" ]]; then
        warn "glow binary not found inside $asset"
        rm -rf "$tmp_dir"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    run_cmd install -m 755 "$bin" "$HOME/.local/bin/glow"
    rm -rf "$tmp_dir"
    if command -v glow &>/dev/null; then
        success "glow installed: $(glow --version 2>/dev/null | head -1)"
    else
        warn "glow installed to ~/.local/bin but not on PATH — ensure ~/.local/bin is on PATH"
    fi
}

# ==============================================================================
# OMZ Plugins & Themes (always runs during main flow)
# ==============================================================================

install_omz_plugins() {
    local omz_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if [[ ! -d "$omz_custom" ]]; then
        warn "Oh My Zsh custom directory not found. Skipping plugins."
        return
    fi

    step "Oh My Zsh Plugins & Theme"

    # One section-level decision: if anything is missing, ask once; the per-item
    # confirms below are then auto-answered as a group.
    local _omz_missing=false
    [[ ! -d "$omz_custom/plugins/zsh-autosuggestions" ]] && _omz_missing=true
    [[ ! -d "$omz_custom/plugins/zsh-syntax-highlighting" ]] && _omz_missing=true
    [[ ! -d "$omz_custom/plugins/zsh-completions" ]] && _omz_missing=true
    [[ ! -d "$omz_custom/themes/powerlevel10k" ]] && _omz_missing=true
    if [[ "$_omz_missing" == true ]]; then
        if confirm "Install missing Oh My Zsh plugins + Powerlevel10k theme?" "y"; then
            SECTION_DECISION=yes
        else
            SECTION_DECISION=no
        fi
    fi

    local any_missing=false

    # --- Plugins ---
    local -a plugin_names=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
    local -a plugin_urls=(
        "https://github.com/zsh-users/zsh-autosuggestions"
        "https://github.com/zsh-users/zsh-syntax-highlighting"
        "https://github.com/zsh-users/zsh-completions"
    )

    local i
    for i in "${!plugin_names[@]}"; do
        local plugin="${plugin_names[$i]}"
        local url="${plugin_urls[$i]}"
        if [[ ! -d "$omz_custom/plugins/$plugin" ]]; then
            any_missing=true
            if confirm "Install OMZ plugin: $plugin?"; then
                run_cmd git clone "$url" "$omz_custom/plugins/$plugin"
                success "$plugin installed"
            fi
        else
            echo -e "  ${GREEN}✓${RESET} $plugin already installed"
        fi
    done

    # --- Powerlevel10k ---
    if [[ ! -d "$omz_custom/themes/powerlevel10k" ]]; then
        any_missing=true
        if confirm "Install Powerlevel10k theme?"; then
            run_cmd git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$omz_custom/themes/powerlevel10k"
            success "Powerlevel10k installed"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Powerlevel10k already installed"
    fi

    if [[ "$any_missing" == false ]]; then
        success "All plugins and themes already installed"
    fi
    SECTION_DECISION=ask
}

# ==============================================================================
# Installation: Stow
# ==============================================================================

_is_stow_managed() {
    # Walk up parent directories of a target path. If any ancestor is a
    # symlink pointing into the dotfiles repo, the file is already managed
    # by stow via tree-folding — not a real conflict.
    #
    # Note: the loop starts from the file's parent and walks up through
    # $HOME (inclusive). Without checking $HOME itself, files placed
    # directly in $HOME (e.g. ~/.foo) are never evaluated, which was a
    # dead zone in the original while [[ dir != HOME ]] condition.
    local path="$1"
    local dir
    dir="$(dirname "$path")"
    while [[ "$dir" != "/" ]]; do
        if [[ -L "$dir" ]]; then
            local link_target
            link_target=$(readlink "$dir")
            if [[ "$link_target" == *"fifty-shades-of-dotfiles"* ]]; then
                return 0
            fi
        fi
        [[ "$dir" == "$HOME" ]] && break
        dir="$(dirname "$dir")"
    done
    return 1
}

# Remove EVERY ~ symlink that points into any copy of this repo. Only uninstall
# uses it now, where removing them all is the point. Restowing must NOT: this
# ran before every stow, so stow's first conflict left ~ with no links at all
# (all 171 gone on 2026-10-05, W-20261005-A48); _restow_home lets stow name the
# links it does not own instead.
_clean_stale_repo_links() {
    local home_dir="$REPO_DIR/home"
    local cleaned=0

    while IFS= read -r -d '' dir; do
        local relative="${dir#$home_dir/}"
        local target="$HOME/$relative"
        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" == *"fifty-shades-of-dotfiles"* ]]; then
                verbose "Removing stale link: ~/$relative/ → $link_target"
                run_cmd "$SAFE_RM" "$target"
                cleaned=$((cleaned+1))
            fi
        fi
    done < <(find "$home_dir" -mindepth 1 -type d -print0)

    while IFS= read -r -d '' file; do
        local relative="${file#$home_dir/}"
        local target="$HOME/$relative"
        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" == *"fifty-shades-of-dotfiles"* ]]; then
                verbose "Removing stale link: ~/$relative → $link_target"
                run_cmd "$SAFE_RM" "$target"
                cleaned=$((cleaned+1))
            fi
        fi
    done < <(find "$home_dir" -type f ! -name '.DS_Store' -print0)

    if (( cleaned > 0 )); then
        info "Removed $cleaned stale symlink(s) from previous install"
    fi
}

# Read-only. Name every path under ~ that stow could not take over: a real file
# where the repo's link belongs (unless it sits inside a folded repo directory),
# or a link to somewhere outside this repo. Returns 1 if there is any.
_stow_preflight() {
    local home_dir="$REPO_DIR/home"
    local file relative target n=0
    while IFS= read -r -d '' file; do
        relative="${file#$home_dir/}"
        _conflict_check_ignored "$relative" && continue
        target="$HOME/$relative"
        if [[ -L "$target" ]]; then
            [[ "$(readlink "$target")" == *"fifty-shades-of-dotfiles"* ]] && continue
            warn "Conflict: ~/$relative is a link to somewhere else: $(readlink "$target")"
        elif [[ -e "$target" ]]; then
            _is_stow_managed "$target" && continue
            warn "Conflict: ~/$relative is a real file where the repo's link belongs"
        else
            continue
        fi
        n=$((n+1))
    done < <(find "$home_dir" -type f ! -name '.DS_Store' -print0)
    (( n == 0 )) && return 0
    error "$n conflict(s). Nothing was removed or linked."
    echo -e "  Move them aside (or adopt them with ${CYAN}./install.sh --force${RESET}), then re-run." >&2
    return 1
}

# Restow home/ into ~ without ever leaving ~ half-linked (W-20261005-A48).
# 1. Name every real conflict and stop, with nothing touched.
# 2. Ask stow itself with `stow -n` (read-only, so it runs under --dry-run too).
# 3. If stow's only objection is "existing target is not owned by stow" for links
#    into some copy of this repo (a moved clone, an absolute link, a folded dir:
#    the reason the old pre-clean existed, 9c3d485), remove exactly those links
#    and ask stow again. Stow decides what it owns; a path comparison here could
#    not (a folded dir link that resolves correctly is still "not owned").
# 4. Any other objection stops with nothing removed. Only then stow.
# With --adopt (./install.sh --force) step 1 is skipped, because adopting the
# real files is the point, and stow runs with --adopt instead of -R.
# Run from $REPO_DIR.
_restow_home() {
    # Tell dotlinks-watch a deploy is under way (it holds its alarm while this pid
    # lives: the restow removes links on purpose for a moment), and say "done" on
    # every way out, so the rest of a long install is watched again.
    local lstate="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links" rc
    if [[ "$DRY_RUN" != true ]] && mkdir -p "$lstate" 2>/dev/null; then
        printf '%s\n' "$$" > "$lstate/DEPLOYING" 2>/dev/null || true
    fi
    _restow_home_inner "$@"; rc=$?
    # Not under --dry-run: nothing was claimed above, and a dry run must write nothing.
    [[ "$DRY_RUN" != true && -e "$lstate/DEPLOYING" ]] && { printf 'done\n' > "$lstate/DEPLOYING" 2>/dev/null || true; }
    return $rc
}

_restow_home_inner() {
    _refuse_other_checkout || return 1
    local -a stow_args=(-R --no-folding -t "$HOME" home)
    if [[ "${1:-}" == --adopt ]]; then
        stow_args=(--adopt --no-folding -t "$HOME" home)
    else
        _stow_preflight || return 1
    fi
    # Skip flags: the ignores go BEFORE the package name; stow reads options anywhere
    # but a listing reads better with the package last.
    local -a ign=()
    local a
    while IFS= read -r a; do [[ -n "$a" ]] && ign+=("$a"); done < <(_stow_ignore_args)
    if (( ${#ign[@]} > 0 )); then
        stow_args=("${stow_args[@]:0:${#stow_args[@]}-1}" "${ign[@]}" home)
        info "stow skips: $(_stow_skip_names | paste -sd ' ' -)"
    fi
    local -a unowned=()
    local plan line rel other=0
    if ! plan=$(stow -n "${stow_args[@]}" 2>&1); then
        while IFS= read -r line; do
            case "$line" in
                *"existing target is not owned by stow: "*)
                    rel=${line##*existing target is not owned by stow: }
                    if [[ -L "$HOME/$rel" && "$(readlink "$HOME/$rel")" == *"fifty-shades-of-dotfiles"* ]]; then
                        unowned+=("$rel")
                        continue
                    fi
                    ;;
                # Any other listed conflict ("  * cannot stow ...") or error stops us.
                *"* "*|*ERROR*) ;;
                # stow's banner and notes, e.g. "Ignoring an absolute symlink: X"
                *) continue ;;
            esac
            other=$((other+1))
        done <<< "$plan"
        if (( other > 0 || ${#unowned[@]} == 0 )); then
            error "stow's dry run refused, so nothing was removed or linked:"
            printf '%s\n' "$plan" | sed 's/^/    /' >&2
            return 1
        fi
        # Note where each one points first: if stow still refuses, or the real
        # stow fails, they are put back exactly as they were. One of them can be
        # a folded dir that works today (~/.claude/hooks, say), and losing it is
        # the 2026-10-05 outage again in miniature.
        RESTOW_REMOVED=() RESTOW_TARGETS=()
        # Killed part-way (Ctrl-C, SIGTERM): put the removed links back first.
        trap '_restow_put_back; trap - INT TERM; exit 130' INT TERM
        for rel in "${unowned[@]}"; do
            RESTOW_REMOVED+=("$rel")
            RESTOW_TARGETS+=("$(readlink "$HOME/$rel")")
            verbose "Removing stale link: ~/$rel → $(readlink "$HOME/$rel")"
            run_cmd "$SAFE_RM" "$HOME/$rel"
        done
        if [[ "$DRY_RUN" == true ]]; then
            info "Would remove ${#unowned[@]} stale link(s) stow does not own (an older or moved copy of the repo)"
        else
            info "Removed ${#unowned[@]} stale link(s) stow did not own (an older or moved copy of the repo)"
        fi
        if [[ "$DRY_RUN" != true ]] && ! plan=$(stow -n "${stow_args[@]}" 2>&1); then
            error "stow's dry run still refused after removing those stale links; nothing was linked:"
            printf '%s\n' "$plan" | sed 's/^/    /' >&2
            _restow_put_back
            trap - INT TERM
            return 1
        fi
    fi
    [[ "$VERBOSE" == true ]] && stow_args=("${stow_args[0]}" -v "${stow_args[@]:1}")
    if [[ "$DRY_RUN" == true ]]; then
        # Show the plan itself, not just the command: `stow -n` prints NOTHING at
        # default verbosity (CLAUDE.md, "stow -n PRINTS NOTHING"), so a dry run that
        # only echoed the command could not tell an empty plan from a real one. -v2
        # lists every LINK, UNLINK and MKDIR; the counts are summarised first.
        local plan_out
        plan_out=$(stow -n -v2 "${stow_args[@]}" 2>&1) || true
        local n_link n_unlink n_mkdir
        n_link=$(printf '%s\n' "$plan_out" | grep -c '^LINK: ' || true)
        n_unlink=$(printf '%s\n' "$plan_out" | grep -c '^UNLINK: ' || true)
        n_mkdir=$(printf '%s\n' "$plan_out" | grep -c '^MKDIR: ' || true)
        info "[dry-run] stow plan: ${n_link} LINK, ${n_unlink} UNLINK, ${n_mkdir} MKDIR (LINK lines without '(reverts previous action)' are new):"
        printf '%s\n' "$plan_out" | grep -E '^(LINK|UNLINK|MKDIR): ' | sed 's/^/      /'
    fi
    if ! run_cmd stow "${stow_args[@]}"; then
        [[ "$DRY_RUN" != true ]] && _restow_put_back
        trap - INT TERM
        return 1
    fi
    trap - INT TERM
}

# Deploy only from the one checkout ~ already points at. Run from a linked
# worktree or a second clone, stow would re-point every link in ~ into that copy
# -- and when the copy is removed (worktree cleanup, the temp sweep) every link
# dangles (red team, 2026-10-05, measured). A repo that was MOVED is fine: the
# old path no longer exists. A temp-dir copy only warns: into an empty ~ (a
# fresh machine, a test) there is nothing to re-point.
_refuse_other_checkout() {
    local gd cd here other
    gd=$(git -C "$REPO_DIR" rev-parse --absolute-git-dir 2>/dev/null) || gd=""
    cd=$(cd "$REPO_DIR" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || cd=""
    if [[ -n "$gd" && -n "$cd" && "$gd" != "$cd" ]]; then
        error "Refusing to deploy from a linked worktree ($(pretty_path "$REPO_DIR")): ~ would point into a copy that gets removed. Run install.sh from the main checkout."
        return 1
    fi
    here=$(cd "$REPO_DIR" && pwd -P)
    case "$here/" in
        "${TMPDIR:-/nonexistent}"*|/tmp/*|/private/tmp/*|/private/var/folders/*)
            warn "Deploying from a temporary copy ($here): every link in ~ will dangle once it is swept." ;;
    esac
    # Where does ~ point today? Follow ~/.zshrc (always stowed) to its repo.
    if [[ -L "$HOME/.zshrc" ]]; then
        other=$(cd "$(dirname "$HOME/.zshrc")" && cd "$(dirname "$(readlink "$HOME/.zshrc")")" 2>/dev/null && pwd -P) || other=""
        other=${other%/home}
        if [[ -n "$other" && "$other" != "$here" && -d "$other/home" ]]; then
            error "Refusing: ~ is deployed from $other, not from $here. Run install.sh from there, or move one copy away first."
            return 1
        fi
    fi
    return 0
}

# After a good deploy, record every link (~/.local/state/dotfiles/links/current.tsv)
# and keep a REAL-FILE copy of home/.local/bin/dotlinks beside it as `restore`, so
#   sh ~/.local/state/dotfiles/links/restore
# rebuilds ~ from any terminal even when every link is gone -- no hooks, no
# .zshrc, no ~/.local/bin (W-20261005-A48 follow-up; the 5 Oct outage needed
# archaeology instead). ~/.local/state holds nothing stowed, so a failed restow
# cannot take this with it. Never records a broken state: every path stow would
# link (every file under home/, minus what stow ignores) must be a link into
# this repo, or the snapshot is refused and the last good one kept.
# Record, beside the link manifest, what this stow left out and which profile asked
# for it: `stow-skip` (one basename per line) is read by the welcome banner's parity
# line and by deploy-parity-check, so neither reports a skipped tree as a gap;
# `profile` is what a later flag-less run re-applies. Written on every real stow,
# so a run with no skips leaves both empty (an empty file is a positive "nothing
# skipped", never an absent one). `profile` is only rewritten when a profile was
# named (--profile X or --profile none): a run that typed bare skip flags keeps the
# stored profile for next time.
_write_stow_state() {
    local dir="$1"
    _stow_skip_names > "$dir/stow-skip.tmp.$$" && mv -f "$dir/stow-skip.tmp.$$" "$dir/stow-skip" \
        || warn "could not write $(pretty_path "$dir/stow-skip")"
    if [[ -n "$PROFILE" ]]; then
        printf '%s\n' "$PROFILE" > "$dir/profile.tmp.$$" && mv -f "$dir/profile.tmp.$$" "$dir/profile" \
            || warn "could not write $(pretty_path "$dir/profile")"
        [[ "$PROFILE" == none ]] && verbose "stored profile cleared" || verbose "profile ${PROFILE} recorded for later flag-less runs"
    fi
    return 0
}

_snapshot_links() {
    local dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links"
    local rel t lt n=0 good=0 tmp list
    [[ "$DRY_RUN" == true ]] && { info "[dry-run] Would record the link manifest in $(pretty_path "$dir")${PROFILE:+ and the profile (${PROFILE})}"; return 0; }
    mkdir -p "$dir" || { warn "Link manifest NOT written: cannot create $(pretty_path "$dir")"; return 0; }
    _write_stow_state "$dir"
    # Every file stow would link: tracked AND untracked, gitignored ones included
    # (stow reads .stow-local-ignore, not .gitignore -- a gitignored tool in
    # ~/.local/bin is still linked, measured); stow's own ignores are dropped below.
    if ! list=$(git -C "$REPO_DIR" ls-files -co -- home 2>/dev/null); then
        warn "Link manifest NOT written: git could not list home/"
        return 0
    fi
    tmp="$dir/current.tsv.tmp.$$"
    : > "$tmp" || { warn "Link manifest NOT written: $(pretty_path "$dir") is not writable"; return 0; }
    while IFS= read -r rel; do
        rel=${rel#home/}
        [[ -n "$rel" ]] || continue
        _conflict_check_ignored "$rel" && continue
        n=$((n+1))
        t="$HOME/$rel"
        if [[ -L "$t" ]] && lt=$(readlink "$t") && [[ "$lt" == *"fifty-shades-of-dotfiles/home/$rel" ]]; then
            printf '%s\t%s\n' "$rel" "$lt" >> "$tmp"
            good=$((good+1))
        else
            warn "  not a repo link: ~/$rel"
        fi
    done <<< "$list"
    if (( n == 0 || good != n )); then
        mv -f "$tmp" "$dir/rejected.tsv"
        warn "Link manifest NOT updated: $good of $n paths are repo links, so this deploy is not recorded as good (kept the last good one; this attempt is in $(pretty_path "$dir/rejected.tsv"))"
        return 0
    fi
    [[ -f "$dir/current.tsv" ]] && mv -f "$dir/current.tsv" "$dir/previous.tsv"
    mv -f "$tmp" "$dir/current.tsv"
    if cp "$REPO_DIR/home/.local/bin/dotlinks" "$dir/restore.tmp.$$" && chmod 755 "$dir/restore.tmp.$$" \
        && mv -f "$dir/restore.tmp.$$" "$dir/restore"; then
        info "Link manifest: $good of $n paths recorded. If links ever go missing: ${CYAN}sh $(pretty_path "$dir/restore")${RESET}"
    else
        warn "Link manifest written, but the restore script copy failed"
    fi
    _install_links_watch "$dir"
    _zshenv_links_warning
}

# A marked block in the REAL ~/.zshenv (not stowed, so it survives a failed
# restow) that speaks up in a new interactive shell when the links are gone:
# on 2026-10-05 a new terminal just opened without .zshrc, silently, with plain
# `rm` falling through to the permanent /bin/rm. Two -L tests per shell; silent
# when healthy. Added with consent, written by temp + rename, kept if present.
_zshenv_links_warning() {
    local f="$HOME/.zshenv" begin="# >>> fifty-shades links-warning >>>" end="# <<< fifty-shades links-warning <<<"
    local nb ne
    nb=$(grep -cxF "$begin" "$f" 2>/dev/null) || nb=0
    ne=$(grep -cxF "$end" "$f" 2>/dev/null) || ne=0
    if [[ "$nb" == 1 && "$ne" == 1 ]]; then verbose "~/.zshenv links-warning block present"; return 0; fi
    if [[ "$nb" != 0 || "$ne" != 0 ]]; then
        warn "~/.zshenv has a half links-warning block (markers not one each); fix it by hand, then re-run."
        return 0
    fi
    if [[ -L "$f" ]]; then warn "~/.zshenv is a symlink; not adding the links-warning block to it."; return 0; fi
    info "A marked block in ~/.zshenv warns a new terminal when the dotfiles links are gone, and names the one-command restore."
    confirm "Add the links-warning block to ~/.zshenv?" "y" || return 0
    {
        [[ -f "$f" ]] && cat "$f"
        cat <<'BLOCK'
# >>> fifty-shades links-warning >>>
# Added by fifty-shades-of-dotfiles install.sh (outage of 2026-10-05). Silent when the
# links are healthy. Remove the whole block (both marker lines) to opt out.
if [[ -o interactive && -f "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links/current.tsv" ]] \
   && { [[ ! -L "$HOME/.zshrc" ]] || [[ ! -L "$HOME/.local/bin/rm" ]]; }; then
  print -u2 -- "DOTFILES LINKS MISSING: this shell has no dotfiles setup, Claude sessions are blocked, and plain rm is the PERMANENT /bin/rm here."
  print -u2 -- "  Restore (no hooks or dotfiles needed, deletes nothing, safe to run twice): sh ${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links/restore"
fi
# <<< fifty-shades links-warning <<<
BLOCK
    } > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f" && success "links-warning block added to ~/.zshenv" \
        || warn "could not write ~/.zshenv"
}

# Run dotlinks-watch as a launchd agent (macOS), from a REAL-FILE copy beside the
# manifest -- never through the ~/.local/bin link, which the very outage it
# reports would remove. The plist is a real file too. Reloaded only when either
# changed, so a re-run is a no-op.
_install_links_watch() {
    local dir="$1" label="com.captaincodeau.dotlinks-watch" plist tmp changed=0 uid
    [[ "$(check_os)" == "macos" ]] || { verbose "dotlinks-watch: launchd agent is macOS only (skipped)"; return 0; }
    plist="$HOME/Library/LaunchAgents/$label.plist"
    if ! cmp -s "$REPO_DIR/home/.local/bin/dotlinks-watch" "$dir/watch" 2>/dev/null; then
        cp "$REPO_DIR/home/.local/bin/dotlinks-watch" "$dir/watch.tmp.$$" && chmod 755 "$dir/watch.tmp.$$" \
            && mv -f "$dir/watch.tmp.$$" "$dir/watch" || { warn "dotlinks-watch NOT installed: could not copy it to $(pretty_path "$dir")"; return 0; }
        changed=1
    fi
    mkdir -p "$HOME/Library/LaunchAgents" || return 0
    tmp="$plist.tmp.$$"
    cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>-f</string><string>$dir/watch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>$dir/watch.err</string>
</dict>
</plist>
PLIST
    cmp -s "$tmp" "$plist" 2>/dev/null || changed=1
    mv -f "$tmp" "$plist"   # identical bytes when unchanged; never a delete
    uid=$(id -u)
    if (( changed )) || ! launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
        launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
        if launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
            info "dotlinks-watch running (launchd $label): a broken link is reported within seconds"
        else
            warn "dotlinks-watch NOT started: launchctl bootstrap gui/$uid $plist failed (run it by hand to see why)"
        fi
    fi
}

# Recreate the links _restow_home removed (RESTOW_REMOVED / RESTOW_TARGETS),
# each exactly as it pointed before, wherever nothing has taken its place.
RESTOW_REMOVED=() RESTOW_TARGETS=()
_restow_put_back() {
    local i=0 n=0 p
    while (( i < ${#RESTOW_REMOVED[@]} )); do
        p="$HOME/${RESTOW_REMOVED[$i]}"
        if [[ ! -e "$p" && ! -L "$p" ]] && ln -s "${RESTOW_TARGETS[$i]}" "$p"; then
            n=$((n+1))
        fi
        i=$((i+1))
    done
    (( ${#RESTOW_REMOVED[@]} == 0 )) || warn "Put back $n of ${#RESTOW_REMOVED[@]} removed link(s) as they were."
}

# Mirrors home/.stow-local-ignore (the file stow itself reads) and
# deploy-parity-check's SKIP_NAMES/is_ignored(), which already carries the
# same "mirrors .stow-local-ignore, keep in sync" comment. A pattern in one
# without its counterpart here means this function reports a "conflict"
# stow was never actually going to create -- confirmed live 2026-08-19: a
# stale home/.local/bin/__pycache__/*.pyc (Python bytecode the PEP 723
# scripts leave behind when run, gitignored, excluded in
# .stow-local-ignore) was flagged as a real conflict requiring a backup
# decision, even though stow itself would have silently skipped it.
_conflict_check_ignored() {
    local rel="$1"
    # A skip flag's paths are not stowed, so they are not conflicts, not manifest
    # entries and not parity gaps either (see _stow_skip_names).
    _stow_skipped_rel "$rel" && return 0
    case "$rel" in
        *__pycache__*|*.pyc) return 0 ;;
        # .stow-local-ignore's own header: these are stow's built-in default
        # ignores, matched by BASENAME at any depth -- not just top-level.
        # Verified live 2026-08-20: home/.config/herdr/.gitignore (nested)
        # was still being counted as "linked" by stow_home() even though
        # stow itself has always skipped it, because this case only matched
        # the bare top-level name. Same bug class as .DS_Store below, just
        # missed for this group the first time.
        .gitignore|*/.gitignore|.gitmodules|*/.gitmodules) return 0 ;;
        .stow-local-ignore|*/.stow-local-ignore) return 0 ;;
        .DS_Store|*/.DS_Store|._*|*/._*) return 0 ;;
        .Spotlight-V100|*/.Spotlight-V100|.Trashes|*/.Trashes) return 0 ;;
    esac
    return 1
}

# "orig|backup" for every real file check_conflicts moved aside, so a stow that
# then fails can put them back (_restore_conflict_backups).
CONFLICT_MOVED=()
_restore_conflict_backups() {
    local pair orig bak n=0
    (( ${#CONFLICT_MOVED[@]} )) || return 0
    [[ "$DRY_RUN" == true ]] && return 0
    for pair in "${CONFLICT_MOVED[@]}"; do
        orig=${pair%%|*} bak=${pair#*|}
        if [[ ! -e "$orig" && ! -L "$orig" && -e "$bak" ]] && mv "$bak" "$orig"; then
            n=$((n+1))
        fi
    done
    warn "stow failed, so the $n of ${#CONFLICT_MOVED[@]} file(s) backed up for it were moved back into place."
}

check_conflicts() {
    step "Checking for Conflicts"

    local conflicts=0
    local stow_managed=0
    local repo_symlinks=0
    local conflict_files=()
    local home_dir="$REPO_DIR/home"

    while IFS= read -r -d '' file; do
        local relative="${file#$home_dir/}"
        _conflict_check_ignored "$relative" && continue
        local target="$HOME/$relative"

        if [[ -e "$target" && ! -L "$target" ]]; then
            if _is_stow_managed "$target"; then
                echo -e "  ${DIM}✓ ~/$relative (stow-managed)${RESET}"
                stow_managed=$((stow_managed+1))
            else
                warn "Conflict: ~/$relative already exists (not a symlink)"
                conflict_files+=("$target")
                conflicts=$((conflicts+1))
            fi
        elif [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" != *"fifty-shades-of-dotfiles"* ]]; then
                warn "Conflict: ~/$relative is a symlink to something else: $link_target"
                conflict_files+=("$target")
                conflicts=$((conflicts+1))
            else
                repo_symlinks=$((repo_symlinks+1))
                verbose "~/$relative → $link_target (existing stow symlink)"
            fi
        fi
    done < <(find "$home_dir" -type f ! -name '.DS_Store' -print0)

    if (( stow_managed > 0 )); then
        echo
        echo -e "  ${DIM}$stow_managed file(s) inside stow-managed directories${RESET}"
    fi

    if (( repo_symlinks > 0 )); then
        echo
        info "$repo_symlinks file(s) already symlinked to repo (re-install detected — will restow)"
    fi

    if (( conflicts > 0 )); then
        echo
        warn "$conflicts conflict(s) found"
        echo
        echo -e "  Options:"
        echo -e "    1. ${CYAN}Auto-backup${RESET}: Move conflicting files to ~/dotfiles-backup/"
        echo -e "    2. ${CYAN}Force adopt${RESET}: Run ${CYAN}./install.sh --force${RESET} (stow --adopt, then git diff to review)"
        echo -e "    3. ${CYAN}Manual${RESET}: Delete or move conflicting files yourself"
        echo

        if confirm "Back up these ${conflicts} conflicting file(s) to ~/dotfiles-backup/ and continue?" "y"; then
            local backup_dir="$HOME/dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
            run_cmd mkdir -p "$backup_dir"
            for f in "${conflict_files[@]}"; do
                local rel="${f#$HOME/}"
                run_cmd mkdir -p "$backup_dir/$(dirname "$rel")"
                run_cmd mv "$f" "$backup_dir/$rel"
                CONFLICT_MOVED+=("$f|$backup_dir/$rel")
                info "Backed up: ~/$rel → $(pretty_path "$backup_dir")/$rel"
            done
            success "Conflicts backed up to $(pretty_path "$backup_dir")"
            return 0
        fi

        return 1
    else
        success "No conflicts found"
        return 0
    fi
}

stow_home() {
    step "Stowing home/ → ~/"

    cd "$REPO_DIR"

    # NOTE for anyone running stow by hand under a restricted sandbox (e.g. a Claude
    # Code session): reads under `home/.ssh` may be denied, and stow ABORTS there while
    # walking the tree. A simulated run (`stow -n -R -v --no-folding -t ~ home`) then
    # prints an unlink phase with no matching link phase -- observed as 59 UNLINK / 0
    # LINK -- which reads as "tear down every stowed file and restore none". Unsandboxed
    # the same command returns a symmetric 70 UNLINK / 71 LINK. Verify a dry run
    # SUCCEEDED before trusting it; a truncated plan looks like a plan. See CLAUDE.md.
    if _restow_home; then
        success "home/ stowed successfully"
        _snapshot_links
    else
        # Not "stow did not run": a stow that passed its dry run can still fail
        # part-way, so say how to find out rather than guess.
        error "stow did not complete."
        echo -e "  ${CYAN}What is linked now?${RESET}  ${CYAN}sh ~/.local/state/dotfiles/links/restore check${RESET}" >&2
        echo -e "  ${CYAN}Put the last good links back:${RESET}  ${CYAN}sh ~/.local/state/dotfiles/links/restore${RESET} (moves blocking files aside, deletes nothing)" >&2
        echo -e "  ${CYAN}Details:${RESET}  ./install.sh --verbose --stow-only" >&2
        return 1
    fi

    local count=0
    while IFS= read -r -d '' file; do
        local relative="${file#$REPO_DIR/home/}"
        _conflict_check_ignored "$relative" && continue
        count=$((count+1))
    done < <(find "$REPO_DIR/home" -type f ! -name '.DS_Store' -print0)
    info "Linked $count file(s) from home/ to ~/"
}

stow_platform() {
    local os
    os=$(check_os)

    if [[ "$os" != "macos" ]]; then
        info "Platform-specific files only available for macOS. Skipping."
        return 0
    fi

    step "Platform: macOS Application Support"

    local platform_dir="$REPO_DIR/platforms/macos/Library/Application Support"

    if [[ ! -d "$platform_dir" ]]; then
        info "No macOS platform files found. Skipping."
        return 0
    fi

    # --- Cursor ---
    local cursor_app_dir="$HOME/Library/Application Support/Cursor"
    if [[ -d "$cursor_app_dir" ]]; then
        local cursor_src="$platform_dir/Cursor/User/settings.json"
        local cursor_dst="$cursor_app_dir/User/settings.json"
        if [[ -f "$cursor_src" ]]; then
            if [[ -f "$cursor_dst" && ! -L "$cursor_dst" ]]; then
                if _settings_same_ignoring_colors "$cursor_src" "$cursor_dst"; then
                    echo -e "  ${GREEN}✓${RESET} Cursor settings.json unchanged (only machine colors differ) — skipping"
                else
                    # Genuine change vs repo — back it up before overwriting.
                    # direnvrc will re-inject machine colors on next shell open.
                    local cursor_bak="${cursor_dst}.bak.$(date +%Y%m%d_%H%M%S)"
                    run_cmd cp "$cursor_dst" "$cursor_bak"
                    info "Cursor settings.json backed up → $(basename "$cursor_bak")"
                    run_cmd cp "$cursor_src" "$cursor_dst"
                    success "Cursor settings.json updated from repo"
                fi
            elif [[ -L "$cursor_dst" ]]; then
                echo -e "  ${GREEN}✓${RESET} Cursor settings.json is a symlink — leaving as-is"
            else
                info "Cursor settings.json not found — copying from repo"
                run_cmd mkdir -p "$(dirname "$cursor_dst")"
                run_cmd cp "$cursor_src" "$cursor_dst"
                success "Cursor settings.json created from repo"
            fi
        fi
    else
        info "Cursor not installed. Skipping."
    fi

    # --- VSCode ---
    local code_app_dir="$HOME/Library/Application Support/Code"
    if [[ -d "$code_app_dir" ]]; then
        local code_src="$platform_dir/Code/User/settings.json"
        local code_dst="$code_app_dir/User/settings.json"
        if [[ -f "$code_src" ]]; then
            if [[ -f "$code_dst" && ! -L "$code_dst" ]]; then
                if _settings_same_ignoring_colors "$code_src" "$code_dst"; then
                    echo -e "  ${GREEN}✓${RESET} VSCode settings.json unchanged (only machine colors differ) — skipping"
                else
                    # Genuine change vs repo — back it up before overwriting.
                    # direnvrc will re-inject machine colors on next shell open.
                    local code_bak="${code_dst}.bak.$(date +%Y%m%d_%H%M%S)"
                    run_cmd cp "$code_dst" "$code_bak"
                    info "VSCode settings.json backed up → $(basename "$code_bak")"
                    run_cmd cp "$code_src" "$code_dst"
                    success "VSCode settings.json updated from repo"
                fi
            elif [[ -L "$code_dst" ]]; then
                echo -e "  ${GREEN}✓${RESET} VSCode settings.json is a symlink — leaving as-is"
            else
                info "VSCode settings.json not found — copying from repo"
                run_cmd mkdir -p "$(dirname "$code_dst")"
                run_cmd cp "$code_src" "$code_dst"
                success "VSCode settings.json created from repo"
            fi
        fi
    else
        info "VSCode not installed. Skipping."
    fi

    _iterm_profiles_sync apply

    # --- iTerm2 full preferences restore (profiles, key bindings, pointer/
    # ctrl-click bindings, Hotkey Window, general prefs) -----------------------
    # Deliberately NOT unconditional like _iterm_profiles_sync above: this
    # REPLACES the live com.googlecode.iterm2 defaults domain wholesale, so it
    # must stay an explicit, default-NO offer, never a silent "make it so"
    # step -- a machine's settings may have been customized further since the
    # repo snapshot, and importing would clobber that with no warning otherwise.
    local iterm_prefs_restorer="$REPO_DIR/settings/iterm2/prefs/restore.sh"
    local iterm_prefs_plist="$REPO_DIR/settings/iterm2/prefs/com.googlecode.iterm2.plist"
    if [[ -x "$iterm_prefs_restorer" && -f "$iterm_prefs_plist" && -d "$HOME/Library/Application Support/iTerm2" ]]; then
        echo
        if pgrep -x iTerm2 >/dev/null 2>&1; then
            info "iTerm2 is running — quit it first, then run ${CYAN}${iterm_prefs_restorer}${RESET} to restore full preferences (profiles, key bindings, pointer bindings, Hotkey Window)."
        elif confirm "Restore full iTerm2 preferences from the repo? This REPLACES current settings (backed up first)."; then
            run_cmd "$iterm_prefs_restorer" --yes
        fi
    fi
}

# ------------------------------------------------------------------------------
# speak-clipboard backend check (macOS only)
# ------------------------------------------------------------------------------
# The herdr speak-clipboard key shells out to `say2` directly, one process per
# press (see home/.local/bin/speak-clipboard's own header for why, and for the
# 2026-09-10 measurements that retired the old compiled Swift renderer this
# function used to prebuild -- say2 already streams playback internally, so
# there is no longer anything to compile ahead of time).
#
# Two things can be missing on a fresh Mac, independently: say2 itself (not a
# Homebrew dependency of this repo, install separately), and the premium Siri
# "natural" tier voice it needs (Aaron/Voice 1 or Simone/Voice 2 in Apple's own
# picker -- System Settings > Accessibility > Spoken Content > System Voice).
# speak-clipboard itself already falls back to the built-in `say` voice at
# runtime if neither is available (see its own header), so this check is
# purely informational: it tells the installer which case it's in, and gives
# the exact command to fix the voice gap, rather than leaving that to be
# discovered the first time the hotkey sounds wrong.
_check_speak_clipboard_backend() {
    [[ "$(check_os)" == "macos" ]] || return 0
    local sc="$HOME/.local/bin/speak-clipboard"
    [[ -x "$sc" ]] || return 0
    if ! command -v say2 &>/dev/null; then
        info "say2 not found -- herdr speak-clipboard will fall back to the built-in \`say\` voice until it's installed (https://github.com/CaptainCodeAU/say2)."
        return 0
    fi
    if say2 voices --json 2>/dev/null | jq -e '
        .voices[]? | select(.installed==true) |
        select(.assetKey=="en-US:natural:male:Aaron:premium:5030"
            or .assetKey=="en-US:natural:female:Simone:premium:5029")
    ' >/dev/null 2>&1; then
        success "say2 found, premium Siri voice installed (herdr speak-clipboard backend)"
    else
        warn "say2 is installed, but neither premium Siri voice (Aaron/Voice 1 or Simone/Voice 2) is downloaded."
        info "Install one: ${CYAN}say2 voices --install \"en-US:natural:male:Aaron:premium:5030\"${RESET}"
        info "herdr speak-clipboard will use the built-in \`say\` voice until then."
    fi
    return 0
}

# ==============================================================================
# Post-Install
# ==============================================================================

post_install() {
    step "Post-Install"

    local os
    os=$(check_os)

    # No section-level gate here (deliberately -- see commit message). Each item
    # below checks itself and only prompts if it actually has something to do,
    # same shape as dotenvx already had. A fully set-up box asks nothing at all.

    # --- Git identity (stored in ~/.gitconfig.private, included by .gitconfig) ---
    local git_private="$HOME/.gitconfig.private"
    local git_name git_email
    git_name=$(git config user.name 2>/dev/null || true)
    git_email=$(git config user.email 2>/dev/null || true)
    if [[ "$SKIP_GIT_IDENTITY" == true ]]; then
        info "Git identity prompt skipped (--skip-git-identity); ~/.gitconfig.private is yours to write."
    elif [[ -z "$git_name" || -z "$git_email" ]]; then
        if [[ -f "$git_private" ]]; then
            warn "Git identity not fully resolved, but $(pretty_path "$git_private") already exists."
            info "The file may contain includeIf rules, URL rewrites, or multi-account config."
            info "Skipping auto-creation to avoid overwriting. Edit it manually if needed."
        else
            info "Git identity not configured."
            info "Identity is stored in ${CYAN}~/.gitconfig.private${RESET} (not committed to the repo)."
            if confirm "Set up git user.name and user.email now?"; then
                if [[ -z "$git_name" ]]; then
                    read -rp "$(echo -e "${CYAN}  Your name: ${RESET}")" git_name
                fi
                if [[ -z "$git_email" ]]; then
                    read -rp "$(echo -e "${CYAN}  Your email: ${RESET}")" git_email
                fi
                if [[ -n "$git_name" || -n "$git_email" ]]; then
                    run_cmd bash -c "cat > '$git_private' << GITEOF
[user]
	name = ${git_name}
	email = ${git_email}
GITEOF"
                    success "Git identity saved to $(pretty_path "$git_private")"
                fi
            fi
        fi
    else
        success "Git identity: $git_name <$git_email>"
    fi

    # --- git lfs install ---
    if command -v git-lfs &>/dev/null; then
        if ! git lfs env &>/dev/null 2>&1; then
            info "Running one-time git-lfs setup..."
            run_cmd git lfs install
        fi
        success "git-lfs configured"
    fi

    # --- speak-clipboard backend (herdr, macOS only) ---
    _check_speak_clipboard_backend

    # --- gh (SSH-only model) ---
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null 2>&1; then
            success "GitHub CLI authenticated (optional for API operations)"
        else
            info "GitHub CLI (gh) is not authenticated."
            info "This setup uses SSH-only Git auth; ${CYAN}do not run gh auth login${RESET} or ${CYAN}gh auth setup-git${RESET}."
            info "Use SSH keys plus URL rewrites in ${CYAN}~/.gitconfig.private${RESET} (see README)."
            info "For trusted LAN remotes that need agent forwarding, add private Host blocks with ${CYAN}ForwardAgent yes${RESET} to ${CYAN}~/.ssh/config.local${RESET} (loaded via ${CYAN}Include${RESET}). For sealed / untrusted boxes, keep ${CYAN}ForwardAgent no${RESET}."
        fi
    fi

    # --- Python via uv ---
    if [[ "$SKIP_UV" == true ]]; then
        verbose "Python 3.13 via uv skipped (--skip-uv)"
    else
        _ensure_python_313
    fi

    # --- NVM ---
    # Pin the exact, audited tag (v${NVM_MIN_VERSION}); older nvm is affected by
    # CVE-2026-10796 (<= 0.40.4), CVE-2026-15921 (<= 0.40.5) and CVE-2026-94185
    # (<= 0.40.7). The official
    # installer is idempotent — re-running it upgrades an existing nvm in place.
    # PROFILE=/dev/null: nvm's installer otherwise appends its source lines to the
    # rc file of $SHELL. ~/.zshrc is a stow link into this repo by now and already
    # sources nvm.sh, so the append would be repo pollution (and on a box whose
    # login shell is still bash it would edit ~/.bashrc, which nothing here reads).
    if [[ "$SKIP_NVM" == true ]]; then
        verbose "nvm skipped (--skip-nvm)"
    elif [[ ! -d "$HOME/.nvm" ]]; then
        if confirm "nvm not found. Install it (v${NVM_MIN_VERSION}) for Node.js version management?" n y; then
            run_cmd bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_MIN_VERSION}/install.sh | PROFILE=/dev/null bash"
            # Activate in current session so subsequent steps and the user can
            # use nvm immediately without opening a new terminal.
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            success "nvm installed (v${NVM_MIN_VERSION})"
        fi
    elif _nvm_needs_upgrade; then
        local cur_nvm
        cur_nvm=$(_nvm_installed_version)
        warn "nvm ${cur_nvm:-?} is below ${NVM_MIN_VERSION} (CVE-2026-10796 <= 0.40.4, CVE-2026-15921 <= 0.40.5, CVE-2026-94185 <= 0.40.7)."
        if confirm "Upgrade nvm to v${NVM_MIN_VERSION}?" n y; then
            run_cmd bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_MIN_VERSION}/install.sh | PROFILE=/dev/null bash"
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            success "nvm upgraded to v${NVM_MIN_VERSION}"
        fi
    else
        success "nvm installed (v$(_nvm_installed_version))"
    fi

    # --- Node (a default version under nvm) ---
    _ensure_default_node

    # --- Bun ---
    # bun >= BUN_MIN_VERSION is required for the ~/.bunfig.toml minimumReleaseAge
    # cooldown to apply; below it, bun silently ignores the key. `bun upgrade`
    # moves to the latest stable (bun can't pin a version like nvm does).
    if [[ "$SKIP_BUN" == true ]]; then
        verbose "bun skipped (--skip-bun)"
    elif ! command -v bun &>/dev/null; then
        if confirm "bun not found. Install it?" n y; then
            run_cmd bash -c 'curl -fsSL https://bun.sh/install | bash'
            # Activate in current session.
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            success "bun installed ($(bun --version 2>/dev/null || echo '?'))"
        fi
    else
        local cur_bun; cur_bun=$(bun --version 2>/dev/null || echo "?")
        if [[ "$cur_bun" != "?" && "$(_vercmp "$cur_bun" "$BUN_MIN_VERSION")" == "-1" ]]; then
            warn "bun ${cur_bun} is below ${BUN_MIN_VERSION} — the ~/.bunfig.toml release-age cooldown is IGNORED until bun >= ${BUN_MIN_VERSION}."
            if confirm "Run 'bun upgrade' now?"; then
                run_cmd bun upgrade
                success "bun upgraded ($(bun --version 2>/dev/null || echo '?'))"
            fi
        else
            success "bun installed (${cur_bun})"
        fi
    fi

    # --- dotenvx (optional; Claude Code's session-checks.sh hook uses it for
    #     .env encryption checks). It lives on the dotenvx/brew tap, which
    #     Homebrew's tap-trust feature ignores until trusted -- so trust the
    #     single formula (never the whole tap) per the narrow-trust posture.
    #     brew-gated; the SECTION_DECISION=ask override below is now a harmless
    #     no-op (no group survives to override) but stays as defensive belt-
    #     and-suspenders in case that ever changes. ---
    if command -v brew &>/dev/null; then
        if command -v dotenvx &>/dev/null; then
            success "dotenvx already installed"
            run_cmd brew trust --formula dotenvx/brew/dotenvx || true
        elif SECTION_DECISION=ask confirm "Install dotenvx (optional -- .env encryption check for Claude hooks)?"; then
            if run_cmd brew install dotenvx/brew/dotenvx; then
                run_cmd brew trust --formula dotenvx/brew/dotenvx \
                    || warn "dotenvx installed but 'brew trust' failed -- run: brew trust --formula dotenvx/brew/dotenvx"
            fi
        fi
    fi

    # --- TPM (Tmux Plugin Manager) ---
    if [[ "$SKIP_TMUX" == true ]]; then
        verbose "TPM skipped (--skip-tmux)"
    elif command -v tmux &>/dev/null; then
        if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
            if confirm "Install TPM (Tmux Plugin Manager)?" n y; then
                run_cmd git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
                success "TPM installed"
                info "Start tmux and press ${CYAN}prefix + I${RESET} to install plugins."
            fi
        else
            success "TPM already installed"
        fi
    fi

    # --- Nerd Font (Symbols Only) ---
    local has_nerd_font=false
    if [[ "$os" == "macos" ]]; then
        local nerd_font_count
        nerd_font_count=$(find ~/Library/Fonts /Library/Fonts \( -iname "*NerdFont*" -o -iname "*Nerd*Font*" \) 2>/dev/null | wc -l || true)
        if (( nerd_font_count > 0 )); then
            has_nerd_font=true
        fi
    else
        local fc_count
        fc_count=$(fc-list 2>/dev/null | grep -ci "nerd" || true)
        if (( fc_count > 0 )); then
            has_nerd_font=true
        fi
    fi

    if [[ "$SKIP_FONTS" == true ]]; then
        verbose "Nerd Font skipped (--skip-fonts)"
    elif [[ "$has_nerd_font" == false ]]; then
        if confirm "Install Nerd Font (Symbols Only) for Powerlevel10k icons?"; then
            if [[ "$os" == "macos" ]]; then
                run_cmd brew install --cask font-symbols-only-nerd-font
            else
                info "Installing Nerd Font Symbols Only from GitHub releases..."
                run_cmd mkdir -p "$HOME/.local/share/fonts"
                run_cmd bash -c 'curl -fLo /tmp/NerdFontsSymbolsOnly.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip && unzip -o /tmp/NerdFontsSymbolsOnly.zip -d "$HOME/.local/share/fonts/" && rm /tmp/NerdFontsSymbolsOnly.zip'
                if command -v fc-cache &>/dev/null; then
                    run_cmd fc-cache -fv
                fi
            fi
            success "Nerd Font installed"
        fi
    else
        success "Nerd Font already installed"
    fi

    # --- direnv allow for the repo's own .envrc (if present) ---
    if command -v direnv &>/dev/null && [[ -f "$REPO_DIR/.envrc" ]]; then
        info "Allowing direnv for repo .envrc"
        run_cmd direnv allow "$REPO_DIR/.envrc"
    fi

    # --- ~/.zshrc.private ---
    if [[ ! -f "$HOME/.zshrc.private" ]]; then
        info "Consider creating ~/.zshrc.private for API keys and machine-specific settings."
        echo -e "  ${CYAN}touch ~/.zshrc.private${RESET}"
    else
        success "~/.zshrc.private exists"
    fi

    _rc_pollution_check
}

# After nvm is present: install NODE_DEFAULT_VERSION and make it the default when nvm
# holds no Node at all. An existing Node (any version) is never touched here; the
# EOL pre-flight and the onboarding nudge own that conversation. The nvm mirror is
# pinned for the install exactly as home/.zshrc pins it (CVE-2026-10796).
_ensure_default_node() {
    [[ "$SKIP_NVM" == true ]] && return 0
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ ! -s "$nvm_dir/nvm.sh" ]]; then
        # A dry run never installs nvm, so say what the real run does after it.
        [[ "$DRY_RUN" == true ]] && info "[dry-run] nvm not present yet; a real run installs Node ${NODE_DEFAULT_VERSION} and sets it as default right after nvm (no-questions answer: yes)"
        return 0
    fi
    local have=""
    have=$( export NVM_DIR="$nvm_dir"; \. "$nvm_dir/nvm.sh" --no-use >/dev/null 2>&1; nvm version default 2>/dev/null ) || have=""
    if [[ -n "$have" && "$have" != "N/A" ]]; then
        success "Node default under nvm: ${have}"
        return 0
    fi
    local installed=""
    installed=$(ls "$nvm_dir/versions/node" 2>/dev/null | paste -sd ' ' - || true)
    if [[ -n "$installed" ]]; then
        warn "nvm has Node (${installed}) but no default alias; set one: nvm alias default <version>"
        return 0
    fi
    if confirm "nvm has no Node yet. Install Node ${NODE_DEFAULT_VERSION} and make it the default?" y y; then
        if run_cmd bash -c "export NVM_DIR=\"$nvm_dir\" NVM_NODEJS_ORG_MIRROR=https://nodejs.org/dist; . \"\$NVM_DIR/nvm.sh\" --no-use >/dev/null && nvm install ${NODE_DEFAULT_VERSION} && nvm alias default ${NODE_DEFAULT_VERSION}"; then
            success "Node ${NODE_DEFAULT_VERSION} installed and set as nvm's default"
        else
            warn "Node ${NODE_DEFAULT_VERSION} install failed; later: nvm install ${NODE_DEFAULT_VERSION} && nvm alias default ${NODE_DEFAULT_VERSION}"
        fi
    fi
}

# The installers above (uv, nvm, pnpm, bun) each like to append lines to the shell
# rc files they find. Once stow has run, ~/.zshrc IS home/.zshrc in this repo, so an
# append lands in tracked source. Guards are passed where an installer offers one
# (uv, nvm); this is the measurement for the rest: the repo's own rc files must be
# unchanged by the install. Reported, never reverted -- the diff may be yours.
_rc_pollution_check() {
    [[ "$DRY_RUN" == true ]] && return 0
    local dirty
    dirty=$(git -C "$REPO_DIR" diff --stat -- home/.zshrc home/.zshenv home/.zprofile home/.bashrc home/.profile 2>/dev/null || true)
    [[ -n "$dirty" ]] || return 0
    warn "A tracked shell rc file changed during this install (an installer appended to it through the stow link?):"
    printf '%s\n' "$dirty" | sed 's/^/    /'
    info "Review with: ${CYAN}git -C $(pretty_path "$REPO_DIR") diff -- home/.zshrc${RESET}  (the stowed .zshrc already sets PATH for every tool installed here)"
}

# ==============================================================================
# Uninstall
# ==============================================================================

uninstall() {
    step "Uninstalling Dotfiles"

    cd "$REPO_DIR"

    if confirm "Remove all symlinks created by stow (home/ → ~/)?"; then
        _clean_stale_repo_links
        local -a stow_args=(-D --no-folding -t "$HOME" home)
        [[ "$VERBOSE" == true ]] && stow_args=(-D --no-folding -v -t "$HOME" home)
        if run_cmd stow "${stow_args[@]}"; then
            success "Symlinks removed"
            # Retire the link manifest and stop the watcher, so nothing "restores" or
            # alarms about a deliberate uninstall.
            local lm="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links/current.tsv"
            local wl="$HOME/Library/LaunchAgents/com.captaincodeau.dotlinks-watch.plist"
            [[ -f "$lm" ]] && run_cmd mv -f "$lm" "${lm%.tsv}.retired-$(date +%Y%m%d-%H%M%S).tsv"
            if [[ -f "$wl" ]]; then
                run_cmd launchctl bootout "gui/$(id -u)/com.captaincodeau.dotlinks-watch" 2>/dev/null || true
                run_cmd mv -f "$wl" "$wl.retired-$(date +%Y%m%d-%H%M%S)"
            fi
        else
            error "stow -D failed"
            return 1
        fi
    fi

    local os
    os=$(check_os)
    if [[ "$os" == "macos" ]]; then
        local cursor_dst="$HOME/Library/Application Support/Cursor/User/settings.json"
        local code_dst="$HOME/Library/Application Support/Code/User/settings.json"

        for dst in "$cursor_dst" "$code_dst"; do
            if [[ -L "$dst" ]]; then
                local target
                target=$(readlink "$dst")
                if [[ "$target" == *"fifty-shades-of-dotfiles"* ]]; then
                    run_cmd "$SAFE_RM" "$dst"
                    success "Removed: $(pretty_path "$dst")"
                    if [[ -f "${dst}.bak" ]]; then
                        run_cmd mv "${dst}.bak" "$dst"
                        info "Restored backup: $(pretty_path "${dst}.bak") → $(pretty_path "$dst")"
                    fi
                fi
            fi
        done
    fi

    echo
    success "Uninstall complete. Your home directory is back to normal."
    info "The repo itself is untouched — run ./install.sh to re-install."
}

# ==============================================================================
# Update (pull + restow)
# ==============================================================================

update() {
    step "Updating Dotfiles"

    cd "$REPO_DIR"

    info "Pulling latest changes..."
    run_cmd git pull

    # Bypasses main()'s flow entirely and restows on its own -- must not
    # skip the gate main() would otherwise have run.
    _gate_toolchain_takeover

    info "Restowing home/ → ~/"
    # Same sandbox caveat as stow_home() -- see the note there before trusting a dry run.
    if ! _restow_home; then
        error "Restow did not complete; check the links with: ${CYAN}sh ~/.local/state/dotfiles/links/restore check${RESET}"
        return 1
    fi
    _snapshot_links

    stow_platform

    success "Dotfiles updated and restowed."
}

# ==============================================================================
# Force (stow --adopt)
# ==============================================================================

force_adopt() {
    step "Force Adopt (stow --adopt)"

    cd "$REPO_DIR"

    warn "This will replace repo files with your local versions."
    warn "After adoption, use 'git diff' to review what changed."
    echo

    # --adopt overwrites repo files in the working tree. With uncommitted edits
    # under home/ (this session's, or another session's in the same checkout)
    # those edits would be lost, and git cannot bring them back.
    local dirty
    dirty=$(git -C "$REPO_DIR" status --porcelain -- home 2>/dev/null)
    if [[ -n "$dirty" ]]; then
        error "Refusing --force: home/ has uncommitted changes that adoption would overwrite:"
        printf '%s\n' "$dirty" | sed 's/^/    /' >&2
        echo -e "  Commit them (or ask the session that owns them) first." >&2
        return 1
    fi

    if confirm "Proceed with stow --adopt?"; then
        # force_adopt also (re)applies the hijack functions -- same gate as
        # every other path that stows home/.zshrc.
        _gate_toolchain_takeover
        if ! _restow_home --adopt; then
            error "Adoption did not complete; check the links with: ${CYAN}sh ~/.local/state/dotfiles/links/restore check${RESET}"
            return 1
        fi
        _snapshot_links
        success "Adoption complete."
        echo
        info "Review changes with: ${CYAN}git diff${RESET}"
        info "To undo:             ${CYAN}git checkout -- home/${RESET}"
    fi
}

# ==============================================================================
# Summary
# ==============================================================================

show_summary() {
    step "Installation Complete"
    echo
    echo -e "${BOLD}What was done:${RESET}"
    echo -e "  ${GREEN}✓${RESET} Dotfiles from home/ symlinked to ~/"

    local os
    os=$(check_os)
    if [[ "$os" == "macos" ]]; then
        local cursor_dst="$HOME/Library/Application Support/Cursor/User/settings.json"
        local code_dst="$HOME/Library/Application Support/Code/User/settings.json"
        [[ -L "$cursor_dst" ]] && echo -e "  ${GREEN}✓${RESET} Cursor settings linked"
        [[ -L "$code_dst" ]] && echo -e "  ${GREEN}✓${RESET} VSCode settings linked"
    fi
    if [[ -x "$HOME/.local/bin/sysinfo" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}sysinfo${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/dirdiff" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}dirdiff${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/watch-history-sync" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}watch-history-sync${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/pnpm-audit-tree" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}pnpm-audit-tree${RESET} ${DIM}(recursive supply-chain auditor)${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/pnpm-audit-hook" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}pnpm-audit-hook${RESET} ${DIM}(opt-in git pre-commit/pre-push; see docs/PNPM_AUDIT_TREE.md)${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/git-trailer-audit" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}git-trailer-audit${RESET} ${DIM}(C-* attribution coverage audit; see docs/CLAUDE_SESSION_ATTRIBUTION.md)${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/p10k-contrast-check" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}p10k-contrast-check${RESET} ${DIM}(prompt contrast audit per iTerm2 profile)${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/toolchain-stocktake" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}toolchain-stocktake${RESET} ${DIM}(survey existing Python/Node toolchain; see docs/TOOLCHAIN_TAKEOVER_CONSENT.md)${RESET}"
    fi
    if [[ -x "$HOME/.local/bin/project-impact-scan" ]]; then
        echo -e "  ${GREEN}✓${RESET} Standalone script command available: ${CYAN}project-impact-scan${RESET} ${DIM}(which projects break when npm/venv get blocked; see docs/TOOLCHAIN_TAKEOVER_CONSENT.md)${RESET}"
    fi

    # Show what's still missing
    echo
    echo -e "${BOLD}Still needed (if not done above):${RESET}"
    local all_good=true

    # REPEATED HERE ON PURPOSE. The C++ pre-flight runs first, and on a re-install
    # roughly two hundred lines of stow output scroll past before the run ends --
    # so the one thing the operator actually has to go and do by hand is the one
    # thing they can no longer see. Said again at the point they stop reading.
    #
    # Gated on the flag, not on Intel: a compiler/SDK mismatch is not
    # architecture-specific, it just happened to surface on an Intel machine.
    if [[ "${CC_TOOLCHAIN_OK:-true}" != true ]]; then
        # STATE THE NUMBERS, do not ask for a lookup. "Match your macOS version"
        # makes the operator go and find three facts this script already holds.
        # Every one of them is printed below, so the only thing left to decide on
        # Apple's page is which row to click.
        local _os_ver=""
        _os_ver=$(sw_vers -productVersion 2>/dev/null) || true
        local _os_major="${_os_ver%%.*}"
        # No codename: `sw_vers -productName` returns plain "macOS", and guessing
        # marketing names ("Sequoia", "Tahoe") is how a helpful line becomes a
        # wrong one. Apple's download page lists version numbers anyway.

        echo -e "  ${RED}!${RESET} ${BOLD}C++ toolchain is still broken${RESET} -- Homebrew cannot build from source."
        echo
        echo -e "     ${BOLD}This machine:${RESET}  macOS ${CYAN}${_os_ver:-unknown}${RESET}\
${CC_CLANG_MAJOR:+  ·  clang ${CYAN}${CC_CLANG_MAJOR}${RESET}}\
${CC_SDK_VER:+  ·  SDK ${CYAN}${CC_SDK_VER}${RESET}}"
        if [[ -n "$CC_CLANG_MAJOR" ]]; then
            echo -e "     ${BOLD}You need:${RESET}      Command Line Tools shipping clang ${BOLD}newer than ${CC_CLANG_MAJOR}${RESET}"
        else
            echo -e "     ${BOLD}You need:${RESET}      the newest Command Line Tools for macOS ${_os_major:-your version}"
        fi
        echo
        echo -e "     ${BOLD}1.${RESET} Open  ${CYAN}https://developer.apple.com/download/all/?q=command+line+tools${RESET}"
        echo -e "     ${BOLD}2.${RESET} Take the ${BOLD}newest${RESET} \"Command Line Tools for Xcode\"${_os_major:+ listed for macOS ${_os_major}}"
        echo -e "     ${BOLD}3.${RESET} Run the .dmg ${DIM}(installs over the top -- nothing needs deleting)${RESET}"
        echo -e "     ${BOLD}4.${RESET} Re-test  ${CYAN}echo '#include <string>' | clang++ -x c++ -fsyntax-only -${RESET}"
        echo
        echo -e "     ${DIM}Do NOT take an older release. Software Update may offer one; it is a${RESET}"
        echo -e "     ${DIM}downgrade and fails with \"No such update\".${RESET}"
        all_good=false
    fi

    if ! command -v gh &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Install GitHub CLI (${CYAN}gh${RESET}) if you need GitHub API/PR commands"
        all_good=false
    elif ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}~${RESET} ${CYAN}gh${RESET} is not authenticated (optional for API/PR usage)."
        echo -e "     ${DIM}Git transport here is SSH-only; avoid gh auth login/setup-git.${RESET}"
        all_good=false
    fi
    if [[ -d "$HOME/.tmux/plugins/tpm" ]] && command -v tmux &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Start tmux and press ${CYAN}prefix + I${RESET} to install tmux plugins"
        all_good=false
    fi
    if ! command -v claude &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Install Claude Code CLI: ${CYAN}https://docs.anthropic.com/en/docs/claude-code/overview${RESET} ${DIM}(install.sh never installs it)${RESET}"
        all_good=false
    fi
    if (( ${#NO_SUDO_SKIPPED[@]} > 0 )); then
        echo -e "  ${YELLOW}~${RESET} ${#NO_SUDO_SKIPPED[@]} command(s) needed root and were NOT run (--no-sudo); for root to run:"
        local _c
        for _c in "${NO_SUDO_SKIPPED[@]}"; do echo -e "      ${CYAN}${_c}${RESET}"; done
        all_good=false
    fi
    if [[ "$all_good" == true ]]; then
        echo -e "  ${GREEN}✓${RESET} Everything looks good!"
    fi
    if [[ -n "$PROFILE" ]]; then
        echo
        echo -e "${BOLD}Profile ${PROFILE}:${RESET} the parts it leaves out are listed on the Mode line at the top; ${CYAN}docs/INSTALL_PROFILES.md${RESET} says why."
    fi

    echo
    echo -e "${BOLD}Next steps:${RESET}"
    echo -e "  1. Open a new terminal (or: ${CYAN}exec zsh${RESET}) — nvm/pnpm/bun usable immediately in this terminal if installed above"
    echo -e "  2. The onboarding script will run automatically on first start"
    echo -e "  3. Create ${CYAN}~/.zshrc.private${RESET} for API keys and secrets"
    echo
    echo -e "${BOLD}Useful commands:${RESET}"
    echo -e "  ${CYAN}./install.sh --check${RESET}      Check prerequisites"
    echo -e "  ${CYAN}./install.sh --update${RESET}     Pull latest and restow"
    echo -e "  ${CYAN}./install.sh --uninstall${RESET}  Remove all symlinks"
    echo -e "  ${CYAN}./install.sh --dry-run${RESET}    Preview what would be done"
    echo -e "  ${CYAN}./install.sh --verbose${RESET}    Show detailed diagnostic output"
    echo -e "  ${DIM}Note:${RESET} Standalone scripts deploy via ${CYAN}home/.local/bin${RESET} and ${CYAN}home/.local/share/fifty-shades-of-dotfiles/scripts${RESET}"
    echo
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════╝${RESET}"
}

show_help() {
    echo -e "${BOLD}fifty-shades-of-dotfiles installer${RESET}"
    echo
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  ./install.sh              Full interactive install"
    echo -e "  ./install.sh --check      Check prerequisites + deploy parity (no changes)"
    echo -e "  ./install.sh --stow-only  Just run stow (skip prereqs)"
    echo -e "  ./install.sh --uninstall  Remove all symlinks"
    echo -e "  ./install.sh --update     Pull latest changes and restow"
    echo -e "  ./install.sh --force      Adopt existing files into repo (stow --adopt)"
    echo -e "  ./install.sh --help       Show this help"
    echo
    echo -e "${BOLD}Modifiers (combinable with any action):${RESET}"
    echo -e "  --verbose, -v             Show detailed diagnostic output"
    echo -e "  --dry-run                 Preview what would be done (no changes)"
    echo -e "  --skip-preflight          Skip pnpm conflict-detection AND the toolchain-takeover"
    echo -e "                            re-survey (does NOT skip consent itself -- see below)"
    echo
    echo -e "${BOLD}Profiles, skip flags, unattended runs (docs/INSTALL_PROFILES.md):${RESET}"
    echo -e "  --profile NAME            A named bundle of the flags below. Known: codebox"
    echo -e "  --no-questions            Every yes/no prompt takes its recorded answer; typed gates decline"
    echo -e "  --no-sudo                 A step that needs sudo is printed and skipped, never run"
    echo -e "  --skip-claude             home/.claude, Claude hook registration, pj settings and checks"
    echo -e "  --skip-ssh                home/.ssh"
    echo -e "  --skip-system-packages    apt/dnf/pacman/zypper/brew tool installs"
    echo -e "  --skip-tmux               .tmux.conf, .zsh_tmux, TPM"
    echo -e "  --skip-docker             .zsh_docker_functions, lazydocker"
    echo -e "  --skip-rust --skip-yazi --skip-fonts --skip-git-hooks --skip-git-identity"
    echo -e "  --skip-nvm --skip-pnpm --skip-bun --skip-uv --skip-herdr --skip-omz"
    echo
    echo -e "${BOLD}What it does:${RESET}"
    echo -e "  1. Checks and installs prerequisites (Homebrew, stow, uv, etc.)"
    echo -e "  2. Installs Oh My Zsh, plugins, and Powerlevel10k (if missing)"
    echo -e "  3. Checks for file conflicts in ~/ (with auto-backup option)"
    echo -e "  4. Surveys the machine's existing Python/Node toolchain and asks -- with a"
    echo -e "     real typed confirmation, not a bare-Enter default -- before Python is"
    echo -e "     handed to uv or npm/npx/yarn are blocked. Silent on a clean box. See"
    echo -e "     docs/TOOLCHAIN_TAKEOVER_CONSENT.md"
    echo -e "  5. Symlinks home/ → ~/ using GNU Stow"
    echo -e "  6. Symlinks platform-specific files (macOS Cursor/VSCode settings)"
    echo -e "  7. Sets up git identity, git-lfs, and SSH-only GitHub workflow guidance"
    echo -e "  8. Installs Python 3.13 via uv, nvm, pnpm, bun (standalone)"
    echo -e "  9. Installs TPM (Tmux Plugin Manager) and Nerd Fonts"
    echo -e " 10. Suggests creating ~/.zshrc.private for secrets"
    echo -e " 11. Verifies deploy parity — every tracked home/ file is linked in ~/"
    echo
}

# ==============================================================================
# Main
# ==============================================================================

# ==============================================================================
# pnpm supply-chain audit git hooks (opt-in, confirm-gated)
# ==============================================================================
# Optionally route git hooks through the stow-managed chainer at
# ~/.config/git/hooks so pnpm-audit-hook runs on `git push` for every repo, while
# preserving each repo's own hooks. A user-level core.hooksPath REPLACES per-repo
# .git/hooks (a repo that sets its own core.hooksPath, e.g. husky, overrides this
# and is unaffected), so the chainer delegates to each repo's real hook first and
# only adds the audit on pre-push. The setting is written to ~/.gitconfig.private
# (a machine-local file the stowed ~/.gitconfig already [include]s), NOT via
# `git config --global`: on these dotfiles ~/.gitconfig is a stow symlink into the
# repo, so --global would write the change straight into the tracked home/.gitconfig
# (repo pollution). Dormant until enabled here.
# ==============================================================================
# Claude Code hook registration
# ==============================================================================
# Stow deploys the hook SCRIPTS to ~/.claude/hooks/. A script there does NOTHING
# until ~/.claude/settings.json REGISTERS it -- and settings.json can never be
# stowed, because it is machine-local (the model, MCP servers, voice, permissions
# and the entire PAI hook set live in the same file).
#
# Until 2026-09-05 nothing here closed that gap: `grep -n '\.claude' install.sh`
# returned ZERO matches, so a newly added hook was stowed-but-inert on every
# machine until someone hand-edited 44KB of JSON. The Intel MacBook made it
# visible -- three hook files stowed, none registered, nothing saying so.
#
# The merge itself lives in home/.local/bin/claude-hooks-sync (add-only; it never
# removes or edits an existing entry) with its own selftest, matching how
# safe-rm, vuln-scan and deploy-parity-check are built. This is only the caller.
# See docs/CLAUDE_HOOKS.md.
#
# NEVER FATAL. A box with no jq, or with no settings.json yet, is a box with no
# hooks registered -- an install that is incomplete, not one that failed. The
# tool prints its own reason in every such case; exit 2 means "could not run".
# Render ~/.claude/settings.project.json, the settings file `pj` reads.
#
# WHY THIS EXISTS. Until 2026-09-19 that file was tracked by NOTHING -- not this
# repo, not a stow symlink, not dot-claude. It held the pj launcher's whole
# configuration in one place, on one machine, backed up nowhere. It cannot simply
# be stowed because it must carry ABSOLUTE paths (Claude Code does not expand
# ${HOME} in settings env values -- measured), and a committed copy of those
# would put a username in a public repo, which the pre-commit leak gate blocks.
#
# ORDER IS LOAD-BEARING: THIS RUNS BEFORE _claude_hooks_sync. The sync registers
# ci-watch INTO this file. The renderer merges any existing hooks forward, so
# either order preserves them on a second run -- but on a FIRST run, rendering
# after the sync would write the file before the hook was ever added, and the
# alarm would not appear until the next install. Render, then register.
#
# NEVER FATAL, same contract as _claude_hooks_sync: a box with no jq or no
# template is a box without pj settings, not a failed install.
_render_project_settings() {
    local mode="${1:-install}" rc=0
    local tool="$REPO_DIR/home/.local/bin/claude-project-settings-render"
    local template="$REPO_DIR/settings/claude/settings.project.json.template"

    [[ -x "$tool" ]]       || return 0
    [[ -f "$template" ]]   || return 0

    local -a args=("--$mode")
    [[ "$mode" == "install" && "$DRY_RUN" == true ]] && args+=(--dry-run)

    CLAUDE_PROJECT_SETTINGS_TEMPLATE="$template" "$tool" "${args[@]}" || rc=$?

    case "$mode" in
        check)
            # 1 = a render is pending: a real, fixable gap, so it counts against
            # --check like a missing symlink. 2 = could not run, which the tool
            # has already explained and install.sh cannot fix.
            (( rc == 1 )) && return 1
            return 0
            ;;
        *)
            (( rc != 0 )) && warn "pj settings render did not complete (exit $rc) -- continuing."
            return 0
            ;;
    esac
}

# The pj ID allocator (home/.local/bin/pj-id) stamps every W- and D- ID with the LETTER of
# the machine that minted it -- W-20260921-A07 -- so two clones can never claim the same ID
# (P5.5, P8a). The letter lives in ~/.config/pj/machine:
#   name: <hostname>
#   letter: A
# Gavin's four machines, ruled 2026-09-21:
#   A  the M4 Mac mini (desktop)      C  the PC, all coding inside WSL2 Ubuntu
#   B  the Intel Mac laptop           D  a Proxmox Linux VM or container
#
# THERE IS NO DEFAULT LETTER. pj-id REFUSES to allocate without one, so `open-items add` and
# `decided add` are dead on a box that skips this step. That is deliberate: a default range
# only risked a duplicate number, but a default LETTER would put another machine's name on
# this machine's work, which is a wrong record rather than a clash.
#
# WRITTEN ONCE, with ONE exception: a file left over from the retired two-range scheme
# (`range: 01-49`) is rewritten, because pj-id refuses to read it and the box would silently
# lose the ability to file an item. Every ID already claimed keeps its own text; the P8a
# migration renamed them and both tools still resolve the old shape.
# A GUESS, never a default (Gavin, 2026-09-27): the four machines differ today in facts
# the box can see (Mac chip, WSL or not), so the prompt names the likely letter. The
# letter is still TYPED; Enter alone writes nothing. A fifth machine sharing a shape with
# one of these would get the same guess, which is exactly why the guess is not accepted
# silently. The Mac chip comes from hw.optional.arm64, not `uname -m`: under Rosetta an
# M-series Mac reports x86_64. WSL is detected the way home/.zshrc detects it.
_pj_machine_letter_guess() {
    # Prints "<letter>|<description>", or nothing when the shape matches no known machine.
    case "$(uname -s)" in
        Darwin)
            if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]]; then
                printf 'A|M4 Mac mini'
            else
                printf 'B|Intel Mac laptop'
            fi ;;
        Linux)
            if [[ "$(uname -r)" =~ [Ww][Ss][Ll] || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
                printf 'C|PC, WSL2 Ubuntu'
            else
                printf 'D|Proxmox Linux VM'
            fi ;;
    esac
}
_pj_machine_letter_prompt() {
    # Prints ONE capital letter on stdout, or nothing when it could not ask.
    local ans guess
    [[ -t 0 && "$NO_QUESTIONS" != true ]] || { printf ''; return 0; }
    echo -e "  ${DIM}A = M4 Mac mini (desktop)   B = Intel Mac laptop   C = PC/WSL2 Ubuntu   D = Proxmox Linux VM${RESET}" >&2
    guess="$(_pj_machine_letter_guess)"
    [[ -n "$guess" ]] && echo -e "  Looks like ${BOLD}${guess%%|*}${RESET} (${guess#*|}). Type the letter to confirm; Enter alone writes nothing." >&2
    read -rp "$(echo -e "${YELLOW}Which machine is this? [A/B/C/D]: ${RESET}")" ans || { printf ''; return 0; }
    ans="$(printf '%s' "$ans" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
    case "$ans" in [A-Z]) printf '%s' "$ans" ;; *) printf '' ;; esac
}
_write_pj_machine_file() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/pj/machine" name letter existing_letter existing_range
    if [[ -f "$f" ]]; then
        existing_letter="$(sed -n 's/^letter:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
        existing_range="$(sed -n 's/^range:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
        if [[ "$existing_letter" =~ ^[A-Z]$ && -z "$existing_range" ]]; then
            info "pj machine file present: $f ($(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1), letter $existing_letter). Left as is."
            return 0
        fi
        if [[ "$existing_letter" =~ ^[A-Z]$ ]]; then
            # letter present, retired range line still there: drop the dead key, keep the letter
            name="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
            [[ -n "$name" ]] || name="$(hostname -s 2>/dev/null || hostname)"
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would drop the retired 'range: $existing_range' line from $f, keeping letter $existing_letter${RESET}"
                return 0
            fi
            # temp + rename: a failed write must never leave a half-written file pj-id refuses
            printf 'name: %s\nletter: %s\n' "$name" "$existing_letter" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f" \
                && success "pj machine file tidied: dropped the retired 'range:' line from $f (letter $existing_letter kept)" \
                || warn "could not rewrite $f"
            return 0
        fi
        # No letter at all. pj-id refuses to allocate from this file, so it must be fixed.
        warn "pj machine file $f has no 'letter:' line${existing_range:+ (it still carries the retired 'range: $existing_range')}. pj-id REFUSES to allocate an ID without one, so 'open-items add' and 'decided add' will not work on this box."
        # KEEP a name someone chose. The tidy branch above preserves it; this one used to
        # fall through to the hostname, so a hand-written file with a meaningful name lost
        # it on the very run that was meant to repair it.
        name="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | sed 's/[[:space:]]*$//')"
    fi
    [[ -n "${name:-}" ]] || name="$(hostname -s 2>/dev/null || hostname)"
    if [[ "$DRY_RUN" == true ]]; then
        local _g; _g="$(_pj_machine_letter_guess)"
        echo -e "  ${DIM}[dry-run] Would write $f (name: $name, letter: asked interactively -- A mini, B Intel laptop, C WSL, D Linux VM${_g:+; looks like ${_g%%|*}})${RESET}"
        return 0
    fi
    [[ -f "$f" ]] || warn "No pj machine file yet. Every W-/D- ID carries the letter of the machine that minted it, so two clones can never claim the same one."
    letter="$(_pj_machine_letter_prompt)"
    if [[ -z "$letter" ]]; then
        warn "No letter given, so $f was NOT written. pj-id will refuse to allocate IDs until it exists; re-run ./install.sh, or write it by hand:"
        # printf, not echo -e: echo does not substitute %s, and the first version of this
        # line printed the placeholders verbatim at the exact moment someone needed the
        # command to copy.
        printf '      %sprintf '"'"'name: %s\\nletter: <A-D>\\n'"'"' > %s%s\n' "${CYAN}" "$name" "$f" "${RESET}"
        return 0
    fi
    mkdir -p "$(dirname "$f")" || { warn "could not create $(dirname "$f"); pj-id will refuse to allocate IDs"; return 0; }
    { printf 'name: %s\nletter: %s\n' "$name" "$letter" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"; } || { warn "could not write $f"; return 0; }
    success "pj machine file written: $f (name: $name, letter: $letter -- IDs here read X-YYYYMMDD-${letter}NN)"
}

# --- pj prerequisites that live OUTSIDE this repo (P8a gate Q2) ---------------
# REPORT ONLY. It clones nothing, writes nothing and never fails the install.
#
# WHY IT EXISTS. Code and wiring live in this repo; the personal content pj needs does not
# (D-20260920-09). `pj-prompt-file` concatenates ~/.claude/LIFEOS/USER/CONFIG/OPERATIONAL_RULES.md
# and ~/.claude/pj-global/RULES.md, and `pj` REFUSES to launch when it gets neither. So on a
# fresh machine this installer can finish perfectly and `pj` still will not start -- measured
# by reading pj:46-49 and pj-prompt-file:118, not guessed. Before P8a nothing said so.
#
# THE PATH IS LOAD-BEARING. dot-claude tracks the three pj plugin files as SYMLINKS
# (git mode 120000) whose targets are relative paths ending in
# CODE/Scaffoldings/fifty-shades-of-dotfiles. Clone this repo anywhere else and those links
# dangle, silently: the plugin folder exists, the files in it resolve to nothing, and the
# only symptom is a pj session with no /pj:wrap-up. So a dead link is reported WITH the path
# it needs, not just as "missing".
# W-20260921-A23. PJ_PREREQS_OK is a GLOBAL, and the function still returns 0,
# because install.sh runs under `set -e`: returning non-zero here would abort the
# rest of main() mid-way, which is the opposite of the ruling. The ruling is that
# the installer FINISHES the public part, then refuses to call itself a success.
# The exit code is applied once, at the end of the dispatch.
PJ_PREREQS_OK=1
_check_pj_prereqs() {
    local dotclaude="$HOME/.claude" ok=1 required="$HOME/CODE/Scaffoldings/fifty-shades-of-dotfiles"
    local rules="$dotclaude/pj-global/RULES.md"
    local oprules="$dotclaude/LIFEOS/USER/CONFIG/OPERATIONAL_RULES.md"
    local p dead=""

    step "pj framework prerequisites (report only)"

    if [[ -r "$rules" ]]; then echo -e "  ${GREEN}✓${RESET} pj-global/RULES.md"
    else echo -e "  ${RED}✗${RESET} $rules missing -- pj launches without its machine-wide rules"; ok=0; fi
    for p in decisions notes/INDEX.md; do
        if [[ -e "$dotclaude/pj-global/$p" ]]; then echo -e "  ${GREEN}✓${RESET} pj-global/$p"
        else echo -e "  ${YELLOW}~${RESET} $dotclaude/pj-global/$p missing"; fi
    done
    if [[ -r "$oprules" ]]; then echo -e "  ${GREEN}✓${RESET} LIFEOS OPERATIONAL_RULES.md"
    else echo -e "  ${RED}✗${RESET} $oprules missing -- pj launches without Gavin's operating rules"; ok=0; fi
    if [[ -d "$dotclaude/pj-voice" ]]; then echo -e "  ${GREEN}✓${RESET} pj-voice plugin dir"
    else echo -e "  ${RED}✗${RESET} $dotclaude/pj-voice missing -- the pj output style will not load"; ok=0; fi

    # Profiles (F5a). NOT a ✗ and NOT part of `ok`: with no profiles dir `pj` falls back to
    # its built-in argv and launches exactly as it always did. That fallback is a supported
    # state, not a fault, so a missing profiles dir must not turn a working install red.
    # It is still worth a line, because the dir is what `pj --profile` and `c2` need.
    local pdir="${XDG_CONFIG_HOME:-$HOME/.config}/pj/profiles"
    if [[ -d "$pdir" ]]; then
        local pnames; pnames="$(ls "$pdir" 2>/dev/null | paste -sd ' ' -)"
        echo -e "  ${GREEN}✓${RESET} pj profiles: ${pnames:-none} ${DIM}(${pdir/#$HOME/\~})${RESET}"
        # A declared config dir that does not exist yet needs a human: a fresh config dir
        # has no credentials and no folder trust, so its first launch stops at /login.
        local pf cfg
        for pf in "$pdir"/*; do
            [[ -f "$pf" ]] || continue
            cfg="$(sed -n 's/^config_dir:[[:space:]]*//p' "$pf" 2>/dev/null | head -1)"
            [[ -n "$cfg" ]] || continue
            cfg="${cfg/#\~/$HOME}"
            [[ -d "$cfg" ]] || echo -e "      ${YELLOW}~${RESET} profile $(basename "$pf") declares ${cfg/#$HOME/\~}, which does not exist yet -- its first launch will ask you to /login and to trust the folder"
        done
    else
        echo -e "  ${YELLOW}~${RESET} $pdir absent -- pj uses its built-in argv (supported); \`pj --profile\` and \`c2\` need it, so re-run stow"
    fi

    # The three tracked symlinks: a dangling one is worse than an absent one, because the
    # folder still looks right.
    for p in pj/.claude-plugin/plugin.json pj/skills/wrap-up/SKILL.md pj/skills/health/SKILL.md; do
        if [[ -e "$dotclaude/$p" ]]; then echo -e "  ${GREEN}✓${RESET} $p"
        elif [[ -L "$dotclaude/$p" ]]; then dead="$dead $p"
        else echo -e "  ${YELLOW}~${RESET} $dotclaude/$p absent (stow places it)"; fi
    done
    if [[ -n "$dead" ]]; then
        ok=0
        echo -e "  ${RED}✗${RESET} dangling symlink(s) in ~/.claude:${dead}"
        echo -e "      ${DIM}dot-claude tracks these as symlinks into the dotfiles repo, so the repo MUST be at:${RESET}"
        echo -e "      ${CYAN}${required}${RESET}"
        [[ "$REPO_DIR" != "$required" ]] && echo -e "      ${DIM}this checkout is at ${REPO_DIR} -- move or symlink it there, then re-run ./install.sh${RESET}"
    fi

    if (( ok )); then
        success "pj can launch on this machine."
        PJ_PREREQS_OK=1
    else
        # W-20260921-A23, ruled 2026-09-21. The public installer NEVER clones the
        # two private repos -- a human clones them first. But it must SAY SO
        # unmistakably and it must not exit 0, or "installed fine" and "installed,
        # and pj cannot start" look identical to anyone reading a terminal or a CI
        # log. That is the same silent-failure shape as the SessionStart hooks
        # that were stowed but unregistered: a missing thing fails toward silence.
        PJ_PREREQS_OK=0
        echo
        echo -e "${RED}${BOLD}  ════════════════════════════════════════════════════════════${RESET}"
        echo -e "${RED}${BOLD}   pj is not ready on this machine${RESET}"
        echo -e "${RED}${BOLD}  ════════════════════════════════════════════════════════════${RESET}"
        warn "Everything this installer owns is done. pj itself will NOT launch until the items marked ✗ above exist. They live in two PRIVATE repos this installer deliberately does not clone:"
        echo -e "      ${CYAN}git clone <dot-claude>      ~/.claude${RESET}          ${DIM}(pj-global/, pj-voice/, the plugin symlinks)${RESET}"
        echo -e "      ${CYAN}git clone <lifeos-private>  ~/CODE/CaptainCodeAU/lifeos-private${RESET}"
        echo -e "      ${DIM}then link ~/.claude/LIFEOS/USER -> that clone. Clone dot-claude BEFORE running stow.${RESET}"
        echo -e "      ${DIM}And keep this repo at ${required} -- the tracked symlinks point there.${RESET}"
        echo
        echo -e "      ${DIM}Then re-run ./install.sh. When both are present this block is replaced by${RESET}"
        echo -e "      ${DIM}one green line, and ${RESET}${CYAN}pj-health${RESET}${DIM}'s pj-global row is the standing proof.${RESET}"
        echo -e "${RED}${BOLD}  ════════════════════════════════════════════════════════════${RESET}"
    fi

    # The zsh helper namespace check, if it is stowed. Read-only, and a real failure here
    # means a pj session's shell helpers collide with something else.
    if command -v zsh-helper-namespace-check >/dev/null 2>&1; then
        if zsh-helper-namespace-check >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${RESET} zsh helper namespace clean"
        else
            echo -e "  ${YELLOW}~${RESET} zsh-helper-namespace-check reports a collision -- run it to see which helper"
        fi
    fi
    return 0
}

_claude_hooks_sync() {
    local mode="${1:-install}" rc=0
    local tool="$REPO_DIR/home/.local/bin/claude-hooks-sync"
    local manifest="$REPO_DIR/settings/claude/hooks.json"

    [[ -x "$tool" ]]     || return 0
    [[ -f "$manifest" ]] || return 0

    # TWO TARGETS, ONE MANIFEST. ~/.claude/settings.json is what an ordinary
    # launch reads; ~/.claude/settings.project.json is what `pj` reads, because
    # pj passes --setting-sources project,local and so never loads the user
    # source at all. An entry reaches the second file only when its manifest
    # `targets` array names "project" -- today that is ci-watch alone.
    #
    # WHY THE PROJECT TARGET IS GATED ON THE FILE EXISTING. A machine that has
    # never run pj has no settings.project.json, and the tool would correctly
    # exit 2 ("nothing to register into") on every install. That is a true
    # statement nobody needs to read on every run, and an installer that prints
    # a harmless warning every time teaches you to skip its output.
    #
    # ORDER MATTERS IF A RENDER STEP IS EVER ADDED. Registration must run AFTER
    # anything that writes settings.project.json wholesale, or the render
    # silently drops the hooks this just registered.
    local -a targets=(user)
    [[ -f "$HOME/.claude/settings.project.json" ]] && targets+=(project)

    local t pending=0
    for t in "${targets[@]}"; do
        local -a args=("--$mode" --target "$t")
        # --dry-run reaches the tool so a dry install.sh run stays a dry run all
        # the way down; check mode never writes anyway.
        [[ "$mode" == "install" && "$DRY_RUN" == true ]] && args+=(--dry-run)

        rc=0
        CLAUDE_HOOKS_MANIFEST="$manifest" "$tool" "${args[@]}" || rc=$?

        case "$mode" in
            check)
                # 1 = registrations pending: a real, fixable deployment gap, so
                # let it count against --check exactly like a missing symlink.
                # 2 = could not run (no jq / no settings file). Not a deployment
                # problem and not something ./install.sh can fix, so it must not
                # fail the audit -- the tool has already said why.
                (( rc == 1 )) && pending=1
                ;;
            *)
                (( rc != 0 )) && warn "Claude hook registration ($t) did not complete (exit $rc) -- continuing."
                ;;
        esac
    done

    [[ "$mode" == "check" ]] && return "$pending"
    return 0
}

setup_vuln_scan() {
    # vuln-scan checks INSTALLED Homebrew packages against NVD and is wired into
    # both the shell banner and Claude's SessionStart. Deployment itself is handled
    # by stow (both files live under home/.local/bin), so this step exists for the
    # one thing stow cannot do: tell you the NVD API key is missing.
    #
    # WHY THAT MATTERS ENOUGH TO REPORT. The key is NOT a credential -- it grants
    # no access and only lifts NVD's anonymous limit from 5 to 50 requests per 30s.
    # But without it a first full scan takes ~20 minutes instead of ~4, and a
    # security check that feels broken is a security check that gets switched off.
    # So: never fatal, never prompts, never stores anything -- just says where to
    # put it on THIS platform, because the answer differs.
    command -v vuln-scan >/dev/null 2>&1 || return 0

    # Homebrew-only by design; on a Debian/Ubuntu box the tool reports that itself
    # rather than pretending to have scanned. Nothing to configure there yet.
    command -v brew >/dev/null 2>&1 || return 0

    local key_file="$HOME/.config/dotfiles/nvd-api-key"
    local have_key=false
    [[ -n "${NVD_API_KEY:-}" ]] && have_key=true
    [[ -s "$key_file" ]] && have_key=true
    # check_os(), not $IS_MAC -- that variable belongs to home/.zshrc and is
    # never assigned by install.sh itself. Under set -u it was an unbound-
    # variable crash on any box whose calling shell hadn't already loaded this
    # repo's dotfiles (a fresh machine, a friend's machine, plain `bash`) --
    # masked here only because the owner's own shells always export it first.
    local is_mac=false
    [[ "$(check_os)" == "macos" ]] && is_mac=true
    if [[ "$is_mac" == true ]] && security find-generic-password -s nvd-api-key -w >/dev/null 2>&1; then
        have_key=true
    fi

    if [[ "$have_key" == true ]]; then
        info "vuln-scan: NVD API key found (full-speed scans)."
        return 0
    fi

    warn "vuln-scan: no NVD API key -- scans will work but run ~5x slower."
    info "  Get one free (no account value, instantly regenerable):"
    info "    ${CYAN}https://nvd.nist.gov/developers/request-an-api-key${RESET}"
    if [[ "$is_mac" == true ]]; then
        info "  Then store it in the Keychain, without leaking it to shell history:"
        info "    ${CYAN}read -rs NVDK && security add-generic-password -U -a \"\$USER\" -s nvd-api-key -w \"\$NVDK\" && unset NVDK${RESET}"
    else
        info "  Then store it in a file readable only by you (no Keychain on this platform):"
        info "    ${CYAN}mkdir -p ~/.config/dotfiles && (umask 077; read -rs NVDK && printf '%s\\n' \"\$NVDK\" > ${key_file} && unset NVDK)${RESET}"
        info "  Or export ${CYAN}NVD_API_KEY${RESET} from ${CYAN}~/.zshrc.private${RESET} -- either is read automatically."
    fi
}

# npm and npx are refused on every route on this machine (D-20261006-A10): point each
# nvm Node version's bin/npm and bin/npx at npm-guard, which refuses and names the pnpm
# command. Re-run on every install.sh, because `nvm install` puts nvm's own links back
# for the version it installs. DOTFILES_ALLOW_NPM=1 stays the escape.
_apply_npm_guard() {
    local g="$HOME/.local/bin/npm-guard"
    step "npm guard (pnpm only)"
    if [[ ! -x "$g" ]]; then
        warn "npm-guard is not at $(pretty_path "$g"); npm and npx are NOT guarded."
        return 0
    fi
    if [[ ! -d "${NVM_DIR:-$HOME/.nvm}/versions/node" ]]; then
        info "No nvm Node versions yet; nothing to guard. Re-run ./install.sh after installing Node."
        return 0
    fi
    if "$g" --status >/dev/null 2>&1; then
        success "npm and npx are already guarded in every nvm Node version."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        "$g" --status 2>&1 | sed 's/^/  /'
        info "[dry-run] Would run: npm-guard --apply"
        return 0
    fi
    if "$g" --apply; then
        success "npm and npx now refuse on every route (DOTFILES_ALLOW_NPM=1 is the escape)."
    else
        warn "npm-guard --apply reported a problem; run it by hand: npm-guard --apply"
    fi
}

# Everything post-stow that lives in ~/.claude: render the pj settings file, THEN
# register hooks into it (the tool refuses to register a hook whose script is not on
# disk, so this must follow stow_home; render first so a first-ever install ends with
# the hook present), the pj machine letter, and the report on pj's prerequisites
# outside this repo (stow places the plugin symlinks it checks). --skip-claude skips
# the lot: home/.claude was not stowed, so there is nothing to register into and no
# pj to report on, and PJ_PREREQS_OK stays 1 so _finish exits 0.
_claude_post_stow() {
    if [[ "$SKIP_CLAUDE" == true ]]; then
        info "Claude hooks, pj settings, pj machine letter and pj checks skipped (--skip-claude)."
        return 0
    fi
    _render_project_settings install
    _claude_hooks_sync install
    _write_pj_machine_file
    _check_pj_prereqs
}

# ~/.zshrc.private.early is the machine-local file home/.zshrc reads BEFORE its
# startup guards (section 3), the same file install.sh's takeover gate writes its
# DOTFILES_ALLOW_* opt-outs to. A skip flag that changes what the stowed shell
# should do on THIS machine records it here, once, as a marked line.
#   --skip-claude  -> DOTFILES_PLAIN_CLAUDE=1: home/.zshrc's claude() guard refuses a
#                     bare `claude` in every interactive zsh and names engage, which a
#                     box without ~/.claude does not have. The flag leaves the guard
#                     undefined so plain Claude Code works (codebox Q17).
_write_early_optouts() {
    local early="$HOME/.zshrc.private.early" line
    local -a lines=()
    [[ "$SKIP_CLAUDE" == true ]] && lines+=("export DOTFILES_PLAIN_CLAUDE=1  # written by install.sh --skip-claude: no claude() pane guard on this box; see docs/INSTALL_PROFILES.md")
    (( ${#lines[@]} > 0 )) || return 0
    for line in "${lines[@]}"; do
        local key="${line%%=*}"
        if [[ -f "$early" ]] && grep -q "^${key}=" "$early" 2>/dev/null; then
            verbose "$(pretty_path "$early") already has ${key}"
            continue
        fi
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would append to $(pretty_path "$early"): ${key}=1${RESET}"
            continue
        fi
        if printf '%s\n' "$line" >> "$early"; then
            success "${key}=1 recorded in $(pretty_path "$early")"
        else
            warn "could not write $(pretty_path "$early"); add by hand: ${line}"
        fi
    done
    return 0
}

setup_pnpm_audit_hooks() {
    local hooks_dir="$HOME/.config/git/hooks"
    local priv="$HOME/.gitconfig.private"
    if [[ "$SKIP_GIT_HOOKS" == true ]]; then
        verbose "pnpm-audit git hooks skipped (--skip-git-hooks)"
        return 0
    fi
    # Need the stowed chainer present, and the auditor on PATH to be useful.
    [[ -e "$hooks_dir/pre-push" ]] || return 0
    command -v pnpm-audit-hook >/dev/null 2>&1 || return 0

    # Probe the value straight from ~/.gitconfig.private, where this setting is designed
    # to live. A plain `git config --get` reads the MERGED effective value -- and since
    # install.sh runs from inside this repo, a repo-local core.hooksPath (husky/lefthook,
    # or a stray override) would shadow the global state and mislead the decision below.
    # `--file "$priv"` reads only that file, immune to repo-local shadowing. (`--global
    # --get` is wrong here: it does NOT follow the [include] of ~/.gitconfig.private.)
    # `--type=path` expands a leading `~/` the way git itself does when it USES the value;
    # without it the literal "~/.config/git/hooks" never equals $hooks_dir and a hook path
    # that is ours was reported as someone else's on every run (W-20261006-A32). git < 2.18
    # has no --type, so fall back to the raw read rather than to empty: an empty answer here
    # means "unset" and leads to the prompt that WRITES the key.
    local current
    current=$(git config --file "$priv" --type=path --get core.hooksPath 2>/dev/null) \
        || current=$(git config --file "$priv" --get core.hooksPath 2>/dev/null || true)
    [[ "$current" == "~/"* ]] && current="$HOME/${current#\~/}"
    # Same directory by another spelling (a symlink, a trailing slash) is still ours.
    if [[ -n "$current" && -d "$current" && -d "$hooks_dir" ]] \
        && [[ "$(cd -P -- "$current" && pwd)" == "$(cd -P -- "$hooks_dir" && pwd)" ]]; then
        current="$hooks_dir"
    fi

    if [[ "$current" == "$hooks_dir" ]]; then
        verbose "pnpm-audit git hooks already active (core.hooksPath -> $hooks_dir)."
        return 0
    fi
    if [[ -n "$current" ]]; then
        warn "git core.hooksPath is already set to '$current' (not the pnpm-audit chainer). Leaving it untouched."
        info "To enable manually: ${CYAN}git config --file ~/.gitconfig.private core.hooksPath $hooks_dir${RESET}"
        return 0
    fi

    echo
    info "Optional: run the pnpm supply-chain auditor on every ${CYAN}git push${RESET} (all repos)."
    info "  Writes core.hooksPath -> ${CYAN}$hooks_dir${RESET} into ${CYAN}~/.gitconfig.private${RESET} (machine-local,"
    info "  NOT the stowed ~/.gitconfig). Preserves each repo's own hooks; husky/lefthook"
    info "  repos that set their own hooksPath are unaffected."
    info "  Bypass once with ${CYAN}PNPM_AUDIT_DISABLE=1 git push${RESET} or ${CYAN}git push --no-verify${RESET}."
    if confirm "Enable the pnpm-audit pre-push hook (writes to ~/.gitconfig.private)?"; then
        run_cmd git config --file "$priv" core.hooksPath "$hooks_dir"
        success "pnpm-audit pre-push hook enabled via ~/.gitconfig.private (runs on push)."
    else
        info "Skipped. Re-run ${CYAN}./install.sh${RESET} anytime to enable it."
    fi
}

main() {
    echo
    echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${MAGENTA}║          fifty-shades-of-dotfiles — Installer               ║${RESET}"
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo

    # --- Check we're running from the repo root ---
    if [[ ! -d "$REPO_DIR/home" ]]; then
        error "Cannot find 'home/' directory. Run this script from the repo root."
        exit 1
    fi

    # --- Concurrent Homebrew guard (FIRST, before anything touches brew) ---
    # Ordering is the whole point: every brew step below fails in a confusing way
    # when another brew holds a formula lock, and the operator sees a lock error
    # about an unrelated package instead of "something else is running".
    _preflight_brew_busy_check

    # --- C/C++ toolchain health (warns, never blocks) ---
    _preflight_cc_toolchain_check

    # --- Untrusted Homebrew taps (their formulae are being ignored) ---
    _preflight_brew_tap_trust_check

    # --- pnpm conflict pre-flight (corepack/v10 cleanup) ---
    # Run here (not inside install_prerequisites) so it executes on every run,
    # shows up under --dry-run, and clears conflicting pnpm sources BEFORE the
    # standalone-install step — even when all other prerequisites are present.
    _preflight_pnpm_check

    # --- pnpm floor pre-flight (upgrade a present-but-below-floor pnpm every run) ---
    # The in-prereq block (install_macos_prerequisites) only runs when a tool is
    # MISSING, so a fully-provisioned box never gets its pnpm floor enforced there.
    # This closes that gap; a missing pnpm is still left to the prereq installer.
    _preflight_pnpm_floor_check

    # --- Node EOL pre-flight (offer to remove unsupported Node majors) ---
    _preflight_node_eol_check

    # --- env-python3 floor pre-flight ---
    _preflight_env_python_floor_check

    # --- herdr cooldown guard (re-pin a formula that lost its pin) ---
    # A `brew unpin herdr` for a deliberate upgrade leaves the gate open if the
    # re-pin is forgotten; every run re-asserts it. No-op unless herdr is present
    # and Homebrew-managed.
    _preflight_herdr_pin_check

    # --- herdr cooldown bump (macOS/Homebrew): unpin/upgrade/pin once herdr-cooldown-check
    # reports the newest release has cleared HERDR_COOLDOWN_DAYS. Runs AFTER the pin-check
    # above so it always starts from a known-pinned state. herdr-cooldown-check itself stays
    # read-only -- this just runs the same manual commands it recommends, automatically. ---
    _preflight_herdr_bump_check

    # --- herdr leftover LaunchAgent (macOS): report a pre-2026-09-24 brew-services
    # plist, which would make `herdr server stop` respawn. Reports only. ---
    _preflight_herdr_service_health_check

    # --- herdr release pre-flight (Linux/WSL): re-apply a pin bump on a box that
    # already has herdr installed, since check_prerequisites never flags it "missing" ---
    _preflight_herdr_release_check

    # --- yt-dlp purge: yt() now runs it on demand via uvx, so a box that still
    # has it installed (package manager, or a loose Linux binary) is stale.
    # Unconditional for the same reason as the release-check above -- a box
    # missing nothing else would otherwise never reach it. ---
    _preflight_purge_ytdlp

    # --- Install prerequisites ---
    if ! check_prerequisites; then
        echo
        if confirm "Install all missing prerequisites (Homebrew, core + optional tools, pnpm, Oh My Zsh)?" n y; then
            SECTION_DECISION=yes
            install_prerequisites
            SECTION_DECISION=ask
            echo
            if ! check_prerequisites; then
                error "Some prerequisites are still missing. Please install them manually."
                exit 1
            fi
        else
            warn "Continuing without all prerequisites. Some features may not work."
        fi
    fi

    # --- pnpm cleanup steps held by the pre-flight until the replacement runs ---
    _pnpm_deferred_cleanup

    # --- OMZ plugins & themes (always prompt, even if prereqs passed) ---
    if [[ -d "$HOME/.oh-my-zsh" && "$SKIP_OMZ" != true ]]; then
        install_omz_plugins
    fi

    # --- Check for conflicts ---
    if ! check_conflicts; then
        echo
        info "Resolve conflicts (or use ./install.sh --force) and run again."
        exit 0
    fi

    # --- Toolchain takeover: survey, disclose, gate (MUST precede stow_home --
    # see the function's own comment for why not earlier / not skipped) ---
    _gate_toolchain_takeover

    # --- Stow ---
    # If stow fails, put back the real files check_conflicts moved into
    # ~/dotfiles-backup/, rather than leaving those paths empty in ~.
    if ! stow_home; then
        _restore_conflict_backups
        exit 1
    fi

    # --- Platform files ---
    stow_platform

    # --- Machine-local opt-outs a skip flag implies (~/.zshrc.private.early) ---
    _write_early_optouts

    # --- Post-install ---
    post_install

    # --- rm reach: plain shells reach the Trash rm; foreign look-alikes named.
    # Must run AFTER stow_home so ~/.local/bin/rm exists for the probe. ---
    _check_rm_reach

    # --- npm guard: every nvm Node version's npm/npx refuse. Must run AFTER
    # stow_home so ~/.local/bin/npm-guard exists to link to. ---
    _apply_npm_guard

    # --- herdr systemd user service (Linux/WSL): enable the unit stow just
    # placed. Must run AFTER stow_home; refuses to enable over a hand-started
    # server (respawn loop). The launchd equivalent is in preflight. ---
    if [[ "$SKIP_HERDR" != true ]]; then
        _post_stow_herdr_systemd_service

        # --- herdr: register the plugin stow just placed, share the agent skill
        # with Codex, and validate config.toml. Must run AFTER stow_home. ---
        _post_stow_herdr_plugins_and_skill
    fi

    # --- Claude and pj: settings render, hook registration, machine letter, pj
    # prerequisites. All of it lives in ~/.claude, so --skip-claude skips all of it. ---
    _claude_post_stow

    # --- Optional: pnpm-audit git hooks (confirm-gated) ---
    setup_pnpm_audit_hooks

    # --- Report on the vuln-scan NVD key (never fatal, never prompts) ---
    setup_vuln_scan

    # --- Offer to sweep outdated Homebrew formulae (LAST, and confirm-gated) ---
    # Runs at the very end on purpose: everything this script actually owns is
    # already done by here, so declining the sweep -- or having it fail -- costs
    # the operator nothing. Gated on the C++ toolchain being healthy.
    _offer_brew_sweep

    # --- Summary ---
    show_summary
}

# ==============================================================================
# Argument Handling
# ==============================================================================

# A profile is a named bundle of flags. Applied FIRST (see below), so a flag typed on
# the command line can still add to it; nothing typed can take a profile's skip away,
# because the flags are one-way switches, which keeps a profile's promises simple.
_apply_profile() {
    case "$1" in
        none)
            # Explicitly no profile. Also what clears a stored one (see _write_stow_state).
            ;;
        codebox)
            # Gavin's throwaway Claude Code box (Ubuntu 24.04, user without sudo, no
            # ~/.claude, no ~/.ssh, no tmux, no Docker; git over HTTPS only). The root
            # side installs zsh, stow, jq, trash-cli, fzf, zoxide and direnv before this
            # runs (Network_Plan boxes/codebox-vm-205/scripts/golden-system.sh). What
            # this profile installs as the user: uv + Python 3.13, nvm + Node
            # NODE_DEFAULT_VERSION, standalone pnpm, bun, herdr's pinned Linux release,
            # Oh My Zsh + plugins + Powerlevel10k, lazygit. docs/INSTALL_PROFILES.md.
            NO_QUESTIONS=true; NO_SUDO=true
            SKIP_CLAUDE=true; SKIP_SSH=true; SKIP_SYSTEM_PACKAGES=true
            SKIP_TMUX=true; SKIP_DOCKER=true; SKIP_RUST=true; SKIP_YAZI=true
            SKIP_FONTS=true; SKIP_GIT_HOOKS=true
            ;;
        *)
            error "Unknown profile: $1 (known: codebox, none)"
            exit 1 ;;
    esac
}

# A profile describes the BOX, not one run. Once a profiled stow has happened, a
# later plain `./install.sh --update` or `--stow-only` here would otherwise stow
# the very trees the profile left out (~/.claude on codebox). So a good stow records
# the profile in ~/.local/state/dotfiles/links/profile, and a run with no profile and
# no skip flags typed re-applies it, saying so. `--profile none` clears it. A run
# that types skip flags but no profile uses only what it typed, for that run.
_stored_profile_file() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/links/profile"; }
_stored_profile() {
    local f; f=$(_stored_profile_file)
    [[ -f "$f" ]] || return 0
    head -1 "$f" 2>/dev/null | tr -d '[:space:]'
}

ACTION=""
_CLI_PROFILE=""
declare -a _CLI_REST=()
# First pass: find the profile, so it is applied before any other flag.
_args=("$@")
_i=0
while (( _i < ${#_args[@]} )); do
    case "${_args[$_i]}" in
        --profile)   _CLI_PROFILE="${_args[$((_i+1))]:-}"; [[ -n "$_CLI_PROFILE" ]] || { error "--profile needs a name"; exit 1; }; _i=$((_i+2)); continue ;;
        --profile=*) _CLI_PROFILE="${_args[$_i]#--profile=}"; [[ -n "$_CLI_PROFILE" ]] || { error "--profile needs a name"; exit 1; }; _i=$((_i+1)); continue ;;
    esac
    _CLI_REST+=("${_args[$_i]}")
    _i=$((_i+1))
done
if [[ -n "$_CLI_PROFILE" ]]; then
    PROFILE="$_CLI_PROFILE"
    _apply_profile "$PROFILE"
fi
set -- "${_CLI_REST[@]+"${_CLI_REST[@]}"}"

_FLAGS_TYPED=false   # any --no-questions / --no-sudo / --skip-* on the command line
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)  VERBOSE=true; shift ;;
        --dry-run)     DRY_RUN=true; shift ;;
        --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
        --no-questions) NO_QUESTIONS=true; _FLAGS_TYPED=true; shift ;;
        --no-sudo)     NO_SUDO=true; _FLAGS_TYPED=true; shift ;;
        --skip-claude)          SKIP_CLAUDE=true; _FLAGS_TYPED=true; shift ;;
        --skip-ssh)             SKIP_SSH=true; _FLAGS_TYPED=true; shift ;;
        --skip-system-packages) SKIP_SYSTEM_PACKAGES=true; _FLAGS_TYPED=true; shift ;;
        --skip-tmux)            SKIP_TMUX=true; _FLAGS_TYPED=true; shift ;;
        --skip-docker)          SKIP_DOCKER=true; _FLAGS_TYPED=true; shift ;;
        --skip-rust)            SKIP_RUST=true; _FLAGS_TYPED=true; shift ;;
        --skip-yazi)            SKIP_YAZI=true; _FLAGS_TYPED=true; shift ;;
        --skip-fonts)           SKIP_FONTS=true; _FLAGS_TYPED=true; shift ;;
        --skip-git-hooks)       SKIP_GIT_HOOKS=true; _FLAGS_TYPED=true; shift ;;
        --skip-nvm)             SKIP_NVM=true; _FLAGS_TYPED=true; shift ;;
        --skip-pnpm)            SKIP_PNPM=true; _FLAGS_TYPED=true; shift ;;
        --skip-bun)             SKIP_BUN=true; _FLAGS_TYPED=true; shift ;;
        --skip-uv)              SKIP_UV=true; _FLAGS_TYPED=true; shift ;;
        --skip-herdr)           SKIP_HERDR=true; _FLAGS_TYPED=true; shift ;;
        --skip-omz)             SKIP_OMZ=true; _FLAGS_TYPED=true; shift ;;
        --skip-git-identity)    SKIP_GIT_IDENTITY=true; _FLAGS_TYPED=true; shift ;;
        --help|-h)     ACTION="help"; shift ;;
        --check)       ACTION="check"; shift ;;
        --stow-only)   ACTION="stow-only"; shift ;;
        --uninstall)   ACTION="uninstall"; shift ;;
        --update)      ACTION="update"; shift ;;
        --force)       ACTION="force"; shift ;;
        *)             error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# No profile and no flags typed: a profile recorded by an earlier stow on this box
# still applies (see _stored_profile). Not for --help or --uninstall.
if [[ -z "$PROFILE" && "$_FLAGS_TYPED" != true && "${ACTION:-}" != help && "${ACTION:-}" != uninstall ]]; then
    _stored="$(_stored_profile)"
    if [[ -n "$_stored" && "$_stored" != none ]]; then
        PROFILE="$_stored"
        _apply_profile "$PROFILE"
        info "Profile ${PROFILE} re-applied from the last stow on this box ($(pretty_path "$(_stored_profile_file)")); ${CYAN}--profile none${RESET} drops it."
    fi
    unset _stored
fi

# Say what an unattended or profiled run is doing before it does it. One line, at
# the top, so a log of the run can be read without knowing the command that made it.
if [[ -n "$PROFILE" || "$NO_QUESTIONS" == true || "$NO_SUDO" == true || "$_FLAGS_TYPED" == true ]]; then
    _mode=""
    [[ -n "$PROFILE" ]] && _mode+=" profile=$PROFILE"
    [[ "$NO_QUESTIONS" == true ]] && _mode+=" no-questions"
    [[ "$NO_SUDO" == true ]] && _mode+=" no-sudo"
    _skips=""
    for _v in CLAUDE SSH SYSTEM_PACKAGES TMUX DOCKER RUST YAZI FONTS GIT_HOOKS NVM PNPM BUN UV HERDR OMZ GIT_IDENTITY; do
        _n="SKIP_$_v"
        [[ "${!_n}" == true ]] && _skips+=" $(printf '%s' "$_v" | tr 'A-Z_' 'a-z-')"
    done
    info "Mode:${_mode:- (no profile)}${_skips:+ · skipping:${_skips}}"
    unset _mode _skips _v _n
fi

# W-20260921-A23: the two actions that run _check_pj_prereqs exit NON-ZERO when pj
# cannot launch. Everything the installer owns has already been done by then; the
# code says "done, and pj is not ready", which a human reading a terminal and a CI
# log reading $? both understand. Without it those two outcomes are identical.
_finish() { [[ "${PJ_PREREQS_OK:-1}" -eq 1 ]] || exit 3; exit 0; }

case "${ACTION:-}" in
    help)       show_help ;;
    check)      check_prerequisites ;;
    # --stow-only is what a consumer box runs after a pull, so it must also
    # register the hooks it just deployed -- otherwise the exact command the
    # welcome banner recommends leaves them stowed and inert, which is the
    # original bug wearing a different hat.
    stow-only)  _gate_toolchain_takeover; stow_home; stow_platform; _write_early_optouts; _claude_post_stow; _finish ;;
    uninstall)  uninstall ;;
    update)     update ;;
    force)      force_adopt ;;
    "")         main; _finish ;;
esac
