# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-whisper"]
# ///
"""Clean a text with the live speak key, render it the way the line player does,
save it as a WAV, and write it back to text with word times and silences."""
import subprocess, sys, time, wave, struct
voice, rate, out_dir = "en-US:natural:male:Aaron:premium:5030", "460", sys.argv[1]
texts = {
    "codeblock": "Run this:\n```\necho one\necho two\n```\n\nThen check.\n",
    "control_plain": "Run this: Then check.\n",
}
def wait_idle():
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0:
        time.sleep(2)
import mlx_whisper
for name, raw in texts.items():
    clean = subprocess.run([f"{__import__('os').path.expanduser('~')}/.local/bin/speak-clipboard",
                            "--profile", "aaron_fast", "--print", "--stdin"],
                           input=raw.encode(), capture_output=True).stdout.decode().strip()
    wait_idle()
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm",
                        "-o", "-", "--", clean], capture_output=True)
    if r.returncode != 0 or not r.stdout:
        print(name, "RENDER FAILED rc", r.returncode, r.stderr.decode()[:300]); continue
    wav = f"{out_dir}/{name}.wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(r.stdout)
    # silences of 40 ms or more, 10 ms windows, -45 dBFS
    n = len(r.stdout) // 2
    s = struct.unpack(f"<{n}h", r.stdout[: n * 2])
    win, sil, start = 480, [], None
    for i in range(0, n, win):
        quiet = max(abs(x) for x in s[i:i + win]) < 184
        t = i / 48000
        if quiet and start is None: start = t
        if not quiet and start is not None:
            if t - start >= 0.04: sil.append((round(start, 2), round(t - start, 3)))
            start = None
    res = mlx_whisper.transcribe(wav, path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
                                 word_timestamps=True, language="en")
    words = [(w["word"].strip(), round(w["start"], 2), round(w["end"], 2))
             for seg in res["segments"] for w in seg.get("words", [])]
    print(f"== {name}: {n/48000:.2f} s audio, saved {wav}")
    print("sent to the voice:", repr(clean))
    print("heard back:", res["text"].strip())
    print("words (start-end s):", " ".join(f"{w}[{a}-{b}]" for w, a, b in words))
    print("silences inside the speech (start s, length s):", [x for x in sil if x[0] > 0.05])
