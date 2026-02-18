# ==============================================================================
#  Unified Zsh Configuration for macOS, Linux & WSL
# ==============================================================================

# Profiling support - run with: ZPROF=1 zsh
[[ -n "$ZPROF" ]] && zmodload zsh/zprof

# ==============================================================================
# 1. Core Path Configuration (CRITICAL)
# ==============================================================================
# Set the most important user paths FIRST. This ensures that tools installed by
# scripts (like uv, fzf) are available immediately in the same session,
# preventing startup loops. The `typeset -U path` later will de-duplicate.
export PATH="$HOME/.fzf/bin:$HOME/.local/bin:$PATH"


# ==============================================================================
# 2. Environment Variables
# ==============================================================================
# --- Cross-Platform Environment ---
export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8

# --- Editor ---
export EDITOR=nvim

# --- History ---
export HISTFILE=~/.zsh_history
export HISTSIZE=50000
export SAVEHIST=50000
setopt EXTENDED_HISTORY          # Write timestamp to history
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicates first
setopt HIST_IGNORE_DUPS          # Don't record duplicates
setopt HIST_IGNORE_ALL_DUPS      # Delete old duplicates
setopt HIST_FIND_NO_DUPS         # Don't display duplicates
setopt HIST_IGNORE_SPACE         # Don't record commands starting with space
setopt HIST_SAVE_NO_DUPS         # Don't write duplicates
setopt SHARE_HISTORY             # Share history between sessions

# --- Globbing & Error Handling ---
setopt EXTENDED_GLOB        # Use extended globbing syntax
setopt NULL_GLOB            # Don't error on no matches, just return empty
setopt NUMERIC_GLOB_SORT    # Sort filenames numerically

# --- Python ---
export PIP_REQUIRE_VIRTUALENV=true
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PROMPT_EOL_MARK="" # Disable Powerlevel10k instant prompt
: ${PYTHON_MIN_VERSION:="3.8"}
: ${PYTHON_MAX_VERSION:="3.14"}
: ${PYTHON_DEFAULT_VERSION:="3.13"} # Using major.minor for consistency
: ${PYTHON_VERSION_PATTERN:="^3\.(8|9|1[0-4])$"}

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

# --- pnpm ---
export PNPM_HOME="$HOME/Library/pnpm"

# --- PHP ---
export WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR^E_PARSE^E_COMPILE_ERROR -d display_errors=0"

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
export CLAUDE_CODE_ENABLE_TELEMETRY=0; export DISABLE_BUG_COMMAND=1
export DISABLE_ERROR_REPORTING=1


# ==============================================================================
# 3. OS Detection
# ==============================================================================
export IS_MAC=false
export IS_WSL=false
export IS_LINUX=false
export MAC_ARCH=""
export HOMEBREW_PREFIX=""

case "$(uname -s)" in
    Darwin)
        IS_MAC=true
        MAC_ARCH="$(uname -m)"  # "arm64" or "x86_64"
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

# --- Secrets from Keychain (macOS only) ---
# Tokens stored in macOS Keychain — no plaintext secrets in config files.
# To add a token: security add-generic-password -a "$USER" -s "github-pat" -w "YOUR_TOKEN"
if [[ "$IS_MAC" == "true" ]]; then
    export GITHUB_PERSONAL_ACCESS_TOKEN="$(security find-generic-password -a "$USER" -s github-pat -w 2>/dev/null)"
fi


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


# ==============================================================================
# 5. Full PATH Configuration
# ==============================================================================
# --- WSL GPU Support (for SSH access) ---
# WSL stores Windows NVIDIA drivers here. When SSHing into WSL, this path
# isn't automatically added, so we add it manually for GPU access.
if [[ "$IS_WSL" == "true" && -d "/usr/lib/wsl/lib" ]]; then
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    path+=("/usr/lib/wsl/lib")
fi

# Use Zsh's `path` array to manage the path and ensure that the path array contains only unique entries (no duplicates).
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
    "$HOME/.local/bin"     # This will be de-duplicated by `typeset -U`
    "$HOME/.cargo/bin"     # For Rust
	"$HOME/.dotnet/tools"  # For .NET
)
# Only add the Go path if the 'go' command actually exists.
if command -v go &>/dev/null; then
    path+=("$(go env GOPATH)/bin")
fi

