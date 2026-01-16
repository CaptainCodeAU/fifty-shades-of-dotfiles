# PLAN: Phase 1a — `.zsh_welcome` Consolidation

> **Date Created:** 16/01/2025  
> **Last Updated:** 16/01/2025  
> **Status:** Ready for Implementation  
> **Author:** Claude (via claude.ai conversation)  
> **Executor:** Claude Code (PLAN MODE)

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

Consolidate three separate welcome files into a single unified `.zsh_welcome` file with:
- OS-aware logic (macOS, Linux, WSL)
- Independent verbosity controls for welcome message and quick reference
- Auto-detection for SSH/tmux sessions
- Enhanced features (disk space, Homebrew, GPU detection)
- Comprehensive testing

### Success Criteria

- [ ] Single `.zsh_welcome` file replaces three OS-specific files
- [ ] All verbosity modes work correctly (`full`, `minimal`, `none`)
- [ ] Auto-detection correctly identifies SSH and tmux sessions
- [ ] Disk space warning displays when threshold exceeded
- [ ] Homebrew check works on macOS
- [ ] GPU detection works on WSL/Linux
- [ ] Quick reference has independent verbosity control
- [ ] All tests pass on macOS, Linux, and WSL
- [ ] `.zshrc` updated to source single file
- [ ] Documentation updated

---

## Current State Analysis

### Files to Consolidate

| File | Location | Size |
|------|----------|------|
| `.zsh_mac_welcome` | `home/.zsh_mac_welcome` | ~2.9k |
| `.zsh_linux_welcome` | `home/.zsh_linux_welcome` | ~4.1k |
| `.zsh_wsl_welcome` | `home/.zsh_wsl_welcome` | ~4.0k |

### Current Problems

1. **Code duplication** — 90%+ identical code across 3 files
2. **Inconsistencies:**
   - WSL hardcodes `3.13` instead of using `$PYTHON_DEFAULT_VERSION`
   - Docker helper list differs between files
   - Mixed usage of `command which` vs `command -v`
3. **Missing features:**
   - No disk space awareness
   - No Homebrew health check (Mac)
   - No GPU detection (WSL/Linux)
   - No tmux function references
   - No verbosity control
4. **No quiet mode for SSH/tmux sessions**

---

## Feature Specifications

### 1. Verbosity Controls (Independent Variables)

Two environment variables control output independently:

#### `ZSH_WELCOME` — Controls Environment Overview

| Value | Behavior |
|-------|----------|
| `full` | Full multi-line environment overview (default) |
| `minimal` | Single-line compact status |
| `none` | No environment overview shown |

#### `ZSH_WELCOME_QUICKREF` — Controls Quick Reference

| Value | Behavior |
|-------|----------|
| `full` | Multi-line categorized quick reference (default) |
| `minimal` | Compact 2-line category hints |
| `none` | No quick reference shown |

#### Variable Location in `.zshrc`

These variables should be defined in **Section 2 (Environment Variables)** for easy access:

```bash
# ==============================================================================
# 2. Environment Variables
# ==============================================================================

# --- Welcome Message Verbosity ---
# Options: full (default), minimal, none
# Auto-detects SSH/tmux and defaults to 'minimal' in those contexts
: ${ZSH_WELCOME:=""}  # Empty = auto-detect

# --- Quick Reference Verbosity ---
# Options: full (default), minimal, none
# Independent of ZSH_WELCOME
: ${ZSH_WELCOME_QUICKREF:="full"}

# --- Disk Space Warning Threshold ---
# Warn if disk usage exceeds this percentage (default: 90)
: ${ZSH_WELCOME_DISK_WARN:=90}
```

### 2. Auto-Detection Logic

When `ZSH_WELCOME` is empty (not explicitly set), auto-detect context:

```bash
# Priority order (first match wins):
1. If ZSH_WELCOME is explicitly set → use that value
2. If inside SSH session ($SSH_CONNECTION is set) → default to "minimal"
3. If inside tmux ($TMUX is set) → default to "minimal"
4. Otherwise → default to "full"
```

