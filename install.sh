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
#    ./install.sh --help       # Show help
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

# --- Mode flags ---
DRY_RUN=false

# --- Helpers ---
info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}" >&2; }
step()    { echo -e "\n${BOLD}${MAGENTA}━━━ $* ━━━${RESET}"; }

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
    check_command jq       "jq"       || true
    check_command fzf      "fzf"      || true
    check_command eza      "eza"      || true
    check_command zoxide   "zoxide"   || true
    check_command tmux     "tmux"     || true
    check_command rg       "ripgrep"  || true
    check_command fd       "fd"       || true
    check_command gh       "GitHub CLI (gh)" || true
    check_command nvim     "neovim"   || true
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
    check_command_optional pnpm "pnpm" || true
    check_command_optional node "node" || true
    check_command_optional bun  "bun"  || true
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
    check_command_optional lazygit  "lazygit"  || true
    check_command_optional lazydocker "lazydocker" || true
    check_command_optional yazi     "yazi"     || true
    check_command_optional ffmpeg   "ffmpeg"   || true
    check_command_optional yt-dlp   "yt-dlp"   || true
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
    local -a formulae=(stow uv direnv jq fzf eza zoxide neovim tmux ripgrep fd gh git-lfs)
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

    # --- Optional CLI tools ---
    local -a optional=(ffmpeg yt-dlp aria2 tree neofetch lazygit lazydocker yazi)
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
        if confirm "Install core tools (stow, jq, fzf, direnv, eza, zoxide, tmux, ripgrep, fd, gh, git-lfs)?"; then
            case "$pkg_mgr" in
                apt)
                    run_cmd sudo apt update
                    run_cmd sudo apt install -y stow jq fzf direnv zoxide tmux ripgrep fd-find git-lfs
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
                dnf)    run_cmd sudo dnf install -y stow jq fzf direnv eza zoxide tmux ripgrep fd-find gh git-lfs ;;
                pacman) run_cmd sudo pacman -S --noconfirm stow jq fzf direnv eza zoxide tmux ripgrep fd github-cli git-lfs ;;
                zypper) run_cmd sudo zypper install -y stow jq fzf direnv zoxide tmux ripgrep fd git-lfs ;;
            esac
        fi

        # --- Optional CLI tools ---
        if confirm "Install optional CLI tools (ffmpeg, yt-dlp, aria2, tree, neofetch, lazygit, yazi)?"; then
            case "$pkg_mgr" in
                apt)    run_cmd sudo apt install -y ffmpeg aria2 tree neofetch
                        info "yt-dlp, lazygit, lazydocker, and yazi may need manual install on Debian/Ubuntu."
                        info "  yt-dlp:     pip install yt-dlp  OR  https://github.com/yt-dlp/yt-dlp#installation"
                        info "  lazygit:    https://github.com/jesseduffield/lazygit#installation"
                        info "  lazydocker: https://github.com/jesseduffield/lazydocker#installation"
                        info "  yazi:       https://github.com/sxyazi/yazi#installation"
                        ;;
                dnf)    run_cmd sudo dnf install -y ffmpeg aria2 tree neofetch yt-dlp lazygit yazi ;;
                pacman) run_cmd sudo pacman -S --noconfirm ffmpeg aria2 tree neofetch yt-dlp lazygit yazi ;;
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
    local -A plugins=(
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
        [zsh-completions]="https://github.com/zsh-users/zsh-completions"
    )

    for plugin in "${!plugins[@]}"; do
        if [[ ! -d "$omz_custom/plugins/$plugin" ]]; then
            any_missing=true
            if confirm "Install OMZ plugin: $plugin?"; then
                run_cmd git clone "${plugins[$plugin]}" "$omz_custom/plugins/$plugin"
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

