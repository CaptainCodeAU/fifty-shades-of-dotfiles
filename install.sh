#!/usr/bin/env bash
# ==============================================================================
#  Dotfiles Installer — fifty-shades-of-dotfiles
# ==============================================================================
#  Usage:
#    ./install.sh              # Full install (interactive)
#    ./install.sh --check      # Check prerequisites only
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

# --- Ensure tool paths are visible to bash ---
# Tools installed via standalone installers (pnpm, bun, uv) land outside
# /usr/bin and may not be on PATH in a bash login shell. Root PNPM_HOME is
# included here so install.sh can find a pre-migration v10-layout pnpm to
# upgrade — the permanent PATH (in .zshrc) only includes bin/.
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

# --- pnpm version policy ---
# Minimum acceptable pnpm. If pnpm is missing OR below this, install/upgrade
# is offered. Keep in sync with PNPM_MIN_VERSION in home/.zsh_onboarding.
PNPM_MIN_VERSION="11.2.2"

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

# OS-correct home of the standalone pnpm install (where get.pnpm.io installs):
# ~/Library/pnpm on macOS, ~/.local/share/pnpm on Linux/WSL.
_pnpm_standalone_home() {
    case "$(check_os)" in
        macos) echo "$HOME/Library/pnpm" ;;
        *)     echo "$HOME/.local/share/pnpm" ;;
    esac
}

