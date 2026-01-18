# PLAN: Phase 1b — `.zsh_onboarding` Consolidation

> **Date Created:** 16/01/2025  
> **Last Updated:** 16/01/2025  
> **Status:** Ready for Implementation  
> **Author:** Claude (via claude.ai conversation)  
> **Executor:** Claude Code (PLAN MODE)  
> **Depends On:** Phase 1a (`.zsh_welcome` consolidation) — recommended to complete first

---

## Important: Working Directory Boundaries

```
⚠️  CRITICAL RULES FOR IMPLEMENTATION
────────────────────────────────────────────────────────────────────────────────
• ONLY operate within:     ~/CODE/fifty-shades-of-dotfiles/
• DO NOT access or read:   Files from the actual home folder (~/.zsh*, ~/.zshrc, etc.)
• Source files location:   fifty-shades-of-dotfiles/home/
• Temp folder (if needed): fifty-shades-of-dotfiles/Temp/
• Plan files location:     fifty-shades-of-dotfiles/docs/plans/

If files from outside the project folder are needed, STOP and request them to be 
copied into fifty-shades-of-dotfiles/Temp/
────────────────────────────────────────────────────────────────────────────────
```

---

## Objective

Create a unified `.zsh_onboarding` script that:
- Works on all 3 platforms (macOS, Linux, WSL)
- Uses appropriate package manager per OS
- Checks for and offers to install essential development tools
- Runs automatically on first shell start AND can be triggered manually
- Replaces the Linux-only `.zsh_linux_onboarding`

### Success Criteria

- [ ] Single `.zsh_onboarding` file works on macOS, Linux, and WSL
- [ ] Correct package manager detected and used per OS
- [ ] Homebrew check and install offer on macOS
- [ ] All essential tools checked (see tool list below)
- [ ] `run_onboarding` command available for manual triggering
- [ ] Auto-runs on first shell start (when `_ONBOARDING_COMPLETE` not set)
- [ ] All tests pass on macOS, Linux, and WSL
- [ ] `.zshrc` Section 4 simplified
- [ ] Documentation updated

---

## Current State Analysis

### Existing Files

| File | Exists? | Size | Purpose |
|------|---------|------|---------|
| `.zsh_linux_onboarding` | ✓ | ~6.4k | Interactive dependency checker for Linux only |
| `.zsh_mac_onboarding` | ✗ | — | Does not exist |
| `.zsh_wsl_onboarding` | ✗ | — | Does not exist |

### Current Problems

1. **Only Linux has onboarding** — Mac and WSL users must manually install tools
2. **No Homebrew bootstrapping** — Mac users assumed to have Homebrew already
3. **Missing tool checks** — `aria2c`, `eza`, `zoxide`, `uv` not checked
4. **Not manually triggerable** — Can't re-run onboarding after initial setup
5. **OS-specific file** — Doesn't follow the unified pattern of other dotfiles

---

## Feature Specifications

### 1. Package Manager Detection

| OS | Package Manager | Install Command |
|----|-----------------|-----------------|
| macOS | Homebrew | `brew install` |
| Ubuntu/Debian | apt | `sudo apt-get install -y` |
| Fedora | dnf | `sudo dnf install -y` |
| Arch | pacman | `sudo pacman -S --noconfirm` |
| openSUSE | zypper | `sudo zypper install -y` |

### 2. Tool Checklist

All tools checked on all platforms unless noted:

#### Essential Tools

| Tool | Command | Package (brew) | Package (apt) | Notes |
|------|---------|----------------|---------------|-------|
| git | `git` | `git` | `git` | Version control |
| curl | `curl` | `curl` | `curl` | HTTP client |
| unzip | `unzip` | `unzip` | `unzip` | Archive extraction |

#### User Experience Tools

| Tool | Command | Package (brew) | Package (apt) | Notes |
|------|---------|----------------|---------------|-------|
| eza | `eza` | `eza` | `eza` | Modern `ls` replacement (for `l`/`ll` aliases) |
| fzf | `fzf` | `fzf` | `fzf` | Fuzzy finder for shell history |
| jq | `jq` | `jq` | `jq` | JSON processor |
| direnv | `direnv` | `direnv` | `direnv` | Auto environment loading |
| zoxide | `zoxide` | `zoxide` | `zoxide` | Smart `cd` replacement |

