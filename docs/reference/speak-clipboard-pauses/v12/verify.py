# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-whisper"]
# ///
import subprocess, struct, time, wave, os, sys
import mlx_whisper
voice, rate, out = "en-US:natural:male:Aaron:premium:5030", "460", sys.argv[1]
cases = {
    "a_whole_reply_piece": "Run this:\n```bash\necho one\necho two\n```\n\nThen check.\n",
    "b_block_ends_the_piece": "```bash\necho one\necho two\n```\n",
    "c_no_block (control)": "Run this. Then check.\n",
}
for name, raw in cases.items():
    clean = subprocess.run([os.path.expanduser("~/.local/bin/speak-clipboard"), "--profile", "aaron_fast", "--print", "--stdin"], input=raw.encode(), capture_output=True).stdout.decode().strip()
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", clean], capture_output=True)
    n = len(r.stdout) // 2; s = struct.unpack(f"<{n}h", r.stdout[: n * 2])
    sil, start = [], None
    for i in range(0, n, 480):
        q = max(abs(x) for x in s[i:i + 480]) < 184; t = i / 48000
        if q and start is None: start = t
        if not q and start is not None:
            if t - start >= 0.04 and start > 0.05: sil.append(round(t - start, 2))
            start = None
    last = max((i for i in range(n) if abs(s[i]) >= 184), default=0)
    wav = f"{out}/{name.split()[0]}.wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(r.stdout)
    heard = mlx_whisper.transcribe(wav, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language="en")["text"].strip()
    print(f"== {name}\n   sent: {clean!r}\n   heard back: {heard}\n   pauses inside: {sil} s; silence at the end: {round((n-last)/48000, 2)} s")
