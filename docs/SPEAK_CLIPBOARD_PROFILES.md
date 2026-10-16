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

| Pause              | After                                               |
| ------------------ | --------------------------------------------------- |
| none               | a space, `"` `/` `*` `#`                            |
| about 80 ms        | `,` `...` `-` `--` dashes `)` `\|`                  |
| 110-130 ms, uneven | `;` `:` `. . .`                                     |
| 270-290 ms         | `.` `!` `?` `..` and any line break                 |
| 150 ms, steady     | `[[slnc N]]` for any N from 50 to 450               |
| N plus about 90 ms | `[[slnc N]]` from 500 up (500 -> 590, 1000 -> 1090) |

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
`chars.py` is the table above. `frag.py` times single pieces (a path, a command, a status line) for the reply-format test; `reply-sample.md` is the reply measured, `results/reply-v9.json` its pauses before v10. `sample.md` is Gavin's example. Both need
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

Added the same evening (v11, Gavin, after listening to v10): a path ending in
`/` is spoken as its last part and "sub-folder" (`~/CODE/.../results/` is
"results sub-folder"), and a slash command such as `/copy` is spoken as `the
"copy" slash command`. One word after a `/` with no other `/` counts as a slash
command, except a top-level folder name (`/tmp`, `/etc`, `/Users` and the like),
which stays as it is.

Changed 13 Oct (v12, Gavin, dotfiles-main, D-20261013-A02, D-20261013-A03): a
fenced code block is spoken as "A code block. Comprising of N lines." (1 line,
0 lines), where N is the lines between the fences, with a breath before and
after it. A breath also goes before every line that starts a section: one that
starts with `**` (a bold label) or with the `❯` status mark (Q3: 1). Detail
lines (`⋅`) and list items get none (changed 14 Oct, below: they now get a
beat).

Changed 14 Oct (Gavin, dotfiles-main, D-20261014-A08): every list item now
gets a beat in front, and a list of two or more items gets a rest after it:
in front of the next line, or at the end of the text if the list ends it.
With only a full stop between them, the items of a list ran together. A
list item is a line that starts with `-`, `*`, `+`, a bullet dot (`•`) or a
detail dot (`⋅`) and a space, at any indent; the marker is dropped. A line
indented deeper than the marker is the item wrapping and gets none. Where
two pauses meet, such as a `❯` line right after a list, the longer one
wins. Numbered items are unchanged.

The same day went through four versions: a breath around list items
(D-20261014-A03), then a beat before each item and after the list, with the
detail lines (`⋅`) counted as list items, which reverses that part of
D-20261013-A03 (D-20261014-A04), then a hold after the list (D-20261014-A05),
then a rest, a new pause word of about 0.75 s (Q9, Q10, D-20261014-A08).

A beat and a rest are made like a breath: a cut, with 350 ms (beat) or
600 ms (rest) of silence in front instead of 200 ms. At the end of a text a
beat is a full stop and `[[slnc 680]]`, a rest a full stop and
`[[slnc 950]]`. **Not measured yet.** The gaps are worked out from the
breaths (0.31-0.41 s with 200 ms); at the end of a text, `[[slnc 500]]` was
0.34 s and `[[slnc 680]]` 0.50 s on 13 Oct, without a full stop in front,
and 950 is that line carried on to 0.75 s.

Changed 14 Oct (Gavin, dotfiles-main, Q4: "every bold label gets 0.5",
D-20261014-A06): a bold label gets a beat after it. A bold label is a bold
span at the start of a line, after any list marker or list number,
that ends in `.`, `!`, `?` or `:` and has more text after it on the line.
Any length, so "What it means for you:" counts. Before, a label ending in a
full stop got a stop (about 0.22 s, D-20261013-A04) and one ending in a
colon got the shorter label pause (`pause_label`, 0.11-0.17 s), and only up
to three words. Bold inside a sentence, and a bold line on its own, are
unchanged. Not measured, like every beat.