#### CLI Tools

| Tool | Command | Package (brew) | Package (apt) | Notes |
|------|---------|----------------|---------------|-------|
| ripgrep | `rg` | `ripgrep` | `ripgrep` | Fast grep alternative |
| tree | `tree` | `tree` | `tree` | Directory tree viewer |
| neofetch | `neofetch` | `neofetch` | `neofetch` | System info display |
| ffmpeg | `ffmpeg` | `ffmpeg` | `ffmpeg` | Media processing |
| yt-dlp | `yt-dlp` | `yt-dlp` | `yt-dlp` | Video downloader |
| aria2c | `aria2c` | `aria2` | `aria2` | Fast download accelerator (for `yt` wrapper) |

#### Development Tool Managers

| Tool | Command | Install Method | Notes |
|------|---------|----------------|-------|
| nvm | `nvm` (function) | Official install script | Node.js version manager |
| pipx | `pipx` | Package manager | Python CLI tool installer |
| uv | `uv` | Official install script | Fast Python package manager |

#### Special Cases

| Tool | Handling |
|------|----------|
| Homebrew | macOS only — check first, offer to install if missing |
| Docker | All platforms — show guidance only (complex install) |
| lsd | Skip — replaced by `eza` in your aliases |

### 3. Execution Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| Auto | First shell start (`_ONBOARDING_COMPLETE` not set) | Full interactive onboarding |
| Manual | `run_onboarding` command | Full interactive onboarding (re-run anytime) |

### 4. No Verbosity Control

Onboarding is always interactive and shows everything. No `ZSH_ONBOARDING` variable needed.

---

## Implementation Tasks

### Task 1: Update `.zshrc` — Simplify Section 4

**File:** `home/.zshrc`  
**Section:** 4 (Onboarding & Dependency Checks)

**Find and replace this block:**

```bash
# ==============================================================================
# 4. Onboarding & Dependency Checks (Linux Only)
# ==============================================================================
# This runs AFTER the core path is set, so it can find installed tools.
if [[ "$IS_LINUX" == "true" && -f ~/.zsh_linux_onboarding && -z "$_ONBOARDING_COMPLETE" ]]; then
    source ~/.zsh_linux_onboarding
    export _ONBOARDING_COMPLETE=true
fi
```

**With this:**

```bash
# ==============================================================================
# 4. Onboarding & Dependency Checks
# ==============================================================================
# Unified onboarding for macOS, Linux, and WSL.
# Runs automatically on first shell start. Can also be triggered manually
# at any time by running: run_onboarding
#
# This runs AFTER the core path is set, so it can find installed tools.
if [[ -f ~/.zsh_onboarding ]]; then
    source ~/.zsh_onboarding
    # Auto-run on first shell start only
    if [[ -z "$_ONBOARDING_COMPLETE" && -t 1 ]]; then
        run_onboarding
        export _ONBOARDING_COMPLETE=true
    fi
fi
```

### Task 2: Create Unified `.zsh_onboarding`

**File:** `home/.zsh_onboarding` (NEW FILE)

**Full file content:**

