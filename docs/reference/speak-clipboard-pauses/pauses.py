"""Measure where speak-clipboard's voice pauses, and for how long.

Cleans a text file with a speak-clipboard script (--stdin --print), renders
the whole text with say2 the way the line player does, and finds every
silence. Then renders the text cut off after each break (punctuation or **)
and times each piece: a silence that starts where a piece ends belongs to
that break. Prints one row per break, then any silence no break claimed.

  uv run python3 pauses.py SAMPLE OUT.json [--script PATH] [--rate N] [--voice KEY]
  uv run python3 pauses.py --compare A.json B.json

Needs say2 to reach the speech service: run outside the Claude sandbox.
"""
import json, re, subprocess, sys

BPS = 96000            # 48 kHz mono s16le
WIN = 480              # 10 ms windows
THRESH = 184           # -45 dBFS peak
MIN_SIL = 0.04         # shortest silence counted, seconds
TOL = 0.15             # a piece's end and a silence's start this close: a match


def wait_for_speak_key():
    # Never render while speak-clipboard's line player is speaking: both use
    # the same Siri service, and the speak key must win.
    import time
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0:
        time.sleep(2)


def render(text, voice, rate):
    wait_for_speak_key()
    # say2 exit 5 (service busy) and 7 (timed out) are worth a retry: seen
    # with several long renders at once.
    for _ in range(3):
        r = subprocess.run(["say2", "-v", voice, "-r", str(rate), "--engine", "siri",
                            "--format", "pcm", "-o", "-", "--", text], capture_output=True)
        if r.returncode not in (5, 7):
            break
    if r.returncode != 0 or not r.stdout:
        sys.exit(f"say2 failed (exit {r.returncode}): {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def silences(pcm):
    import array
    a = array.array("h"); a.frombytes(pcm[: len(pcm) // 2 * 2])
    out, start = [], None
    for w in range(0, len(a), WIN):
        quiet = max((abs(x) for x in a[w:w + WIN]), default=0) < THRESH
        t = w / 48000
        if quiet and start is None:
            start = t
        elif not quiet and start is not None:
            if t - start >= MIN_SIL:
                out.append((start, t))
            start = None
    end = len(a) / 48000
    if start is not None and end - start >= MIN_SIL:
        out.append((start, end))
    return out, end


def breaks(text):
    # After every word that ends in punctuation or **, and before every
    # [[slnc N]] the cleaner wrote; never inside one.
    out = [m.end() for m in re.finditer(r"\S*(?:[.:;,!?]|\*\*)(?=\s)", text) if not m.group().endswith("]]")]
    out += [m.start() for m in re.finditer(r" \[\[slnc \d+\]\]", text)]
    return sorted(set(out))


def key(piece):
    # The last three words without punctuation or speech commands, so the
    # same spot matches before and after a change (Found: and Found [[slnc]]).
    words = re.sub(r"\[\[slnc \d+\]\]", " ", piece)
    words = re.sub(r"[^A-Za-z0-9' -]", " ", words).split()
    return " ".join(words[-3:])


def measure(sample, out, script, rate, voice):
    raw = open(sample, "rb").read()
    if script == "none":   # the sample is already the spoken text
        text = raw.decode().strip()
    else:
        text = subprocess.run([script, "--stdin", "--print"], input=raw,
                              capture_output=True).stdout.decode().strip()
    if not text:
        sys.exit("the cleaner printed nothing")
    full = render(text, voice, rate)
    import wave
    with wave.open(re.sub(r"\.json$", "", out) + ".wav", "wb") as w:   # to listen to
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(full)
    sils, total = silences(full)
    # One render at a time, never several: six at once (12 Oct 2026, about
    # 9:31 PM) hung Siri renders for minutes and Gavin's speak key went
    # silent. A long reply is slow this way; that is the price.
    bs = breaks(text)
    ends = [silences(render(text[:b], voice, rate))[1] for b in bs]
    rows = [{"at": round(e, 2), "after": key(text[:b]), "ms": 0} for b, e in zip(bs, ends)]
    # Each silence goes to the one break whose end is nearest its start, so
    # two breaks close together cannot both claim it.
    claimed = set()
    for i, (s, e) in enumerate(sils):
        near = [(abs(s - r["at"]), j) for j, r in enumerate(rows) if abs(s - r["at"]) <= TOL]
        if near:
            _, j = min(near)
            if rows[j]["ms"] == 0:
                rows[j]["ms"] = round((e - s) * 1000)
                claimed.add(i)
    lead = [i for i, (s, e) in enumerate(sils) if s == 0]
    tail = [i for i, (s, e) in enumerate(sils) if abs(e - total) < 0.011]
    other = [{"start": round(s, 2), "ms": round((e - s) * 1000)}
             for i, (s, e) in enumerate(sils) if i not in claimed and i not in lead + tail]
    res = {"script": script.replace(__import__("os").path.expanduser("~"), "~"), "rate": rate, "voice": voice, "text": text,
           "seconds": round(total, 2), "silences": len(sils), "breaks": rows, "unclaimed": other}
    json.dump(res, open(out, "w"), indent=1)
    show(res)


def show(res):
    print(f"spoken text: {res['text']}\n")
    print(f"{res['seconds']} s of speech, {res['silences']} silences found, {len(res['breaks'])} breaks\n")
    print(f"{'at':>6}  {'pause':>6}  after")
    for r in res["breaks"]:
        print(f"{r['at']:6.2f}  {r['ms']:4d} ms  ...{r['after']}")
    if res["unclaimed"]:
        print("\nsilences no break claimed (inside a sentence):")
        for u in res["unclaimed"]:
            print(f"{u['start']:6.2f}  {u['ms']:4d} ms")
    else:
        print("\nevery silence inside the speech was claimed by a break")


def compare(a, b):
    A, B = json.load(open(a)), json.load(open(b))
    print(f"before: {A['seconds']} s   after: {B['seconds']} s\n")
    bm = {r["after"]: r["ms"] for r in B["breaks"]}
    print(f"{'before':>7} {'after':>7}  after")
    seen = set()
    for r in A["breaks"]:
        seen.add(r["after"])
        print(f"{r['ms']:4d} ms {bm.get(r['after'], '-'):>4} ms  ...{r['after']}")
    for r in B["breaks"]:
        if r["after"] not in seen:
            print(f"{'-':>4} ms {r['ms']:4d} ms  ...{r['after']}   (new break)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--compare":
        compare(args[1], args[2]); sys.exit(0)
    opts = {"--script": __import__("os").path.expanduser("~/.local/bin/speak-clipboard"), "--rate": "440",
            "--voice": "en-US:natural:male:Aaron:premium:5030"}
    pos = []
    while args:
        x = args.pop(0)
        if x in opts: opts[x] = args.pop(0)
        else: pos.append(x)
    measure(pos[0], pos[1], opts["--script"], int(opts["--rate"]), opts["--voice"])
