#!/usr/bin/env bash
# Stop hook (read-only): is a peer session's message still unanswered?
#
# WHY IT EXISTS
#   OPERATIONAL_RULES already says to close the loop with a peer agent
#   unprompted, twice, in two different sections. On 2026-09-17 Gavin still had
#   to ask "do you need to communicate it to them?" more than once in a single
#   session. A rule that has to be remembered is not a mechanism, and that same
#   file already names this exact fallback: "a PostToolUse hook nudge on
#   Agent/SendMessage dispatch (agreed 2026-09-13, deliberately not built yet)."
#   This is that nudge, on Stop rather than PostToolUse, because the question is
#   not "did you dispatch" but "are you ending a turn owing someone a reply".
#
#   The failure it catches is the absence-that-lies shape again: from in here, a
#   peer waiting on an answer looks exactly like a peer who needs nothing.
#
# HOW
#   Compares two POSITIONS in the transcript: the last inbound cross-session
#   message, and the last SendMessage this session made. Inbound later means a
#   reply is owed. Position only -- it never parses what anyone said and never
#   judges whether a reply was adequate.
#
# GUARANTEES: read-only, never blocks, always exits 0, silent when nothing owed.
set -uo pipefail

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

uv run python3 - "$TRANSCRIPT" <<'PY'
import json, sys, pathlib

last_inbound = -1
last_sent = -1

try:
    lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
except OSError:
    sys.exit(0)

# ROLE MATTERS, and a substring test alone gets this WRONG. Measured while
# building this hook: a plain text search fired on the live transcript even
# though the reply had been sent, because the line that mentioned
# "cross-session-message" was the ASSISTANT writing this very script. A check
# that matches its own source is not a check. So an inbound message only counts
# when it arrives in a USER-role message, and a send only counts when it is an
# assistant tool_use named SendMessage.
for i, line in enumerate(lines):
    if "SendMessage" not in line and "cross-session-message" not in line:
        continue                      # cheap skip: most lines are neither
    try:
        rec = json.loads(line)
    except Exception:
        continue
    role = (rec.get("message") or {}).get("role") or rec.get("role") or ""
    blob = json.dumps(rec.get("message") or rec)
    if role == "user" and "<cross-session-message" in blob:
        last_inbound = i
    if role == "assistant" and '"name": "SendMessage"' in blob.replace('"name":"SendMessage"', '"name": "SendMessage"'):
        last_sent = i

if last_inbound > last_sent:
    print("PEER REPLY OWED (Stop hook, read-only)")
    print("   A peer session's message arrived after your last SendMessage, and this turn is ending.")
    print("   OPERATIONAL_RULES: close the loop unprompted -- what landed, what you verified,")
    print("   where you disagreed, and that nothing further is owed. Even if they said none was needed.")
    print("   If a reply genuinely is not due yet, say that out loud rather than letting it lapse.")
PY
exit 0
