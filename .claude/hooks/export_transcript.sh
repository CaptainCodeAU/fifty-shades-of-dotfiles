#!/bin/bash
# Export the current session transcript on session end

# Skip if SKIP_SESSION_END_HOOK is set
[ "$SKIP_SESSION_END_HOOK" = "1" ] && exit 0

# Read JSON from stdin and extract transcript_path
TRANSCRIPT_PATH=$(uv run python -c "import sys, json; print(json.load(sys.stdin).get('transcript_path', ''))" 2>/dev/null) || exit 0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    OUT_DIR=~/CODE/claude-code-transcripts
    MARK=$(mktemp)
    claude-code-transcripts json "$TRANSCRIPT_PATH" -o "$OUT_DIR" -a --json || true
    # Defense-in-depth: redact GitHub token patterns from files written this run.
    # (The read-only token shouldn't be writable to GitHub, but never persist it.)
    # NOTE: this only scrubs files WE generate here; Claude Code's own raw
    # ~/.claude/projects/.../*.jsonl logs are written by the harness, out of scope.
    find "$OUT_DIR" -type f -newer "$MARK" \( -name '*.md' -o -name '*.json' \) -print0 2>/dev/null \
      | xargs -0 sed -i '' -E 's/(github_pat_|gh[posru]_)[A-Za-z0-9_]+/\1[REDACTED]/g' 2>/dev/null || true
    rm -f "$MARK"
fi

exit 0