Then (Gavin, Q6, D-20261014-A07): a status line, one that starts with `❯`,
keeps the stop after its bold name, as Gavin marked it on 13 Oct
(D-20261013-A04). Only the other bold labels get the beat.

### Pause words (Gavin, 13 Oct, Q4, Q5 and Q7)

Between Gavin and the agents, a pause is written as a word in triple curly
braces inside an example, such as `{{{breath}}}`. They are notes, never
commands: the speak key does not obey them. `--print` shows a breath it will
make the same way.

**Every time an agent shows Gavin a pause word, it also shows this table**
(Gavin, Q7: 2, "I'm not going to remember it and I don't want cognitive
load"). It belongs to speak-clipboard work, not to the reply style.

| Word           | How long                     | Made from                          | Where the speak key uses it now                         |
| -------------- | ---------------------------- | ---------------------------------- | ------------------------------------------------------- |
| `{{{tick}}}`   | About 0.1 s.                 | A comma.                           | Wherever the text has one.                              |
| `{{{stop}}}`   | About 0.25 s.                | A full stop or a middle dot.       | Wherever the text has one.                              |
| `{{{breath}}}` | About 0.35 s.                | A full stop plus a short silence.  | Before and after code blocks, and before section lines. |
| `{{{beat}}}`   | About 0.5 s (not measured).  | A full stop plus a longer silence. | Before each list item, and after a bold label.          |
| `{{{rest}}}`   | About 0.75 s (not measured). | A full stop plus a long silence.   | After a list of two or more items.                      |
| `{{{hold}}}`   | About 1 second.              | Not made yet.                      | Nowhere yet.                                            |

Measured ranges: tick 0.03-0.09 s, stop 0.22-0.36 s, breath 0.28-0.42 s.

### Status lines (Gavin's marked-up line, 13 Oct, D-20261013-A04)

Gavin marked the line he wanted:
`{{{breath}}} ❯ **Pause words.** {{{stop}}} ✓ done · {{{stop}}} ❕ low risk. {{{stop}}}`

- A middle dot is now a full stop (a comma since v10).
- Bold stars round a span ending in `.`, `!` or `?` are dropped. With them the
  voice lost the full stop's pause before a small letter: "**Pause words.**
  done" 0.04 s, without the stars 0.22 s; before a capital, 0.22 s either
  way. A label ending in a colon keeps its stars: without them its pause was
  shorter (0.17 s became 0.11 s).
- Measured on that line after the change: breath 0.28 s, 0.25 s after "Pause
  words", 0.36 s after "done". Before: 0.31 s, 0.05 s and 0.09 s.

### How a breath is made

Measured with the remote's voice (Aaron, 460 wpm), each case three times; the
voice gave the same result every time.

- In the middle of a text the voice pauses 0.24 s at a full stop, and a
  `[[slnc]]` after a full stop adds nothing. Without one, `[[slnc N]]` is
  0.08 s below 500 and 0.54 s at 500. Nothing in between, so a breath cannot
  be made inside one voice.
- So a breath inside the text is a cut: the press sends each part as its own
  voice, with 200 ms of silence in front (the player's per-voice gap).
- A breath at the start of a text counts only when the voice is queued after
  another, as the remote's pieces are. The first line of a press gets none.
- A breath at the end of a text is a full stop and `[[slnc 250]]`.
- Typing `..` adds no pause.

Tested by listening back, at Gavin's suggestion: a whole example reply was
cleaned, cut, rendered, joined with the gaps exactly as the player does, timed,
and written back to text with Whisper (`whisper-large-v3-turbo`, already on
the Mac). As one press: breaths 0.31-0.41 s, every other pause 0.30 s or less
(with a 110 ms gap the breaths were 0.20-0.32 s, no longer than a full stop).
Sent in pieces, as the remote does: breaths 0.29-0.42 s. Whisper heard no code
and no stray words.

### Known limits (v12)

- A code block copied from the terminal by mouse has no fence lines, so it is
  still read out (W-20261013-A01). `/copy`, which copies the Markdown, works.
- A terminal copy has no `**` either, so only `❯` lines get a section breath,
  and no bold label gets its beat (14 Oct). `/copy` keeps the stars.
- A reply that quotes a pause command, such as `[[slnc 500]]` in backticks, is
  read as "S L N C 500": the cleaner splits every `[[` so copied text can
  never command the voice. Do not quote one in a reply.
- `--skip` skips one voice, so a press cut by breaths, beats or rests needs
  one skip per part. A long list is now one part per item.

### The measuring runs and the speak key

At about 9:31 PM a `pauses.py` run with six Siri renders at once, while
Gavin's remote was queuing voices, hung renders for minutes; the remote went
silent and its line player ended three lines. `button_bunny-main` reported
it. `pauses.py` now renders one piece at a time, retries a timed-out render,
and waits while speak-clipboard's line player runs. Run it only with Gavin's
say-so in the session.

## When the sound began (Gavin, 13 Oct, Q8: 1)

A press at 11:23 PM seemed to make no sound. The press log showed it started,
and a second press stopped it 3 s later; nothing said whether any sound had
come out. The text itself was fine: it cleaned to 1,417 characters and all
three parts rendered with Aaron in 1.9-8.9 s, loud, with under 0.3 s of
silence in front. Blank lines and extra spaces were ruled out too: the cleaner
already trims both ends and squeezes runs of spaces and blank lines.

So the press log now says when the sound began:

- `mode=line pid=N outcome=sound after=0.69s fed=0.40s`: the player's own
  line, once its first voice is heard (ffplay's clock past the lead-in).
  `fed` is when the first audio reached ffplay.
- `outcome=no-sound ran=10.2s fed=...`: a line that ended with nothing heard.
- On a stop, toggle stop or replacing press: `sound=yes`, or
  `sound=none ran=3.14s fed=0.40s`. A stop is SIGKILL, so the player cannot
  log it; it keeps `~/.local/state/herdr/speak-line.sound` (pid, start, when
  heard, when fed) for the stop to read.

`fed` early and nothing heard means the audio was there and the device did not
play it. `fed=no` means the voice was still rendering.

**First readings, 11:36-11:40 PM.** Four presses were heard after 0.68-0.71 s.
One, at 11:38 PM, was stopped after 3.14 s with nothing heard (it ran before
`fed` existed). One more silent press, at 11:34 PM, ended itself after about
10 s with "ffplay's clock has not moved for 5 s ... (a stuck audio device?)".
That first reading (the audio device not starting) was wrong: see "Why some
presses were silent" below.

Tests: 14 checks (258 in all). A copy with the logging switched off fails the
13 that need it; the 14th, a sound file left by another player, is a control.

## Why some presses were silent (14 Oct)

Found by reading the Mac's own log (`/usr/bin/log show`, processes sirittsd,
say2, ffplay, coreaudiod, bluetoothd) for three silent presses and one that
worked, on 13 Oct.

**Cause: the voice parts reached the Siri voice service out of order.**
`sirittsd` renders one request at a time, in the order requests arrive. Since
v12 a press is cut at every breath into several voices, and the line player
started up to three renders at once. Whichever request got there first was
rendered first, and the player can only play voice 1 first:

| Press                | Order the requests arrived (characters)        | Result                   |
| -------------------- | ---------------------------------------------- | ------------------------ |
| 11:23 PM             | 481 first; voice 1 (165) never started         | stopped at 3 s, silent   |
| 11:34 PM             | 481, 737, then voice 1 (165), which waited 8 s | silent, then cut (below) |
| 11:38 PM             | 2,611 first, then voice 1 (437)                | stopped at 3 s, silent   |
| 11:38 PM, next press | voice 1 (437) first                            | heard after 0.68 s       |

Ruled out, with the same log: the audio set-up (every ffplay, silent or not,
went through the same steps, and the device ran); Bluetooth (the same warnings
in the good press); other audio at the same time (one iTerm alert at 11:38 PM,
absent from the other two); the stop at 11:38:12 PM (coreaudiod cleaned up in
8 ms); slow rendering (thermal state 0, normal sentence timings).

**Fix: renders in order.** A voice's render starts only once the voice before
it has sent audio, or ended. The service is serial anyway, so nothing is lost.

**Second fault: a false "stuck audio device".** The stall check timed
ffplay's clock from ffplay's start, not from its first audio. At 11:34 PM
voice 1 arrived 8 s late and was cut 10 ms after it went in. The clock is now
timed from the first audio. Also found by a new test: a stuck ffplay holding
under 0.5 s of audio never ended at all; with nothing played, any audio
waiting now counts.

**The restart (Q10: 1).** Built as asked: when nothing has played 1.5 s
after the first audio went into ffplay, a new ffplay is started, once per
line, and every voice it held is written again. It was chosen on the first
reading (the device), so it would likely not have helped these presses. It is
a safety net for a device that really does not start. Kept as that (Gavin,
14 Oct, Q11: 1).

**Code-block count (Q9 v2: 1).** "Comprising of N lines" counts only lines
with text; a blank line, or one of only spaces and tabs, is not counted.

**Leftover processes.** Gavin asked whether jammed players of the same kind
were checked for. At 12:03 AM on 14 Oct none were running: no line player,
say2 or ffplay. A press stops the previous player as a whole process group,
and the restart kills its own ffplay before starting another.

Tests: 270 in all. Each fix was taken out of a copy in turn, and each copy
fails its own new checks.

## Speaking from a remote herdr tab (Gavin, 16 Oct: Q22 (v2): 1, then Q26 / NP-2 Q4: 3)

A herdr key runs its command on the herdr server. In a `herdr --remote` tab the
server is codebox (Linux), so the speak keys ran speak-clipboard there, with no
Mac voice and nobody listening. herdr's own code shows this
(`src/app/custom_commands.rs`: every key command kind is started by the server),
and a remote press left nothing in the Mac's speak log while local presses did.

Now, on a box that is not a Mac, the nine speak-key commands are relayed, and
the Mac collects them:

- speak-clipboard writes one line, `<epoch seconds> <words>` (such as
  `--toggle` or `--set rate +20`), to `~/.local/state/herdr/speak-relay.queue`
  on the box and exits 0. Anything else runs on the box as before. Each press
  adds a `mode=relay result="queued"` line to the box's speak log.
- `speak-relay` on the Mac (`home/.local/bin/speak-relay`, a LaunchAgent,
  `com.captaincodeau.speak-relay`) keeps one plain ssh login to each box
  (`SPEAK_RELAY_HOSTS`, default `codebox.lan`) running `tail -F` on that file,
  with every port forward switched off for that login. A dropped link is
  retried, every 5 s at first and at most every minute.
- It runs `speak-clipboard` with a line's words only when they are exactly one
  of the nine commands in `home/.config/herdr/config.toml` and the line is at
  most 15 s old, so a stalled link never replays a burst. No shell is used.
  Everything else is logged as refused or stale. Log:
  `~/.local/state/herdr/speak-relay.log`.
- The Mac speaks its own clipboard. That holds the remote copy because of
  Q21: Claude in a herdr pane on codebox copies through the terminal
  (`docs/CLAUDE_LAUNCH_ENV.md`).

Why the Mac collects: the first build sent each press to port 8888 on the Mac
through a reverse ssh forward. codebox's lockdown refuses that by design
(`AllowTcpForwarding local`, Network_Plan CB D-008: codebox reaches nothing on
the LAN, the Mac included), and Gavin kept the lockdown (NP-2 Q4: 3). With the
Mac collecting, codebox opens nothing to the Mac, and the Mac listens on no
port.

The box is told apart by bash's `OSTYPE`, not `uname`: the selftest runs with
a PATH of stand-ins only, and a missing `uname` made the Mac look remote
(23 of 279 checks failed until it changed).

Tested on the Mac with a local stand-in for the ssh login and for the speaker:
all nine commands queued and ran; `--help` and a Mac press were not queued;
a line with extra words, a line 100 s old and a line of junk were refused or
dropped; after the link was cut it reconnected in 5 s and the next press ran;
a stop left no `tail` behind. The selftest passes 279 of 279. Live: the
LaunchAgent logged in to codebox, and a line queued there by hand at 3:37 AM
ran on the Mac.

The queue file grows by about 25 bytes a press; a refresh of codebox from its
golden copy starts it again.

`speak-relay --status` shows whether it is loaded and each box's last link
event; `--install` and `--uninstall` start it or stop it and trash the
LaunchAgent.

### What else a remote tab needs (16 Oct)

Three pieces have to line up, and each failed alone that night:

1. **The key must reach the far box.** `herdr --remote` uses the Mac's own
   keys by default, and the speak keys then did nothing at all: no line in
   codebox's speak log. `--remote-keybindings server` fixed it at once (Gavin's
   test, 3:44 AM: the Mac's relay log shows `codebox.lan ran '--toggle'`).
   `home/.zshrc` now exports `HERDR_REMOTE_KEYBINDINGS=server`, so no flag is
   needed. Background: `docs/HERDR.md`, "Two machines: the keymap drifts too".
2. **The copy must land on the Mac.** Claude on codebox copies through the
   terminal only when it believes it is over SSH; codebox's `claude()` sets
   `SSH_TTY` inside a herdr pane (Q21, `docs/CLAUDE_LAUNCH_ENV.md`). A Claude
   started before that change still copies to codebox until restarted.
3. **The press must reach the Mac.** The queue file and `speak-relay`, above.

Upstream: herdr issue #4833 (a remote copy lands on the far box's clipboard)
is the cause behind piece 2, still open on 16 Oct.

### After a restart (checked 16 Oct, 3:48 AM)

- **codebox reboots:** nothing on codebox has to be running for the relay;
  the queue file stays. The Mac's ssh login drops and is retried every 5 s,
  then at most every minute, so it comes back by itself. Proven by a real
  reboot (`qm reboot 205`, about 3:50 AM): the link ended at 3:49, three
  retries were refused while codebox started, and it reconnected at 3:50
  and stayed up.
- **codebox is refreshed from its golden copy** (Network_Plan
  `codebox-refresh.sh`): a plain refresh rolls back to the golden's dotfiles,
  which predate the relay and the Q21 `SSH_TTY` change. Only `update` /
  `regolden-current` pulls the dotfiles. Until a new golden is taken, pull
  `~/fifty-shades-of-dotfiles` on codebox after each refresh.
- **The Mac reboots:** the LaunchAgent starts at login, but its ssh login to
  codebox works only while the codebox key (`~/.ssh/codebox-admin`, which has
  a passphrase) is in the ssh agent launchd hands to jobs. Measured with a
  one-off launchd job: with that agent rc 0; with no agent rc 255
  ("Permission denied (publickey)"). After a reboot that agent starts empty,
  so the relay keeps retrying, once a minute, until the key is loaded again.

**The fix for a Mac reboot (Gavin, Q29: 1):** a key used for nothing else,
`~/.ssh/codebox-speak-relay` (ed25519, no passphrase, so no agent needed).
When the file exists, speak-relay uses it alone (`IdentitiesOnly`,
`IdentityAgent=none`), so the running link already behaves as it will after a
reboot. On codebox it is pinned in `authorized_keys` with `restrict` and a
forced command that only runs the queue's `tail` (added by NP-2 on Gavin's
NP-2 Q6, about 3:58 AM; kept in future goldens by Network_Plan c242b45).

Proved from a one-off launchd job with no ssh agent: the key logs in and the
tail runs (still running at 6 s); `id` through it printed 0 bytes; a reverse
forward with it was refused; a queue write sent through it never ran. Then
the LaunchAgent, on the key alone, ran a `--stop` queued on codebox at 4:00 AM.
Without the file, the entry's usual key is used through the agent.

## One speak key in every app: `cmd+option+backtick` (Gavin, 16 Oct: Q12 (v2): 2)

The herdr keys (`ctrl+alt+backtick`, `prefix+backtick`) only work inside herdr.
On 2 Oct Gavin asked for `cmd+option+backtick` at the macOS level, "the
convenience of using the same keyboard shortcut", with one firm rule: "I
didn't want the previous clipboard contents to be lost or overwritten", with
"the least downtime". Why the 2 Oct attempt was not kept: it was a herdr-only
build, undone on 3 Oct with no reason given; the every-app key itself was
never built (open item W-20261003-A06, parked).

**What it is:** `Speak Anywhere.app` in `~/Applications`, a small Swift
helper started at login by the LaunchAgent `com.captaincodeau.speak-anywhere`.
Source: `home/.local/share/speak-anywhere/SpeakAnywhere.swift` (what one
press does is written at its top). Build, install, status and self-test:
`speak-anywhere --install | --uninstall | --status | --selftest`.

**One press:**
- Speech playing: stop. Checked first, the same test as `speaker_alive`, so a
  stop never waits on a copy.
- iTerm2, Ghostty or Terminal in front: speak the clipboard, as the herdr key
  does (herdr owns the highlight there, and a drag has already copied).
- Any other app: the app's selected text through the accessibility API (the
  clipboard is never touched); if the app does not answer, snapshot every
  clipboard item and type, send `Cmd+C` once Command and Option are let go,
  wait up to 500 ms, read the text, put the snapshot back. Nothing
  highlighted: speak the clipboard.
