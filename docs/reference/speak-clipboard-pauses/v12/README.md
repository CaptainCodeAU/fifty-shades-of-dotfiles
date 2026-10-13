# speak-clipboard v12 measuring scripts (13 Oct 2026, session dotfiles-main)

Kept from the session that built the v12 breaths and status-line pauses. Each renders text with
say2 the way the line player does, times the silences (10 ms windows, -45 dBFS), and some write
it back to text with mlx-whisper. They use the Siri service Gavin's remote uses: run only with
his say-so, one at a time. Outside the Claude sandbox.

- `listen.py SCRIPT SAMPLE OUTDIR whole|remote`: a whole reply as one press, or in pieces like
  the remote; prints each breath against every other pause and what Whisper heard.
- `words.py SAMPLE OUTDIR [SCRIPT]`: one text, Whisper word times between each pair of words.
- `sil.py WAV`: every silence in a WAV.
- `pairs.py`, `breath3.py`, `sweep.py`, `tail.py`: the pause-size sweeps quoted in
  docs/SPEAK_CLIPBOARD_PROFILES.md.
- `verify.py`, `hear.py`: the first listen-back checks of the code-block wording.
- `example.md`, `target.md`: the sample reply and status line used.

W-20261013-A04 is to turn this into one command.
