#!/usr/bin/env bash

set -euo pipefail

DEFAULT_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
APP_STATE_DIR="$DEFAULT_STATE_HOME/fifty-shades-of-dotfiles"

db_path="${WATCH_HISTORY_DB_PATH:-$APP_STATE_DIR/watch_history.db}"
playlist_items="${PLAYLIST_ITEMS:-1:20}"
cookies_browser="${WATCH_HISTORY_COOKIES_BROWSER:-brave}"
keep_log=false
log_path=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

usage() {
  cat <<EOF
watch-history-sync - Export YouTube watch history to SQLite

Usage:
  watch-history-sync [options]

Options:
  --db-path <path>             Override destination SQLite file.
  --playlist-items <range>     yt-dlp playlist item range (default: ${playlist_items}).
                               Use empty string to fetch full history.
  --cookies-from-browser <id>  Browser profile for yt-dlp cookies (default: ${cookies_browser}).
  --keep-log                   Keep generated yt-dlp stderr log and print its path.
  --log-path <path>            Write yt-dlp stderr to this file (always retained).
  -h, --help                   Show this help.

Environment:
  WATCH_HISTORY_DB_PATH        Default DB path override.
  WATCH_HISTORY_COOKIES_BROWSER
                               Default browser name for yt-dlp cookies.
  PLAYLIST_ITEMS               Default playlist range override.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --db-path" >&2; exit 1; }
      db_path="$2"
      shift 2
      ;;
    --playlist-items)
      [[ $# -ge 2 ]] || { echo "Missing value for --playlist-items" >&2; exit 1; }
      playlist_items="$2"
      shift 2
      ;;
    --cookies-from-browser)
      [[ $# -ge 2 ]] || { echo "Missing value for --cookies-from-browser" >&2; exit 1; }
      cookies_browser="$2"
      shift 2
      ;;
    --keep-log)
      keep_log=true
      shift
      ;;
    --log-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --log-path" >&2; exit 1; }
      log_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cleanup_log=true
if [[ -n "$log_path" ]]; then
  mkdir -p "$(dirname "$log_path")"
  ytdlp_stderr_log="$log_path"
  : > "$ytdlp_stderr_log"
  cleanup_log=false
else
  ytdlp_stderr_log="$(mktemp "${TMPDIR:-/tmp}/watch-history-sync.ytdlp.XXXXXX.log")"
  if [[ "$keep_log" == true ]]; then
    cleanup_log=false
  fi
fi

if [[ "$cleanup_log" == true ]]; then
  trap 'rm -f "$ytdlp_stderr_log"' EXIT
fi

mkdir -p "$(dirname "$db_path")"

echo ""
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}         YouTube Watch History -> SQLite Exporter            ${RESET}"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""

missing=0
for cmd in yt-dlp uv sqlite3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  ${RED}[x]${RESET} ${BOLD}$cmd${RESET} not found. Please install it first."
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo ""
  echo -e "  ${RED}Aborting due to missing dependencies.${RESET}"
  echo ""
  exit 1
fi

echo -e "  ${GREEN}[ok]${RESET} All dependencies found"
echo -e "  ${DIM}Database:${RESET} ${BOLD}$db_path${RESET}"
echo -e "  ${DIM}Items:${RESET}    ${BOLD}${playlist_items:-all}${RESET}"
echo -e "  ${DIM}Browser:${RESET}  ${BOLD}$cookies_browser${RESET}"
echo ""
echo -e "${BOLD}${BLUE}> Fetching watch history...${RESET}"
echo ""

read -r -d '' PYTHON_INGEST <<'PY' || true
import json
import os
import sqlite3
import sys

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

db_path = os.environ["DB_PATH"]

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
except Exception as exc:
    print(f"  {RED}[x] Failed to open database: {exc}{RESET}", file=sys.stderr)
    sys.exit(1)

cur.execute(
    """
CREATE TABLE IF NOT EXISTS watch_history (
    id                    TEXT PRIMARY KEY,
    title                 TEXT,
    fulltitle             TEXT,
    description           TEXT,
    upload_date           TEXT,
    timestamp             INTEGER,
    duration              REAL,
    duration_string       TEXT,
    media_type            TEXT,
    categories            TEXT,
    tags                  TEXT,
    language              TEXT,
    age_limit             INTEGER,
    availability          TEXT,
    playable_in_embed     INTEGER,
    url                   TEXT,
    webpage_url           TEXT,
    original_url          TEXT,
    channel               TEXT,
    channel_id            TEXT,
    channel_url           TEXT,
    channel_follower_count INTEGER,
    channel_is_verified   INTEGER,
    uploader              TEXT,
    uploader_id           TEXT,
    uploader_url          TEXT,
    view_count            INTEGER,
    like_count            INTEGER,
    comment_count         INTEGER,
    is_live               INTEGER,
    was_live              INTEGER,
    live_status           TEXT,
    ext                   TEXT,
    format                TEXT,
    format_id             TEXT,
    format_note           TEXT,
    resolution            TEXT,
    width                 INTEGER,
    height                INTEGER,
    aspect_ratio          REAL,
    fps                   REAL,
    dynamic_range         TEXT,
    vcodec                TEXT,
    acodec                TEXT,
    vbr                   REAL,
    abr                   REAL,
    asr                   INTEGER,
    audio_channels        INTEGER,
    filesize_approx       INTEGER,
    protocol              TEXT,
    thumbnail             TEXT,
    playlist_index        INTEGER,
    playlist_autonumber   INTEGER,
    epoch                 INTEGER,
    fetched_at            TEXT DEFAULT (datetime('now'))
)
"""
)

def get(item, key, default=None):
    value = item.get(key, default)
    return default if value is None else value

def get_bool(item, key):
    value = item.get(key)
    if value is None:
        return None
    return 1 if value else 0

def get_json_list(item, key):
    value = item.get(key)
    if value is None:
        return None
    return json.dumps(value)

count = 0
errors = 0

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    try:
        item = json.loads(line)
    except json.JSONDecodeError as exc:
        errors += 1
        print(f"  {YELLOW}[!] Skipped malformed JSON entry: {exc}{RESET}")
        continue

    vid = get(item, "id", "unknown")
    title = get(item, "title", "Unknown")

    try:
        cur.execute(
            """
            INSERT OR REPLACE INTO watch_history (
                id, title, fulltitle, description, upload_date, timestamp,
                duration, duration_string, media_type, categories, tags,
                language, age_limit, availability, playable_in_embed,
                url, webpage_url, original_url,
                channel, channel_id, channel_url, channel_follower_count,
                channel_is_verified, uploader, uploader_id, uploader_url,
                view_count, like_count, comment_count,
                is_live, was_live, live_status,
                ext, format, format_id, format_note, resolution,
                width, height, aspect_ratio, fps, dynamic_range,
                vcodec, acodec, vbr, abr, asr, audio_channels,
                filesize_approx, protocol,
                thumbnail, playlist_index, playlist_autonumber, epoch
            ) VALUES (
                ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?,
                ?, ?,
                ?, ?, ?, ?
            )
            """,
            (
                get(item, "id"),
                get(item, "title"),
                get(item, "fulltitle"),
                get(item, "description"),
                get(item, "upload_date"),
                get(item, "timestamp"),
                get(item, "duration"),
                get(item, "duration_string"),
                get(item, "media_type"),
                get_json_list(item, "categories"),
                get_json_list(item, "tags"),
                get(item, "language"),
                get(item, "age_limit"),
                get(item, "availability"),
                get_bool(item, "playable_in_embed"),
                get(item, "url"),
                get(item, "webpage_url"),
                get(item, "original_url"),
                get(item, "channel"),
                get(item, "channel_id"),
                get(item, "channel_url"),
                get(item, "channel_follower_count"),
                get_bool(item, "channel_is_verified"),
                get(item, "uploader"),
                get(item, "uploader_id"),
                get(item, "uploader_url"),
                get(item, "view_count"),
                get(item, "like_count"),
                get(item, "comment_count"),
                get_bool(item, "is_live"),
                get_bool(item, "was_live"),
                get(item, "live_status"),
                get(item, "ext"),
                get(item, "format"),
                get(item, "format_id"),
                get(item, "format_note"),
                get(item, "resolution"),
                get(item, "width"),
                get(item, "height"),
                get(item, "aspect_ratio"),
                get(item, "fps"),
                get(item, "dynamic_range"),
                get(item, "vcodec"),
                get(item, "acodec"),
                get(item, "vbr"),
                get(item, "abr"),
                get(item, "asr"),
                get(item, "audio_channels"),
                get(item, "filesize_approx"),
                get(item, "protocol"),
                get(item, "thumbnail"),
                get(item, "playlist_index"),
                get(item, "playlist_autonumber"),
                get(item, "epoch"),
            ),
        )
        count += 1
        channel = get(item, "channel", "")
        duration = get(item, "duration_string", "?")
        print(f"  {GREEN}[ok]{RESET} {DIM}[{count}]{RESET} {BOLD}{title}{RESET}")
        print(f"    {DIM}{channel} | {duration} | {get(item, 'view_count', 0):,} views{RESET}")
    except sqlite3.Error as exc:
        errors += 1
        print(f'  {RED}[x] DB error for "{title}" ({vid}): {exc}{RESET}')

conn.commit()
conn.close()

print("")
print(f"  {BOLD}------------------------------------{RESET}")
print(f"  {GREEN}Inserted:{RESET} {BOLD}{count}{RESET} entries")
if errors > 0:
    print(f"  {YELLOW}Skipped:{RESET}  {BOLD}{errors}{RESET} errors")
print(f"  {BOLD}------------------------------------{RESET}")
PY

yt_dlp_cmd=(yt-dlp --cookies-from-browser "$cookies_browser" --dump-json --skip-download)
if [[ -n "$playlist_items" ]]; then
  yt_dlp_cmd+=(--playlist-items "$playlist_items")
fi
yt_dlp_cmd+=("https://www.youtube.com/feed/history")

set +e
"${yt_dlp_cmd[@]}" 2>"$ytdlp_stderr_log" | DB_PATH="$db_path" uv run python3 -c "$PYTHON_INGEST"
pipeline_exit=$?
set -e

echo ""

if [[ -s "$ytdlp_stderr_log" ]]; then
  if rg -qi "error|unable|failed|warning" "$ytdlp_stderr_log"; then
    echo -e "  ${YELLOW}[!] yt-dlp messages:${RESET}"
    while IFS= read -r errline; do
      echo -e "    ${DIM}$errline${RESET}"
    done < <(awk 'NR<=8 { print }' "$ytdlp_stderr_log")
    echo ""
  fi
fi

if [[ "$pipeline_exit" -ne 0 ]]; then
  echo -e "  ${RED}[x] Script failed. Check the errors above.${RESET}"
  if [[ "$cleanup_log" == false ]]; then
    echo -e "  ${DIM}yt-dlp log: $ytdlp_stderr_log${RESET}"
  fi
  echo ""
  exit 1
fi

echo -e "${BOLD}${BLUE}> Verifying database...${RESET}"
echo ""

set +e
row_count="$(sqlite3 "$db_path" "SELECT count(*) FROM watch_history;" 2>/dev/null)"
sqlite_rc=$?
set -e

if [[ "$sqlite_rc" -ne 0 || -z "$row_count" ]]; then
  echo -e "  ${RED}[x] Could not read database at ${db_path}${RESET}"
  echo ""
  exit 1
fi

echo -e "  ${GREEN}[ok]${RESET} ${BOLD}${row_count}${RESET} rows in ${BOLD}watch_history${RESET}"
echo ""

sqlite3 -header -column "$db_path" \
  "SELECT id, substr(title,1,35) AS title, substr(channel,1,20) AS channel, upload_date, view_count, media_type FROM watch_history LIMIT 5;"
echo ""

db_size="$(du -h "$db_path" | awk '{print $1}')"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}  ${GREEN}[ok] Done!${RESET}                                             ${BOLD}${CYAN}${RESET}"
echo -e "${BOLD}${CYAN}  ${DIM}Database:${RESET} ${BOLD}${db_path}${RESET} (${db_size})"
if [[ "$cleanup_log" == false ]]; then
  echo -e "${BOLD}${CYAN}  ${DIM}yt-dlp log:${RESET} ${BOLD}${ytdlp_stderr_log}${RESET}"
fi
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""