#### Why Auto-Detection?

| Scenario | Auto Default | Rationale |
|----------|--------------|-----------|
| New terminal window | `full` | First shell of the day, show full info |
| SSH into machine | `minimal` | You're remoting in, you know your setup |
| New tmux pane | `minimal` | You've seen the banner in first pane |
| Explicit override | (your setting) | User knows best |

### 3. Environment Overview (`show_welcome`)

#### OS Information (OS-Aware)

| OS | Display |
|----|---------|
| macOS | `macOS: 15.1.1` via `sw_vers -productVersion` |
| Linux | `Distro: Ubuntu 24.04.1 LTS` via `lsb_release -ds` + kernel |
| WSL | `Distro: Ubuntu 24.04.1 LTS` via `lsb_release -ds` + kernel |

#### Disk Space Check

```bash
# Display format:
Disk: 45% used (234GB free)           # Normal — default color
Disk: 92% used (12GB free) ⚠️          # Warning — yellow (when > threshold)
```

#### Tool Status Checks

| Tool | Check Method | Display |
|------|--------------|---------|
| **uv** | `command -v uv` | Version + Python status |
| **Node** | `nvm current` | Version + npm/pnpm versions |
| **Docker** | `docker ps 2>/dev/null` | Running / Not Running |
| **Homebrew** | `command -v brew` (Mac only) | OK / Not Found |
| **GPU** | `nvidia-smi` (WSL/Linux only) | Available / Not Detected |

### 4. Quick Reference (`show_quick_reference`)

#### Full Mode Output

```
🚀  Quick Reference:
    Python:  python_new_project, python_setup, python_delete
    Node:    node_new_project, node_setup, node_clean
    Docker:  docker_help | Tmux: tdev, gs, gstatus
    Media:   yt --help
```

#### Minimal Mode Output (Option B — Compact 2 Lines)

```
💡 Python: python_new_project | Node: node_new_project | Docker: docker_help
   Tmux: tdev, gs | Media: yt --help
```

#### None Mode

No output.

### 5. Output Examples

#### Full Welcome + Full Quick Reference (Default)

```
🛡️  macOS Environment Overview:
    macOS: 15.1.1
    Disk: 45% used (234GB free)
    uv: 0.5.1 (Python 3.13: ✓)
    Node: v22.11.0 (npm: 10.9.0, pnpm: 9.14.2)
    Docker: Running
    Homebrew: OK

🚀  Quick Reference:
    Python:  python_new_project, python_setup, python_delete
    Node:    node_new_project, node_setup, node_clean
    Docker:  docker_help | Tmux: tdev, gs, gstatus
    Media:   yt --help
```

#### Minimal Welcome + None Quick Reference (SSH/Tmux Auto)

```
🛡️  macOS | Disk 45% | uv ✓ | Node v22 | Docker ✓
```

#### Full Welcome + Minimal Quick Reference

```
🛡️  macOS Environment Overview:
    macOS: 15.1.1
    Disk: 45% used (234GB free)
    uv: 0.5.1 (Python 3.13: ✓)
    Node: v22.11.0 (npm: 10.9.0, pnpm: 9.14.2)
    Docker: Running
    Homebrew: OK

💡 Python: python_new_project | Node: node_new_project | Docker: docker_help
   Tmux: tdev, gs | Media: yt --help
```

#### None Welcome + None Quick Reference

(No output)

---

## Implementation Tasks

### Task 1: Update `.zshrc` — Add Environment Variables

**File:** `home/.zshrc`  
**Section:** 2 (Environment Variables)  
**Action:** Add new variables after the Python section

**Find this block:**
```bash
# --- Python ---
export PIP_REQUIRE_VIRTUALENV=true
export PIP_DISABLE_PIP_VERSION_CHECK=1
```

