import subprocess, time, struct, os
voice, rate = "en-US:natural:male:Aaron:premium:5030", "460"
pairs = [
 ("1A", "❯ **Pause words.** ✓ done · ❕ low risk."),
 ("1B", "❯ Pause words. ✓ done · ❕ low risk."),
 ("2A", "**What it means for you:** you were right."),
 ("2B", "What it means for you: you were right."),
 ("3A", "  ⋅ **Proof.** All 242 checks pass."),
 ("3B", "  ⋅ Proof. All 242 checks pass."),
]
for name, line in pairs:
    text = subprocess.run([os.path.expanduser("~/.local/bin/speak-clipboard"), "--profile", "aaron_fast", "--print", "--stdin"],
                          input=(line + "\n").encode(), capture_output=True).stdout.decode().strip()
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    a = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", text], capture_output=True).stdout
    n = len(a) // 2; s = struct.unpack(f"<{n}h", a)
    out, start = [], None
    for i in range(0, n, 480):
        q = max(abs(x) for x in s[i:i + 480]) < 184; t = i / 48000
        if q and start is None: start = t
        if not q and start is not None:
            if t - start >= 0.03 and start > 0.05: out.append((round(start, 2), round(t - start, 2)))
            start = None
    print(f"{name}: {n/48000:.2f} s  sent {text!r}\n     pauses (start, length): {out}")
