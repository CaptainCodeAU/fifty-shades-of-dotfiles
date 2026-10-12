import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from pauses import render, silences
V = "en-US:natural:male:Aaron:premium:5030"
for label, text in [
    ("status, as now", "done low risk."),
    ("status, with commas", "done, low risk."),
    ("short path", "`~/.local/bin/speak-clipboard` ."),
    ("long path", "`~/CODE/Scaffoldings/fifty-shades-of-dotfiles/docs/reference/speak-clipboard-pauses/results/` ,"),
    ("long path, last part only", "`results/` ,"),
    ("the command", "git -C ~/CODE/Scaffoldings/fifty-shades-of-dotfiles revert --no-edit 5b7523b."),
    ("item code", "W-20261012-A12"),
    ("commit hash", "`5b7523b` :"),
    ("file name", "`chars.py`"),
    ("sub-bullet with dash", "- Only Aaron at 440 wpm was measured."),
    ("sub-bullet without", "Only Aaron at 440 wpm was measured."),
    ("backtick + spaced full stop", "`fifty-shades-of-dotfiles` ."),
    ("no backticks", "fifty-shades-of-dotfiles."),
]:
    pcm = render(text, V, 440)
    sils, total = silences(pcm)
    lead = sils[0][1] if sils and sils[0][0] == 0 else 0
    print(f"{total - lead:5.2f} s  {label:<28} {text}")
