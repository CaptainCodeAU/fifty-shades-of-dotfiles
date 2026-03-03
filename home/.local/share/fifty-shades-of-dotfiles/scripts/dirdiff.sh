#!/usr/bin/env bash

set -eo pipefail

DIRDIFF_VERSION="1.0.0"
CONFIG_DIR="$HOME/.config/dirdiff"
CONFIG_FILE="$CONFIG_DIR/config"
DEFAULT_LIMIT=30

USE_COLOR=true
OPT_LIMIT=$DEFAULT_LIMIT
OPT_SIZE_DIFF=false
OPT_INLINE_DIFFS=false
OPT_BY_TYPE=false
OPT_JSON=false
OPT_IGNORE_CONTENT=false
OPT_INIT=false
OPT_RESET_CONFIG=false
DIR1=""
DIR2=""
PATH_STYLE="dirname"
JQ_AVAILABLE=false

declare -a IGNORE_DIRS=()
declare -a IGNORE_PATTERNS=()
declare -a CLI_EXCLUDES=()
declare -a EXCLUSION_ARGS=()
declare -a LEFT_FILES=()
declare -a RIGHT_FILES=()
declare -a ONLY_LEFT=()
declare -a ONLY_RIGHT=()
declare -a FILES_DIFFER=()

RED=""
GREEN=""
YELLOW=""
CYAN=""
BOLD=""
DIM=""
RESET=""
BOX_TL="+"
BOX_TR="+"
BOX_BL="+"
BOX_BR="+"
BOX_H="-"
BOX_V="|"
BOX_ML="+"
BOX_MR="+"
BOX_TM="+"
BOX_BM="+"
BOX_X="+"

LEFT_FILES_COUNT=0
LEFT_DIRS_COUNT=0
LEFT_SYMLINKS_COUNT=0
LEFT_SIZE_HUMAN="0B"
RIGHT_FILES_COUNT=0
RIGHT_DIRS_COUNT=0
RIGHT_SYMLINKS_COUNT=0
RIGHT_SIZE_HUMAN="0B"