- The text goes to `speak-clipboard --toggle --stdin`, so voice, speed,
  pauses and the cleaner are the same as every other key.

**Needs Accessibility** (System Settings > Privacy & Security >
Accessibility > Speak Anywhere) to read a highlight and send `Cmd+C`.
Catching the key needs none. Without it every press speaks the clipboard and
the log says `no-permission`. The app is signed ad hoc and macOS ties the
grant to that exact build, so `--install` rebuilds only when the source's
SHA-256 changes, and a rebuild needs the grant again.

**Asking whether it is trusted from a terminal measures the terminal.** The
first `--status` ran the check from this session's shell and said "trusted"
while the helper itself had logged "NO": a child process inherits the
responsible app's permission. The status now reads the helper's own log
lines (`start ok ... accessibility=`, then `accessibility granted`).

**Self-test (16 Oct, 12:42 PM, outside the sandbox, which cannot reach the
clipboard):** three arms. The live clipboard (1 item, 1 type) survives a
marker write and a restore. Two items with plain, rich and web text and a PNG
(10 types once macOS adds its own UTF-16 text) survive byte for byte. A copy
with one byte changed is told apart (the control). The first rich arm failed
because it compared against the list it wrote, not the clipboard's own
snapshot: macOS adds `public.utf16-external-plain-text` by itself.