check_conflicts() {
    step "Checking for Conflicts"

    local conflicts=0
    local conflict_files=()
    local home_dir="$REPO_DIR/home"

    while IFS= read -r -d '' file; do
        local relative="${file#$home_dir/}"
        local target="$HOME/$relative"

        if [[ -e "$target" && ! -L "$target" ]]; then
            warn "Conflict: ~/$relative already exists (not a symlink)"
            conflict_files+=("$target")
            ((conflicts++))
        elif [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" != *"fifty-shades-of-dotfiles"* ]]; then
                warn "Conflict: ~/$relative is a symlink to something else: $link_target"
                conflict_files+=("$target")
                ((conflicts++))
            fi
        fi
    done < <(find "$home_dir" -type f -print0)

    if (( conflicts > 0 )); then
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

    if run_cmd stow -t "$HOME" home; then
        success "home/ stowed successfully"
    else
        error "stow failed. Run with --verbose for details: stow -v -t ~ home"
        return 1
    fi

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
            run_cmd mkdir -p "$(dirname "$cursor_dst")"
            if [[ -e "$cursor_dst" && ! -L "$cursor_dst" ]]; then
                warn "Backing up existing Cursor settings to settings.json.bak"
                run_cmd mv "$cursor_dst" "${cursor_dst}.bak"
            fi
            run_cmd ln -sfn "$cursor_src" "$cursor_dst"
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
            run_cmd mkdir -p "$(dirname "$code_dst")"
            if [[ -e "$code_dst" && ! -L "$code_dst" ]]; then
                warn "Backing up existing VSCode settings to settings.json.bak"
                run_cmd mv "$code_dst" "${code_dst}.bak"
            fi
            run_cmd ln -sfn "$code_src" "$code_dst"
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

    local os
    os=$(check_os)

    # --- Git identity ---
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || true)
    git_email=$(git config --global user.email 2>/dev/null || true)
    if [[ -z "$git_name" || -z "$git_email" ]]; then
        info "Git identity not configured."
        if confirm "Set up git user.name and user.email now?"; then
            if [[ -z "$git_name" ]]; then
                read -rp "$(echo -e "${CYAN}  Your name: ${RESET}")" git_name
                if [[ -n "$git_name" ]]; then
                    run_cmd git config --global user.name "$git_name"
                fi
            fi
            if [[ -z "$git_email" ]]; then
                read -rp "$(echo -e "${CYAN}  Your email: ${RESET}")" git_email
                if [[ -n "$git_email" ]]; then
                    run_cmd git config --global user.email "$git_email"
                fi
            fi
            success "Git identity configured"
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

    # --- gh auth ---
    if command -v gh &>/dev/null; then
        if ! gh auth status &>/dev/null 2>&1; then
            warn "GitHub CLI (gh) is not authenticated."
            info "Your .gitconfig uses gh for credential management."
            info "Run ${CYAN}gh auth login${RESET} after installation to authenticate."
        else
            success "GitHub CLI authenticated"
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
            export NVM_DIR="$HOME/.nvm"
            success "nvm installed"
        fi
    else
        success "nvm installed"
    fi

    # --- pnpm (standalone) ---
    if ! command -v pnpm &>/dev/null; then
        if confirm "pnpm not found. Install it (standalone)?"; then
            run_cmd bash -c 'curl -fsSL https://get.pnpm.io/install.sh | sh -'
            success "pnpm installed (restart shell to use)"
        fi
    else
        success "pnpm installed"
    fi

    # --- Bun ---
    if ! command -v bun &>/dev/null; then
        if confirm "bun not found. Install it?"; then
            run_cmd bash -c 'export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH" && curl -fsSL https://bun.sh/install | bash'
            success "bun installed (PATH already configured in .zshrc)"
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
        if run_cmd stow -D -t "$HOME" home; then
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
    run_cmd stow -R -t "$HOME" home

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
        run_cmd stow --adopt -t "$HOME" home
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

    # Show what's still missing
    echo
    echo -e "${BOLD}Still needed (if not done above):${RESET}"
    local all_good=true

    if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}~${RESET} Run ${CYAN}gh auth login${RESET} to authenticate GitHub CLI"
        all_good=false
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
    echo -e "  1. Open a new terminal (or: ${CYAN}exec zsh${RESET})"
    echo -e "  2. The onboarding script will run automatically on first start"
    echo -e "  3. Create ${CYAN}~/.zshrc.private${RESET} for API keys and secrets"
    echo
    echo -e "${BOLD}Useful commands:${RESET}"
    echo -e "  ${CYAN}./install.sh --check${RESET}      Check prerequisites"
    echo -e "  ${CYAN}./install.sh --update${RESET}     Pull latest and restow"
    echo -e "  ${CYAN}./install.sh --uninstall${RESET}  Remove all symlinks"
    echo -e "  ${CYAN}./install.sh --dry-run${RESET}    Preview what would be done"
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
    echo -e "  ./install.sh --update     Pull latest changes and restow"
    echo -e "  ./install.sh --dry-run    Preview what would be done (no changes)"
    echo -e "  ./install.sh --force      Adopt existing files into repo (stow --adopt)"
    echo -e "  ./install.sh --help       Show this help"
    echo
    echo -e "${BOLD}What it does:${RESET}"
    echo -e "  1. Checks and installs prerequisites (Homebrew, stow, uv, etc.)"
    echo -e "  2. Installs Oh My Zsh, plugins, and Powerlevel10k (if missing)"
    echo -e "  3. Checks for file conflicts in ~/ (with auto-backup option)"
    echo -e "  4. Symlinks home/ → ~/ using GNU Stow"
    echo -e "  5. Symlinks platform-specific files (macOS Cursor/VSCode settings)"
    echo -e "  6. Sets up git identity, git-lfs, and GitHub CLI auth"
    echo -e "  7. Installs Python 3.13 via uv, nvm, pnpm (standalone)"
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
    --update)
        update
        ;;
    --dry-run)
        DRY_RUN=true
        main
        ;;
    --force)
        force_adopt
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
