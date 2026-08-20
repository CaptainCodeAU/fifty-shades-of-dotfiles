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
# a trash tool is already a checked prerequisite -- see check_command trash / trash-put.
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
[[ -d "$HOME/.local/bin" ]]              && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/.local/share/pnpm" ]]       && export PATH="$HOME/.local/share/pnpm:$PATH"
[[ -d "$HOME/.local/share/pnpm/bin" ]]   && export PATH="$HOME/.local/share/pnpm/bin:$PATH"
[[ -d "$HOME/Library/pnpm" ]]            && export PATH="$HOME/Library/pnpm:$PATH"
[[ -d "$HOME/Library/pnpm/bin" ]]        && export PATH="$HOME/Library/pnpm/bin:$PATH"
[[ -d "$HOME/.bun/bin" ]]                && export PATH="$HOME/.bun/bin:$PATH"
[[ -d "$HOME/.cargo/bin" ]]              && export PATH="$HOME/.cargo/bin:$PATH"

# --- Mode flags ---
DRY_RUN=false
VERBOSE=false
SKIP_PREFLIGHT=false

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
PNPM_MIN_VERSION="11.21.0"

# --- nvm version policy ---
# Minimum acceptable nvm. Two mirror-based CVEs set this floor: CVE-2026-10796
# (RCE via a malicious mirror's version strings; affects <= 0.40.4, fixed 0.40.5)
# and CVE-2026-15921 (startup-file overwrite via LTS-alias path traversal;
# affects 0.32.1-0.40.5, fixed 0.40.6). If nvm is missing OR below this,
# install/upgrade is offered; the installer pins exactly this tag. Keep in sync
# with NVM_MIN_VERSION in home/.zsh_onboarding.
NVM_MIN_VERSION="0.40.6"

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
#   brew unpin herdr && brew upgrade herdr && brew pin herdr
# Raised from 3 to 7 (2026-08-20) after checking herdr's actual disclosed-vuln
# history: one real report took ~5.8 days to reach a shipped fix, and a second
# was auto-closed by their triage bot in 8 seconds with no human ever seeing
# it -- 3 days wasn't the right lever regardless, but 7 buys more of the
# window that DOES sometimes work (community/maintainer response) without
# pretending the gate alone solves a triage-process gap. See docs/HERDR.md.
HERDR_COOLDOWN_DAYS="7"

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
# v0.8.0 assets. install.sh REFUSES to install on mismatch, so a silently
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
#   4. update HERDR_VERSION + both hashes below in ONE commit
#   5. push, pull on each box, re-run ./install.sh
HERDR_VERSION="v0.8.0"
HERDR_SHA256_LINUX_X86_64="b872ea7e40fa2cb17e857ac9b62b1bf26db7b403c622f5d2f3f5b35f6e9acd28"
HERDR_SHA256_LINUX_AARCH64="f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"

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

