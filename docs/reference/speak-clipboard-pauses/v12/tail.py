import subprocess, struct, time
voice, rate = "en-US:natural:male:Aaron:premium:5030", "460"
pieces = {
    "end_with_pause": "A code block. Comprising of 2 lines [[slnc 500]]",
    "end_with_stop (control)": "A code block. Comprising of 2 lines.",
    "end_with_pause_1000": "A code block. Comprising of 2 lines [[slnc 1000]]",
}
def wait_idle():
    while subprocess.run(["pgrep", "-f", "perl - speak-clipboard-line"], capture_output=True).returncode == 0:
        time.sleep(2)
for name, text in pieces.items():
    wait_idle()
    r = subprocess.run(["say2", "-v", voice, "-r", rate, "--engine", "siri", "--format", "pcm", "-o", "-", "--", text], capture_output=True)
    n = len(r.stdout) // 2
    s = struct.unpack(f"<{n}h", r.stdout[: n * 2])
    last = max((i for i in range(n) if abs(s[i]) >= 184), default=0)
    print(f"{name}: rc {r.returncode}, audio {n/48000:.2f} s, silence at the end {(n-last)/48000:.2f} s")