```bash
# ~/.zsh_onboarding
# ==============================================================================
#  Unified Onboarding & Dependency Checker
# ==============================================================================
# Cross-platform onboarding script for macOS, Linux, and WSL.
# Checks for essential development tools and offers to install missing ones.
#
# USAGE:
#   - Runs automatically on first shell start
#   - Run manually anytime with: run_onboarding
#
# SUPPORTED PLATFORMS:
#   - macOS (via Homebrew)
#   - Linux: Ubuntu/Debian (apt), Fedora (dnf), Arch (pacman), openSUSE (zypper)
#   - WSL (same as Linux)
#
# Date Created: 16/01/2025
# ==============================================================================

# ------------------------------------------------------------------------------
# UI Helpers (self-contained for portability)
# ------------------------------------------------------------------------------
# These may already be defined in .zshrc, but we define them here too
# to ensure the script works standalone.
if [[ -z "$ok" ]]; then
    autoload -U colors && colors
    ok="$fg[green]"
    warn="$fg[yellow]"
    err="$fg[red]"
    info="$fg[cyan]"
    done="$reset_color"
fi

# ------------------------------------------------------------------------------
# Global Variables
# ------------------------------------------------------------------------------
_PKG_MANAGER_NAME=""
_PKG_MANAGER_CMD=""
_PKG_MANAGER_CHECK=""

# ------------------------------------------------------------------------------
# Package Manager Detection
# ------------------------------------------------------------------------------
_detect_package_manager() {
    _PKG_MANAGER_NAME=""
    _PKG_MANAGER_CMD=""
    _PKG_MANAGER_CHECK=""
    
    if [[ "$IS_MAC" == "true" ]]; then
        if command -v brew &>/dev/null; then
            _PKG_MANAGER_NAME="Homebrew"
            _PKG_MANAGER_CMD="brew install"
            _PKG_MANAGER_CHECK="brew list"
        else
            _PKG_MANAGER_NAME=""
            _PKG_MANAGER_CMD=""
        fi
    elif command -v apt-get &>/dev/null; then
        _PKG_MANAGER_NAME="apt"
        _PKG_MANAGER_CMD="sudo apt-get install -y"
        _PKG_MANAGER_CHECK="dpkg -l"
    elif command -v dnf &>/dev/null; then
        _PKG_MANAGER_NAME="dnf"
        _PKG_MANAGER_CMD="sudo dnf install -y"
        _PKG_MANAGER_CHECK="dnf list installed"
    elif command -v pacman &>/dev/null; then
        _PKG_MANAGER_NAME="pacman"
        _PKG_MANAGER_CMD="sudo pacman -S --noconfirm"
        _PKG_MANAGER_CHECK="pacman -Q"
    elif command -v zypper &>/dev/null; then
        _PKG_MANAGER_NAME="zypper"
        _PKG_MANAGER_CMD="sudo zypper install -y"
        _PKG_MANAGER_CHECK="zypper se --installed-only"
    else
        echo "${warn}Could not detect package manager. Automatic installation disabled.${done}"
        _PKG_MANAGER_NAME=""
        _PKG_MANAGER_CMD=""
    fi
}

# ------------------------------------------------------------------------------
# Homebrew Bootstrap (macOS only)
# ------------------------------------------------------------------------------
_ensure_homebrew() {
    if [[ "$IS_MAC" != "true" ]]; then
        return 0
    fi
    
    if command -v brew &>/dev/null; then
        return 0
    fi
    
    echo "${warn}Homebrew not found.${done}"
    echo "${info}Homebrew is the package manager for macOS and is required to install other tools.${done}"
    
    if [[ -t 1 ]]; then
        read "REPLY?${info}    👉 Would you like to install Homebrew now? [y/N] ${done}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "${info}Installing Homebrew...${done}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            if [[ $? -eq 0 ]]; then
                echo "${ok}    ✅ Homebrew installed successfully.${done}"
                # Add Homebrew to PATH for this session
                if [[ -d /opt/homebrew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                else
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                # Re-detect package manager
                _detect_package_manager
            else
                echo "${err}    ❌ Homebrew installation failed.${done}"
                return 1
            fi
        else
            echo "${warn}    Skipping Homebrew installation. Some tools cannot be installed automatically.${done}"
            return 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Generic Command Checker
# ------------------------------------------------------------------------------
# Usage: _ensure_command <command_to_check> <package_name_brew> <package_name_apt>
# If only one package name provided, it's used for all package managers.
_ensure_command() {
    local cmd_to_check="$1"
    local pkg_brew="${2:-$1}"
    local pkg_apt="${3:-$pkg_brew}"
    local pkg_name=""
    
    # Select package name based on package manager
    if [[ "$_PKG_MANAGER_NAME" == "Homebrew" ]]; then
        pkg_name="$pkg_brew"
    else
        pkg_name="$pkg_apt"
    fi
    
    # Check if command exists
    if command -v "$cmd_to_check" &>/dev/null; then
        return 0
    fi
    
    # Command not found — offer to install
    if [[ -n "$_PKG_MANAGER_CMD" && -t 1 ]]; then
        echo "${warn}Tool missing: '$cmd_to_check' not found.${done}"
        read "REPLY?${info}    👉 Install '$pkg_name' using ${_PKG_MANAGER_NAME}? [y/N] ${done}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "${info}    Installing '$pkg_name'...${done}"
            eval "$_PKG_MANAGER_CMD $pkg_name"
            if [[ $? -eq 0 ]]; then
                echo "${ok}    ✅ Successfully installed '$pkg_name'.${done}"
                rehash  # Refresh command cache
            else
                echo "${err}    ❌ Installation failed.${done}"
                return 1
            fi
        else
            echo "${warn}    Skipping '$pkg_name'.${done}"
        fi
    else
        echo "${warn}Tool missing: '$cmd_to_check'. Please install '$pkg_name' manually.${done}"
    fi
}

# ------------------------------------------------------------------------------
# NVM (Node Version Manager) — Special Handler
# ------------------------------------------------------------------------------
_ensure_nvm() {
    # NVM is a shell function, not a binary — check for its directory
    if [[ -d "$HOME/.nvm" ]]; then
        return 0
    fi
    
    if [[ -t 1 ]]; then
        echo "${warn}Tool missing: 'nvm' (Node Version Manager) not found.${done}"
        read "REPLY?${info}    👉 Install nvm from the official source? [y/N] ${done}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "${info}    Downloading and installing nvm...${done}"
            curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
            if [[ $? -eq 0 ]]; then
                echo "${ok}    ✅ nvm installed successfully.${done}"
                echo "${info}    Note: Restart your shell or run 'source ~/.zshrc' to use nvm.${done}"
            else
                echo "${err}    ❌ nvm installation failed.${done}"
            fi
        else
            echo "${warn}    Skipping nvm installation.${done}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# pipx — Special Handler
# ------------------------------------------------------------------------------
_ensure_pipx() {
    if command -v pipx &>/dev/null; then
        return 0
    fi
    
    if [[ -n "$_PKG_MANAGER_CMD" && -t 1 ]]; then
        echo "${warn}Tool missing: 'pipx' not found.${done}"
        read "REPLY?${info}    👉 Install 'pipx' using ${_PKG_MANAGER_NAME}? [y/N] ${done}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "${info}    Installing pipx...${done}"
            eval "$_PKG_MANAGER_CMD pipx"
            if [[ $? -eq 0 ]]; then
                echo "${ok}    ✅ pipx installed successfully.${done}"
                # Ensure pipx path is set up
                if command -v pipx &>/dev/null; then
                    pipx ensurepath &>/dev/null
                fi
            else
                echo "${err}    ❌ pipx installation failed.${done}"
            fi
        else
            echo "${warn}    Skipping pipx installation.${done}"
        fi
    else
        echo "${warn}Tool missing: 'pipx'. Please install it manually.${done}"
    fi
}

# ------------------------------------------------------------------------------
# uv (Python Package Manager) — Special Handler
# ------------------------------------------------------------------------------
_ensure_uv() {
    if command -v uv &>/dev/null; then
        return 0
    fi
    
    if [[ -t 1 ]]; then
        echo "${warn}Tool missing: 'uv' (fast Python package manager) not found.${done}"
        read "REPLY?${info}    👉 Install uv from the official source? [y/N] ${done}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "${info}    Downloading and installing uv...${done}"
            curl -LsSf https://astral.sh/uv/install.sh | sh
            if [[ $? -eq 0 ]]; then
                echo "${ok}    ✅ uv installed successfully.${done}"
                # Add to path for this session
                export PATH="$HOME/.local/bin:$PATH"
                rehash
            else
                echo "${err}    ❌ uv installation failed.${done}"
            fi
        else
            echo "${warn}    Skipping uv installation.${done}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Docker — Guidance Only
# ------------------------------------------------------------------------------
_show_docker_guidance() {
    if command -v docker &>/dev/null; then
        return 0
    fi
    
    echo "${warn}Tool missing: 'docker' not found.${done}"
    
    if [[ "$IS_MAC" == "true" ]]; then
        echo "${info}    Docker Desktop for Mac: https://docs.docker.com/desktop/install/mac-install/${done}"
    elif [[ "$IS_WSL" == "true" ]]; then
        echo "${info}    Docker Desktop for Windows (with WSL backend): https://docs.docker.com/desktop/install/windows-install/${done}"
        echo "${info}    Or install Docker Engine in WSL: https://docs.docker.com/engine/install/ubuntu/${done}"
    else
        echo "${info}    Docker Engine installation: https://docs.docker.com/engine/install/${done}"
    fi
}

# ------------------------------------------------------------------------------
# Main Onboarding Function
# ------------------------------------------------------------------------------
run_onboarding() {
    echo
    echo "${info}══════════════════════════════════════════════════════════════════════════════${done}"
    echo "${info}  🚀  Development Environment Onboarding${done}"
    echo "${info}══════════════════════════════════════════════════════════════════════════════${done}"
    echo
    
    # Display OS info
    if [[ "$IS_MAC" == "true" ]]; then
        echo "${info}Platform:${done} macOS $(sw_vers -productVersion 2>/dev/null)"
    elif [[ "$IS_WSL" == "true" ]]; then
        echo "${info}Platform:${done} WSL ($(lsb_release -ds 2>/dev/null || echo 'Linux'))"
    else
        echo "${info}Platform:${done} $(lsb_release -ds 2>/dev/null || echo 'Linux')"
    fi
    echo
    
    # Force Zsh to rebuild command cache
    rehash
    
    # --- macOS: Ensure Homebrew first ---
    if [[ "$IS_MAC" == "true" ]]; then
        echo "${info}Checking for Homebrew...${done}"
        _ensure_homebrew
        echo
    fi
    
    # --- Detect package manager ---
    echo "${info}Detecting package manager...${done}"
    _detect_package_manager
    
    if [[ -n "$_PKG_MANAGER_NAME" ]]; then
        echo "${ok}    ✓ Found: ${_PKG_MANAGER_NAME}${done}"
    else
        echo "${warn}    No supported package manager found. Manual installation required.${done}"
    fi
    echo
    
    # --- Essential Tools ---
    echo "${info}Checking essential tools...${done}"
    _ensure_command "git" "git" "git"
    _ensure_command "curl" "curl" "curl"
    _ensure_command "unzip" "unzip" "unzip"
    echo
    
    # --- User Experience Tools ---
    echo "${info}Checking user experience tools...${done}"
    _ensure_command "eza" "eza" "eza"
    _ensure_command "fzf" "fzf" "fzf"
    _ensure_command "jq" "jq" "jq"
    _ensure_command "direnv" "direnv" "direnv"
    _ensure_command "zoxide" "zoxide" "zoxide"
    echo
    
    # --- CLI Tools ---
    echo "${info}Checking CLI tools...${done}"
    _ensure_command "rg" "ripgrep" "ripgrep"
    _ensure_command "tree" "tree" "tree"
    _ensure_command "neofetch" "neofetch" "neofetch"
    _ensure_command "ffmpeg" "ffmpeg" "ffmpeg"
    _ensure_command "yt-dlp" "yt-dlp" "yt-dlp"
    _ensure_command "aria2c" "aria2" "aria2"
    echo
    
    # --- Development Tool Managers ---
    echo "${info}Checking development tool managers...${done}"
    _ensure_nvm
    _ensure_pipx
    _ensure_uv
    echo
    
    # --- Docker (guidance only) ---
    echo "${info}Checking Docker...${done}"
    _show_docker_guidance
    echo
    
    # --- Complete ---
    echo "${info}══════════════════════════════════════════════════════════════════════════════${done}"
    echo "${ok}  ✅  Onboarding complete!${done}"
    echo "${info}══════════════════════════════════════════════════════════════════════════════${done}"
    echo
    echo "${info}Tips:${done}"
    echo "  • Run ${info}run_onboarding${done} anytime to re-check dependencies"
    echo "  • Restart your shell or run ${info}source ~/.zshrc${done} if new tools were installed"
    echo
}

# ------------------------------------------------------------------------------
# Export the function so it's available as a command
# ------------------------------------------------------------------------------
# The function is now defined and can be called manually with: run_onboarding
# Auto-execution is handled by .zshrc Section 4
```

