# speak-clipboard: profiles and `--queue` (built 2026-10-10, v8); pauses and lead-in (2026-10-12, v9)

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
`--get`, `--reset` with an unknown profile. `--print` gets the stderr line
only, no notification (12 Oct Q20). A bad value given with an unknown profile:
a press reports the value (2 or 3), `--set` reports the profile (6) (12 Oct
Q21 v2). Both in "Lock and exit-code rulings" below.

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
- `--stop` and `--skip` always win: they wait up to 6 s for a press that is
  still running, never "busy" (12 Oct Q19, below).

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

## Lock and exit-code rulings (2026-10-12, D-20261012-A07)

Gavin answered four questions in session dotfiles-main on 12 Oct (numbered
there Q18-Q21; not the Q18-Q21 of the 9-10 Oct design above). Open item:
W-20261011-A05. Each has a selftest check, and each new check failed on the
script before the fix, except Q21's, which proves behaviour that was already
right. Selftest: 212 checks.

- **A lock file that cannot be opened is an error, never busy (Q18).** Until
  now a `speak-clipboard.flock` that could not be opened (a folder in its
  place, a state folder that cannot be written) was reported as busy, exit 0,
  so every press did nothing in silence. Now: **exit 7** (new), a stderr line
  naming the file, a notification naming it unless `--no-notify`, and
  `outcome=lock-unopenable` in the log. A lock that another press holds is
  still busy, exit 0, quiet.
- **Stop and Skip always win (Q19).** A `--queue` press holds the lock while it
  waits up to 5 s to join the line, so a `--stop` or `--skip` in that window
  used to be busy and do nothing. `--stop` and `--skip` now wait up to 6 s for
  the lock, longer than that join wait. Every other press still gives up at
  once (key repeat must stay busy).
- **`--print` never notifies (Q20).** `--print` with an unknown profile prints
  the error and exits 6, with no notification: it is typed in a terminal, so
  the error is already on screen. A press with an unknown profile still
  notifies, because a hotkey has no screen.
- **A bad value with an unknown profile (Q21 v2).** On a press the value's
  error wins: `--rate 900 --profile nosuch` is exit 3, because press options
  are checked as they are read. `--set` checks the profile first:
  `--set rate abc --profile nosuch` is exit 6, because a step (`+20`) or a
  voice number needs the profile's values before it can be checked. Gavin
  ruled to leave both as they are. Q21 v1 said the value error wins for `--set`
  too, which was not true of the script; A07 replaces D-20261012-A06 for that
  reason.

## Pauses (v9, 2026-10-12)

Asked in session dotfiles-main-2 (numbered there Q2-Q5) with Gavin's own
example: a "Found and Did" summary with a heading, numbered items with bold
titles, and "Found:" / "Did:" lines. Two problems: a heading or an item's
title ran straight into the next words (the cleaner joins every line into
one), and the pause after "Found:", "Did:" or "2." went anywhere from none
to about 290 ms.

### What the voice can do (measured, Aaron, 440 wpm)

Each mark measured in three sentences (`chars.py`, below); the middle value:

| Pause                         | After                                            |
| ----------------------------- | ------------------------------------------------ |
| none                          | a space, `"` `/` `*` `#`                         |
| about 80 ms                   | `,` `...` `-` `--` dashes `)` `\|`               |
| 110-130 ms, uneven            | `;` `:` `. . .`                                  |
| 270-290 ms                    | `.` `!` `?` `..` and any line break              |
| 150 ms, steady                | `[[slnc N]]` for any N from 50 to 450            |
| N plus about 90 ms            | `[[slnc N]]` from 500 up (500 -> 590, 1000 -> 1090) |

So there is no pause between about 150 and 500 ms, and no punctuation gives
a short steady one; `[[slnc]]` does. After a list number, `[[slnc 150]]`
measured only 70-100 ms and a full stop about 215 ms.

### Settings (Q3 v2: the voice's own pauses)

Per profile, each `none` (the text as it was), `short` (`[[slnc 150]]`),
`sentence` (a full stop) or `500`-`5000` (`[[slnc N]]`):

- `pause_title` (default `sentence`, Q2-a): after a line that ends without
  punctuation where the break was meant: a blank line follows, or the next
  line's first word would have fitted on it. A wrapped line is full up to the
  widest line of the selection, so it gets none.
- `pause_label` (default `short`, Q2-b): after one to three words and a colon
  starting a line, as in `Found:`.
