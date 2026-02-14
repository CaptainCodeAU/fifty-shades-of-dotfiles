#!/bin/bash
# Export the current session transcript on session end

# Skip if SKIP_SESSION_END_HOOK is set
[ "$SKIP_SESSION_END_HOOK" = "1" ] && exit 0

# Read JSON from stdin and extract transcript_path
TRANSCRIPT_PATH=$(uv run python -c "import sys, json; print(json.load(sys.stdin).get('transcript_path', ''))" 2>/dev/null) || exit 0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    claude-code-transcripts json "$TRANSCRIPT_PATH" -o ~/CODE/claude-code-transcripts -a --json || true
fi

exit 0
