# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-whisper"]
# ///
"""Speak a text the way the line player does, with a speak-clipboard build:
clean, cut at each breath, render each part, 110 ms of silence in front of
every part after the first. Mode whole: one press. Mode remote: one press
per paragraph, queued; a paragraph starting a section gets 110 ms in front."""
import subprocess, struct, time, wave, sys, re
import mlx_whisper
script, src, out, mode = sys.argv[1:5]
voice, rate, BREATH = "en-US:natural:male:Aaron:premium:5030", "460", 200
raw = open(src, encoding="utf-8").read()
def clean(text):
    r = subprocess.run(["bash", script, "--profile", "aaron_fast", "--print", "--stdin"], input=text.encode(), capture_output=True)
    return r.stdout.decode().strip()
def render(text):
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", text], capture_output=True)
    assert r.returncode == 0, r.stderr
    return r.stdout
presses = [raw] if mode == "whole" else [p for p in re.split(r"\n\s*\n", raw) if p.strip() and not p.strip().startswith("```")]
if mode == "remote":   # keep a fenced block with its fences as one paragraph
    presses = re.split(r"\n\s*\n(?![^`]*```\n\s*\n)", raw)
    presses = [p for p in re.split(r"\n\n(?=(?:[^`]|`(?!``))*$)|\n\n(?=\S)", raw) if p.strip()]
audio, marks, sent = b"", [], []
for i, press in enumerate(presses):
    parts = clean(press).split(" {{{breath}}} ")
    lead = BREATH if (i > 0 and re.match(r"\s*(\*\*|❯|```)", press)) else 0
    for j, part in enumerate(parts):
        gap = lead if j == 0 else BREATH
        if gap: marks.append(len(audio) // 2 / 48000)
        audio += b"\0\0" * (48 * gap) + render(part)
        sent.append(("+" if gap else "") + part)
wav = f"{out}/listen-{mode}.wav"
with wave.open(wav, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(audio)
n = len(audio) // 2; s = struct.unpack(f"<{n}h", audio)
sil, start = [], None
for i in range(0, n, 480):
    q = max(abs(x) for x in s[i:i + 480]) < 184; t = i / 48000
    if q and start is None: start = t
    if not q and start is not None:
        if t - start >= 0.15 and start > 0.05: sil.append((round(start, 2), round(t - start, 2)))
        start = None
print(f"== mode {mode}: {len(presses)} press(es), {len(sent)} voice parts, {n/48000:.1f} s, saved {wav}")
for x in sent: print("   part:", x[:90])
print("   breath gaps placed at (s):", [round(m, 2) for m in marks])
print("   every silence of 0.15 s or more (start, length):", sil)
heard = mlx_whisper.transcribe(wav, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language="en")["text"].strip()
print("   heard back:", heard)
for w in ("echo", "breath", "slnc", "S L N C", "brace"): print(f"   '{w}' heard: {w.lower() in heard.lower()}")
# Breaths against ordinary full stops in the same audio.
near = lambda t: any(abs(t - m) < 0.1 for m in marks)
br = [x[1] for x in sil if near(x[0])]; other = [x[1] for x in sil if not near(x[0])]
print(f"   breaths: {sorted(br)}  |  other pauses: {sorted(other)}")
