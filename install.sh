#!/usr/bin/env bash
# ==============================================================================
#  Dotfiles Installer — fifty-shades-of-dotfiles
# ==============================================================================
#  Usage:
#    ./install.sh              # Full install (interactive)
#    ./install.sh --check      # Check prerequisites only
#    ./install.sh --stow-only  # Just run stow (skip prereqs)
#    ./install.sh --uninstall  # Remove all symlinks
#    ./install.sh --help       # Show help
# ==============================================================================

set -euo pipefail

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Resolve the repo root (where this script lives) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# --- Helpers ---
info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}" >&2; }
step()    { echo -e "\n${BOLD}${MAGENTA}━━━ $* ━━━${RESET}"; }

# Shorten a path for display: replace $HOME with ~
pretty_path() {
    echo "${1/#$HOME/~}"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
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

# ==============================================================================
# Prerequisite Checks
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
    echo

    echo -e "${BOLD}Shell Framework:${RESET}"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        echo -e "  ${GREEN}✓${RESET} Oh My Zsh ($HOME/.oh-my-zsh)"
    else
        echo -e "  ${RED}✗${RESET} Oh My Zsh — not installed"
        ((missing++))
    fi

    # Check for OMZ custom plugins
    local omz_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    for plugin in zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do
        if [[ -d "$omz_custom/plugins/$plugin" ]]; then
            echo -e "  ${GREEN}✓${RESET} $plugin"
        else
            echo -e "  ${YELLOW}~${RESET} $plugin — not installed (optional but recommended)"
        fi
    done

    # Check for Powerlevel10k
    if [[ -d "$omz_custom/themes/powerlevel10k" ]]; then
        echo -e "  ${GREEN}✓${RESET} Powerlevel10k theme"
    else
        echo -e "  ${YELLOW}~${RESET} Powerlevel10k — not installed (optional)"
    fi
    echo

    echo -e "${BOLD}Core Tools:${RESET}"
    check_command uv       "uv"       || ((missing++))
    check_command direnv   "direnv"   || true
    check_command jq       "jq"       || true
    check_command fzf      "fzf"      || true
    check_command eza      "eza"      || true
    check_command zoxide   "zoxide"   || true
    check_command nvim     "neovim"   || true
    check_command node     "node"     || true
    echo

    echo -e "${BOLD}Python (via uv):${RESET}"
    if command -v uv &>/dev/null; then
        local uv_python
        uv_python=$(uv python list 2>/dev/null | grep -m1 "cpython-3.13" | grep -v "download available" | awk '{print $1}')
        if [[ -n "$uv_python" ]]; then
            echo -e "  ${GREEN}✓${RESET} Python 3.13 available via uv"
        else
            echo -e "  ${YELLOW}~${RESET} Python 3.13 not yet installed (run: uv python install 3.13)"
        fi
    fi
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

install_macos_prerequisites() {
    # --- Homebrew ---
    if ! command -v brew &>/dev/null; then
        if confirm "Homebrew not found. Install it?"; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add to PATH for this session
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
    local -a formulae=(stow uv direnv jq fzf eza zoxide neovim)
    local to_install=()

    for formula in "${formulae[@]}"; do
        if ! brew list "$formula" &>/dev/null; then
            to_install+=("$formula")
        fi
    done

    if (( ${#to_install[@]} > 0 )); then
        info "Installing: ${to_install[*]}"
        brew install "${to_install[@]}"
    else
        success "Core formulae already installed"
    fi

    # --- Oh My Zsh ---
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        fi
    fi
}

install_linux_prerequisites() {
    # Detect package manager
    local pkg_mgr=""
    if command -v apt &>/dev/null; then pkg_mgr="apt";
    elif command -v dnf &>/dev/null; then pkg_mgr="dnf";
    elif command -v pacman &>/dev/null; then pkg_mgr="pacman";
    elif command -v zypper &>/dev/null; then pkg_mgr="zypper";
    fi

    if [[ -z "$pkg_mgr" ]]; then
        warn "Could not detect package manager. Install stow, jq, fzf, and direnv manually."
    else
        info "Detected package manager: $pkg_mgr"
        if confirm "Install core tools (stow, jq, fzf, direnv, eza, zoxide)?"; then
            case "$pkg_mgr" in
                apt)    sudo apt update && sudo apt install -y stow jq fzf direnv zoxide ;;
                dnf)    sudo dnf install -y stow jq fzf direnv zoxide ;;
                pacman) sudo pacman -S --noconfirm stow jq fzf direnv zoxide ;;
                zypper) sudo zypper install -y stow jq fzf direnv zoxide ;;
            esac
        fi
    fi

    # --- uv ---
    if ! command -v uv &>/dev/null; then
        if confirm "uv not found. Install it?"; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    # --- Oh My Zsh ---
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if confirm "Oh My Zsh not found. Install it?" "y"; then
            RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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
    local -A plugins=(
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
        [zsh-completions]="https://github.com/zsh-users/zsh-completions"
    )

    for plugin in "${!plugins[@]}"; do
        if [[ ! -d "$omz_custom/plugins/$plugin" ]]; then
            any_missing=true
            if confirm "Install OMZ plugin: $plugin?"; then
                git clone "${plugins[$plugin]}" "$omz_custom/plugins/$plugin"
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
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$omz_custom/themes/powerlevel10k"
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

check_conflicts() {
    step "Checking for Conflicts"

    local conflicts=0
    local home_dir="$REPO_DIR/home"

    # Find all files in home/ that would be stowed
    while IFS= read -r -d '' file; do
        local relative="${file#$home_dir/}"
        local target="$HOME/$relative"

        # If target exists and is NOT already a symlink to our repo, it's a conflict
        if [[ -e "$target" && ! -L "$target" ]]; then
            warn "Conflict: ~/$relative already exists (not a symlink)"
            ((conflicts++))
        elif [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" != *"fifty-shades-of-dotfiles"* ]]; then
                warn "Conflict: ~/$relative is a symlink to something else: $link_target"
                ((conflicts++))
            fi
        fi
    done < <(find "$home_dir" -type f -print0)

    if (( conflicts > 0 )); then
        warn "$conflicts conflict(s) found"
        echo
        echo -e "  Options:"
        echo -e "    1. Back up conflicting files: ${CYAN}mkdir ~/dotfiles-backup && mv ~/.zshrc ~/dotfiles-backup/${RESET}"
        echo -e "    2. Force stow (adopt): ${CYAN}stow --adopt -t ~ home${RESET} (replaces repo files with yours, then git diff to review)"
        echo -e "    3. Delete conflicting files manually"
        echo
        return 1
    else
        success "No conflicts found"
        return 0
    fi
}

stow_home() {
    step "Stowing home/ → ~/"

    cd "$REPO_DIR"

    if stow -t "$HOME" home; then
        success "home/ stowed successfully"
    else
        error "stow failed. Run with --verbose for details: stow -v -t ~ home"
        return 1
    fi

    # --- Count what was linked ---
    local count=0
    while IFS= read -r -d '' file; do
        ((count++))
    done < <(find "$REPO_DIR/home" -type f -print0)
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

    # VSCode and Cursor settings live in ~/Library/Application Support/
    # Stow can't easily handle "Application Support" (space in path),
    # so we symlink these manually.
    local platform_dir="$REPO_DIR/platforms/macos/Library/Application Support"

    if [[ ! -d "$platform_dir" ]]; then
        info "No macOS platform files found. Skipping."
        return 0
    fi

    # --- Cursor ---
    local cursor_src="$platform_dir/Cursor/User/settings.json"
    local cursor_dst="$HOME/Library/Application Support/Cursor/User/settings.json"
    if [[ -f "$cursor_src" ]]; then
        if confirm "Symlink Cursor settings.json?"; then
            mkdir -p "$(dirname "$cursor_dst")"
            if [[ -e "$cursor_dst" && ! -L "$cursor_dst" ]]; then
                warn "Backing up existing Cursor settings to settings.json.bak"
                mv "$cursor_dst" "${cursor_dst}.bak"
            fi
            ln -sfn "$cursor_src" "$cursor_dst"
            success "Cursor settings.json → repo"
            echo -e "    ${CYAN}src: $(pretty_path "$cursor_src")${RESET}"
            echo -e "    ${CYAN}dst: $(pretty_path "$cursor_dst")${RESET}"
        fi
    fi

    # --- VSCode ---
    local code_src="$platform_dir/Code/User/settings.json"
    local code_dst="$HOME/Library/Application Support/Code/User/settings.json"
    if [[ -f "$code_src" ]]; then
        if confirm "Symlink VSCode settings.json?"; then
            mkdir -p "$(dirname "$code_dst")"
            if [[ -e "$code_dst" && ! -L "$code_dst" ]]; then
                warn "Backing up existing VSCode settings to settings.json.bak"
                mv "$code_dst" "${code_dst}.bak"
            fi
            ln -sfn "$code_src" "$code_dst"
            success "VSCode settings.json → repo"
            echo -e "    ${CYAN}src: $(pretty_path "$code_src")${RESET}"
            echo -e "    ${CYAN}dst: $(pretty_path "$code_dst")${RESET}"
        fi
    fi
}

# ==============================================================================
# Post-Install
# ==============================================================================

post_install() {
    step "Post-Install"

    # --- Python via uv ---
    if command -v uv &>/dev/null; then
        local has_python
        has_python=$(uv python list 2>/dev/null | grep "cpython-3.13" | grep -v "download available" | head -1)
        if [[ -z "$has_python" ]]; then
            if confirm "Install Python 3.13 via uv?"; then
                uv python install 3.13
            fi
        else
            success "Python 3.13 already available via uv"
        fi
    fi

    # --- direnv allow for the repo's own .envrc (if present) ---
    if command -v direnv &>/dev/null && [[ -f "$REPO_DIR/.envrc" ]]; then
        info "Allowing direnv for repo .envrc"
        direnv allow "$REPO_DIR/.envrc"
    fi

    # --- ~/.zshrc.private ---
    if [[ ! -f "$HOME/.zshrc.private" ]]; then
        info "Consider creating ~/.zshrc.private for API keys and machine-specific settings."
        echo -e "  ${CYAN}touch ~/.zshrc.private${RESET}"
    else
        success "~/.zshrc.private exists"
    fi

    # --- NVM ---
    if [[ ! -d "$HOME/.nvm" ]]; then
        info "nvm not found. Install it for Node.js version management:"
        echo -e "  ${CYAN}curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash${RESET}"
    else
        success "nvm installed"
    fi
}

# ==============================================================================
# Uninstall
# ==============================================================================

uninstall() {
    step "Uninstalling Dotfiles"

    cd "$REPO_DIR"

    if confirm "Remove all symlinks created by stow (home/ → ~/)?"; then
        if stow -D -t "$HOME" home; then
            success "Symlinks removed"
        else
            error "stow -D failed"
            return 1
        fi
    fi

    # --- Platform symlinks ---
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
                    rm "$dst"
                    success "Removed: $(pretty_path "$dst")"
                    # Restore backup if it exists
                    if [[ -f "${dst}.bak" ]]; then
                        mv "${dst}.bak" "$dst"
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
    echo
    echo -e "${BOLD}Next steps:${RESET}"
    echo -e "  1. Open a new terminal (or: ${CYAN}exec zsh${RESET})"
    echo -e "  2. The onboarding script will run automatically on first start"
    echo -e "  3. Create ${CYAN}~/.zshrc.private${RESET} for API keys and secrets"
    echo
    echo -e "${BOLD}Useful commands:${RESET}"
    echo -e "  ${CYAN}./install.sh --check${RESET}      Check prerequisites"
    echo -e "  ${CYAN}./install.sh --uninstall${RESET}  Remove all symlinks"
    echo -e "  ${CYAN}cd $REPO_DIR && stow -R -t ~ home${RESET}  Restow after adding new files"
    echo
}

show_help() {
    echo -e "${BOLD}fifty-shades-of-dotfiles installer${RESET}"
    echo
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  ./install.sh              Full interactive install"
    echo -e "  ./install.sh --check      Check prerequisites only"
    echo -e "  ./install.sh --stow-only  Just run stow (skip prereqs)"
    echo -e "  ./install.sh --uninstall  Remove all symlinks"
    echo -e "  ./install.sh --help       Show this help"
    echo
    echo -e "${BOLD}What it does:${RESET}"
    echo -e "  1. Checks and installs prerequisites (Homebrew, stow, uv, etc.)"
    echo -e "  2. Installs Oh My Zsh, plugins, and Powerlevel10k (if missing)"
    echo -e "  3. Checks for file conflicts in ~/"
    echo -e "  4. Symlinks home/ → ~/ using GNU Stow"
    echo -e "  5. Symlinks platform-specific files (macOS Cursor/VSCode settings)"
    echo -e "  6. Installs Python 3.13 via uv (if missing)"
    echo -e "  7. Suggests creating ~/.zshrc.private for secrets"
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
            # Re-check
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

case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --check)
        check_prerequisites
        ;;
    --stow-only)
        stow_home
        stow_platform
        ;;
    --uninstall)
        uninstall
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