setup_colors() {
  if [[ "$USE_COLOR" == true && -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
    BOX_TL='┌' ; BOX_TR='┐' ; BOX_BL='└' ; BOX_BR='┘'
    BOX_H='─'  ; BOX_V='│'  ; BOX_ML='├' ; BOX_MR='┤'
    BOX_TM='┬' ; BOX_BM='┴' ; BOX_X='┼'
  else
    BOX_TL='+' ; BOX_TR='+' ; BOX_BL='+' ; BOX_BR='+'
    BOX_H='-'  ; BOX_V='|'  ; BOX_ML='+' ; BOX_MR='+'
    BOX_TM='+' ; BOX_BM='+' ; BOX_X='+'
  fi
}

err() {
  printf "${RED}Error:${RESET} %s\n" "$1" >&2
}

warn() {
  printf "${YELLOW}Warning:${RESET} %s\n" "$1" >&2
}

info() {
  printf "${CYAN}%s${RESET}\n" "$1"
}

repeat_char() {
  local c="$1" n="$2" i
  local out=""
  for (( i=0; i<n; i++ )); do out="${out}${c}"; done
  printf '%s' "$out"
}

print_rule() {
  local label="$1" width=56
  if [[ -n "$label" ]]; then
    local pad=$(( width - ${#label} - 3 ))
    if [[ "$pad" -lt 0 ]]; then pad=0; fi
    printf -- "${BOLD}$(repeat_char "$BOX_H" 2) %s $(repeat_char "$BOX_H" "$pad")${RESET}\n" "$label"
  else
    printf -- "${BOLD}$(repeat_char "$BOX_H" "$width")${RESET}\n"
  fi
}

fmt_num() {
  printf "%'d" "$1" 2>/dev/null || printf "%d" "$1"
}

strip_slash() {
  local path="$1"
  while [[ "${path%/}" != "$path" && "$path" != "/" ]]; do
    path="${path%/}"
  done
  printf '%s' "$path"
}

show_help() {
  cat <<EOF
${BOLD}dirdiff${RESET} v${DIRDIFF_VERSION} — Directory Comparison Tool

${BOLD}USAGE${RESET}
  dirdiff [OPTIONS] <dir1> <dir2>

${BOLD}ARGUMENTS${RESET}
  dir1    First directory (shown as "Left")
  dir2    Second directory (shown as "Right")

${BOLD}OPTIONS${RESET}
  -h, --help            Show this help message
  -v, --version         Show version number
  --no-color            Disable colored output
  --limit N             Max differences to list (default: ${DEFAULT_LIMIT}, 0=all)
  --size-diff           Show per-file size comparison for differing files
  --inline-diffs        Preview content changes for differing files
  --by-type             Show file count breakdown by extension
  --json                Output results as JSON (requires jq)
  --ignore-content      Compare structure only, skip content diffing
  --exclude <pattern>   Additional exclusion pattern (repeatable)
  --init                Generate default config if it doesn't exist
  --reset-config        Ensure config exists (no overwrite)

${BOLD}CONFIG${RESET}
  ${CONFIG_FILE}
  Auto-generated on first run. Edit to customise default ignore rules.
  Existing config files are never overwritten.

${BOLD}EXAMPLES${RESET}
  dirdiff dir1 dir2
  dirdiff --exclude .git --exclude "*.log" dir1 dir2
  dirdiff --size-diff --by-type dir1 dir2
  dirdiff --inline-diffs --limit 10 dir1 dir2
  dirdiff --json dir1 dir2 | jq '.summary'
EOF
}

check_dependencies() {
  local required=("diff" "find" "du" "sed" "awk" "wc")
  local missing=()
  local tool
  for tool in "${required[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 4
  fi

  if ! command -v column >/dev/null 2>&1; then
    warn "Optional tool 'column' not found. Table formatting may be degraded."
  fi
  if command -v jq >/dev/null 2>&1; then
    JQ_AVAILABLE=true
  fi
}

generate_default_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'EOF'
# ─────────────────────────────────────────────────────────
# dirdiff configuration
# ─────────────────────────────────────────────────────────
# This file controls default ignore rules for dirdiff.
# Comment out any line with # to temporarily stop excluding it.
# Existing config files are never overwritten by dirdiff.
# ─────────────────────────────────────────────────────────
[default]

path_style = dirname

ignore_dirs = [
  .git,
  node_modules,
  .next,
  .claude,
  .roo,
  # dist,
  # build,
  # vendor,
  # __pycache__,
  # .venv,
  # .terraform,
  # .cache,
  # coverage,
  # .svn,
  # .hg,
  # History,
  # WebStorage,
  # workspaceStorage,
  # site-packages,
  # shell-snapshots,
  # index-build,
  # checkouts,
  # debug,
]

ignore_patterns = [
  *.ibd,
  *.ibt,
  *.sdi,
  *.hbs,
  *_tmp,
  binlog.*,
  # *.pyc,
  # *.o,
  # *.so,
  # *.log,
  # *.swp,
  # .DS_Store,
  # Thumbs.db,
  # *.bak,
  # *.orig,
]
EOF
}

reset_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    printf "Config already exists: %s\n" "$CONFIG_FILE"
    return
  fi
  generate_default_config
  printf "Generated: %s\n" "$CONFIG_FILE"
}

ensure_local_config_file() {
  mkdir -p "$CONFIG_DIR"

  if [[ -L "$CONFIG_FILE" ]]; then
    local tmp
    tmp="$(mktemp)"

    cat "$CONFIG_FILE" > "$tmp" 2>/dev/null || true
    rm -f "$CONFIG_FILE"

    if [[ -s "$tmp" ]]; then
      cp "$tmp" "$CONFIG_FILE"
      info "Converted symlinked config to local file: ${CONFIG_FILE}"
    else
      generate_default_config
      info "Generated default config: ${CONFIG_FILE}"
    fi

    rm -f "$tmp"
  fi
}

ensure_config() {
  ensure_local_config_file
  if [[ ! -f "$CONFIG_FILE" ]]; then
    generate_default_config
    info "Generated default config: ${CONFIG_FILE}"
  fi
}

parse_config() {
  IGNORE_DIRS=()
  IGNORE_PATTERNS=()
  PATH_STYLE="dirname"

  local line_num=0
  local in_array=false
  local current_key=""
  local section_count=0
  local saw_default=false

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line_num=$((line_num + 1))
    local line trimmed entry value

    line="$(printf '%s' "$raw_line" | tr -d '\r')"
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
      continue
    fi

    if [[ "$in_array" == true ]]; then
      if [[ "$trimmed" == "]" ]]; then
        in_array=false
        current_key=""
        continue
      fi

      entry="$(printf '%s' "$trimmed" | sed 's/,[[:space:]]*$//')"
      if [[ -z "$entry" ]]; then
        err "Config error on line ${line_num}: empty entry in '${current_key}'."
        return 1
      fi

      if [[ "$current_key" == "ignore_dirs" ]]; then
        IGNORE_DIRS+=("$entry")
      else
        IGNORE_PATTERNS+=("$entry")
      fi
      continue
    fi

    if [[ "$trimmed" =~ ^\[[^]]+\]$ ]]; then
      section_count=$((section_count + 1))
      if [[ "$trimmed" != "[default]" ]]; then
        err "Config error on line ${line_num}: only [default] section is allowed."
        return 1
      fi
      saw_default=true
      continue
    fi

    if [[ "$trimmed" =~ ^path_style[[:space:]]*= ]]; then
      value="$(printf '%s' "$trimmed" | sed 's/^[^=]*=[[:space:]]*//')"
      if [[ "$value" != "relative" && "$value" != "dirname" && "$value" != "full" ]]; then
        err "Config error on line ${line_num}: invalid path_style '${value}'. Must be relative, dirname, or full."
        return 1
      fi
      PATH_STYLE="$value"
      continue
    fi

    if [[ "$trimmed" =~ ^ignore_dirs[[:space:]]*=[[:space:]]*\[$ ]]; then
      in_array=true
      current_key="ignore_dirs"
      continue
    fi

    if [[ "$trimmed" =~ ^ignore_patterns[[:space:]]*=[[:space:]]*\[$ ]]; then
      in_array=true
      current_key="ignore_patterns"
      continue
    fi

    err "Config error on line ${line_num}: unrecognized content '${trimmed}'."
    return 1
  done < "$CONFIG_FILE"

  if [[ "$in_array" == true ]]; then
    err "Config error: unclosed array for '${current_key}' (missing closing ']')."
    return 1
  fi

  if [[ "$saw_default" != true || "$section_count" -ne 1 ]]; then
    err "Config error: expected exactly one [default] section."
    return 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        setup_colors
        show_help
        exit 0
        ;;
      -v|--version)
        printf "dirdiff %s\n" "$DIRDIFF_VERSION"
        exit 0
        ;;
      --no-color)
        USE_COLOR=false
        ;;
      --limit)
        shift
        if [[ -z "${1:-}" || ! "$1" =~ ^[0-9]+$ ]]; then
          err "--limit requires a numeric argument"
          exit 2
        fi
        OPT_LIMIT="$1"
        ;;
      --size-diff)
        OPT_SIZE_DIFF=true
        ;;
      --inline-diffs)
        OPT_INLINE_DIFFS=true
        ;;
      --by-type)
        OPT_BY_TYPE=true
        ;;
      --json)
        OPT_JSON=true
        ;;
      --ignore-content)
        OPT_IGNORE_CONTENT=true
        ;;
      --exclude)
        shift
        if [[ -z "${1:-}" ]]; then
          err "--exclude requires a pattern argument"
          exit 2
        fi
        CLI_EXCLUDES+=("$1")
        ;;
      --init)
        OPT_INIT=true
        ;;
      --reset-config)
        OPT_RESET_CONFIG=true
        ;;
      -*)
        err "Unknown option: $1"
        printf "Run 'dirdiff --help' for usage.\n" >&2
        exit 2
        ;;
      *)
        if [[ -z "$DIR1" ]]; then
          DIR1="$(strip_slash "$1")"
        elif [[ -z "$DIR2" ]]; then
          DIR2="$(strip_slash "$1")"
        else
          err "Too many arguments. Expected two directories."
          exit 2
        fi
        ;;
    esac
    shift
  done
}

