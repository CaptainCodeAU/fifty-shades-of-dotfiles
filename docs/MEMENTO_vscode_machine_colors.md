# 🎨 VSCode/Cursor Machine-Specific Colors Setup

> **Memento File** - A complete guide for future-you who has forgotten everything.
>
> Last Updated: January 12, 2025

---

## TL;DR - Quick Reference

```bash
# 1. Copy direnv config to any machine
mkdir -p ~/.config/direnv
cp direnvrc ~/.config/direnv/
cp direnv.toml ~/.config/direnv/

# 2. cd into any project with .envrc - colors are auto-applied!
cd ~/your-project

# 3. Verify colors were set
# macOS:
grep "titleBar" ~/Library/Application\ Support/Cursor/User/settings.json
# Linux/WSL:
cat ~/.cursor-server/data/Machine/settings.json
```

**Color Mapping:**
| Machine | Color | Hex |
|---------|-------|-----|
| macOS (AdminMBP) | Dark Gray | `#202020` |
| WSL Ubuntu (mlbox.lan) | Blue | `#1a4d7a` |
| Linux LXC 111 (production) | Orange | `#D96400` |
| Linux VM 105 (codebox.lan) | Green | `#97B500` |

**Color Settings Applied:**
| Setting | Value | Purpose |
|---------|-------|---------|
| `titleBar.activeBackground` | Machine color | Title bar when window focused |
| `titleBar.activeForeground` | `#e7e7e7` | Title text when focused |
| `titleBar.inactiveBackground` | Machine color | Title bar when window not focused |
| `titleBar.inactiveForeground` | `#999999` | Title text when not focused (dimmer) |
| `statusBar.background` | Machine color | Bottom status bar |
| `statusBar.foreground` | `#e7e7e7` | Status bar text |

---

## The Problem (Plain English)

When working across multiple machines via SSH (Mac → WSL, Mac → Linux VMs), all VSCode/Cursor windows look identical. This makes it easy to accidentally run commands on the wrong machine - especially dangerous when one is production!

**Goal:** Automatically color-code the title bar and status bar based on which machine you're connected to, so you can instantly tell them apart visually.

**Constraints:**
- Must be automatic (no manual steps when connecting)
- Must work on macOS (local), WSL, and Linux VMs (remote)
- Must not require changes to every project's `.envrc` file
- Must handle existing settings files without breaking them

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HOW IT ALL FITS TOGETHER                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│   You type:      │
│   cd ~/project   │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                        direnv detects .envrc                      │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│              ~/.config/direnv/direnvrc (sourced FIRST)           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  _setup_vscode_machine_colors()                            │  │
│  │    1. Detect OS (Darwin/Linux/WSL)                         │  │
│  │    2. Detect hostname for Linux variants                   │  │
│  │    3. Select color based on machine                        │  │
│  │    4. Check if settings file exists                        │  │
│  │    5. Insert colorCustomizations if missing                │  │
│  └────────────────────────────────────────────────────────────┘  │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Settings File Updated                          │
│                                                                   │
│  macOS:     ~/Library/Application Support/Cursor/User/settings.json
│  Linux/WSL: ~/.cursor-server/data/Machine/settings.json          │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Project's .envrc runs                          │
│                    (venv activation, welcome message, etc.)       │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│  🎨 VSCode/Cursor shows machine-specific colors!                 │
│                                                                   │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ │
│  │   macOS    │ │    WSL     │ │  Codebox   │ │ Production │ │
│  │  ███████   │ │  ███████   │ │  ███████   │ │  ███████   │ │
│  │  #202020   │ │  #1a4d7a   │ │  #97B500   │ │  #D96400   │ │
│  │ Dark Gray  │ │   Blue     │ │   Green    │ │  Orange    │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### Settings File Hierarchy (Precedence)

```
Default Settings
      ↓
User Settings        ← direnvrc modifies this (macOS)
      ↓
Machine Settings     ← direnvrc modifies this (Linux/WSL remote)
      ↓
Workspace Settings   ← .vscode/settings.json (project-level, DO NOT add colors here)
```

**Important:** Workspace settings override Machine/User settings. Never add `workbench.colorCustomizations` to `.vscode/settings.json` or it will override the machine colors!

---

## All Configuration Files

