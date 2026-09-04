#!/usr/bin/env python3
"""census — count tokens across a project's files, and REFUSE to answer without a control.

MACHINE-GLOBAL COPY. Deployed by stow to ~/.claude/tools/census.py, which is a SYMLINK
back to this file, so the live copy and the master are the same bytes by construction.

⚠️ THIS IS NOT THE ESTATE COPY. A separate, byte-pinned census.py is published inside
   DIB/governor and held verbatim across that estate by its own readiness rule. The two
   are different artifacts with different jobs: that one is governed and pinned, this one
   is a machine utility that must run in any project on this box, git or not.
   DO NOT byte-compare them and DO NOT "reconcile" one to the other.

WHY IT EXISTS — measured, not felt
    In one working sitting, five ad-hoc censuses produced wrong answers while every
    purpose-built tool in the tree was right every time. Three of the five were one
    defect: A NEGATIVE RESULT REPORTED WITHOUT PROVING THE INSTRUMENT COULD PRODUCE A
    POSITIVE ONE.

      · a census printed only its top rows, so the control it had declared scrolled
        off and was never checked
      · an unquoted shell variable made grep read nine paths as ONE filename; it
        returned 0, and that 0 was one sentence from being reported as "none anywhere"
      · a search for a page footer returned nothing, then errored on regex complexity,
        while the footer was present the whole time

    ⇒ THE RULE THIS TOOL MAKES STRUCTURAL: no count leaves here unless a control
      pattern — one known to be present — hits first. If it does not, the result is an
      error and NO NUMBERS, because a number that cannot be trusted is worse than no
      number at all.

WHAT IT FIXES, BY CLASS
    A · the unenforced control  → --control is REQUIRED and asserted before output
    C · shell word-splitting    → the file set comes from `git ls-files` (or an explicit
                                  walk), never from a shell variable that can silently
                                  collapse into one argument; patterns arrive as argv,
                                  unexpanded
    · the missing denominator   → the file count is always printed, so a count is never
                                  quoted without the population it was drawn from
    · silent truncation         → nothing is ever headed or tailed
    · an unstated population    → the MODE is printed every run. `git` is complete by
                                  construction; `walk` is not, and says so.

WHAT IT DOES NOT FIX
    It cannot tell you a hit is a DEFECT. Triage is a human reading, always. A real run
    once produced six hits for a retired name and all six were legitimate.

Usage
    uv run python3 ~/.claude/tools/census.py --control <token-known-present> PATTERN...

    --control TOKEN     required. A token you KNOW is present. Zero hits ⇒ exit 2.
    --root PATH         project root to census (default: current directory).
    --under PREFIX      restrict to files under this path, relative to root (repeatable).
    --exclude PREFIX    drop files under this path (repeatable) — PRINTED, so the
                        exclusion is always visible rather than silent.
    --regex             treat patterns as regular expressions instead of literals.
    --case-sensitive    default is case-insensitive.
    --walk              force the filesystem walk even inside a git repo.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

RED, YELLOW, GREEN, DIM, OFF = "\033[1;31m", "\033[0;33m", "\033[0;32m", "\033[2m", "\033[0m"

# Directories the walk never descends into. Printed on every walk run, because a
# population trimmed by a list nobody can see is exactly the defect this tool exists
# to remove.
SKIP_DIRS = {
    ".git", ".hg", ".svn", "node_modules", "__pycache__", ".venv", "venv",
    ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox", ".next", ".nuxt",
    "dist", "build", "target", ".gradle", ".idea", ".DS_Store",
}


def git_files(root):
    """Tracked files, complete by construction. Returns None if this is not a git repo."""
    r = subprocess.run(
        ["git", "-C", str(root), "ls-files"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return None
    return [f for f in r.stdout.split("\n") if f.strip()]


def walked_files(root):
    """Every readable file under root, minus SKIP_DIRS. NOT complete by construction."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name in SKIP_DIRS:
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            out.append(rel)
    return sorted(out)


def collect(root, unders, excludes, force_walk):
    """Return (files, mode). mode is 'git' or 'walk' and is always reported."""
    files = None if force_walk else git_files(root)
    mode = "git"
    if files is None:
        files = walked_files(root)
        mode = "walk"
    if unders:
        files = [f for f in files if f.startswith(tuple(unders))]
    if excludes:
        files = [f for f in files if not f.startswith(tuple(excludes))]
    return files, mode


# Metacharacters whose presence in a LITERAL pattern almost always means the caller
# meant regex. `.` and `-` are deliberately absent: they appear in ordinary literal
# searches (`foo.md`, `safe-rm`) and escaping them changes nothing a human cares about,
# so including them would fire the notice on nearly every run — and a notice that always
# fires is a notice nobody reads.
REGEX_METACHARS = set("\\|()[]{}*+?^$")