### Task 3: Verify File Creation

After creating the file, verify:

```bash
# Check file exists
ls -la home/.zsh_onboarding

# Check for syntax errors
zsh -n home/.zsh_onboarding && echo "✓ Syntax OK" || echo "✗ Syntax Error"

# Check .zshrc still valid
zsh -n home/.zshrc && echo "✓ Syntax OK" || echo "✗ Syntax Error"
```

---

## Testing Plan

### Pre-Flight Checks

```bash
# Navigate to project
cd ~/CODE/fifty-shades-of-dotfiles

# Verify source file exists
ls -la home/.zsh_linux_onboarding

# Verify .zshrc exists
ls -la home/.zshrc
```

### Unit Tests

#### Test 1: Syntax Validation

```bash
# Check new file syntax
zsh -n home/.zsh_onboarding && echo "✓ Syntax OK" || echo "✗ Syntax Error"

# Check .zshrc syntax
zsh -n home/.zshrc && echo "✓ Syntax OK" || echo "✗ Syntax Error"
```

#### Test 2: Function Definition Check

```bash
# Verify run_onboarding function is defined
(
    source home/.zshrc 2>/dev/null || true
    source home/.zsh_onboarding
    type run_onboarding
)
# Expected: "run_onboarding is a shell function"
```

#### Test 3: Package Manager Detection — macOS

