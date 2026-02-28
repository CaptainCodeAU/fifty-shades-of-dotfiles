# 🎨 VSCode/Cursor Machine-Specific Colors Setup

> **Memento File** - A complete guide for future-you who has forgotten everything.
>
> Last Updated: February 28, 2026

---

## TL;DR - Quick Reference

```bash
# 1. Copy direnv config to any machine
mkdir -p ~/.config/direnv
cp direnvrc ~/.config/direnv/
cp direnv.toml ~/.config/direnv/

# 2. Ensure color profiles JSON is deployed
# (stow handles this from home/.config/zshrc/color-profiles.json)
ls ~/.config/zshrc/color-profiles.json

# 3. cd into any project with .envrc - colors are auto-applied!
cd ~/your-project

# 4. Verify colors were set
# macOS:
grep "titleBar" ~/Library/Application\ Support/Cursor/User/settings.json
# Linux/WSL:
cat ~/.cursor-server/data/Machine/settings.json
```

**Color Profile Mapping:**
| Machine | Profile | Primary Hex | Description |
|---------|---------|-------------|-------------|
| macOS ARM (Apple Silicon) | slate | `#2F4858` | Cool blue-gray |
| macOS Intel | charcoal | `#464F51` | Dark neutral gray |
| WSL Ubuntu (mlbox.lan) | ocean-deep | `#23395B` | Dark navy blue |
| Linux VM 105 (codebox.lan) | forest-green | `#226F54` | Deep green |
| Linux LXC 111 (production) | burnt-orange | `#A3320B` | Warm orange-brown |

**Color Settings Applied (10 per profile):**
| Setting | Source | Purpose |
|---------|--------|---------|
| `titleBar.activeBackground` | Profile primary color | Title bar when window focused |
| `titleBar.activeForeground` | Profile (usually `#ffffff`) | Title text when focused |
| `titleBar.inactiveBackground` | Profile secondary color | Title bar when window not focused |
| `titleBar.inactiveForeground` | Profile (usually `#999999`) | Title text when not focused (dimmer) |
| `panel.border` | Profile secondary color | Bottom panel border |
| `sideBar.border` | Profile secondary color | Side bar border |
| `statusBar.background` | Profile primary color | Bottom status bar |
| `statusBar.foreground` | Profile (usually `#e7e7e7`) | Status bar text |
| `terminal.inactiveSelectionBackground` | Profile (`#3D3D3D`) | Terminal selection when inactive |
| `terminal.selectionBackground` | Profile (`#474747`) | Terminal selection when active |

**Dependencies:**

- `jq` — required (essential prerequisite in `install.sh`)
- `~/.config/zshrc/color-profiles.json` — 10 named color profiles (deployed via stow)
- `~/.config/zshrc/init-vscode-project-settings.sh` — project-level color scaffolding script (deployed via stow)

---

## The Problem (Plain English)

When working across multiple machines via SSH (Mac → WSL, Mac → Linux VMs), all VSCode/Cursor windows look identical. This makes it easy to accidentally run commands on the wrong machine - especially dangerous when one is production!

**Goal:** Automatically color-code the title bar, status bar, and borders based on which machine you're connected to, so you can instantly tell them apart visually.

**Constraints:**

- Must be automatic (no manual steps when connecting)
- Must work on macOS (local, both ARM and Intel), WSL, and Linux VMs (remote)
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
│  │    2. Detect architecture (ARM/Intel) or hostname          │  │
│  │    3. Select color profile name                            │  │
│  │    4. Read profile from color-profiles.json via jq         │  │
│  │    5. Insert 10 colorCustomizations if missing             │  │
│  └────────────────────────────────────────────────────────────┘  │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│             ~/.config/zshrc/color-profiles.json                   │
│             (10 named profiles, each with 10 color properties)    │
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
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
│  │ macOS ARM │ │macOS Intel│ │    WSL    │ │  Codebox  │ │Production │
│  │  ███████  │ │  ███████  │ │  ███████  │ │  ███████  │ │  ███████  │
│  │  #2F4858  │ │  #464F51  │ │  #23395B  │ │  #226F54  │ │  #A3320B  │
│  │   slate   │ │ charcoal  │ │ocean-deep │ │for.-green │ │brnt.-org. │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘ └───────────┘
└──────────────────────────────────────────────────────────────────┘
```

### Settings File Hierarchy (Precedence)

```
Default Settings
      ↓
User Settings        ← direnvrc modifies this (macOS) — machine identity
      ↓
Machine Settings     ← direnvrc modifies this (Linux/WSL remote) — machine identity
      ↓
