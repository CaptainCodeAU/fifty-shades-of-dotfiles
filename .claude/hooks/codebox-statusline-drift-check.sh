#!/usr/bin/env bash
# SessionStart hook (read-only): has the Mac's status line moved on from codebox's copy?
# The tool is home/.local/bin/codebox-statusline-drift; this only calls it and never blocks.
set -uo pipefail
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TOOL=""
for cand in "$HOME/.local/bin/codebox-statusline-drift" \
            "$PROJECT_DIR/home/.local/bin/codebox-statusline-drift"; do
  [ -x "$cand" ] && { TOOL="$cand"; break; }
done
[ -z "$TOOL" ] && { echo "📊 codebox status line: drift tool not found, skipped."; exit 0; }
out=$(timeout 10 "$TOOL" 2>&1); rc=$?
case "$rc" in
  0) echo "📊 $out" ;;
  *) echo "📊 $out"
     echo "    Assistant: codebox runs a copy of the Mac's status line. Run"
     echo "    codebox-statusline-drift --sync, commit and push, then tell Network_Plan-main." ;;
esac
exit 0
