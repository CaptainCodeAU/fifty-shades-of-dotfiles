export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8
export LC_COLLATE=en_AU.UTF-8
export LC_CTYPE=en_AU.UTF-8
export LC_MESSAGES=en_AU.UTF-8
export LC_MONETARY=en_AU.UTF-8

autoload -U +X compinit && compinit

# More info - https://devqa.io/brew-install-java/
export JAVA_8_HOME=$(/usr/libexec/java_home -v1.8)
export JAVA_11_HOME=$(/usr/libexec/java_home -v11)
export JAVA_13_HOME=$(/usr/libexec/java_home -v13)
export JAVA_16_HOME=$(/usr/libexec/java_home -v16)
alias java8='export JAVA_HOME=$JAVA_8_HOME'
alias java11='export JAVA_HOME=$JAVA_11_HOME'
alias java13='export JAVA_HOME=$JAVA_13_HOME'
alias java16='export JAVA_HOME=$JAVA_16_HOME'

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# pyenv setup
# More info: https://github.com/pyenv/pyenv#set-up-your-shell-environment-for-pyenv
export ZSH_PYENV_VIRTUALENV=true
export PYENV_ROOT="$HOME/.pyenv"
# command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
# export PATH="$PYENV_ROOT/bin:$PATH"

# PYENV_VERSION is more temporary and scoped, which is good for project-specific versions.
# It takes precedence over the global setting. Therefore we are NOT setting it at the global level (here).
# The .pyenv/version file is more permanent and global, which is good for setting our overall default.
# Note: Setting PYENV_VERSION environment variable allows you to temporarily override both,
# the local and global Python versions that you've set with pyenv local <version> and pyenv global <version>
# export PYENV_VERSION=3.11.4

# This command checks if pyenv is available on the system.
# If it is, then it initializes pyenv!
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

# This command checks if pyenv-virtualenv-init is available on the system.
# If it is, then it initializes pyenv-virtualenv, which is
# an extension for pyenv that allows you to handle Python virtual environments.
if command -v pyenv-virtualenv-init 1>/dev/null 2>&1; then
  eval "$(pyenv virtualenv-init -)"
fi

# Add pyenv's shims directory to the front of the PATH
export PATH="$PYENV_ROOT/shims:$PATH"

# More info: https://virtualenvwrapper.readthedocs.io/en/latest/install.html#basic-installation
#export WORKON_HOME=$HOME/.virtualenvs
#source /Users/admin/.pyenv/shims/virtualenvwrapper.sh

# To avoid them accidentally linking against a Pyenv-provided Python, add the following line into your interactive shell's configuration
alias brew='env PATH="${PATH//$(pyenv root)\/shims:/}" brew'


# pip should only run if there is a virtualenv currently activated
export PIP_REQUIRE_VIRTUALENV=true


# enable completions for pipx:
eval "$(register-python-argcomplete pipx)"

# To enable shell autocompletion for uv commands
eval "$(uv generate-shell-completion zsh)"
# To enable shell autocompletion for uvx commands
eval "$(uvx --generate-shell-completion zsh)"


# Starship Setup
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
eval "$(starship init zsh)"



export NVM_DIR="$HOME/.nvm"
  # This loads nvm
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh"
  # This loads nvm bash_completion
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"
# You can set $NVM_DIR to any location, but leaving it unchanged from /usr/local/opt/nvm will destroy any nvm-installed Node installations upon upgrade/reinstall.


# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# ZSH_THEME="robbyrussell"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions vscode history-substring-search shellfirm pyenv)
# virtualenv virtualenv-autodetect
# autoload -U compinit && compinit


source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Settings for mono / "brew install mono"
# mono-project.com
# alias sqlite="/usr/local/opt/sqlite/bin/sqlite3"
# alias sqlite3="/usr/local/opt/sqlite/bin/sqlite3"

export LDFLAGS="-L/usr/local/opt/sqlite/lib"
export CPPFLAGS="-I/usr/local/opt/sqlite/include"
export PKG_CONFIG_PATH="/usr/local/opt/sqlite/lib/pkgconfig"
export MONO_GAC_PREFIX="/usr/local"

export FrameworkPathOverride="/Library/Frameworks/Mono.framework/Versions/Current"

