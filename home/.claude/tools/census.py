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

WHAT IT SEARCHES, AND WHAT IT DOES NOT
    CONTENTS, never paths. A retired name surviving only in a FILENAME therefore counts
    zero — on exactly the question this tool is most used for. A zero now checks the
    paths too and says so when the name is sitting in one; it does not add path hits to
    the count, because a filename and an occurrence are different facts.

    Text, and UTF-16 when it carries a BOM. Everything else with a NUL byte in the first
    8 KB is counted out as binary and named. `git ls-files -z` is used throughout, so a
    filename with a space, a newline or non-ASCII characters is searched like any other;
    such a name is escaped when printed so a result row can never span two lines.

    Symlinks are followed. One pointing outside the root is read and reported under its
    in-repo path, and a broken one is counted as unreadable rather than skipped quietly.

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
    --include-ignored   search the tracked files AND the hidden ones together.
    --ignored-only      search ONLY the hidden ones — the exact complement.

SCOPE — the three populations partition the project
    default             tracked files (git ls-files), or the visible tree in walk mode
    --ignored-only      the complement: gitignored + untracked, or the contents of
                        SKIP_DIRS (build/, dist/, node_modules/ ...) in walk mode
    --include-ignored   the union, so its counts are the SUM of the other two

    A default run that returns 0 has not proved a name is gone; it has proved the name
    is not in the tracked set. `--ignored-only` is the second search that finishes the
    job, and `--include-ignored` is the single run that needs no footnote. `.git` is
    never searched under any scope. The two flags are mutually exclusive.

    Carrying a control across from a default run into `--ignored-only` usually fails,
    and correctly so: a control living in a tracked file cannot prove an instrument
    pointed at the hidden set. census says so and names the way out.
    --json              one JSON object on stdout instead of the text report, carrying
                        every fact the text carries. EVERY refusal is JSON too -
                        including argparse's own usage errors - so a script never has to
                        scrape prose to learn it was refused. Implies --no-color.
                        Success: {ok:true, control, population, patterns[], total}
                        Refusal: {ok:false, refused:"<reason>", ...}  exit 2
    --no-color          never emit ANSI. NO_COLOR is honoured too, and colour is off
                        automatically whenever stdout is not a terminal.

REFUSALS (exit 2, no numbers printed)
    · the control matched nothing
    · --control is empty, or can match the empty string (x*, a?, ^, ...) — such a
      control "passes" against any corpus at all and proves nothing
    · a PATTERN is empty
    · the control or any pattern is not a valid regular expression — the run is refused
      WHOLE, because a partial count with no TOTAL beneath it reads like a complete one
    · --root is not a directory

Exit codes
    0  a count was produced      2  refused (see REFUSALS above)
