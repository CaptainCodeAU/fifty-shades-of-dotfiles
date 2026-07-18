# Cross-project comms — outbound change-notes

> Dated, OUTBOUND notes addressed to projects that depend on this one. Each is a self-contained
> "here's what changed on my side / here's my answer" message — a point-in-time record of what a
> given dependent was told, and when.

> **Spec version adopted: v1.15** — see `CONVENTION.md`. Keep this line accurate: it is how the
> operator answers "is everyone on the same page?" with one grep instead of four conversations.

## ⚠️ Read on-demand ONLY — do not front-load

Open a recipient's notes only when that project is explicitly in scope. Not auto-loaded anywhere,
by design — but DO list comms/ in the master docs index, or it's undiscoverable (R5).

## Timezone

All note timestamps are local time — **Australia/Melbourne**. Stated once, here, so it isn't
copied onto every filename. If this project's machine or zone ever changes, amend THIS line;
never retro-edit filenames.

## Layout

`docs/comms/<recipient>/<YYYY-MM-DD>T<HHMMSS>_<topic>.md` — one subfolder per recipient;
timestamped files inside; newest = the current dispatch, older = history. Read newest-first.
The filename records filing; each note's `Relay state:` line records delivery.

## Recipients

| Recipient    | What it is | Latest |
| ------------ | ---------- | ------ |
| _(none yet)_ |            |        |

<!-- Add a row only when a recipient folder exists — i.e. when its FIRST real note is filed.
     Row shape:
     | [`<name>/`](<name>/) | <one line: who they are + relationship to this project> | [`<newest file>`](<name>/<newest file>) |  -->

> The `Latest` column MUST be updated whenever a new note is filed — in the SAME commit (R4).