**Add after it:**
```bash
# --- Welcome Message Settings ---
# ZSH_WELCOME: Controls environment overview display
#   - "full"    : Complete multi-line overview (default for new terminals)
#   - "minimal" : Single-line compact status (default for SSH/tmux)
#   - "none"    : No overview displayed
#   - ""        : Auto-detect based on context (recommended)
: ${ZSH_WELCOME:=""}

# ZSH_WELCOME_QUICKREF: Controls quick reference display (independent of ZSH_WELCOME)
#   - "full"    : Multi-line categorized reference
#   - "minimal" : Compact 2-line hints
#   - "none"    : No quick reference displayed
: ${ZSH_WELCOME_QUICKREF:="full"}

# ZSH_WELCOME_DISK_WARN: Disk usage percentage threshold for warning (default: 90)
: ${ZSH_WELCOME_DISK_WARN:=90}
```

### Task 2: Update `.zshrc` — Simplify Section 10

**File:** `home/.zshrc`  
**Section:** 10 (Welcome / Onboarding Scripts)

**Replace this:**
```bash
# ==============================================================================
# 10. Welcome / Onboarding Scripts
# ==============================================================================
# Only run in interactive shells on first load.
if [[ -z "$_WELCOME_MESSAGE_SHOWN" && -t 1 ]]; then
    if [[ "$IS_MAC" == "true" ]] && [ -f ~/.zsh_mac_welcome ]; then
        source ~/.zsh_mac_welcome
    elif [[ "$IS_WSL" == "true" ]] && [ -f ~/.zsh_wsl_welcome ]; then
        source ~/.zsh_wsl_welcome
    elif [[ "$IS_LINUX" == "true" ]] && [ -f ~/.zsh_linux_welcome ]; then
        source ~/.zsh_linux_welcome
    fi
    # Set a flag to prevent this from running again in the same session
    export _WELCOME_MESSAGE_SHOWN=true
fi
```

**With this:**
```bash
# ==============================================================================
# 10. Welcome / Onboarding Scripts
# ==============================================================================
# Only run in interactive shells on first load.
# Verbosity controlled by ZSH_WELCOME and ZSH_WELCOME_QUICKREF (see Section 2).
# Auto-detects SSH/tmux sessions and adjusts verbosity accordingly.
if [[ -z "$_WELCOME_MESSAGE_SHOWN" && -t 1 ]]; then
    [ -f ~/.zsh_welcome ] && source ~/.zsh_welcome
    export _WELCOME_MESSAGE_SHOWN=true
fi
```

### Task 3: Create Unified `.zsh_welcome`

**File:** `home/.zsh_welcome` (NEW FILE)

**Full file content follows:**

