# ==============================================================================
# Environment Variables
# ==============================================================================
export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8
# Note: Setting LC_ALL typically makes other LC_* vars redundant, but explicit is fine.
# export LC_COLLATE=en_AU.UTF-8
# export LC_CTYPE=en_AU.UTF-8
# export LC_MESSAGES=en_AU.UTF-8
# export LC_MONETARY=en_AU.UTF-8

# Prevent pip from running outside a virtual environment
export PIP_REQUIRE_VIRTUALENV=true

# Opt-out of .NET CLI telemetry
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# Zsh & Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# NVM Directory (ensure it matches your installation location)
export NVM_DIR="$HOME/.nvm"

# ==============================================================================
# Oh My Zsh Configuration
# ==============================================================================

# Theme (Powerlevel10k)
ZSH_THEME="powerlevel10k/powerlevel10k"

# Oh My Zsh Plugins
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git
    docker # Ensure completions are handled below if necessary
    zsh-autosuggestions
    zsh-syntax-highlighting
    # zsh-completions # Can sometimes conflict with brew's completions or be slow. Test if needed.
    vscode
    history-substring-search
    # shellfirm # Removed as per comments
)

# Source Oh My Zsh
# IMPORTANT: This should typically come *after* plugin definitions and basic env vars,
# but *before* things that rely on OMZ functions/aliases (like P10k sourcing or plugin configs)
# However, P10k instant prompt requires being very early.
# Let's keep OMZ source later as per its standard practice.

# ==============================================================================
# Completions & Initializations
# ==============================================================================

# Zsh Completions
# If you uncomment the zsh-completions plugin above, this might be redundant
# or need coordination. If not using the plugin, this is the standard way.
autoload -U +X compinit && compinit