alias cls="clear"
alias down="cd ~/Downloads"
alias desk="cd ~/Desktop"
alias ..="cd .."
alias ....="cd ../.."
#alias ls="ls -tUal -G"
#alias lssort="ls -Sal -G"
alias ll="lsd -al"

alias ffmpeg="/Users/admin/Documents/apps/ffmpeg"
alias ffprobe="/Users/admin/Documents/apps/ffprobe"
alias ffplay="/Users/admin/Documents/apps/ffplay"

alias look="sudo find . -name"
alias search="sudo grep --color -rnw ./ -e "
alias ports="sudo lsof -PiTCP -sTCP:LISTEN"

alias merge_tracks='/Users/admin/merge_tracks.sh'


alias speedtest="wget -O /dev/null cachefly.cachefly.net/10mb.test"

# alias poetry_shell='. "$(dirname $(poetry run which python))/activate"'

# Android Studio alias
alias studio="open -a \"Android Studio\" "

# If you are getting "zsh: no matches found" error then you must add this line below
setopt nonomatch

DOTNET_CLI_TELEMETRY_OPTOUT=1
export PATH="$PATH:/Users/admin/.dotnet/tools"

# source /usr/local/opt/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# export PATH="$HOME/.poetry/bin:$PATH"

# add Flutter path
# export PATH="$PATH:/Users/admin/My_Shell_Code/flutter/bin"

export PATH="/usr/local/opt/tcl-tk/bin:$PATH"
export PATH="/usr/local/opt/php@8.1/bin:$PATH"
export PATH="/usr/local/opt/php@8.1/sbin:$PATH"

# Created by `pipx` on 2024-10-16 04:03:51
export PATH="$PATH:/Users/admin/.local/bin"


[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh


# Function to create/update the VSCode project's local settings.json file
update_vscode_settings() {
    local settings_file=".vscode/settings.json"
    local default_settings=$(cat <<- EOM
{
    "editor.indentSize": "tabSize",
    "editor.fontSize": 16,
    "editor.suggestFontSize": 16,
    "editor.minimap.enabled": false,
    "editor.inlineSuggest.enabled": true,
    "editor.bracketPairColorization.enabled": true,
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "editor.linkedEditing": true,
    "editor.accessibilitySupport": "off",
    "workbench.startupEditor": "none",
    "workbench.editor.enablePreview": false,
    # "python.defaultInterpreterPath": ".venv/bin/python",
    "python.defaultInterpreterPath": ".venv/bin/python",
    "python.analysis.extraPaths": [".venv/lib/python3.x/site-packages"],
    "python.analysis.typeCheckingMode": "basic",
    "python.experiments.optOutFrom": ["All"],
    "[python]": {
        "editor.formatOnType": true,
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
            "source.fixAll": "explicit",
            "source.organizeImports": "explicit"
        },
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.rulers": [80],
        "editor.tabCompletion": "onlySnippets",
        "editor.wordBasedSuggestions": "matchingDocuments",
        "python.formatting.provider": "black",
        "python.formatting.blackArgs": ["--line-length", "80"]
    },
    "ruff.nativeServer": "on",
    "ruff.logLevel": "trace",
    "ruff.showNotifications": "always",
    "ruff.interpreter": ["${workspaceFolder}/.venv/bin/python"],
    "[json]": {
        "editor.defaultFormatter": "vscode.json-language-features"
    },
    "prettier.printWidth": 80,
    "prettier.tabWidth": 4,
    "prettier.singleQuote": true,
    "prettier.trailingComma": "all",
    "prettier.bracketSpacing": true,
    "prettier.useTabs": true,
    "prettier.arrowParens": "avoid",
    "prettier.endOfLine": "auto",
    "explorer.confirmDragAndDrop": false,
    "git.confirmSync": false,
    "git.autofetch": true,
    "security.workspace.trust.untrustedFiles": "open",
    "gitHistory.logLevel": "Debug",
    "accessibility.signals": {
		"diffLineDeleted": "off",
		"diffLineInserted": "off",
		"diffLineModified": "off",
		"lineHasBreakpoint": "off",
		"lineHasError": "off",
		"lineHasFoldedArea": "off",
		"lineHasInlineSuggestion": "off",
		"noInlayHints": "off",
		"onDebugBreak": "off",
		"taskCompleted": "off",
		"taskFailed": "off",
		"terminalCommandFailed": "off",
		"terminalQuickFix": "off"
	}
}
EOM
)

    # Ensure .vscode directory exists
    mkdir -p ".vscode"

    # Count the lines in the settings file if it exists, or set line count to 0
    local line_count=$( [[ -f $settings_file ]] && wc -l < $settings_file || echo "0" )

    # If settings file doesn't exist or has less than 12 lines, replace it with default settings
    if (( line_count < 12 )); then
        # echo "$default_settings" > $settings_file
        echo "$default_settings" | sed 's/    /\t/g' > $settings_file
    fi
}


