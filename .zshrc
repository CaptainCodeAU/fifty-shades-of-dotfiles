# ==============================================================================
#  Unified Zsh Configuration for macOS, Linux & WSL
# ==============================================================================

# ==============================================================================
# 1. Environment Variables & OS Detection
# ==============================================================================
# --- Cross-Platform Environment ---
export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8

# --- Python ---
export PIP_REQUIRE_VIRTUALENV=true
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PROMPT_EOL_MARK="" # Disable Powerlevel10k instant prompt
: ${PYTHON_MIN_VERSION:="3.8"}
: ${PYTHON_MAX_VERSION:="3.13"}
: ${PYTHON_DEFAULT_VERSION:="$PYTHON_MAX_VERSION"}
: ${PYTHON_VERSION_PATTERN:="^3\.(8|9|1[0-3])$"}

# --- Telemetry Opt-Out ---
export ANONYMIZED_TELEMETRY=false; export ARTILLERY_DISABLE_TELEMETRY=true
export AWS_CLI_TELEMETRY_OPTOUT=1; export AZURE_TELEMETRY_OPTOUT=true
export CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=true; export CREWAI_DISABLE_TELEMETRY=true
export DISABLE_TELEMETRY=true; export DOTNET_CLI_TELEMETRY_OPTOUT=true
export DOTNET_NOLOGO=true; export GRAPHITI_TELEMETRY_ENABLED=false
export JUPYTER_NO_TELEMETRY=1; export MEM0_TELEMETRY_DISABLED=true
export N8N_DIAGNOSTICS_ENABLED=false; export NETLIFY_TELEMETRY_DISABLED=1
export NEW_RELIC_TELEMETRY_ENABLED=false; export NEXT_TELEMETRY_DISABLED=1
export OTEL_SDK_DISABLED=true; export PLAUSIBLE_TELEMETRY_DISABLED=true
export POSTHOG_TELEMETRY_DISABLED=true; export TELEMETRY=false
export TELEMETRY_DISABLED=true; export TELEMETRY_ENABLED=false
export TELEMETRY_OPTOUT=true; export VSCODE_TELEMETRY_OPTOUT=1

# --- PHP ---
export WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR^E_PARSE^E_COMPILE_ERROR -d display_errors=0"

# ==============================================================================
# 2. OS Detection & Environment-Specific Settings
# ==============================================================================
export IS_MAC=false
export IS_WSL=false
export IS_LINUX=false
export HOMEBREW_PREFIX=""