# True (0) on Intel macOS, where pnpm's standalone executable is a Node.js SEA
# binary that segfaults 100% of the time (upstream nodejs/node#62893 /
# pnpm#11423). There, Homebrew is the supported pnpm provider instead of the
# get.pnpm.io standalone installer. Apple Silicon / Linux / WSL use standalone.
_pnpm_use_homebrew() {
    [[ "$(check_os)" == "macos" && "$(uname -m)" == "x86_64" ]]
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
            if [[ -x "$arg/npm" ]]; then
                run_cmd env PATH="$arg:$PATH" "$arg/npm" rm -g pnpm
            elif command -v npm &>/dev/null; then
                run_cmd npm rm -g pnpm
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
    local applied=0 failed=0
    for i in "${!ACT[@]}"; do
        echo
        info "${PLAN[$i]}"
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
    success "pnpm cleanup complete: $applied applied, $failed failed."
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

_preflight_herdr_pin_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # herdr is only gated if it is actually installed AND managed by Homebrew --
    # a direct install has no pin concept, and `herdr update` would bypass the
    # cooldown anyway (that case is reported by `herdr-cooldown-check`, not here).
    command -v herdr &>/dev/null || return 0
    command -v brew &>/dev/null || return 0
    brew list --versions herdr &>/dev/null || return 0
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
# running server process (Unix keeps the old inode mapped) or restarts the
# launchd service -- Homebrew's own herdr formula requires a manual `brew
# services restart herdr` after an upgrade, and never does it for you. That's
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

_preflight_herdr_bump_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    # macOS/Homebrew path only -- Linux/WSL bumps ship via _preflight_herdr_release_check.
    # Mirrors _preflight_pnpm_floor_check: once the cooldown has genuinely elapsed, upgrade
    # unconditionally, no y/N -- "lazy option", install.sh is the only thing you run.
    # Reuses herdr-cooldown-check's own (self-tested) version/age math via --json instead of
    # re-deriving it here in bash: one place decides ELIGIBLE, and its self-test gates this
    # too (a broken detector never triggers a bump, it just skips).
    command -v herdr &>/dev/null || return 0
    command -v brew &>/dev/null || return 0
    brew list --versions herdr &>/dev/null || return 0
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
    if run_cmd brew unpin herdr; then
        if ! run_cmd brew upgrade herdr; then
            warn "brew upgrade herdr failed — re-pinning the current version; will retry next run."
        fi
        run_cmd brew pin herdr
        hash -r 2>/dev/null || true
        if command -v herdr &>/dev/null; then
            success "herdr now $(herdr --version 2>/dev/null | awk '{print $2}') (pinned)"
        fi
        if [[ "$DRY_RUN" != true ]]; then
            local _restart_status
            _restart_status=$(_herdr_server_restart_status)
            if [[ "$_restart_status" == yes:* ]]; then
                warn "The running herdr server is still on ${_restart_status#yes:} — every attached session (including this one) would drop if restarted now."
                info "This never restarts automatically. Restart it yourself when it's a good time: ${CYAN}brew services restart herdr${RESET}"
            fi
        fi
    else
        warn "brew unpin herdr failed — leaving the current pin in place."
    fi
    return 0
}