```bash
# Simulate macOS
(
    export IS_MAC="true"
    export IS_WSL="false"
    export IS_LINUX="false"
    source home/.zsh_onboarding
    _detect_package_manager
    echo "Manager: $_PKG_MANAGER_NAME"
    echo "Command: $_PKG_MANAGER_CMD"
)
# Expected (if brew installed): Manager: Homebrew, Command: brew install
```

#### Test 4: Package Manager Detection — Linux

```bash
# Simulate Linux with apt
(
    export IS_MAC="false"
    export IS_WSL="false"
    export IS_LINUX="true"
    source home/.zsh_onboarding
    _detect_package_manager
    echo "Manager: $_PKG_MANAGER_NAME"
)
# Expected: Manager: apt (or dnf, pacman, etc. based on system)
```

#### Test 5: Manual Trigger

```bash
# Test that run_onboarding can be called manually
(
    export IS_MAC="true"  # or appropriate OS
    source home/.zsh_onboarding
    # Just check function exists, don't run full onboarding
    type run_onboarding &>/dev/null && echo "✓ run_onboarding available"
)
```

### Integration Tests

These require deployment to actual machines:

#### macOS Integration Test

```bash
# On actual macOS after deploying:
# 1. Copy home/.zsh_onboarding to ~/.zsh_onboarding
# 2. Update ~/.zshrc Section 4
# 3. Unset _ONBOARDING_COMPLETE: unset _ONBOARDING_COMPLETE
# 4. Open new terminal

# Expected: Full onboarding runs with Homebrew check first

# Test manual trigger:
run_onboarding
# Expected: Full onboarding runs again
```

