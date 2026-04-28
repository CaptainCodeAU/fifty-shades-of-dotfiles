# Cross-Platform Zsh Development Environment

![Shell](https://img.shields.io/badge/Shell-Zsh-lightgrey.svg?logo=gnome-terminal&logoColor=white)
![Python with uv](https://img.shields.io/badge/Python-uv-hotpink.svg?logo=python&logoColor=white)
![Node.js with nvm](https://img.shields.io/badge/Node.js-nvm%20%2B%20pnpm%2Fbun-green.svg?logo=nodedotjs&logoColor=white)
![Docker](https://img.shields.io/badge/Tools-Docker-blue.svg?logo=docker&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude-Code-blueviolet.svg?logo=anthropic&logoColor=white)
![OS Support](https://img.shields.io/badge/OS-macOS%20%7C%20Linux%20%7C%20WSL-blue.svg?logo=apple)

A set of Zsh dotfiles that create a unified, automated development environment across **macOS, Linux, and Windows (via WSL)**. Built around a modern toolchain (`uv`, `pnpm`/`bun`, `direnv`, `stow`) that prioritizes speed, consistency, and developer experience.

---

## Overview and history

I created this repo because I kept losing my shell setup. Not dramatically, no hard drive failures or anything, just the slow erosion that happens when you set up a new machine, SSH into a Linux box, or spin up a WSL instance and realise you can't remember how you had things configured last time. Every time, I'd spend a day or two getting my terminal back to "normal," swearing I'd write it down this time, and then not writing it down.

The first commit was just a `.zshrc` with some Python virtual environment helpers. I'd switched to `uv` and kept forgetting the incantations for setting up a new project with direnv, so I wrapped them in a function. Then I wrapped a few more things. Then I added Node.js scaffolding because I was tired of the same twenty minutes of boilerplate every time I started a TypeScript project. You can see where this is going.

At some point it stopped being a dotfiles backup and became something closer to an operating philosophy for how I want to work. I have two GitHub accounts and a couple of machines / VMs, and I needed all of them to feel the same. Same aliases, same git identity routing, same safety rails, same muscle memory. One `./install.sh` on a fresh box and I'm home.

A lot of what's in here exists because I got burned. The `rm` wrapper exists because I deleted a symlink target once when I meant to delete the link. The `gh auth` blocker exists because GitHub's credential helper silently broke my SSH-only setup twice before I caught it. The npm/yarn interceptors exist because a stray `npm install` in a pnpm project creates a `package-lock.json` that ghosts you for hours. Every guardrail in this repo is a scar from a past mistake, turned into a rule so I never make it again. I am not a fast learner but I am a stubborn one.

The system is built around GNU Stow, which symlinks everything from one directory into your home folder. The `home/` directory mirrors `~/` exactly, so what you see in the repo is what you get on disk. The installer handles the rest: prerequisites, Oh My Zsh plugins, nvm, pnpm, bun, Nerd Fonts, tmux plugin manager, git identity. All interactive, all idempotent, all skippable if you already have your own setup for something.

If you just want the shell functions without the full install, you can symlink individual files. But the real value is in having all the pieces wired together: direnv auto-activating environments, tmux windows naming themselves after git branches, per-machine colour profiles so you know at a glance whether you're on your laptop or SSHed into something else. It's the kind of thing that sounds like overkill until you've used it for a week and can't go back.

---

## Key Features

- **💻 Cross-Platform by Design**: Works seamlessly on macOS, Linux, and WSL with OS-specific adaptations handled automatically.
- **🚀 Automatic Onboarding**: On a fresh system (macOS, Linux, or WSL), the script detects missing tools and interactively prompts to install them. Run `run_onboarding` anytime to re-check.
- **🤖 Automated Project Scaffolding**: Create complete, best-practice Python (`python_new_project`) or Node.js (`node_new_project`) projects with a single command.
- **✨ Seamless Environment Management**:
  - **`direnv`** for automatic activation/deactivation of Python virtual environments.
  - **`nvm`** with automatic Node.js version switching via `.nvmrc` files.
- **🐳 Integrated Docker Helpers**: Functions to quickly start, stop, and manage common development services like PostgreSQL, Qdrant, and Jupyter Lab.
- **🖥️ Tmux Integration**: Powerful tmux session management with git-aware workflows and automatic window naming.
- **🎨 Machine & Project Color Identity**: Automatic per-machine title bar/status bar colors via direnv (macOS ARM, Intel, WSL, Linux), plus a scaffolding script (`init-vscode-project-settings.sh`) to give each project its own visual identity. All colors come from 10 named profiles in `color-profiles.json`.
- **📝 Editor Integration**: Automatic environment syncing between Cursor/VSCode terminals and tmux sessions.
- **🎬 Media Tools**: Built-in `yt()` wrapper for yt-dlp with auto-generated configuration and quality presets.
- **🔒 Private Configuration**: A built-in pattern for managing your secret keys and machine-specific settings in a `.zshrc.private` file, which is kept out of version control.

---

## Prerequisites for Mac

1. **Homebrew**: Ensure [Homebrew](https://brew.sh/) is installed on your macOS system.
2. **Core Tools**: Install the essential technologies using Homebrew.

   ```bash
   brew install stow uv direnv jq zoxide eza fzf tmux ripgrep fd gh git-lfs safe-rm neovim glow
   ```

   > **Note:** `stow` is used by the installer to symlink dotfiles from this repo into `~/`. `jq` is required by the direnv color profile system and the project settings scaffolding script, as well as Node.js scaffolding and onboarding checks. `zoxide` replaces `cd`, `eza` powers the `l`/`ll` aliases, `fzf` provides fuzzy finding, `tmux` powers session management, `ripgrep` (`rg`) enables fast code search, `fd` is a fast `find` alternative, `gh` is the GitHub CLI (used by `.gitconfig` for credential management), `git-lfs` enables Git Large File Storage, `safe-rm` wraps `rm` to prevent accidental deletion of protected paths, `neovim` is the default `$EDITOR` (with fallback to vim/vi), and `glow` renders Markdown files beautifully in the terminal.

3. **Recommended Tools**: These are optional but enhance the experience significantly.

   ```bash
   brew install ffmpeg yt-dlp aria2 tree neofetch lazygit lazydocker yazi imagemagick
   ```

   > **Note:** `ffmpeg` and `aria2` are used by the `yt()` media download wrapper. `lazygit`/`lazydocker` power the `lg`/`lzd` aliases. `yazi` is a terminal file manager used by the `y()` function. `imagemagick` is required by the yazi zoom plugin for image resizing.

4. **Nerd Font**: Required for Powerlevel10k icons and glyphs.

   ```bash
   brew install --cask font-symbols-only-nerd-font
   ```

5. **Post-install Setup**: Run these one-time setup commands after installing the tools above.

   ```bash
   git lfs install                    # One-time git-lfs setup (configures hooks)
   ```

   > **Note:** This system uses SSH-only authentication for GitHub — do **not** run `gh auth login` as it re-adds HTTPS credential helpers. Instead, configure your SSH keys in `~/.ssh/config` and add URL rewrites in `~/.gitconfig.private`. See [Customization & Private Settings](#customization--private-settings) for details.

---

## Installation

Setting up is designed to be as simple as possible. The included `install.sh` script handles everything interactively, or you can set things up manually.

### Automated Install (Recommended)

```bash
git clone https://github.com/CaptainCodeAU/fifty-shades-of-dotfiles.git ~/fifty-shades-of-dotfiles
cd ~/fifty-shades-of-dotfiles
./install.sh
```

The installer will check prerequisites, install missing tools, set up Oh My Zsh plugins, symlink dotfiles via GNU Stow, configure git identity, install TPM/nvm/pnpm/bun/Nerd Fonts, and more. Run `./install.sh --help` for all options including `--check`, `--dry-run`, `--update`, and `--force`.

### Manual Install

1. **Prerequisites**:
   - Ensure `git` and `zsh` are installed.
   - Install **[Oh My Zsh](https://ohmy.zsh.sh/#install)**.

2. **Clone the Repository**:

   ```bash
   git clone https://github.com/CaptainCodeAU/fifty-shades-of-dotfiles.git ~/fifty-shades-of-dotfiles
   ```

3. **Symlink Configuration (optional)**: Link the configuration files to your home directory using the one-to-one mapping structure.

   ```bash
   # WARNING: This will overwrite existing files. Backup yours first!
   # Link main zsh configuration
   ln -sf ~/fifty-shades-of-dotfiles/home/.zshrc ~/.zshrc

   # Link zsh function files
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_python_functions ~/.zsh_python_functions
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_node_functions ~/.zsh_node_functions
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_docker_functions ~/.zsh_docker_functions
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_cursor_functions ~/.zsh_cursor_functions
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_tmux ~/.zsh_tmux
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_onboarding ~/.zsh_onboarding
   ln -sf ~/fifty-shades-of-dotfiles/home/.zsh_welcome ~/.zsh_welcome

   # Link git configuration
   ln -sf ~/fifty-shades-of-dotfiles/home/.gitconfig ~/.gitconfig
   ln -sf ~/fifty-shades-of-dotfiles/home/.gitignore_global ~/.gitignore_global

   # Create private git identity (not committed to the repo)
   cat > ~/.gitconfig.private << 'EOF'
   [user]
       name = Your Name
       email = you@example.com
   EOF

   # Link other configuration files
   ln -sf ~/fifty-shades-of-dotfiles/home/.tmux.conf ~/.tmux.conf
   ln -sf ~/fifty-shades-of-dotfiles/home/.p10k.zsh ~/.p10k.zsh
   ln -sf ~/fifty-shades-of-dotfiles/home/.vimrc ~/.vimrc

   # Link .config directory files
   mkdir -p ~/.config/direnv ~/.config/zshrc ~/.config/yt-dlp
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/direnv/direnvrc ~/.config/direnv/direnvrc
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/direnv/direnv.toml ~/.config/direnv/direnv.toml
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/zshrc/color-profiles.json ~/.config/zshrc/color-profiles.json
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/zshrc/init-vscode-project-settings.sh ~/.config/zshrc/init-vscode-project-settings.sh
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/yt-dlp/config ~/.config/yt-dlp/config
   ln -sf ~/fifty-shades-of-dotfiles/home/.config/yazi ~/.config/yazi

   # Link platform-specific files (macOS only)
   # mkdir -p ~/Library/Application\ Support/Cursor/User
   # mkdir -p ~/Library/Application\ Support/Code/User
   # ln -sf ~/fifty-shades-of-dotfiles/platforms/macos/Library/Application\ Support/Cursor/User/settings.json ~/Library/Application\ Support/Cursor/User/settings.json
   # ln -sf ~/fifty-shades-of-dotfiles/platforms/macos/Library/Application\ Support/Code/User/settings.json ~/Library/Application\ Support/Code/User/settings.json
   ```

   > **Note**: The repository uses a one-to-one mapping structure where `home/` mirrors `~/` and `platforms/` contains platform-specific files. See [`docs/STRUCTURE.md`](docs/STRUCTURE.md) for details.

4. **Node.js Ecosystem**: Install nvm, pnpm, and TPM for tmux plugins.

   ```bash
   # nvm (Node Version Manager)
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

   # pnpm (standalone install — used instead of Corepack)
   curl -fsSL https://get.pnpm.io/install.sh | sh -

   # bun (JavaScript runtime & toolkit)
   # Pre-set BUN_INSTALL and PATH so the installer skips modifying .zshrc
   export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH" && curl -fsSL https://bun.sh/install | bash

   # TPM (Tmux Plugin Manager) — required for tmux plugins in .tmux.conf
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
   # After starting tmux, press prefix + I to install plugins
   ```

5. **Enable `direnv`**: The provided `.zshrc` already contains the hook for `direnv`. If you are merging with an existing file, ensure this line is present:

   ```zsh
   # In your .zshrc
   if command -v direnv &> /dev/null; then eval "$(direnv hook zsh)"; fi
   ```

6. **Restart Your Shell**: Open a new terminal window or run `source ~/.zshrc`.
   - **On any new system**, the onboarding script will run automatically and guide you through installing any missing dependencies.
   - A welcome message will confirm the setup is active.

---

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

| OS            | Package Manager                     |
| ------------- | ----------------------------------- |
| macOS         | Homebrew (auto-installs if missing) |
| Ubuntu/Debian | apt                                 |
| Fedora        | dnf                                 |
| Arch          | pacman                              |
| openSUSE      | zypper                              |

### Tools Checked

| Category                 | Tools                                                  |
| ------------------------ | ------------------------------------------------------ |
| **Essential**            | git, curl, unzip, stow, safe-rm                        |
| **User Experience**      | eza, fzf, jq, direnv, zoxide, fd, yazi, glow           |
| **CLI Tools**            | ripgrep, neovim, tree, neofetch, ffmpeg, yt-dlp, aria2 |
| **Git**                  | gh, git-lfs                                            |
| **Development Managers** | nvm, uv, pnpm, bun                                     |
| **Special**              | Docker (guidance only — requires manual installation)  |

### Skipping Onboarding

To prevent auto-onboarding on a fresh shell:

```bash
export _ONBOARDING_COMPLETE=true
```

---

## Usage: Your Day-to-Day Python Workflow

### 1. Creating a New Python Project

This is the primary entry point. The function scaffolds everything you need.

```bash
# 1. Create and enter a directory for your new project
mkdir my-awesome-app && cd my-awesome-app

# 2. Run the new project command with the desired Python version
python_new_project 3.12
```

This single command performs over a dozen steps, including `git init`, `uv venv`, `uv pip install`, and creating all necessary config files.

### 2. Setting Up an Existing Project

If you clone a project or need to reset your environment, use `python_setup`. This function intelligently installs default `dev` dependencies and any other optional extras you specify.

```bash
# 1. Clone a repo and enter it
git clone <url> && cd <project-name>

# 2. Set up the environment using a specific Python version
# This will install base + 'dev' dependencies.
python_setup 3.12

# 3. Set up the environment and include additional optional dependencies
# This will install base + 'dev' + 'api' + 'web' dependencies.
python_setup 3.12 api web
```

### 3. Managing a Global Command-Line Tool

If your `pyproject.toml` defines a script, you can install it as a system-wide command using `uv tool`. The install uses **editable mode** by default, so code changes are reflected immediately without reinstalling. These helpers require an active virtual environment to determine which Python version to use.

```bash
# Inside your project directory (with .venv active via direnv):

# Install the tool for the first time with 'cli' extras (editable mode)
uv_tool_install_current_project cli

# Install with NO extras
uv_tool_install_current_project --no-extras

# Reinstall (only needed when pyproject.toml entry points change)
uv_tool_reinstall_current_project cli

# Check the installation status of the current project's tool
uv_tool_check_current_project

# Uninstall the tool
uv_tool_uninstall_current_project

# Run a tool once without installing (via uvx)
uvx ruff check .
```

### 4. Cleaning Up a Project

To completely remove all generated artifacts and return the directory to a clean state, use `python_delete`. This is non-destructive to your source code.

```bash
# This will remove .venv, .envrc, caches, build artifacts, and uv.lock
python_delete
```

---

## Python Workflow at a Glance

This environment supercharges Python development using `uv` and `direnv`.

### 1. New Project Scaffolding (`python_new_project`)

```mermaid
graph TD
    subgraph "🚀 Initial Setup"
        A["💻 User runs:<br><b>mkdir my-app && cd my-app</b>"] --> B
        B["💻 User runs:<br><b>python_new_project 3.12</b>"]
    end

    subgraph "🤖 Automated Scaffolding"
        B --> C{"⚙️ `uv init`, `git init`"}
        C --> D["📄 pyproject.toml<br>📄 .gitignore<br>📄 README.md"]
        C --> E["📁 src/my_app/__init__.py<br>📁 tests/test_main.py"]
        C --> F["🐍 `uv venv`<br>Creates .venv"]
        F --> G["📦 `uv pip install -e .[dev]`<br>Installs dependencies"]
        C --> H["🗝️ `direnv`<br>Creates .envrc for auto-activation"]
    end

    subgraph "✅ Result"
        I["✨ A complete, ready-to-develop<br>Python project with one command."]
    end

    D & E & G & H --> I

    classDef userAction fill:#3498db,stroke:#2980b9,stroke-width:2px,color:white;
    classDef automation fill:#f1c40f,stroke:#f39c12,stroke-width:2px,color:black;
    classDef artifact fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:white;
    classDef result fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:white;

    class A,B userAction;
    class C,F,G,H automation;
    class D,E artifact;
    class I result;
```

### 2. Existing Project Setup (`python_setup`)

```mermaid
graph TD
    subgraph "🚀 Initial State"
        A["📁 Existing Project<br>(e.g., after `git clone`)"]
    end

    subgraph "🤖 Automated Setup"
        A --> B["💻 User runs:<br><b>python_setup 3.12 api</b>"]
        B --> C["🗑️ Removes existing `.venv` folder"]
        C --> D["🐍 Creates new `.venv` using<br>the specified Python version (3.12)"]
        D --> E["📦 Installs dependencies from `pyproject.toml`<br>including `[dev]` and specified extras (`[api]`)"]
        E --> F["🗝️ Ensures `.envrc` exists for `direnv`"]
    end

    subgraph "✅ Result"
        G["✨ A clean, consistent, and<br>ready-to-use development environment."]
    end

    F --> G

    classDef userAction fill:#3498db,stroke:#2980b9,stroke-width:2px,color:white;
    classDef automation fill:#e67e22,stroke:#d35400,stroke-width:2px,color:white;
    classDef initialState fill:#95a5a6,stroke:#7f8c8d,stroke-width:2px,color:white;
    classDef result fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:white;

    class A initialState;
    class B userAction;
    class C,D,E,F automation;
    class G result;
```

### 3. Global CLI Deployment (`uv_tool_*`)

```mermaid
graph TD
    subgraph "🔄 Daily Development Cycle"
        A["💻 `cd my-project`"] --> B
        B["✨ `direnv` auto-activates<br>the `.venv` environment"]
        B --> C["👨‍💻 Write code, run `pytest`, `ruff format`..."]
    end

    subgraph "🌍 Global CLI Deployment (Optional)"
        C --> F["Run: `uv_tool_install_current_project cli`"]
        F --> G["✅ `my-cli` is now available globally<br>(editable — code changes apply immediately)"]
        G --> H["... make code changes ..."]
        H --> I["Run: `uv_tool_reinstall_current_project cli`<br>(only if entry points change)"]
    end
```

### 4. Daily Development & Deployment

This diagram shows the seamless daily workflow enabled by `direnv` and the `uv tool` helper functions.

```mermaid
graph TD
    subgraph "🔄 Daily Development Cycle"
        A["💻 `cd my-project`"] --> B
        B["✨ `direnv` auto-activates<br>the `.venv` environment"]
        B --> C["👨‍💻 Write code, run `pytest`, `ruff format`..."]
        C --> D["💻 `cd ..`"]
        D --> E["✨ `direnv` auto-deactivates<br>the `.venv` environment"]
    end

    subgraph "🌍 Global CLI Deployment (Optional)"
        C --> F["Run: `uv_tool_install_current_project cli`<br>to install with 'cli' extra (editable)"]
        F --> G["✅ `my-cli` is now available globally"]
        G --> H["... make code changes ..."]
        H --> I["Run: `uv_tool_reinstall_current_project cli`<br>to update (only if entry points change)"]
        I --> J["Run: `uv_tool_uninstall_current_project`<br>to remove the global command"]
    end

    classDef userAction fill:#3498db,stroke:#2980b9,stroke-width:2px,color:white;
    classDef tool fill:#e67e22,stroke:#d35400,stroke-width:2px,color:white;
    classDef devLoop fill:#1abc9c,stroke:#16a085,stroke-width:2px,color:white;
    classDef result fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:white;

    class A,D,F,H,I,J userAction;
    class B,E tool;
    class C devLoop;
    class G result;
```

---

## Node.js & Docker Workflows

### Node.js (`node_*` functions)

The setup provides similar automation for Node.js projects, standardizing on `nvm` with `pnpm` or `bun` as co-primary package managers. Projects scaffold with **TypeScript by default** (pass `--no-ts` for JavaScript) and integrate with **direnv** for automatic environment activation. When creating a new project, you choose your package manager — pnpm uses **Vitest** for testing, bun uses its **built-in test runner**.

- **Create a new TypeScript project**: `mkdir my-node-app && cd my-node-app && node_new_project`
  - Prompts for package manager (`pnpm` or `bun`), or pass `--pnpm`/`--bun` to skip the prompt. Scaffolds `src/index.ts`, `tests/index.test.ts`, `tsconfig.json`, `.nvmrc`, `.gitignore`, and a rich `.envrc` (if direnv is available). Installs TypeScript, ESLint, Prettier, and type definitions.
- **Create a JavaScript project**: `node_new_project --no-ts` (or `node_new_project --no-ts --bun`)
  - Same scaffold without TypeScript — creates `src/index.js` and `tests/index.test.js` instead.
- **Set up an existing project**: `cd existing-project && node_setup`
  - Switches to the Node version from `.nvmrc`, auto-detects the package manager from the lockfile (`bun.lockb` → bun, `pnpm-lock.yaml` → pnpm), installs dependencies, creates `.envrc` if missing, and displays available scripts.
- **Quick project dashboard**: `node_info`
  - Shows Node/pnpm/bun versions, `.nvmrc` status, package.json details, available scripts, and global link status.
- **Clean up artifacts**: `node_clean`
  - Removes `node_modules`, `dist`, `build`, `.next`, `.turbo`, `.tsbuildinfo`, coverage, caches, and lockfiles.

#### Global Node.js Package Management

For CLI tools you're developing, use `node_link` / `node_unlink` / `node_check_global` to manage global symlinks. These auto-detect whether to use `pnpm link --global` or `bun link --global` based on the project's lockfile. Note that global links are tied to the current nvm Node version — switching nvm versions will lose access to the linked binary. For one-off tool execution, use `pnpm dlx` or `bunx` — neither requires global installation. (`npx` is intercepted and will suggest both alternatives.)

### Docker (`docker_*` functions & aliases)

Quickly manage common development services and stacks.

- **Start a PostgreSQL container for development**: `pg_dev_start [db] [pw] [port]`
- **Start a Qdrant vector database**: `qdrant_start [port]`
- **Start a full AI/ML stack (Qdrant + Jupyter)**: `dev_stack_start ai`
- **Start a web development stack**: `dev_stack_start web`
- **Start a full stack (web + AI/ML)**: `dev_stack_start full`
- **Check the status of all services**: `dev_stack_status`
- **Clean up all unused Docker resources**: `dcleanup`
- **View Docker overview**: `docker_overview`
- **Get help**: `docker_help`

### Tmux Workflows

The configuration includes powerful tmux session management:

- **Quick session access**: `ta mysession` (attach or create)
- **Coding sessions**: `tc` (coding session), `tcc` (claudecode session)
- **Development sessions**: `tdev myproject` (multi-window setup)
- **Git-aware sessions**: `tgit myproject` (split panes for git and editing)
- **Git integration**: All git branch operations automatically update tmux window names

### Media Downloads

Use the `yt()` wrapper for easy video/audio downloads:

```bash
yt https://youtube.com/watch?v=...              # Default: 1080p + best audio
yt --video-highest https://youtube.com/watch?v=... # Maximum quality
yt --audio-only https://youtube.com/watch?v=...    # Extract audio
yt --bundle https://youtube.com/watch?v=...        # Video + all metadata
yt --help                                          # Show all options
```

---

## Claude Code LSP Servers

Claude Code supports LSP (Language Server Protocol) plugins for enhanced code intelligence. These servers need to be installed globally on the system so Claude Code can find them on `$PATH`.

### LSP Server Setup

```bash
# Pyright (Python) — installed via uv tool
uv tool install pyright

# TypeScript Language Server — installed via pnpm or bun global
pnpm add -g typescript-language-server typescript  # or: bun add -g typescript-language-server typescript

# Swift (sourcekit-lsp) — ships with Xcode, no install needed
# Verify with: /usr/bin/sourcekit-lsp --help
```

### Verification

```bash
pyright --version                    # Should show version (e.g., 1.1.408)
typescript-language-server --version # Should show version (e.g., 5.1.3)
which sourcekit-lsp                  # Should show /usr/bin/sourcekit-lsp
```

---

## Claude Code Configuration

This repository includes a comprehensive [Claude Code](https://code.claude.com/) setup in the `.claude/` directory.

### Installing Claude Code

Claude Code is a CLI tool from Anthropic. Install it following the [official documentation](https://docs.anthropic.com/en/docs/claude-code/overview). Once installed, the shell aliases (`c`, `cb`, `cr`, `ci`, `ct`, `cd_`, `cskip`) defined in `.zshrc` will work.

### Optional Tools for Hooks

The Claude Code hooks in this repo benefit from these optional tools:

```bash
# markdownlint — used by pre-commit gate for markdown auto-fix
brew install markdownlint-cli

# dotenvx — used by session-checks.sh to verify .env encryption
brew install dotenvx/brew/dotenvx
```

### Permissions (`.claude/settings.local.json`)

The local settings file configures fine-grained permissions using the modern `Bash(command *)` wildcard syntax:

- **`allow`**: Pre-approved commands for common shell utilities, git operations, Swift/Xcode tooling, package managers (uv, pnpm, brew, cargo, pip, pod), Docker, GitHub CLI, and more.
- **`ask`**: Prompts before running destructive operations like `git push` and `git reset`.
- **`deny`**: Blocks reading sensitive files — `.env` variants (except `.env.example`), private keys (`.pem`, `.key`, `.cert`), `~/.ssh/`, `~/.aws/`, `~/.gnupg/`, `secrets/`, `credentials/`, and password files.
- **`WebFetch`**: Allowlisted domains for documentation lookups — GitHub, Anthropic docs, Apple Developer, Swift.org, npm, PyPI, Stack Overflow, and others.

> **Note**: `.claude/settings.local.json` is gitignored by Claude Code. The version in this repo serves as a reference template.

### Hooks (`.claude/hooks/`)

Custom lifecycle hooks that run at various points during Claude Code sessions. See [`.claude/hooks/README.md`](.claude/hooks/README.md) for details.

### Using in Other Projects

To pull the `.claude` hooks folder into another project, use [gitpick](https://github.com/nrjdalal/gitpick):

```bash
pnpm dlx gitpick CaptainCodeAU/fifty-shades-of-dotfiles/tree/master/.claude  # or: bunx gitpick ...
```

Run this from the target project's root directory. It downloads just the `.claude` folder without cloning the full repository.

---

## Customization & Private Settings

To keep your main configuration portable and shareable, personal and machine-specific settings live in private files that are **never committed** to the repository. These are protected by `.gitignore_global`.

### Git Identity (`~/.gitconfig.private`)

The shared `.gitconfig` includes `~/.gitconfig.private` via `[include]`. This file is the central hub for git identity, multi-account routing, and SSH URL rewrites.

For a single account, a minimal setup is:

```ini
[user]
    name = Your Name
    email = you@example.com
```

The installer (`./install.sh`) will prompt you to create this file on a fresh machine. If the file already exists (e.g., with multi-account config), the installer skips creation to avoid overwriting it.

> **Note:** The files `.gitconfig.local`, `.gitconfig.private`, `.gitconfig.private.local`, and `~/.ssh/gitconfig-*` are all protected by `.gitignore_global` to prevent accidental commits.

#### SSH-Only Authentication

This system enforces SSH-only authentication for GitHub. The shared `.gitconfig` has no credential helpers — instead, `~/.gitconfig.private` contains **scoped** URL rewrite rules that convert HTTPS URLs to SSH only for **your own** GitHub usernames. Third-party URLs (Homebrew taps, open-source repos) stay on HTTPS and work without authentication.

```ini
# ~/.gitconfig.private — URL rewrites (scoped per username)

[url "<ssh-host-alias>:<YourGitHubUsername>/"]
    insteadOf = https://github.com/<YourGitHubUsername>/
[url "<ssh-host-alias>:"]
    insteadOf = https://gist.github.com/<YourGitHubUsername>/
```

> **Important:** Do **not** use a blanket `insteadOf = https://github.com/` rule — this rewrites all GitHub URLs (including Homebrew taps and third-party repos) to SSH, which breaks `brew update` and any unauthenticated HTTPS clone.

This is part of a defence-in-depth model:

1. **SSH config hardening** — `AddKeysToAgent no`, `UseKeychain no`, `IdentitiesOnly yes` ensure every operation requires a passphrase
2. **Scoped URL rewrites** — only your own GitHub repos are rewritten to SSH; third-party HTTPS URLs pass through untouched
3. **No credential helpers** — the shared `.gitconfig` contains no `[credential]` sections, so even if a URL rewrite is bypassed, HTTPS auth fails rather than silently succeeding
4. **Claude Code SSH isolation** — the `_claude_launch` wrapper spins up an **isolated SSH agent** scoped to the Claude Code process — the key is loaded only into this ephemeral agent and is never visible to other terminals or the system launchd agent. The agent dies when Claude Code exits; a 4-hour timeout is a safety net for abnormal termination (SIGKILL).

> **Warning:** Running `gh auth login` or `gh auth setup-git` will silently re-add HTTPS credential helpers to `~/.gitconfig`. A `gh()` shell wrapper (in `.zshrc`) blocks these commands to prevent this.

#### Multiple GitHub Accounts

If you have multiple GitHub accounts, each account gets three things:

1. **SSH host alias** in `~/.ssh/config` — maps a short name to `github.com` with the correct key
2. **Git identity file** in `~/.ssh/gitconfig-<alias>` — sets `[user]` name/email and `core.sshCommand`
3. **`includeIf` rule** in `~/.gitconfig.private` — loads the identity file based on repo directory

**SSH config** (`~/.ssh/config`):

```ini
# Global defaults — strict key handling
Host *
    AddKeysToAgent no
    UseKeychain no
    IdentitiesOnly yes

Host git-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/personal

Host git-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/work
```

**Identity files** (co-located with SSH keys in `~/.ssh/`):

```ini
# ~/.ssh/gitconfig-personal
[user]
    name = PersonalHandle
    email = personal@example.com
[core]
    sshCommand = ssh -i ~/.ssh/personal
```

```ini
# ~/.ssh/gitconfig-work
[user]
    name = Work Name
    email = you@company.com
[core]
    sshCommand = ssh -i ~/.ssh/work
```

**Private config** (`~/.gitconfig.private`):

```ini
# Default identity (fallback for repos outside includeIf dirs)
[user]
    name = PersonalHandle
    email = personal@example.com

# Per-account identity overrides (last match wins)
[includeIf "gitdir:~/CODE/"]
    path = ~/.ssh/gitconfig-personal
[includeIf "gitdir:~/WORK/"]
    path = ~/.ssh/gitconfig-work

# Scoped URL rewrites (only your repos → SSH)
[url "git-personal:PersonalHandle/"]
    insteadOf = https://github.com/PersonalHandle/
[url "git-work:WorkOrg/"]
    insteadOf = https://github.com/WorkOrg/
```

**Clone URLs** use the short SSH host aliases directly — no `git@` prefix needed since `User git` is defined in `~/.ssh/config`:

```bash
git clone git-personal:PersonalHandle/my-repo
git clone git-work:WorkOrg/my-repo
```

The trailing `/` in `gitdir:~/WORK/` is important — it matches any repo inside that directory recursively (including nested subdirectories). The `includeIf` rules use last-match-wins ordering, so more specific directory rules should come after broader catch-all rules.

#### Adding a New Account

1. Create SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/<account>`
2. Add SSH host alias: `Host git-<alias>` in `~/.ssh/config`
3. Create identity file: `~/.ssh/gitconfig-<alias>` with `[user]` and `[core] sshCommand`
4. Add `includeIf` rule in `~/.gitconfig.private`
5. Add scoped URL rewrites in `~/.gitconfig.private`
6. Add public key to the GitHub account
7. Verify: `ssh -T git-<alias>` should show "Hi &lt;username&gt;!"

### Shell Settings (`~/.zshrc.private`)

Machine-specific shell settings, API keys, and personal aliases go in `~/.zshrc.private`:

1. Create the file: `touch ~/.zshrc.private`
2. Add your private settings to it.

**Example `~/.zshrc.private`:**

```zsh
# Private and machine-specific settings for this computer.

# Secret API Keys
export OPENAI_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# PATH for a tool installed in a non-standard location on this machine
export PATH="/opt/custom-tool/bin:$PATH"

# A personal alias
alias my-server="ssh my-user@192.168.1.100"
```

---

## Additional macOS Tools

These are specialized tools that are not part of the core setup but may be useful depending on your workflow. Install them individually as needed:

```bash
# Swift / Xcode development
brew install swiftlint xcodegen

# Networking & security
brew install cloudflared mkcert

# Document & image processing
brew install poppler imagemagick mpack

# Other utilities
brew install ripmine              # Redmine CLI
brew install markdownlint-cli     # Markdown linting (also used by Claude Code hooks)
brew install dotenvx/brew/dotenvx # .env encryption (also used by Claude Code hooks)
```

> **Note:** These are macOS-specific Homebrew formulae. Equivalent packages may be available on Linux via apt/dnf/pacman but are not covered by the install script.

---

## Welcome Message & Verbosity Control

The shell displays an environment overview on startup. You can control this behavior with environment variables.

### Verbosity Levels

#### `ZSH_WELCOME` — Environment Overview

| Value     | Description                                              |
| --------- | -------------------------------------------------------- |
| `full`    | Complete multi-line overview (default for new terminals) |
| `minimal` | Single-line compact status (default for SSH/tmux)        |
| `none`    | No overview displayed                                    |
| _(empty)_ | Auto-detect based on context (recommended)               |

#### `ZSH_WELCOME_QUICKREF` — Quick Reference

| Value     | Description                      |
| --------- | -------------------------------- |
| `full`    | Multi-line categorized reference |
| `minimal` | Compact 2-line hints             |
| `none`    | No quick reference displayed     |

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

| Context          | Auto Default | Rationale                                |
| ---------------- | ------------ | ---------------------------------------- |
| Regular terminal | `full`       | First shell of the day, show full info   |
| SSH session      | `minimal`    | You're remoting in, you know your setup  |
| Tmux pane        | `minimal`    | You've seen the banner in the first pane |

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

---

## Repository Structure

This repository uses a **one-to-one mapping** structure that mirrors actual deployment locations, making it clear where each file goes:

```text
fifty-shades-of-dotfiles/
├── install.sh                         # Interactive installer (./install.sh --help)
├── home/                              # Files that go directly in ~/
│   ├── .gitconfig                     # Git config template → ~/.gitconfig
│   ├── .gitignore_global              # Global gitignore → ~/.gitignore_global
│   ├── .zshrc                         # Main zsh config → ~/.zshrc
│   ├── .zsh_python_functions          # Python helpers → ~/.zsh_python_functions
│   ├── .zsh_node_functions            # Node.js helpers → ~/.zsh_node_functions
│   ├── .zsh_docker_functions          # Docker helpers → ~/.zsh_docker_functions
│   ├── .zsh_cursor_functions          # Cursor/VSCode integration → ~/.zsh_cursor_functions
│   ├── .zsh_tmux                      # Tmux integration → ~/.zsh_tmux
│   ├── .zsh_onboarding                # Cross-platform onboarding → ~/.zsh_onboarding
│   ├── .zsh_welcome                   # Unified welcome script → ~/.zsh_welcome
│   ├── .tmux.conf                     # Tmux config → ~/.tmux.conf
│   ├── .p10k.zsh                      # Powerlevel10k config → ~/.p10k.zsh
│   ├── .vimrc                        # Vim config → ~/.vimrc
│   │
│   └── .config/                       # Files that go in ~/.config/
│       ├── safe-rm                    # safe-rm protected paths → ~/.config/safe-rm
│       ├── direnv/                    # direnv configs → ~/.config/direnv/
│       │   ├── direnv.toml
│       │   └── direnvrc              # Machine color profiles + env hooks
│       ├── zshrc/                     # Shared shell data → ~/.config/zshrc/
│       │   ├── color-profiles.json   # 10 named color profiles (single source of truth)
│       │   └── init-vscode-project-settings.sh  # Project-level .vscode/settings.json scaffold
│       ├── yazi/                      # Yazi file manager → ~/.config/yazi/
│       │   ├── yazi.toml              # Main config (layout, openers, plugins)
│       │   ├── keymap.toml            # Keybindings (vim-style + zoom)
│       │   ├── theme.toml             # Theme (catppuccin-mocha flavor)
│       │   ├── init.lua               # Init script (loads git plugin)
│       │   ├── package.toml           # Plugin/flavor dependencies
│       │   ├── plugins/               # Plugins (git status, zoom)
│       │   └── flavors/               # Flavor themes (catppuccin-mocha)
│       ├── zed/                        # Zed editor → ~/.config/zed/
│       │   └── settings.json          # Zed editor settings
│       └── yt-dlp/                    # yt-dlp config → ~/.config/yt-dlp/
│           └── config
│   │
│   └── .local/                        # User-level commands and shared script sources
│       ├── bin/                       # Command entrypoints on PATH → ~/.local/bin/
│       │   ├── dirdiff                # Wrapper command for directory diff script
│       │   ├── sysinfo                # Wrapper command for system monitor script
│       │   └── watch-history-sync     # Wrapper command for YouTube history exporter
│       └── share/
│           └── fifty-shades-of-dotfiles/
│               └── scripts/           # Standalone script sources + local scripts README
│                   ├── README.md
│                   ├── dirdiff.sh
│                   ├── sysinfo.sh
│                   └── watch-history-sync.sh
│
├── .vscode/                           # VS Code workspace settings (not stowed)
│   ├── settings.json                 # This repo's workspace colors
│   └── tasks.json                    # Tasks: init project colors, list profiles
│
├── .claude/                           # Claude Code configuration
│   ├── settings.json                  # Shared project settings (committed)
│   ├── settings.local.json            # Local permissions & deny rules (gitignored)
│   └── hooks/                         # Claude Code lifecycle hooks
│       ├── config.yaml                # Hook configuration
│       ├── hook_runner.py             # Main hook runner
│       └── lib/                       # Hook handler modules
│
├── platforms/                         # Platform-specific locations
│   └── macos/                         # macOS-specific paths
│       └── Library/Application Support/
│           ├── Cursor/User/settings.json
│           └── Code/User/settings.json
│
├── settings/                         # Exported app configs (reference/import)
│   ├── iterm2/                       # iTerm2 terminal emulator
│   │   └── profiles.json             # iTerm2 profiles (import via Profiles > Other Actions > Import)
│   └── wezterm/                      # WezTerm terminal emulator
│       └── wezterm.lua               # Full config (color scheme, keys, tabs, SSH detection)
│
└── docs/                              # Documentation
    ├── MEMENTO_vscode_machine_colors.md
    └── reference/                     # Reference materials
        ├── colors.md
        ├── mermaid_examples.md
        ├── tmux_cheatsheet.md
        └── windows/                   # Historical Windows scripts (reference only)
            ├── activate.v1.bat
            ├── activate.v2.bat
            └── run.cmd
```

### Key Files

- **`install.sh`**: Interactive installer that handles prerequisites, tool installation, symlinks, and post-setup configuration. Supports `--check`, `--dry-run`, `--update`, `--force`, and `--uninstall` modes.
- **`home/.gitconfig`**: Public-safe git configuration template. Contains LFS filters, merge/diff settings, and sensible defaults. No credential helpers (SSH-only auth). Includes `~/.gitconfig.private` via `[include]` for personal identity, multi-account routing, and scoped URL rewrites — see [Customization & Private Settings](#customization--private-settings).
- **`home/.gitignore_global`**: Global gitignore patterns for OS files, editor artifacts, environment/secret files, build outputs, and temporary files. Referenced by `.gitconfig` via `core.excludesfile`.
- **`home/.zshrc`**: The main controller. It detects the OS, loads plugins, and sources all other function files. Also contains inline functions like `yt()` (yt-dlp wrapper), `rm()` (symlink-aware safe deletion wrapper), and various aliases.
- **`home/.zsh_python_functions`**: Contains all Python-related helper functions (`python_new_project`, `uv_tool_*`, etc.).
- **`home/.zsh_node_functions`**: Contains all Node.js helper functions (`node_new_project`, etc.).
- **`home/.zsh_docker_functions`**: Contains all Docker helper functions and aliases (`pg_dev_start`, `dcleanup`, etc.).
- **`home/.zsh_cursor_functions`**: Cursor/VSCode editor integration for automatic environment syncing with tmux sessions.
- **`home/.zsh_tmux`**: Comprehensive tmux session management, git integration, and workflow functions.
- **`home/.zsh_onboarding`**: Cross-platform onboarding script that detects missing tools and offers to install them on any OS.
- **`home/.zsh_welcome`**: Unified cross-platform welcome script with verbosity controls, auto-detection for SSH/tmux, and environment overview.
- **`home/.vimrc`**: Lightweight Vim configuration with line numbers, search highlighting, tab settings, and sensible defaults.
- **`home/.config/safe-rm`**: User-level safe-rm configuration listing protected paths (one per line). Prevents accidental `rm` of critical system directories. Works alongside the `rm()` zsh wrapper for symlink-aware protection.
- **`home/.config/direnv/`**: direnv configuration files. `direnvrc` reads color profiles from `color-profiles.json` via `jq` and applies machine-specific colors to VSCode/Cursor title bars, status bars, and borders.
- **`home/.config/zshrc/color-profiles.json`**: 10 named color profiles (single source of truth). Used by both direnvrc (machine-level) and `init-vscode-project-settings.sh` (project-level).
- **`home/.config/zshrc/init-vscode-project-settings.sh`**: Scaffolds `.vscode/settings.json` with a color profile and font settings. Supports `--profile`, `--random`, and `--list` flags.
- **`home/.config/yazi/`**: Yazi terminal file manager configuration with catppuccin-mocha theme, vim-style keybindings, and plugins for git status indicators and image zoom. The zoom plugin requires ImageMagick (`brew install imagemagick`).
- **`home/.config/zed/settings.json`**: Zed editor settings. Only `settings.json` is managed; `prompts/` and `themes/` remain user-local.
- **`home/.config/yt-dlp/config`**: yt-dlp configuration template (auto-generated by `yt()` function, but included as reference).
- **`home/.local/share/fifty-shades-of-dotfiles/scripts/`**: Canonical source for standalone shell scripts that are exposed as commands via wrappers in `home/.local/bin/`. See `home/.local/share/fifty-shades-of-dotfiles/scripts/README.md` for architecture, conventions, and add-new-script workflow.
- **`settings/iterm2/profiles.json`**: Exported iTerm2 profiles for manual import (Profiles > Other Actions > Import JSON Profiles).
- **`settings/wezterm/wezterm.lua`**: Archived WezTerm configuration with custom Coolnight color scheme, SSH-aware tab styling, and comprehensive keybindings.

For detailed structure documentation, see [`docs/STRUCTURE.md`](docs/STRUCTURE.md).

---

## Cursor Editor Integration

The `.zsh_cursor_functions` file provides seamless integration between Cursor/VSCode terminals and tmux sessions. It automatically syncs environment variables (like `VSCODE_INJECTION`, `CURSOR_TRACE_ID`, etc.) from Cursor/VSCode terminals into tmux sessions.

### How It Works

- **Automatic Environment Capture**: When you're in a Cursor/VSCode terminal, the environment is automatically saved to `~/.cache/cursor_env.zsh`.
- **Tmux Integration**: The `tmux` command is wrapped to automatically load the saved environment when attaching to sessions.
- **New Pane Support**: New tmux panes automatically inherit the Cursor/VSCode environment variables.

This ensures that tools and scripts that rely on editor-specific environment variables work correctly inside tmux sessions.

---

## Tmux Functions & Git Integration

The `.zsh_tmux` file provides powerful tmux session management and git workflow functions.

### Tmux Session Management

| Function            | Arguments    | Description                                                                        |
| :------------------ | :----------- | :--------------------------------------------------------------------------------- |
| `ta <session>`      | session name | Attach to tmux session or create if doesn't exist                                  |
| `tc`                | none         | Attach to 'coding' session (create if needed)                                      |
| `tcc`               | none         | Attach to 'claudecode' session (create if needed)                                  |
| `tdev <project>`    | project name | Create multi-window development session with code, git, terminal, and logs windows |
| `tgit <project>`    | project name | Create git-aware coding session with split panes for git status and editing        |
| `tbranch <project>` | project name | Create tmux session for branch management workflows                                |
| `tpull <project>`   | project name | Create session for pull/merge workflows                                            |
| `tclean`            | none         | Clean up old coding-related tmux sessions                                          |
| `tlast`             | none         | Quick attach to most recent session                                                |
| `tls`               | none         | List sessions with detailed information                                            |

### Git Integration Functions

These functions integrate git workflows with tmux, automatically updating window names with branch information:

| Function              | Arguments      | Description                                                                   |
| :-------------------- | :------------- | :---------------------------------------------------------------------------- |
| `gstatus`             | none           | Full git repository dashboard with branch info, changes, commits, and stashes |
| `gs`                  | none           | Quick git status showing repo, branch, change count, and last commit          |
| `gtree`               | none           | Visual git tree (uses git-tree or tig if available)                           |
| `gwip2`               | none           | Show what you're working on (recently modified files)                         |
| `gt <branch>`         | branch name    | Tmux-aware git switch (updates window name)                                   |
| `gtc <branch>`        | branch name    | Tmux-aware branch creation (updates window name)                              |
| `gswitch <branch>`    | branch name    | Switch branch and update tmux window name                                     |
| `gfeature <name>`     | feature name   | Create feature branch following git flow and update tmux window               |
| `gpr_quick <message>` | commit message | Quick PR workflow: add, commit, push                                          |

### Usage Examples

**Create a development session:**

```bash
tdev myproject
# Creates a tmux session with:
# - 'code' window (opens editor)
# - 'git' window (shows git status)
# - 'term' window (for running commands)
# - 'logs' window (for monitoring)
```

**Git workflow with tmux:**

```bash
cd ~/CODE/Ideas/myproject
gt feature/new-feature  # Switches branch and updates tmux window name
# Window name becomes: "myproject:feature/new-feature"
```

**Quick git overview:**

```bash
gs        # Quick status
gstatus   # Full dashboard
```

---

## Additional Aliases & Functions

### yt-dlp Wrapper (`yt()`)

A comprehensive wrapper function for `yt-dlp` that auto-generates configuration and provides a user-friendly interface:

```bash
# Basic usage (1080p + best audio, default)
yt https://youtube.com/watch?v=dQw4w9WgXcQ

# Quality presets
yt --video https://youtube.com/watch?v=dQw4w9WgXcQ           # 1080p/720p
yt --video-highest https://youtube.com/watch?v=dQw4w9WgXcQ   # Maximum resolution
yt --audio-only https://youtube.com/watch?v=dQw4w9WgXcQ      # Extract audio

# With subtitles
yt --video --subs https://youtube.com/watch?v=dQw4w9WgXcQ

# Metadata bundles
yt --bundle https://youtube.com/watch?v=dQw4w9WgXcQ          # Video + all metadata
yt --thumbnail https://youtube.com/watch?v=dQw4w9WgXcQ       # Thumbnail only

# Help
yt --help
```

The function auto-generates a comprehensive `~/.config/yt-dlp/config` file on first use with sensible defaults (1080p video, aria2c downloader, embedded metadata, etc.).

### Other Useful Aliases

- **File Listing**: `l` and `ll` use `eza` for enhanced directory listings with git status
- **Navigation**: `..`, `...`, `....`, `.....` for quick directory navigation
- **Node.js**: `serve` (pnpm dlx http-server), `tsc` (pnpm dlx typescript) — also usable via `bunx`
- **Docker**: `lzd` (lazydocker), `lzg`/`lg` (lazygit)
- **Claude Code**: `c` (standard), `cb` (bare/full control), `cr` (resume), `ci` (non-interactive), `ct` (tmux agent teams), `cpr` (from PR), `cd_` (debug), `cskip` (skip end hooks). All aliases spin up an isolated ephemeral SSH agent scoped to the Claude Code process, so marketplace plugin refreshes and git operations work with SSH-only auth without leaking the key to other terminals.
- **Zoxide**: `cd` command is replaced with `zoxide` for intelligent directory jumping

### Standalone Script Commands

Standalone shell scripts are managed through the dotfiles stow layout and exposed as commands on PATH:

- Source scripts: `home/.local/share/fifty-shades-of-dotfiles/scripts/*.sh`
- Command entrypoints: `home/.local/bin/<command>`
- Current commands: `dirdiff`, `sysinfo`, `watch-history-sync`

For the full architecture, conventions, migration policy, and add-new-script workflow, see:

- [`home/.local/share/fifty-shades-of-dotfiles/scripts/README.md`](home/.local/share/fifty-shades-of-dotfiles/scripts/README.md)

### Special Functions

- **`rm()` wrapper**: Two-layer deletion safety net. First warns before deleting symlinks (shows link target, prompts for confirmation). Then routes through `safe-rm` when installed (blocks deletion of protected paths like `/`, `/etc`, `/usr`). Falls back to native `rm` if `safe-rm` is absent. Configured via `~/.config/safe-rm`.
- **`cp()`/`mv()` wrappers**: Default to interactive overwrite protection (`-i`) so you are prompted before clobbering existing files. Explicit force flags (`-f`, e.g. `-rf`) bypass prompts when you intentionally want non-interactive overwrite behavior.
- **`sudo()` wrapper**: Prevents accidental `sudo claude` commands and redirects appropriately
- **`pip()` wrapper**: Intercepts `pip install` → `uv add` and `pip uninstall` → `uv remove`; passes through editable installs and read-only subcommands via `uv pip`
- **`pipx()` wrapper**: Intercepts `pipx` commands and shows the equivalent `uv tool` commands
- **`npx()` wrapper**: Intercepts `npx` commands and shows the equivalent `pnpm dlx` commands
- **`python()`/`python3()` wrapper**: Intercepts direct Python calls and redirects to `uv run`
- **`py31X()` wrappers**: Intercepts version-specific Python calls (`py313`, `py312`, `py311`, `py310`) and redirects to `uv run --python`
- **`ports()` function**: OS-specific port listing (macOS: `lsof`, Linux/WSL: `ss`/`netstat`)
- **`y()` function**: Yazi file manager integration for visual directory navigation

---

## Full Function & Alias Reference

### Python Functions

| Function                            | Arguments                    | Description                                                                      |
| :---------------------------------- | :--------------------------- | :------------------------------------------------------------------------------- |
| `python_new_project`                | `<py_version>`               | Scaffolds a complete new Python project in the current directory.                |
| `python_setup`                      | `<py_version> [extra1...]`   | Resets/creates the `.venv` and installs dependencies for an existing project.    |
| `python_delete`                     | `(none)`                     | Deletes the `.venv`, `.envrc`, caches, and build artifacts.                      |
| `uv_tool_install_current_project`   | `[extra1...] \| --no-extras` | Installs the current project as a global CLI tool via `uv tool` (editable mode). |
| `uv_tool_reinstall_current_project` | `[extra1...] \| --no-extras` | Reinstalls the global CLI tool (needed when entry points change).                |
| `uv_tool_uninstall_current_project` | `(none)`                     | Uninstalls the `uv tool`-managed CLI tool for the current project.               |
| `uv_tool_check_current_project`     | `(none)`                     | Checks if the current project is installed via `uv tool`.                        |

### Node.js Functions

| Function            | Arguments         | Description                                                                          |
| :------------------ | :---------------- | :----------------------------------------------------------------------------------- |
| `node_new_project`  | `[--no-ts\|--js]` | Scaffolds a new Node.js project (TypeScript by default, `--no-ts` for JavaScript).   |
| `node_setup`        | `(none)`          | Sets up an existing project: switches Node version, installs deps, creates `.envrc`. |
| `node_clean`        | `(none)`          | Deletes `node_modules`, build artifacts, caches, and lockfiles.                      |
| `node_info`         | `(none)`          | Displays project dashboard: versions, `.nvmrc` status, scripts, global link status.  |
| `node_link`         | `(none)`          | Links current project globally via `pnpm link --global`.                             |
| `node_unlink`       | `(none)`          | Unlinks current project from global scope.                                           |
| `node_check_global` | `(none)`          | Checks if current project is linked globally (returns 0/1).                          |
| `create_node_envrc` | `(none)`          | Creates a rich `.envrc` with nvm auto-switch and project info box.                   |

### Docker Functions

#### Database Functions

| Function         | Arguments                   | Description                                |
| :--------------- | :-------------------------- | :----------------------------------------- |
| `pg_dev_start`   | `[db] [pw] [port]`          | Starts a PostgreSQL development container. |
| `pg_dev_stop`    | `(none)`                    | Stops PostgreSQL development container.    |
| `pg_dev_connect` | `[db_name]`                 | Connect to PostgreSQL container.           |
| `db_backup`      | `[container] [backup_name]` | Backup database from container.            |

#### AI/ML Functions

| Function        | Arguments           | Description                                |
| :-------------- | :------------------ | :----------------------------------------- |
| `qdrant_start`  | `[port]`            | Starts a Qdrant vector database container. |
| `qdrant_stop`   | `(none)`            | Stops Qdrant container.                    |
| `qdrant_backup` | `[backup_name]`     | Backup Qdrant data.                        |
| `jupyter_start` | `[port] [work_dir]` | Starts a Jupyter Lab container.            |
| `jupyter_stop`  | `(none)`            | Stops Jupyter Lab container.               |

#### MCP Server Functions

| Function    | Arguments          | Description                              |
| :---------- | :----------------- | :--------------------------------------- |
| `mcp_start` | `<service> [port]` | Start MCP service container.             |
| `mcp_stop`  | `[service\|all]`   | Stop MCP service(s).                     |
| `mcp_list`  | `(none)`           | List available and running MCP services. |

#### Development Stack Functions

| Function           | Arguments         | Description                                            |
| :----------------- | :---------------- | :----------------------------------------------------- |
| `dev_stack_start`  | `[web\|ai\|full]` | Starts a pre-configured stack of development services. |
| `dev_stack_stop`   | `(none)`          | Stops all services managed by this script.             |
| `dev_stack_status` | `(none)`          | Shows the running status of the dev stack services.    |

#### Project Templates

| Function             | Arguments               | Description                                            |
| :------------------- | :---------------------- | :----------------------------------------------------- |
| `create_web_project` | `<name> [node\|python]` | Create web project template with Docker Compose.       |
| `create_ai_project`  | `<name>`                | Create AI/ML project template with Qdrant and Jupyter. |

#### MLbox Integration (SSH)

| Function       | Arguments                              | Description                   |
| :------------- | :------------------------------------- | :---------------------------- |
| `mlbox_tunnel` | `<local_port> <remote_port> [service]` | Create SSH tunnel to MLbox.   |
| `mlbox_deploy` | `<image_name> [container_name]`        | Deploy Docker image to MLbox. |

#### Utility Functions

| Function             | Arguments                 | Description                        |
| :------------------- | :------------------------ | :--------------------------------- |
| `py_docker_dev`      | `[python_version] [port]` | Python development container.      |
| `docker_maintenance` | `(none)`                  | Interactive Docker system cleanup. |
| `docker_overview`    | `(none)`                  | Show Docker system overview.       |
| `docker_help`        | `(none)`                  | Show all custom Docker functions.  |

#### Docker Aliases

| Alias         | Description                                         |
| :------------ | :-------------------------------------------------- |
| `dps`         | `docker ps`                                         |
| `dpsa`        | `docker ps -a`                                      |
| `di`          | `docker images`                                     |
| `dlog`        | `docker logs -f`                                    |
| `dexec`       | `docker exec -it`                                   |
| `dstop`       | Stop all running containers                         |
| `drm`         | Remove all stopped containers                       |
| `drmi`        | Remove all images                                   |
| `dcleanup`    | `docker system prune -af && docker volume prune -f` |
| `dcleanbuild` | `docker builder prune -af`                          |
| `dspace`      | `docker system df`                                  |
| `dinfo`       | `docker info`                                       |
| `dc`          | `docker-compose`                                    |
| `dcup`        | `docker-compose up -d`                              |
| `dcdown`      | `docker-compose down`                               |
| `dclogs`      | `docker-compose logs -f`                            |

---

## FAQ

**Can I use parts of this without installing everything?**

Yeah. Each function file (`.zsh_python_functions`, `.zsh_node_functions`, etc.) can be symlinked individually and sourced from your own `.zshrc`. Some of them reference shared helpers defined in the main `.zshrc`, so you might need to grab a function or two, but there's no "all or nothing" requirement. The installer is the easy path, not the only path.

**Will this nuke my existing dotfiles?**

No. The installer is fully interactive and asks before every step. But it goes further than that: before stow even runs, it scans your home directory for conflicts. If it finds a real file where it wants to place a symlink, it stops and gives you three options: auto-backup the conflicting files to `~/dotfiles-backup/`, force-adopt them into the repo with `--force` (which uses `stow --adopt`, then you review with `git diff`), or handle it yourself. Stow itself also refuses to overwrite a real file with a symlink, so there are two layers of protection before anything gets touched.

**Why GNU Stow instead of chezmoi / yadm / a bare git repo?**

Stow is dumb in the best way. It makes symlinks. That's it. No templating language, no special commands to remember, no database of managed files. The repo structure mirrors your home directory exactly, so you can see what goes where just by looking at the file tree. I tried fancier tools and kept fighting them. Stow gets out of the way.

**Why uv? Why pnpm and bun? Why not [thing I'm already using]?**

These are my opinions, not universal truths. `uv` is absurdly fast and replaces pip, pip-tools, virtualenv, and pyenv in one binary. pnpm and bun are both faster and stricter than npm, and bun doubles as a runtime. npm and yarn aren't blocked because they're bad, they're blocked because mixing package managers in the same project creates lockfile conflicts that waste your afternoon. If you disagree, the wrappers are easy to find and easier to delete.

**Does this work on my machine?**

If you're running zsh on macOS, Ubuntu/Debian, Fedora, Arch, openSUSE, or WSL, probably yes. The installer detects your OS and package manager and adapts accordingly. On Linux it handles the quirks for you, like `fd` being packaged as `fdfind` on Debian/Ubuntu (it auto-symlinks), or `eza` and `gh` needing separate repos on apt-based systems. It does not support bash or fish. It's zsh all the way down, and converting it would be a different project entirely.

**What about my API keys and private settings?**

Nothing secret goes in this repo. There's a built-in pattern for private files that stay out of version control: `~/.zshrc.private` for shell secrets and machine-specific settings, `~/.gitconfig.private` for git identity and SSH routing. The installer will prompt you to create them on a fresh machine, but if `~/.gitconfig.private` already exists (say, with multi-account config), it won't touch it. The global `.gitignore` protects against accidentally committing them.

**How do I update after pulling new changes?**

`./install.sh --update` will pull the latest and restow everything. Under the hood, stow `-R` unstows and restows in one pass, so it's not literally a no-op, but the end result is the same as a fresh install: any new files in the repo get symlinked, and existing links stay put. If you've modified a symlinked file locally, well, you've modified it in the repo too, because that's how symlinks work. Which is either a feature or a footgun depending on your perspective.