```bash
# ~/.zsh_welcome
# ==============================================================================
#  Unified Welcome & Environment Overview Script
# ==============================================================================
# Cross-platform welcome message for macOS, Linux, and WSL.
#
# VERBOSITY CONTROL (set in ~/.zshrc or ~/.zshrc.private):
#   ZSH_WELCOME          - Environment overview: "full", "minimal", "none", or "" (auto)
#   ZSH_WELCOME_QUICKREF - Quick reference: "full", "minimal", "none"
#   ZSH_WELCOME_DISK_WARN - Disk warning threshold percentage (default: 90)
#
# AUTO-DETECTION:
#   When ZSH_WELCOME="" (empty/unset), automatically uses:
#   - "minimal" for SSH sessions ($SSH_CONNECTION)
#   - "minimal" for tmux sessions ($TMUX)
#   - "full" otherwise
#
# Date Created: 16/01/2025
# ==============================================================================

# ------------------------------------------------------------------------------
# Verbosity Resolution
# ------------------------------------------------------------------------------
_resolve_welcome_verbosity() {
    # If explicitly set, use that value
    if [[ -n "$ZSH_WELCOME" ]]; then
        echo "$ZSH_WELCOME"
        return
    fi
    
    # Auto-detect: SSH session → minimal
    if [[ -n "$SSH_CONNECTION" ]]; then
        echo "minimal"
        return
    fi
    
    # Auto-detect: tmux session → minimal
    if [[ -n "$TMUX" ]]; then
        echo "minimal"
        return
    fi
    
    # Default: full
    echo "full"
}

# Store resolved verbosity
_WELCOME_VERBOSITY=$(_resolve_welcome_verbosity)
: ${ZSH_WELCOME_QUICKREF:="full"}
: ${ZSH_WELCOME_DISK_WARN:=90}

# ------------------------------------------------------------------------------
# Helper: Get Disk Usage
# ------------------------------------------------------------------------------
_get_disk_usage() {
    local usage_pct free_space
    
    if [[ "$IS_MAC" == "true" ]]; then
        # macOS: use df on root volume
        usage_pct=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}')
        free_space=$(df -h / | awk 'NR==2 {print $4}')
    else
        # Linux/WSL: use df on home directory
        usage_pct=$(df -h ~ | awk 'NR==2 {gsub(/%/,""); print $5}')
        free_space=$(df -h ~ | awk 'NR==2 {print $4}')
    fi
    
    echo "${usage_pct}:${free_space}"
}

# ------------------------------------------------------------------------------
# Helper: Check GPU Availability (WSL/Linux only)
# ------------------------------------------------------------------------------
_check_gpu() {
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        echo "available"
    else
        echo "none"
    fi
}

# ------------------------------------------------------------------------------
# Full Welcome Display
# ------------------------------------------------------------------------------
_show_welcome_full() {
    echo
    
    # --- OS Header ---
    if [[ "$IS_MAC" == "true" ]]; then
        echo "${info}🛡️  macOS Environment Overview:${done}"
        echo "    macOS: $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    elif [[ "$IS_WSL" == "true" ]]; then
        echo "${info}🛡️  WSL Environment Overview:${done}"
        if command -v lsb_release &>/dev/null; then
            echo "    Distro: $(lsb_release -ds 2>/dev/null)"
        fi
        echo "    Kernel: $(uname -r)"
    else
        echo "${info}🛡️  Linux Environment Overview:${done}"
        if command -v lsb_release &>/dev/null; then
            echo "    Distro: $(lsb_release -ds 2>/dev/null)"
        fi
        echo "    Kernel: $(uname -r)"
    fi
    
    # --- Disk Space ---
    local disk_info=$(_get_disk_usage)
    local disk_pct="${disk_info%%:*}"
    local disk_free="${disk_info##*:}"
    
    if [[ "$disk_pct" -ge "$ZSH_WELCOME_DISK_WARN" ]]; then
        echo "    Disk: ${warn}${disk_pct}% used${done} (${disk_free} free) ⚠️"
    else
        echo "    Disk: ${disk_pct}% used (${disk_free} free)"
    fi
    
    # --- uv (Python) ---
    if command -v uv &>/dev/null; then
        local uv_version=$(uv --version 2>/dev/null | awk '{print $2}')
        local uv_python_path=""
        if command -v get_uv_python_path &>/dev/null; then
            uv_python_path=$(get_uv_python_path "${PYTHON_DEFAULT_VERSION}" 2>/dev/null)
        fi
        if [[ -n "$uv_python_path" && -x "$uv_python_path" ]]; then
            local uv_python_version=$("$uv_python_path" --version 2>/dev/null)
            echo "    uv: ${ok}${uv_version}${done} (Python ${PYTHON_DEFAULT_VERSION}: ${uv_python_version})"
        else
            echo "    uv: ${ok}${uv_version}${done} (Python ${PYTHON_DEFAULT_VERSION}: ${warn}not installed${done})"
        fi
    else
        echo "    uv: ${err}Not Found${done}"
    fi
    
    # --- Node.js ---
    if command -v nvm &>/dev/null; then
        local active_node=$(nvm current 2>/dev/null)
        if [[ "$active_node" == "none" || -z "$active_node" ]]; then
            local default_node=$(nvm version default 2>/dev/null)
            echo "    Node: ${warn}None active${done} (default: ${default_node:-N/A})"
        else
            local npm_ver=$(npm -v 2>/dev/null || echo 'N/A')
            local pnpm_ver=$(pnpm -v 2>/dev/null || echo 'N/A')
            echo "    Node: ${ok}${active_node}${done} (npm: ${npm_ver}, pnpm: ${pnpm_ver})"
        fi
    else
        echo "    Node: ${err}nvm not found${done}"
    fi
    
    # --- Docker ---
    if command -v docker &>/dev/null && docker ps &>/dev/null 2>&1; then
        echo "    Docker: ${ok}Running${done}"
    elif command -v docker &>/dev/null; then
        if [[ "$IS_MAC" == "true" ]]; then
            echo "    Docker: ${warn}Not Running${done}"
        else
            echo "    Docker: ${warn}Not Running${done} (try: sudo usermod -aG docker \$USER)"
        fi
    else
        echo "    Docker: ${err}Not Installed${done}"
    fi
    
    # --- Homebrew (macOS only) ---
    if [[ "$IS_MAC" == "true" ]]; then
        if command -v brew &>/dev/null; then
            echo "    Homebrew: ${ok}OK${done}"
        else
            echo "    Homebrew: ${err}Not Found${done}"
        fi
    fi
    
    # --- GPU (WSL/Linux only) ---
    if [[ "$IS_WSL" == "true" || "$IS_LINUX" == "true" ]]; then
        local gpu_status=$(_check_gpu)
        if [[ "$gpu_status" == "available" ]]; then
            echo "    GPU: ${ok}NVIDIA Available${done}"
        else
            echo "    GPU: ${warn}Not Detected${done}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Minimal Welcome Display (Single Line)
# ------------------------------------------------------------------------------
_show_welcome_minimal() {
    local parts=()
    
    # OS
    if [[ "$IS_MAC" == "true" ]]; then
        parts+=("macOS")
    elif [[ "$IS_WSL" == "true" ]]; then
        parts+=("WSL")
    else
        parts+=("Linux")
    fi
    
    # Disk
    local disk_info=$(_get_disk_usage)
    local disk_pct="${disk_info%%:*}"
    if [[ "$disk_pct" -ge "$ZSH_WELCOME_DISK_WARN" ]]; then
        parts+=("${warn}Disk ${disk_pct}%${done}")
    else
        parts+=("Disk ${disk_pct}%")
    fi
    
    # uv
    if command -v uv &>/dev/null; then
        parts+=("${ok}uv ✓${done}")
    else
        parts+=("${err}uv ✗${done}")
    fi
    
    # Node
    if command -v nvm &>/dev/null; then
        local node_ver=$(nvm current 2>/dev/null)
        if [[ -n "$node_ver" && "$node_ver" != "none" ]]; then
            parts+=("${ok}Node ${node_ver%%.*}${done}")
        else
            parts+=("${warn}Node -${done}")
        fi
    else
        parts+=("${err}Node ✗${done}")
    fi
    
    # Docker
    if command -v docker &>/dev/null && docker ps &>/dev/null 2>&1; then
        parts+=("${ok}Docker ✓${done}")
    else
        parts+=("${warn}Docker -${done}")
    fi
    
    # Homebrew (Mac only)
    if [[ "$IS_MAC" == "true" ]]; then
        if command -v brew &>/dev/null; then
            parts+=("${ok}Brew ✓${done}")
        fi
    fi
    
    # GPU (WSL/Linux only)
    if [[ "$IS_WSL" == "true" || "$IS_LINUX" == "true" ]]; then
        if [[ "$(_check_gpu)" == "available" ]]; then
            parts+=("${ok}GPU ✓${done}")
        fi
    fi
    
    echo "🛡️  ${(j: | :)parts}"
}

# ------------------------------------------------------------------------------
# Quick Reference — Full
# ------------------------------------------------------------------------------
_show_quickref_full() {
    echo
    echo "${info}🚀  Quick Reference:${done}"
    echo "    Python:  python_new_project, python_setup, python_delete"
    echo "    Node:    node_new_project, node_setup, node_clean"
    echo "    Docker:  docker_help | Tmux: tdev, gs, gstatus"
    echo "    Media:   yt --help"
}

# ------------------------------------------------------------------------------
# Quick Reference — Minimal (Compact 2 Lines)
# ------------------------------------------------------------------------------
_show_quickref_minimal() {
    echo
    echo "${info}💡 Python: python_new_project | Node: node_new_project | Docker: docker_help${done}"
    echo "   Tmux: tdev, gs | Media: yt --help"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

# Show welcome based on verbosity
case "$_WELCOME_VERBOSITY" in
    full)
        _show_welcome_full
        ;;
    minimal)
        _show_welcome_minimal
        ;;
    none|"")
        # No welcome output
        ;;
esac

# Show quick reference based on its own verbosity setting
# (Only show if welcome is not 'none' — if user wants no welcome, probably wants no quickref either)
if [[ "$_WELCOME_VERBOSITY" != "none" ]]; then
    case "$ZSH_WELCOME_QUICKREF" in
        full)
            _show_quickref_full
            ;;
        minimal)
            _show_quickref_minimal
            ;;
        none|"")
            # No quick reference output
            ;;
    esac
fi

# Add blank line for spacing (only if we showed something)
if [[ "$_WELCOME_VERBOSITY" != "none" ]]; then
    echo
fi

# ------------------------------------------------------------------------------
# uv Python Install Prompt
# ------------------------------------------------------------------------------
# Only prompt if:
# 1. Welcome verbosity is 'full' (not in SSH/tmux quick mode)
# 2. Shell is interactive
# 3. Python version is actually missing
if [[ "$_WELCOME_VERBOSITY" == "full" ]]; then
    if command -v get_uv_python_path &>/dev/null && ! get_uv_python_path "${PYTHON_DEFAULT_VERSION}" &>/dev/null; then
        echo "${warn}⚠️  Default Python (${PYTHON_DEFAULT_VERSION}) not found in 'uv' cache.${done}"
        if [[ -t 1 ]]; then
            read "REPLY?    👉 Would you like to run 'uv python install python@${PYTHON_DEFAULT_VERSION}' now? [y/N] "
            case "$REPLY" in
                [yY][eE][sS]|[yY])
                    uv python install "python@${PYTHON_DEFAULT_VERSION}"
                    ;;
                *)
                    echo "${warn}    Skipping 'uv' Python installation.${done}"
                    ;;
            esac
        fi
    fi
fi

# Cleanup internal variables
unset _WELCOME_VERBOSITY
```

