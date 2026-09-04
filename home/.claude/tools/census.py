#!/usr/bin/env python3
r"""census — count pattern hits across a project's files, and REFUSE to answer without a control.

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

WHAT THE CONTROL DOES AND DOES NOT PROVE (read this before quoting a zero)
    The control and your patterns run through the SAME count(). So a green tick proves
    the FILES ARE REACHABLE. It does not prove YOUR QUESTION WAS ASKED.

      proven by the control  · --root points at a real directory
                             · --under / --exclude left a non-empty population
                             · those files are readable and were searched
      NOT proven             · that your pattern means what you think it means

    Measured: `--control stow '\.zshrc'` returned a GREEN control and 0 hits, while the
    true count was 210. The control was a plain word, so it survived literal escaping;
    the pattern was a regex, so it did not. One shared code path, two different fates.

    Closed structurally, not by discipline: the header states the matching mode on every
    run, and a pattern that returns ZERO while carrying regex syntax in literal mode
    prints the expression actually compiled beside the one that was typed.

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
    · a silent default          → the matching mode (literal/regex, case) is printed
                                  every run, because both defaults can turn a real
                                  count into a zero that reads like a finding
    · an invisible trim         → `git` mode prints how many files it never opened
                                  (ignored, untracked); every --under/--exclude prints
                                  how many files it actually moved, loudly at zero;
                                  binary and unreadable files are counted out and named
    · painted output            → colour only on a terminal. NO_COLOR and --no-color are
                                  honoured, because piping a painted row into grep
                                  returns a confident 0

WHAT IT DOES NOT FIX
    It cannot tell you a hit is a DEFECT. Triage is a human reading, always. A real run
    once produced six hits for a retired name and all six were legitimate.

    It cannot tell you your PATTERN was right — only that the files were searched. See
    "WHAT THE CONTROL DOES AND DOES NOT PROVE" above.

Usage
    uv run python3 ~/.claude/tools/census.py --control <token-known-present> PATTERN...

    --control TOKEN     required. A token you KNOW is present. Zero hits ⇒ exit 2.
                        Give it the SAME syntax class as your patterns: a literal
                        control cannot prove a regex pattern compiled as intended.
    --root PATH         project root to census (default: current directory).
    --under PREFIX      restrict to this path or anything beneath it, relative to root
                        (repeatable). Matched on PATH boundaries, so `d` never means
                        docs/, dist/ and data/ at once.
    --exclude PREFIX    drop this path and anything beneath it (repeatable). Both
                        filters print the number of files they moved.
    --regex             treat patterns as regular expressions instead of literals.
    --case-sensitive    default is case-insensitive.
    --walk              force the filesystem walk even inside a git repo.
    --binary            also search binary files (default: skipped, and the count shown).
    --no-color          never emit ANSI. NO_COLOR is honoured too, and colour is off
                        automatically whenever stdout is not a terminal.

Exit codes
    0  a count was produced      2  the control failed, or --root is not a directory
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

RED, YELLOW, GREEN, DIM, OFF = "\033[1;31m", "\033[0;33m", "\033[0;32m", "\033[2m", "\033[0m"


def init_colour(force_off):
    """Paint only a terminal. Piped output is DATA, and an escape sequence is text.

    Unconditional colour put a wrong zero one pipe away: `census … | grep -c '^  name'`
    returned 0 because every result row began with an escape sequence, not with two
    spaces. That is this tool's own failure mode, emitted by this tool.
    """
    global RED, YELLOW, GREEN, DIM, OFF
    if force_off or os.environ.get("NO_COLOR") or not sys.stdout.isatty():
        RED = YELLOW = GREEN = DIM = OFF = ""

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


def git_unsearched(root):
    """(ignored, untracked) counts — files git KNOWS about that `ls-files` never returns.

    `git` mode is complete over TRACKED files and silent about everything else. A rename
    once verified clean at 0 stale references while ignored files still held the old
    name. Returns (None, None) outside a repo.
    """
    def n(extra):
        r = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", *extra],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            return None
        return len([f for f in r.stdout.split("\n") if f.strip()])
    return n(["--ignored"]), n([])


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


def inside(path, prefix):
    """True when `path` IS `prefix` or lies beneath it — on PATH boundaries, not letters.

    A bare str.startswith made `--exclude d` swallow docs/, dist/ and data/ alike while
    the header printed only `EXCLUDED: d`. The trim was silent, which is the same defect
    as an unstated population.
    """
    return path == prefix or path.startswith(prefix + "/")


def classify(path):
    """'text', 'binary' (NUL in the first 8 KB, the sniff git and grep use), or 'unreadable'.

    read_text(errors='replace') will happily scan an mp3 and report hits inside it: not
    readable, not triageable, and they inflate a number somebody will quote. Unreadable
    is kept SEPARATE from binary rather than folded into it — a permission-denied file is
    a hole in the population, and reporting it as "binary" would be its own quiet lie.
    """
    try:
        with open(path, "rb") as fh:
            return "binary" if b"\x00" in fh.read(8192) else "text"
    except OSError:
        return "unreadable"


def collect(root, unders, excludes, force_walk, include_binary=False):
    """Return (files, mode, filters). mode is 'git' or 'walk' and is always reported.

    `filters` records what each --under/--exclude ACTUALLY did, so a prefix that matched
    nothing (a typo) and one that matched half the tree cannot look the same on screen.
    Binary files are dropped from the POPULATION, not merely skipped while counting, so
    the denominator stays the set actually searched.
    """
    files = None if force_walk else git_files(root)
    mode = "git"
    if files is None:
        files = walked_files(root)
        mode = "walk"

    filters = []
    unders = [u.strip("/") for u in unders]
    excludes = [e.strip("/") for e in excludes]
    if unders:
        for u in unders:
            filters.append(("--under", u, sum(1 for f in files if inside(f, u)), "kept"))
        files = [f for f in files if any(inside(f, u) for u in unders)]
    for e in excludes:
        n = sum(1 for f in files if inside(f, e))
        filters.append(("--exclude", e, n, "dropped"))
        files = [f for f in files if not inside(f, e)]

    kinds = {f: classify(root / f) for f in files}
    unreadable = [f for f in files if kinds[f] == "unreadable"]
    binaries = [f for f in files if kinds[f] == "binary"]
    if unreadable:
        filters.append(("unreadable", "(could not be opened)", len(unreadable), "dropped"))
    if binaries and not include_binary:
        filters.append(("binary", "(NUL byte in first 8 KB)", len(binaries), "dropped"))
    keep = {"text"} | ({"binary"} if include_binary else set())
    files = [f for f in files if kinds[f] in keep]
    return files, mode, filters


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
    ap.add_argument("--no-color", "--no-colour", action="store_true", dest="no_color")
    ap.add_argument("--binary", action="store_true",
                    help="also search binary files (default: skipped, and the count printed)")
    ap.add_argument("patterns", nargs="+")
    a = ap.parse_args()

    init_colour(a.no_color)

    # ── AN EMPTY CONTROL IS NOT A CONTROL ─────────────────────────────────────────
    # `--control ""` compiles to the empty pattern, which matches at every position, so
    # it reported "the instrument works" over any corpus at all — the one gate this whole
    # tool is built around, walked straight through.
    #
    # This is the tool's OWN founding accident, mirrored. census exists because an
    # unquoted shell variable made grep return a false ZERO; `--control "$VAR"` with VAR
    # unset makes census return a false PASS. Same slip, opposite direction.
    if not a.control.strip():
        print(f"{RED}✗ --control is empty — that is not a control, it is a blank cheque.{OFF}")
        print(f"  {DIM}An empty pattern matches everywhere, so the control would 'pass'\n"
              f"  against any corpus and prove nothing. If you wrote --control \"$VAR\",\n"
              f"  the variable is unset or empty — the exact accident this tool exists to\n"
              f"  catch, pointed at the control instead of the pattern.{OFF}")
        return 2
    for p in a.patterns:
        if not p.strip():
            print(f"{RED}✗ an empty PATTERN was given — it matches everywhere "
                  f"and counts nothing.{OFF}")
            return 2

    # ── NOR IS A CONTROL THAT CAN MATCH NOTHING AT ALL ────────────────────────────
    # Blanking the control is only the crudest way to make it meaningless. `--regex
    # --control 'x*'` is the same hole with a fig leaf: `x*` matches the empty string, so
    # it hits at every position and "proves" an instrument that was never tested. Same for
    # `a?`, `(?:)`, `^`, and anything else that can match zero characters.
    #
    # The test is the property, not a blacklist: compile it and ask whether it matches the
    # empty string. A control that can match nothing cannot prove anything.
    try:
        _ctl_rx = re.compile(effective(a.control, a.regex))
    except re.error:
        _ctl_rx = None                      # invalid regex is handled below
    if _ctl_rx is not None and _ctl_rx.match("") is not None:
        print(f"{RED}✗ --control `{a.control}` can match the EMPTY STRING, so it hits "
              f"everywhere.{OFF}")
        print(f"  {DIM}A control that matches nothing cannot prove anything. Zero-width\n"
              f"  patterns — x*, a?, ^, (?:) — pass against any corpus at all. Give a\n"
              f"  control that must consume at least one character.{OFF}")
        return 2

    root = Path(a.root).resolve()
    if not root.is_dir():
        print(f"{RED}✗ --root {root} is not a directory — no population, no count{OFF}")
        return 2

    files, mode, filters = collect(root, a.under, a.exclude, a.walk, a.binary)

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
    print(f"{DIM}  population: {len(files)} file(s) via {mode.upper()}{OFF}")
    print(f"{DIM}  root: {root}{OFF}")
    # Each filter with the number of files it moved. Naming a prefix is not the same as
    # showing its effect, and a prefix matching 0 files is nearly always a typo.
    for flag, prefix, n, verb in filters:
        tone = YELLOW if n == 0 else DIM
        tail = "  ← matched nothing; check the spelling" if n == 0 else ""
        print(f"{tone}  {flag} {prefix} → {n} file(s) {verb}{tail}{OFF}")
    # The two silent defaults, stated. A literal search that should have been a regex
    # returns 0 and looks exactly like a true finding; so does a case delta. Printing
    # the mode costs one line and removes the whole class.
    print(f"{DIM}  matching: {matching_mode(a.regex, a.case_sensitive)}{OFF}")
    if mode == "git":
        # Complete over TRACKED files, and mute about the rest. Say the size of the
        # blind spot every run: a population is only honest with its exclusions beside it.
        ignored, untracked = git_unsearched(root)
        if ignored is not None:
            hidden = ignored + untracked
            tone = YELLOW if hidden else DIM
            print(f"{tone}  NOT searched: {ignored} ignored, {untracked} untracked"
                  f"{' — git mode covers tracked files only' if hidden else ''}{OFF}")
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