"""

import argparse
import json
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


def git_files(root, scope="tracked"):
    """The population for a scope. Returns None if this is not a git repo.

    The three scopes PARTITION the repository, and that is the point:

        tracked   what `git ls-files` returns — complete by construction, blind to the rest
        ignored   exactly the complement: gitignored plus untracked
        all       the union, and therefore the sum of the other two

    A default run reports the size of the blind spot but does not look inside it.
    `ignored` is the missing half — the second search you run when the first said zero —
    and `all` is the one number that needs no footnote.
    """
    def ls(args):
        # -z, always. Without it `git ls-files` C-QUOTES any path with a non-ASCII or
        # special character — `"caf\303\251-\342\230\225.txt"`, `"line\nbreak.txt"` —
        # and census took the quoted spelling as the filename, failed to open it, and
        # counted it as unreadable. Measured: 4 files in, 2 searched, 2 "unreadable",
        # with the unicode and newline names dropped. -z emits paths verbatim, separated
        # by NUL, so no name can be mangled and none can be split in half either.
        r = subprocess.run(["git", "-C", str(root), "ls-files", "-z", *args],
                           capture_output=True, text=True)
        return None if r.returncode != 0 else [f for f in r.stdout.split("\0") if f]
    tracked = ls([])
    if tracked is None:
        return None
    if scope == "tracked":
        return tracked
    hidden = (ls(["--others", "--exclude-standard", "--ignored"]) or []) \
        + (ls(["--others", "--exclude-standard"]) or [])
    if scope == "ignored":
        return sorted(set(hidden))
    return sorted(set(tracked) | set(hidden))


def git_unsearched(root):
    """(ignored, untracked) counts — files git KNOWS about that `ls-files` never returns.

    `git` mode is complete over TRACKED files and silent about everything else. A rename
    once verified clean at 0 stale references while ignored files still held the old
    name. Returns (None, None) outside a repo.
    """
    def n(extra):
        r = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--others", "--exclude-standard",
             *extra],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            return None
        return len([f for f in r.stdout.split("\0") if f])
    return n(["--ignored"]), n([])


def walked_files(root, scope="tracked"):
    """(files, skipped) — everything under root minus SKIP_DIRS, and HOW MANY that cost.

    Naming the skipped directories was not enough. A retired token living in build/ made
    a real session read `0` from walk mode and start to call it gone; the list of skipped
    names was on screen, in a wall of nineteen entries, and carried no number. `it skips
    … build …` and `2 file(s) inside skipped directories were NOT searched` land very
    differently, and only the second is a quantity you can act on.
    """
    # Walk mode partitions the same way: the visible tree, the contents of SKIP_DIRS,
    # and their union. `.git` is never descended into under any scope — it is an object
    # store, not source, and searching it yields hits nobody can act on.
    out, skipped = [], 0
    always = {".git"}
    prune = always if scope in ("all", "ignored") else SKIP_DIRS
    for dirpath, dirnames, filenames in os.walk(root):
        pruned = [d for d in dirnames if d in prune]
        dirnames[:] = [d for d in dirnames if d not in prune]
        for d in pruned:                       # count what the prune actually cost
            for _, _, fs in os.walk(os.path.join(dirpath, d)):
                skipped += len(fs)
        for name in filenames:
            if name in prune:
                skipped += 1
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            out.append(rel)
    return sorted(out), skipped


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


def collect(root, unders, excludes, force_walk, include_binary=False, scope="tracked"):
    """Return (files, mode, filters). mode is 'git' or 'walk' and is always reported.

    `filters` records what each --under/--exclude ACTUALLY did, so a prefix that matched
    nothing (a typo) and one that matched half the tree cannot look the same on screen.
    Binary files are dropped from the POPULATION, not merely skipped while counting, so
    the denominator stays the set actually searched.
    """
    files = None if force_walk else git_files(root, scope)
    mode, skipped = "git", 0
    if files is None:
        files, skipped = walked_files(root, scope)
        mode = "walk"
        if scope == "ignored":
            # walked_files returns the whole tree when nothing is pruned; the ignored
            # scope is the COMPLEMENT of the default, so subtract the visible set.
            visible, _ = walked_files(root, "tracked")
            files = sorted(set(files) - set(visible))

    filters = []
    unders = [u.strip("/") for u in unders]
    excludes = [e.strip("/") for e in excludes]
    if unders:
        for u in unders:
            n = sum(1 for f in files if inside(f, u))
            filters.append(("--under", u, n, "kept", "typo" if n == 0 else "", n))
        files = [f for f in files if any(inside(f, u) for u in unders)]
    # Each exclude is scored against the population as it stood BEFORE any exclude ran,
    # not against the progressively shrinking one. Otherwise a filter that is merely
    # REDUNDANT — `--exclude docs --exclude docs`, or a prefix already covered by an
    # earlier one — scores 0 and gets accused of being a typo. That warning exists to
    # catch a misspelling; firing it on a correct-but-redundant filter is how it becomes
    # noise, and noise is how the real one gets ignored.
    before_excludes = list(files)
    for e in excludes:
        newly = sum(1 for f in files if inside(f, e))
        matched = sum(1 for f in before_excludes if inside(f, e))
        if matched == 0:
            note = "typo"                       # matches nothing in the population at all
        elif newly == 0:
            note = "redundant"                  # a previous filter already removed these
        else:
            note = ""
        filters.append(("--exclude", e, newly, "dropped", note, matched))
        files = [f for f in files if not inside(f, e)]

    kinds = {f: classify(root / f) for f in files}
    unreadable = [f for f in files if kinds[f] == "unreadable"]
    binaries = [f for f in files if kinds[f] == "binary"]
    if unreadable:
        filters.append(("unreadable", "(could not be opened)", len(unreadable),
                        "dropped", "", len(unreadable)))
    if binaries and not include_binary:
        filters.append(("binary", "(NUL byte in first 8 KB)", len(binaries),
                        "dropped", "", len(binaries)))
    keep = {"text"} | ({"binary"} if include_binary else set())
    files = [f for f in files if kinds[f] in keep]
    return files, mode, filters, skipped


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


def show_path(path):
    """A path safe to print on ONE line. Unremarkable names pass through untouched.

    A filename may legally contain a newline. Printed raw it splits a result row in two,
    so the report grows a line that carries no count and the file list stops being
    parseable — a tool that promises never to truncate must also never smear one row
    across two. Only names carrying control characters are escaped, so the common case
    reads exactly as before.
    """
    if any(ord(c) < 0x20 or ord(c) == 0x7f for c in path):
        return repr(path)
    return path


def matching_mode(use_regex, case_sensitive):
    """The two silent defaults, as a printable string. Never let a count leave without it."""
    return ("regex" if use_regex else "literal") + ", " + \
           ("case-sensitive" if case_sensitive else "case-insensitive")


def rx_of(pattern, use_regex=False, case_sensitive=False):
    """The compiled expression, so the path check and the content count cannot diverge."""
    return re.compile(effective(pattern, use_regex),
                      0 if case_sensitive else re.IGNORECASE)


def count(root, files, pattern, use_regex, case_sensitive):
    flags = 0 if case_sensitive else re.IGNORECASE
    rx = re.compile(effective(pattern, use_regex), flags)
    per_file, total = {}, 0
    for f in files:
        try:
            raw = (root / f).read_bytes()
        except (OSError, IsADirectoryError):
            continue
        # UTF-16 is full of NUL bytes, so classify() calls it binary and --binary is the
        # only way to reach it — at which point read_text(utf-8) mangled every character
        # and the search found nothing. A flag that says "also search these" and then
        # cannot read them is a false promise, and a quiet zero inside a search the
        # caller explicitly asked for. Honour the BOM; everything else stays UTF-8.
        if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
            text = raw.decode("utf-16", errors="replace")
        else:
            text = raw.decode("utf-8", errors="replace")
        n = len(rx.findall(text))
        if n:
            per_file[f] = n
            total += n
    return total, per_file


DESCRIPTION = """\
Count pattern hits across a project's files, and REFUSE to answer without a control.