# True (0) if the active pnpm resolves to the standalone install (under its
# PNPM_HOME), as opposed to a corepack shim or an npm-global pnpm. Those other
# flavors can't be `pnpm self-update`d into the standalone layout, so the
# installer must treat them as "no standalone present" and curl-install instead.
_pnpm_is_standalone() {
    local p home
    p=$(command -v pnpm 2>/dev/null) || return 1
    home=$(_pnpm_standalone_home)
    [[ "$p" == "$home"/* ]]
}

# True (0) if a *standalone* pnpm is missing OR below PNPM_MIN_VERSION. A pnpm
# that exists only as a corepack shim / npm-global counts as "missing" here, so
# the standalone install path runs (self-update can't convert those into one).
_pnpm_needs_install_or_upgrade() {
    # No standalone pnpm (absent, or only corepack/npm-global present) → install.
    _pnpm_is_standalone || return 0
    local v cmp
    v=$(pnpm -v 2>/dev/null) || return 0
    cmp=$(_vercmp "$v" "$PNPM_MIN_VERSION") || return 0
    [[ "$cmp" == "-1" ]]
}

# Pre-flight: detect existing pnpm setups that would conflict with the dotfiles
# approach (standalone install at $PNPM_HOME, camelCase YAML config, no shell rc
# appends from `pnpm setup`, no distro/brew/corepack pnpm). Each detection is
# offered as an interactive fix via the `confirm` helper. User can decline any
# individual fix and resolve manually. See docs/PNPM_SETUP_GUIDE.md for the full
# mental model.
_preflight_pnpm_check() {
    if [[ "$SKIP_PREFLIGHT" == true ]]; then
        info "Skipping pre-flight pnpm check (--skip-preflight)"
        return 0
    fi
    step "Pre-flight pnpm conflict check"
    local issues_found=0
    local os
    os=$(check_os)

    # --- Cross-platform ---

    # 1. Multiple pnpm binaries on PATH (brew + standalone + npm-global, etc.)
    if command -v pnpm &>/dev/null; then
        local pnpm_paths pnpm_count
        pnpm_paths=$(which -a pnpm 2>/dev/null | sort -u)
        pnpm_count=$(echo "$pnpm_paths" | wc -l | tr -d ' ')
        if (( pnpm_count > 1 )); then
            warn "Multiple pnpm binaries on PATH:"
            echo "$pnpm_paths" | sed 's/^/    /'
            warn "Shell uses the first match. Removed sources below; verify the survivor is your intended one."
            ((issues_found++))
        fi
    fi

    # 2. ~/.npmrc with registry override / auth (may shadow pnpm settings)
    if [[ -f "$HOME/.npmrc" ]] && grep -qE '^(registry=|//|_auth)' "$HOME/.npmrc" 2>/dev/null; then
        warn "~/.npmrc has registry/auth content:"
        grep -E '^(registry=|//|_auth)' "$HOME/.npmrc" | sed 's/^/    /'
        warn "Custom registry here will override pnpm's expected default."
        if confirm "Back up and remove ~/.npmrc?"; then
            run_cmd mv "$HOME/.npmrc" "$HOME/.npmrc.pre-stow.$(date +%Y%m%d-%H%M%S).bak"
        fi
        ((issues_found++))
    fi

    # 3. ~/.config/pnpm/config.yaml is a real file (not a stow symlink)
    if [[ -f "$HOME/.config/pnpm/config.yaml" ]] && [[ ! -L "$HOME/.config/pnpm/config.yaml" ]]; then
        warn "~/.config/pnpm/config.yaml is a real file, not a stow symlink."
        warn "Stow will refuse to link the repo's config.yaml over it."
        if confirm "Back up the real file so stow can link the repo version?"; then
            run_cmd mv "$HOME/.config/pnpm/config.yaml" "$HOME/.config/pnpm/config.yaml.pre-stow.$(date +%Y%m%d-%H%M%S).bak"
        fi
        ((issues_found++))
    fi

    # 4. config.yaml with kebab-case keys (silently ignored by pnpm 11 in YAML)
    local active_cfg=""
    if [[ "$os" == "macos" ]] && [[ -e "$HOME/Library/Preferences/pnpm/config.yaml" ]]; then
        active_cfg="$HOME/Library/Preferences/pnpm/config.yaml"
    elif [[ -e "$HOME/.config/pnpm/config.yaml" ]]; then
        active_cfg="$HOME/.config/pnpm/config.yaml"
    fi
    if [[ -n "$active_cfg" ]] && grep -qE '^[a-z]+(-[a-z]+)+:' "$active_cfg" 2>/dev/null; then
        warn "Detected kebab-case keys in $(pretty_path "$active_cfg") — pnpm 11 silently ignores them in YAML."
        warn "Settings keys must be camelCase. Examples found:"
        grep -nE '^[a-z]+(-[a-z]+)+:' "$active_cfg" | head -5 | sed 's/^/    /'
        warn "Edit the file to switch keys to camelCase (e.g. minimumReleaseAge), then re-run install.sh."
        ((issues_found++))
    fi

    # 5. PNPM_HOME export in private/local rc files outside stow scope
    local rcfile
    for rcfile in "$HOME/.zshrc.local" "$HOME/.zshrc.private" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [[ -f "$rcfile" ]] && grep -qE '^export PNPM_HOME|^export PATH.*PNPM_HOME' "$rcfile" 2>/dev/null; then
            warn "PNPM_HOME export found in $(pretty_path "$rcfile"):"
            grep -nE 'PNPM_HOME' "$rcfile" | head -3 | sed 's/^/    /'
            warn "The stowed .zshrc already exports PNPM_HOME. Manual exports double-up PATH or conflict."
            warn "Edit $(pretty_path "$rcfile") to remove the pnpm lines."
            ((issues_found++))
        fi
    done

    # 6. Corepack-managed pnpm
    if command -v corepack &>/dev/null && corepack ls 2>/dev/null | grep -q pnpm; then
        warn "Corepack has pnpm enabled. May shadow the standalone install."
        if confirm "Disable corepack-managed pnpm?"; then
            run_cmd corepack disable pnpm
        fi
        ((issues_found++))
    fi

    # 7. Running pnpm daemons (may hold store locks)
    if pgrep -x pnpm &>/dev/null; then
        warn "Running pnpm processes detected:"
        pgrep -lx pnpm | head -3 | sed 's/^/    /'
        if confirm "Stop them with pkill?"; then
            run_cmd pkill -x pnpm || true
        fi
        ((issues_found++))
    fi

    # 8. v10 shim layout (pnpm binary at root instead of bin/)
    if [[ -n "${PNPM_HOME:-}" && -f "$PNPM_HOME/pnpm" ]]; then
        warn "pnpm shim at \$PNPM_HOME root (v10 layout). v11 expects \$PNPM_HOME/bin/ only."
        if confirm "Remove root-level shims (pnpm, pnpx, pn, pnx)?"; then
            local shim
            for shim in pnpm pnpx pn pnx; do
                [[ -f "$PNPM_HOME/$shim" ]] && rm "$PNPM_HOME/$shim"
            done
            info "Root shims removed."
        else
            ((issues_found++))
        fi
    fi

    # 8b. v10 managed-binary residue. pnpm 11 stores self-managed versions under
    #     .tools/@pnpm+exe/; the bare .tools/pnpm-exe/ dir holds only old pnpm 10
    #     binaries (dead weight, not on PATH). Platform-agnostic via PNPM_HOME.
    if [[ -n "${PNPM_HOME:-}" && -d "$PNPM_HOME/.tools/pnpm-exe" ]]; then
        local v10_exe_size
        v10_exe_size=$(du -sh "$PNPM_HOME/.tools/pnpm-exe" 2>/dev/null | awk '{print $1}')
        warn "Old pnpm 10 managed binaries at \$PNPM_HOME/.tools/pnpm-exe (${v10_exe_size:-unknown size})."
        if confirm "Delete v10 pnpm-exe binaries?"; then
            run_cmd rm -rf "$PNPM_HOME/.tools/pnpm-exe"
        fi
        ((issues_found++))
    fi

    # --- macOS-only ---
    if [[ "$os" == "macos" ]]; then
        # 9. Homebrew pnpm collides with standalone
        if command -v brew &>/dev/null && brew list pnpm &>/dev/null; then
            warn "Homebrew has pnpm installed. Collides with the standalone installer."
            if confirm "Run 'brew uninstall pnpm'?"; then
                run_cmd brew uninstall pnpm
            fi
            ((issues_found++))
        fi

        # 10. Real file at ~/Library/Preferences/pnpm/config.yaml (not a symlink)
        local mac_yaml="$HOME/Library/Preferences/pnpm/config.yaml"
        if [[ -f "$mac_yaml" ]] && [[ ! -L "$mac_yaml" ]]; then
            warn "$(pretty_path "$mac_yaml") is a real file, not a symlink."
            warn "install.sh will symlink it to ~/.config/pnpm/config.yaml — needs the real file moved first."
            if confirm "Back up the real file? (install.sh will then create the bridge symlink)"; then
                run_cmd mv "$mac_yaml" "${mac_yaml}.pre-stow.$(date +%Y%m%d-%H%M%S).bak"
            fi
            ((issues_found++))
        fi

        # 11. v10 store leftover — offer to delete (v10 is unsupported)
        if [[ -d "$HOME/Library/pnpm/store/v10" ]]; then
            local v10_size
            v10_size=$(du -sh "$HOME/Library/pnpm/store/v10" 2>/dev/null | awk '{print $1}')
            warn "pnpm 10 store at ~/Library/pnpm/store/v10 (${v10_size:-unknown size})."
            if confirm "Delete v10 store to reclaim disk?"; then
                run_cmd rm -rf "$HOME/Library/pnpm/store/v10"
            fi
            ((issues_found++))
        fi

        # 12. v10 globals layout — offer to delete (v10 is unsupported)
        if [[ -d "$HOME/Library/pnpm/global/5" ]]; then
            warn "Old pnpm 10 globals at ~/Library/pnpm/global/5."
            warn "Reinstall any still-needed globals via 'pnpm install -g <pkg>'."
            if confirm "Delete v10 globals directory?"; then
                run_cmd rm -rf "$HOME/Library/pnpm/global/5"
            fi
            ((issues_found++))
        fi
    fi

    # --- Linux/WSL ---
    if [[ "$os" == "linux" || "$os" == "wsl" ]]; then
        if command -v dpkg &>/dev/null && dpkg -l 2>/dev/null | grep -qE '^ii\s+pnpm\s'; then
            warn "apt has pnpm installed. Distro packages lag the standalone version."
            if confirm "Run 'sudo apt remove pnpm'?"; then
                run_cmd sudo apt remove pnpm
            fi
            ((issues_found++))
        fi
        if command -v dnf &>/dev/null && dnf list installed 2>/dev/null | grep -q '^pnpm\.'; then
            warn "dnf has pnpm installed. Distro packages lag the standalone version."
            if confirm "Run 'sudo dnf remove pnpm'?"; then
                run_cmd sudo dnf remove pnpm
            fi
            ((issues_found++))
        fi
        if command -v pacman &>/dev/null && pacman -Qs '^pnpm$' &>/dev/null; then
            warn "pacman has pnpm installed. Distro packages lag the standalone version."
            if confirm "Run 'sudo pacman -R pnpm'?"; then
                run_cmd sudo pacman -R pnpm
            fi
            ((issues_found++))
        fi
        if command -v snap &>/dev/null && snap list pnpm &>/dev/null 2>&1; then
            warn "Snap has pnpm installed. Sandboxing conflicts with standalone setup."
            if confirm "Run 'snap remove pnpm'?"; then
                run_cmd snap remove pnpm
            fi
            ((issues_found++))
        fi
        if [[ -d "$HOME/.local/share/pnpm/global/5" ]]; then
            warn "Old pnpm 10 globals at ~/.local/share/pnpm/global/5."
            warn "Reinstall any still-needed globals via 'pnpm install -g <pkg>'."
            if confirm "Delete v10 globals directory?"; then
                run_cmd rm -rf "$HOME/.local/share/pnpm/global/5"
            fi
            ((issues_found++))
        fi
        if [[ -d "$HOME/.local/share/pnpm/store/v10" ]]; then
            local v10_size
            v10_size=$(du -sh "$HOME/.local/share/pnpm/store/v10" 2>/dev/null | awk '{print $1}')
            warn "pnpm 10 store at ~/.local/share/pnpm/store/v10 (${v10_size:-unknown size})."
            if confirm "Delete v10 store to reclaim disk?"; then
                run_cmd rm -rf "$HOME/.local/share/pnpm/store/v10"
            fi
            ((issues_found++))
        fi
    fi

    # --- WSL-only ---
    if [[ "$os" == "wsl" ]]; then
        if [[ -n "${PNPM_HOME:-}" ]] && [[ "$PNPM_HOME" == /mnt/[a-z]/* ]]; then
            error "PNPM_HOME points to a Windows mount: $PNPM_HOME"
            error "NTFS doesn't support symlinks under WSL2; pnpm will break."
            error "Fix: export PNPM_HOME=\"\$HOME/.local/share/pnpm\" in your shell rc."
            ((issues_found++))
        fi
        if command -v pnpm &>/dev/null; then
            local pnpm_path
            pnpm_path=$(command -v pnpm)
            if [[ "$pnpm_path" == /mnt/[a-z]/* ]]; then
                warn "pnpm in PATH is a Windows install: $pnpm_path"
                warn "WSL and Windows pnpm have different node_modules semantics. Re-order PATH to put WSL pnpm first."
                ((issues_found++))
            fi
        fi
    fi

    # --- Summary ---
    echo
    if (( issues_found > 0 )); then
        warn "Pre-flight check found $issues_found issue(s)."
        warn "Resolve them above, or re-run with --skip-preflight to bypass."
        warn "See docs/PNPM_SETUP_GUIDE.md for detailed remediation guidance."
    else
        success "Pre-flight pnpm check: clean."
    fi
    return 0
}

pretty_path() {
    echo "${1/#$HOME/~}"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
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

check_prerequisites() {
    step "Checking Prerequisites"

    local os
    os=$(check_os)
    info "Detected OS: $os"
    echo

    local missing=0

    echo -e "${BOLD}Essential:${RESET}"
    check_command git      "git"      || ((missing++))
    check_command zsh      "zsh"      || ((missing++))
    check_command stow     "GNU Stow" || ((missing++))
    check_command jq       "jq"       || ((missing++))
    echo

    echo -e "${BOLD}Shell Framework:${RESET}"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        echo -e "  ${GREEN}✓${RESET} Oh My Zsh ($HOME/.oh-my-zsh)"
    else
        echo -e "  ${RED}✗${RESET} Oh My Zsh — not installed"
        ((missing++))
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
    check_command uv       "uv"       || ((missing++))
    check_command direnv   "direnv"   || true
    check_command fzf      "fzf"      || true
    check_command eza      "eza"      || true
    check_command zoxide   "zoxide"   || true
    check_command tmux     "tmux"     || true
    check_command rg       "ripgrep"  || true
    if ! check_command fd "fd"; then
        check_command fdfind "fd (as fdfind)" || ((missing++))
    fi
    check_command gh       "GitHub CLI (gh)" || ((missing++))
    check_command nvim     "neovim"   || true
    check_command glow     "glow"     || true
    check_command lazygit  "lazygit"  || ((missing++))
    check_command lazydocker "lazydocker" || ((missing++))
    if [[ "$(check_os)" == "macos" ]]; then
        check_command trash    "trash (macOS)"  || ((missing++))
    else
        check_command trash-put "trash-cli (Linux)" || ((missing++))
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
    check_command pnpm     "pnpm"     || ((missing++))
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
            ((missing++))
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

install_macos_prerequisites() {
    _preflight_pnpm_check
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
    local -a formulae=(stow uv direnv jq fzf eza zoxide neovim tmux ripgrep fd gh git-lfs glow trash)
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
    local -a optional=(ffmpeg yt-dlp aria2 tree neofetch yazi)
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
            run_cmd brew install "${opt_install[@]}"
        fi
    fi

    # --- pnpm (standalone) ---
    if _pnpm_needs_install_or_upgrade; then
        local cur_pnpm="" prompt=""
        command -v pnpm &>/dev/null && cur_pnpm=$(pnpm -v 2>/dev/null || echo "unknown")
        if _pnpm_is_standalone; then
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
                    [[ -f "$PNPM_HOME/$shim" ]] && rm "$PNPM_HOME/$shim"
                done
                info "Root-level shims removed (v11 layout: \$PNPM_HOME/bin/ only)."
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
    _preflight_pnpm_check
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
        if confirm "Install optional CLI tools (ffmpeg, yt-dlp, aria2, tree, neofetch, yazi)?"; then
            case "$pkg_mgr" in
                apt)    run_cmd sudo apt install -y ffmpeg aria2 tree neofetch
                        info "yt-dlp and yazi may need manual install on Debian/Ubuntu."
                        info "  yt-dlp: pip install yt-dlp  OR  https://github.com/yt-dlp/yt-dlp#installation"
                        info "  yazi:   installer offers a GitHub release download below; or see https://github.com/sxyazi/yazi#installation"
                        ;;
                dnf)    run_cmd sudo dnf install -y ffmpeg aria2 tree neofetch yt-dlp yazi ;;
                pacman) run_cmd sudo pacman -S --noconfirm ffmpeg aria2 tree neofetch yt-dlp yazi ;;
                zypper) run_cmd sudo zypper install -y ffmpeg aria2 tree neofetch ;;
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
                    [[ -f "$PNPM_HOME/$shim" ]] && rm "$PNPM_HOME/$shim"
                done
                info "Root-level shims removed (v11 layout: \$PNPM_HOME/bin/ only)."
            fi
        fi
    fi

    # --- Rust toolchain (rustup) — optional ---
    if ! command -v rustup &>/dev/null; then
        if confirm "Install Rust toolchain (rustup)? Needed for cargo-binstall and other rust CLI tools."; then
            install_rust_toolchain
        fi
    fi

    # --- yazi (terminal file manager) via GitHub release zip ---
    if ! command -v yazi &>/dev/null; then
        if confirm "Install yazi (terminal file manager) from GitHub release?"; then
            install_yazi_release
        fi
    fi

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
                run_cmd rm "$target"
                ((cleaned++)) || true
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
                run_cmd rm "$target"
                ((cleaned++)) || true
            fi
        fi
    done < <(find "$home_dir" -type f ! -name '.DS_Store' -print0)

    if (( cleaned > 0 )); then
        info "Removed $cleaned stale symlink(s) from previous install"
    fi
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
        local target="$HOME/$relative"

        if [[ -e "$target" && ! -L "$target" ]]; then
            if _is_stow_managed "$target"; then
                echo -e "  ${DIM}✓ ~/$relative (stow-managed)${RESET}"
                ((stow_managed++))
            else
                warn "Conflict: ~/$relative already exists (not a symlink)"
                conflict_files+=("$target")
                ((conflicts++))
            fi
        elif [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" != *"fifty-shades-of-dotfiles"* ]]; then
                warn "Conflict: ~/$relative is a symlink to something else: $link_target"
                conflict_files+=("$target")
                ((conflicts++))
            else
                ((repo_symlinks++))
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

        if confirm "Auto-backup conflicting files to ~/dotfiles-backup/?"; then
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
        ((count++))
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
                # Real file (direnvrc has injected machine colors) — back it up before overwriting.
                # direnvrc will re-inject colors on next shell open (idempotent guard checks content).
                local cursor_bak="${cursor_dst}.bak.$(date +%Y%m%d_%H%M%S)"
                run_cmd cp "$cursor_dst" "$cursor_bak"
                info "Cursor settings.json backed up → $(basename "$cursor_bak")"
                run_cmd cp "$cursor_src" "$cursor_dst"
                success "Cursor settings.json updated from repo"
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
                # Real file (direnvrc has injected machine colors) — back it up before overwriting.
                local code_bak="${code_dst}.bak.$(date +%Y%m%d_%H%M%S)"
                run_cmd cp "$code_dst" "$code_bak"
                info "VSCode settings.json backed up → $(basename "$code_bak")"
                run_cmd cp "$code_src" "$code_dst"
                success "VSCode settings.json updated from repo"
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
}

# ==============================================================================
# Post-Install
# ==============================================================================

post_install() {
    step "Post-Install"

    local os
    os=$(check_os)

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
            info "For trusted LAN remotes, add private Host blocks with ${CYAN}ForwardAgent yes${RESET} to ${CYAN}~/.ssh/config.local${RESET} (loaded via ${CYAN}Include${RESET} from the stowed base config)."
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
    if [[ ! -d "$HOME/.nvm" ]]; then
        if confirm "nvm not found. Install it for Node.js version management?"; then
            run_cmd bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
            # Activate in current session so subsequent steps and the user can
            # use nvm immediately without opening a new terminal.
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            success "nvm installed"
        fi
    else
        success "nvm installed"
    fi

    # --- Bun ---
    if ! command -v bun &>/dev/null; then
        if confirm "bun not found. Install it?"; then
            run_cmd bash -c 'curl -fsSL https://bun.sh/install | bash'
            # Activate in current session.
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            success "bun installed"
        fi
    else
        success "bun installed"
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
                    run_cmd rm "$dst"
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

    info "Restowing home/ → ~/"
    _clean_stale_repo_links
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
    echo -e "  ./install.sh --check      Check prerequisites only"
    echo -e "  ./install.sh --stow-only  Just run stow (skip prereqs)"
    echo -e "  ./install.sh --uninstall  Remove all symlinks"
    echo -e "  ./install.sh --update     Pull latest changes and restow"
    echo -e "  ./install.sh --force      Adopt existing files into repo (stow --adopt)"
    echo -e "  ./install.sh --help       Show this help"
    echo
    echo -e "${BOLD}Modifiers (combinable with any action):${RESET}"
    echo -e "  --verbose, -v             Show detailed diagnostic output"
    echo -e "  --dry-run                 Preview what would be done (no changes)"
    echo -e "  --skip-preflight          Skip pnpm conflict-detection step"
    echo
    echo -e "${BOLD}What it does:${RESET}"
    echo -e "  1. Checks and installs prerequisites (Homebrew, stow, uv, etc.)"
    echo -e "  2. Installs Oh My Zsh, plugins, and Powerlevel10k (if missing)"
    echo -e "  3. Checks for file conflicts in ~/ (with auto-backup option)"
    echo -e "  4. Symlinks home/ → ~/ using GNU Stow"
    echo -e "  5. Symlinks platform-specific files (macOS Cursor/VSCode settings)"
    echo -e "  6. Sets up git identity, git-lfs, and SSH-only GitHub workflow guidance"
    echo -e "  7. Installs Python 3.13 via uv, nvm, pnpm, bun (standalone)"
    echo -e "  8. Installs TPM (Tmux Plugin Manager) and Nerd Fonts"
    echo -e "  9. Suggests creating ~/.zshrc.private for secrets"
    echo
}

# ==============================================================================
# Main
# ==============================================================================

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

    # --- Install prerequisites ---
    if ! check_prerequisites; then
        echo
        if confirm "Some prerequisites are missing. Attempt to install them?"; then
            install_prerequisites
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
        if ! confirm "Continue anyway (stow may fail)?"; then
            info "Resolve conflicts and run again."
            exit 0
        fi
    fi

    # --- Stow ---
    stow_home

    # --- Platform files ---
    stow_platform

    # --- Post-install ---
    post_install

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
    stow-only)  stow_home; stow_platform ;;
    uninstall)  uninstall ;;
    update)     update ;;
    force)      force_adopt ;;
    "")         main ;;
esac