# Enable Powerlevel10k instant prompt. Should stay close to the top.
# Initialization code that may require console input must go above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Load NVM
# Ensure the path `/usr/local/opt/nvm/nvm.sh` is correct for your Homebrew setup
[ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh" --no-use # Load nvm without using default node
# Load NVM bash_completion (often handled automatically by nvm script or zsh completion system)
[ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"

# Pipx Completions
# Check if command exists before running eval to prevent errors if pipx isn't installed
command -v register-python-argcomplete >/dev/null && eval "$(register-python-argcomplete pipx)"

# UV Completions
command -v uv >/dev/null && eval "$(uv generate-shell-completion zsh)"
command -v uvx >/dev/null && eval "$(uvx --generate-shell-completion zsh)"

# FZF Setup (Key bindings and fuzzy completion)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Source Oh My Zsh (Standard location)
source "$ZSH/oh-my-zsh.sh"

# Source Powerlevel10k Theme
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Docker Desktop Completions (Added by Docker)
# Check if the directory exists to avoid errors
[ -d "$HOME/.docker/completions" ] && fpath=("$HOME/.docker/completions" $fpath)
# Note: OMZ or the primary compinit call should handle initializing completions.
# Redundant calls to compinit can slow down startup. Avoid if possible.
# autoload -Uz compinit
# compinit

# ==============================================================================
# PATH Configuration
# ==============================================================================
# Start with a clean slate to control order explicitly.
PATH=""

# Homebrew (Recommended location: /opt/homebrew for Apple Silicon, /usr/local for Intel)
# Adjust if your Homebrew prefix is different
HOMEBREW_PREFIX="/usr/local" # Change if needed (e.g., /opt/homebrew)
export PATH="$HOMEBREW_PREFIX/bin:$PATH"
export PATH="$HOMEBREW_PREFIX/sbin:$PATH"

# Standard system paths
export PATH="$PATH:/usr/bin"
export PATH="$PATH:/bin"
export PATH="$PATH:/usr/sbin"
export PATH="$PATH:/sbin"

# Tool-specific paths (Managed by Homebrew)
# Add paths for tools installed via brew that aren't automatically linked
export PATH="$HOMEBREW_PREFIX/opt/sqlite/bin:$PATH" # Example if needed, seems related to MONO below
export PATH="$HOMEBREW_PREFIX/opt/tcl-tk/bin:$PATH"
export PATH="$HOMEBREW_PREFIX/opt/php@8.1/bin:$PATH"
export PATH="$HOMEBREW_PREFIX/opt/php@8.1/sbin:$PATH"
export PATH="$HOMEBREW_PREFIX/opt/postgresql@16/bin:$PATH"
export PATH="$HOMEBREW_PREFIX/opt/libpq/bin:$PATH"
# export PATH="$HOMEBREW_PREFIX/opt/fzf/bin:$PATH" # Usually linked by brew into $HOMEBREW_PREFIX/bin

# User-specific bin directories
export PATH="$PATH:$HOME/.local/bin" # For pipx, uv bins, etc.
export PATH="$PATH:$HOME/.cargo/bin" # Rust cargo
export PATH="$PATH:$HOME/.dotnet/tools" # .NET tools

# Other system paths (Add if necessary)
export PATH="$PATH:/Library/Apple/usr/bin"
# export PATH="$PATH:/Library/TeX/texbin" # Uncomment if you use TeX

# Ensure NVM path is handled dynamically by the NVM script, not hardcoded here.
# Ensure virtual environment bin paths get prepended when activated (handled by activate scripts)

# ==============================================================================
# Aliases
# ==============================================================================

# ---- General ----
alias cls="clear"
alias ..="cd .."
alias ....="cd ../.."
alias ~="cd ~"
alias desk="cd ~/Desktop"
alias down="cd ~/Downloads"
alias ll="lsd -al" # Requires lsd to be installed
# alias ls="ls -G" # Basic colorized ls as fallback

# ---- File System & Search ----
alias look="sudo find . -name" # Find by name
alias search="grep --color=auto -rnw . -e " # Search for text in files recursively
alias ports="sudo lsof -PiTCP -sTCP:LISTEN" # Show listening ports

# ---- Development ----
alias studio="open -a \"Android Studio\" " # Open Android Studio
alias vi="nvim" # Use Neovim
alias vim="nvim"
alias aider="source $HOME/.local/share/aider/.venv/bin/activate && aider" # Aider (consider installing globally via pipx if possible)

# ---- Python (using UV) ----
alias pip="uv pip" # Always use uv for pip operations
alias python="python3" # Ensure python points to python3

# Python version shortcuts (requires specific uv installations)
alias py313="$HOME/.local/share/uv/python/cpython-3.13.0-macos-x86_64-none/bin/python3.13" # Adjust path/version if needed
alias py312="$HOME/.local/share/uv/python/cpython-3.12.7-macos-x86_64-none/bin/python3.12" # Adjust path/version if needed
alias py311="$HOME/.local/share/uv/python/cpython-3.11.10-macos-x86_64-none/bin/python3.11" # Adjust path/version if needed
alias py310="$HOME/.local/share/uv/python/cpython-3.10.15-macos-x86_64-none/bin/python3.10" # Adjust path/version if needed

# ---- Java Version Management ----
# These rely on /usr/libexec/java_home (macOS specific)
export JAVA_8_HOME=$(/usr/libexec/java_home -v1.8 2>/dev/null)
export JAVA_11_HOME=$(/usr/libexec/java_home -v11 2>/dev/null)
export JAVA_13_HOME=$(/usr/libexec/java_home -v13 2>/dev/null)
export JAVA_16_HOME=$(/usr/libexec/java_home -v16 2>/dev/null)
alias java8='[ -n "$JAVA_8_HOME" ] && export JAVA_HOME=$JAVA_8_HOME || echo "Java 8 not found"'
alias java11='[ -n "$JAVA_11_HOME" ] && export JAVA_HOME=$JAVA_11_HOME || echo "Java 11 not found"'
alias java13='[ -n "$JAVA_13_HOME" ] && export JAVA_HOME=$JAVA_13_HOME || echo "Java 13 not found"'
alias java16='[ -n "$JAVA_16_HOME" ] && export JAVA_HOME=$JAVA_16_HOME || echo "Java 16 not found"'
# Set a default Java version if desired, e.g.:
# java11

# ---- Multimedia (FFmpeg) ----
# Assumes ffmpeg apps are in a specific location. Consider adding this dir to PATH instead.
# export PATH="$PATH:$HOME/Documents/apps"
alias ffmpeg="$HOME/Documents/apps/ffmpeg"
alias ffprobe="$HOME/Documents/apps/ffprobe"
alias ffplay="$HOME/Documents/apps/ffplay"

# ---- Custom Scripts ----
alias merge_tracks='$HOME/merge_tracks.sh' # Run custom script
alias repomix="repomix" # Assuming repomix is a function or script in PATH

# ---- Network ----
alias speedtest="wget -O /dev/null cachefly.cachefly.net/10mb.test" # Simple download speed test

# ==============================================================================
# Settings & Options
# ==============================================================================

# Prevent "zsh: no matches found" error for patterns like *
setopt nonomatch

# Settings for MONO (macOS specific, related to brew install mono)
# Check if these are still needed; often handled by pkg-config automatically if set up correctly.
#export LDFLAGS="-L/usr/local/opt/sqlite/lib $LDFLAGS"
#export CPPFLAGS="-I/usr/local/opt/sqlite/include $CPPFLAGS"
#export PKG_CONFIG_PATH="/usr/local/opt/sqlite/lib/pkgconfig:$PKG_CONFIG_PATH"
#export MONO_GAC_PREFIX="/usr/local"
#export FrameworkPathOverride="/Library/Frameworks/Mono.framework/Versions/Current"

# =====> ADD DIRENV HOOK HERE <=====
# Hook direnv into the shell
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi
# ==================================

# ==============================================================================
# Custom Functions & Final Steps
# ==============================================================================

# Load custom functions
if [ -f ~/.zsh_functions ]; then
    source ~/.zsh_functions
else
    echo "Warning: ~/.zsh_functions not found."
fi

# Shell Integration (needed for Cmd+Click, etc., in VSCode Terminal)
# Uncomment if needed
# [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

# Ensure virtual environment PATH takes precedence if active
# This might be redundant if activate scripts work correctly, but provides robustness.
if [[ -n "$VIRTUAL_ENV" ]]; then
    if [[ ":$PATH:" != *":$VIRTUAL_ENV/bin:"* ]]; then
        export PATH="$VIRTUAL_ENV/bin:$PATH"
    fi
fi

# echo "Zsh config loaded." # Uncomment for debugging startup