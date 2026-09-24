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
export PATH="$HOME/.local/bin:$HOME/.docker/bin:$PATH"


# ==============================================================================
# 2. Environment Variables
# ==============================================================================
# --- Cross-Platform Environment ---
export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8

# --- Editor ---
if command -v nvim &>/dev/null; then
    export EDITOR=nvim
elif command -v vim &>/dev/null; then
    export EDITOR=vim
else
    export EDITOR=vi
fi

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
setopt RM_STAR_WAIT         # 10-second wait before confirming wildcard deletions (rm path/*)

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
#   - "full"    : Complete multi-line overview (DEFAULT — used when unset)
#   - "minimal" : Single-line compact status
#   - "none"    : No overview displayed
# Override per-machine in ~/.zshrc.private if you want non-default verbosity.
: ${ZSH_WELCOME:=""}

# ZSH_WELCOME_QUICKREF: Controls quick reference display (independent of ZSH_WELCOME)
#   - "full"    : Multi-line categorized reference
#   - "minimal" : Compact 2-line hints
#   - "none"    : No quick reference displayed
: ${ZSH_WELCOME_QUICKREF:="full"}

# ZSH_WELCOME_DISK_WARN: Disk usage percentage threshold for warning (default: 90)
: ${ZSH_WELCOME_DISK_WARN:=90}

# --- bun ---
export BUN_INSTALL="$HOME/.bun"

# --- PHP ---
export WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR^E_PARSE^E_COMPILE_ERROR -d display_errors=0"

# --- Telemetry Opt-Out ---
export ALCHEMY_TELEMETRY_DISABLED=1; export ANONYMIZED_TELEMETRY=false
export ARTILLERY_DISABLE_TELEMETRY=true; export AWS_CLI_TELEMETRY_OPTOUT=1
export AZURE_TELEMETRY_OPTOUT=true; export CLAUDE_CODE_ENABLE_TELEMETRY=0
export CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=true; export CREWAI_DISABLE_TELEMETRY=true
export DISABLE_BUG_COMMAND=1; export DISABLE_ERROR_REPORTING=1
export DISABLE_TELEMETRY=true; export DO_NOT_TRACK=1
export DOTNET_CLI_TELEMETRY_OPTOUT=true; export DOTNET_NOLOGO=true
export GRAPHITI_TELEMETRY_ENABLED=false; export HOMEBREW_NO_ANALYTICS=1
export JUPYTER_NO_TELEMETRY=1
export MEM0_TELEMETRY_DISABLED=true; export N8N_DIAGNOSTICS_ENABLED=false
export NETLIFY_TELEMETRY_DISABLED=1; export NEW_RELIC_TELEMETRY_ENABLED=false
export NEXT_TELEMETRY_DISABLED=1; export NUXT_TELEMETRY_DISABLED=1
export OTEL_SDK_DISABLED=true; export PLAUSIBLE_TELEMETRY_DISABLED=true
export POSTHOG_TELEMETRY_DISABLED=true; export TELEMETRY=false
export TELEMETRY_DISABLED=true; export TELEMETRY_ENABLED=false
export TELEMETRY_OPTOUT=true; export VSCODE_TELEMETRY_OPTOUT=1


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

# --- GitHub API token (read-only) ---
# Stored in macOS Keychain as "github-api-readonly" (fine-grained, read-only:
# issues / PRs / actions / checks / commit-statuses; NO source/contents). It is
# NOT exported globally - it is read on demand and exposed as $GH_TOKEN only
# inside __claude_launch() (Claude sessions), so it never sits in every shell.
# To (re)store the token without leaking it to shell history:
#   read -rs GH_PAT && security add-generic-password -U -a "$USER" -s github-api-readonly -w "$GH_PAT" && unset GH_PAT

# --- NVD API key (rate limit only, NOT a credential) ---
# Stored in macOS Keychain as "nvd-api-key". It authorises nothing and reads
# nothing private - it only lifts NVD's anonymous limit from 5 to 50 req/30s,
# which is what makes toolchain-cve-check's 231-formula Homebrew sweep finish in
# ~2min instead of ~20min. Free and instantly regenerable, so a leak is a
# non-event: https://nvd.nist.gov/developers/request-an-api-key
# Exposed as $NVD_API_KEY inside __claude_launch(); toolchain-cve-check also reads
# the Keychain entry directly, so manual runs are authenticated too.
# To (re)store it without leaking it to shell history:
#   read -rs NVDK && security add-generic-password -U -a "$USER" -s nvd-api-key -w "$NVDK" && unset NVDK


# --- EARLY private overrides (settings the STARTUP GUARDS read) ---
# ~/.zshrc.private is sourced at the very END of this file, and that is deliberate: its
# whole contract is "private beats shared", which only holds when it is read last. But
# several guards below are evaluated DURING startup and have already made their decision
# by then, so a switch set in the late file cannot reach them. That is not a theoretical
# gap -- two comments in this file used to tell you to set exactly such a switch in
# ~/.zshrc.private, where it silently did nothing:
#
#   _ONBOARDING_COMPLETE       read in section 4  (~30 lines below)
#   NVM_ALLOW_CUSTOM_MIRROR    read in section 7
#   UV_EXCLUDE_NEWER           read in section 6  (UV_NO_COOLDOWN is now call-time, see there)
#   DOTFILES_ALLOW_NPM              read near the end of the python/node hijacks
#   DOTFILES_ALLOW_SYSTEM_PYTHON    (install.sh's takeover gate writes these on decline;
#                                    see docs/TOOLCHAIN_TAKEOVER_CONSENT.md)
#
# So: anything a startup guard reads goes in ~/.zshrc.private.early; everything else stays
# in ~/.zshrc.private. Keep this file's guards documented in the list above when adding one.
# Optional -- absent on a fresh machine, and that is fine.
[ -f ~/.zshrc.private.early ] && source ~/.zshrc.private.early


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
    # Prepend Homebrew AHEAD of the system paths (/usr/bin etc., which macOS
    # path_helper seeds first via /etc/zprofile) so brew's newer git/openssl/jq
    # win over Apple's copies. ~/.local/bin + ~/.docker/bin (Section 1) stay in
    # front; typeset -U (above) de-dups, keeping the first occurrence.
    path=(
        "$HOME/.local/bin"
        "$HOME/.docker/bin"
        "$HOMEBREW_PREFIX/bin"
        "$HOMEBREW_PREFIX/sbin"
        # Add any opt-in paths for tools that Homebrew doesn't symlink automatically
        "$HOMEBREW_PREFIX/opt/libpq/bin"
        $path
    )
fi

# Prepend common user paths (Cross-Platform)
path+=(
    "$HOME/.docker/bin"    # For Docker tools
    "$HOME/.local/bin"     # This will be de-duplicated by `typeset -U`
	"$BUN_INSTALL/bin"     # For Bun
)
# Only add the Go path if the 'go' command actually exists.
if command -v go &>/dev/null; then
    path+=("$(go env GOPATH)/bin")
fi

# Prepend macOS-specific paths
if [[ "$IS_MAC" == "true" ]]; then
	export PNPM_HOME="$HOME/Library/pnpm"
    path+=(
		"$PNPM_HOME/bin" # pnpm 11 global bin
		"$HOME/.lmstudio/bin" # LM Studio CLI (lms)
    )
fi

# Prepend Linux/WSL-specific paths
if [[ "$IS_LINUX" == "true" || "$IS_WSL" == "true" ]]; then
	export PNPM_HOME="$HOME/.local/share/pnpm"
    path+=(
		"$PNPM_HOME/bin" # pnpm 11 global bin
    )
fi

# Second, independent source for pnpm's minimumReleaseAge/trustPolicy, on top
# of home/.config/pnpm/config.yaml. pnpm 11.18.0 hardened self-update to read
# these ONLY from the built-in default, global config, a PNPM_CONFIG_* env
# var, or a CLI flag (a project can no longer weaken them) -- but if
# config.yaml or its platform path bridge is ever unreachable, self-update
# would otherwise silently fall back to pnpm's own built-in defaults: 1 day
# cooldown instead of 3, and trust-checking OFF instead of on. These two vars
# close that gap. Verified against pnpm's Rust config source (env_overlay.rs)
# 2026-08-19: read as PNPM_CONFIG_MINIMUM_RELEASE_AGE / PNPM_CONFIG_TRUST_POLICY,
# same casing/values as config.yaml. Note: these apply to EVERY pnpm command,
# not just self-update, and outrank a project's own pnpm-workspace.yaml --
# intentional given this repo's posture, but worth knowing.
export PNPM_CONFIG_MINIMUM_RELEASE_AGE="4320"
export PNPM_CONFIG_TRUST_POLICY="no-downgrade"


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
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
[ -s "$PNPM_HOME/_pnpm" ] && source "$PNPM_HOME/_pnpm"