### Repository File Locations

| Repository Path | Purpose | Deploy To |
|-----------------|---------|-----------|
| `home/.config/direnv/direnvrc` | Main logic - detects machine, sets colors | `~/.config/direnv/direnvrc` |
| `home/.config/direnv/direnv.toml` | direnv config (hides env diff output) | `~/.config/direnv/direnv.toml` |
| `platforms/macos/Library/Application Support/Cursor/User/settings.json` | Template for Cursor user settings (macOS) | `~/Library/Application Support/Cursor/User/settings.json` |
| `platforms/macos/Library/Application Support/Code/User/settings.json` | Template for VSCode user settings (macOS) | `~/Library/Application Support/Code/User/settings.json` |
| `home/.zshrc` | Unified shell config with `python()` function | `~/.zshrc` |
| `home/.zsh_python_functions` | Contains `update_vscode_settings()`, `create_envrc()` | `~/.zsh_python_functions` |

### Settings File Locations

#### macOS (Local Development)

```bash
# VSCode
~/Library/Application Support/Code/User/settings.json

# Cursor
~/Library/Application Support/Cursor/User/settings.json
```

#### WSL Ubuntu (mlbox.lan) - Remote

```bash
# VSCode (created when you SSH via VSCode Remote)
~/.vscode-server/data/Machine/settings.json

# Cursor (created when you SSH via Cursor Remote)
~/.cursor-server/data/Machine/settings.json
```

#### Linux VM 105 (codebox.lan) - Remote

```bash
~/.vscode-server/data/Machine/settings.json
~/.cursor-server/data/Machine/settings.json
```

#### Linux LXC 111 (production) - Remote

```bash
~/.vscode-server/data/Machine/settings.json
~/.cursor-server/data/Machine/settings.json
```

---

## Complete Setup Instructions

### New Machine Setup

#### Step 1: Install direnv (if not installed)

```bash
# macOS
brew install direnv

# Ubuntu/Debian
sudo apt install direnv

# Add to ~/.zshrc (should already be there if using the unified zshrc)
eval "$(direnv hook zsh)"
```

#### Step 2: Deploy direnv Configuration

```bash
# Create directory
mkdir -p ~/.config/direnv

# Copy files from the fifty-shades-of-dotfiles repository
cp ~/fifty-shades-of-dotfiles/home/.config/direnv/direnvrc ~/.config/direnv/
cp ~/fifty-shades-of-dotfiles/home/.config/direnv/direnv.toml ~/.config/direnv/
```

#### Step 3: Trigger Color Setup

```bash
# cd into any project with .envrc
cd ~/CODE/your-project

# If .envrc exists, direnv will:
# 1. Source ~/.config/direnv/direnvrc (sets colors)
# 2. Source the project's .envrc
```

#### Step 4: Verify

```bash
# macOS
grep -A4 "colorCustomizations" ~/Library/Application\ Support/Cursor/User/settings.json

# Linux/WSL
cat ~/.cursor-server/data/Machine/settings.json
```

### Updating Colors on Existing Machine

If you need to change colors or re-run the setup:

```bash
# Clear the session flag
unset _VSCODE_COLORS_CHECKED

# Re-enter a project directory
cd .. && cd your-project
```

### Manual Color Removal (if needed)

```bash
# macOS - edit directly
cursor ~/Library/Application\ Support/Cursor/User/settings.json
# Remove the workbench.colorCustomizations block

# Linux/WSL - delete the file (will be recreated)
rm ~/.cursor-server/data/Machine/settings.json
```

---

## Troubleshooting

### Colors Not Being Applied

**Symptom:** Title bar stays default color after cd'ing into project.

**Checks:**
```bash
# 1. Is direnvrc in the right place?
ls -la ~/.config/direnv/direnvrc

# 2. Is the project's .envrc allowed?
cd your-project
direnv allow .

# 3. Is the session flag blocking re-run?
unset _VSCODE_COLORS_CHECKED
cd .. && cd your-project

# 4. Check if colors exist in settings
# macOS:
grep "titleBar" ~/Library/Application\ Support/Cursor/User/settings.json
# Linux:
grep "titleBar" ~/.cursor-server/data/Machine/settings.json
```

### Colors Applied But Not Showing