**Log:** `~/.local/state/herdr/speak-anywhere.log`, one line per press: the
app in front, the path (`stop`, `terminal-clipboard`, `ax`, `copy`,
`clipboard`, `no-permission`), characters and milliseconds. Never the text.

**A switch that is on can still mean no permission (16 Oct, 2:05 PM).** The
first build started at 12:41 PM and asked for Accessibility, which made the
entry in System Settings. It was rebuilt at 12:42 PM, so the entry pointed
at a build that no longer existed: Gavin's screenshot showed the switch on,
and a restart at 2:05 PM still logged `accessibility=NO`. Removing the entry
with `-` and adding `~/Applications/Speak Anywhere.app` with `+` fixed it
(`accessibility granted` at 2:06 PM). So: never rebuild after the first start
without saying the grant must be redone.

**The clash that made two voices (16 Oct, 12:58 PM).** The Mac's own Speak
Selection was on `cmd+option+backtick` (speech prefs
`SpokenUIUseSpeakingHotKeyCombo = 2354`: key 50, the backtick, plus 0x900,
Command and Option), and Brave had custom menu shortcuts "Start Speaking" on
the same key and "Stop Speaking" on `cmd+option+1`. A press spoke the Brave
highlight in the Mac's voice and the clipboard through the helper, in either
order. The Mac's main shortcut list (`com.apple.symbolichotkeys`) holds
neither, so checking it alone missed the clash; app menu shortcuts are
`NSUserKeyEquivalents` in each app's domain. Gavin moved Speak Selection to
`cmd+option+2` (now 2323) and, on Q34: 1, both Brave shortcuts were removed.