A control is a token you KNOW is present. It runs first; if it misses, you get an
error and NO NUMBERS, because a number from an unproven instrument is worse than
no number at all.

What a green control proves:      --root is real, the filters left a population,
                                  and those files were opened and searched.
What it does NOT prove:           that your pattern means what you think it does.
                                  Give the control the same syntax class as the
                                  patterns - a literal control cannot vouch for a
                                  regex pattern."""

EPILOG = """\
refused (exit 2, and nothing is counted):
  the control matched nothing            an empty PATTERN
  --control empty, or able to match      the control or a pattern is not valid
    the empty string (x*, a?, ^)           regex - the run is refused WHOLE, since
  --root is not a directory                a partial count reads like a full one

always printed, so a count is never quoted bare:
  the population and how it was drawn (git ls-files, or an explicit walk)
  the matching mode, because literal-vs-regex and case are both silent defaults
  what every filter removed, and what was never searched at all

example:
  census.py --control stow --under home SAFE_RM_OFF
  census.py --regex --control 'CONTR.L' '66\\.226\\.144\\.185'

a hit is not a defect. triage every one by reading it."""


class _JsonAwareParser(argparse.ArgumentParser):
    """Emit argparse's own errors as JSON when --json was asked for.

    A missing PATTERN or a bad flag exited 2 with prose on stderr, so a script running
    with --json still had to scrape English to learn what went wrong. Every other refusal
    speaks JSON; this one is not allowed to be the exception. --json is read straight from
    argv because the failure happens before parsing finishes.
    """

    def error(self, message):
        if "--json" in sys.argv[1:]:
            print(json.dumps({"ok": False, "refused": "bad_arguments",
                              "error": message}, indent=2))
            raise SystemExit(2)
        super().error(message)


def build_parser():
    """The parser, built apart from main() so the self-test can inspect it.

    Every option carries help text. Nine of eleven had none: `--help` printed a bare
    column of flag names while the reasoning sat in a docstring nobody running --help
    ever sees. A tool whose whole value is a discipline has to explain the discipline
    at the place people actually look.
    """
    ap = _JsonAwareParser(
        add_help=True,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=DESCRIPTION,
        epilog=EPILOG,
    )
    ap.add_argument("--control", required=True, metavar="TOKEN",
                    help="REQUIRED. A token you KNOW is present. Asserted before any "
                         "result is shown; zero hits ends the run with exit 2")
    ap.add_argument("--root", default=".", metavar="PATH",
                    help="project root to census (default: the current directory)")
    ap.add_argument("--under", action="append", default=[], metavar="PREFIX",
                    help="restrict to this path or anything beneath it, relative to "
                         "root. Repeatable. Matched on PATH boundaries, so 'd' never "
                         "means docs/, dist/ and data/ at once")
    ap.add_argument("--exclude", action="append", default=[], metavar="PREFIX",
                    help="drop this path and anything beneath it. Repeatable. Both "
                         "filters print how many files they actually moved")
    ap.add_argument("--regex", action="store_true",
                    help="treat the control and patterns as regular expressions "
                         "(default: literal, so metacharacters are escaped)")
    ap.add_argument("--case-sensitive", action="store_true",
                    help="match case exactly (default: case-insensitive)")
    ap.add_argument("--walk", action="store_true",
                    help="force the filesystem walk even inside a git repo. The walk is "
                         "NOT complete by construction and says so")
    ap.add_argument("--no-color", "--no-colour", action="store_true", dest="no_color",
                    help="never emit ANSI. NO_COLOR is honoured too, and colour is off "
                         "automatically whenever stdout is not a terminal")
    scope_group = ap.add_mutually_exclusive_group()
    scope_group.add_argument("--include-ignored", action="store_true", dest="include_ignored",
                    help="search the tracked files AND the hidden ones together: "
                         "gitignored plus untracked in git mode, build/ dist/ "
                         "node_modules/ etc in walk mode. The union, so its count is the "
                         "sum of a default run and an --ignored-only run")
    scope_group.add_argument("--ignored-only", action="store_true", dest="ignored_only",
                    help="search ONLY the hidden files - the exact complement of a "
                         "default run. This is the second search you make when the first "
                         "returned zero: it lists what a tracked-only census could not "
                         "see. .git is never searched under any scope")
    ap.add_argument("--json", action="store_true",
                    help="emit one JSON object on stdout instead of the text report, "
                         "carrying every fact the text carries. REFUSALS are JSON too, "
                         "so a script never has to scrape prose to learn it was refused. "
                         "Implies --no-color")
    ap.add_argument("--binary", action="store_true",
                    help="also search binary files (default: skipped, and the count "
                         "printed so the omission is never silent)")
    ap.add_argument("patterns", nargs="+", metavar="PATTERN",
                    help="one or more things to count. Passed as argv and never through "
                         "a shell variable, so they cannot collapse into one argument")
    return ap


def main() -> int:
    ap = build_parser()
    a = ap.parse_args()

    init_colour(a.no_color or a.json)

    def refused(reason, **extra):
        """In JSON mode print the machine answer and stop; otherwise fall through to the
        human text below. A refusal a script cannot parse forces it back to scraping
        prose, which is the class of failure this whole tool exists to end."""
        if a.json:
            print(json.dumps({"ok": False, "refused": reason, **extra}, indent=2))
            return True
        return False

    # ── AN EMPTY CONTROL IS NOT A CONTROL ─────────────────────────────────────────
    # `--control ""` compiles to the empty pattern, which matches at every position, so
    # it reported "the instrument works" over any corpus at all — the one gate this whole
    # tool is built around, walked straight through.
    #
    # This is the tool's OWN founding accident, mirrored. census exists because an
    # unquoted shell variable made grep return a false ZERO; `--control "$VAR"` with VAR
    # unset makes census return a false PASS. Same slip, opposite direction.
    if not a.control.strip():
        if refused("empty_control", control=a.control):
            return 2
        print(f"{RED}✗ --control is empty — that is not a control, it is a blank cheque.{OFF}")
        print(f"  {DIM}An empty pattern matches everywhere, so the control would 'pass'\n"
              f"  against any corpus and prove nothing. If you wrote --control \"$VAR\",\n"
              f"  the variable is unset or empty — the exact accident this tool exists to\n"
              f"  catch, pointed at the control instead of the pattern.{OFF}")
        return 2
    for p in a.patterns:
        if not p.strip():
            if refused("empty_pattern"):
                return 2
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
    # ── EVERY EXPRESSION COMPILES BEFORE ANY OUTPUT LEAVES ────────────────────────
    # An invalid regex used to raise from inside the result loop, so census printed a
    # GREEN control, the population, and a real result row — and THEN a traceback. Those
    # numbers were true but partial, and partial output with no TOTAL beneath it is a
    # number that cannot be trusted: precisely what this tool exists to refuse.
    # Compile the control and every pattern up front, and refuse the whole run.
    bad = []
    for label, p in [("--control", a.control)] + [("pattern", x) for x in a.patterns]:
        try:
            re.compile(effective(p, a.regex))
        except re.error as e:
            bad.append((label, p, str(e)))
    if bad:
        if refused("invalid_regex",
                   invalid=[{"what": lbl, "expression": pat, "error": err}
                            for lbl, pat, err in bad]):
            return 2
        print(f"{RED}✗ {len(bad)} expression(s) are not valid regular expressions — "
              f"nothing was counted.{OFF}")
        for label, p, err in bad:
            print(f"  {RED}{label} {p}{OFF}  {DIM}→ {err}{OFF}")
        print(f"  {DIM}Refused whole rather than in part. A run that dies midway prints\n"
              f"  real numbers with no TOTAL under them, and a partial count reads exactly\n"
              f"  like a complete one.{OFF}")
        return 2

    _ctl_rx = re.compile(effective(a.control, a.regex))
    if _ctl_rx.match("") is not None:
        if refused("zero_width_control", control=a.control):
            return 2
        print(f"{RED}✗ --control `{a.control}` can match the EMPTY STRING, so it hits "
              f"everywhere.{OFF}")
        print(f"  {DIM}A control that matches nothing cannot prove anything. Zero-width\n"
              f"  patterns — x*, a?, ^, (?:) — pass against any corpus at all. Give a\n"
              f"  control that must consume at least one character.{OFF}")
        return 2

    root = Path(a.root).resolve()
    if not root.is_dir():
        if refused("root_not_a_directory", root=str(root)):
            return 2
        print(f"{RED}✗ --root {root} is not a directory — no population, no count{OFF}")
        return 2

    scope = "ignored" if a.ignored_only else ("all" if a.include_ignored else "tracked")
    files, mode, filters, skipped = collect(root, a.under, a.exclude, a.walk, a.binary,
                                           scope)

    # ── the denominator AND how it was drawn, ON BOTH PATHS ───────────────────────
    # This block used to run only AFTER the control passed, so a CONTROL FAILED run
    # withheld the population, the filters and the matching mode — the exact facts you
    # need to work out WHY it failed. "matched NOTHING in 1 file(s)" while silently
    # declining to mention that 30 binaries and 142 ignored files had been dropped is a
    # riddle, not a diagnosis. The message says "the file set is wrong, or both"; it must
    # therefore show the file set.
    def show_population():
        print(f"{DIM}  population: {len(files)} file(s) via {mode.upper()}{OFF}")
        print(f"{DIM}  root: {root}{OFF}")
        # Each filter with the number of files it moved. Naming a prefix is not the same
        # as showing its effect, and a prefix matching 0 files is nearly always a typo.
        for flag, prefix, n, verb, note, matched in filters:
            if note == "typo":
                tone, tail = YELLOW, "  ← matched nothing; check the spelling"
            elif note == "redundant":
                tone = DIM
                tail = f"  ({matched} already removed by an earlier filter — redundant, not a typo)"
            else:
                tone, tail = DIM, ""
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
                # Say what this scope did and did not open. Each of the three has a
                # different blind spot, and printing the wrong sentence would be the
                # same lie the line exists to prevent.
                if scope == "all":
                    print(f"{DIM}  ALSO searched: {ignored} ignored, {untracked} untracked "
                          f"(--include-ignored — tracked and hidden together){OFF}")
                elif scope == "ignored":
                    print(f"{YELLOW}  SCOPE: the hidden files ONLY — {ignored} ignored, "
                          f"{untracked} untracked. The tracked files were NOT searched;\n"
                          f"    this is the complement of a default run, not a whole "
                          f"census.{OFF}")
                else:
                    tone = YELLOW if hidden else DIM
                    print(f"{tone}  NOT searched: {ignored} ignored, {untracked} untracked"
                          f"{' — git mode covers tracked files only' if hidden else ''}"
                          f"{'  ·  --ignored-only searches just those, --include-ignored both' if hidden else ''}{OFF}")
        if mode == "walk":
            # The COUNT first, then the names. A list of nineteen directory names is
            # scenery; "2 file(s) ... NOT searched" is a quantity, and a quantity is the
            # thing a reader weighs against a zero.
            if scope == "ignored":
                print(f"{YELLOW}  SCOPE: the skipped directories ONLY. The visible tree "
                      f"was NOT searched;\n    this is the complement of a default run, "
                      f"not a whole census.{OFF}")
            else:
                tone = YELLOW if skipped else DIM
                print(f"{tone}  NOT searched: {skipped} file(s) inside skipped directories"
                      f"{' — a hit could be in any of them' if skipped else ''}"
                      f"{'  ·  --ignored-only searches just those, --include-ignored both' if skipped else ''}{OFF}")
            print(f"{YELLOW}  ⚠ WALK mode — not a git repo (or --walk forced). This population is NOT\n"
                  f"    complete by construction: it skips {', '.join(sorted(SKIP_DIRS))}.\n"
                  f"    State that limit alongside any number you quote from this run.{OFF}")

    def population_report():
        """The same facts show_population() prints, as data. Built from the same values
        so the JSON and the text can never disagree about what was searched."""
        ignored, untracked = git_unsearched(root) if mode == "git" else (None, None)
        # not_searched must describe THIS run, not the default one. Reporting
        # "ignored: 3" under scope "all" would have the JSON contradict the text, which
        # says ALSO searched for the very same files — and a machine reader has no
        # prose to correct it with.
        if scope == "all":
            gap = {"tracked": 0, "ignored": 0, "untracked": 0, "in_skipped_dirs": 0}
        elif scope == "ignored":
            tracked = git_files(root, "tracked") if mode == "git" else None
            gap = {"tracked": len(tracked) if tracked is not None else None,
                   "ignored": 0, "untracked": 0, "in_skipped_dirs": 0}
        else:
            gap = {"tracked": 0, "ignored": ignored, "untracked": untracked,
                   "in_skipped_dirs": skipped if mode == "walk" else None}
        return {
            "root": str(root),
            "mode": mode,
            "scope": scope,
            "searched": len(files),
            "matching": {"regex": bool(a.regex), "case_sensitive": bool(a.case_sensitive)},
            "filters": [{"flag": f, "prefix": pre, "files": n, "action": verb,
                         "note": note or None, "matched": matched}
                        for f, pre, n, verb, note, matched in filters],
            "not_searched": gap,
        }

    # ── THE CONTROL, ASSERTED BEFORE ANY RESULT IS SHOWN ──────────────────────────
    ctl_total, ctl_files = count(root, files, a.control, a.regex, a.case_sensitive)
    if ctl_total == 0:
        if refused("control_failed",
                   control={"pattern": a.control, "hits": 0, "files": 0},
                   population=population_report()):
            return 2
        print(f"{RED}✗ CONTROL FAILED — `{a.control}` matched NOTHING in "
              f"{len(files)} file(s) [{mode} mode].{OFF}")
        show_population()
        print(f"  {DIM}The instrument is not proven, so no counts are reported. Either the\n"
              f"  pattern is wrong, the file set is wrong, or both — the population above\n"
              f"  says which files were actually opened. A zero from an unproven instrument\n"
              f"  is indistinguishable from a finding.{OFF}")
        print(f"  {DIM}census.py --help lists every flag and every refusal.{OFF}")
        if scope == "ignored":
            # The predictable way to hit this: carry the control over from a default run,
            # where it lived in a TRACKED file that this scope deliberately excludes. Say
            # so, rather than leaving the caller to infer it from the SCOPE line.
            print(f"  {YELLOW}↳ --ignored-only searches ONLY the hidden files, so a "
                  f"control that\n    lives in a tracked file cannot hit here. Either "
                  f"pick a control you know is\n    in the hidden set, or use "
                  f"--include-ignored, which searches both and\n    accepts the "
                  f"control you already have.{OFF}")
        return 2
    if a.json:
        results, grand = [], 0
        for p in a.patterns:
            total, per_file = count(root, files, p, a.regex, a.case_sensitive)
            grand += total
            results.append({
                "pattern": p,
                "compiled": effective(p, a.regex),
                "total": total,
                # The same caveat the text prints, as a field a script can branch on.
                "literal_mode_zero_may_be_escaping":
                    total == 0 and not a.regex and looks_like_regex(p),
                "files": dict(sorted(per_file.items(), key=lambda kv: -kv[1])),
            })
        print(json.dumps({
            "ok": True,
            "control": {"pattern": a.control, "hits": ctl_total, "files": len(ctl_files)},
            "population": population_report(),
            "patterns": results,
            "total": grand,
        }, indent=2))
        return 0

    print(f"{GREEN}✓ control{OFF} {DIM}`{a.control}` → {ctl_total} hit(s) in "
          f"{len(ctl_files)} file(s) — the instrument works{OFF}")
    show_population()
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
        # census reads CONTENTS, never paths. So a retired name surviving only in a
        # FILENAME reports a clean zero — on the exact question the tool is most used
        # for. Measured: `OLDNAME` returned 0 with OLDNAME_config.py sitting in the
        # population. Fired only on a zero, where "gone" is about to be concluded, so a
        # run that already found something stays quiet.
        if total == 0:
            # Same mode as the content search. Defaulting here would let the path
            # check disagree with the count it is commenting on.
            named = [f for f in files
                     if rx_of(p, a.regex, a.case_sensitive).search(f)]
            if named:
                print(f"      {YELLOW}⚠ 0 in file CONTENTS, but the name appears in "
                      f"{len(named)} PATH(S):{OFF}")
                for f in named[:10]:
                    print(f"          {YELLOW}{show_path(f)}{OFF}")
                if len(named) > 10:
                    print(f"          {YELLOW}… and {len(named) - 10} more{OFF}")
                print(f"        {DIM}census searches contents only. This is not gone.{OFF}")
        if total == 0 and not a.regex and looks_like_regex(p):
            print(f"      {YELLOW}⚠ literal mode — compiled as  {effective(p, False)}\n"
                  f"        rather than as the regex  {p}\n"
                  f"        This zero may be the escaping, not a finding. "
                  f"Re-run with --regex.{OFF}")
        for f, n in sorted(per_file.items(), key=lambda kv: -kv[1]):
            print(f"      {DIM}{n:>4}  {show_path(f)}{OFF}")
    print(f"\n  {DIM}{'-' * 34}{OFF}\n  {'TOTAL':<28} {grand:>5}"
          f"   {DIM}across {len(files)} file(s){OFF}")
    # The --help pointer rides on the EXISTING footer rather than adding a line of its
    # own. Measured 2026-09-04: a first-time session used census correctly and never ran
    # --help, learning --include-ignored only because the population line names it at the
    # moment it matters. That exception-based hint works and must not be diluted; this is
    # the standing pointer to everything the situation did not happen to surface.
    print(f"\n{DIM}  ⚠️ A hit is not a defect. Triage each one by reading it: a real run once\n"
          f"     produced 6 hits for a retired name and all 6 were legitimate.\n"
          f"     census.py --help lists every flag — scoping, hidden files, regex, JSON.{OFF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