**Symptom:** Settings file has colors but VSCode/Cursor still shows default.

**Solutions:**
1. Reload the window: `Cmd+Shift+P` → "Reload Window"
2. Check if workspace settings override: Look in `.vscode/settings.json` for `colorCustomizations`
3. Restart VSCode/Cursor completely

### Duplicate Color Blocks (Malformed JSON)

**Symptom:** Settings file has multiple `workbench.colorCustomizations` blocks.

**Cause:** Old version of direnvrc had a sed bug that matched braces inside objects.

**Fix:**
1. Open settings file
2. Remove duplicate blocks, keep only one at the top
3. Ensure valid JSON (no `},},` patterns)
4. Update to latest `direnvrc` (uses `1 a\` sed command)

### macOS: "jq not found" or Colors Not Applied

**Symptom:** Colors work on Linux but not macOS.

**Note:** The current direnvrc uses `sed` for macOS (not jq), so this shouldn't happen with the latest version. But if using an old version:

```bash
# Install jq
brew install jq

# Or update to latest direnvrc which uses sed instead
```

### macOS: Settings File Has Comments (JSONC)

**Symptom:** jq fails with "parse error" on macOS settings.

**Cause:** VSCode/Cursor settings files use JSONC (JSON with Comments), which jq can't parse.

**Solution:** The current direnvrc uses `sed` for macOS, which handles JSONC. Make sure you have the latest version.

### Wrong Color on Linux Machine

**Symptom:** Linux machine shows wrong color (e.g., production orange instead of codebox green).

**Cause:** Hostname detection pattern doesn't match.

**Fix:** Edit `~/.config/direnv/direnvrc` and update the hostname patterns:

```bash
case "$(hostname)" in
    *codebox*|*105*)
        # Green for codebox
        color="#97B500"
        ;;
    *)
        # Orange for everything else (production)
        color="#D96400"
        ;;
esac
```

### Existing colorCustomizations Block (Empty)

**Symptom:** Settings file has `workbench.colorCustomizations` but no titleBar colors inside. The `.envrc` diagnostic shows "✗ Not configured".

**Cause:** The settings.json template has an empty `colorCustomizations` block with just comments:
```json
"workbench.colorCustomizations": {
    // titleBar and statusBar colors are automatically set by direnvrc
},
```

Old versions of direnvrc would skip the file because the section "exists" (even though empty).

**Fix:** Update to the latest `direnvrc` which now:
1. Checks if `titleBar.activeBackground` exists (not just the section)
2. If section exists but no titleBar settings → inserts colors INTO the existing block
3. If section doesn't exist → creates the whole block

```bash
# Update direnvrc
cp ~/fifty-shades-of-dotfiles/home/.config/direnv/direnvrc ~/.config/direnv/direnvrc

# Clear session flag and re-trigger
unset _VSCODE_COLORS_CHECKED
cd .. && cd your-project
```

### Title Bar Color Reverts When Window Inactive

**Symptom:** Title bar shows correct color when focused, but reverts to default when clicking away.

**Cause:** Old direnvrc only set `titleBar.activeBackground`, not the inactive variant.

**Fix:** Update to latest `direnvrc` which sets both:
- `titleBar.activeBackground` - when window is focused
- `titleBar.inactiveBackground` - when window is not focused

---

## Alternative Approaches (Rejected)

We considered several approaches before settling on Method G (direnv integration):

### Method A: Manual One-Time Setup
- **What:** SSH into each machine, manually create settings file
- **Rejected because:** Repetitive, easy to forget machines, manual updates needed

### Method B: Centralized Deployment from Mac
- **What:** Script on Mac that SSHs to all machines and deploys settings
- **Rejected because:** Requires manual trigger, Mac needs to know about all hosts

### Method D: Integration with Onboarding Script
- **What:** Add to `.zsh_linux_onboarding` that runs once per machine
- **Rejected because:** Only works on Linux, not macOS or WSL

### Method E: Standalone Bootstrap Script
- **What:** Single script to curl/wget and run on each machine
- **Rejected because:** Requires manual trigger

### Method F: fifty-shades-of-dotfiles Repository
- **What:** Store settings in git repo, sync across machines
- **Rejected because:** Too much infrastructure for this specific feature

---

## Alternative Approaches (Kept as Backup)

If the direnv approach ever fails, these are viable alternatives:

### Method C: Integration with Welcome Scripts

Add color setup to `~/.zsh_mac_welcome`, `~/.zsh_wsl_welcome`, `~/.zsh_linux_welcome`.

**Pros:** Already have these scripts, runs on shell startup
**Cons:** Runs every shell start (though with guard check)

### Method H: SSH Config LocalCommand

Use SSH config's `LocalCommand` or `PermitLocalCommand` to run setup on connection.

**Pros:** Automatic on SSH connection
**Cons:** Complex SSH config, security considerations, only works on SSH (not local terminal)

---

## Files to Backup When Migrating

### Essential Files

```bash
# direnv configuration
~/.config/direnv/direnvrc
~/.config/direnv/direnv.toml