## Who pressed: `source=` in the speak log (Gavin, 16 Oct: Q35: 1)

Every line `speak-clipboard` writes to `~/.local/state/herdr/speak-clipboard.log`
(a press, and a relayed press on a box that is not a Mac) now ends with
`source=<name>`, taken from the `SPEAK_SOURCE` the caller sets. Before, the
only clue was `ppid=`, a number to look up by hand that changes with every
restart.

| Caller                           | Sets                         |
| -------------------------------- | ---------------------------- |
| herdr's speak keys (config.toml) | `herdr`                      |
| `Speak Anywhere.app` (its plist) | `speak-anywhere`             |
| `speak-relay`, per box           | `speak-relay:<box>`          |
| anything else (T33Remap today)   | nothing, so `unknown`        |

Only letters, digits and `. _ : -` are kept, at most 64 characters, so a
caller cannot write anything else into the log. The helper's name is set in
its LaunchAgent, not in its code, because a rebuild loses the Accessibility
grant; the app in front stays in the helper's own log, at the same second.
Tests: 4 new arms (unset, given, unsafe characters cut, a relayed press), 283
of 283 pass.

**A changed key command needs `herdr server reload-config`, not `prefix+r`.**
herdr runs a key's command in its server, and `prefix+r` reloads only the
client (docs/HERDR.md, "the keymap drifts too"). After `prefix+r` at about
4:15 PM, herdr presses at 4:15 and 4:18 PM still logged `source=unknown`; the
server had run since 13 Oct. `herdr server reload-config` answered
`"status":"applied"` with no diagnostics at 4:19 PM.

