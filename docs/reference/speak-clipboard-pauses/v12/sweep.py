import subprocess, struct, time
voice, rate = "en-US:natural:male:Aaron:premium:5030", "460"
def render(text):
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", text], capture_output=True)
    n = len(r.stdout) // 2
    return struct.unpack(f"<{n}h", r.stdout[: n * 2])
def silences(s):
    out, start = [], None
    for i in range(0, len(s), 480):
        q = max(abs(x) for x in s[i:i + 480]) < 184
        t = i / 48000
        if q and start is None: start = t
        if not q and start is not None:
            if t - start >= 0.04: out.append(round(t - start, 2))
            start = None
    return out
def tail(s):
    last = max((i for i in range(len(s)) if abs(s[i]) >= 184), default=0)
    return round((len(s) - last) / 48000, 2)
base = "Comprising of 2 lines"
print("one full stop, middle (control):", max(silences(render(base + ". Then check."))))
print("two full stops typed, middle:", silences(render(base + ".. Then check.")))
for n in (500, 570, 650):
    print(f"middle [[slnc {n}]]:", max(silences(render(f"{base} [[slnc {n}]] Then check."))))
for n in (700, 750, 800):
    print(f"end [[slnc {n}]]: silence at the end", tail(render(f"{base} [[slnc {n}]]")))
