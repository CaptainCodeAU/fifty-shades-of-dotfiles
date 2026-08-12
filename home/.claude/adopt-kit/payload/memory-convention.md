# The memory-store convention — the SHAPE that travels, not the contents

⚠️ **This kit deliberately seeds no memories.**

The rules about how to work with the operator live in the instruction-file block, because a rule
stored only in memory is consulted rather than obeyed. Writing those same rules into memory as
well would put one fact in two homes, and two copies go unnoticed and only drift.

Everything else a memory store should hold — facts, decisions, reasoning — is **project-specific
by definition** and cannot be prepared in advance. It accretes as work happens.

So what travels is the shape, and the rules for writing into it.

---

## The two-level index

```
memory/
├── MEMORY.md ──────────── loaded EVERY session; the only always-visible file
│     ├── standing rules and tooling ....... INLINE pointers, one line each
│     └── one line per DOMAIN ............... each pointing at a sub-index
│
├── _index-<domain>.md .... an INDEX, not a memory: no frontmatter,
│                           one "[Title](<slug>.md) — hook" line per entry
│
└── <slug>.md ............. one fact per file, YAML frontmatter, [[wiki-links]]
```

**Why two levels:** a session loads `MEMORY.md`, then only the sub-index it needs, then only the
one topic file — never the whole store. A flat index makes every session pay for every memory.

**Start flat.** A new project has no domains yet. Begin with `MEMORY.md` plus topic files and
inline pointers; introduce a `_index-*` sub-index only when one area has enough entries that its
pointers crowd the front page. Creating empty sub-indexes up front is scaffolding nobody asked
for.

## Topic-file frontmatter

```markdown
---
name: <short-kebab-case-slug>          # must equal the filename, minus .md
description: <one line, used to judge relevance during recall>
metadata:
  type: user | feedback | project | reference
---
```

| `type` | Holds |
|---|---|
| `user` | who the operator is — role, expertise, standing preferences |
| `feedback` | guidance on how to work; corrections and confirmed approaches. Include the WHY |
| `project` | ongoing work, goals, constraints not derivable from the code or git history |
| `reference` | pointers to external resources — URLs, dashboards, tickets |

For `feedback` and `project`, follow the fact with a **Why:** line and a **How to apply:** line.
Link related memories with `[[their-slug]]`. Link liberally — a `[[link]]` with no file yet marks
something worth writing, not an error.

## Rules for writing a memory

- **Memory holds facts, decisions and reasoning — never a behavioural rule.** Rule language
  (*always · never · must · do not*) appearing in a memory file is a signal it belongs in the
  instruction file instead, where it will actually fire.
- **No count that can be computed from the project.** State where it is computed from. Vendor-
  published figures (rate limits, caps, cutoffs) are the exception — nowhere else has them.
- **Convert relative dates to absolute.** "Last week" rots; a date does not.
- **Lead with the correction.** A corrected claim gets its fix at or before the claim, never
  further down the file where a skimming reader misses it.
- **A fact from someone else is theirs.** Check it against their record or mark it
  `[unverified, as of <date>]`.
- **One fact per file.** If a file needs "and" to describe it, it is two files.
- **Never store what the project already records** — code structure, git history, or anything
  already stated in the instruction file. Memory is only for what the memory layer alone knows.
- **A deletion's blast radius is its inbound links.** Removing a memory is not finished when its
  own pointer is gone; it is finished when nothing still points at it.

## The invariant worth checking

**Closed-world, both ways:** every topic file has exactly one index line, and every index line
resolves to a file. When those two counts disagree, something is either invisible or dangling.

## ⚠️ The store is not version controlled

It lives outside the project and is typically not in git. **An overwrite is unrecoverable.**
Snapshot before any bulk change, and never let a mechanical sweep decide what it touches — use
an explicit list of files.
