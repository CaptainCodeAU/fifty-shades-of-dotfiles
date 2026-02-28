#!/usr/bin/env bash
# =============================================================================
# init-vscode-project-settings.sh
# =============================================================================
# Scaffolds a .vscode/settings.json with a color profile and font settings.
#
# Usage:
#   init-vscode-project-settings.sh                 # show help
#   init-vscode-project-settings.sh -r              # random profile
#   init-vscode-project-settings.sh -p slate        # specific profile
#   init-vscode-project-settings.sh --profile teal  # specific profile
#   init-vscode-project-settings.sh --list           # list available profiles
#
# Reads profiles from ~/.config/zshrc/color-profiles.json
# =============================================================================

set -euo pipefail

PROFILES_FILE="$HOME/.config/zshrc/color-profiles.json"
TARGET_DIR=".vscode"
TARGET_FILE="$TARGET_DIR/settings.json"

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Linux:  sudo apt install jq" >&2
    exit 1
fi

if [[ ! -f "$PROFILES_FILE" ]]; then
    echo "Error: Color profiles not found at $PROFILES_FILE" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
profile_name=""
list_profiles=false
random_profile=false

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Scaffolds .vscode/settings.json with a color profile and font settings."
    echo ""
    echo "Options:"
    echo "  -p, --profile NAME   Use a specific color profile"
    echo "  -r, --random         Use a random color profile"
    echo "  -l, --list           List available profiles"
    echo "  -h, --help           Show this help"
}

# No arguments → show help
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --profile requires a name argument." >&2
                exit 1
            fi
            profile_name="$2"
            shift 2
            ;;
        -r|--random)
            random_profile=true
            shift
            ;;
        --list|-l)
            list_profiles=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'. Use --help for usage." >&2
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# List profiles mode
# -----------------------------------------------------------------------------
if [[ "$list_profiles" == true ]]; then
    echo "Available color profiles:"
    echo ""
    jq -r '.profiles[] | "  \(.name)  \(.["titleBar.activeBackground"])"' "$PROFILES_FILE"
    exit 0
fi

# -----------------------------------------------------------------------------
# Project directory check
# -----------------------------------------------------------------------------
if [[ ! -d ".git" ]]; then
    echo "Warning: No .git/ directory found. This might not be a project root."
    read -rp "Continue anyway? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
fi

# -----------------------------------------------------------------------------
# Select profile
# -----------------------------------------------------------------------------
profile_count=$(jq '.profiles | length' "$PROFILES_FILE")

if [[ "$random_profile" == true ]]; then
    random_index=$(( RANDOM % profile_count ))
    profile=$(jq -r ".profiles[$random_index]" "$PROFILES_FILE")
    profile_name=$(echo "$profile" | jq -r '.name')
elif [[ -n "$profile_name" ]]; then
    profile=$(jq -r --arg name "$profile_name" '.profiles[] | select(.name == $name)' "$PROFILES_FILE")
    if [[ -z "$profile" ]]; then
        echo "Error: Profile '$profile_name' not found." >&2
        echo "Available profiles:" >&2
        jq -r '.profiles[].name' "$PROFILES_FILE" >&2
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Check for existing file
# -----------------------------------------------------------------------------
if [[ -f "$TARGET_FILE" ]]; then
    echo "Warning: $TARGET_FILE already exists."
    echo ""
    echo "Current contents:"
    head -20 "$TARGET_FILE"
    if [[ $(wc -l < "$TARGET_FILE") -gt 20 ]]; then
        echo "  ... ($(wc -l < "$TARGET_FILE") lines total)"
    fi
    echo ""
    read -rp "Overwrite with profile '$profile_name'? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
fi

# -----------------------------------------------------------------------------
# Generate settings.json
# -----------------------------------------------------------------------------
mkdir -p "$TARGET_DIR"

# Extract color values from the profile
jq -n --argjson profile "$profile" '{
    "workbench.colorCustomizations": {
        "titleBar.activeBackground": $profile["titleBar.activeBackground"],
        "titleBar.activeForeground": $profile["titleBar.activeForeground"],
        "titleBar.inactiveBackground": $profile["titleBar.inactiveBackground"],
        "titleBar.inactiveForeground": $profile["titleBar.inactiveForeground"],
        "panel.border": $profile["panel.border"],
        "sideBar.border": $profile["sideBar.border"],
        "statusBar.background": $profile["statusBar.background"],
        "statusBar.foreground": $profile["statusBar.foreground"],
        "terminal.inactiveSelectionBackground": $profile["terminal.inactiveSelectionBackground"],
        "terminal.selectionBackground": $profile["terminal.selectionBackground"]
    },
    "terminal.integrated.fontFamily": "'\''JetBrains Mono'\'', monospace",
    "editor.fontFamily": "MonoLisa Nerd Font Mono"
}' > "$TARGET_FILE"

echo "Created $TARGET_FILE with profile '$profile_name' ($(echo "$profile" | jq -r '.["titleBar.activeBackground"]'))"