## A voice that ran 2.5 times too slow at exactly 440 (16 Oct, 3:01 PM; Q36: 1)

Gavin heard a herdr press start slowly and then pick up. The first part of
the text (cut at the first pause mark) was "Got it. From now on, anything
for win_go_app_test goes from this session straight to win_go_app_test-main
by message. You will not get words to type for it." Measured with the
player's own say2 call (`--engine siri --format pcm -o -`):

- at `-r 440` it is 9.33 s, every time (3 live streams, a file render, a
  repeat); at 436, 438, 439, 441, 442 and 444 it is 3.75 s; at 175 it is 4.09 s
- "Got it." plays at normal speed; everything after it in that part about
  2.5 times slower than at 430 or 450
- the fault is in Apple's engine, not say2: `-r 440` is native rate
  2.5142857, and `--rate 2.5142857142857142` (and 2.51428571) gives 9.33 s
  while 2.514285 gives 3.75 s
- small word changes avoid it too ("Okay." for "Got it.": 3.93 s)
- 40 random paragraphs of this doc at 430, 440 and 450: none affected; the
  bad text, run first as the control, was caught

Why one step matters, as far as can be seen from outside: the engine likely
works out how long each sound lasts from the speed, and at that one exact
number, for that sentence, takes a wrong turn (a rounding edge). One word a
minute moves the number off the edge. That is an inference, not a measurement
of Apple's code.

