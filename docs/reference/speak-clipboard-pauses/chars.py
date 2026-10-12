"""How long does the voice pause after each punctuation mark or character?

Each mark is put into the same three carrier sentences at the same spot.
For each, the full sentence is rendered, and the sentence cut off just after
the mark: the silence that starts where the cut-off piece ends is the pause
the mark made. A plain space (no mark) is the baseline.

  uv run python3 chars.py OUT.json [--rate N] [--voice KEY]
Outside the Claude sandbox (say2 needs the speech service).
"""
import json, statistics, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from pauses import render, silences

CARRIERS = [
    ("We checked the first part", " then we moved on to the rest of it."),
    ("Nothing stopped that kind of test", " so we added a check that catches it."),
    ("The deletion rules were missing", " the new ruling about secret files."),
]
MARKS = [
    ("(no mark, baseline)", ""), (",", ","), (";", ";"), (":", ":"),
    (".", "."), ("!", "!"), ("?", "?"), ("?!", "?!"),
    ("..", ".."), ("...", "..."), ("... (unicode)", "…"), (". . .", ". . ."),
    (". .", ". ."), (". . . . .", ". . . . ."),
    (" -", " -"), (" --", " --"), ("em dash", "—"), (" em dash ", " —"),
    ("en dash", " –"), ("( ... )", " (aside)"), (")", ")"),
    ('"', '"'), ("/", " /"), ("|", " |"), ("*", " *"), ("#", " #"),
    ("newline", "\n"), ("two newlines", "\n\n"), (". + newline", ".\n"),
    (", + newline", ",\n"), ] + [(f"[[slnc {n}]]", f" [[slnc {n}]]") for n in (0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 800, 1000)] + [
    (". [[slnc 300]]", ". [[slnc 300]]"), (". [[slnc 500]]", ". [[slnc 500]]"), (", [[slnc 500]]", ", [[slnc 500]]"),
]
TOL = 0.2


def pause_after(head, mark, tail, voice, rate):
    full = render(head + mark + tail, voice, rate)
    sils, total = silences(full)
    _, end = silences(render(head, voice, rate))   # the last word ends here, whatever the mark
    near = [(abs(s - end), e - s) for s, e in sils if abs(s - end) <= TOL]
    return (round(min(near)[1] * 1000) if near else 0), total


def main():
    args = sys.argv[1:]
    out = args[0]
    rate = int(args[args.index("--rate") + 1]) if "--rate" in args else 440
    voice = args[args.index("--voice") + 1] if "--voice" in args else "en-US:natural:male:Aaron:premium:5030"
    rows, base_len = [], None
    print(f"{'mark':<22} {'pause in 3 sentences':<22} {'middle':>6}  {'adds to length':>14}")
    for label, mark in MARKS:
        ms, lens = [], []
        for head, tail in CARRIERS:
            p, total = pause_after(head, mark, tail, voice, rate)
            ms.append(p); lens.append(total)
        mid = statistics.median(ms)
        if base_len is None:
            base_len = statistics.median(lens)
        added = round((statistics.median(lens) - base_len) * 1000)
        rows.append({"label": label, "mark": mark, "ms": ms, "median": mid, "added_ms": added})
        print(f"{label:<22} {' / '.join(f'{x:>3}' for x in ms):<22} {mid:>6.0f}  {added:>+11d} ms")
    json.dump({"rate": rate, "voice": voice, "rows": rows}, open(out, "w"), indent=1)


main()