# --- uv supply-chain release-age cooldown (parity with pnpm + bun) ---
# The cutoff lives in ~/.config/uv/uv.toml as `exclude-newer`, and UV READS THAT FILE ITSELF.
# Nothing here exports it. That is the entire point: a shell can only configure a shell, and
# this is a supply-chain gate that has to hold everywhere. Same intent as pnpm's
# minimumReleaseAge (config.yaml) and bun's (.bunfig.toml). Only bites when uv RESOLVES
# (uv add / pip install / tool install / a stale lock); installing a current lock is unaffected.
#
# HOW IT GOT HERE, so nobody "simplifies" it backwards:
#  1. Rolling now-3d, exported at startup. uv STAMPS the cutoff into uv.lock, so the value
#     differed in every shell and every `uv run` rewrote the lock -- git dirty everywhere,
#     pre-commit hooks tripping, and a COMMITTED lock whose cutoff depended on which shell
#     wrote it. Found via a sibling project, where it blocked commits outright.
#  2. Truncated to midnight UTC (2026-08-03). Cut the churn from per-shell to per-DAY. Better,
#     not fixed: every repo with a committed lock went dirty again at each UTC midnight.
#  3. Stored in a file, still exported at startup (2026-08-10, morning). Ended the churn --
#     but the export only ever happened in an INTERACTIVE shell, so cron, CI, git hooks and
#     agent tool-shells resolved with NO cooldown at all. Measured: `zsh -c`, `zsh -lc` and
#     `env -i` all reported UV_EXCLUDE_NEWER unset. A login shell was not enough either.
#  4. This. uv's own user config, which uv reads in every context.
#
# VERIFIED on uv 0.12.1 with an isolated XDG_CONFIG_HOME (2026-08-10): a cutoff of 2021-01-01
# in uv.toml resolved idna 2.10 instead of 3.18, so it CONSTRAINS resolution rather than
# merely being recorded. Independently measured by the sibling project on the same version.
#
# ROLLING AND A COMMITTED LOCKFILE CANNOT BOTH BE HAD -- any mechanism that recomputes the
# date rewrites every committed lock, and from here it would reach CI too. So the date is
# FIXED and moves only via `uv-cooldown-bump`. The window is therefore "3 days OR OLDER",
# which is the safe direction (it only ever excludes MORE), but it rots if ignored -- hence
# the staleness warning below, which is load-bearing. Threshold: UV_COOLDOWN_STALE_DAYS.
#
# PRECEDENCE, measured on uv 0.12.1 (2026-08-10, both files present, env unset):
#   `--exclude-newer` CLI  >  UV_EXCLUDE_NEWER env  >  a project's pyproject.toml [tool.uv]
#   >  THIS user uv.toml
# The last link is a strict ORDERING, not a tie -- an earlier version of this comment wrote
# the two config files as equals, which would have made a project pin look optional. It is
# not: a project pin genuinely beats the machine cutoff, and that is intended. It is how a
# repo with a committed lock pins its own date and stays reproducible in CI regardless of
# whose machine ran the resolve. Verified: pyproject 2023-06-01 resolved idna 3.4 while this
# file said 2021-01-01; removing the project pin resolved 2.10.
#
# ESCAPE HATCH: UV_NO_COOLDOWN=1, honoured by the uv()/uvx() wrappers below. Note that its
# MECHANISM changed with this move -- see the comment there before touching it.
: ${UV_COOLDOWN_FILE:="$HOME/.config/uv/uv.toml"}
: ${UV_COOLDOWN_STALE_DAYS:=30}

# NOTHING IS EXPORTED HERE, and that is the fix. uv reads uv.toml itself, so the control
# holds under cron, CI, git hooks and agent tool-shells -- none of which load this file. This
# block only ADVISES a human, so it is interactive-only and the gate does not depend on it
# running at all.
#
# ONE SOURCE, DELIBERATELY. Do not also export UV_EXCLUDE_NEWER "for good measure": env
# OUTRANKS uv.toml, so a second mechanism lets an interactive shell and a cron job resolve
# against different dates. That brings the churn back as a context-dependent flip, which is
# harder to diagnose than the daily drift this replaced.
if [[ -t 2 ]] && command -v uv >/dev/null 2>&1; then
    _uv_cutoff=$(sed -n 's/^[[:space:]]*exclude-newer[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$UV_COOLDOWN_FILE" 2>/dev/null | head -n 1)
    if [[ -z "$_uv_cutoff" ]]; then
        print -ru2 -- "⚠️  uv cooldown: no exclude-newer in ${UV_COOLDOWN_FILE} -- uv is resolving with NO release-age gate, in EVERY context. Fix: uv-cooldown-bump"
    else
        # ISO-8601 sorts lexically, so this needs no epoch maths and no BSD-vs-GNU date PARSING.
        _uv_stale=$(date -u -v-${UV_COOLDOWN_STALE_DAYS}d +%Y-%m-%dT00:00:00Z 2>/dev/null \
                 || date -u -d "${UV_COOLDOWN_STALE_DAYS} days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null)
        [[ -n "$_uv_stale" && "$_uv_cutoff" < "$_uv_stale" ]] && print -ru2 -- \
            "⚠️  uv cooldown cutoff ${_uv_cutoff} is older than ${UV_COOLDOWN_STALE_DAYS} days -- 'uv add' resolves against a stale index. Bump it: uv-cooldown-bump"
        unset _uv_stale
    fi
    unset _uv_cutoff
fi

# Move the stored cutoff forward to (today - 3 days) at midnight UTC, and rewrite the file
# with its header intact. Deliberately NOT automatic: advancing a supply-chain gate is a
# decision, and making it a decision is what stops the lockfile churn this replaced.
uv-cooldown-bump() {
    local target new tmp
    target="${UV_COOLDOWN_FILE:-$HOME/.config/uv/uv.toml}"
    new=$(date -u -v-3d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT00:00:00Z 2>/dev/null)
    [[ -n "$new" ]] || { print -ru2 -- "uv-cooldown-bump: could not compute a date"; return 1 }
    # Writing THROUGH a stow symlink normally means you are polluting tracked source by
    # accident. Here it is the intent -- the cutoff is a committed fact -- so say so loudly
    # rather than let it look like the usual mistake.
    [[ -L "$target" ]] && print -ru2 -- "note: ${target} is a stow symlink -- this edits tracked dotfiles source (intended; commit it)."
    mkdir -p "${target:h}" || return 1
    # Edit exclude-newer IN PLACE. This is uv's real config file now, so any OTHER uv setting
    # in it has to survive a bump -- rewriting the whole file would silently eat them.
    if [[ -f "$target" ]] && grep -q '^[[:space:]]*exclude-newer[[:space:]]*=' "$target" 2>/dev/null; then
        tmp="${target}.bump.$$"
        if sed "s|^[[:space:]]*exclude-newer[[:space:]]*=.*|exclude-newer = \"${new}\"|" "$target" > "$tmp"; then
            cat "$tmp" > "$target"; command rm -f "$tmp"
        else
            command rm -f "$tmp"; return 1
        fi
    else
        [[ -f "$target" ]] || cat > "$target" <<'HDR'
# uv user configuration. uv reads this file ITSELF, in every context -- no shell, no direnv,
# no prompt hook -- which is why the supply-chain cooldown lives here rather than in an
# environment variable exported by ~/.zshrc. See .zshrc section 6 for the full rationale.
HDR
        printf 'exclude-newer = "%s"\n' "$new" >> "$target"
    fi
    print -r -- "uv cooldown cutoff -> ${new}"
    print -r -- "Next: commit the change, then 'uv lock' in any repo with a committed uv.lock."
}

# --- uv / uvx: the UV_NO_COOLDOWN opt-out ---
# THE MECHANISM CHANGED when the cutoff moved into uv.toml, and the old one would have failed
# SILENTLY. `env -u UV_EXCLUDE_NEWER` worked while the cutoff WAS that variable; against a
# config file it unsets something that is no longer set, and the cutoff still applies -- a
# bypass that reports success, which is precisely the bug this whole line of work started
# with. Measured: with the cutoff in uv.toml, `env -u` resolved idna 2.10, identical to
# baseline. Decorative.
#
# A far-future date is the surgical replacement: env OUTRANKS user config, and a cutoff in
# 2999 excludes nothing. `--no-config` also works but discards ALL uv configuration rather
# than just the cutoff. The far-future date additionally leaves an honest trace in any lock
# it touches, so an accidental bypass shows up in a diff instead of vanishing.
uv() {
    if [[ -n "$UV_NO_COOLDOWN" ]]; then
        UV_EXCLUDE_NEWER=2999-01-01T00:00:00Z command uv "$@"
    else
        command uv "$@"
    fi
}

uvx() {
    if [[ -n "$UV_NO_COOLDOWN" ]]; then
        UV_EXCLUDE_NEWER=2999-01-01T00:00:00Z command uvx "$@"
    else
        command uvx "$@"
    fi
}


# ==============================================================================
# 7. NVM (Node Version Manager)
# ==============================================================================
# --- NVM Setup ---
# Official, unified loading script for script-based installations.
# This snippet is based on the official NVM README for robustness and XDG compliance.
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"

# --- NVM mirror hardening (CVE-2026-10796) ---
# A malicious Node mirror can inject shell commands via crafted version strings
# (GHSA-3c52-35h2-gfmm, fixed in nvm 0.40.5). Pin the official HTTPS mirrors so a
# stray or planted NVM_NODEJS_ORG_MIRROR can't redirect downloads. To use a custom
# mirror (e.g. a corporate proxy), set NVM_ALLOW_CUSTOM_MIRROR=1 in
# ~/.zshrc.private.EARLY (section 3) -- NOT ~/.zshrc.private, which is sourced ~900 lines
# below this `if` and so could never have switched it off. That instruction stood here
# wrong for months: a documented escape hatch on a SECURITY control that silently did
# nothing, which is worse than having no escape hatch at all.
if [[ -z "$NVM_ALLOW_CUSTOM_MIRROR" ]]; then
    export NVM_NODEJS_ORG_MIRROR="https://nodejs.org/dist"
    export NVM_IOJS_ORG_MIRROR="https://iojs.org/dist"
fi

# If NVM is installed, load it but don't activate Node yet.
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use

# --- nvm x extendedglob compatibility shim ---
# nvm 0.40.6's LTS-alias resolution (part of the CVE-2026-15921 fix) misbehaves
# under `setopt extendedglob` (set globally in this .zshrc): `nvm version lts/*`
# returns N/A, so `default -> lts/*` can't resolve and the startup `nvm use
# default` below silently no-ops, leaving Homebrew/system node active. Wrap nvm so
# its body always runs with extendedglob disabled (function-local via
# LOCAL_OPTIONS) without changing the global option. nvm 0.40.5 tolerated
# extendedglob; 0.40.6 does not. See docs/NVM_SECURITY.md.
if typeset -f nvm >/dev/null 2>&1 && ! typeset -f nvm_orig >/dev/null 2>&1; then
    functions[nvm_orig]=$functions[nvm]
    nvm() { setopt localoptions noextendedglob; nvm_orig "$@"; }
fi

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

# --- Keep an inherited active venv at the FRONT of PATH ---
# macOS path_helper (run by /etc/zprofile on every login shell) rebuilds PATH
# with /etc/paths + /etc/paths.d dirs first, sinking an already-active venv's
# bin to the bottom. A fresh shell is fine -- direnv prepends .venv/bin -- but a
# NESTED login shell (e.g. a tmux pane that inherited $VIRTUAL_ENV) makes direnv
# skip re-activation, so /usr/bin/python3 would shadow the venv's python3.
# Re-assert the venv at the front. No-op in fresh shells ($VIRTUAL_ENV is empty
# until direnv loads). typeset -U path (Section 5) keeps the result de-duplicated.
if [[ -n "$VIRTUAL_ENV" && -d "$VIRTUAL_ENV/bin" ]]; then
    path=("$VIRTUAL_ENV/bin" ${path:#"$VIRTUAL_ENV/bin"})
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
            # `return 1`, same reasoning as the python()/npx() wrappers: a refusal that
            # reports SUCCESS is the dangerous direction. `pip install x && deploy` used to
            # print this advice, install nothing, and then deploy.
            return 1
            ;;
        uninstall)
            echo "${warn}⚠️  pip uninstall is not used on this system. Use uv remove instead.${done}"
            echo
            echo "  Instead of:  ${err}pip uninstall ${@:2}${done}"
            echo "  Run:         ${ok}uv remove ${@:2}${done}"
            return 1
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
    # Every branch above only prints advice, so return non-zero for ALL of them -- otherwise
    # `pipx install x && deploy` reports success and deploys. Same rule as pip()/python().
    return 1
}

# Hijack npx/npm/yarn — none are used on this system.
# pnpm and bun are the package managers; npx is replaced by pnpm dlx / bunx.
npx() {
    echo "${warn}⚠️  npx is not used on this system. Use pnpm dlx or bunx instead.${done}"
    echo
    echo "  Instead of:  ${err}npx $@${done}"
    echo "  Run:         ${ok}pnpm dlx $@${done}"
    echo "         or:   ${ok}bunx $@${done}"
    return 1
}

npm() {
    echo "${warn}⚠️  npm is not used on this system. Use pnpm or bun instead.${done}"
    echo
    echo "  Instead of:  ${err}npm $@${done}"
    echo "  Run:         ${ok}pnpm $@${done}"
    echo "         or:   ${ok}bun $@${done}"
    return 1
}

yarn() {
    echo "${warn}⚠️  yarn is not used on this system. Use pnpm or bun instead.${done}"
    echo
    echo "  Instead of:  ${err}yarn $@${done}"
    echo "  Run:         ${ok}pnpm $@${done}"
    echo "         or:   ${ok}bun $@${done}"
    return 1
}

# Guard pnpm link --global — shims land at $PNPM_HOME root (v10 layout),
# not $PNPM_HOME/bin/ (v11 layout). Linked binaries are invisible on PATH.
pnpm() {
    if [[ "$1" == "link" || "$1" == "ln" ]]; then
        local arg
        for arg in "${@:2}"; do
            case "$arg" in
                -g|--global)
                    echo "${err}BLOCKED: pnpm link --global${done}"
                    echo
                    echo "  ${warn}pnpm link --global drops shims at \$PNPM_HOME/ root (v10 layout),${done}"
                    echo "  ${warn}not \$PNPM_HOME/bin/ (v11). Linked binaries won't be found.${done}"
                    echo
                    echo "  Instead of:  ${err}pnpm link --global${done}"
                    echo "  Run:         ${ok}pnpm install -g .${done}"
                    return 1
                    ;;
                --)
                    break
                    ;;
            esac
        done
    fi
    command pnpm "$@"
}