### Task 4: Verify File Creation

After creating the file, verify:
- File exists at `home/.zsh_welcome`
- File has correct permissions (readable)
- No syntax errors: `zsh -n home/.zsh_welcome`

---

## Testing Plan

### Pre-Flight Checks

Before making any changes, verify current state:

```bash
# Navigate to project
cd ~/CODE/fifty-shades-of-dotfiles

# Verify source files exist
ls -la home/.zsh_mac_welcome home/.zsh_linux_welcome home/.zsh_wsl_welcome

# Verify .zshrc exists
ls -la home/.zshrc
```

### Unit Tests

Run these tests after implementation:

#### Test 1: Syntax Validation

```bash
# Check for syntax errors in new file
zsh -n home/.zsh_welcome && echo "✓ Syntax OK" || echo "✗ Syntax Error"

# Check .zshrc still valid
zsh -n home/.zshrc && echo "✓ Syntax OK" || echo "✗ Syntax Error"
```

#### Test 2: Verbosity — Full Mode

```bash
# Simulate full mode
(
    source home/.zshrc  # Load variables
    export ZSH_WELCOME="full"
    export ZSH_WELCOME_QUICKREF="full"
    export IS_MAC="true"  # or IS_LINUX/IS_WSL
    source home/.zsh_welcome
)
# Expected: Full multi-line output with quick reference
```

