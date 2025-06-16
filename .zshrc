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

# Disable telemetry for the mem0 library (which includes browser-use)
export MEM0_TELEMETRY_DISABLED=true
export ANONYMIZED_TELEMETRY=false

# ==============================================================================
# UI & Color Helpers
# ==============================================================================
# Load colors and define global variables for consistent script output.
# These will be available to .zshrc and all functions sourced from .zsh_functions.
autoload -U colors && colors

ok="$fg[green]"
warn="$fg[yellow]"
err="$fg[red]"
info="$fg[cyan]"
example="$fg[magenta]"
done="$reset_color"
# ==============================================================================

# Zsh & Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# NVM Directory (ensure it matches your installation location)
export NVM_DIR="$HOME/.nvm"

# Powerlevel9k Instant Prompt (off by default)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

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

# Ensure PATH doesn't contain duplicates, which can cause some commands to not work.
typeset -U path

# Homebrew (Recommended location: /opt/homebrew for Apple Silicon, /usr/local for Intel)
if [[ -d /opt/homebrew ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

# Start with Homebrew to give it precedence, avoiding an empty initial PATH.
PATH="$HOMEBREW_PREFIX/bin"
PATH="$HOMEBREW_PREFIX/sbin:$PATH"

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
# if [[ -n "$VIRTUAL_ENV" ]]; then
#     if [[ ":$PATH:" != *":$VIRTUAL_ENV/bin:"* ]]; then
#         export PATH="$VIRTUAL_ENV/bin:$PATH"
#     fi
# fi

# =====> ADD DIRENV HOOK HERE <=====
# Hook direnv into the shell
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi
# ==================================


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
# alias vi="nvim" # Use Neovim
# alias vim="nvim"

# ---- Python (using UV) ----
alias pip="uv pip" # Always use uv for pip operations
alias python="python3" # Ensure python points to python3

# Python version shortcuts (requires specific uv installations)
py313() { "$(get_uv_python_path 3.13)" "$@"; }
py312() { "$(get_uv_python_path 3.12)" "$@"; }
py311() { "$(get_uv_python_path 3.11)" "$@"; }
py310() { "$(get_uv_python_path 3.10)" "$@"; }

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

# echo "Zsh config loaded." # Uncomment for debugging startup
# Task Master aliases added on 13/04/2025
alias tm='task-master'
alias taskmaster='task-master'
export REPLICATE_API_TOKEN=your_token_here


# ==============================================================================
# Python 3.13 Health Check & Onboarding for Homebrew and uv (zsh)
# ==============================================================================

# ---- Homebrew Python locations ----
BREW_PYTHON="/usr/local/bin/python3"
BREW_PYTHON_CELLAR="/usr/local/Cellar/python@3.13"
BREW_PYTHON_BIN="$BREW_PYTHON_CELLAR"/*/bin/python3.13

# ---- Homebrew presence check ----
HAVE_BREW=false
if command -v brew >/dev/null 2>&1; then
    HAVE_BREW=true
fi

echo
echo "${info}🛡️  Python Environment Check:${done}"

# ---- Show current python3 and its version ----
if command -v python3 >/dev/null 2>&1; then
    echo "    python3 path: $(which python3)"
    echo -n "    python3 version: "
    python3 --version
else
    echo "${err}    python3 not found in PATH.${done}"
fi

# ---- Check if python3 is Homebrew's 3.13 ----
show_onboarding_summary() {
    echo "${info}🚀  RECOMMENDED WORKFLOW: Use 'uv' for all Python project work!${done}"
    echo "------------------------------------------------------------------------------------------------"
    # echo
    # echo "${ok}How to make your Python project a system-wide CLI executable (no conflicts):${done}"
    # echo
    # echo "  1. Activate your project's venv:"
    # echo "         source .venv/bin/activate"
    # echo "  2. Build/install your project in 'editable' mode (from project root):"
    # echo "         uv pip install -e ."
    # echo "     (Make sure your pyproject.toml defines a [project.scripts] entry for your CLI!)"
    # echo
    # echo "  3. Install your CLI globally for your user using pipx (best practice!):"
    # echo "         pipx install --force \$(pwd)"
    # echo "     - This puts your CLI in ~/.local/bin, which should already be in your PATH."
    # echo "     - Each CLI installed with pipx has its own isolated virtualenv—no dependency conflicts."
    # echo "     - You can run your CLI from any folder, in any shell session."
    # echo
    # echo "  4. To update your CLI after you change your code:"
    # echo "         pipx reinstall <your-cli-name>"
    # echo
    # echo "  5. See all installed pipx CLIs and manage them:"
    # echo "         pipx list"
    # echo "         pipx upgrade <your-cli-name>"
    # echo "         pipx uninstall <your-cli-name>"
    # echo "------------------------------------------------------------------------------------------------"
    echo "${ok}Custom Shell Helper Functions (.zsh_functions):${done}"
    echo
    echo "  1. ${info}python_setup <major.minor>${done}"
    echo "      - Sets up (or recreates) .venv for the ${warn}existing${done} Python project using the specified Python."
    echo "      - Example: ${example}python_setup 3.13${done}"
    echo
    echo "  2. ${info}python_new_project <major.minor>${done}"
    echo "      - Scaffolds a ${warn}new${done} Python project in the current folder."
    echo "      - Example: ${example}python_new_project 3.13${done}"
    echo
    echo "  3. ${info}python_delete${done}"
    echo "      - ${warn}Cleans up${done} all typical Python project artifacts (.venv, caches, build, etc.)."
    echo
    echo "  4. ${info}pipx_install_current_project${done}"
    echo "      - Installs the ${warn}current project${done} as a global user CLI (isolated by pipx, no conflicts)."
    echo
    echo "  5. ${info}pipx_reinstall_current_project${done}"
    echo "      - Reinstalls the global user CLI after local code changes."
    echo
    echo "  6. ${info}pipx_uninstall_current_project${done}"
    echo "      - Uninstalls the global CLI for the current project."
    echo
    echo "  7. ${info}pipx_check_current_project${done}"
    echo "      - ${warn}Checks${done} if the current project is installed via pipx and reports executable locations."
    echo "------------------------------------------------------------------------------------------------"
    echo
}

main_python_path=$(which python3 2>/dev/null)
resolved_link=$(readlink "$main_python_path" 2>/dev/null || echo "")

if [[ -x "$BREW_PYTHON" && "$resolved_link" == *"Cellar/python@3.13"* ]]; then
    echo "${ok}✅  Homebrew Python 3.13 detected at $BREW_PYTHON.${done}"
    show_onboarding_summary
    return 0
fi

# ---- Handle various "not Homebrew" situations ----
if [[ -n "$main_python_path" ]]; then
    resolved_link=$(readlink "$main_python_path" 2>/dev/null || echo "")
    if [[ "$resolved_link" == *"Cellar/python@3.13"* ]]; then
        echo "${ok}✅  Homebrew Python 3.13 detected at $main_python_path (via symlink).${done}"
        show_onboarding_summary
        return 0
    elif [[ "$main_python_path" == "/usr/bin/python3" ]]; then
        echo "${warn}⚠️  WARNING: Your 'python3' is the system Python at /usr/bin/python3 (not recommended for projects).${done}"
    else
        echo "${warn}⚠️  WARNING: Your 'python3' is at $main_python_path (symlink: $resolved_link), and is NOT Homebrew's python@3.13.${done}"
    fi
else
    echo "${err}    python3 not found at all.${done}"
fi

# ---- Check if Homebrew's python@3.13 is installed but not linked ----
if $HAVE_BREW; then
    if [[ -d "$BREW_PYTHON_CELLAR" ]] && ls $BREW_PYTHON_BIN >/dev/null 2>&1; then
        echo "${ok}    Homebrew Python 3.13 is installed at: $BREW_PYTHON_BIN${done}"
        # Offer to link if needed
        if [[ ! -x "$BREW_PYTHON" || "$(readlink "$BREW_PYTHON")" != *"Cellar/python@3.13"* ]]; then
            if [[ -t 1 ]]; then
                echo
                read "REPLY?    👉 Would you like to link Homebrew Python 3.13 as 'python3'? [y/N] "
                case "$REPLY" in
                    [yY][eE][sS]|[yY])
                        echo "${info}    Linking python@3.13...${done}"
                        brew link python@3.13 --overwrite --force
                        if [[ $? -eq 0 ]]; then
                            echo "${ok}    ✅ python@3.13 linked as python3! Please restart your terminal.${done}"
                        else
                            echo "${err}    ❌ Failed to link python@3.13. See brew errors above.${done}"
                        fi
                        ;;
                    *)
                        echo "${warn}    Skipping Homebrew Python linking.${done}"
                        ;;
                esac
            else
                echo "    (Non-interactive shell; skipping auto-link prompt.)"
            fi
        fi
        # Even if not linked, we can use uv!
        show_onboarding_summary
        return 0
    else
        echo "${warn}    Homebrew Python 3.13 not installed.${done}"
        if [[ -t 1 ]]; then
            read "REPLY?    👉 Would you like to install Homebrew Python 3.13 now? [y/N] "
            case "$REPLY" in
                [yY][eE][sS]|[yY])
                    echo "${info}    Installing python@3.13 via Homebrew...${done}"
                    brew install python@3.13
                    if [[ $? -eq 0 ]]; then
                        echo "${ok}    ✅ python@3.13 installed! Please restart your terminal.${done}"
                    else
                        echo "${err}    ❌ Installation failed. Check Homebrew errors above.${done}"
                    fi
                    ;;
                *)
                    echo "${warn}    Skipping Homebrew Python 3.13 installation.${done}"
                    ;;
            esac
        else
            echo "    (Non-interactive shell; skipping install prompt.)"
        fi
    fi
else
    echo "${err}    Homebrew is not installed, so Homebrew Python can't be managed.${done}"
    echo "    Install Homebrew first: https://brew.sh/"
fi

echo
echo "${info}    If you skip this, 'uv' will manage Python versions for your projects in ~/.local/share/uv/python/.${done}"
echo "    New venvs will use the closest match, and 'uv' will download what you need."
echo

# Display Python / uv related info
show_onboarding_summary



# ==============================================================================
# Settings & Options
# ==============================================================================

# Prevent "zsh: no matches found" error for patterns like *
setopt nonomatch