# Prepend macOS-specific paths
if [[ "$IS_MAC" == "true" ]]; then
    path+=(
		"$HOME/.turso" # Turso
		"$HOME/.antigravity/antigravity/bin" # Antigravity
		"$HOME/Library/pnpm" # pnpm
		"$PNPM_HOME" # pnpm home
		"$HOME/Library/Application Support/Local/lightning-services/mysql-8.0.35+4/bin/darwin/bin" # MySQL from Local dev tool
    )
fi


# ==============================================================================
# 6. UI, Zsh, Oh My Zsh & Powerlevel10k
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
plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting zsh-completions vscode history-substring-search)

# --- Add to fpath BEFORE sourcing Oh My Zsh ---
# This ensures OMZ's `compinit` call finds these completion files.
if [[ "$IS_MAC" == "true" && -d "$HOME/.docker/completions" ]]; then
    # Suggested by Docker Desktop to enable Docker CLI completions.
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
command -v uv >/dev/null && eval "$(uv generate-shell-completion zsh)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh


# ==============================================================================
# 7. NVM (Node Version Manager)
# ==============================================================================
# --- NVM Setup ---
# Official, unified loading script for script-based installations.
# This snippet is based on the official NVM README for robustness and XDG compliance.
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"

# If NVM is installed, load it but don't activate Node yet.
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use

# --- NVM Automatic Version Switching ---
# This hook automatically runs 'nvm use' if an .nvmrc file is found in the
# current directory or any parent directory. This avoids the need to manually
# switch versions for each project.
# Based on the official nvm documentation for speeding up zsh.
autoload -U add-zsh-hook

# --- NVM Automatic Version Switching ---
# Automatically switches to the Node version specified in .nvmrc if found in the current directory
# (or parent directories), otherwise reverts to the default Node version
load-nvmrc() {
	# Ensure nvm command is available before trying to use it
    if ! command -v nvm &>/dev/null; then return; fi

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

# Runs the load-nvmrc function automatically every time you change directories.
add-zsh-hook chpwd load-nvmrc

# Runs the load-nvmrc function automatically when the shell starts.
command -v nvm &>/dev/null && load-nvmrc


# ==============================================================================
# 8. Functions & Final Hooks
# ==============================================================================
# --- Load Custom Functions ---
# Make your helper functions available before they are used by aliases or other scripts.
# Added ~/.zsh_cursor_functions to this loop
for func_file in ~/.zsh_python_functions ~/.zsh_node_functions ~/.zsh_docker_functions ~/.zsh_cursor_functions; do
    [ -f "$func_file" ] && source "$func_file"
done

# --- Yazi File Manager Integration ---
# Navigate directories visually and have the shell follow your location on exit
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# --- Performance Profiling ---
# Time how long your shell takes to start
timezsh() {
    shell=${1-$SHELL}
    for i in $(seq 1 10); do time $shell -i -c exit; done
}
# Profile which parts of .zshrc are slow
profilezsh() {
    ZPROF=1 zsh -i -c exit
}

# To hide direnv messages to be displayed in the terminal, added `hide_env_diff = true` in
# this file: `~/.config/direnv/direnv.toml`

# --- Hook Direnv into the Shell ---
# IMPORTANT: This must be one of the last things in your .zshrc.
# It needs to hook into the prompt after Oh My Zsh and P10k have finished setting it up.
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# Prevent "zsh: no matches found" error
setopt nonomatch


# ==============================================================================
# 9. Aliases & Functions
# ==============================================================================
# --- Common Aliases (Cross-Platform) ---
alias cls="clear"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ~="cd ~"
# alias ll="lsd -altr" # Requires lsd (https://github.com/lsd-rs/lsd)
# alias l="lsd -altr"
alias l="eza -l --git --grid --color=always --icons=always --no-quotes --hyperlink -a -s modified --time modified --git-repos-no-status"
alias ll="eza -l --git --time-style relative --color=always --icons=always --no-quotes --hyperlink -a -s modified --time modified --git-repos-no-status"
alias search="grep --color=auto -rnw . -e "
# Hijack pip to intercept install/uninstall and redirect to uv add/remove.
# Read-only subcommands (list, show, freeze, check) pass through to uv pip.
# Note: internal helper functions call `uv pip` directly, bypassing this function.
pip() {
    case "$1" in
        install)
            # Allow editable installs — these are a legitimate uv pip workflow
            if [[ "$*" == *"-e"* ]]; then
                echo "${info}ℹ️  Passing editable install through to uv pip.${done}"
                echo
                command uv pip "${@}"
                return
            fi
            echo "${warn}⚠️  pip install is not used on this system. Use uv add instead.${done}"
            echo
            # Detect -r/--requirement flag for requirements file installs
            if [[ "$*" == *"-r "* || "$*" == *"--requirement "* ]]; then
                echo "  Instead of:  ${err}pip install ${@:2}${done}"
                echo "  Run:         ${ok}uv add -r <requirements-file>${done}"
                echo "  Or:          ${ok}uv pip sync <requirements-file>${done}"
            else
                echo "  Instead of:  ${err}pip install ${@:2}${done}"
                echo "  Run:         ${ok}uv add ${@:2}${done}"
            fi
            ;;
        uninstall)
            echo "${warn}⚠️  pip uninstall is not used on this system. Use uv remove instead.${done}"
            echo
            echo "  Instead of:  ${err}pip uninstall ${@:2}${done}"
            echo "  Run:         ${ok}uv remove ${@:2}${done}"
            ;;
        *)
            # Pass through read-only and other subcommands (list, show, freeze, check, etc.)
            command uv pip "${@}"
            ;;
    esac
}