#### Test 3: Verbosity — Minimal Mode

```bash
# Simulate minimal mode
(
    source home/.zshrc
    export ZSH_WELCOME="minimal"
    export ZSH_WELCOME_QUICKREF="none"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Single line output, no quick reference
```

#### Test 4: Verbosity — None Mode

```bash
# Simulate none mode
(
    source home/.zshrc
    export ZSH_WELCOME="none"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: No output
```

#### Test 5: Auto-Detection — SSH

```bash
# Simulate SSH session (should auto-default to minimal)
(
    source home/.zshrc
    export ZSH_WELCOME=""  # Empty = auto-detect
    export SSH_CONNECTION="fake-connection"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Minimal output (single line)
```

#### Test 6: Auto-Detection — Tmux

```bash
# Simulate tmux session (should auto-default to minimal)
(
    source home/.zshrc
    export ZSH_WELCOME=""  # Empty = auto-detect
    export TMUX="/tmp/fake-tmux"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Minimal output (single line)
```

#### Test 7: Quick Reference Independence

```bash
# Full welcome but no quick reference
(
    source home/.zshrc
    export ZSH_WELCOME="full"
    export ZSH_WELCOME_QUICKREF="none"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Full environment overview, no quick reference

# Minimal welcome but full quick reference
(
    source home/.zshrc
    export ZSH_WELCOME="minimal"
    export ZSH_WELCOME_QUICKREF="full"
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Single line status + full quick reference below
```