- `pause_number` (default `sentence`, Q2-c and Q4): after `1.` or `1)`
  starting a line.

The cleaner marks the spots while the lines are still apart and writes the
pauses after the join. Copied text still cannot add a speech command: `[[` is
split before, and the mark bytes are dropped with the rest of non-ASCII.

### lead_in (Q5)

Gavin heard the first word or two go missing at times. Measured on 12 Oct:
one player at a time, however fast the presses (six 0.3 s apart: started,
then replaced x5; six at the same instant: one ran, five busy; nothing left
after `--stop`). The output was Bose QC headphones over Bluetooth, which drop
the start of sound while they wake. `lead_in` (ms, 0-2000, default 300) is
silence written in front of the first voice of a new line only, never in
front of a queued voice. Whether 300 is enough is for Gavin's ears.

### Measured on the example (before -> after)

Heading 0 -> 330 ms; item titles 0/190/0 -> 280/260/270 ms; `Found` 220/0/150
-> 120/110/130 ms; `Did` 50/0/0 -> 150/120/180 ms; numbers about 215 ms
either way. The renders are repeatable: two runs of the same text gave the
same pauses to the 10 ms.

### Tools

`docs/reference/speak-clipboard-pauses/`: `pauses.py` measures every pause in
a text and labels it by the words before it, by rendering the text cut off
at each break; `--compare A.json B.json` shows two runs side by side.
`chars.py` is the table above. `sample.md` is Gavin's example. Both need
say2, so they run outside the Claude sandbox.
`results/` holds the runs behind every number in this section: `before.json`
and `before-2.json` (v8, two runs, identical), `after.json` (v9 defaults),
`chars-440.json` and `slnc-440.json` (the table), and `try-*.json` (the
label and list-number trials that settled Q3 and Q4). Each holds the spoken
text, so a run can be repeated. Recordings (`.wav`) are not kept: run
`pauses.py` again to make one.

### Known limits

- Measured with Aaron at 440 wpm only. Simone, and other rates, may pause
  for other lengths; `chars.py --rate N --voice KEY` measures them.
- `pauses.py` gives a silence to the break whose cut-off piece ends nearest
  to it. Two breaks under about 0.15 s apart can swap: "2." after "added it."
  reads 40-90 ms in every trial, while "1." and "3." read about 215 ms.
- A recording from `pauses.py` comes straight from say2, so it has no
  lead-in; only the line player adds one.
- Whether 300 ms of lead-in is enough for the Bluetooth headphones is not
  measured: it needs Gavin to listen.

### Also found

- Six presses at the same instant wiped `speak-clipboard.log` (each trims it
  through the same temp name at exit). W-20261012-A09.

## The reply format, spoken (v10, 2026-10-12)

Gavin's terminal replies follow his reply style
(`~/CODE/CaptainCodeAU/CaptainCodeAU-isolinear/reference/reply-style/STYLE.md`).
One whole reply, as an example, spoke for 79 s. Timed piece by piece (Aaron,
440 wpm): the `❯` and `⋅` markers, backticks, a space before a full stop and a
dash on a sub-bullet cost nothing; a status line "✓ done · ❕ low risk" ran
together as "done low risk" (the cleaner dropped the `·`); a code block's
command took 2.9 s; a long path 2.2 s against 0.2 s for its last part; an item
code like W-20261012-A12 1.4 s and a commit hash about 1 s.

Gavin chose (dotfiles-main-2 Q6-Q8):

- Q6: a middle dot between words is a comma: "done, low risk".
- Q7: a fenced code block is spoken as "Code block." and no more. An unclosed
  fence is read as it is. A code block copied from the terminal, where Claude
  Code draws it without the fences, is still read.
- Q8: a path with two or more slashes is spoken as its last part. It counts
  as a path only when it starts at `~`, `/` or `.`, or ends in a file name
  with an extension, so a URL, a date and "and/or/not" are left alone. A
  full stop ending the sentence stays.

Item codes and commit hashes are still read in full; not asked.

### The measuring runs and the speak key

At about 9:31 PM a `pauses.py` run with six Siri renders at once, while
Gavin's remote was queuing voices, hung renders for minutes; the remote went
silent and its line player ended three lines. `button_bunny-main` reported
it. `pauses.py` now renders one piece at a time, retries a timed-out render,
and waits while speak-clipboard's line player runs. Run it only with Gavin's
say-so in the session.