# Guard against hand-starting the herdr server where a service manages it.
#
# A hand-started `herdr server` inherits this shell's environment -- including
# the exported once-only banner flags from section 4 and 10, so every pane it
# spawns skips the welcome banner -- and dies with the SSH session. On Linux
# the server is a systemd --user unit (home/.config/systemd/user/herdr.service,
# enabled by install.sh); on macOS it is a brew-services LaunchAgent. Both are
# detected by the file they leave behind, so a box with no service is unaffected.
#
# Two vectors, both covered:
#   1. `herdr server` with NO subcommand. Blocked; the service command is printed.
#      `herdr server stop|reload-config|...` pass straight through.
#   2. Bare `herdr` (attach). Upstream: "starts or attaches to the remote Herdr
#      server" -- when the service is down, attaching quietly spawns the very
#      hand-started server this guard exists to prevent. So on Linux the unit is
#      started first. Skipped inside a herdr pane (HERDR_ENV=1: the server is
#      by definition running) so agents' frequent CLI calls pay nothing.
#
# A shell function only guards interactive use and Claude's Bash tool (which
# sources the snapshotted functions). Scripts calling the binary by path are
# not covered; none in this estate start a server. Measured 2026-09-06.
herdr() {
    local _unit="$HOME/.config/systemd/user/herdr.service"
    local _plist="$HOME/Library/LaunchAgents/homebrew.mxcl.herdr.plist"
    if [[ "$1" == "server" && -z "$2" ]]; then
        if [[ -L "$_unit" ]] && command -v systemctl &>/dev/null; then
            echo "${err}BLOCKED: herdr server${done}"
            echo
            echo "  herdr is managed by systemd --user on this box. A hand-started server"
            echo "  ${warn}inherits this shell's environment and dies with this session.${done}"
            echo
            echo "  Use:   systemctl --user start herdr.service"
            echo "  State: systemctl --user status herdr.service"
            return 1
        elif [[ -f "$_plist" ]]; then
            echo "${err}BLOCKED: herdr server${done}"
            echo
            echo "  herdr is managed by launchd (brew services) on this Mac. A second server"
            echo "  ${warn}exits 1 on the socket and keep_alive respawns it forever.${done}"
            echo
            echo "  Use:   brew services start herdr"
            echo "  State: brew services info herdr"
            return 1
        fi
    fi
    if [[ -z "${HERDR_ENV:-}" && "$1" != "server" && -L "$_unit" ]] && command -v systemctl &>/dev/null; then
        if [[ "$(systemctl --user is-active herdr.service 2>/dev/null)" != "active" ]]; then
            # stderr: stdout may be a pipe (`herdr status server --json | jq`).
            echo "${warn}herdr.service is not running; starting it so attach does not spawn a hand-started server${done}" >&2
            systemctl --user start herdr.service || echo "${err}systemctl --user start herdr.service failed -- see journalctl --user -u herdr.service${done}" >&2
        fi
    fi
    # herdr ships its own updater. `herdr update` downloads and installs a
    # release directly, and `herdr channel set preview` repoints it at preview
    # builds. Either one walks straight around Homebrew, `brew pin`, and the
    # whole HERDR_COOLDOWN_DAYS gate -- the release-cooldown posture in
    # docs/SECURITY.md is that nothing ships into this estate on the day it is
    # published, and a self-updater is exactly the hole that posture exists to
    # close. install.sh already bumps herdr on its own once the cooldown has
    # genuinely elapsed (_preflight_herdr_bump_check), so there is nothing the
    # blocked commands would give you that waiting does not.
    if [[ "$1" == "update" ]] || [[ "$1" == "channel" && "$2" == "set" && "$3" == "preview" ]]; then
        echo "${err}BLOCKED: herdr $1${2:+ $2}${3:+ $3}${done}"
        echo
        echo "  This bypasses Homebrew, the pin and the ${warn}${HERDR_COOLDOWN_DAYS:-5}-day release cooldown${done}."
        echo
        echo "  Check state:  herdr-cooldown-check"
        echo "  Upgrade:      ./install.sh   (bumps automatically once the cooldown has elapsed)"
        echo "  By hand:      brew unpin herdr && brew upgrade herdr && brew pin herdr"
        return 1
    fi
    command herdr "$@"
}