# Hijack pipx to redirect users to uv tool equivalents.
# pipx is no longer used on this system — uv tool replaces it entirely.
pipx() {
    echo "${warn}⚠️  pipx is no longer used on this system. Use uv tool instead.${done}"
    echo
    case "$1" in
        install)
            echo "  Instead of:  ${err}pipx install ${@:2}${done}"
            echo "  Run:         ${ok}uv tool install ${@:2}${done}"
            ;;
        uninstall)
            echo "  Instead of:  ${err}pipx uninstall ${@:2}${done}"
            echo "  Run:         ${ok}uv tool uninstall ${@:2}${done}"
            ;;
        run)
            echo "  Instead of:  ${err}pipx run ${@:2}${done}"
            echo "  Run:         ${ok}uvx ${@:2}${done}"
            ;;
        list)
            echo "  Instead of:  ${err}pipx list${done}"
            echo "  Run:         ${ok}uv tool list --show-paths${done}"
            ;;
        upgrade|upgrade-all)
            echo "  Instead of:  ${err}pipx $1 ${@:2}${done}"
            echo "  Run:         ${ok}uv tool upgrade ${@:2}${done}"
            ;;
        inject)
            echo "  Instead of:  ${err}pipx inject ${@:2}${done}"
            echo "  Run:         ${ok}uv tool install --with <extra-pkg> <tool-pkg>${done}"
            ;;
        *)
            echo "  General replacement: ${ok}uv tool ${@}${done}"
            echo
            echo "  Common commands:"
            echo "    ${example}uv tool install <package>${done}    # Install a CLI tool globally"
            echo "    ${example}uv tool uninstall <package>${done}  # Remove a CLI tool"
            echo "    ${example}uv tool list --show-paths${done}    # List installed tools"
            echo "    ${example}uv tool upgrade <package>${done}    # Upgrade a tool"
            echo "    ${example}uvx <package>${done}                # Run a tool without installing"
            ;;
    esac
}

# Hijack npx to redirect users to pnpm dlx equivalents.
# npx is no longer used on this system — pnpm dlx replaces it entirely.
npx() {
    echo "${warn}⚠️  npx is not used on this system. Use pnpm dlx instead.${done}"
    echo
    echo "  Instead of:  ${err}npx $@${done}"
    echo "  Run:         ${ok}pnpm dlx $@${done}"
}

alias chawan="cha"
alias web="cha"
alias www="cha"
alias lzd='lazydocker'
alias lzg='lazygit'
alias lg='lazygit'
# ── Claude Code ──────────────────────────────────────────────────────
# Agent teams (still experimental opt-in), hide account info for recordings
_claude_env="CLAUDE_CODE_HIDE_ACCOUNT_INFO=1 ENABLE_EXPERIMENTAL_MCP_CLI=1"