# Distinct from _herdr_server_restart_status on purpose: that one guards an
# ALREADY-running server (disruptive to touch, so it only ever warns). This
# guards a server that is supposed to be running (its launchd plist exists)
# but currently ISN'T -- a down server has no attached sessions to protect,
# so starting it here is safe and needs no confirmation, same as any other
# preflight fix in this script. Without this, a crashed-and-not-restarted
# herdr (or one that didn't survive a reboot) shows a false green "server
# managed by launchd" in the prerequisites summary and install.sh does
# nothing to fix it -- confirmed live: the summary only checks the plist
# FILE exists, never whether the service it describes is actually up.
_preflight_herdr_service_health_check() {
    [[ "$SKIP_PREFLIGHT" == true ]] && return 0
    [[ "$(check_os)" == "macos" ]] || return 0
    command -v herdr &>/dev/null || return 0
    command -v brew &>/dev/null || return 0
    command -v jq &>/dev/null || return 0
    # Only relevant once someone opted into launchd management at all -- a box
    # that never ran `brew services start herdr` isn't broken, it's just
    # unmanaged (see the "~ server not managed" note in check_prerequisites).
    [[ -f "$HOME/Library/LaunchAgents/homebrew.mxcl.herdr.plist" ]] || return 0

    local svc_json=""
    svc_json=$(brew services info herdr --json 2>/dev/null) || true
    [[ -n "$svc_json" ]] || return 0
    local running
    running=$(jq -r '.[0].running // false' <<<"$svc_json" 2>/dev/null) || return 0
    [[ "$running" == "true" ]] && return 0

    step "Pre-flight herdr service health check"
    warn "herdr is supposed to be managed by launchd but isn't running — no attached sessions to protect, starting it."
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] No changes made. Re-run without --dry-run to start herdr."
        return 0
    fi
    if run_cmd brew services restart herdr; then
        success "herdr service restarted."
    else
        warn "brew services restart herdr failed — check ${CYAN}brew services info herdr${RESET} manually."
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

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    # Group-level auto-answer: a section approved/declined as a whole answers its
    # inner prompts here (echoed, so the user still sees what's covered).
    case "${SECTION_DECISION:-ask}" in
        yes) echo -e "  ${DIM}↳ ${prompt} → yes${RESET}"; return 0 ;;
        no)  echo -e "  ${DIM}↳ ${prompt} → skipped${RESET}"; return 1 ;;
    esac
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would ask: $prompt${RESET}"
        return 1
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
    verbose "Running: $*"
    "$@"
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
    DOTFILES_REPO="$REPO_DIR" "$checker"
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
    check_command uv       "uv"       || missing=$((missing+1))
    check_command direnv   "direnv"   || true
    check_command fzf      "fzf"      || true
    check_command eza      "eza"      || true
    check_command zoxide   "zoxide"   || true
    check_command tmux     "tmux"     || true
    check_command rg       "ripgrep"  || true
    if ! check_command fd "fd"; then
        check_command fdfind "fd (as fdfind)" || missing=$((missing+1))
    fi
    check_command gh       "GitHub CLI (gh)" || missing=$((missing+1))
    check_command nvim     "neovim"   || true
    check_command glow     "glow"     || true
    check_command lazygit  "lazygit"  || missing=$((missing+1))
    check_command lazydocker "lazydocker" || missing=$((missing+1))
    if [[ "$(check_os)" == "macos" ]]; then
        check_command trash    "trash (macOS)"  || missing=$((missing+1))
    else
        check_command trash-put "trash-cli (Linux)" || missing=$((missing+1))
    fi
    # herdr is REQUIRED on every platform. macOS gets it from Homebrew (formula
    # hashes the source tarball, checksummed bottle); Linux/WSL gets the pinned
    # release binary verified against HERDR_SHA256_* by install_herdr_release.
    # Both routes refuse an unverified artefact, so neither box is held to a
    # standard the other escapes.
    check_command herdr "herdr" || missing=$((missing+1))
    # Where herdr exists, its guards ARE the policy and must be observable:
    # the pin enforces the release cooldown, config.toml keeps the two
    # phone-home paths closed, and the LaunchAgent is what makes the session
    # server survive a crash. Report all three rather than assuming a past run
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
        if [[ -f "$HOME/Library/LaunchAgents/homebrew.mxcl.herdr.plist" ]]; then
            # The plist existing only means launchd is SET UP to manage it, not that
            # it's actually up right now (a crash, a reboot, or FileVault's pre-boot
            # ceiling -- see docs/HERDR.md -- can all leave it down with the plist
            # still present). _preflight_herdr_service_health_check runs earlier in
            # this script and would already have restarted it if it were down and
            # SKIP_PREFLIGHT wasn't set, but this line reports the real state rather
            # than assume that ran.
            local _herdr_svc_running=""
            if command -v jq &>/dev/null; then
                _herdr_svc_running=$(brew services info herdr --json 2>/dev/null \
                    | jq -r '.[0].running // false' 2>/dev/null)
            fi
            if [[ "$_herdr_svc_running" == "true" ]]; then
                echo -e "      ${GREEN}✓${RESET} server managed by launchd and running (crash-restart + start at login)"
            elif [[ "$_herdr_svc_running" == "false" ]]; then
                echo -e "      ${YELLOW}~${RESET} launchd plist present but server NOT running — ${CYAN}brew services restart herdr${RESET}"
            else
                echo -e "      ${GREEN}✓${RESET} server managed by launchd (crash-restart + start at login)"
            fi
        elif [[ "$(check_os)" == "macos" ]]; then
            echo -e "      ${YELLOW}~${RESET} server not managed — ${CYAN}brew services start herdr${RESET} (stop any running server FIRST)"
        fi
        # Surfaces skew from ANY upgrade path (this script's bump, a manual brew
        # upgrade, the Linux release pin) -- not just one this run just performed.
        # Never restarts anything; see _herdr_server_restart_status.
        local _herdr_restart_status
        _herdr_restart_status=$(_herdr_server_restart_status)
        if [[ "$_herdr_restart_status" == yes:* ]]; then
            echo -e "      ${YELLOW}~${RESET} server still running ${_herdr_restart_status#yes:} (installed build is newer) — restart when convenient:"
            echo -e "        ${CYAN}brew services restart herdr${RESET} (disrupts every attached session; never automatic)"
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
    check_command pnpm     "pnpm"     || missing=$((missing+1))
    check_command_optional node "node" || true
    check_command_optional bun  "bun"  || true
    echo

    echo -e "${BOLD}Python (via uv):${RESET}"
    if command -v uv &>/dev/null; then
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
    check_command_optional ffmpeg   "ffmpeg"   || true
    check_command_optional yt-dlp   "yt-dlp"   || true
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
    local -a formulae=(stow uv direnv jq fzf eza zoxide neovim tmux ripgrep fd gh git-lfs glow trash herdr)
    local to_install=()

    for formula in "${formulae[@]}"; do
        if ! brew list "$formula" &>/dev/null; then
            to_install+=("$formula")
        fi
    done

    if (( ${#to_install[@]} > 0 )); then
        info "Core tools to install: ${to_install[*]}"
        if confirm "Install these core tools via Homebrew?"; then
            run_cmd brew install "${to_install[@]}"
        fi
    else
        success "Core formulae already installed"
    fi

    # Pin herdr the moment it exists. The pre-flight guard runs BEFORE this
    # point, so on a fresh box it finds no herdr and returns clean -- leaving a
    # freshly installed, unpinned formula that the next `brew upgrade` could
    # walk straight past the cooldown. Close that window here.
    _preflight_herdr_pin_check

    # --- Required CLI tools (lazygit, lazydocker — installed unconditionally) ---
    local -a required_cli=(lazygit lazydocker)
    local req_install=()
    for formula in "${required_cli[@]}"; do
        brew list "$formula" &>/dev/null || req_install+=("$formula")
    done
    if (( ${#req_install[@]} > 0 )); then
        info "Installing required CLI tools: ${req_install[*]}"
        run_cmd brew install "${req_install[@]}"
    else
        success "lazygit + lazydocker already installed"
    fi

    # --- Optional CLI tools ---
    local -a optional=(ffmpeg yt-dlp aria2 tree fastfetch yazi)
    local opt_install=()

    for formula in "${optional[@]}"; do
        if ! brew list "$formula" &>/dev/null; then
            opt_install+=("$formula")
        fi
    done

    if (( ${#opt_install[@]} > 0 )); then
        echo
        info "Optional CLI tools not yet installed: ${opt_install[*]}"
        if confirm "Install optional CLI tools (media, git UI, file manager)?"; then
            # Install individually + non-fatal: a discontinued or renamed optional
            # formula must never abort the whole install (these are non-essential).
            local opt
            for opt in "${opt_install[@]}"; do
                run_cmd brew install "$opt" || warn "Optional '$opt' not installed (skipped)."
            done
        fi
    fi

    # --- pnpm ---
    # macOS provider: standalone (get.pnpm.io) on Apple Silicon; Homebrew on
    # Intel, where the standalone SEA binary segfaults (nodejs/node#62893).
    if _pnpm_needs_install_or_upgrade; then
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
            if confirm "$prompt"; then
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
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            run_cmd env RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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
    else
        info "Detected package manager: $pkg_mgr"

        # --- Core tools ---
        if confirm "Install core tools (stow, jq, fzf, direnv, eza, zoxide, tmux, ripgrep, fd, gh, git-lfs, trash-cli, neovim, glow)?"; then
            case "$pkg_mgr" in
                apt)
                    run_cmd sudo apt update
                    run_cmd sudo apt install -y stow jq fzf direnv zoxide tmux ripgrep fd-find git-lfs trash-cli glow neovim unzip
                    # fd-find installs as fdfind on Debian/Ubuntu — symlink to fd
                    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
                        run_cmd mkdir -p "$HOME/.local/bin"
                        run_cmd ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
                        info "Symlinked fdfind → ~/.local/bin/fd"
                    fi
                    # eza and gh need special repos on Ubuntu/Debian
                    if ! command -v eza &>/dev/null; then
                        info "eza requires a separate install on Debian/Ubuntu."
                        info "See: https://github.com/eza-community/eza#installation"
                    fi
                    if ! command -v gh &>/dev/null; then
                        info "Installing GitHub CLI via official repo..."
                        run_cmd sudo mkdir -p -m 755 /etc/apt/keyrings
                        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
                        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                        run_cmd sudo apt update && run_cmd sudo apt install -y gh
                    fi
                    ;;
                dnf)    run_cmd sudo dnf install -y stow jq fzf direnv eza zoxide tmux ripgrep fd-find gh git-lfs trash-cli glow neovim ;;
                pacman) run_cmd sudo pacman -S --noconfirm stow jq fzf direnv eza zoxide tmux ripgrep fd github-cli git-lfs trash-cli glow neovim ;;
                zypper) run_cmd sudo zypper install -y stow jq fzf direnv zoxide tmux ripgrep fd git-lfs trash-cli glow neovim ;;
            esac
        fi

        # --- lazygit (required — installed from latest GitHub release on all distros) ---
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
                        run_cmd sudo install "$lg_tmp/lazygit" -D -t /usr/local/bin/
                        success "lazygit ${lg_ver} installed to /usr/local/bin"
                    else
                        warn "lazygit release download failed — see https://github.com/jesseduffield/lazygit#installation"
                    fi
                    rm -rf "$lg_tmp"
                fi
            fi
        fi

        # --- lazydocker (required — official install script → ~/.local/bin on all distros) ---
        if command -v lazydocker &>/dev/null; then
            success "lazydocker already installed"
        else
            info "Installing lazydocker via official install script..."
            run_cmd bash -c 'curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | DIR="$HOME/.local/bin" bash'
        fi

        # --- Optional CLI tools ---
        if confirm "Install optional CLI tools (ffmpeg, yt-dlp, aria2, tree, fastfetch, yazi)?"; then
            # Non-fatal: a missing/renamed optional package must not abort the install.
            case "$pkg_mgr" in
                apt)    run_cmd sudo apt install -y ffmpeg aria2 tree fastfetch || warn "Some optional tools not installed (skipped)."
                        info "yt-dlp and yazi may need manual install on Debian/Ubuntu."
                        info "  yt-dlp: pip install yt-dlp  OR  https://github.com/yt-dlp/yt-dlp#installation"
                        info "  yazi:   installer offers a GitHub release download below; or see https://github.com/sxyazi/yazi#installation"
                        ;;
                dnf)    run_cmd sudo dnf install -y ffmpeg aria2 tree fastfetch yt-dlp yazi || warn "Some optional tools not installed (skipped)." ;;
                pacman) run_cmd sudo pacman -S --noconfirm ffmpeg aria2 tree fastfetch yt-dlp yazi || warn "Some optional tools not installed (skipped)." ;;
                zypper) run_cmd sudo zypper install -y ffmpeg aria2 tree fastfetch || warn "Some optional tools not installed (skipped)." ;;
            esac
        fi
    fi

    # --- uv ---
    if ! command -v uv &>/dev/null; then
        if confirm "uv not found. Install it?"; then
            run_cmd bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    # --- pnpm (standalone) ---
    if _pnpm_needs_install_or_upgrade; then
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
        if confirm "$prompt"; then
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
    if ! command -v rustup &>/dev/null; then
        if SECTION_DECISION=ask confirm "Install Rust toolchain (rustup)? Needed for cargo-binstall and other rust CLI tools."; then
            install_rust_toolchain
        fi
    fi

    # --- yazi (terminal file manager) via GitHub release zip ---
    if ! command -v yazi &>/dev/null; then
        if confirm "Install yazi (terminal file manager) from GitHub release?"; then
            install_yazi_release
        fi
    fi

    # --- herdr (agent multiplexer) via PINNED + hash-verified GitHub release ---
    # Not gated behind `command -v herdr` like yazi above: the function itself
    # compares the installed version against HERDR_VERSION, so re-running
    # install.sh after a deliberate version bump actually deploys the bump.
    install_herdr_release || warn "herdr not installed — see docs/HERDR.md"

    # --- Oh My Zsh ---
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            run_cmd env RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        fi
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

    _clean_stale_repo_links

    # NOTE for anyone running stow by hand under a restricted sandbox (e.g. a Claude
    # Code session): reads under `home/.ssh` may be denied, and stow ABORTS there while
    # walking the tree. A simulated run (`stow -n -R -v --no-folding -t ~ home`) then
    # prints an unlink phase with no matching link phase -- observed as 59 UNLINK / 0
    # LINK -- which reads as "tear down every stowed file and restore none". Unsandboxed
    # the same command returns a symmetric 70 UNLINK / 71 LINK. Verify a dry run
    # SUCCEEDED before trusting it; a truncated plan looks like a plan. See CLAUDE.md.
    local -a stow_args=(-R --no-folding -t "$HOME" home)
    [[ "$VERBOSE" == true ]] && stow_args=(-R --no-folding -v -t "$HOME" home)

    if run_cmd stow "${stow_args[@]}"; then
        success "home/ stowed successfully"
    else
        error "stow failed to create symlinks."
        echo -e "  ${CYAN}Re-install?${RESET}  Try ${CYAN}./install.sh --update${RESET}"
        echo -e "  ${CYAN}Real files?${RESET}  Try ${CYAN}./install.sh --force${RESET}"
        echo -e "  ${CYAN}Debug?${RESET}       Try ${CYAN}./install.sh --verbose${RESET}"
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
    if [[ -z "$git_name" || -z "$git_email" ]]; then
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
    if command -v uv &>/dev/null; then
        local has_python
        has_python=$(uv python list 2>/dev/null | grep "cpython-3.13" | grep -v "download available" | head -1)
        if [[ -z "$has_python" ]]; then
            if confirm "Install Python 3.13 via uv?"; then
                run_cmd uv python install 3.13
            fi
        else
            success "Python 3.13 already available via uv"
        fi
    fi

    # --- NVM ---
    # Pin the exact, audited tag (v${NVM_MIN_VERSION}); older nvm is affected by
    # CVE-2026-10796 (<= 0.40.4) and CVE-2026-15921 (<= 0.40.5). The official
    # installer is idempotent — re-running it upgrades an existing nvm in place.
    if [[ ! -d "$HOME/.nvm" ]]; then
        if confirm "nvm not found. Install it (v${NVM_MIN_VERSION}) for Node.js version management?"; then
            run_cmd bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_MIN_VERSION}/install.sh | bash"
            # Activate in current session so subsequent steps and the user can
            # use nvm immediately without opening a new terminal.
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            success "nvm installed (v${NVM_MIN_VERSION})"
        fi
    elif _nvm_needs_upgrade; then
        local cur_nvm
        cur_nvm=$(_nvm_installed_version)
        warn "nvm ${cur_nvm:-?} is below ${NVM_MIN_VERSION} (CVE-2026-10796 <= 0.40.4, CVE-2026-15921 <= 0.40.5)."
        if confirm "Upgrade nvm to v${NVM_MIN_VERSION}?"; then
            run_cmd bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_MIN_VERSION}/install.sh | bash"
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            success "nvm upgraded to v${NVM_MIN_VERSION}"
        fi
    else
        success "nvm installed (v$(_nvm_installed_version))"
    fi

    # --- Bun ---
    # bun >= BUN_MIN_VERSION is required for the ~/.bunfig.toml minimumReleaseAge
    # cooldown to apply; below it, bun silently ignores the key. `bun upgrade`
    # moves to the latest stable (bun can't pin a version like nvm does).
    if ! command -v bun &>/dev/null; then
        if confirm "bun not found. Install it?"; then
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
    if command -v tmux &>/dev/null; then
        if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
            if confirm "Install TPM (Tmux Plugin Manager)?"; then
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

    if [[ "$has_nerd_font" == false ]]; then
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
    _clean_stale_repo_links
    # Same sandbox caveat as stow_home() -- see the note there before trusting a dry run.
    local -a stow_args=(-R --no-folding -t "$HOME" home)
    [[ "$VERBOSE" == true ]] && stow_args=(-R --no-folding -v -t "$HOME" home)
    run_cmd stow "${stow_args[@]}"

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

    if confirm "Proceed with stow --adopt?"; then
        # force_adopt also (re)applies the hijack functions -- same gate as
        # every other path that stows home/.zshrc.
        _gate_toolchain_takeover
        _clean_stale_repo_links
        local -a stow_args=(--adopt --no-folding -t "$HOME" home)
        [[ "$VERBOSE" == true ]] && stow_args=(--adopt --no-folding -v -t "$HOME" home)
        run_cmd stow "${stow_args[@]}"
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

    if ! command -v gh &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Install GitHub CLI (${CYAN}gh${RESET}) if you need GitHub API/PR commands"
    elif ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}~${RESET} ${CYAN}gh${RESET} is not authenticated (optional for API/PR usage)."
        echo -e "     ${DIM}Git transport here is SSH-only; avoid gh auth login/setup-git.${RESET}"
    fi
    if [[ -d "$HOME/.tmux/plugins/tpm" ]] && command -v tmux &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Start tmux and press ${CYAN}prefix + I${RESET} to install tmux plugins"
        all_good=false
    fi
    if ! command -v claude &>/dev/null; then
        echo -e "  ${YELLOW}~${RESET} Install Claude Code CLI: ${CYAN}https://docs.anthropic.com/en/docs/claude-code/overview${RESET}"
        all_good=false
    fi
    if [[ "$all_good" == true ]]; then
        echo -e "  ${GREEN}✓${RESET} Everything looks good!"
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

