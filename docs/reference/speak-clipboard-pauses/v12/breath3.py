import subprocess, struct, time
voice, rate = "en-US:natural:male:Aaron:premium:5030", "460"
def render(text):
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0: time.sleep(2)
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", text], capture_output=True)
    n = len(r.stdout) // 2
    return struct.unpack(f"<{n}h", r.stdout[: n * 2])
def loud(s): return [i for i in range(0, len(s), 480) if max(abs(x) for x in s[i:i+480]) >= 184]
def gaps(s):
    L = loud(s); return sorted([round((b - a - 480) / 48000, 2) for a, b in zip(L, L[1:]) if b - a > 480], reverse=True)[:2]
def lead(s): return round(loud(s)[0] / 48000, 2)
def tail(s): return round((len(s) - loud(s)[-1] - 480) / 48000, 2)
A, B = "The change works", "Start here"
rows = [
 ("mid", "full stop (control)", f"{A}. {B}."),
 ("mid", "stop + slnc 150", f"{A}. [[slnc 150]] {B}."),
 ("mid", "stop + slnc 300", f"{A}. [[slnc 300]] {B}."),
 ("mid", "no stop, slnc 300", f"{A} [[slnc 300]] {B}."),
 ("mid", "no stop, slnc 500", f"{A} [[slnc 500]] {B}."),
 ("start", "nothing (control)", f"{B}."),
 ("start", "slnc 150", f"[[slnc 150]] {B}."),
 ("end", "full stop (control)", f"{A}."),
 ("end", "stop + slnc 300", f"{A}. [[slnc 300]]"),
 ("end", "stop + slnc 500", f"{A}. [[slnc 500]]"),
]
for where, name, t in rows:
    out = []
    for _ in range(3):
        s = render(t)
        out.append(gaps(s) if where == "mid" else lead(s) if where == "start" else tail(s))
    print(f"{where:5} {name:22} {out}")