# Guard gh auth subcommands that re-add HTTPS credential helpers.
# Blocks: login (unless --git-protocol ssh), setup-git, refresh.
# Allows: status, token, switch, logout, login --git-protocol ssh, and all
# non-auth gh commands.
gh() {
    if [[ "$1" == "auth" ]]; then
        case "$2" in
            login)
                # The ONE verified-safe form: --git-protocol ssh never adds
                # an HTTPS credential helper. Confirmed by reading gh's own
                # source (cli/cli pkg/cmd/auth/shared/login_flow.go): the
                # credential-helper prompt is gated behind
                # `opts.Interactive && gitProtocol == "https"`, so this
                # branch of gh auth login never runs it. Every other form
                # (bare, or --git-protocol https) stays blocked.
                if [[ "$*" == *"--git-protocol ssh"* || "$*" == *"--git-protocol=ssh"* ]]; then
                    command gh "$@"
                else
                    echo "${err}BLOCKED: gh auth login${done}"
                    echo
                    echo "  This system uses SSH-only authentication for GitHub."
                    echo "  ${warn}gh auth login re-adds HTTPS credential helpers to ~/.gitconfig${done}"
                    echo "  which bypasses the SSH lockdown -- UNLESS you pass --git-protocol ssh"
                    echo "  (verified safe: never touches git's credential config)."
                    echo
                    echo "  Try instead: gh auth login --git-protocol ssh"
                    return 1
                fi
                ;;
            setup-git)
                echo "${err}BLOCKED: gh auth setup-git${done}"
                echo
                echo "  This system uses SSH-only authentication for GitHub."
                echo "  ${warn}gh auth setup-git re-adds HTTPS credential helpers to ~/.gitconfig${done}"
                echo "  which bypasses the SSH lockdown."
                return 1
                ;;
            refresh)
                echo "${err}BLOCKED: gh auth refresh${done}"
                echo
                echo "  This system uses SSH-only authentication for GitHub."
                echo "  ${warn}gh auth refresh can update HTTPS tokens${done}"
                echo "  which bypasses the SSH lockdown."
                return 1
                ;;
            *)
                # Allow: status, token, switch, logout, etc.
                command gh "$@"
                ;;
        esac
    else
        # gh doesn't consult git's own credential.helper (that's a git-only
        # mechanism), so a repo flipped onto the shared/dedicated GitHub App
        # system (github-agent-flip rewrites 'origin' to this exact URL
        # shape) needs its own hook here too. Mint a fresh, repo-scoped,
        # 1-hour token and use it for just this one call -- never exported
        # into the shell's real environment.
        if [[ "$(git remote get-url origin 2>/dev/null)" == https://x-access-token@github.com/* ]]; then
            local _gh_token
            if ! _gh_token="$(github-agent-token token)"; then
                echo "${err}github-agent-token failed, see above${done}" >&2
                return 1
            fi
            GH_TOKEN="$_gh_token" command gh "$@"
        else
            command gh "$@"
        fi
    fi
}

# brew wrapper: warn before an install pulls in a runtime managed elsewhere.
# Homebrew packages some npm/PyPI CLIs with node/python as a dependency, silently
# landing a second, unmanaged runtime (node -> nvm, python -> uv). Homebrew offers
# no way to install a formula while skipping such a dep, so this guard is advisory:
# on `brew install`, it lists the managed runtimes a formula would NEWLY install
# (skipping any already present) and asks to confirm. Casks are exempt. Bypass by
# answering y, or `HOMEBREW_ALLOW_MANAGED_RUNTIME=1 brew install ...`. Only guards
# interactive `brew install`; every other brew subcommand passes straight through.
brew() {
    if [[ "$1" == "install" && -z "$HOMEBREW_ALLOW_MANAGED_RUNTIME" ]] \
       && [[ -o interactive ]] && [[ " $* " != *" --cask "* ]]; then
        local -a formulae=() hits=()
        local arg
        for arg in "${@:2}"; do
            [[ "$arg" == -* ]] || formulae+=("$arg")
        done
        if (( ${#formulae} )); then
            local -a managed=('node' 'python@*' 'deno' 'bun')
            local deps installed d m
            deps=$(command brew deps --union "${formulae[@]}" 2>/dev/null)
            installed=$(command brew list --formula 2>/dev/null)
            for d in ${(f)deps}; do
                for m in $managed; do
                    if [[ "$d" == ${~m} ]] && ! print -r -- "$installed" | grep -qx -- "$d"; then
                        hits+=("$d")
                    fi
                done
            done
        fi
        if (( ${#hits} )) && __cannot_prompt; then
            # Nobody can answer the confirm below: take the safe default, install nothing.
            print -ru2 -- "brew: nothing installed: '${formulae[*]}' would newly install ${(uj:, :)hits}, and no one can answer the confirm prompt here (agent or no terminal). Set HOMEBREW_ALLOW_MANAGED_RUNTIME=1 to proceed."
            return 1
        fi
        if (( ${#hits} )); then
            print -ru2 -- ""
            print -ru2 -- "WARNING: 'brew install ${formulae[*]}' would newly install a runtime you manage elsewhere:"
            local h
            for h in ${(u)hits}; do print -ru2 -- "        - $h"; done
            print -ru2 -- "    node -> nvm, python -> uv. Prefer 'pnpm dlx' or a pnpm|bun global (JS), 'uv tool' (Python)."
            print -ru2 -- "    Proceed anyway: answer y below, or  HOMEBREW_ALLOW_MANAGED_RUNTIME=1 brew install ..."
            local reply
            read "reply?    Proceed with this brew install? [y/N] "
            [[ "$reply" == [Yy] ]] || { print -ru2 -- "    Aborted -- nothing installed."; return 1; }
        fi
    fi
    command brew "$@"
}

alias chawan="cha"
alias web="cha"
alias www="cha"
alias lzd='lazydocker'
alias lzg='lazygit'
alias lg='lazygit'

# markdownlint-cli + repomix run on-demand via `pnpm dlx`, NOT Homebrew: brew
# packages these npm CLIs with their own node as a dependency, which lands an
# unwanted second node runtime on the machine. dlx keeps the pnpm supply-chain
# gate (minimumReleaseAge) fully intact -- `pnpm add -g` cannot, because npm's
# abbreviated metadata omits the publish "time" and the gate fails closed
# (ERR_PNPM_MISSING_TIME). Versions are pinned for reproducibility; bump them
# deliberately (dlx otherwise floats to the newest release past the 3-day gate).
alias markdownlint='pnpm dlx markdownlint-cli@0.49.1'
alias repomix='pnpm dlx repomix@1.16.1'

# ── Claude Code ──────────────────────────────────────────────────────
# Use system ripgrep for Claude Code search (faster than bundled ripgrep).
export USE_BUILTIN_RIPGREP=0

# __claude_launch, the shared launch function, lives in ~/.zsh_claude_launch since F3
# (2026-09-21) so the `pj` SCRIPT in ~/.local/bin can source the same definition. One
# copy: edit it there, never paste it back here. The `c` family below still calls it.
[[ -f ~/.zsh_claude_launch ]] && source ~/.zsh_claude_launch

# LifeOS "Layer 2": the constitutional system prompt (output format, verification
# gate, security protocol, ~/.claude privacy rule). Layer 1 -- global CLAUDE.md,
# hooks, skills, memory -- loads in EVERY session regardless; this flag is the
# only thing that adds the constitution, and only `lifeos` passed it before.
# Array, not a scalar: zsh does NOT word-split an unquoted parameter, so
# `claude $_LIFEOS_SP` would pass flag+path as ONE argv entry and fail.
# Deliberately NOT applied to `ci` (piped -p: the banner format would pollute
# script stdout) or `claude-clean` (unconstituted by design).
_LIFEOS_SP=(--append-system-prompt-file "$HOME/.claude/LIFEOS/LIFEOS_SYSTEM_PROMPT.md")

# `c` IS A SIGNPOST NOW, NOT A LAUNCHER (F5c, ruled by Gavin 2026-09-22).
#
# It used to be the standard launch, and it is the habit that predates the pj framework:
# typing it in a project got a session with no start card, no open items, no rulings and
# no wrap-up -- the whole framework silently absent, which looks exactly like a framework
# that has nothing to say. A launcher reached for out of habit cannot be fixed by writing
# something down somewhere else.
#
# Measured before changing it: `alias c=` has exactly ONE definition on this machine, this
# line, and it lives in THIS repo rather than in a LifeOS-owned file. Nothing can call it
# programmatically either -- an alias is not visible to a script, a hook or a cron job --
# so the only caller was a human at a prompt. `c-legacy` kept the original launch, unchanged,
# from 2026-09-22 until P10 the same day, when Gavin ruled it out: nothing had needed it
# (it was never the LifeOS launch; that is `lifeos`), and the `_LIFEOS_SP` prompt still
# reaches `cb`, `cr`, `ct`, `cpr`, `cd_` and `cskip` below.
#
# A FUNCTION, not an alias, because it has to EXIT 1: a signpost that exits 0 is
# indistinguishable from a launcher that started something and printed nothing. The text
# and every arm of its behaviour live in ~/.local/bin/pj-launcher-menu (stowed from this
# repo), which has a --selftest; an alias could not be tested at all, since a
# non-interactive shell never sees one. Same reasoning that made `pj` a script in F3.
c() { pj-launcher-menu; }
alias ct='__claude_launch CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude "${_LIFEOS_SP[@]}" --dangerously-skip-permissions --permission-mode plan --teammate-mode tmux'  # Tmux agent teams

# pj - light project launcher (TRIAL, added 2026-09-19; a SCRIPT since F3, 2026-09-21).
# Claude Code + OPERATIONAL_RULES + the project's own CLAUDE.md and notes. No LifeOS prompt,
# no global CLAUDE.md. Settings live in ~/.claude/settings.project.json.
# herdr, AgentRelay, ISA and pj-voice are loaded as single-skill plugins.
#
# THERE IS NO `alias pj` HERE ON PURPOSE. `pj` is ~/.local/bin/pj, stowed from this repo
# (home/.local/bin/pj). It sources ~/.zsh_claude_launch and hands __claude_launch the same
# argv the alias used to build. Why it stopped being an alias: an alias is read ONCE when
# the shell starts and shadows any PATH command of the same name, so every shell opened
# before the alias changed kept launching the OLD form for as long as it lived. Herdr
# keeps panes alive for days; four of the last seven pj sessions ran without
# pj-global/RULES.md that way (P5.7, P6a reports; W-20260921-13). A script is read from
# disk at every launch and cannot go stale. Adding an alias back here would shadow the
# script and reintroduce the fault; pj-health's `launcher` row FAILs on one.
# `pj --dry-run` prints the exact claude argv; `pj --selftest` proves it.
#
# HOOKS: --setting-sources project,local means ~/.claude/settings.json is never
# read, so none of its 14 SessionStart hooks register here. That was silent until
# 2026-09-19, when ci-watch -- the escalating CI-red alarm -- was found never to
# run under the launcher used most, and a silent alarm looks exactly like a happy
# one. ci-watch is now registered into settings.project.json as well, via the
# `targets` field in settings/claude/hooks.json. So pj DOES have one global hook,
# on purpose; it is not a leak. Add another by naming "project" in that manifest,
# never by hand-editing settings.project.json. pj-launch-check (F3) is registered the
# same way: it reads the running claude's argv at SessionStart and shouts one LAUNCH
# WARNING line when the prompt file or a plugin dir is missing, and logs every launch
# to ~/.local/state/pj/launches.log.
# PLUGINS: ~/.claude/pj is the pj plugin (stowed from this repo, home/.claude/pj):
# /pj:wrap-up, the end-of-session pass (D-20260920-03). A project's own /wrap-up
# keeps the plain name; the pj: prefix always reaches this one (verified 2026-09-20).
# It ships as a SKILL (skills/wrap-up/SKILL.md), not a command: the plugin command
# loader ignores stow's file symlinks, the skill loader follows them (measured 2026-09-21).
# SYSTEM PROMPT: two files must land there, OPERATIONAL_RULES.md (LifeOS) and
# ~/.claude/pj-global/RULES.md (machine-wide pj rules, D-20260920-07). Claude Code keeps
# only the LAST --append-system-prompt-file and refuses to mix it with the text flag
# (both measured 2026-09-21), so `pj-prompt-file` (home/.local/bin) glues them into
# ~/.cache/dotfiles/pj-system-prompt.md at every launch and the script passes that path.
# The script carries paths only; the content stays in lifeos-private and dot-claude.
# Remove home/.local/bin/pj and this block to end the trial.

# Clean-room Claude for measuring front-loaded context (CLAUDE.md, memory,
# skills, MCP) one piece at a time. Measured 2026-09-06 (Claude Code 2.1.263):
#   --bare            : the official minimal mode, but it never reads OAuth or
#                       the keychain -> "Not logged in" on a Max account.
#   CLAUDE_CONFIG_DIR : a fresh config dir is logged out for the same reason.
#   THIS              : login intact. An EMPTY cwd means no project CLAUDE.md
#                       and no auto-memory (both keyed by folder); empty
#                       --setting-sources drops user/project/local settings,
#                       and with them hooks, loadAtStartup files and even the
#                       global ~/.claude/CLAUDE.md; --strict-mcp-config with no
#                       --mcp-config means zero MCP servers. A fresh session
#                       launched this way reported: no PAI, no CLAUDE.md from
#                       any path, no memory, 0 MCP tools.
# Not routed through __claude_launch on purpose: that injects $GH_TOKEN and
# $NVD_API_KEY, which is exactly the kind of ambient context this exists to
# exclude. No permission flags either -- default mode prompts before acting,
# which is the safe default for an untrusted-by-design scratch folder; add
# --dangerously-skip-permissions yourself when a test needs to act.
#
# Usage: claude-clean [extra claude flags...]
#   claude-clean --append-system-prompt-file ~/draft-CLAUDE.md
#   claude-clean --disable-slash-commands      # also drop the built-in skills
# Inside: /context shows the token breakdown per source -- the measuring stick.
# Each run gets its own empty folder under ~/.cache/claude-clean/; drop a
# CLAUDE.md in there and relaunch WITHOUT --setting-sources '' to test a
# project CLAUDE.md the way a real project injects it. Folders are yours to
# delete; nothing else references them.
claude-clean() {
    local dir="$HOME/.cache/claude-clean/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir" || return 1
    echo "clean-room cwd: $dir" >&2
    ( builtin cd "$dir" && command claude --setting-sources '' --strict-mcp-config "$@" )
}
alias cb='__claude_launch claude "${_LIFEOS_SP[@]}"'                                          # Bare (full control)
alias cr='__claude_launch claude "${_LIFEOS_SP[@]}" --dangerously-skip-permissions --resume'  # Resume last session
alias ci='__claude_launch claude --dangerously-skip-permissions -p'                          # Non-interactive / piped (NO Layer 2: banner would pollute stdout)
alias cpr='__claude_launch claude "${_LIFEOS_SP[@]}" --dangerously-skip-permissions --from-pr'  # Resume session from PR
alias cd_='__claude_launch claude "${_LIFEOS_SP[@]}" --dangerously-skip-permissions --permission-mode plan --verbose --debug "api,hooks,mcp,statsig"'               # Debug (verbose logging)
alias cskip='__claude_launch SKIP_SESSION_END_HOOK=1 claude "${_LIFEOS_SP[@]}" --dangerously-skip-permissions --permission-mode plan'  # Skip end hooks

# claude() IS THE HERDR PANE GUARD (W-20260924-A59, ruled by Gavin 2026-09-24, D-20260924-A05).
#
# Outside herdr (HERDR_ENV unset) it is `command claude "$@"` and nothing else: there was no
# claude function or alias before it (census 0, `whence -wa claude` said "command").
#
# Inside a herdr pane it refuses to start a Claude session that carries no system-prompt file,
# i.e. one with none of pj's (or LifeOS's) rules. WHY A SHELL FUNCTION: herdr TYPES
# `claude <args>` into the pane's interactive zsh for `agent start --kind claude`, `pane run`,
# `send-text` and `send-keys` letter by letter, and every `c` alias ends in `claude` too
# (measured with a decoy function, redteam-3 H1). A Bash PreToolUse hook sees none of the
# indirect routes; the shell that finally runs the word sees them all.
#
# PASSES: HERDR_ENV unset; any argv holding --append-system-prompt-file or --system-prompt-file
# (pj, cb, cr, ct, cpr, cd_, cskip); --help/-h/--version/-v anywhere; a first word that is a
# `claude --help` subcommand (the selftest diffs this list against the real CLI); and
# PJ_WORKERS_CONTROL=<item id> in the environment, the one named override, which is logged with
# the pane id to hooks-security.log and REFUSED when that log cannot be written.
# REFUSES: everything else, `claude -p` included (a headless session is still a session
# without the rules, it counts against the per-project cap, and `pj -p` exists), and so `ci`.
# Gavin typing a bare `claude` in a herdr pane is refused too (ruled): the guard cannot tell his
# typing from herdr's, and the refusal names the escape.
#
# ESCAPES, by design: `command claude` (the human's, and pj-worker --cleanroom's route, as in
# claude-clean above); `sudo claude` (already `command claude`); a path such as
# ~/.local/bin/claude. Scripts never see this function: pj and lifeos run claude from PATH.
# It DOES reach an agent's Bash tool, through Claude Code's shell snapshot, where HERDR_ENV is
# set in every herdr-hosted session. Blind to: panes whose shell started before this landed,
# a non-zsh pane shell, and a machine without these dotfiles. Proof: zsh-claude-paneguard-selftest.
claude() {
    [[ "${HERDR_ENV-}" == 1 ]] || { command claude "$@"; return; }
    local __cpg_a MATCH MBEGIN MEND   # =~ below sets MATCH; keep it out of the caller's shell
    local -a match mbegin mend
    for __cpg_a in "$@"; do
        case "$__cpg_a" in
            --append-system-prompt-file|--append-system-prompt-file=*|--system-prompt-file|--system-prompt-file=*|-h|--help|-v|--version)
                command claude "$@"; return ;;
        esac
    done
    case "${1-}" in
        agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|project|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade)
            command claude "$@"; return ;;
    esac
    local __cpg_log="${CONV_HOOK_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log}"
    local __cpg_argv="${${(j: :)${(q)@}}//$'\n'/ }" __cpg_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ -n "${PJ_WORKERS_CONTROL-}" ]]; then
        if [[ "$PJ_WORKERS_CONTROL" =~ '^W-[0-9]{8}-[A-Za-z0-9]+$' ]] \
            && { mkdir -p "${__cpg_log:h}" && print -r -- "[$__cpg_ts] OVERRIDE claude-paneguard \"PJ_WORKERS_CONTROL=$PJ_WORKERS_CONTROL pane=${HERDR_PANE_ID-unknown}\" \"claude $__cpg_argv\"" >> "$__cpg_log"; } 2>/dev/null; then
            print -ru2 -- "claude: herdr pane guard OVERRIDDEN by PJ_WORKERS_CONTROL=$PJ_WORKERS_CONTROL (logged to $__cpg_log)"
            command claude "$@"; return
        fi
        print -ru2 -- "claude: REFUSED in a herdr pane: PJ_WORKERS_CONTROL must be an item id like W-20260924-A59 and must log to $__cpg_log; one failed. Workers: pj-worker start. To run it anyway: command claude $__cpg_argv"
        return 1
    fi
    { mkdir -p "${__cpg_log:h}" && print -r -- "[$__cpg_ts] BLOCKED claude-paneguard \"no system-prompt file pane=${HERDR_PANE_ID-unknown}\" \"claude $__cpg_argv\"" >> "$__cpg_log"; } 2>/dev/null
    print -ru2 -- "claude: REFUSED in a herdr pane: this session would carry no pj rules. Workers: pj-worker start. Yourself: pj. To run it anyway: command claude $__cpg_argv"
    return 1
}

# Intercepting the use of a command like 'sudo claude update' :P
# pnpm branch: pnpm keeps global packages/config in the invoking user's home
# dir, not root's -- sudo would silently operate on root's home instead
# (pnpm 11.21+ already warns about this itself; a future major version
# refuses it outright). Re-runs through the pnpm() wrapper above (not
# `command pnpm`) so its own guards (e.g. link --global) still apply.
sudo() {
	if [[ "$1" == "claude" ]]; then
		echo "⚠️  Don't use sudo with claude commands!"
		echo "Running: claude ${@:2}"
		command claude "${@:2}"
	elif [[ "$1" == "pnpm" ]]; then
		echo "${err}⚠️  Don't run pnpm with sudo.${done}"
		echo "  ${warn}pnpm keeps global packages/config in YOUR home dir --${done}"
		echo "  ${warn}sudo would silently operate on root's home instead.${done}"
		echo "Running: pnpm ${@:2}"
		pnpm "${@:2}"
	else
		# --- sudo rm / sudo rmdir: route to YOUR Trash, not root's ---------------
		# `sudo rm -rf x` is the one deletion the rm() wrapper above can never see:
		# sudo execs the real /bin/rm, so the shell function is not in the picture.
		#
		# WHY WE RE-RUN IT AS THE INVOKING USER rather than `sudo safe-rm`:
		# moving a file needs write permission on its PARENT DIRECTORY, not on the
		# file itself, so an unprivileged trash usually succeeds even on root-owned
		# targets -- and it lands in ~/.Trash, where Finder's "Put Back" works.
		# `sudo safe-rm` would instead trash into /var/root/.Trash, which is mode
		# 0750 root:wheel and invisible to you. That looks safe and recovers badly,
		# which is the worst of both.
		#
		# THE COMMAND IS FOUND BY SCANNING PAST SUDO'S OWN OPTIONS, not by reading
		# "$1". A naive `[[ "$1" == rm ]]` is defeated by `sudo -u root rm -rf x`
		# -- the same bug class the `pnpm link --global` guard above had to fix.
		#
		# DELIBERATELY NOT CAUGHT (these are the "I really mean it" doors):
		#   sudo /bin/rm ...        absolute path, documented escape hatch
		#   sudo sh -c 'rm -rf x'   the rm is inside a string; no wrapper can see it
		# See docs/DELETION_SAFETY.md.
		local -a _sudo_rest=()
		local _sudo_cmd="" _sudo_skip=0 _sudo_seen=0 _sudo_arg _sudo_c _sudo_tail
		for _sudo_arg in "$@"; do
			if (( _sudo_seen )); then _sudo_rest+=("$_sudo_arg"); continue; fi
			if (( _sudo_skip )); then _sudo_skip=0; continue; fi
			case "$_sudo_arg" in
				# Long options that consume the NEXT argument. The --opt=value form
				# carries its own value, so it falls to the catch-all below instead.
				--chdir|--close-from|--group|--host|--prompt|--chroot|--role|--type|--command-timeout|--other-user|--user)
					_sudo_skip=1 ;;
				-[!-]*)
					# A short-flag CLUSTER. getopt lets you write `-nu root`, so whether
					# a value follows depends on where the value-taking letter sits, not
					# on the first letter. Walk the cluster: the first value-taking
					# letter swallows the REST of the cluster if there is any (`-uroot`),
					# otherwise it swallows the NEXT argument (`-nu root`).
					#
					# Getting this wrong is not cosmetic. Measured 2026-09-04, before the
					# fix: `sudo -nu root rm -rf /x` read `root` as the command and handed
					# the whole line to real sudo -- a guard that reports protection and
					# provides none, which is the exact failure this repo keeps hitting.
					_sudo_tail="${_sudo_arg#-}"
					while [[ -n "$_sudo_tail" ]]; do
						_sudo_c="${_sudo_tail[1]}"
						_sudo_tail="${_sudo_tail[2,-1]}"
						case "$_sudo_c" in
							C|D|g|h|p|R|r|t|T|U|u)
								[[ -z "$_sudo_tail" ]] && _sudo_skip=1
								_sudo_tail="" ;;
						esac
					done
					;;
				--|-*) ;;          # end-of-options marker, or a long flag with no value
				*=*) ;;            # VAR=value assignment, not the command
				*) _sudo_cmd="$_sudo_arg"; _sudo_seen=1 ;;
			esac
		done

		if [[ "$_sudo_cmd" == "rm" || "$_sudo_cmd" == "rmdir" ]]; then
			echo "${warn}⚠️  sudo ${_sudo_cmd} intercepted — a root delete is permanent.${done}"
			echo "  ${info}Retrying as you, so anything removed lands in YOUR Trash.${done}"
			echo
			if (( ${#_sudo_rest} == 0 )); then
				echo "${err}  No targets given — nothing done.${done}" >&2
				return 1
			fi
			if ! command -v safe-rm &>/dev/null; then
				echo "${err}❌  safe-rm not found on PATH — refusing to delete.${done}" >&2
				echo "${info}   It ships in this dotfiles repo at ~/.local/bin/safe-rm; run ./install.sh.${done}" >&2
				return 1
			fi
			# safe-rm strips rm-style flags itself, so pass the tail through untouched.
			if safe-rm "${_sudo_rest[@]}"; then
				return 0
			fi
			echo
			echo "  ${warn}That target needs real root privileges.${done}"
			echo "  ${info}Deliberate override (PERMANENT — there is no Trash for this):${done}"
			echo "    ${err}sudo /bin/${_sudo_cmd} ${_sudo_rest[*]}${done}"
			return 1
		fi

		command sudo "$@"
	fi
}

# Intercept rm: warn on symlinks (first layer), then send to trash (second layer).
# Symlink warning prevents accidentally nuking files through directory symlinks
# (e.g. rm ~/.config/direnv/file when ~/.config/direnv is a symlink into the repo).
# Routes to OS-native trash (recoverable): macOS 'trash' → ~/.Trash; Linux 'trash-put' → XDG trash.
# 'command trash' (not bare 'trash') bypasses shell functions — prevents infinite recursion.
# This function covers INTERACTIVE use only. Scripts are covered separately, by the PATH shim
# at ~/.local/bin/rm -- a zsh function outranks PATH, so the two never collide: you get this
# one (which prints what it trashed), a script gets the shim (quiet). Only `/bin/rm` and
# `SAFE_RM_OFF=1` still delete permanently. See docs/DELETION_SAFETY.md.
rm() {
	local symlinks=()
	for arg in "$@"; do
		[[ "$arg" != -* && -L "$arg" ]] && symlinks+=("$arg")
	done
	if (( ${#symlinks[@]} > 0 )) && __cannot_prompt; then
		# Nobody can answer the confirm below: take the safe default, delete nothing.
		print -ru2 -- "${funcstack[1]}: nothing deleted: ${symlinks[*]} is a symlink and no one can answer the confirm prompt here (agent or no terminal). To trash it anyway: 'command rm <path>' (the Trash-routed PATH shim, no prompt)."
		return 1
	fi
	if (( ${#symlinks[@]} > 0 )); then
		echo "${warn}⚠️  Symlink target(s) detected:${done}"
		for s in "${symlinks[@]}"; do
			echo "    $s → $(readlink "$s")"
		done
		echo "${info}   Deleting will remove the link (or follow into target dir with trailing slash).${done}"
		read "REPLY?${warn}   Proceed? [y/N] ${done}"
		[[ "$REPLY" =~ ^[Yy]$ ]] || return 1
	fi
	# Delegate to safe-rm: ONE owner for "how do we move something to the Trash", shared with
	# every script in this repo. A shell function only exists in an interactive zsh, so
	# install.sh and the hooks could never have used this one -- see safe-rm's header.
	# It strips rm-style flags itself, so pass "$@" through untouched.
	if ! command -v safe-rm &>/dev/null; then
		echo "${err}❌  safe-rm not found on PATH — refusing to delete.${done}" >&2
		echo "${info}   It ships in this dotfiles repo at ~/.local/bin/safe-rm; run ./install.sh.${done}" >&2
		return 1
	fi
	safe-rm "$@"
}

# rmdir sends empty directories to trash. Mirrors rm()'s symlink warning so that
# rmdir on a stow-symlinked dir (e.g. ~/.config/zed) prompts before nuking the link.
rmdir() {
	local symlinks=()
	for arg in "$@"; do
		[[ "$arg" != -* && -L "$arg" ]] && symlinks+=("$arg")
	done
	if (( ${#symlinks[@]} > 0 )) && __cannot_prompt; then
		# Nobody can answer the confirm below: take the safe default, delete nothing.
		print -ru2 -- "${funcstack[1]}: nothing deleted: ${symlinks[*]} is a symlink and no one can answer the confirm prompt here (agent or no terminal). To trash it anyway: 'command rm <path>' (the Trash-routed PATH shim, no prompt)."
		return 1
	fi
	if (( ${#symlinks[@]} > 0 )); then
		echo "${warn}⚠️  Symlink target(s) detected:${done}"
		for s in "${symlinks[@]}"; do
			echo "    $s → $(readlink "$s")"
		done
		read "REPLY?${warn}   Proceed? [y/N] ${done}"
		[[ "$REPLY" =~ ^[Yy]$ ]] || return 1
	fi
	if ! command -v safe-rm &>/dev/null; then
		echo "${err}❌  safe-rm not found on PATH — refusing to delete.${done}" >&2
		echo "${info}   It ships in this dotfiles repo at ~/.local/bin/safe-rm; run ./install.sh.${done}" >&2
		return 1
	fi
	safe-rm "$@"
}

# __cannot_prompt: true when nobody can answer a y/n prompt in this shell. That is an
# agent running it (CLAUDECODE or AI_AGENT set and non-empty), or stdin that is not a
# terminal: a pipe, a `| while read` loop, /dev/null, or the silent socket Claude Code's
# Bash tool hands every command containing a heredoc or any `<`, where a read blocks
# forever (measured 2026-09-24, W-20260924-A32). Every prompting wrapper in this file
# asks this before it reads. CLAUDECODE is also set in IDE integrated terminals, so a
# human typing there gets the no-prompt behaviour too (known, accepted in stage 1).
# Double underscore on purpose: Claude Code's shell snapshot drops _single helpers
# (docs/ZSH_HELPER_NAMESPACE.md).
__cannot_prompt() {
    [[ -n "${CLAUDECODE-}" || -n "${AI_AGENT-}" ]] && return 0
    [[ ! -t 0 ]]
}

# Prompt before overwriting files by default; cp() and mv() both come here.
# -f means overwrite with no prompt, as always, but only when it is an OPTION: the
# scan stops at `--` or the first operand, so `cp -- -file dst` or a file named -foo
# is not -f. Short clusters count (-rf, -pf), and so does --force; other long options
# never do (GNU --dereference, --reflink). An i next to the f (-if, -i -f) cancels it,
# because macOS cp lets -i win in either order.
# At a terminal with nobody else driving: `-i`, exactly as before.
# Otherwise (__cannot_prompt): never prompt, never overwrite, never hang. The tool
# still runs with -i but reads /dev/null, so each overwrite is declined at once, a
# caller's stdin (a while-read loop) is never consumed, every declined file gets one
# stderr line naming it, and the call returns non-zero. A source of /dev/stdin is
# data, so it keeps stdin and an existing target is refused before the copy runs.
__cp_mv_guarded() {
    local tool=$1; shift
    local arg end=0 force=0 inter=0 fromstdin=0 err rc line t dest
    local -a ops=() declined=()
    for arg in "$@"; do
        if (( ! end )); then
            case $arg in
                --) end=1; continue ;;
                --force) force=1; continue ;;
                --interactive) inter=1; continue ;;
                --*) continue ;;
                -?*) [[ $arg == *f* ]] && force=1; [[ $arg == *i* ]] && inter=1; continue ;;
                *) end=1 ;;
            esac
        fi
        ops+=("$arg")
        [[ $arg == /dev/stdin || $arg == /dev/fd/0 || $arg == /proc/self/fd/0 ]] && fromstdin=1
    done
    if (( force && ! inter )); then
        command $tool "$@"
        return
    fi
    if ! __cannot_prompt; then
        command $tool -i "$@" || return
        [[ $tool == mv ]] && { __mv_post_check 0 "$@"; return; }
        return 0
    fi
    if (( fromstdin )); then
        dest=${ops[-1]}
        for arg in "${(@)ops[1,-2]}"; do
            if [[ -d "$dest" ]]; then t="$dest/${arg:t}"; else t="$dest"; fi
            [[ -e "$t" || -L "$t" ]] && declined+=("$t")
        done
        if (( ! ${#declined} )); then
            command $tool "$@"
            return
        fi
        rc=1
    else
        { err=$(command $tool -i "$@" 2>&1 1>&3 3>&- </dev/null) } 3>&1
        rc=$?
        for line in "${(@f)err}"; do
            case $line in
                'overwrite '*'? (y/n [n]) not overwritten')      # macOS BSD
                    t=${line#overwrite }; declined+=("${t%'? (y/n [n]) not overwritten'}") ;;
                "$tool: overwrite "*)                             # GNU (unverified)
                    t=${line#"$tool: overwrite "}; t=${t% }; declined+=("${t%\?}") ;;
                '') ;;
                *) print -ru2 -- "$line" ;;
            esac
        done
    fi
    for t in "${declined[@]}"; do
        print -ru2 -- "$tool: $t NOT overwritten: no one can answer an overwrite prompt here (agent or no terminal). Use $tool -f to overwrite."
    done
    if [[ $tool == mv ]] && (( ! fromstdin && rc == 0 )); then
        __mv_post_check $(( ${#declined} > 0 )) "$@" || rc=1
    fi
    (( ${#declined} && rc == 0 )) && rc=1
    return $rc
}

cp() {
    __cp_mv_guarded cp "$@"
}

# mv -i EXITS 0 WHEN AN OVERWRITE IS DECLINED (measured 2026-09-23, macOS mv: it
# prints "not overwritten" and reports success, also on EOF, which is what an agent's
# Bash gives it), so `mv a b && next` went on as if the move had happened. cp -i
# already exits 1 on a decline (same measurement), so cp needs nothing. After an -i
# run, a source still where it was was declined: say so, return 1. A case-only
# rename on APFS (Foo -> foo) is judged by the exact spelling in the directory,
# because there -e finds the file under either name.
# Checked only for the plain form, options from -h -i -n -v; anything else keeps
# mv's own exit status (off a terminal the decline lines themselves also count, see
# __cp_mv_guarded). $1 = 1 keeps it quiet when those lines already named the files.
# `mv-wrapper-selftest` proves the arms.
__mv_post_check() {
    local quiet=$1; shift
    local arg
    local -a ops=()
    local end=0 dest s t declined=0
    for arg in "$@"; do
        if (( ! end )) && [[ "$arg" == -- ]]; then end=1; continue; fi
        if (( ! end )) && [[ "$arg" == -* ]]; then
            [[ "${arg//[hinv]/}" == - ]] || return 0
            continue
        fi
        ops+=("$arg")
    done
    (( ${#ops} >= 2 )) || return 0
    dest=${ops[-1]}
    local -a ents
    for s in "${(@)ops[1,-2]}"; do
        s=${s%/}
        [[ -e "$s" || -L "$s" ]] || continue
        if [[ -d "$dest" ]]; then t="$dest/${s:t}"; else t="$dest"; fi
        if [[ "$s" -ef "$t" ]]; then
            # Same file: a case-only rename on a case-insensitive disk (Foo -> foo),
            # where -e cannot tell. mv -i prompts for it too (measured). Declined
            # only when the old spelling is still an entry in its directory.
            [[ "${s:t}" == "${t:t}" ]] && continue
            ents=( "${s:h}"/*(DN:t) )
            (( ${ents[(Ie)${s:t}]} )) || continue
        fi
        (( quiet )) || print -ru2 -- "mv: $s was not moved (overwrite declined); returning 1"
        declined=1
    done
    return $declined
}

mv() {
    __cp_mv_guarded mv "$@"
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
# JavaScript Runtime (needed for YouTube's anti-scraping challenges)
# -----------------------------------------------------------------------------
# Node is already installed (via nvm, v22+) -- use it instead of the deno
# default (not installed here) or bun (works, but deprecated upstream).
--js-runtimes node

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

# --best-video: Best mp4 video + m4a audio (no metadata extras)
--alias best-video "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]"

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

# --info / --formats: List available formats only, skip download (same as -F)
--alias info "-F"
--alias formats "-F"

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

# --best-bundle: Best mp4/m4a video + all metadata
--alias best-bundle "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4] --write-subs --sub-format srt/ass/vtt --write-auto-subs --write-comments --no-write-info-json --print-to-file %(comments)#j %(upload_date)s-%(title)s-[%(id)s].comments.json --sub-langs live_chat --write-description --write-thumbnail"

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
  --best-video       Best mp4 video + m4a audio

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
  --info             List available formats only (same as -F)
  --formats          Same as --info

${fg[yellow]}BUNDLES ${fg[white]}(video/audio + all metadata)${reset_color}
  --bundle-video     1080p video + subs, comments, chat, desc, thumb
  --bundle-audio     Audio + subs, comments, chat, desc, thumb
  --bundle           Same as --bundle-video
  --bundle-high      Highest video + all metadata
  --best-bundle      Best mp4/m4a + subs, comments, chat, desc, thumb

${fg[yellow]}MODIFIERS${reset_color}
  --overwrite        Force overwrite existing files

${fg[yellow]}EXAMPLES${reset_color}
  ${fg[magenta]}yt https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}                   # 1080p + best audio (default)
  ${fg[magenta]}yt --video https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}           # 1080p/720p video
  ${fg[magenta]}yt --video --subs https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}    # video + subtitles
  ${fg[magenta]}yt --video-highest https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}   # max resolution
  ${fg[magenta]}yt --audio-only https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}      # extract audio
  ${fg[magenta]}yt --bundle https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}          # video + all metadata
  ${fg[magenta]}yt --best-bundle https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}     # best mp4/m4a + all metadata
  ${fg[magenta]}yt --thumbnail https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}       # thumbnail only
  ${fg[magenta]}yt --overwrite https://youtube.com/watch?v=dQw4w9WgXcQ${reset_color}       # re-download, overwrite

${fg[yellow]}DEFAULTS${reset_color}
  ${fg[white]}•${reset_color} Format: 1080p video + best audio (fallback: best available)
  ${fg[white]}•${reset_color} Output: ${fg[cyan]}%(upload_date)s - %(title)s [%(id)s].%(ext)s${reset_color}
  ${fg[white]}•${reset_color} Embeds: thumbnail, chapters, metadata, info.json
  ${fg[white]}•${reset_color} Restricted filenames (safe characters only)
  ${fg[white]}•${reset_color} Intermediate files auto-deleted after merge
  ${fg[white]}•${reset_color} No overwrites (use --overwrite to force)
  ${fg[white]}•${reset_color} Runs via uvx — yt-dlp is never installed, always current

${fg[yellow]}REQUIRES${reset_color}
  ${fg[white]}•${reset_color} uv (runs yt-dlp via uvx)
  ${fg[white]}•${reset_color} ffmpeg (merges video + audio)
  ${fg[white]}•${reset_color} aria2c (for faster downloads)

${fg[yellow]}CONFIG${reset_color}
  ${fg[cyan]}$config_file${reset_color}
EOF
  else
    UV_EXCLUDE_NEWER=2999-01-01T00:00:00Z command uvx --prerelease allow 'yt-dlp[default]' "$@"
  fi
}

# --- ffmpeg Re-encode Wrapper ---
# Re-encode a local video file to H.264 (default) or AV1, audio copied untouched.
conv() {
  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat << EOF
${fg[cyan]}conv${reset_color} - Re-encode video or audio with ffmpeg

${fg[yellow]}USAGE${reset_color}
  conv [OPTIONS] INPUT

${fg[yellow]}AUTO-DETECTED${reset_color}
  A file with no real video stream (plain audio, or audio with an embedded
  thumbnail) converts to MP3 automatically -- no flags needed.
  A file with a real video stream converts to H.264 by default.

${fg[yellow]}VIDEO CODEC${reset_color}
  --h264             Encode to H.264 / libx264 (default for video files)
  --av1              Encode to AV1 / libsvtav1
  --crf N            Override video quality (default: 18 for h264, 30 for av1)

${fg[yellow]}AUDIO${reset_color}
  --bitrate N        MP3 bitrate in kbps (default: matches the source's own
                      bitrate, so it never invents quality that wasn't there)

${fg[yellow]}OPTIONS${reset_color}
  -o, --output PATH  Output file path (default: INPUT-CODEC.ext, same folder)

${fg[yellow]}EXAMPLES${reset_color}
  ${fg[magenta]}conv movie.mp4${reset_color}                        # H.264, crf 18 -> movie-h264.mp4
  ${fg[magenta]}conv --av1 movie.mp4${reset_color}                  # AV1, crf 30 -> movie-av1.mp4
  ${fg[magenta]}conv --av1 --crf 24 movie.mp4${reset_color}         # AV1, crf 24
  ${fg[magenta]}conv song.opus${reset_color}                        # auto -> song-mp3.mp3, bitrate matched
  ${fg[magenta]}conv song.opus --bitrate 320${reset_color}          # force 320kbps mp3
  ${fg[magenta]}conv movie.mp4 -o clean.mp4${reset_color}           # custom output name
  ${fg[magenta]}conv movie.mp4 -o ~/Movies/clean.mp4${reset_color}  # custom output path (relative or full)

${fg[yellow]}DEFAULTS${reset_color}
  ${fg[white]}•${reset_color} Video: audio stream copied untouched (-c:a copy)
  ${fg[white]}•${reset_color} Video codec: H.264 unless --av1 is given
  ${fg[white]}•${reset_color} Video CRF: 18 (h264) / 30 (av1) unless --crf overrides it
  ${fg[white]}•${reset_color} Audio: MP3 bitrate matched to the source (clamped 32-320kbps),
    falls back to high-quality VBR if the source bitrate can't be read
  ${fg[white]}•${reset_color} A cover-art/thumbnail image embedded in an audio file does NOT
    count as video -- it's still treated as an audio conversion
  ${fg[white]}•${reset_color} Output auto-named INPUT-CODEC.ext (or INPUT-mp3.mp3) next to the input

${fg[yellow]}REQUIRES${reset_color}
  ${fg[white]}•${reset_color} ffmpeg
  ${fg[white]}•${reset_color} ffprobe (ships with ffmpeg)
EOF
    return
  fi

  if ! command -v ffmpeg &>/dev/null; then
    echo "${err}conv: ffmpeg not found on PATH.${done}"
    return 1
  fi
  if ! command -v ffprobe &>/dev/null; then
    echo "${err}conv: ffprobe not found on PATH.${done}"
    return 1
  fi

  local codec="" crf="" bitrate="" output="" input=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --h264) codec="h264"; shift ;;
      --av1)  codec="av1"; shift ;;
      --crf)  [ $# -ge 2 ] || { echo "${err}conv: --crf needs a value${done}"; return 1; }; crf="$2"; shift 2 ;;
      --bitrate) [ $# -ge 2 ] || { echo "${err}conv: --bitrate needs a value${done}"; return 1; }; bitrate="$2"; shift 2 ;;
      -o|--output) [ $# -ge 2 ] || { echo "${err}conv: $1 needs a value${done}"; return 1; }; output="$2"; shift 2 ;;
      -*)
        echo "${err}conv: unknown option '$1'${done}"
        return 1
        ;;
      *)
        if [[ -n "$input" ]]; then
          echo "${err}conv: unexpected extra argument '$1'${done}"
          return 1
        fi
        input="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$input" ]]; then
    echo "${err}conv: no input file given. Run 'conv --help' for usage.${done}"
    return 1
  fi
  if [[ ! -f "$input" ]]; then
    echo "${err}conv: input file not found: $input${done}"
    return 1
  fi

  # Detect a REAL video stream -- excludes an embedded cover-art/thumbnail
  # image, which ffprobe also reports as a "video" stream (disposition:
  # attached_pic). Without this, an audio file with a thumbnail (e.g. from
  # `yt --audio-only`) would be wrongly treated as a video file.
  local vinfo line has_video=""
  vinfo=$(ffprobe -v error -select_streams v -show_entries "stream=codec_type:stream_disposition=attached_pic" -of csv=p=0 "$input" 2>/dev/null)
  for line in ${(f)vinfo}; do
    [[ "$line" == "video,0" ]] && has_video=1
  done

  if [[ -z "$has_video" ]]; then
    if [[ "$codec" == "h264" || "$codec" == "av1" ]]; then
      echo "${err}conv: '$input' has no real video stream -- can't encode it as $codec.${done}"
      return 1
    fi

    local dir base
    dir="${input:h}"
    base="${input:t:r}"
    [[ -z "$output" ]] && output="${dir}/${base}-mp3.mp3"

    local abr
    if [[ -n "$bitrate" ]]; then
      abr="$bitrate"
    else
      # Match the source's own bitrate so this never invents quality that
      # wasn't there. Stream-level bit_rate first, falling back to the
      # container's overall bit_rate when the stream doesn't report one.
      local raw
      raw=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null)
      [[ -z "$raw" || "$raw" == "N/A" ]] && raw=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null)
      if [[ "$raw" == <-> ]]; then
        abr=$(( raw / 1000 ))
        (( abr < 32 )) && abr=32
        (( abr > 320 )) && abr=320
      fi
    fi

    if [[ -n "$abr" ]]; then
      echo "${info}Encoding${done} ${fg[cyan]}$input${reset_color} ${info}->${done} ${fg[cyan]}$output${reset_color} ${info}(mp3, ${abr}kbps, matched to source)${done}"
      ffmpeg -i "$input" -vn -c:a libmp3lame -b:a "${abr}k" "$output"
    else
      echo "${info}Encoding${done} ${fg[cyan]}$input${reset_color} ${info}->${done} ${fg[cyan]}$output${reset_color} ${info}(mp3, VBR q2 -- source bitrate unreadable)${done}"
      ffmpeg -i "$input" -vn -c:a libmp3lame -q:a 2 "$output"
    fi
    return
  fi

  [[ -z "$codec" ]] && codec="h264"
  local vcodec crf_default
  if [[ "$codec" == "av1" ]]; then
    vcodec="libsvtav1"
    crf_default=30
  else
    vcodec="libx264"
    crf_default=18
  fi
  [[ -z "$crf" ]] && crf="$crf_default"

  if [[ -z "$output" ]]; then
    local dir base ext
    dir="${input:h}"
    base="${input:t:r}"
    ext="${input:e}"
    if [[ -n "$ext" ]]; then
      output="${dir}/${base}-${codec}.${ext}"
    else
      output="${dir}/${base}-${codec}"
    fi
  fi

  echo "${info}Encoding${done} ${fg[cyan]}$input${reset_color} ${info}->${done} ${fg[cyan]}$output${reset_color} ${info}(codec: $vcodec, crf: $crf)${done}"
  ffmpeg -i "$input" -c:v "$vcodec" -crf "$crf" -c:a copy "$output"
}


# --- OS Information Aliases ---
if [[ "$IS_WSL" == "true" ]] || [[ "$IS_LINUX" == "true" ]]; then
    alias os='cat /etc/os-release'
fi

# --- Zoxide ---
# https://github.com/ajeetdsouza/zoxide
# This makes zoxide respond to cd directly while keeping the real cd available as __zoxide_cd internally. This is the "official" way to replace cd
# Suppress false-positive config warning (zoxide init is correctly placed at end of config)
export _ZO_DOCTOR=0
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
#
# All six of these `return 1`, matching npx/npm/yarn above. They used to print the
# advice and exit 0, which is the dangerous direction: a refusal that reports SUCCESS.
# `python build.py && deploy` would print a tip, do no work, and then deploy — and
# nothing anywhere would report a failure, because as far as the shell was concerned
# there wasn't one.
python() {
    echo "${warn}⚠️  python is not used directly on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}python $@${done}"
    echo "  Run:         ${ok}uv run python $@${done}"
    return 1
}

python3() {
    echo "${warn}⚠️  python3 is not used directly on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}python3 $@${done}"
    echo "  Run:         ${ok}uv run python3 $@${done}"
    return 1
}

py313() {
    echo "${warn}⚠️  py313 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py313 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.13 python $@${done}"
    return 1
}

py312() {
    echo "${warn}⚠️  py312 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py312 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.12 python $@${done}"
    return 1
}

py311() {
    echo "${warn}⚠️  py311 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py311 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.11 python $@${done}"
    return 1
}

py310() {
    echo "${warn}⚠️  py310 is not used on this system. Use uv run instead.${done}"
    echo
    echo "  Instead of:  ${err}py310 $@${done}"
    echo "  Run:         ${ok}uv run --python 3.10 python $@${done}"
    return 1
}

# --- Toolchain-takeover consent opt-out -------------------------------------
# install.sh's takeover gate (_gate_toolchain_takeover) writes these into
# ~/.zshrc.private.early (machine-local, untracked, sourced above at line 166
# -- BEFORE every hijack this unsets is even defined) when the operator
# DECLINES one of the two big changes. Read here, never set here. See
# docs/TOOLCHAIN_TAKEOVER_CONSENT.md. pnpm() (the `pnpm link --global` guard,
# defined earlier) is a correctness fix, not a takeover -- never unset it.
if [[ -n "$DOTFILES_ALLOW_NPM" ]]; then
    unset -f npm npx yarn 2>/dev/null
fi
if [[ -n "$DOTFILES_ALLOW_SYSTEM_PYTHON" ]]; then
    unset -f python python3 pip pipx py313 py312 py311 py310 2>/dev/null
fi

# --- Node.js 'pnpm dlx' / 'bunx' Aliases ---
# Use pnpm dlx (or bunx) to run commands without installing them globally.
# This avoids having to reinstall them for every Node version with nvm.
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

    # LibreOffice CLI (macOS app bundle has no symlinked binary on PATH)
    alias soffice='/Applications/LibreOffice.app/Contents/MacOS/soffice'

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
# Private / Machine-Specific Overrides
# ==============================================================================
# Source machine-specific settings, API keys, and PATH additions.
# This file is not tracked by git. Create it with: touch ~/.zshrc.private
# See README.md → "Shell Settings (~/.zshrc.private)" for examples.
[ -f ~/.zshrc.private ] && source ~/.zshrc.private


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

# LifeOS launch command — without this, LifeOS Core is installed but launches
# un-constituted (plain `claude`, no mode banner / verification / security layer).
alias lifeos='bun "$HOME/.claude/LIFEOS/TOOLS/lifeos.ts" -s "$HOME/.claude/LIFEOS/LIFEOS_SYSTEM_PROMPT.md"'
