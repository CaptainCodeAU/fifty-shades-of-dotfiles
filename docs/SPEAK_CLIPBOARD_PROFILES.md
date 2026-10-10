# speak-clipboard: profiles and `--queue` (built 2026-10-10, v8)

Designed 2026-10-09/10 in session dotfiles-main with Gavin, by listening tests
(demos 1-6 below). Every rule here cites the question that settled it
("Q14" = dotfiles-main Q14). Open item: W-20261009-A03. Script:
`home/.local/bin/speak-clipboard`. Built from this plan in the next session;
where the build had to choose something the plan left open, "As built" at the
end says what and why.

## Why

Gavin sometimes needs two kinds of text spoken back to back, fast, in
different voices. Today every press stops whatever is speaking, there is one
set of settings, and a second voice means `--voice`, which skips streaming.

## Profiles

A profile is a full set of the four settings: `rate`, `volume`, `voice`,
`notify`. Any of them can differ; two profiles may share a voice. `notify` is
per profile, not global (Q14 v2: "I don't see a reason why you wouldn't allow
flexibility").

### Settings file: one block per profile under a heading (Q14 v2: B)

```
# speak-clipboard settings
[aaron_fast]
rate=440
volume=70
voice=en-US:natural:male:Aaron:premium:5030
notify=on

[simone_fast]
rate=440
volume=70
voice=en-US:natural:female:Simone:premium:5029
notify=on
```

- Read with bash builtins only (`read`, `case`), as today: no library, no fork.
- Whole-line comments only, starting `#` or `;`. A comment after a value is not
  supported.
- Rejected: name prefix on every line (A), one file per profile (C: "makes no
  sense"), today's flat file plus prefixed extras (D: "ugly and lazy", two
  styles in one file).
- Warnings (shown by `--settings`, logged on a press), because B's failure mode
  is a lost or mistyped heading moving a block into the profile above:
  a setting above the first heading; a setting twice in one profile; a profile
  missing a setting (the built-in default is used, exit 10 as today).
- Profile names: letters, digits, `_`, `-`. No spaces (every hotkey would need
  quotes) and no dots (ambiguous in `--get` output such as `aaron_fast.rate`).

### Which profile a press uses (Q15: 1)

`--profile NAME` picks one. Without it, the **first profile in the file** (not
counting `_REMOVED` ones). No `default=` line: it would sit outside every
heading, the mixed style rejected in Q14.

### Unknown profile is refused (Q16: refuse)

`--profile NAME` naming no profile: nothing spoken, a notification naming the
missing profile, **exit 6** (new: "no such profile"). Never falls back to
another profile: "it'll become difficult to debug". The same for `--set`,
`--get`, `--reset` with an unknown profile.

### Commands

- `--profiles`: list every profile with its settings; mark the first. (Q24)
- `--new-profile NAME`: a copy of the first profile; refused if NAME exists.
  No `--from` (Q13 v3). A `--set` on a missing profile is refused (exit 6), so
  a typo cannot create a stray profile (Q13 v2).
- `--remove-profile NAME`: renames the heading to `NAME_REMOVED`. Hidden from
  `--profiles`, unusable by `--profile`; only a hand edit deletes it. (Q24)
  If `NAME_REMOVED` already exists, the next is `NAME_REMOVED_2`, and so on.
  Refused for the last usable profile.
- No rename command (Q24, not chosen). Editing the file by hand always works.
- `--set`, `--reset`, `--get`, `--settings` all take `--profile`; without it
  they act on the first profile.

### Migration

A flat (pre-profile) file is rewritten once into one block named `[default]`.
On this machine the file is written by hand at build time as `[aaron_fast]`
(today's values: 440, 70, Aaron premium, notify on) and `[simone_fast]` (the
same, with Simone premium), as Gavin asked.

## Waiting in line: `--queue [MS]`

- A flag on the command, never a profile setting (Q12: 1, "flexible and easily
  programmable"). It goes on the **second** press: a press with `--queue` that
  finds speech playing waits for it instead of stopping it. Without `--queue`,
  a press behaves as today.
- Optional delay in milliseconds before that voice starts: `--queue` = 0,
  `--queue 150` = 150 ms. Whole numbers 0-5000; anything else exit 3.
  Part of `--queue`, not a separate `--gap` (Q19 v3; seconds were rejected as
  too coarse).
- No limit on how many wait (Q22). Presses under 0.5 s apart are ignored as key
  repeat (busy, exit 0), as the lock does today.
- `--toggle` with `--queue` is refused, exit 2: they contradict (Q21).
- A press without `--queue` while a line is waiting: clean slate. The current
  voice stops, the line is cleared, the new text speaks now (Q23 v2).

### Stopping (Q25)

- `--stop`: silence. Current voice stopped and the line cleared (today's
  meaning, so existing hotkeys keep working).
- `--skip` (new): stop the current voice only; the next in line plays.
- A `--toggle` press while speaking acts as `--stop`.

### How it plays: one player, volume inside the audio (Q17, Q18: 1)

All voices in a line go through **one** `ffplay`, at `-volume 100`. Each
voice's own profile volume is applied to its samples before the player
(samples x volume/100, the same linear scale `ffplay -volume` uses, so a
profile sounds as loud as it does today). The delay is that many ms of zero
samples written into the stream, exact to the sample.

Why: demos 2, 3 (two players) gave a faint crackle at 3 of 4 changeovers and
about 0.5 s of extra silence; demo 5 and 6 (one player) gave no crackle in
three runs and the shorter gap.

Text is never written to disk (as today): a waiting press keeps its text in
its own memory, renders it while it waits, and writes its audio into the
running player's stream when its turn comes. Rendering early also hides
say2's occasional slow renders (2-16 s, seen 3 times in about 30, cause
unknown) behind the voice that is speaking.

### Every voice streams

A voice chosen by a profile or by `--voice` uses the same streaming path as
the saved voice does today. (Today `--voice` skips it and a long selection
waits for the whole render: 35 s of silence on 3,360 chars.)

## Tests (Gavin: "make sure all the tests are there and done")

`speak-clipboard --selftest`: runs in a temp folder with stand-ins for say2,
ffplay, osascript and herdr; no speech, no real notification; exits non-zero
if any arm fails. Arms for: file format and every warning, profile selection,
exit 6, `--new-profile`, `--remove-profile` (including `_REMOVED_2`),
`--profiles`, migration, `--queue` with and without a delay, the delay byte
count, the volume step (samples scaled exactly), `--skip`, `--stop` clearing
the line, the clean-slate press, `--toggle --queue` refused, key repeat, and
the existing settings and exit-code behaviour. Closes W-20261008-A05.

## Evidence: the listening tests (2026-10-09/10)

Prototype, kept as a record: `docs/reference/speak-clipboard-try-back-to-back.sh`
(`1`-`6`, `--swap`, `--silent`; demo 6 holds the one-player volume step). Profile A:
Aaron 440 wpm vol 70; B: Simone 380 wpm vol 60, unless stated.

| Demo | What                                                 | Heard by Gavin                                                       | Measured                            |
| ---- | ---------------------------------------------------- | -------------------------------------------------------------------- | ----------------------------------- |
| 1    | B cuts A off after 3 s                               | clean switch; A stopped at "long enough that there"                  | B started ~0.1 s after the cut      |
| 2    | B waits, rendered after A ends (two players)         | slightly more gap than demo 1; faint crackle before the second voice | second voice 3.49 s                 |
| 3    | B waits, rendered while A plays (two players)        | same as demo 2; crackle came and went                                | second voice 3.47 s                 |
| 4    | A and B at once                                      | the louder, longer voice drowned the other                           |                                     |
| 5    | A then B through one player, vol 70                  | no crackle, two runs                                                 | 8.05 s vs 8.57 s with two players   |
| 6    | Simone vol 70 then Aaron vol 40, 440 wpm, one player | Aaron slightly quieter, no crackle                                   | peak 26,846 -> 10,738 at 40 (exact) |

Voice switching costs nothing measurable: Aaron/Simone renders 0.10 s either
way, and both render at once without loss (0.13 s each).

## As built (2026-10-10)

Everything above is built as written. These are the points the plan left open,
or where the build had to choose; each is a judgement call, open to change.

- **Who renders a waiting voice.** The plan has the waiting press render it in
  its own memory. Built: the press hands its text to the line's player
  through a named pipe (`speak-line.fifo`, kernel memory, never disk), and the
  player renders it at once, while the current voice plays. Same effect (text
  never on disk, slow renders hidden), one process doing the ordering.
- **How the player knows what you hear.** It reads ffplay's own playback clock
  (the `-stats` status line on stderr). The next voice goes into the stream when
  the current one has 0.3 s left, so only the voice you hear is in ffplay's
  buffer. That is what lets `--skip` drop exactly that voice: killing ffplay is
  the only way to take audio back out, and the next voice starts in a fresh
  ffplay. If ffplay ever stops printing that line, the player falls back to a
  wall-clock guess (selftest arm "no clock line").
- **The gap applies only when the voice waits.** A `--queue 150` press with
  nothing playing speaks at once, with no silence in front.
- **Key repeat (0.5 s) counts `--queue` presses only**, against the last
  `--queue` press. A plain or toggle press keeps today's lock-only rule.
- **Exit 6's notification is sent whatever `notify` says** (`--no-notify`
  skips it): it is an error from a hotkey with no screen, not a settings change.
