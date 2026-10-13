import wave, struct, sys
w = wave.open(sys.argv[1]); n = w.getnframes(); s = struct.unpack(f"<{n}h", w.readframes(n))
out, start = [], None
for i in range(0, n, 480):
    q = max(abs(x) for x in s[i:i + 480]) < 184; t = i / 48000
    if q and start is None: start = t
    if not q and start is not None:
        if t - start >= 0.04 and start > 0.05: out.append((round(start, 2), round(t - start, 2)))
        start = None
print("silences (start s, length s):", out)
