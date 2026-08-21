#!/bin/bash
#
# Capture THIS Mac's full iTerm2 preferences (every profile, color scheme,
# key binding, pointer/ctrl-click binding, Hotkey Window, general prefs --
# the whole com.googlecode.iterm2 domain) and write a sanitized, portable
# copy into this directory. Never run automatically -- this is a deliberate,
# dev-machine-only snapshot step; sanitize_plist.py refuses to write if it
# finds anything that still looks machine-specific or secret.
#
# Adapted from steveli2026/iterm2-settings (MIT License). See LICENSE here.
#
# Usage:
#   ./export.sh
#   git diff -- settings/iterm2/prefs/com.googlecode.iterm2.plist
#   git add settings/iterm2/prefs/com.googlecode.iterm2.plist
#   git commit -m "..." && git push

set -euo pipefail

DOMAIN="com.googlecode.iterm2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${SCRIPT_DIR}/${DOMAIN}.plist"
SANITIZER="${SCRIPT_DIR}/sanitize_plist.py"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: this exporter only supports macOS." >&2
    exit 1
fi

for command_name in defaults plutil uv mktemp pgrep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: required command not found: ${command_name}" >&2
        exit 1
    fi
done

if [[ ! -f "$SANITIZER" ]]; then
    echo "Error: sanitizer not found: ${SANITIZER}" >&2
    exit 1
fi

if pgrep -x iTerm2 >/dev/null 2>&1; then
    echo "Note: iTerm2 is running; preferences currently registered with macOS will be exported."
fi

TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_PLIST="$(mktemp "${TEMP_ROOT%/}/iterm2-prefs-export.XXXXXX")"

cleanup() {
    if [[ -n "${TEMP_PLIST:-}" && -f "$TEMP_PLIST" ]]; then
        case "$TEMP_PLIST" in
            "${TEMP_ROOT%/}"/iterm2-prefs-export.*)
                rm -f -- "$TEMP_PLIST"
                ;;
            *)
                echo "Warning: refusing to clean unexpected temp path: ${TEMP_PLIST}" >&2
                ;;
        esac
    fi
}
trap cleanup EXIT

defaults export "$DOMAIN" "$TEMP_PLIST" >/dev/null
"$SANITIZER" "$TEMP_PLIST" "$DESTINATION"
plutil -lint "$DESTINATION" >/dev/null

echo "Exported sanitized iTerm2 preferences to: ${DESTINATION}"
echo "Review before publishing: git diff -- settings/iterm2/prefs/${DOMAIN}.plist"