- **Refusals:** `--new-profile` with a taken, bad or `_REMOVED` name, and
  `--remove-profile` on the last usable profile, exit 3 (bad value);
  `--remove-profile` on an unknown name exits 6.
- **Two more file warnings** beyond the plan's three: a heading that is not a
  valid name (its block is not used), and a heading that appears twice (both
  blocks count as one profile). Line numbers in warnings are the file as it is
  after any put-back.
- **The file is edited in place**: a `--set` changes only its own line, so
  comments, order and blank lines stay. A put-back setting goes after its
  block's last setting.
- **Engine cache**: one line per voice, so two profiles with different voices
  do not re-probe say2 on alternate presses.
- **A `--queue` press that finds a pre-v8 speaker** (one started before the
  update) replaces it: there is no line to join.
- **Measured with the real say2 and ffplay at volume 0** (silent): one press
  2.37 s against 2.30 s for the v7 pipeline; two voices 3.7 s for 3.19 s of
  audio; after `--skip`, the next voice plus a fresh ffplay start in 1.66 s. A
  cold first render of the second voice added about 1.4 s of silence once,
  when it was queued only 1 s into the first: rendering early hides a slow
  render only when there is time to hide it.
- **Keys** (Gavin, 2026-10-10): none for the second profile or `--queue`;
  those are run from code. By hand, in herdr: ctrl+alt+6 `--skip`, ctrl+alt+7
  `--stop` (a stop that never starts speech, unlike the speak key).