# Function to remove the `venv` directory
venv_delete() {
  if [[ -d "./venv" ]]; then
    echo "Removing .venv directory..."
    rm -rf "./venv"
    echo ".venv directory removed."
  else
    echo "No venv directory found in the current directory."
  fi
}


# Function to create .gitignore file
create_gitignore() {
    if [[ ! -f "./.gitignore" ]]; then
        echo "Creating .gitignore with common entries..."
        cat << EOF > .gitignore
*.db
npm-debug.log
*/node_modules/
tsconfig.lsif.json
*.lsif
tmp/
temp/
log/
logs/
package-lock.json

# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
share/python-wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# PyInstaller
#  Usually these files are written by a python script from a template
#  before PyInstaller builds the exe, so as to inject date/other infos into it.
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.nox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
*.py,cover
.hypothesis/
.pytest_cache/

# Translations
*.mo
*.pot

# Django stuff:
*.log
local_settings.py
db.sqlite3
db.sqlite3-journal
*.sqlite3

# Flask stuff:
instance/
.webassets-cache

# Scrapy stuff:
.scrapy

# Sphinx documentation
docs/_build/

# PyBuilder
.pybuilder/
target/

# Jupyter Notebook
.ipynb_checkpoints

# IPython
profile_default/
ipython_config.py

# PEP 582; used by e.g. github.com/David-OConnor/pyflow and github.com/pdm-project/pdm
__pypackages__/

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# IDEs
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
EOF
    fi
}