def looks_like_regex(pattern):
    """True when a literal pattern carries syntax that only means something in regex mode."""
    return any(c in REGEX_METACHARS for c in pattern)


def effective(pattern, use_regex):
    """The expression actually compiled. Printed whenever it is not what was typed."""
    return pattern if use_regex else re.escape(pattern)


def matching_mode(use_regex, case_sensitive):
    """The two silent defaults, as a printable string. Never let a count leave without it."""
    return ("regex" if use_regex else "literal") + ", " + \
           ("case-sensitive" if case_sensitive else "case-insensitive")


def count(root, files, pattern, use_regex, case_sensitive):
    flags = 0 if case_sensitive else re.IGNORECASE
    rx = re.compile(effective(pattern, use_regex), flags)
    per_file, total = {}, 0
    for f in files:
        try:
            text = (root / f).read_text(encoding="utf-8", errors="replace")
        except (OSError, IsADirectoryError):
            continue
        n = len(rx.findall(text))
        if n:
            per_file[f] = n
            total += n
    return total, per_file


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--control", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--under", action="append", default=[])
    ap.add_argument("--exclude", action="append", default=[])
    ap.add_argument("--regex", action="store_true")
    ap.add_argument("--case-sensitive", action="store_true")
    ap.add_argument("--walk", action="store_true")
    ap.add_argument("patterns", nargs="+")
    a = ap.parse_args()

    root = Path(a.root).resolve()
    if not root.is_dir():
        print(f"{RED}✗ --root {root} is not a directory — no population, no count{OFF}")
        return 2

    files, mode = collect(root, a.under, a.exclude, a.walk)

    # ── THE CONTROL, ASSERTED BEFORE ANY RESULT IS SHOWN ──────────────────────────
    ctl_total, ctl_files = count(root, files, a.control, a.regex, a.case_sensitive)
    if ctl_total == 0:
        print(f"{RED}✗ CONTROL FAILED — `{a.control}` matched NOTHING in "
              f"{len(files)} file(s) [{mode} mode].{OFF}")
        print(f"  {DIM}The instrument is not proven, so no counts are reported. Either the\n"
              f"  pattern is wrong, the file set is wrong, or both. Fix the control first —\n"
              f"  a zero from an unproven instrument is indistinguishable from a finding.{OFF}")
        return 2
    print(f"{GREEN}✓ control{OFF} {DIM}`{a.control}` → {ctl_total} hit(s) in "
          f"{len(ctl_files)} file(s) — the instrument works{OFF}")

    # ── the denominator AND how it was drawn, always ──────────────────────────────
    print(f"{DIM}  population: {len(files)} file(s) via {mode.upper()}"
          f"{' under ' + ', '.join(a.under) if a.under else ''}"
          f"{'  ·  EXCLUDED: ' + ', '.join(a.exclude) if a.exclude else ''}{OFF}")
    print(f"{DIM}  root: {root}{OFF}")
    # The two silent defaults, stated. A literal search that should have been a regex
    # returns 0 and looks exactly like a true finding; so does a case delta. Printing
    # the mode costs one line and removes the whole class.
    print(f"{DIM}  matching: {matching_mode(a.regex, a.case_sensitive)}{OFF}")
    if mode == "walk":
        print(f"{YELLOW}  ⚠ WALK mode — not a git repo (or --walk forced). This population is NOT\n"
              f"    complete by construction: it skips {', '.join(sorted(SKIP_DIRS))}.\n"
              f"    State that limit alongside any number you quote from this run.{OFF}")
    print()

    grand = 0
    for p in a.patterns:
        total, per_file = count(root, files, p, a.regex, a.case_sensitive)
        grand += total
        colour = YELLOW if total else DIM
        print(f"  {colour}{p:<28}{OFF} {total:>5}")
        # A zero from a pattern carrying regex syntax in LITERAL mode is the one case
        # the control cannot catch: the control proves the FILES are reachable, never
        # that the QUESTION was asked. Fired only on a zero, so a run that produced an
        # answer stays quiet and this notice keeps its meaning.
        if total == 0 and not a.regex and looks_like_regex(p):
            print(f"      {YELLOW}⚠ literal mode — compiled as  {effective(p, False)}\n"
                  f"        rather than as the regex  {p}\n"
                  f"        This zero may be the escaping, not a finding. "
                  f"Re-run with --regex.{OFF}")
        for f, n in sorted(per_file.items(), key=lambda kv: -kv[1]):
            print(f"      {DIM}{n:>4}  {f}{OFF}")
    print(f"\n  {DIM}{'-' * 34}{OFF}\n  {'TOTAL':<28} {grand:>5}"
          f"   {DIM}across {len(files)} file(s){OFF}")
    print(f"\n{DIM}  ⚠️ A hit is not a defect. Triage each one by reading it: a real run once\n"
          f"     produced 6 hits for a retired name and all 6 were legitimate.{OFF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