alias c="${_claude_env} claude --dangerously-skip-permissions --permission-mode plan"       # Standard launch
alias ct="${_claude_env} CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions --permission-mode plan --teammate-mode tmux"  # Tmux agent teams
alias cb="${_claude_env} claude"                                                            # Bare (full control)
alias cr="${_claude_env} claude --dangerously-skip-permissions --resume"                    # Resume last session
alias ci="${_claude_env} claude --dangerously-skip-permissions -p"                          # Non-interactive / piped
alias cpr="${_claude_env} claude --dangerously-skip-permissions --from-pr"                  # Resume session from PR
alias cd_="${_claude_env} claude --dangerously-skip-permissions --permission-mode plan --verbose --debug"               # Debug (verbose logging)
alias cskip="${_claude_env} SKIP_SESSION_END_HOOK=1 claude --dangerously-skip-permissions --permission-mode plan"  # Skip end hooks

# Intercepting the use of a command like 'sudo claude update' :P
sudo() {
	if [[ "$1" == "claude" ]]; then
		echo "⚠️  Don't use sudo with claude commands!"
		echo "Running: claude ${@:2}"
		command claude "${@:2}"
	else
		command sudo "$@"
	fi
}


# --- yt-dlp Wrapper ---
# Custom wrapper for yt-dlp with simplified aliases defined in ~/.config/yt-dlp/config
yt() {
  # Auto-generate yt-dlp config if it doesn't exist
  local config_dir="$HOME/.config/yt-dlp"
  local config_file="$config_dir/config"
  if [[ ! -f "$config_file" ]]; then
    mkdir -p "$config_dir"
    cat > "$config_file" << 'YTCONFIG'
# =============================================================================
# yt-dlp Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Output & Filename
# -----------------------------------------------------------------------------
--output "%(upload_date)s - %(title)s [%(id)s].%(ext)s"
--restrict-filenames

# -----------------------------------------------------------------------------
# Default Behavior
# -----------------------------------------------------------------------------
--no-overwrites
--no-keep-video
--console-title

# Default format: 1080p + best audio (fallback to best available)
-f "bestvideo[height<=1080]+bestaudio/best"

# -----------------------------------------------------------------------------
# Embedding (into video file)
# -----------------------------------------------------------------------------
--embed-thumbnail
--embed-chapters
--embed-metadata
--embed-info-json
--clean-info-json

# -----------------------------------------------------------------------------
# Downloader
# -----------------------------------------------------------------------------
--downloader aria2c
--downloader "dash,m3u8:native"

# -----------------------------------------------------------------------------
# Aliases: Video
# -----------------------------------------------------------------------------
# --video: 1080p preferred, fallback to 720p
--alias video "-f bestvideo[height<=1080][height>=720]+bestaudio/best[height<=1080][height>=720]"

# --video-low: Best quality below 1080p
--alias video-low "-f bestvideo[height<1080]+bestaudio/best[height<1080]"

# --video-high: Next resolution above 1080p (e.g., 1440p)
--alias video-high "-f bestvideo[height>1080]+bestaudio/best[height>1080]"

# --video-highest: Maximum available resolution
--alias video-highest "-f bestvideo+bestaudio/best"

# -----------------------------------------------------------------------------
# Aliases: Audio
# -----------------------------------------------------------------------------
# --audio-only: Best audio, extracted to audio file
--alias audio-only "-f bestaudio -x"

# -----------------------------------------------------------------------------
# Aliases: Subtitles
# -----------------------------------------------------------------------------
# --subs: Download subtitles along with video
--alias subs "--write-subs --sub-format srt/ass/vtt --write-auto-subs"

# --subs-only: Download subtitles only, skip video
--alias subs-only "--write-subs --sub-format srt/ass/vtt --write-auto-subs --skip-download"

# -----------------------------------------------------------------------------
# Aliases: Metadata Only (standalone, skips video)
# -----------------------------------------------------------------------------
# --comments: Download comments only (to separate .comments.json)
--alias comments "--write-comments --no-write-info-json --skip-download --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json"

# --livechat: Download live chat only (for livestreams/premieres)
--alias livechat "--sub-langs live_chat --write-subs --skip-download"

# --description: Download video description only
--alias description "--write-description --skip-download"

# --thumbnail: Download video thumbnail only
--alias thumbnail "--write-thumbnail --skip-download"

# -----------------------------------------------------------------------------
# Aliases: Bundles (video/audio + all metadata)
# -----------------------------------------------------------------------------
# --bundle-video: Video + all metadata
--alias bundle-video "-f bestvideo[height<=1080][height>=720]+bestaudio/best[height<=1080][height>=720] --write-subs --sub-format srt/ass/vtt --write-auto-subs --write-comments --no-write-info-json --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json --sub-langs live_chat --write-description --write-thumbnail"

# --bundle-audio: Audio + all metadata
--alias bundle-audio "-f bestaudio -x --write-subs --sub-format srt/ass/vtt --write-auto-subs --write-comments --no-write-info-json --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json --sub-langs live_chat --write-description --write-thumbnail"

# --bundle: Video + all metadata (same as bundle-video)
--alias bundle "-f bestvideo[height<=1080][height>=720]+bestaudio/best[height<=1080][height>=720] --write-subs --sub-format srt/ass/vtt --write-auto-subs --write-comments --no-write-info-json --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json --sub-langs live_chat --write-description --write-thumbnail"

# --bundle-high: Highest video + all metadata
--alias bundle-high "-f bestvideo+bestaudio/best --write-subs --sub-format srt/ass/vtt --write-auto-subs --write-comments --no-write-info-json --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json --sub-langs live_chat --write-description --write-thumbnail"

# -----------------------------------------------------------------------------
# Aliases: Modifiers
# -----------------------------------------------------------------------------
# --overwrite: Force overwrite existing files
--alias overwrite "--force-overwrites"
YTCONFIG
    echo "${fg[green]}✓${reset_color} Created yt-dlp config at ${fg[cyan]}$config_file${reset_color}"
  fi

  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat << EOF
${fg[cyan]}yt${reset_color} - Custom yt-dlp wrapper

${fg[yellow]}USAGE${reset_color}
  yt [OPTIONS] URL

${fg[yellow]}VIDEO${reset_color}
  --video            1080p (fallback to 720p)
  --video-low        Below 1080p (next tier down)
  --video-high       Above 1080p (next tier up)
  --video-highest    Highest available resolution

${fg[yellow]}AUDIO${reset_color}
  --audio-only       Highest bitrate audio (extracts audio)

${fg[yellow]}EXTRAS ${fg[white]}(combine with video/audio options)${reset_color}
  --subs             Include subtitles (srt/ass/vtt)

${fg[yellow]}METADATA ONLY ${fg[white]}(standalone, skips video)${reset_color}
  --subs-only        Subtitles only
  --comments         Comments only (to .comments.json)
  --livechat         Live chat only (livestreams/premieres)
  --description      Video description only
  --thumbnail        Video thumbnail only

${fg[yellow]}BUNDLES ${fg[white]}(video/audio + all metadata)${reset_color}
  --bundle-video     1080p video + subs, comments, chat, desc, thumb
  --bundle-audio     Audio + subs, comments, chat, desc, thumb
  --bundle           Same as --bundle-video
  --bundle-high      Highest video + all metadata

${fg[yellow]}MODIFIERS${reset_color}
  --overwrite        Force overwrite existing files

${fg[yellow]}EXAMPLES${reset_color}
  ${fg[magenta]}yt https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}                   # 1080p + best audio (default)
  ${fg[magenta]}yt --video https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}           # 1080p/720p video
  ${fg[magenta]}yt --video --subs https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}    # video + subtitles
  ${fg[magenta]}yt --video-highest https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}   # max resolution
  ${fg[magenta]}yt --audio-only https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}      # extract audio
  ${fg[magenta]}yt --bundle https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}          # video + all metadata
  ${fg[magenta]}yt --thumbnail https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}       # thumbnail only
  ${fg[magenta]}yt --overwrite https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}       # re-download, overwrite