#### Linux Integration Test

```bash
# On actual Linux after deploying:
# 1. Copy home/.zsh_onboarding to ~/.zsh_onboarding
# 2. Update ~/.zshrc Section 4
# 3. Unset _ONBOARDING_COMPLETE: unset _ONBOARDING_COMPLETE
# 4. Open new terminal

# Expected: Full onboarding runs with apt/dnf/pacman detection

# Test manual trigger:
run_onboarding
# Expected: Full onboarding runs again
```

#### WSL Integration Test

```bash
# On actual WSL after deploying:
# 1. Copy home/.zsh_onboarding to ~/.zsh_onboarding
# 2. Update ~/.zshrc Section 4
# 3. Unset _ONBOARDING_COMPLETE: unset _ONBOARDING_COMPLETE
# 4. Open new terminal

# Expected: Full onboarding runs, shows WSL platform

# Test manual trigger:
run_onboarding
# Expected: Full onboarding runs again
```

### Regression Tests

```bash
# Ensure OS detection variables still work
echo "IS_MAC=$IS_MAC IS_WSL=$IS_WSL IS_LINUX=$IS_LINUX"

# Ensure color variables work
echo "${ok}green${done} ${warn}yellow${done} ${err}red${done} ${info}cyan${done}"

# Ensure existing tools still detected
command -v git && echo "git: OK"
command -v curl && echo "curl: OK"
```