# Zsh configuration (contains update_vscode_settings function)
~/.zsh_python_functions
```

### Optional (will be recreated by direnvrc)

```bash
# macOS user settings (has many other settings too - backup!)
~/Library/Application Support/Code/User/settings.json
~/Library/Application Support/Cursor/User/settings.json

# Linux/WSL machine settings (only contains colors, safe to delete)
~/.vscode-server/data/Machine/settings.json
~/.cursor-server/data/Machine/settings.json
```

---

## Quick Reference: Adding a New Machine Type

To add a new machine with a different color:

### 1. Edit `~/.config/direnv/direnvrc`

Find the machine detection section and add your new machine:

```bash
elif [[ "$is_linux" == true ]]; then
    case "$(hostname)" in
        *codebox*|*105*)
            color="#97B500"
            machine_name="Linux-Codebox"
            ;;
        *newmachine*|*999*)        # ← Add new pattern
            color="#FF00FF"          # ← Add new color
            machine_name="Linux-NewMachine"
            ;;
        *)
            color="#D96400"
            machine_name="Linux-Production"
            ;;
    esac
```

### 2. Update the comment at the top of direnvrc

```bash
# Colors:
#   macOS (AdminMBP)           → Dark Gray  #202020
#   WSL Ubuntu (mlbox.lan)     → Blue       #1a4d7a
#   Linux LXC 111 (production) → Orange     #D96400
#   Linux VM 105 (codebox.lan) → Green      #97B500
#   Linux NewMachine           → Magenta    #FF00FF   ← Add this
```

### 3. Update settings.json templates (for documentation)

The settings.json templates are located at:
- `platforms/macos/Library/Application Support/Cursor/User/settings.json`
- `platforms/macos/Library/Application Support/Code/User/settings.json`

### 4. Deploy to the new machine

```bash
scp ~/.config/direnv/direnvrc newmachine:~/.config/direnv/
```

---

## Changelog

- **2025-01-11:** Initial implementation with direnv Method G
- **2025-01-11:** Fixed JSONC parsing issue on macOS (switched from jq to sed)
- **2025-01-11:** Fixed sed duplicate insertion bug (changed to `1 a\` command)
- **2025-01-11:** Added OS-aware .envrc diagnostic check
- **2025-01-11:** Created merged settings.json template
- **2025-01-11:** Updated `update_vscode_settings()` with section comments and direnvrc note
- **2025-01-12:** Fixed: direnvrc now inserts colors INTO existing empty `colorCustomizations` block
- **2025-01-12:** Added inactive title bar colors (`titleBar.inactiveBackground`, `titleBar.inactiveForeground`)
- **2025-01-12:** Fixed: Linux/WSL logic now mirrors macOS (handles existing files with empty colorCustomizations)
- **2025-01-12:** Fixed `.envrc` template: only sets `VIRTUAL_ENV_PROMPT` when venv actually exists
- **2025-01-12:** Updated `python()` function in `.zshrc`: checks `$VIRTUAL_ENV` → local `.venv` → uv global
- **2025-01-12:** Removed pyenv reference from `settings.json` (workspace settings handle interpreter path)
- **2025-01-12:** Updated `create_envrc()` to include Environment Info and VSCode Settings Check sections

---

## Contact / Resources

- **direnv documentation:** https://direnv.net/
- **VSCode settings locations:** https://code.visualstudio.com/docs/getstarted/settings
- **Cursor (VSCode fork):** Uses same settings structure as VSCode