${fg[yellow]}DEFAULTS${reset_color}
  ${fg[white]}•${reset_color} Format: 1080p video + best audio (fallback: best available)
  ${fg[white]}•${reset_color} Output: ${fg[cyan]}%(upload_date)s - %(title)s [%(id)s].%(ext)s${reset_color}
  ${fg[white]}•${reset_color} Embeds: thumbnail, chapters, metadata, info.json
  ${fg[white]}•${reset_color} Restricted filenames (safe characters only)
  ${fg[white]}•${reset_color} Intermediate files auto-deleted after merge
  ${fg[white]}•${reset_color} No overwrites (use --overwrite to force)

${fg[yellow]}REQUIRES${reset_color}
  ${fg[white]}•${reset_color} aria2c (for faster downloads)

${fg[yellow]}CONFIG${reset_color}
  ${fg[cyan]}$config_file${reset_color}
EOF
  else
    yt-dlp "$@"
  fi
}


# --- OS Information Aliases ---
if [[ "$IS_WSL" == "true" ]] || [[ "$IS_LINUX" == "true" ]]; then
    alias os='cat /etc/os-release'
fi

# --- Zoxide ---
# https://github.com/ajeetdsouza/zoxide
# This makes zoxide respond to cd directly while keeping the real cd available as __zoxide_cd internally. This is the "official" way to replace cd
eval "$(zoxide init zsh --cmd cd)"