Fix (Gavin, Q36: 1): both profiles moved from 440 to 441 wpm, which cannot
be heard; the same text is 3.77 s at 441. Other text may hit the same fault
at another speed, rarely; nothing here detects it. If it recurs, the next
step is a guard in the player that re-renders a part whose audio is far
longer than its text needs (Q36 option 2).

## Spoken alerts: `speak-alert` (Gavin, 16 Oct: Q43 (v2): 1; engage #2092 item 2)

`ci-watch` ("dotfiles C I just went red", and a reminder after 3 days red) and
`ccw-watch` ("Capture cannot be confirmed") used to POST their alerts to
`localhost:31337/notify` (LifeOS's Pulse, retired 16 Oct) and `localhost:8888/notify`
(dead for weeks). Nothing listened, both threw the failure away, so every alert was
silently lost, and anything that later listened on those ports would have received
them. Found by engage-main; verified: nothing listened on either port.

Now both call `speak-alert`, which knows four alerts and nothing else:

| Alert | Words |
| --- | --- |
| `ci-red <label>` | Heads up. `<label>` C I just went red. |
| `ci-reminder <days> <label>` | Reminder. `<label>` C I has been red for `<days>` days. |
| `ccw-unconfirmed` | Heads up. Capture cannot be confirmed. |
| `ccw-reminder <days>` | Reminder. Capture has been unconfirmed for `<days>` days. |

`<label>` is 1-60 of `A-Za-z0-9 . _ / @ -` and space, not starting with a space or
`-`; `<days>` is 1-4 digits (`ci-watch`'s `alert_label` trims a label to fit).

- **On the Mac:** `speak-clipboard --queue --stdin`, so an alert waits behind a reply
  being read instead of cutting it off. The speak log names it `source=ci-watch` or
  `source=ccw-watch`.
- **On another box (codebox):** one line `<epoch> --alert <alert> <fields>` in the
  speak-relay queue. `speak-relay` on the Mac matches it against the four shapes
  EXACTLY (`alert_args`), runs `speak-alert` with the fields and no shell, and
  `speak-alert` checks them again and builds the words. A box can pick an alert and
  fill its fields; it can never choose the words. Same queue file, same forced-command
  key, no new path from the box to the Mac (NP-2 agreed, 16 Oct).
- `speak-relay --check-line WORDS` shows what a queue line would run, without running it.

Tests: `speak-alert-selftest`, 24 checks (the four alerts word for word, 13 bad alerts
refused with a 60-character control, the Mac path through a stand-in speaker, the
queue line off the Mac, the relay's shapes and 8 refusals, both watchers off the old
addresses). Against a `speak-alert` that refuses nothing, 3 checks fail. The watchers'
own suites still pass: `ccw-watch-selftest` 45, `ci-watch-selftest` 168.

## A key press stops only a key's speech (Gavin, 17 Oct: Q45: 1)

At 12:05 AM a herdr press started reading 3,142 characters; at 12:06 AM T33Remap
read a reply with a plain press, which replaced it (`outcome=replaced`). At 12:07:43
AM Gavin pressed again while a T33Remap "needs you" notice played: the toggle rule
("any press while speaking stops") stopped the notice and read nothing, and two
seconds later T33Remap spoke another notice. Headphones and volume were fine; every
press logged `outcome=sound` within 0.7 s.

Now the pid file's fourth line records the mode of the press that started the line.
A `--toggle` press stops the speech only when a `--toggle` press started it (or the
file predates this, with no fourth line). Speech started any other way, such as
T33Remap's plain presses, is replaced by the key's own text, logged `outcome=replaced`.
A second key press then stops it, as before.

The other half, T33Remap queueing its automatic speech behind a key's reading
instead of replacing it, is button_bunny's, asked of `understander`.

Known gap until Speak Anywhere's next rebuild (W-20261016-A04): the helper checks
"is anything speaking" itself and then runs `speak-clipboard --toggle` with no text.
In a non-terminal app, a press during T33Remap's speech therefore reads the CLIPBOARD,
not the highlight. A press when nothing speaks reads the highlight as before.

Tests: 3 new arms (a key press during a plain press's speech is `replaced` and reads
its text; a second key press stops it). Four older stop tests started their speech
with a plain press, the way T33Remap does, and now start it with `--toggle`, which is
what their names test. 286 of 286 pass.