# Function to create README.md file
create_readme() {
  if [[ ! -f "./README.md" ]]; then
  echo "Creating README.md..."
  cat << EOF > README.md
# $project_name

## Description
Brief description of your project.

## Installation
\`\`\`
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
\`\`\`

## Usage
\`\`\`python
from $project_name.main import main

main()
\`\`\`

## Running Tests
\`\`\`
uv run pytest
\`\`\`

## Re-resolve all dedependencies
\`\`\`
uv sync
\`\`\`
EOF
  fi
}


# Function to activate the Python virtual environment in that directory
# Note: It will also create the `venv` and other common files if they don't exist
venv_on() {

  # Check if uv is installed
  if ! command -v uv &> /dev/null; then
    echo "Error: uv is not installed. Please install it first."
    return 1
  fi


  # Check for the `.python-version` file
  if [[ ! -f "./.python-version" ]]; then
    echo "3.13" > ./.python-version
    echo "" >> ./.python-version
    echo ".python-version file created."
  fi

  # Determine project name from current directory if not set
  if [[ -z "$project_name" ]]; then
    project_name=$(basename "$PWD")
  fi

  # Convert project name to Python-friendly format
  project_name=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr '-' '_')

  # Initialize the project using uv init --lib
  if [[ ! -f "./pyproject.toml" ]]; then
    echo "Initializing project with uv init --lib..."
    uv init --lib --name "$project_name" .
  else
    echo "Project already initialized. Skipping uv init."
  fi

  # Create or update pyproject.toml with custom configuration
  echo "Updating pyproject.toml with custom configuration..."
  cat << EOF > pyproject.toml
[project]
name = "$project_name"
version = "0.1.0"
description = "Your project description"
authors = [
    {name = "Your Name", email = "your.email@example.com"},
]
readme = "README.md"
requires-python = ">=3.13"
dependencies = []

[project.scripts]
# hello = "example_package_app:hello"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"


[tool.ruff]
fix = true
line-length = 100
indent-width = 4
src = ["."]
target-version = "py313"
extend-include = ["*.ipynb"]

[tool.ruff.lint]
select = ["ALL"]
# Allow fix for all enabled rules (when `--fix`) is provided.
fixable = ["ALL"]
unfixable = []
ignore = [
#     "E501",  # line too long, handled by black
#     "B008",  # do not perform function calls in argument defaults
#     "C901",  # too complex
    "D203",  # one-blank-line-before-class
    "D212",  # multi-line-summary-first-line
#     "D100",  # Missing docstring in public module
#     "D101",  # Missing docstring in public class
#     "D102",  # Missing docstring in public method
    "D103",  # Missing docstring in public function
    "D104",  # Missing docstring in public package
#     "D107",  # Missing docstring in __init__
    "T201",  # Print found
#     "ANN001",  # Missing type annotation for function argument
#     "ANN201",  # Missing return type annotation for public function
    "S101",  # Use of assert detected
    "COM812",  # Missing trailing comma
    "ISC001",  # Implicitly concatenated strings on a single line
]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"

[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S101", "ANN001", "ANN201"]

[tool.ruff.lint.isort]
known-first-party = ["checkout_ell_ai"]


[tool.distutils.bdist_wheel]
universal = true

[tool.hatch.build.targets.wheel]
packages = ["src/$project_name"]

[tool.pytest.ini_options]
addopts = "-v -s"
testpaths = ["tests"]
EOF

  # Create and activate uv virtual environment
  echo "Creating and activating uv virtual environment..."
  uv venv
  source .venv/bin/activate

  # Create project structure if it doesn't exist
  if [[ ! -d "./src/$project_name" ]]; then
    echo "Creating project structure..."
    mkdir -p "src/$project_name"
  fi

  # Create or update __init__.py
  echo "Creating/updating src/$project_name/__init__.py..."
  cat << EOF > "src/$project_name/__init__.py"
"""$project_name package."""

def hello() -> str:
    """Return a greeting message."""
    return "Hello from $project_name!"
EOF

  # Create or update main.py
  echo "Creating/updating main.py..."
  cat << EOF > "src/$project_name/main.py"
"""Main module for $project_name."""

def main() -> None:
    """Run the main application."""
    print("Hello, $project_name!")

if __name__ == "__main__":
    main()
EOF


  # Create test folder if it doesn't exist
  if [[ ! -d "./tests" ]]; then
    echo "Creating test folder and example test..."
    mkdir -p "tests"

    # Create or update __init__.py
    touch "tests/__init__.py"

    # Create example test file
    cat << EOF > "tests/test_main.py"
"""Tests for the main module."""

import pytest
from $project_name.main import main

def test_main(capsys: pytest.CaptureFixture[str]) -> None:
    """Test the main function output."""
    main()
    captured = capsys.readouterr()
    assert captured.out.strip() == "Hello, $project_name!"
EOF
  fi

  # Create README.md
  create_readme

  # Install dependencies
  echo "Installing dependencies..."
  uv pip install ruff
  uv pip install -e .

  # Install development dependencies
  echo "Installing development dependencies..."
  # Testing
  uv add --dev pytest
  # Type checking: To make sure that the types are what you document it to be, we can use pyright.
  uv add --dev pyright
  # Code coverage: also track the code coverage
  uv add --dev pytest-cov

  # Create .env file for environment variables if it doesn't exist
  if [[ ! -f "./.env" ]]; then
    echo "Creating .env file..."
    cat << EOF > .env
# Add your environment variables here
# Example:
# API_KEY=your_api_key_here
EOF
  fi

  # Create or update the .vscode/settings.json file with the provided settings
  update_vscode_settings

  # Check and create `.gitignore` if it doesn't exist
  create_gitignore

  # Generate requirements files
  # echo "Generating requirements files..."
  # uv pip compile pyproject.toml -o requirements.txt
  # uv pip compile pyproject.toml --extra dev -o requirements-dev.txt


  # Run linting, formatting, and tests
  echo "Running linting, formatting, and tests..."
  # Linting: To check if the project is up to standards we can run,
  uvx ruff check .
  # Formatting: This checks how your code is visually structured
  uvx ruff format .
  # To get pyright running we can run
  uv run pyright .
  # Neatly runs the tests. The `-v` flag for a bit more detailed output.
  # Pass in `--durations=5` which prints the duration of the 5 longest running tests.
  uv run pytest tests -v --durations=5
  # Code Coverage
  uv run pytest -v --durations=0 --cov --cov-report=xml

  # Building a wheel
  # uv build

  echo "Project setup complete. Virtual environment activated."
}



# Function to deactivate the Python virtual environment in that directory
venv_off() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo "Deactivating virtual environment..."
        deactivate
        echo "Virtual environment deactivated."
    else
        echo "No active virtual environment detected."
    fi
}