# --- OLD: Direct python resolution (replaced by uv run hijacks below) ---
# alias python="$(get_uv_python_path $PYTHON_DEFAULT_VERSION)"
# alias python3="$(get_uv_python_path $PYTHON_DEFAULT_VERSION)"
#
# # Use functions for python commands instead of aliases.
# # This avoids startup errors by checking for the python path only when the
# # command is actually run ("just-in-time"), not when the shell starts.
# # Priority: active venv > local .venv > local venv > uv global
# python() {
#     # Priority 1: If VIRTUAL_ENV is set (venv activated), use it
#     if [[ -n "$VIRTUAL_ENV" && -x "$VIRTUAL_ENV/bin/python" ]]; then
#         "$VIRTUAL_ENV/bin/python" "$@"
#         return
#     fi
#     # Priority 2: Check for local .venv in current directory
#     if [[ -x ".venv/bin/python" ]]; then
#         ".venv/bin/python" "$@"
#         return
#     fi
#     # Priority 3: Check for local venv in current directory
#     if [[ -x "venv/bin/python" ]]; then
#         "venv/bin/python" "$@"
#         return
#     fi
#     # Fallback: Use uv-managed global python
#     local python_path=$(get_uv_python_path "${PYTHON_DEFAULT_VERSION}")
#     if [[ -n "$python_path" ]]; then "$python_path" "$@"; else return 1; fi
# }
# # Commenting this!! Bad idea because it links to the system 'python' and not the uv venv's python
# # python3() { python "$@"; }
#
# py313() { "$(get_uv_python_path 3.13)" "$@"; }; py312() { "$(get_uv_python_path 3.12)" "$@"; }
# py311() { "$(get_uv_python_path 3.11)" "$@"; }; py310() { "$(get_uv_python_path 3.10)" "$@"; }
# --- END OLD ---

# Hijack python/python3 to redirect users to uv run equivalents.
# python/python3 should not be called directly — use uv run instead.
python() {
    echo "${warn}⚠️  python is not used directly on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}python $@${done}"
    echo "  Run:         ${ok}uv run python $@${done}"
}

python3() {
    echo "${warn}⚠️  python3 is not used directly on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}python3 $@${done}"
    echo "  Run:         ${ok}uv run python3 $@${done}"
}

py313() {
    echo "${warn}⚠️  py313 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py313 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.13 python $@${done}"
}

py312() {
    echo "${warn}⚠️  py312 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py312 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.12 python $@${done}"
}

py311() {
    echo "${warn}⚠️  py311 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py311 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.11 python $@${done}"
}

py310() {
    echo "${warn}⚠️  py310 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py310 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.10 python $@${done}"
}

# --- Node.js 'pnpm dlx' Aliases ---
# Use pnpm dlx to run commands without installing them globally. This avoids
# having to reinstall them for every Node version with nvm.
alias serve='pnpm dlx http-server'
alias tsc='pnpm dlx -p typescript tsc'

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
# 10. Welcome / Onboarding Scripts
# ==============================================================================
# Only run in interactive shells on first load.
# Verbosity controlled by ZSH_WELCOME and ZSH_WELCOME_QUICKREF (see Section 2).
# Auto-detects SSH/tmux sessions and adjusts verbosity accordingly.
if [[ -z "$_WELCOME_MESSAGE_SHOWN" && -t 1 ]]; then
    [ -f ~/.zsh_welcome ] && source ~/.zsh_welcome
    export _WELCOME_MESSAGE_SHOWN=true
fi

# End profiling
[[ -n "$ZPROF" ]] && zprof
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
