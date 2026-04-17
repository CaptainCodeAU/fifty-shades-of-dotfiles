# PAI Memory System — How Claude Remembers Things

This document explains the memory and persistence mechanisms available to Claude (PAI) across conversations, projects, and sessions. Written for Gavin to read at leisure.

---

## The Problem It Solves

Each Claude conversation starts with a blank slate by default. Without a memory system, every session begins with "who are you, what are we working on, why did we do X that way?" That's friction you shouldn't have to pay repeatedly — especially for decisions that took real investigation to reach.

The memory system is the answer to: _"I don't have an adequate and acceptable short-term memory. I rely on your harnessing to help me remember things."_

---

## The Four Memory Layers

### 1. Auto-Memory (Cross-session, project-scoped)

**What it is:** A directory of Markdown files at:

```
~/.claude/projects/-Users-fonzarelli-CODE-Scaffoldings-fifty-shades-of-dotfiles/memory/
```

Each file stores one piece of persistent knowledge. There are four types:

| Type        | Stores                                         | Example                                                            |
| ----------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| `user`      | Who you are, your preferences, how you work    | "Gavin prefers bundling related fixes into grouped commits"        |
| `feedback`  | What to do / avoid in future sessions          | "Don't use line-count heuristics — explain reasoning first"        |
| `project`   | Ongoing work, decisions, context behind things | "brew list is used (not command -v) because formula ≠ binary name" |
| `reference` | Where things live in external systems          | "Pipeline bugs tracked in Linear project INGEST"                   |

**How it gets triggered:** I write these manually, using the `Write` tool, when I recognize that something is worth keeping. It is NOT automatic — I have to recognize the moment. The goal is to capture:

- Why a decision was made (not just what was decided)
- What was surprising or non-obvious
- Preferences and corrections you've given me
- Context that would otherwise require re-investigation

**How it gets read:** `MEMORY.md` (an index file in the same directory) is auto-loaded into every conversation context at session start. I read it and then fetch specific memory files when relevant. The index looks like:

```markdown
- [install.sh design decisions](project_install_decisions.md) — brew list vs command -v reasoning
- [Package manager policy](project_pkg_manager_policy.md) — bun co-primary with pnpm; npm/yarn blocked
```

**Important caveat:** Memories can go stale. If I saved a memory about a specific file or function, that file may have changed since. I'm supposed to verify against current code before asserting something as fact from memory. The date-stamp on memories helps flag when they might be outdated.

---

### 2. CLAUDE.md (Project-level rules, always loaded)

**What it is:** A file checked into the repo at `./CLAUDE.md`. It's loaded into every conversation automatically, before anything else.

**What belongs here:** Permanent project conventions that should never be forgotten:

- "Use `uv run python3` instead of `python3` directly"
- "Default branch is `master`"
- Rules that apply to every conversation, not just recalled context

**What doesn't belong here:** Decision history, investigation notes, or anything that might change. Those go in auto-memory.

There's also a global CLAUDE.md at `~/.claude/CLAUDE.md` — that one contains your PAI system configuration (modes, voice, identity, algorithm). It applies across ALL projects.

---

### 3. Tasks (Within a single conversation)

**What it is:** An in-session task list (`TaskCreate`, `TaskUpdate`, `TaskList`). Steps show up as a checklist and get marked complete as work progresses.

**What it's for:** Breaking a large implementation into trackable steps within the current conversation. Helps Claude stay on track during multi-file, multi-step work.

**Limitation:** Does NOT persist after the session ends. Not memory — it's a scratchpad.

---

### 4. Plans (Implementation alignment)

**What it is:** A structured plan that Claude creates and presents before starting a non-trivial task. You review and approve before any code is touched.

**When to use it:** Any task where the "how" matters as much as the "what" — architecture choices, multi-file changes, things that could go wrong in several ways.

**How it works:** Claude writes the plan, presents it, and stops. No execution until you say go. This is a critical check — a plan that looks wrong before execution costs nothing to fix; one that looks wrong after execution costs rollback effort.

---

## How It All Fits Together

```
Session start
    ↓
CLAUDE.md loaded (project rules, always)          ← permanent law of the land
MEMORY.md index loaded (what memories exist)      ← what to recall this session
    ↓
Conversation begins
    ↓
Work happens...
    ↓
Claude recognizes a decision worth keeping        ← must happen proactively
    ↓
Write to memory/project_xyz.md                    ← persists to future sessions
Update MEMORY.md index                            ← so future sessions can find it
    ↓
Session ends — Tasks and in-session state gone
Memory files remain for next session
```

---

## What Should Be Saved (and What Shouldn't)

**Save:**

- _Why_ something was built a certain way (not just what it does)
- Decisions that took real investigation to reach
- Preferences and corrections you've given Claude
- Counter-intuitive choices that look like bugs until you understand them
- Ongoing project state (who's doing what, deadlines, pivots)

**Don't save:**

- Code patterns, file paths, or project structure — read the code instead
- Git history — `git log` is authoritative
- Ephemeral task details from the current session
- Things already documented in CLAUDE.md

---

## Triggering a Memory Save

There's no automatic trigger — Claude has to recognize the moment. You can always explicitly ask:

> "Remember this decision."
> "Save this for next time."
> "Make a note of why we did it this way."

Claude can also save proactively when it recognizes something non-obvious was just established. The `brew list` vs `command -v` decision during the install.sh audit is a good example — it looked like a bug, required investigation to understand, and is now saved so it won't be re-litigated.

---

## Current Memory Files for This Project

| File                              | Contents                                            |
| --------------------------------- | --------------------------------------------------- |
| `project_planned_features.md`     | Specs in Plans/ directory                           |
| `project_pkg_manager_policy.md`   | bun/pnpm policy, npm/yarn blocked                   |
| `project_tmux_tilit_overrides.md` | tilit binding fix order                             |
| `project_llm_infrastructure.md`   | Ollama removed, LM Studio on RTX 3090               |
| `project_install_decisions.md`    | brew list reasoning, stow_platform line-count guard |
| `feedback_bun_installer_zshrc.md` | bun installer appends duplicate .zshrc entries      |

---

## Gaps and Known Limitations

1. **No automatic capture** — Claude must recognize the moment and save it. If Claude doesn't proactively write a memory, the knowledge is lost after the session.
2. **Memories go stale** — a memory written today about a specific file may not reflect the file in 3 months. Always verify.
3. **Index truncation** — `MEMORY.md` is capped at ~200 lines in the loaded context. If the index grows too large, older entries may not be visible at session start.
4. **Project-scoped** — memories in this directory are only loaded for this project. Cross-project knowledge needs to go in the global memory directory (`~/.claude/memory/`).
