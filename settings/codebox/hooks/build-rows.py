#!/usr/bin/env python3
"""build-rows.py -- write codebox's hook rows into settings/codebox/claude-settings.json.

Gavin, dotfiles-main Q50: 1, 23 Oct 2026. The rows come from hooks.json beside this file and
run the copies the codebox profile places in ~/.claude/hooks/codebox/. Each command is the same
fail-closed wrapper makeitso's hooks/install.py writes: a guard whose script is missing or
crashes DENIES the call; an advisory or alarm says so and lets the call go ahead.

The "hooks" key of the settings source is replaced whole: codebox's hooks are all here.

    uv run python3 settings/codebox/hooks/build-rows.py           # write
    uv run python3 settings/codebox/hooks/build-rows.py --check   # exit 1 when the source differs
"""
import json
import sys
from pathlib import Path

HOOKS = Path(__file__).resolve().parent
SOURCE = HOOKS.parent / "claude-settings.json"
LIVE_REL = ".claude/hooks/codebox/"
FIX = ("Fix it: restore settings/codebox/hooks in fifty-shades-of-dotfiles and run "
       "./install.sh --profile codebox on codebox, which copies the hooks into place ({p}).")


def sq(s):
    """A single-quoted shell word holding s (no single quote may appear in s)."""
    assert "'" not in s, s
    return "'" + s + "'"


def command(row):
    rel = "$HOME/" + LIVE_REL + row["script"]
    shown = "~/" + LIVE_REL + row["script"]
    fix = FIX.format(p=shown)
    if row["class"] == "guard":
        crashed = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": "HOOK CRASHED, DENYING: " + row["script"] + " exited RCMARK, which is neither 0 "
            "(allow, or its own deny) nor 2 (block), so every call it guards is denied until that is fixed. " + fix}})
        a, b = crashed.split("RCMARK")
        missing = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": "HOOK MISSING, DENYING: " + row["script"] + " is registered but " + shown +
            " is missing or not executable, so every call it guards is denied until that is fixed. " + fix}})
        return (f'h="{rel}"; if [ ! -x "$h" ]; then sleep 0.005; fi; if [ -x "$h" ]; then o=$("$h"); r=$?; '
                f'case $r in 0|2) if [ -n "$o" ]; then printf \'%s\\n\' "$o"; fi; exit $r;; esac; '
                f"printf '%s\\n' {sq(a)}\"$r\"{sq(b)}; else printf '%s\\n' {sq(missing)}; fi")
    text = "HOOK MISSING: " + row["script"] + " is registered but " + shown + " is missing or not executable, so it did not run. " + fix
    missing = json.dumps({"systemMessage": text, "hookSpecificOutput": {"hookEventName": row["event"], "additionalContext": text}})
    run = '"$h" || true' if row["class"] == "alarm" else '"$h"'
    return f'h="{rel}"; if [ -x "$h" ]; then {run}; else printf \'%s\\n\' {sq(missing)}; fi'


def rows_block():
    rows = json.loads((HOOKS / "hooks.json").read_text())["hooks"]
    out = {}
    for r in rows:
        if not (HOOKS / r["script"]).is_file():
            sys.exit(f"build-rows: {r['script']} is listed but not in {HOOKS}")
        group = {"hooks": [{"type": "command", "command": command(r), "timeout": r["timeout"]}]}
        if r.get("matcher"):
            group = {"matcher": r["matcher"], **group}
        out.setdefault(r["event"], []).append(group)
    return out, len(rows)


def main():
    cur = json.loads(SOURCE.read_text())
    block, n = rows_block()
    new = {**cur, "hooks": block}
    if "--check" in sys.argv:
        same = cur == new
        print(f"build-rows: {SOURCE.name} " + ("matches hooks.json" if same else "differs from hooks.json; run build-rows.py"))
        sys.exit(0 if same else 1)
    SOURCE.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
    print(f"build-rows: wrote {n} rows into {SOURCE.name}")


main()
