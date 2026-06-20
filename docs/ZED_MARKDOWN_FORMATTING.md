# Zed Markdown Formatting (`md-hardbreak`)

On-demand formatting that keeps a Markdown **source** file clean while making its
rendered **preview** show the line and paragraph structure you actually typed.

The exhaustive reference is the script's own header:
[`home/.local/bin/md-hardbreak`](../home/.local/bin/md-hardbreak). This page is the
overview, the Zed wiring, and the rationale - it links to the script rather than
duplicating it, so the two cannot drift.

## The problem

Zed's Markdown preview follows CommonMark, so by default:

- a single newline inside a paragraph collapses to a space (your separate lines run
  together onto one line), and
- a blank line is only a paragraph break, and its gap size is hardcoded in Zed with
  no user setting (`buffer_line_height` only changes the scroll step; `ui_font_size`
  scales the whole UI).

So the only lever is the source markup, which `md-hardbreak` edits using characters
that stay invisible (or nearly so) in the raw file but change what the renderer draws.

## What it does (composable flags)

| Flag       | Effect                                                                                                          |
| ---------- | --------------------------------------------------------------------------------------------------------------- |
| `--breaks` | Two trailing spaces between continuing lines of a block, so a single source newline renders as a line break.    |
| `--gaps`   | One `U+2800` (braille blank) empty paragraph at each blank-line block boundary, so a blank line shows as a row. |
| `--strip`  | The inverse: remove the breaks + gaps this tool added, back to clean source (collapses blank-line runs to one). |

Flags combine. With no feature flag the default is `--breaks` (backward compatible).
`--strip` ignores `--breaks`/`--gaps`.

### CLI examples

```bash
md-hardbreak --breaks notes.md             # hard breaks only
md-hardbreak --gaps notes.md               # gaps only
md-hardbreak --breaks --gaps notes.md      # both
md-hardbreak --strip notes.md              # undo -> clean source
md-hardbreak --breaks --gaps a.md b.md     # several files at once
pbpaste | md-hardbreak --breaks --gaps -   # pipe text through (reads stdin, writes stdout)
```

Modes: file arguments edit in place; `--stdin` (alias `-`) is a stdin -> stdout filter.
Only Markdown extensions (`.md .markdown .mdx .mdown .mkd .mkdn`) are edited in file mode.

## Zed integration

It runs **on demand only** - there is no on-save trigger. Markdown `format_on_save`
is `off` in Zed settings, so saving leaves the file exactly as typed.

The tasks live in [`home/.config/zed/tasks.json`](../home/.config/zed/tasks.json)
(committed); the key bindings live in [`home/.config/zed/keymap.json`](../home/.config/zed/keymap.json)
(committed, stow-symlinked to `~/.config/zed/keymap.json`). After editing either, reload
Zed so it picks them up.

| Key binding | Zed task                                   | Command                        |
| ----------- | ------------------------------------------ | ------------------------------ |
| `cmd-alt-b` | Markdown: add 2-space line breaks          | `md-hardbreak --breaks`        |
| `cmd-alt-g` | Markdown: add line breaks + paragraph gaps | `md-hardbreak --breaks --gaps` |
| `cmd-alt-u` | Markdown: strip line breaks + gaps         | `md-hardbreak --strip`         |

## Where everything lives

| Piece                 | Location                         | Tracked?                  |
| --------------------- | -------------------------------- | ------------------------- |
| Script                | `home/.local/bin/md-hardbreak`   | committed                 |
| Zed tasks             | `home/.config/zed/tasks.json`    | committed                 |
| Key bindings          | `home/.config/zed/keymap.json`   | committed                 |
| `format_on_save: off` | `home/.config/zed/settings.json` | skip-worktree (Mac-local) |

## Decisions and nuances

- **On-demand only.** No on-save formatting. `format_on_save` was `on` (Prettier on
  save, since 2026-05-03) before 2026-06-20; it may be turned back on later, but only
  after tweaking Prettier so it stops indenting lazy list continuations first.
- **Idempotent.** Running any mode twice changes nothing the second time; `--strip`
  cleanly reverses `--breaks --gaps` on single-blank source.
- **No hard break on a block's last line.** A trailing break there is a no-op in Zed
  but renders as an extra `<br>` in lenient previewers - combined with a gap paragraph
  that looked like a doubled gap. So breaks only go between two continuing lines.
- **Conservative gaps.** A gap is inserted at a blank boundary unless it would split a
  list (both neighbors are list items) or sits next to a heading, hr, code fence,
  blockquote, or an existing gap. Never inside fenced code or YAML frontmatter.
- **Why `U+2800`.** `U+2800`, `U+200B` (zero-width space) and `U+2060` (word joiner)
  all render as a gap and survive Prettier; `U+00A0` (no-break space) and `U+FEFF`
  (BOM) get stripped by Prettier. `U+2800` is the least likely to trip security
  scanners / code review (it is a normal letter-like glyph with width), unlike the
  true zero-width characters - which are the same ones used for hidden-text /
  homograph attacks. The owner is deliberately wary of invisible characters as a
  blanket policy precedent, so `U+2800` is the cautious choice.
- **List-continuation gotcha.** A line jammed directly under a `- ` bullet with no
  blank line is a list-item continuation in Markdown; put blank lines around it to
  make it a standalone paragraph that can take its own gaps.

## See also

- [`home/.local/bin/md-hardbreak`](../home/.local/bin/md-hardbreak) - the script and its full inline documentation (source of truth)
- [`home/.config/zed/tasks.json`](../home/.config/zed/tasks.json) - the Zed tasks that the key bindings spawn
- [`docs/STRUCTURE.md`](STRUCTURE.md) - where this sits in the repo layout