#### Test 8: Disk Space Warning

```bash
# Test disk warning threshold
(
    source home/.zshrc
    export ZSH_WELCOME="full"
    export ZSH_WELCOME_DISK_WARN=1  # Set very low to trigger warning
    export IS_MAC="true"
    source home/.zsh_welcome
)
# Expected: Disk line shows warning emoji and yellow color
```

### Integration Tests

These require actual deployment to test environments:

#### macOS Test

```bash
# On actual macOS machine after deploying:
# 1. Copy home/.zsh_welcome to ~/.zsh_welcome
# 2. Update ~/.zshrc Section 10
# 3. Open new terminal
# Expected: Full welcome with Homebrew status

# Test SSH simulation
SSH_CONNECTION="test" zsh -i -c exit
# Expected: Minimal output
```

#### Linux Test

```bash
# On actual Linux machine after deploying:
# 1. Copy home/.zsh_welcome to ~/.zsh_welcome
# 2. Update ~/.zshrc Section 10
# 3. Open new terminal
# Expected: Full welcome with GPU status (if available)
```

#### WSL Test

```bash
# On actual WSL after deploying:
# 1. Copy home/.zsh_welcome to ~/.zsh_welcome
# 2. Update ~/.zshrc Section 10
# 3. Open new terminal
# Expected: Full welcome with GPU status (if available)

# Test tmux simulation
TMUX="/tmp/test" zsh -i -c exit
# Expected: Minimal output
```

### Regression Tests

Verify nothing broke:

```bash
# Ensure old variables still work
echo $IS_MAC $IS_WSL $IS_LINUX  # Should show true/false values

# Ensure color variables work
echo "${ok}green${done} ${warn}yellow${done} ${err}red${done}"

# Ensure PYTHON_DEFAULT_VERSION is set
echo $PYTHON_DEFAULT_VERSION  # Should show version like 3.13
```

---

## Post-Implementation Verification Checklist

After all changes are made, verify:

- [ ] `home/.zsh_welcome` exists and has no syntax errors
- [ ] `home/.zshrc` Section 2 contains new environment variables
- [ ] `home/.zshrc` Section 10 sources single `.zsh_welcome` file
- [ ] Full mode displays correctly (all tools, disk, OS info)
- [ ] Minimal mode displays single line
- [ ] None mode produces no output
- [ ] Auto-detection works for SSH (`SSH_CONNECTION` set)
- [ ] Auto-detection works for tmux (`TMUX` set)
- [ ] Quick reference has independent verbosity control
- [ ] Disk warning appears when threshold exceeded
- [ ] Homebrew check appears on macOS only
- [ ] GPU check appears on Linux/WSL only
- [ ] uv Python prompt uses `$PYTHON_DEFAULT_VERSION` (not hardcoded)
- [ ] uv Python prompt only appears in full mode