---

## Post-Implementation Verification Checklist

- [ ] `home/.zsh_onboarding` exists and has no syntax errors
- [ ] `home/.zshrc` Section 4 simplified to source single file
- [ ] `run_onboarding` function is available after sourcing
- [ ] Package manager correctly detected on macOS (Homebrew)
- [ ] Package manager correctly detected on Linux (apt/dnf/pacman/zypper)
- [ ] Homebrew install prompt appears on macOS if Homebrew missing
- [ ] All essential tools checked: git, curl, unzip
- [ ] All UX tools checked: eza, fzf, jq, direnv, zoxide
- [ ] All CLI tools checked: ripgrep, tree, neofetch, ffmpeg, yt-dlp, aria2c
- [ ] All dev managers checked: nvm, pipx, uv
- [ ] Docker guidance shown (not auto-install)
- [ ] Manual `run_onboarding` command works
- [ ] Auto-run on first shell works (when `_ONBOARDING_COMPLETE` unset)
- [ ] Subsequent shells don't re-run onboarding (flag persists)

---

## Post-Migration Cleanup (Manual)

> ⚠️ **DO NOT AUTO-DELETE** — Perform manually after verification

After confirming everything works correctly on all platforms:

**Files to delete:**
```
home/.zsh_linux_onboarding    → Replaced by home/.zsh_onboarding
```

**Why delete:**
- Functionality consolidated into unified file
- Keeping it causes no harm but adds clutter
- The new file handles all OS-specific logic internally

**How to delete:**
```bash
cd ~/CODE/fifty-shades-of-dotfiles
rm home/.zsh_linux_onboarding
git add -A
git commit -m "chore: remove legacy Linux onboarding (consolidated into .zsh_onboarding)"
```

---

## README Documentation Update

Add/update this section in `README.md`:

```markdown
## Onboarding & Dependency Management

The shell includes an automatic onboarding system that checks for required tools and offers to install them.

### Automatic Onboarding

On first shell start (on a new machine), the onboarding script runs automatically and:

1. Detects your OS and package manager
2. Checks for essential development tools
3. Offers to install missing tools interactively

### Manual Onboarding

Re-run onboarding anytime to check for missing tools:

```bash
run_onboarding
```

### Supported Package Managers

| OS | Package Manager |
|----|-----------------|
| macOS | Homebrew (auto-installs if missing) |
| Ubuntu/Debian | apt |
| Fedora | dnf |
| Arch | pacman |
| openSUSE | zypper |

### Tools Checked

**Essential:** git, curl, unzip

**User Experience:** eza, fzf, jq, direnv, zoxide

**CLI Tools:** ripgrep, tree, neofetch, ffmpeg, yt-dlp, aria2

**Development Managers:** nvm, pipx, uv

**Special:** Docker (guidance only — requires manual installation)

### Skipping Onboarding

To prevent auto-onboarding on a fresh shell:

```bash
export _ONBOARDING_COMPLETE=true
```
```

---

## Summary of Files Changed

| File | Action | Description |
|------|--------|-------------|
| `home/.zshrc` | MODIFY | Simplify Section 4 |
| `home/.zsh_onboarding` | CREATE | New unified onboarding script |
| `README.md` | MODIFY | Add onboarding documentation |
| `home/.zsh_linux_onboarding` | DELETE (manual) | Legacy — after verification |

---

## Approval

- [ ] Plan reviewed
- [ ] Ready to proceed with implementation

**Next Step:** Execute this plan in Claude Code using PLAN MODE, then switch to edit mode to implement changes.

---

## Execution Order

**Recommended sequence:**

1. Complete Phase 1a (`.zsh_welcome`) first
2. Then execute Phase 1b (this plan)
3. Test both together on all platforms
4. Delete legacy files only after full verification
