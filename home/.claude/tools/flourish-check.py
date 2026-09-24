#!/usr/bin/env python3
"""
flourish-check.py - flag decorative restatements in prose.

WHAT IT IS FOR
    Catches one specific writing habit: finish a sentence that already works,
    add a dash, then add a short compressed phrase saying the same thing again
    more cleverly. The operator finds these expensive to read - they cost a
    decode step and carry no new information.

        BAD   "...three lines above my patch for it - a fix underneath its own cause."
        GOOD  "Anyone reading that file top to bottom would hit the bad
               instruction before they reached my fix."

    It also flags the aphorism vector: a semicolon followed by a short punchy
    restatement, which is the same habit wearing different punctuation.

WHAT IT IS NOT
    It is ADVISORY. It flags, it never blocks, and it has no authority over
    judgement. A flagged clause may be fine. An unflagged one may be awful.
    It cannot parse English; it matches shapes.

    It CANNOT run automatically before a reply is sent. There is no hook that
    sees a message before the reader does. This is a tool to run on drafts and
    on files, not a gate.

HONEST REPORTING - the lesson this tool was built the day after
    A check that examines nothing and reports "clean" is worse than no check.
    So this ALWAYS prints what it examined: files read, lines scanned,
    sentences considered. Zero flags out of zero sentences is not a pass, and
    the output says so out loud.

KNOWN LIMITS - measured, not guessed
    Precision is roughly 1 in 3 on a structured markdown file. On CLAUDE.md it
    flagged 7 clauses and 2 were real. Both real ones were prose written today;
    the false positives were lists, template placeholders and definitions. That
    is acceptable for an advisory tool and worth knowing before you trust a
    count.

    Line numbers point at the START OF A PARAGRAPH, not the sentence, because
    wrapped prose has to be rejoined before it can be read. In a file with one
    sentence per line and no blank lines, every flag reports the first line.

    It cannot see restatement, only shape. A clause that repeats the previous
    sentence in different words will pass if it contains an auxiliary verb.

    DO NOT EDIT GOOD PROSE TO SATISFY THIS TOOL. Run it on itself and it flags
    one of its own sentences, which is a false positive caused by the narrow
    verb list. Read the flag, decide, and move on. A linter that starts
    rewriting sentences to go green has become the problem it was built for.

USAGE
    uv run python3 ~/.claude/tools/flourish-check.py FILE [FILE...]
    cat draft.md | uv run python3 ~/.claude/tools/flourish-check.py
    ... --max-words 15      widen what counts as a short trailing clause
    ... --quiet             only print flags and the denominator
"""

import argparse
import pathlib
import re
import sys

# Dash forms that introduce a trailing clause. Order matters: longest first.
DASHES = ["—", "–", " -- ", " - "]

# Words that suggest the trailing clause is doing real work rather than posing.
# Crude on purpose. A clause with a verb usually says something; a bare noun
# phrase usually re-labels what was just said.
# A finite auxiliary usually means the tail is a real clause, not a re-label.
# Kept DELIBERATELY NARROW. An earlier version matched any word ending in s,
# ed or ing, which matched "its" and silently excused every flourish in the
# control file. Restatement is a meaning, not a shape - no regex can see it.
# So this tool flags CANDIDATES and the human judges. Broad and advisory beats
# clever and wrong.
VERBISH = re.compile(
    r"\b(is|are|was|were|be|been|am|has|have|had|does|did|do|"
    r"will|would|can|could|should|shall|must|may|might)\b",
    re.I,
)

# Abstract nouns that keep turning up in these flourishes. Two or more in one
# short trailing clause is a strong tell.
ABSTRACT = re.compile(
    r"\b("
    r"cause|effect|artefact|artifact|evidence|proof|reason|instrument|shape|"
    r"cost|price|difference|distinction|failure|success|truth|state|"
    r"control|claim|measurement|photograph|tripwire|guess|answer|question"
    r")\b",
    re.I,
)

SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