---

## Post-Migration Cleanup (Manual)

> ⚠️ **DO NOT AUTO-DELETE** — Perform manually after verification

After confirming everything works correctly on all platforms:

**Files to delete:**
```
home/.zsh_mac_welcome    → Replaced by home/.zsh_welcome
home/.zsh_linux_welcome  → Replaced by home/.zsh_welcome
home/.zsh_wsl_welcome    → Replaced by home/.zsh_welcome
```

**Why delete:**
- These are now consolidated into a single file
- Keeping them causes no harm but adds clutter to the dotfiles repo
- The new unified file handles all OS-specific logic internally

**How to delete:**
```bash
cd ~/CODE/fifty-shades-of-dotfiles
rm home/.zsh_mac_welcome home/.zsh_linux_welcome home/.zsh_wsl_welcome
git add -A
git commit -m "chore: remove legacy welcome files (consolidated into .zsh_welcome)"
```

---

## README Documentation Update

Add this section to `README.md`:

```markdown
## Welcome Message & Verbosity Control

The shell displays an environment overview on startup. You can control this behavior with environment variables.

### Verbosity Levels

#### `ZSH_WELCOME` — Environment Overview

| Value | Description |
|-------|-------------|
| `full` | Complete multi-line overview (default for new terminals) |
| `minimal` | Single-line compact status (default for SSH/tmux) |
| `none` | No overview displayed |
| _(empty)_ | Auto-detect based on context (recommended) |

#### `ZSH_WELCOME_QUICKREF` — Quick Reference

| Value | Description |
|-------|-------------|
| `full` | Multi-line categorized reference |
| `minimal` | Compact 2-line hints |
| `none` | No quick reference displayed |

### Setting Verbosity

```bash
# In ~/.zshrc.private (or Section 2 of .zshrc)

# Always show full banner
export ZSH_WELCOME="full"
export ZSH_WELCOME_QUICKREF="full"

# Always show minimal
export ZSH_WELCOME="minimal"
export ZSH_WELCOME_QUICKREF="none"

# Silence completely
export ZSH_WELCOME="none"
```

### Auto-Detection

When `ZSH_WELCOME` is empty (default), the welcome message automatically adjusts:

| Context | Auto Default | Rationale |
|---------|--------------|-----------|
| Regular terminal | `full` | First shell of the day, show full info |
| SSH session | `minimal` | You're remoting in, you know your setup |
| Tmux pane | `minimal` | You've seen the banner in the first pane |

To override auto-detection, set `ZSH_WELCOME` explicitly.

### Disk Space Warning

The welcome message shows disk usage and warns if space is low:

```bash
# Default threshold is 90%
# To adjust (e.g., warn at 85%):
export ZSH_WELCOME_DISK_WARN=85
```

### Examples

```bash
# Temporarily run with full verbosity
ZSH_WELCOME=full zsh

# Temporarily silence
ZSH_WELCOME=none zsh

# Test auto-detection (simulate SSH)
SSH_CONNECTION="test" zsh -i -c exit

# Test auto-detection (simulate tmux)
TMUX="/tmp/test" zsh -i -c exit
```
```

---

## Summary of Files Changed

| File | Action | Description |
|------|--------|-------------|
| `home/.zshrc` | MODIFY | Add env vars (Section 2), simplify Section 10 |
| `home/.zsh_welcome` | CREATE | New unified welcome script |
| `README.md` | MODIFY | Add verbosity documentation |
| `home/.zsh_mac_welcome` | DELETE (manual) | Legacy — after verification |
| `home/.zsh_linux_welcome` | DELETE (manual) | Legacy — after verification |
| `home/.zsh_wsl_welcome` | DELETE (manual) | Legacy — after verification |

---

## Approval

- [ ] Plan reviewed
- [ ] Ready to proceed with implementation

**Next Step:** Execute this plan in Claude Code using PLAN MODE, then switch to edit mode to implement changes.
