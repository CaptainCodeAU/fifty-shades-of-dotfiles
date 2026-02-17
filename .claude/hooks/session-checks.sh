#!/bin/bash
# Combined session startup checks:
#   1. Uncommitted file status
#   2. Unencrypted .env detection
# Runs on Claude Code SessionStart

# ─── Colors ───────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Box drawing chars
TL='╭' TR='╮' BL='╰' BR='╯' H='─' V='│'

# ─── 1. Uncommitted file status ──────────────────────

if git rev-parse --git-dir &>/dev/null; then
  count=$(git status --porcelain 2>/dev/null | wc -l | xargs)

  if [ "$count" -eq 0 ]; then
    echo -e "${DIM}✓ Working tree clean${NC}"
  else
    if [ "$count" -gt 5 ]; then
      echo -e "${YELLOW}●${NC} ${count} uncommitted changes"
    else
      echo -e "${DIM}●${NC} ${count} uncommitted"
    fi
  fi
fi

# ─── 2. Env encryption check ─────────────────────────

# Only run if we're in a project directory
if [[ ! -f "package.json" && ! -f "pyproject.toml" && ! -d ".git" ]]; then
  exit 0
fi

# Check if dotenvx is installed
if ! command -v dotenvx &> /dev/null; then
  echo ""
  echo -e "${YELLOW}${TL}${H}${H}${H} ⚠️  dotenvx ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${NC}"
  echo -e "${YELLOW}${V}${NC}"
  echo -e "${YELLOW}${V}${NC}  dotenvx not installed"
  echo -e "${YELLOW}${V}${NC}  ${DIM}brew install dotenvx/brew/dotenvx${NC}"
  echo -e "${YELLOW}${V}${NC}"
  echo -e "${YELLOW}${BL}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${NC}\n"
  exit 0
fi

# Function to check if .env is encrypted
is_encrypted() {
  local file="$1"
  grep -q "^#/---" "$file" 2>/dev/null && return 0
  grep -qE "^[A-Za-z_][A-Za-z0-9_]*=['\"]?encrypted:" "$file" 2>/dev/null
}

# Scenario 1: Unencrypted .env exists
if [[ -f ".env" ]]; then
  if ! is_encrypted ".env"; then
    echo ""
    echo -e "${RED}${TL}${H}${H}${H} 🔐 SECURITY ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${NC}"
    echo -e "${RED}${V}${NC}"
    echo -e "${RED}${V}${NC}  ${BOLD}Unencrypted .env file detected${NC}"
    echo -e "${RED}${V}${NC}  Secrets may be exposed in commits!"
    echo -e "${RED}${V}${NC}"
    echo -e "${RED}${V}${NC}  ${CYAN}Ask Claude:${NC} \"encrypt my .env file\""
    echo -e "${RED}${V}${NC}  ${DIM}Or: ~/.claude/scripts/encrypt-env.sh${NC}"
    echo -e "${RED}${V}${NC}"
    echo -e "${RED}${BL}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${NC}\n"
    exit 0
  else
    # Verify .env.keys exists for decryption
    if [[ ! -f ".env.keys" ]]; then
      echo ""
      echo -e "${YELLOW}${TL}${H}${H}${H} ⚠️  Missing Key ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${NC}"
      echo -e "${YELLOW}${V}${NC}"
      echo -e "${YELLOW}${V}${NC}  .env is encrypted but .env.keys missing"
      echo -e "${YELLOW}${V}${NC}  You won't be able to decrypt!"
      echo -e "${YELLOW}${V}${NC}"
      echo -e "${YELLOW}${V}${NC}  ${DIM}Create .env.keys with:${NC}"
      echo -e "${YELLOW}${V}${NC}  ${DIM}DOTENV_PRIVATE_KEY=\"your-key-here\"${NC}"
      echo -e "${YELLOW}${V}${NC}"
      echo -e "${YELLOW}${BL}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${NC}\n"
    fi
    exit 0
  fi
fi

# Scenario 2: Check for unencrypted .env variants
UNENCRYPTED_VARIANTS=()
for variant in .env.local .env.development .env.production .env.staging .env.test; do
  if [[ -f "$variant" ]] && ! is_encrypted "$variant"; then
    UNENCRYPTED_VARIANTS+=("$variant")
  fi
done

if [[ ${#UNENCRYPTED_VARIANTS[@]} -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}${TL}${H}${H}${H} ⚠️  Unencrypted ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${NC}"
  echo -e "${YELLOW}${V}${NC}"
  for f in "${UNENCRYPTED_VARIANTS[@]}"; do
    echo -e "${YELLOW}${V}${NC}  • ${f}"
  done
  echo -e "${YELLOW}${V}${NC}"
  echo -e "${YELLOW}${V}${NC}  ${DIM}dotenvx encrypt -f <filename>${NC}"
  echo -e "${YELLOW}${V}${NC}"
  echo -e "${YELLOW}${BL}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${NC}\n"
fi

# Scenario 3: .env.example exists but no .env
if [[ -f ".env.example" && ! -f ".env" ]]; then
  echo ""
  echo -e "${CYAN}${TL}${H}${H}${H} 📋 Setup Needed ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${NC}"
  echo -e "${CYAN}${V}${NC}"
  echo -e "${CYAN}${V}${NC}  Found .env.example but no .env file"
  echo -e "${CYAN}${V}${NC}"
  echo -e "${CYAN}${V}${NC}  ${BOLD}Ask Claude:${NC} \"setup my .env file\""
  echo -e "${CYAN}${V}${NC}"
  echo -e "${CYAN}${BL}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${NC}\n"
  exit 0
fi

exit 0