Workspace Settings   ← .vscode/settings.json — project identity (via init-vscode-project-settings.sh)
```

**How the two systems interact:**

- **Machine colors** (direnvrc, automatic) give each machine a default visual identity
- **Project colors** (init script, manual) override machine colors per-workspace for project identity
- Projects without `.vscode/settings.json` still show machine colors
- Both systems read from the same `color-profiles.json` — no duplication

---

## All Configuration Files

### Repository File Locations

| Repository Path                                                         | Purpose                                                  | Deploy To                                                 |
| ----------------------------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------- |
| `home/.config/direnv/direnvrc`                                          | Main logic - detects machine, reads profile, sets colors | `~/.config/direnv/direnvrc`                               |
| `home/.config/direnv/direnv.toml`                                       | direnv config (hides env diff output)                    | `~/.config/direnv/direnv.toml`                            |
| `home/.config/zshrc/color-profiles.json`                                | 10 named color profiles (JSON)                           | `~/.config/zshrc/color-profiles.json`                     |
| `home/.config/zshrc/init-vscode-project-settings.sh`                    | Project-level color scaffolding script                   | `~/.config/zshrc/init-vscode-project-settings.sh`         |
| `.vscode/tasks.json`                                                    | VS Code tasks for this repo (not stowed)                 | —                                                         |
| `platforms/macos/Library/Application Support/Cursor/User/settings.json` | Template for Cursor user settings (macOS)                | `~/Library/Application Support/Cursor/User/settings.json` |
| `platforms/macos/Library/Application Support/Code/User/settings.json`   | Template for VSCode user settings (macOS)                | `~/Library/Application Support/Code/User/settings.json`   |
| `home/.zshrc`                                                           | Unified shell config with `python()` function            | `~/.zshrc`                                                |
| `home/.zsh_python_functions`                                            | Contains `update_vscode_settings()`, `create_envrc()`    | `~/.zsh_python_functions`                                 |

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

#### Step 1: Install direnv and jq (if not installed)

```bash
# macOS
brew install direnv jq

# Ubuntu/Debian
sudo apt install direnv jq

# Add to ~/.zshrc (should already be there if using the unified zshrc)
eval "$(direnv hook zsh)"
```

#### Step 2: Deploy direnv Configuration and Color Profiles

```bash
# Create directories
mkdir -p ~/.config/direnv
mkdir -p ~/.config/zshrc

# Copy files from the fifty-shades-of-dotfiles repository
cp ~/fifty-shades-of-dotfiles/home/.config/direnv/direnvrc ~/.config/direnv/
cp ~/fifty-shades-of-dotfiles/home/.config/direnv/direnv.toml ~/.config/direnv/
cp ~/fifty-shades-of-dotfiles/home/.config/zshrc/color-profiles.json ~/.config/zshrc/
```

#### Step 3: Trigger Color Setup

```bash
# cd into any project with .envrc
cd ~/CODE/your-project

# If .envrc exists, direnv will:
# 1. Source ~/.config/direnv/direnvrc (reads profile, sets colors)
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

# 2. Is color-profiles.json deployed?
ls -la ~/.config/zshrc/color-profiles.json

# 3. Is jq installed?
command -v jq

# 4. Is the project's .envrc allowed?
cd your-project
direnv allow .

# 5. Is the session flag blocking re-run?
unset _VSCODE_COLORS_CHECKED
cd .. && cd your-project

# 6. Check if colors exist in settings
# macOS:
grep "titleBar" ~/Library/Application\ Support/Cursor/User/settings.json
# Linux:
grep "titleBar" ~/.cursor-server/data/Machine/settings.json

# 7. Test profile lookup manually
jq -r '.profiles[] | select(.name == "slate")' ~/.config/zshrc/color-profiles.json
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

**Symptom:** Colors don't get applied because jq is missing.

**Fix:**

```bash
brew install jq
```

### macOS: Settings File Has Comments (JSONC)

**Symptom:** The settings file uses JSONC (JSON with Comments).

**Note:** direnvrc uses `sed` for inserting colors (not jq for parsing), so JSONC is handled correctly. jq is only used to read the `color-profiles.json` file (which is plain JSON).

### Wrong Color on Linux Machine

**Symptom:** Linux machine shows wrong color (e.g., production orange instead of codebox green).

**Cause:** Hostname detection pattern doesn't match.

**Fix:** Edit `~/.config/direnv/direnvrc` and update the hostname patterns:

```bash
case "$(hostname)" in
    *codebox*|*105*)
        profile_name="forest-green"
        machine_name="Linux-Codebox"
        ;;
    *)
        profile_name="burnt-orange"
        machine_name="Linux-Production"
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

## Available Color Profiles

All profiles are defined in `~/.config/zshrc/color-profiles.json`:

| #   | Name         | Primary   | Secondary | Machine Default  |
| --- | ------------ | --------- | --------- | ---------------- |
| 1   | ocean-deep   | `#23395B` | `#1b2c47` | WSL Ubuntu       |
| 2   | forest-green | `#226F54` | `#1a5540` | Linux Codebox    |
| 3   | deep-purple  | `#4B296B` | `#3a2052` | (available)      |
| 4   | crimson      | `#A71D31` | `#821625` | (available)      |
| 5   | teal         | `#0E9594` | `#0b7372` | (available)      |
| 6   | burnt-orange | `#A3320B` | `#7d2609` | Linux Production |
| 7   | slate        | `#2F4858` | `#243845` | macOS ARM        |
| 8   | magenta      | `#A40E4C` | `#7e0b3b` | (available)      |
| 9   | dark-olive   | `#262A10` | `#1c1f0b` | (available)      |
| 10  | charcoal     | `#464F51` | `#363d3f` | macOS Intel      |

Any profile can also be used for **project-level** colors via the init script (see below).

---

## Project-Level Colors (Per-Workspace)

The `init-vscode-project-settings.sh` script scaffolds a `.vscode/settings.json` in any project, giving each VS Code window its own color identity.

### Usage

```bash
# Show help
~/.config/zshrc/init-vscode-project-settings.sh

# Random profile
~/.config/zshrc/init-vscode-project-settings.sh -r

# Specific profile
~/.config/zshrc/init-vscode-project-settings.sh -p crimson

# List available profiles
~/.config/zshrc/init-vscode-project-settings.sh -l
```

### What it does

1. Checks for `.git/` directory — asks for confirmation if not found
2. Selects a profile (random with `-r`, or named with `-p`)
3. If `.vscode/settings.json` exists, shows contents and asks before overwriting
4. Generates `.vscode/settings.json` with:
   - `workbench.colorCustomizations` (10 properties from the chosen profile)
   - `editor.fontFamily`: MonoLisa Nerd Font Mono
   - `terminal.integrated.fontFamily`: JetBrains Mono

### VS Code Task

This dotfiles repo includes `.vscode/tasks.json` with tasks to run the script from the Command Palette (`Terminal > Run Task…`):

- **Init VSCode Project Colors** — runs with `--random`
- **List Color Profiles** — runs with `--list`

---

## Files to Backup When Migrating

### Essential Files

```bash
# direnv configuration
~/.config/direnv/direnvrc
~/.config/direnv/direnv.toml

# Color profiles and project init script
~/.config/zshrc/color-profiles.json
~/.config/zshrc/init-vscode-project-settings.sh

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

### 1. Choose a profile from `color-profiles.json`

```bash
# List available profiles
jq -r '.profiles[].name' ~/.config/zshrc/color-profiles.json
```

Or add a new profile to `home/.config/zshrc/color-profiles.json` following the existing format (10 color properties per profile).

### 2. Edit `~/.config/direnv/direnvrc`

Find the machine detection section and add your new machine:

```bash
elif [[ "$is_linux" == true ]]; then
    case "$(hostname)" in
        *codebox*|*105*)
            profile_name="forest-green"
            machine_name="Linux-Codebox"
            ;;
        *newmachine*|*999*)           # ← Add new pattern
            profile_name="deep-purple" # ← Use existing or new profile
            machine_name="Linux-NewMachine"
            ;;
        *)
            profile_name="burnt-orange"
            machine_name="Linux-Production"
            ;;
    esac
```

### 3. Update the comment at the top of direnvrc

```bash
# Profile assignments:
#   macOS ARM (Apple Silicon)  → slate        #2F4858
#   ...
#   Linux NewMachine           → deep-purple  #4B296B   ← Add this
```

### 4. Deploy to the new machine

```bash
scp ~/.config/direnv/direnvrc newmachine:~/.config/direnv/
scp ~/.config/zshrc/color-profiles.json newmachine:~/.config/zshrc/
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
- **2026-02-28:** Refactored to profile-based color system with 10 named profiles in `color-profiles.json`
- **2026-02-28:** Added macOS architecture detection (ARM → Slate, Intel → Charcoal)
- **2026-02-28:** Expanded from 6 to 10 color properties (added `panel.border`, `sideBar.border`, `terminal.inactiveSelectionBackground`, `terminal.selectionBackground`)
- **2026-02-28:** Colors now use two-tone format (active vs inactive) loaded from JSON via jq
- **2026-02-28:** Profile names changed to lowercase-hyphenated format (e.g., `ocean-deep`, `burnt-orange`)
- **2026-02-28:** Added `init-vscode-project-settings.sh` for per-project workspace color scaffolding
- **2026-02-28:** Added `.vscode/tasks.json` with VS Code tasks for running the init script
- **2026-02-28:** `jq` promoted to essential prerequisite in `install.sh`

---

## Contact / Resources

- **direnv documentation:** https://direnv.net/
- **VSCode settings locations:** https://code.visualstudio.com/docs/getstarted/settings
- **Cursor (VSCode fork):** Uses same settings structure as VSCode