def trailing_clauses(sentence: str):
    """Yield (kind, clause) for dash and semicolon tails in one sentence."""
    for d in DASHES:
        idx = sentence.rfind(d)
        if idx != -1:
            yield "dash", sentence[idx + len(d) :].strip()
            return
    if ";" in sentence:
        yield "semicolon", sentence.rsplit(";", 1)[1].strip()


def examine(text: str, max_words: int):
    """Return (flags, n_lines, n_sentences)."""
    flags = []
    raw_lines = text.splitlines()

    # Group wrapped prose into paragraphs, keeping each source line's number so
    # a flag points at the right place. Two bugs this guards against, both found
    # by running the tool on real files:
    #   1. splitting on line breaks made every wrap look like a sentence end
    #   2. joining list items inserted " - " between them, inventing dashes
    units = []          # (start_line, text)
    buf, start = [], None
    def flush():
        if buf:
            units.append((start, " ".join(buf)))
    for i, line in enumerate(raw_lines, 1):
        s = line.strip()
        is_break = not s or s.startswith(("```", "|", "$", "#", ">", "!", "---", "==="))
        is_item = bool(re.match(r"^([-*+]\s|\d+[.)]\s)", s))
        if is_break:
            flush(); buf, start = [], None
            continue
        if is_item:
            flush(); buf, start = [], None
            units.append((i, re.sub(r"^([-*+]\s|\d+[.)]\s)", "", s)))
            continue
        if not buf:
            start = i
        buf.append(s)
    flush()

    n_sentences = 0
    for lineno, unit in units:
        for sentence in SENTENCE_END.split(unit):
            sentence = sentence.strip()
            if len(sentence.split()) < 5:
                continue
            # Skip quoted example text and bracketed template placeholders.
            if sentence.startswith(("[", '"', "'", "*\"", "BAD:", "GOOD:")):
                continue
            n_sentences += 1
            for kind, clause in trailing_clauses(sentence):
                clause = clause.rstrip(".!?").strip()
                words = clause.split()
                if not words or len(words) > max_words:
                    continue
                if VERBISH.search(clause):
                    continue
                n_abstract = len(ABSTRACT.findall(clause))
                if kind == "semicolon" and n_abstract < 2:
                    continue
                severity = "HIGH" if n_abstract >= 2 else "flag"
                flags.append((lineno, kind, severity, clause, sentence))
    return flags, len(raw_lines), n_sentences


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="files to check; omit to read stdin")
    ap.add_argument("--max-words", type=int, default=12,
                    help="longest trailing clause still treated as a flourish (default 12)")
    ap.add_argument("--quiet", action="store_true", help="flags and denominator only")
    args = ap.parse_args()

    sources = []
    if args.files:
        for f in args.files:
            p = pathlib.Path(f)
            if not p.is_file():
                print(f"  SKIP (not a file): {f}", file=sys.stderr)
                continue
            sources.append((str(p), p.read_text(errors="replace")))
    else:
        sources.append(("<stdin>", sys.stdin.read()))

    total_flags = total_lines = total_sentences = 0

    for name, text in sources:
        flags, n_lines, n_sent = examine(text, args.max_words)
        total_flags += len(flags)
        total_lines += n_lines
        total_sentences += n_sent
        if flags and not args.quiet:
            print(f"\n{name}")
        for lineno, kind, severity, clause, sentence in flags:
            print(f"  {severity:4s} line {lineno} ({kind}): “{clause}”")
            if not args.quiet:
                short = sentence if len(sentence) <= 120 else sentence[:117] + "..."
                print(f"       in: {short}")
                print(f"       fix: delete it, or replace it with why it matters.")

    # ALWAYS print the denominator. A clean result means nothing without it.
    print()
    print(f"  examined : {len(sources)} file(s), {total_lines} line(s), {total_sentences} sentence(s)")
    print(f"  flagged  : {total_flags}")
    if total_sentences == 0:
        print("  WARNING  : zero sentences examined. This is NOT a pass - the input")
        print("             was empty, unreadable, or entirely skipped as code/tables.")
        return 2
    if total_flags == 0:
        print("  clean, against a real denominator.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