build_exclusions() {
  EXCLUSION_ARGS=()
  local item
  for item in "${IGNORE_DIRS[@]}"; do
    EXCLUSION_ARGS+=("--exclude-dir=$item")
  done
  for item in "${IGNORE_PATTERNS[@]}"; do
    EXCLUSION_ARGS+=("--exclude=$item")
  done
  for item in "${CLI_EXCLUDES[@]}"; do
    EXCLUSION_ARGS+=("--exclude=$item")
  done
}

format_path() {
  local rel="$1"
  local base="$2"

  case "$PATH_STYLE" in
    full)
      local abs
      abs="$(cd "$base" 2>/dev/null && pwd)"
      printf '%s/%s' "$abs" "$rel"
      ;;
    dirname)
      printf '%s/%s' "$(basename "$base")" "$rel"
      ;;
    relative|*)
      printf '%s' "$rel"
      ;;
  esac
}

dir_label() {
  basename "$1"
}

filtered_find() {
  local dir="$1"
  local type="$2"
  shift 2

  local find_args=()
  local item
  for item in "${IGNORE_DIRS[@]}"; do
    find_args+=( -name "$item" -o )
  done
  if [[ ${#find_args[@]} -gt 0 ]]; then
    unset "find_args[$(( ${#find_args[@]} - 1 ))]"
    find "$dir" \( -type d \( "${find_args[@]}" \) -prune \) -o -type "$type" "$@" 2>/dev/null
  else
    find "$dir" -type "$type" "$@" 2>/dev/null
  fi
}

_human_size() {
  local bytes="$1"
  if [[ "$bytes" -ge 1073741824 ]]; then
    awk "BEGIN {printf \"%.1fG\", ${bytes}/1073741824}"
  elif [[ "$bytes" -ge 1048576 ]]; then
    awk "BEGIN {printf \"%.1fM\", ${bytes}/1048576}"
  elif [[ "$bytes" -ge 1024 ]]; then
    awk "BEGIN {printf \"%.1fK\", ${bytes}/1024}"
  else
    printf "%dB" "$bytes"
  fi
}

filtered_size() {
  local dir="$1"

  if du --exclude=__nonexistent__ -sh "$dir" >/dev/null 2>&1; then
    local args=("-sh")
    local i
    for (( i=0; i<${#IGNORE_DIRS[@]}; i++ )); do
      args=("${args[@]}" "--exclude=${IGNORE_DIRS[$i]}")
    done
    for (( i=0; i<${#IGNORE_PATTERNS[@]}; i++ )); do
      args=("${args[@]}" "--exclude=${IGNORE_PATTERNS[$i]}")
    done
    for (( i=0; i<${#CLI_EXCLUDES[@]}; i++ )); do
      args=("${args[@]}" "--exclude=${CLI_EXCLUDES[$i]}")
    done
    du "${args[@]}" "$dir" 2>/dev/null | cut -f1
  else
    local bytes
    bytes=$(filtered_find "$dir" "f" -print0 | xargs -0 stat -f%z 2>/dev/null | awk '{s+=$1} END {print s+0}')
    if [[ -z "$bytes" || "$bytes" = "0" ]]; then
      du -sh "$dir" 2>/dev/null | cut -f1
    else
      _human_size "$bytes"
    fi
  fi
}

list_regular_files() {
  local base="$1"
  local output_file="$2"
  local exclude_expr=()
  local dir_name
  local pattern

  for dir_name in "${IGNORE_DIRS[@]}"; do
    exclude_expr+=( -name "$dir_name" -o )
  done
  if [[ ${#exclude_expr[@]} -gt 0 ]]; then
    unset "exclude_expr[$(( ${#exclude_expr[@]} - 1 ))]"
  fi

  if [[ ${#exclude_expr[@]} -gt 0 ]]; then
    find "$base" \( -type d \( "${exclude_expr[@]}" \) -prune \) -o -type f -print |
      sed "s#^$base/##" > "$output_file"
  else
    find "$base" -type f -print | sed "s#^$base/##" > "$output_file"
  fi

  if [[ ${#IGNORE_PATTERNS[@]} -gt 0 || ${#CLI_EXCLUDES[@]} -gt 0 ]]; then
    local tmp="$output_file.tmp"
    cp "$output_file" "$tmp"
    : > "$output_file"
    while IFS= read -r rel; do
      local skip=false
      for pattern in "${IGNORE_PATTERNS[@]}"; do
        if [[ "$(basename "$rel")" == $pattern ]]; then
          skip=true
          break
        fi
      done
      if [[ "$skip" == false ]]; then
        for pattern in "${CLI_EXCLUDES[@]}"; do
          if [[ "$rel" == $pattern || "$(basename "$rel")" == $pattern ]]; then
            skip=true
            break
          fi
        done
      fi
      if [[ "$skip" == false ]]; then
        printf '%s\n' "$rel" >> "$output_file"
      fi
    done < "$tmp"
    rm -f "$tmp"
  fi

  sort -u "$output_file" -o "$output_file"
}

gather_stats() {
  local left_file right_file
  left_file="$(mktemp)"
  right_file="$(mktemp)"

  list_regular_files "$DIR1" "$left_file"
  list_regular_files "$DIR2" "$right_file"

  LEFT_FILES=()
  RIGHT_FILES=()
  ONLY_LEFT=()
  ONLY_RIGHT=()
  local common_files=()

  while IFS= read -r line; do
    LEFT_FILES+=("$line")
  done < "$left_file"
  while IFS= read -r line; do
    RIGHT_FILES+=("$line")
  done < "$right_file"
  while IFS= read -r line; do
    ONLY_LEFT+=("$line")
  done < <(comm -23 "$left_file" "$right_file")
  while IFS= read -r line; do
    ONLY_RIGHT+=("$line")
  done < <(comm -13 "$left_file" "$right_file")
  while IFS= read -r line; do
    common_files+=("$line")
  done < <(comm -12 "$left_file" "$right_file")

  FILES_DIFFER=()
  if [[ "$OPT_IGNORE_CONTENT" == false ]]; then
    local rel
    for rel in "${common_files[@]}"; do
      if ! cmp -s "$DIR1/$rel" "$DIR2/$rel"; then
        FILES_DIFFER+=("$rel")
      fi
    done
  fi

  LEFT_FILES_COUNT=$(filtered_find "$DIR1" "f" | wc -l | tr -d ' ')
  LEFT_DIRS_COUNT=$(filtered_find "$DIR1" "d" | wc -l | tr -d ' ')
  LEFT_SYMLINKS_COUNT=$(filtered_find "$DIR1" "l" | wc -l | tr -d ' ')
  LEFT_SIZE_HUMAN=$(filtered_size "$DIR1")

  RIGHT_FILES_COUNT=$(filtered_find "$DIR2" "f" | wc -l | tr -d ' ')
  RIGHT_DIRS_COUNT=$(filtered_find "$DIR2" "d" | wc -l | tr -d ' ')
  RIGHT_SYMLINKS_COUNT=$(filtered_find "$DIR2" "l" | wc -l | tr -d ' ')
  RIGHT_SIZE_HUMAN=$(filtered_size "$DIR2")

  rm -f "$left_file" "$right_file"
}

count_dirs() {
  local base="$1"
  local dir_name
  local exclude_expr=()
  for dir_name in "${IGNORE_DIRS[@]}"; do
    exclude_expr+=( -name "$dir_name" -o )
  done
  if [[ ${#exclude_expr[@]} -gt 0 ]]; then
    unset "exclude_expr[$(( ${#exclude_expr[@]} - 1 ))]"
    find "$base" \( -type d \( "${exclude_expr[@]}" \) -prune \) -o -type d -print | wc -l | awk '{print $1-1}'
  else
    find "$base" -type d | wc -l | awk '{print $1-1}'
  fi
}

count_symlinks() {
  local base="$1"
  find "$base" -type l | wc -l | awk '{print $1}'
}

calc_size_kb() {
  local base="$1"
  du -sk "$base" | awk '{print $1}'
}

format_kb() {
  local kb="$1"
  if [[ "$kb" -ge 1048576 ]]; then
    awk -v v="$kb" 'BEGIN { printf "%.2f GB", v/1048576 }'
  elif [[ "$kb" -ge 1024 ]]; then
    awk -v v="$kb" 'BEGIN { printf "%.2f MB", v/1024 }'
  else
    printf "%s KB" "$kb"
  fi
}

print_header() {
  local w=56
  local label1 label2
  label1="$(dir_label "$DIR1")"
  label2="$(dir_label "$DIR2")"

  printf "\n"
  printf "${BOLD}$(repeat_char '═' $w)${RESET}\n"
  printf "${BOLD}  dirdiff - Directory Comparison${RESET}\n"
  printf "${BOLD}$(repeat_char '═' $w)${RESET}\n"
  printf "  ${RED}◀ %s${RESET}  %s\n" "$label1" "${DIM}${DIR1}${RESET}"
  printf "  ${GREEN}▶ %s${RESET}  %s\n" "$label2" "${DIM}${DIR2}${RESET}"
  printf "  ${DIM}Date:${RESET}   %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

  local total_ex=$(( ${#IGNORE_DIRS[@]} + ${#IGNORE_PATTERNS[@]} + ${#CLI_EXCLUDES[@]} ))
  if [[ "$total_ex" -gt 0 ]]; then
    printf "  ${DIM}Ignoring:${RESET} %d dirs, %d patterns" "${#IGNORE_DIRS[@]}" "${#IGNORE_PATTERNS[@]}"
    if [[ ${#CLI_EXCLUDES[@]} -gt 0 ]]; then
      printf " (+%d from CLI)" "${#CLI_EXCLUDES[@]}"
    fi
    printf "\n"
  fi

  printf "  ${DIM}Config:${RESET}  %s\n" "$CONFIG_FILE"
  printf "${BOLD}$(repeat_char '═' $w)${RESET}\n"
}

print_stats_table() {
  local label1 label2
  label1="$(dir_label "$DIR1")"
  label2="$(dir_label "$DIR2")"

  local cw1=21
  local cw2=${#label1}; if [[ "$cw2" -lt 12 ]]; then cw2=12; fi; cw2=$((cw2 + 2))
  local cw3=${#label2}; if [[ "$cw3" -lt 12 ]]; then cw3=12; fi; cw3=$((cw3 + 2))

  printf "\n"
  printf "${BOLD}${BOX_TL}$(repeat_char "$BOX_H" $cw1)${BOX_TM}$(repeat_char "$BOX_H" $cw2)${BOX_TM}$(repeat_char "$BOX_H" $cw3)${BOX_TR}${RESET}\n"
  printf "${BOLD}${BOX_V}${RESET} ${BOLD}%-$((cw1-2))s${RESET} ${BOLD}${BOX_V}${RESET} ${RED}%-$((cw2-2))s${RESET} ${BOLD}${BOX_V}${RESET} ${GREEN}%-$((cw3-2))s${RESET} ${BOLD}${BOX_V}${RESET}\n" \
    "Metric" "$label1" "$label2"
  printf "${BOLD}${BOX_ML}$(repeat_char "$BOX_H" $cw1)${BOX_X}$(repeat_char "$BOX_H" $cw2)${BOX_X}$(repeat_char "$BOX_H" $cw3)${BOX_MR}${RESET}\n"

  printf "${BOX_V} %-$((cw1-2))s ${BOX_V} %$((cw2-2))s ${BOX_V} %$((cw3-2))s ${BOX_V}\n" \
    "Files" "$(fmt_num "$LEFT_FILES_COUNT")" "$(fmt_num "$RIGHT_FILES_COUNT")"
  printf "${BOX_V} %-$((cw1-2))s ${BOX_V} %$((cw2-2))s ${BOX_V} %$((cw3-2))s ${BOX_V}\n" \
    "Directories" "$(fmt_num "$LEFT_DIRS_COUNT")" "$(fmt_num "$RIGHT_DIRS_COUNT")"
  printf "${BOX_V} %-$((cw1-2))s ${BOX_V} %$((cw2-2))s ${BOX_V} %$((cw3-2))s ${BOX_V}\n" \
    "Total Size" "$LEFT_SIZE_HUMAN" "$RIGHT_SIZE_HUMAN"
  printf "${BOX_V} %-$((cw1-2))s ${BOX_V} %$((cw2-2))s ${BOX_V} %$((cw3-2))s ${BOX_V}\n" \
    "Symlinks" "$(fmt_num "$LEFT_SYMLINKS_COUNT")" "$(fmt_num "$RIGHT_SYMLINKS_COUNT")"

  printf "${BOLD}${BOX_BL}$(repeat_char "$BOX_H" $cw1)${BOX_BM}$(repeat_char "$BOX_H" $cw2)${BOX_BM}$(repeat_char "$BOX_H" $cw3)${BOX_BR}${RESET}\n"
}

print_diff_summary() {
  local cnt_left=${#ONLY_LEFT[@]}
  local cnt_right=${#ONLY_RIGHT[@]}
  local cnt_differ=${#FILES_DIFFER[@]}
  local cnt_total=$((cnt_left + cnt_right + cnt_differ))
  local label1 label2
  label1="$(dir_label "$DIR1")"
  label2="$(dir_label "$DIR2")"

  printf "\n"
  print_rule "Difference Summary"
  printf "  ${YELLOW}Files that differ:${RESET}        %6s\n" "$(fmt_num "$cnt_differ")"
  printf "  ${RED}Only in ${label1}:${RESET}"
  local pad=$(( 30 - 10 - ${#label1} ))
  if [[ "$pad" -lt 1 ]]; then pad=1; fi
  printf "%${pad}s%6s\n" "" "$(fmt_num "$cnt_left")"
  printf "  ${GREEN}Only in ${label2}:${RESET}"
  pad=$(( 30 - 10 - ${#label2} ))
  if [[ "$pad" -lt 1 ]]; then pad=1; fi
  printf "%${pad}s%6s\n" "" "$(fmt_num "$cnt_right")"
  printf "  ${BOLD}Total differences:${RESET}        %6s\n" "$(fmt_num "$cnt_total")"
  print_rule ""

  if [[ "$cnt_total" -eq 0 ]]; then
    printf "\n  ${GREEN}${BOLD}✓ Directories are identical.${RESET}\n\n"
  fi
}

print_diff_list_section() {
  local label="$1" color="$2" symbol="$3" remaining="$4"
  shift 4
  local items=("$@")
  local count=${#items[@]}

  if [[ "$count" -eq 0 ]]; then return; fi

  printf "\n"
  print_rule "${label} (${count})"

  local shown=0
  local i
  for (( i=0; i<count; i++ )); do
    if [[ "$OPT_LIMIT" -ne 0 && "$remaining" -le 0 ]]; then
      break
    fi
    printf "  ${color}${symbol}${RESET} %s\n" "${items[$i]}"
    shown=$((shown + 1))
    remaining=$((remaining - 1))
  done

  local hidden=$((count - shown))
  if [[ "$hidden" -gt 0 ]]; then
    printf "  ${DIM}... and %d more (use --limit 0 for all)${RESET}\n" "$hidden"
  fi

  printf '%d' "$remaining" > /tmp/.dirdiff_remaining_$$
}

print_diff_list() {
  local cnt_left=${#ONLY_LEFT[@]}
  local cnt_right=${#ONLY_RIGHT[@]}
  local cnt_differ=${#FILES_DIFFER[@]}
  local total=$((cnt_left + cnt_right + cnt_differ))
  local label1 label2
  label1="$(dir_label "$DIR1")"
  label2="$(dir_label "$DIR2")"

  if [[ "$total" -eq 0 ]]; then return; fi

  local remaining="$OPT_LIMIT"
  if [[ "$OPT_LIMIT" -eq 0 ]]; then remaining=999999; fi

  if [[ "$cnt_left" -gt 0 ]]; then
    local formatted_left=()
    local i
    for (( i=0; i<cnt_left; i++ )); do
      formatted_left=("${formatted_left[@]}" "$(format_path "${ONLY_LEFT[$i]}" "$DIR1")")
    done
    print_diff_list_section "Only in ${label1}" "$RED" "✗" "$remaining" "${formatted_left[@]}"
    if [[ -f /tmp/.dirdiff_remaining_$$ ]]; then
      remaining=$(< /tmp/.dirdiff_remaining_$$)
      rm -f /tmp/.dirdiff_remaining_$$
    fi
  fi

  if [[ "$cnt_right" -gt 0 && "$remaining" -gt 0 ]]; then
    local formatted_right=()
    local i
    for (( i=0; i<cnt_right; i++ )); do
      formatted_right=("${formatted_right[@]}" "$(format_path "${ONLY_RIGHT[$i]}" "$DIR2")")
    done
    print_diff_list_section "Only in ${label2}" "$GREEN" "✚" "$remaining" "${formatted_right[@]}"
    if [[ -f /tmp/.dirdiff_remaining_$$ ]]; then
      remaining=$(< /tmp/.dirdiff_remaining_$$)
      rm -f /tmp/.dirdiff_remaining_$$
    fi
  fi

  if [[ "$cnt_differ" -gt 0 && "$remaining" -gt 0 ]]; then
    local formatted_differ=()
    local i
    for (( i=0; i<cnt_differ; i++ )); do
      formatted_differ=("${formatted_differ[@]}" "$(format_path "${FILES_DIFFER[$i]}" "$DIR1")")
    done
    print_diff_list_section "Files that differ" "$YELLOW" "≠" "$remaining" "${formatted_differ[@]}"
    rm -f /tmp/.dirdiff_remaining_$$
  fi
}

file_size_bytes() {
  local path="$1"
  if stat -f '%z' "$path" >/dev/null 2>&1; then
    stat -f '%z' "$path"
  else
    stat -c '%s' "$path"
  fi
}

print_size_diff() {
  if [[ "$OPT_SIZE_DIFF" != true ]]; then
    return
  fi

  if [[ ${#FILES_DIFFER[@]} -eq 0 && ${#ONLY_LEFT[@]} -eq 0 && ${#ONLY_RIGHT[@]} -eq 0 ]]; then return; fi

  printf "\n"
  print_rule "Size Differences"

  local i
  for (( i=0; i<${#FILES_DIFFER[@]}; i++ )); do
    local f="${FILES_DIFFER[$i]}"
    local s1 s2
    s1=$(du -h "${DIR1}/${f}" 2>/dev/null | cut -f1 | tr -d ' ')
    s2=$(du -h "${DIR2}/${f}" 2>/dev/null | cut -f1 | tr -d ' ')
    printf "  ${YELLOW}≠${RESET} %-40s  %6s  ->  %-6s\n" "$f" "$s1" "$s2"
  done

  for (( i=0; i<${#ONLY_LEFT[@]}; i++ )); do
    local f="${ONLY_LEFT[$i]}"
    local s1
    s1=$(du -h "${DIR1}/${f}" 2>/dev/null | cut -f1 | tr -d ' ')
    printf "  ${RED}✗${RESET} %-40s  %6s  ->  ${DIM}---${RESET}\n" "$f" "$s1"
  done

  for (( i=0; i<${#ONLY_RIGHT[@]}; i++ )); do
    local f="${ONLY_RIGHT[$i]}"
    local s2
    s2=$(du -h "${DIR2}/${f}" 2>/dev/null | cut -f1 | tr -d ' ')
    printf "  ${GREEN}✚${RESET} %-40s  ${DIM}---${RESET}    ->  %-6s\n" "$f" "$s2"
  done
}

extension_of() {
  local rel="$1"
  local base
  base="$(basename "$rel")"
  if [[ "$base" == *.* ]]; then
    printf '%s' "${base##*.}"
  else
    printf '%s' "(none)"
  fi
}

print_by_type() {
  if [[ "$OPT_BY_TYPE" != true ]]; then
    return
  fi

  printf "\n"
  print_rule "File Type Breakdown"

  local tmpfile
  tmpfile="$(mktemp)"
  {
    filtered_find "$DIR1" "f" | sed "s|^${DIR1}/||" | awk -F. '{if (NF>1) print "."$NF; else print "(no ext)"}' | sort | uniq -c | awk '{printf "LEFT\t%s\t%s\n", $2, $1}'
    filtered_find "$DIR2" "f" | sed "s|^${DIR2}/||" | awk -F. '{if (NF>1) print "."$NF; else print "(no ext)"}' | sort | uniq -c | awk '{printf "RIGHT\t%s\t%s\n", $2, $1}'
  } > "$tmpfile"

  printf "  ${BOLD}%-14s %8s %8s %8s${RESET}\n" "Extension" "$(dir_label "$DIR1")" "$(dir_label "$DIR2")" "Diff"
  printf "  ${DIM}%-14s %8s %8s %8s${RESET}\n" "──────────" "──────" "──────" "──────"

  local exts ext
  exts=$(awk -F'\t' '{print $2}' "$tmpfile" | sort -u)
  while IFS= read -r ext; do
    [[ -z "$ext" ]] && continue
    local cl cr
    cl=$(awk -F'\t' -v e="$ext" '$1=="LEFT" && $2==e {print $3}' "$tmpfile")
    cr=$(awk -F'\t' -v e="$ext" '$1=="RIGHT" && $2==e {print $3}' "$tmpfile")
    cl=${cl:-0}
    cr=${cr:-0}
    local d=$((cr - cl))
    local ds=""
    if [[ "$d" -gt 0 ]]; then ds="${GREEN}+${d}${RESET}"
    elif [[ "$d" -lt 0 ]]; then ds="${RED}${d}${RESET}"
    else ds="${DIM}0${RESET}"
    fi
    printf "  %-14s %8s %8s %8b\n" "$ext" "$cl" "$cr" "$ds"
  done <<< "$exts"

  rm -f "$tmpfile"
}

print_inline_diffs() {
  if [[ "$OPT_INLINE_DIFFS" != true ]]; then
    return
  fi

  if [[ ${#FILES_DIFFER[@]} -eq 0 ]]; then return; fi

  local preview_lines=10
  printf "\n"
  print_rule "Inline Diffs"

  local i
  for (( i=0; i<${#FILES_DIFFER[@]}; i++ )); do
    local f="${FILES_DIFFER[$i]}"
    printf "\n  ${YELLOW}≠${RESET} ${BOLD}%s${RESET}\n" "$f"

    if file "${DIR1}/${f}" 2>/dev/null | grep -q "binary\|executable\|data"; then
      printf "  ${BOX_TL}$(repeat_char "$BOX_H" 50)\n"
      printf "  ${BOX_V} ${DIM}Binary files differ${RESET}\n"
      printf "  ${BOX_BL}$(repeat_char "$BOX_H" 50)\n"
      continue
    fi

    local diff_content
    diff_content=$(diff -u "${DIR1}/${f}" "${DIR2}/${f}" 2>/dev/null | tail -n +3)
    local total_lines
    total_lines=$(printf '%s' "$diff_content" | wc -l | tr -d ' ')

    printf "  ${BOX_TL}$(repeat_char "$BOX_H" 50)\n"
    printf '%s\n' "$diff_content" | head -n "$preview_lines" | while IFS= read -r dline; do
      local first_char="${dline:0:1}"
      case "$first_char" in
        "+") printf "  ${BOX_V} ${GREEN}%s${RESET}\n" "$dline" ;;
        "-") printf "  ${BOX_V} ${RED}%s${RESET}\n" "$dline" ;;
        "@") printf "  ${BOX_V} ${CYAN}%s${RESET}\n" "$dline" ;;
        *)   printf "  ${BOX_V} %s\n" "$dline" ;;
      esac
    done

    local hidden=$((total_lines - preview_lines))
    if [[ "$hidden" -gt 0 ]]; then
      printf "  ${BOX_V} ${DIM}... (%d more lines)${RESET}\n" "$hidden"
    fi
    printf "  ${BOX_BL}$(repeat_char "$BOX_H" 50)\n"
  done
}

print_json() {
  if [[ "$OPT_JSON" != true ]]; then return; fi
  if [[ "$JQ_AVAILABLE" != true ]]; then
    err "The --json flag requires jq. Install jq to use this feature."
    exit 5
  fi

  local ol_json or_json fd_json ig_dirs ig_pats
  ol_json="$(jq -n '$ARGS.positional' --args "${ONLY_LEFT[@]}")"
  or_json="$(jq -n '$ARGS.positional' --args "${ONLY_RIGHT[@]}")"
  fd_json="$(jq -n '$ARGS.positional' --args "${FILES_DIFFER[@]}")"
  ig_dirs="$(jq -n '$ARGS.positional' --args "${IGNORE_DIRS[@]}")"
  ig_pats="$(jq -n '$ARGS.positional' --args "${IGNORE_PATTERNS[@]}")"

  jq -n \
    --arg left "$DIR1" \
    --arg left_label "$(dir_label "$DIR1")" \
    --arg right "$DIR2" \
    --arg right_label "$(dir_label "$DIR2")" \
    --arg timestamp "$(date '+%Y-%m-%dT%H:%M:%S')" \
    --arg config "$CONFIG_FILE" \
    --arg path_style "$PATH_STYLE" \
    --argjson excluded_dirs "$ig_dirs" \
    --argjson excluded_patterns "$ig_pats" \
    --argjson left_files "$LEFT_FILES_COUNT" \
    --argjson left_dirs "$LEFT_DIRS_COUNT" \
    --arg left_size "$LEFT_SIZE_HUMAN" \
    --argjson left_symlinks "$LEFT_SYMLINKS_COUNT" \
    --argjson right_files "$RIGHT_FILES_COUNT" \
    --argjson right_dirs "$RIGHT_DIRS_COUNT" \
    --arg right_size "$RIGHT_SIZE_HUMAN" \
    --argjson right_symlinks "$RIGHT_SYMLINKS_COUNT" \
    --argjson files_differ_count "${#FILES_DIFFER[@]}" \
    --argjson only_left_count "${#ONLY_LEFT[@]}" \
    --argjson only_right_count "${#ONLY_RIGHT[@]}" \
    --argjson total_count "$(( ${#FILES_DIFFER[@]} + ${#ONLY_LEFT[@]} + ${#ONLY_RIGHT[@]} ))" \
    --argjson only_left "$ol_json" \
    --argjson only_right "$or_json" \
    --argjson differ "$fd_json" \
    '{
      meta: {
        left: $left,
        left_label: $left_label,
        right: $right,
        right_label: $right_label,
        timestamp: $timestamp,
        config: $config,
        path_style: $path_style,
        excluded_dirs: $excluded_dirs,
        excluded_patterns: $excluded_patterns
      },
      stats: {
        left:  { files: $left_files, dirs: $left_dirs, size_human: $left_size, symlinks: $left_symlinks },
        right: { files: $right_files, dirs: $right_dirs, size_human: $right_size, symlinks: $right_symlinks }
      },
      summary: {
        files_differ: $files_differ_count,
        only_in_left: $only_left_count,
        only_in_right: $only_right_count,
        total: $total_count
      },
      differences: {
        only_left: $only_left,
        only_right: $only_right,
        differ: $differ
      }
    }'
}

main() {
  parse_args "$@"
  setup_colors
  check_dependencies

  if [[ "$OPT_INIT" == true ]]; then
    ensure_config
    exit 0
  fi

  if [[ "$OPT_RESET_CONFIG" == true ]]; then
    reset_config
    exit 0
  fi

  if [[ -z "$DIR1" || -z "$DIR2" ]]; then
    show_help
    exit 2
  fi

  if [[ ! -e "$DIR1" ]]; then
    err "Directory not found: ${DIR1}"
    exit 2
  fi
  if [[ ! -e "$DIR2" ]]; then
    err "Directory not found: ${DIR2}"
    exit 2
  fi
  if [[ ! -d "$DIR1" ]]; then
    err "Not a directory: ${DIR1}"
    exit 2
  fi
  if [[ ! -d "$DIR2" ]]; then
    err "Not a directory: ${DIR2}"
    exit 2
  fi

  ensure_config
  if ! parse_config; then
    exit 3
  fi
  build_exclusions
  gather_stats

  if [[ "$OPT_JSON" == true ]]; then
    print_json
  else
    print_header
    print_stats_table
    print_diff_summary
    print_diff_list
    print_size_diff
    print_by_type
    print_inline_diffs
    printf "\n"
  fi

  local total=$(( ${#FILES_DIFFER[@]} + ${#ONLY_LEFT[@]} + ${#ONLY_RIGHT[@]} ))
  if [[ "$total" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