## Review fixes (2026-10-10)

Four reviewers (settings file, line player, command line, the selftest itself)
found about 80 items; Gavin chose to fix all four groups. Each fix has a
selftest check, and the new checks were run against the previous script
(572ffa2): 49 of them fail there, 203 of 203 pass now (bash 5 and 3.2).

- **Key repeat narrowed (Gavin, 2026-10-10, changing Q22; ruling D-20261010-A04):** the 0.5 s rule
  counts only `--queue` presses that read the clipboard. A `--stdin` press is
  code, and code may queue two voices in a row.
- **Settings file:** a file that cannot be read is never written over (it used
  to be replaced by `[default]`); writes take `speak-settings.flock` and read
  the file again under it (six `--set rate +20` at once lost steps); one write
  whose size is checked before the rename; a temp name of the run's own; CRLF
  line ends, a byte-order mark and spaces around `=` or a heading are read; a
  line that is not a setting is warned about.
- **The line player:** a clock that stops for 5 s with audio waiting ends the
  line with a note (it used to run for ever, and `--queue` voices went
  nowhere); a say2 that sends nothing for 30 s is stopped; an ffplay that dies
  takes only the voice it was playing, and the rest go on in a new one; "nan"
  status lines mean nothing has played yet (a cold device); with no status
  line, the wall-clock guess does not count silence; a failed voice leaves no
  gap; the player always finishes under `speak-line.flock` and reads the pipe
  while it waits for it; it starts before the first voice is written, so a
  long message cannot block.
- **Command line:** one command per run (exit 2); empty values and values that
  are another option are refused; no leading zeros (`0440` was stepped as
  octal); `--get` with no key before another option; `[[` cannot survive the
  cleaner; link text between hyperlinks is kept; a corrupt engine cache line
  is ignored; `--set` re-runs itself through `$BASH`, so a bare name or a
  missing execute bit no longer fails after saving.
- **The selftest:** its arms reach only stand-ins and a few linked system
  tools (never the real `say`), run in a clean environment, never touch the
  real state, stop every stand-in they started, and wait on conditions rather
  than sleeps. The stand-ins can start cold, freeze, die, render slowly, fail
  or hang. It reports a lost or added check against the expected count (203).
- **Left as they are:** `--get` prints the value a command would use (flags
  included); a `--queue` press that resolves to the `say` fallback (no
  premium voice) replaces the line, since `say` cannot stream; the settings
  file is written as a plain file, so a symlinked one would be replaced (it is
  not symlinked on this machine). Gavin ruled on 2026-10-10 that all three
  stay as they are (W-20261010-A21).
