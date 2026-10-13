# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-whisper"]
# ///
import subprocess, time, wave, sys, os
import mlx_whisper
src, out = sys.argv[1:3]; SCRIPT = sys.argv[3] if len(sys.argv) > 3 else os.path.expanduser("~/.local/bin/speak-clipboard")
voice, rate = "en-US:natural:male:Aaron:premium:5030", "460"
text = subprocess.run([SCRIPT, "--profile", "aaron_fast", "--print", "--stdin"],
                      stdin=open(src, "rb"), capture_output=True).stdout.decode().strip()
audio = b""
for i, part in enumerate(text.split(" {{{breath}}} ")):
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", part], capture_output=True)
    audio += (b"\0\0" * 48 * 200 if i else b"") + r.stdout
wav = f"{out}/line.wav"
with wave.open(wav, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(audio)
res = mlx_whisper.transcribe(wav, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", word_timestamps=True, language="en")
ws = [(w["word"].strip(), w["start"], w["end"]) for s in res["segments"] for w in s["words"]]
print("heard back:", res["text"].strip())
for (a, _, e), (b, s2, _) in zip(ws, ws[1:]):
    print(f"  after '{a}' before '{b}': {s2 - e:.2f} s")
