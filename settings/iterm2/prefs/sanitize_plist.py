#!/usr/bin/env -S uv run python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
#
# ==============================================================================
#  sanitize_plist -- make an exported iTerm2 preferences plist public-safe
# ==============================================================================
#
# Adapted from steveli2026/iterm2-settings (MIT License, Copyright (c) 2026
# Steve Li) -- https://github.com/steveli2026/iterm2-settings. See LICENSE in
# this directory for the original notice.
#
# WHY
# ---
# iTerm2 keeps EVERY setting -- profiles, colors, fonts, key bindings, pointer
# bindings, the Hotkey Window, general prefs -- in one macOS preferences
# domain (com.googlecode.iterm2). export.sh dumps that whole domain; this
# script is the gate between that dump and a PUBLIC repo. It strips volatile,
# machine-specific noise, normalizes the current $HOME to `~`, then audits
# the result for anything that still looks like a secret or an identity --
# and REFUSES TO WRITE if it finds one. Same posture as this repo's
# git-leak-scan pre-commit hook: prefer a false positive over a miss.
#
# EXIT CODES
#   0  wrote a sanitized plist, nothing suspicious found
#   1  read/write error, or the audit found something -- destination untouched
# ==============================================================================

from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys
from pathlib import Path
from typing import Any

DOMAIN = "com.googlecode.iterm2"

DROP_EXACT = {
    "NSSplitView Subview Frames NSColorPanelSplitView",
    "NSToolbar Configuration com.apple.NSColorPanel",
    "LoadPrefsFromCustomFolder",
    "PrefsCustomFolder",
    "iTerm Version",
}

DROP_PREFIXES = (
    "NoSync",
    "NSWindow Frame ",
    "SU",
)

SECRET_PATTERNS = (
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b")),
    ("URL containing credentials", re.compile(r"[a-z][a-z0-9+.-]*://[^\s/:]+:[^\s/@]+@", re.I)),
    (
        "email or user@host identity",
        re.compile(r"(?<![\w.+-])[\w.+-]+@[A-Za-z0-9][A-Za-z0-9.-]*(?![\w.-])"),
    ),
)

SENSITIVE_KEY = re.compile(
    r"(?:password|passwd|secret|credential|api[ _-]?key|access[ _-]?token|auth[ _-]?token)",
    re.I,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    return parser.parse_args()


def make_portable(value: Any, home: str, stats: dict[str, int]) -> Any:
    if isinstance(value, dict):
        result: dict[Any, Any] = {}
        for key, child in value.items():
            if isinstance(key, str) and (
                key in DROP_EXACT or any(key.startswith(prefix) for prefix in DROP_PREFIXES)
            ):
                stats["removed"] += 1
                continue
            result[key] = make_portable(child, home, stats)
        return result

    if isinstance(value, list):
        return [make_portable(child, home, stats) for child in value]

    if isinstance(value, str) and home and home in value:
        stats["normalized"] += 1
        return value.replace(home, "~")

    return value


def audit(value: Any, home: str) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []

    def walk(child: Any, path: str, key_name: str | None = None) -> None:
        if isinstance(child, dict):
            for key, nested in child.items():
                nested_path = f"{path}.{key}"
                walk(nested, nested_path, str(key))
            return

        if isinstance(child, list):
            for index, nested in enumerate(child):
                walk(nested, f"{path}[{index}]", key_name)
            return

        if isinstance(child, bytes):
            text = child.decode("latin-1", errors="ignore")
        elif isinstance(child, str):
            text = child
        else:
            return

        if home and home in text:
            findings.append((path, "absolute Home directory remains"))

        if key_name and SENSITIVE_KEY.search(key_name) and text.strip():
            findings.append((path, "non-empty value under a credential-like key"))

        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                findings.append((path, label))

    walk(value, "$")
    return findings


def main() -> int:
    args = parse_args()
    try:
        with args.source.open("rb") as source_file:
            raw = plistlib.load(source_file)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f"Error: could not read source plist: {error}", file=sys.stderr)
        return 1

    if not isinstance(raw, dict):
        print(f"Error: {DOMAIN} preferences must be a dictionary plist.", file=sys.stderr)
        return 1

    home = os.path.expanduser("~").rstrip("/")
    stats = {"removed": 0, "normalized": 0}
    sanitized = make_portable(raw, home, stats)
    findings = audit(sanitized, home)

    if findings:
        print("Error: refusing to write a public settings file; review these fields:", file=sys.stderr)
        for path, label in findings:
            print(f"  - {path}: {label}", file=sys.stderr)
        return 1

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with args.destination.open("wb") as destination_file:
            plistlib.dump(sanitized, destination_file, fmt=plistlib.FMT_XML, sort_keys=True)
    except OSError as error:
        print(f"Error: could not write destination plist: {error}", file=sys.stderr)
        return 1

    print(
        f"Sanitized plist: removed {stats['removed']} volatile fields; "
        f"normalized {stats['normalized']} Home path values."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