setup_pnpm_audit_hooks() {
    local hooks_dir="$HOME/.config/git/hooks"
    local priv="$HOME/.gitconfig.private"
    # Need the stowed chainer present, and the auditor on PATH to be useful.
    [[ -e "$hooks_dir/pre-push" ]] || return 0
    command -v pnpm-audit-hook >/dev/null 2>&1 || return 0

    # Probe the value straight from ~/.gitconfig.private, where this setting is designed
    # to live. A plain `git config --get` reads the MERGED effective value -- and since
    # install.sh runs from inside this repo, a repo-local core.hooksPath (husky/lefthook,
    # or a stray override) would shadow the global state and mislead the decision below.
    # `--file "$priv"` reads only that file, immune to repo-local shadowing. (`--global
    # --get` is wrong here: it does NOT follow the [include] of ~/.gitconfig.private.)
    local current
    current=$(git config --file "$priv" --get core.hooksPath 2>/dev/null || true)

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

    # --- herdr service health (macOS): start it back up if launchd should be managing it
    # but it's not actually running. Safe and unconditional -- a down server has no
    # attached sessions to protect, unlike _herdr_server_restart_status above. ---
    _preflight_herdr_service_health_check

    # --- herdr release pre-flight (Linux/WSL): re-apply a pin bump on a box that
    # already has herdr installed, since check_prerequisites never flags it "missing" ---
    _preflight_herdr_release_check

    # --- Install prerequisites ---
    if ! check_prerequisites; then
        echo
        if confirm "Install all missing prerequisites (Homebrew, core + optional tools, pnpm, Oh My Zsh)?"; then
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

    # --- OMZ plugins & themes (always prompt, even if prereqs passed) ---
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
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
    stow_home

    # --- Platform files ---
    stow_platform

    # --- Post-install ---
    post_install

    # --- Optional: pnpm-audit git hooks (confirm-gated) ---
    setup_pnpm_audit_hooks

    # --- Report on the vuln-scan NVD key (never fatal, never prompts) ---
    setup_vuln_scan

    # --- Summary ---
    show_summary
}

# ==============================================================================
# Argument Handling
# ==============================================================================

ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)  VERBOSE=true; shift ;;
        --dry-run)     DRY_RUN=true; shift ;;
        --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
        --help|-h)     ACTION="help"; shift ;;
        --check)       ACTION="check"; shift ;;
        --stow-only)   ACTION="stow-only"; shift ;;
        --uninstall)   ACTION="uninstall"; shift ;;
        --update)      ACTION="update"; shift ;;
        --force)       ACTION="force"; shift ;;
        *)             error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

case "${ACTION:-}" in
    help)       show_help ;;
    check)      check_prerequisites ;;
    stow-only)  _gate_toolchain_takeover; stow_home; stow_platform ;;
    uninstall)  uninstall ;;
    update)     update ;;
    force)      force_adopt ;;
    "")         main ;;
esac