case "$(uname -s)" in
    Darwin)
        IS_MAC=true
        # Set Homebrew prefix path for Apple Silicon or Intel
        [[ -d /opt/homebrew ]] && HOMEBREW_PREFIX="/opt/homebrew" || HOMEBREW_PREFIX="/usr/local"
        ;;
    Linux)
        if [[ "$(uname -r)" =~ [Ww][Ss][Ll] || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
            IS_WSL=true
            export DIRENV_LOG_FORMAT=""
            export DIRENV_WARN_ON_PS1=0
            export UV_LINK_MODE=copy # For NTFS compatibility
        else
            IS_LINUX=true
        fi
        ;;
esac

# ==============================================================================
# 3. Onboarding & Dependency Checks (Linux Only)
# ==============================================================================
# On first run in a new Linux VM, this will check for and offer to install tools.
if [[ "$IS_LINUX" == "true" && -f ~/.zsh_onboarding && -z "$_ONBOARDING_COMPLETE" ]]; then
    source ~/.zsh_linux_onboarding
    export _ONBOARDING_COMPLETE=true
fi

# ==============================================================================
# 4. UI, Zsh, Oh My Zsh & Powerlevel10k
# ==============================================================================
# --- UI Helpers ---
autoload -U colors && colors
ok="$fg[green]"; warn="$fg[yellow]"; err="$fg[red]"; info="$fg[cyan]"; example="$fg[magenta]"; done="$reset_color"

# --- Zsh/OMZ Base ---
export ZSH="$HOME/.oh-my-zsh"

# Powerlevel9k Instant Prompt (off by default)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# --- Powerlevel10k Instant Prompt (Load First) ---
# Must be sourced before Zsh is initialized for speed.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Oh My Zsh Theme ---
#  # Use a simpler theme in Cursor editor
[[ -n $CURSOR_TRACE_ID ]] && ZSH_THEME="robbyrussell" || ZSH_THEME="powerlevel10k/powerlevel10k"

# --- Oh My Zsh Plugins ---
plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting vscode history-substring-search)

# --- Add to fpath BEFORE sourcing Oh My Zsh ---
# This ensures OMZ's `compinit` call finds these completion files.
if [[ "$IS_MAC" == "true" && -d "$HOME/.docker/completions" ]]; then
    # Suggested by Docker Desktop to enable Docker CLI completions.
    fpath=("$HOME/.docker/completions" $fpath)
fi

# This ensures OMZ's `compinit` call finds these completion files.
if [[ "$IS_MAC" == "true" && -d "$HOME/.docker/completions" ]]; then
    fpath=("$HOME/.docker/completions" $fpath)
fi

# --- Source Oh My Zsh ---
# This must come after theme, plugins, and fpath are defined.
# OMZ will automatically run 'compinit' for us, no need for a separate call.
source "$ZSH/oh-my-zsh.sh"

# --- Source Powerlevel10k Theme Configuration ---
# This should come after sourcing Oh My Zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# --- Source Other Completions AFTER Oh My Zsh ---
# These commands often rely on the completion system already being initialized.
command -v register-python-argcomplete >/dev/null && eval "$(register-python-argcomplete pipx)"
command -v uv >/dev/null && eval "$(uv generate-shell-completion zsh)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ==============================================================================
# 5. NVM (Node Version Manager)
# ==============================================================================
# Official, unified loading script for script-based installations (macOS & WSL).
# This snippet is based on the official NVM README for robustness and XDG compliance.
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
# Source nvm.sh if it exists. The --no-use flag prevents auto-loading a default version.
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh" --no-use
    # Source the bash_completion script if it exists. Nvm's script should handle Zsh,
    # but this is a robust fallback for older versions or custom setups.
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
fi

# --- NVM Automatic Version Switching ---
# This hook automatically runs 'nvm use' if an .nvmrc file is found in the
# current directory or any parent directory. This avoids the need to manually
# switch versions for each project.
# Based on the official nvm documentation for speeding up zsh.
autoload -U add-zsh-hook
load-nvmrc() {
    # Use nvm's logic to find the .nvmrc file upwards from the current directory
    local nvmrc_path="$(nvm_find_nvmrc)"
    if [ -n "$nvmrc_path" ]; then
        local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

        # If the version in .nvmrc is different from the current active version
        if [ "$nvmrc_node_version" != "N/A" ] && [ "$nvmrc_node_version" != "$(nvm version)" ]; then
            nvm use --silent
        fi
    # If no .nvmrc is found, revert to the default version
    elif [ "$(nvm version)" != "$(nvm version default)" ]; then
        nvm use default --silent
    fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc # Run once on startup

# ==============================================================================
# 6. PATH Configuration
# ==============================================================================
# Use Zsh's `path` array to avoid duplicates and simplify management.
typeset -U path

# Prepend OS-specific paths
if [[ "$IS_MAC" == "true" ]]; then
    path+=(
        "$HOMEBREW_PREFIX/bin"
        "$HOMEBREW_PREFIX/sbin"
        # Add any opt-in paths for tools that Homebrew doesn't symlink automatically
        "$HOMEBREW_PREFIX/opt/libpq/bin"
    )
fi

# Prepend common user paths (Cross-Platform)
path+=(
    "$HOME/.docker/bin"    # For Docker tools
    "$HOME/.local/bin"     # For pipx and uv
    "$HOME/.cargo/bin"     # For Rust
    "$(go env GOPATH)/bin" # For Go
    "$HOME/.dotnet/tools"  # For .NET
)

# ==============================================================================
# 7. Functions & Final Hooks
# ==============================================================================
# --- Load Custom Functions ---
# Make your helper functions available before they are used by aliases or other scripts.
for func_file in ~/.zsh_python_functions ~/.zsh_node_functions ~/.zsh_docker_functions; do
    [ -f "$func_file" ] && source "$func_file"
done

# --- Hook Direnv into the Shell ---
# IMPORTANT: This must be one of the last things in your .zshrc.
# It needs to hook into the prompt after Oh My Zsh and P10k have finished setting it up.
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# Prevent "zsh: no matches found" error
setopt nonomatch

# ==============================================================================
# 8. Aliases & Functions
# ==============================================================================
# --- Common Aliases (Cross-Platform) ---
alias cls="clear"; alias ..="cd .."; alias ....="cd ../.."; alias ~="cd ~"
alias ll="lsd -al" # Requires lsd (https://github.com/lsd-rs/lsd)
alias search="grep --color=auto -rnw . -e "
alias pip="uv pip"
alias python="$(get_uv_python_path $PYTHON_DEFAULT_VERSION)"
alias python3="$(get_uv_python_path $PYTHON_DEFAULT_VERSION)"
py313() { "$(get_uv_python_path 3.13)" "$@"; }; py312() { "$(get_uv_python_path 3.12)" "$@"; }
py311() { "$(get_uv_python_path 3.11)" "$@"; }; py310() { "$(get_uv_python_path 3.10)" "$@"; }

# --- Node.js 'npx' Aliases ---
# Use npx to run commands without installing them globally. This avoids
# having to reinstall them for every Node version with nvm.
alias serve='npx http-server'
alias tsc='npx -p typescript tsc'

# --- OS-Specific Functions & Aliases ---

# First, remove any existing 'ports' alias to prevent conflicts when defining
# the function below. Errors are hidden for clean startup.
unalias ports 2>/dev/null || true

# NOTE: We use a function for `ports` on all systems to avoid Zsh parsing
# conflicts that can occur when conditionally defining an alias and a function
# with the same name.

if [[ "$IS_MAC" == "true" ]]; then
    # macOS-specific function for listing ports
    ports() {
        # Pass all arguments ($@) to lsof for filtering (e.g., ports -i :8080)
        sudo lsof -PiTCP -sTCP:LISTEN "$@"
    }

    alias studio="open -a \"Android Studio\" "

    # Java version management (macOS specific)
    export JAVA_11_HOME=$(/usr/libexec/java_home -v11 2>/dev/null)
    alias java11='[ -n "$JAVA_11_HOME" ] && export JAVA_HOME=$JAVA_11_HOME || echo "Java 11 not found"'
else
    # Generic Linux / WSL Function for listing ports
    ports() {
        if command -v ss &>/dev/null; then
            # Pass all arguments ($@) to ss for filtering
            sudo ss -tulpn "$@"
        elif command -v netstat &>/dev/null; then
            # Pass all arguments ($@) to netstat for filtering
            sudo netstat -tulpn "$@"
        else
            echo "Error: Neither 'ss' nor 'netstat' command found." >&2
            echo "Please install 'iproute2' (for ss) or 'net-tools' (for netstat)." >&2
            return 1
        fi
    }
fi


# ==============================================================================
# 9. Welcome / Onboarding Scripts
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

# ==============================================================================
# 10. Load Private & Machine-Specific Configuration
# ==============================================================================
#
# For settings that are unique to this specific machine or contain sensitive
# information, create a file at ~/.zshrc.private.
#
# This file is for:
#   - API keys and other secrets (e.g., export OPENAI_API_KEY="...")
#   - Aliases for scripts that only exist on this machine.
#   - PATH exports for tools installed in non-standard, local-only locations.
#
# IMPORTANT: This file should NEVER be checked into version control (e.g., Git).
# Be sure to add ~/.zshrc.private to your .gitignore file.
#
if [[ -f ~/.zshrc.private ]]; then
    source ~/.zshrc.private
fi
