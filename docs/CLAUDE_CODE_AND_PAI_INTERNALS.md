# Claude Code & PAI Internals

**Audience:** Anyone (human or agent) who needs to understand what lives under
`~/.claude/`, who creates it, and what happens to it when a project is created,
loaded, resumed, or moved. Written as both a complete file/folder reference and a
migration blast-radius guide.

**Scope:** Describes the version actually installed on this Mac as of 2026-05-28
-- PAI 4.0.3, Algorithm 3.7.0, VoiceServer on `:8888` (the underlying Claude Code host
is v2.1.191, Opus 4.8 default, re-checked 2026-06-25). Upstream PAI has moved well
beyond this; see the footnote in the last section. Where a fact was verified
against disk it is stated plainly; where it is inferred it is marked.

---

## 1. The Mental Model: Three Systems, Not Two

Everything under `~/.claude/` belongs to one of three systems. The most common
mistake is conflating the two "memory" systems, so this distinction comes first.

| #   | System                            | Owner       | What it is                                                                                             | How it is used                                                          |
| --- | --------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| 1   | **Native runtime + session data** | Claude Code | Session transcripts, process/shell state, file history, plugins, tasks                                 | Managed entirely by the harness; resumed via `--resume` / `--continue`  |
| 2   | **Native auto-memory**            | Claude Code | `projects/<encoded>/memory/` with a `MEMORY.md` index + typed frontmatter                              | Harness injects `MEMORY.md` into the system prompt at session start     |
| 3   | **PAI framework**                 | PAI         | `PAI/`, `hooks/`, global `MEMORY/` tree, `agents/`, `skills/`, `VoiceServer/`, `CLAUDE.md`, statusline | PAI hooks wired in `settings.json` fire on Claude Code lifecycle events |

Systems 1 and 2 ship with Claude Code and exist on any install. System 3 is the
PAI overlay. **Verified:** PAI's `LoadContext.hook.ts` contains zero references to
`projects/` or the per-project `memory/` directory -- it reads only the global PAI
`MEMORY/` tree. The per-project `memory/` is therefore purely a native Claude Code
feature, not PAI.

---

## 2. System 1 -- Claude Code Native Runtime & Session Data

All paths are under `~/.claude/`.

### projects/<encoded-cwd>/

One directory per working directory, named by encoding the absolute cwd:
`/` -> `-`, `_` -> `-`, `.` -> `-`. Example:
`/Users/<username>/CODE/Scaffoldings/fifty-shades-of-dotfiles` becomes
`-Users-<username>-CODE-Scaffoldings-fifty-shades-of-dotfiles`. Contents:

- **`<sessionId>.jsonl`** -- one append-only file per session (sessionId is a
  UUID v4). Line `type` values observed: `user`, `assistant`, `queue-operation`,
  `ai-title`, `last-prompt`. A `user`/`assistant` line carries `uuid`,
  `parentUuid`, `sessionId`, `cwd`, `gitBranch`, `timestamp`, `version`,
  `entrypoint`, plus the message payload.
- **`<uuid>/subagents/agent-<short>.jsonl`** + **`.meta.json`** -- transcripts for
  spawned subagents; meta records `agentType`, `description`, `toolUseId`.
- **`<uuid>/tool-results/`** -- large tool outputs overflowed out of the main
  JSONL.
- **`memory/`** -- this is System 2 (section 3); it is NOT part of the transcript
  machinery.
- Retention: native rolling cleanup of transcripts (approximately 30 days;
  inferred from PAI docs + web, not directly measured).

### history.jsonl

Global command/prompt index across all projects:
`{display, timestamp, project, sessionId, pastedContents}`. Used for CLI history,
not for resume.

### sessions/<pid>.json

Live process state for a running session: `pid`, `sessionId`, `cwd`,
`status` (`busy`/`idle`), `version`, `kind`, `entrypoint`, timestamps. Created on
start, updated on status change, removed on exit. Lets the harness detect and
attach to running sessions.

### session-env/<sessionId>/

Per-session shell-state placeholders, one dir per session (mostly empty until
shell state is captured).

### shell-snapshots/snapshot-zsh-<ts>-<id>.sh

Full dump of shell functions, aliases, and environment. Sourced to reconstruct
the shell environment for Bash tool calls.

### file-history/

Versioned snapshots of edited files (`<hash>@vN`) for undo/rollback. One of the
larger stores (~111 MB here).

### paste-cache/<hash>.txt

Pasted/clipboard chunks, deduplicated by content hash.

### backups/.claude.json.backup.<ts>

Periodic snapshots of top-level harness state (`numStartups`, theme,
`tipsHistory`, feature flags).

### plugins/

Installed marketplace plugins and MCP servers -- the largest store (~1.3 GB here).
Manifests: `installed_plugins.json`, `known_marketplaces.json`,
`plugin-catalog-cache.json`, `blocklist.json`. Git clones live under `cache/` and
`marketplaces/`. Read at startup to load MCP servers.

### tasks/<taskId>/

Native backend for the TaskCreate / TaskList tools. Each task UUID directory
holds `.lock` and `.highwatermark` files (plus subdirectories). Older Claude Code
builds used `todos/`; this install uses `tasks/`. There is no `~/.claude/todos/`
here.

### Smaller native locations

- **`ide/<pid>.lock`** -- editor-integration locks.
- **`cache/changelog.md`** -- cached Claude Code release notes.
- **`logs/`** -- operation logs (e.g. `transcript-export.log` from the transcript
  exporter plugin).
- **`.last-cleanup`** -- ISO timestamp marker for the cleanup daemon.
- **`.credentials.json`** -- auth tokens (sensitive; do not read or print).
- **`.env`** -- symlink to `~/.config/PAI/.env` (PAI-owned; secrets).

### settings.json (and project-level .claude/)

`~/.claude/settings.json` is the user-level config. The schema is native Claude
Code, but on this machine it is heavily PAI-extended (the `env`, `permissions`,
and entire `hooks` blocks). There is no user-level `settings.local.json` here.
A project may also carry its own `.claude/` (with `settings.json`,
`settings.local.json`, `hooks/`, `commands/`, `docs/`). Precedence, highest to
lowest: enterprise > project-local > project > user.

---

## 3. System 2 -- Claude Code Native Auto-Memory

This is the per-project `memory/` directory, and it is the piece most often
mistaken for PAI. It is a native Claude Code feature.

- **Location:** `~/.claude/projects/<encoded>/memory/`
- **Index:** `MEMORY.md` -- a flat list of one-line pointers in the form
  `- [Title](file.md) -- one-line hook`. The harness loads `MEMORY.md` into the
  system prompt at session start; it is capped at **200 lines OR 25KB, whichever
  comes first** -- a hard limit in the Claude Code binary, with `CLAUDE_MEMORY_STORES`
  (a configurable separate store) as the only documented escape. Content past the cap
  is dropped, so the index is kept terse.
- **Entries:** individual `.md` files with frontmatter `name`, `description`, and
  `metadata.type`, where type is one of `user`, `feedback`, `project`, or
  `reference`. Bodies may cross-link with `[[slug]]`.
- **Written by:** the assistant, following the "auto memory" instructions in the
  system prompt. **Read by:** the harness, every session, for the directory
  matching the current cwd.
- **Worktree variant:** `projects/<encoded>--worktree-<name>/memory/` is a
  distinct context. Learnings from work done in a worktree belong there, not in
  the main project's memory.
- **Migration-critical:** because the directory name is the encoded cwd, moving or
  renaming a repo orphans this memory unless the directory is renamed. The
  `migrate-claude-projects` script handles the rename and rewrites path references
  inside the `.md` files.

---

## 4. System 3 -- PAI Framework

### 4.1 Install layout (under ~/.claude/)

- **`PAI/`** -- framework source and docs:
  - `Algorithm/` -- the Algorithm spec (this install: v3.7.0).
  - `Tools/` -- `Inference.ts`, `SessionProgress.ts`, `SessionHarvester.ts`,
    `LearningPatternSynthesis.ts`, `FailureCapture.ts`, and more.
  - `USER/` -- personal context (`OPINIONS.md`, `PROJECTS`, steering rules).
  - `ACTIONS/`, `FLOWS/`, `PIPELINES/` -- workflow definitions.
  - Architecture docs: `THEHOOKSYSTEM.md`, `MEMORYSYSTEM.md`,
    `PAISYSTEMARCHITECTURE.md`, `CONTEXT_ROUTING.md`, and others.
- **`hooks/`** -- TypeScript `*.hook.ts` files, plus `handlers/` and `lib/` shared
  utilities (`identity.ts`, `learning-readback.ts`, `prd-utils.ts`,
  `tab-setter.ts`, `hook-io.ts`, `paths.ts`, `time.ts`).
- **`MEMORY/`** -- the PAI global memory tree (section 4.3).
- **`agents/`, `skills/`** -- PAI agent and skill definitions.
- **`VoiceServer/`** -- local voice-notification server on `localhost:8888`.
- **`Customizations/`, `PAI-Install/`, `PAI_related_docs_for_myself/`** -- install
  and personal-extension directories.
- **`CLAUDE.md`** (+ `.template`) -- the PAI operating instructions, rebuilt by
  `hooks/handlers/BuildCLAUDE.ts`.
- **`statusline-command.sh`** -- status-line renderer.

### 4.2 Hook system (event -> hook -> effect)

Wired in `settings.json -> hooks`. Verified against `settings.json` on disk:

| Event                | Hooks (in order)                                                                                                              | Key reads / writes                                                                                                                                   |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SessionStart**     | KittyEnvPersist, LoadContext, BuildCLAUDE.ts                                                                                  | LoadContext reads global `MEMORY/` + `settings.loadAtStartup`, injects the session-start system-reminders; BuildCLAUDE rebuilds `CLAUDE.md` if stale |
| **UserPromptSubmit** | RatingCapture, UpdateTabTitle, SessionAutoName                                                                                | RatingCapture -> `MEMORY/LEARNING/SIGNALS/ratings.jsonl` (and a FAILURES dump on ratings <= 3); SessionAutoName -> `MEMORY/STATE/session-names.json` |
| **PreToolUse**       | SecurityValidator (Bash, Edit, Write, Read), SetQuestionTab (AskUserQuestion), AgentExecutionGuard (Task), SkillGuard (Skill) | SecurityValidator blocks dangerous ops and logs security events; guards run before the tool executes                                                 |
| **PostToolUse**      | QuestionAnswered (AskUserQuestion), PRDSync (Write, Edit)                                                                     | PRDSync reads PRD.md frontmatter and writes `MEMORY/STATE/work.json` (it never writes PRD content)                                                   |
| **Stop**             | LastResponseCache, ResponseTabReset, VoiceCompletion, DocIntegrity                                                            | LastResponseCache -> `MEMORY/STATE/last-response.txt`; VoiceCompletion POSTs to `:8888`                                                              |
| **SessionEnd**       | WorkCompletionLearning, SessionCleanup, RelationshipMemory, UpdateCounts, IntegrityCheck                                      | learning files -> `MEMORY/LEARNING/...`; PRD status -> COMPLETED; relationship notes -> `MEMORY/RELATIONSHIP/YYYY-MM/`; counts -> `settings.json`    |

### 4.3 PAI global MEMORY/ tree

Distinct from System 2. Verified subdirectories on disk: `LEARNING/`,
`RELATIONSHIP/`, `STATE/`, `VOICE/`, `WORK/` (plus `README.md` and
`reference_customizations.md`).

- **`LEARNING/`** -- subdirs verified on disk: `ALGORITHM/`, `FAILURES/`,
  `REFLECTIONS/`, `SIGNALS/`, `SYSTEM/`. `SIGNALS/ratings.jsonl` holds 1-10
  satisfaction ratings; `FAILURES/<YYYY-MM>/<ts>_<desc>/` holds full-context dumps
  (CONTEXT.md, transcript, sentiment, tool-calls) for ratings <= 3.
- **`WORK/`** -- `<ts>_<slug>/PRD.md` per work item (consolidated format). PRD
  frontmatter carries `phase`, `progress`, `effort`, `status`, `session_id`.
- **`STATE/`** -- ephemeral, rebuildable: `work.json`, `session-names.json`,
  `progress/`, `algorithms/`, `last-response.txt`, and various `*-cache` files.
- **`VOICE/voice-events.jsonl`** -- log of every voice notification.
- **`RELATIONSHIP/`** -- daily DA/principal notes (sparsely populated here).
- **`WISDOM/`** -- referenced in `settings.json` text but NOT present on disk in
  this install (do not assume it exists).

`LEARNING/` and `WORK/` are permanent; `STATE/` is rebuildable from `WORK/` plus
the native transcripts.

### 4.4 SessionStart load chain

LoadContext produces the system-reminders seen at the top of each session:
(a) force-loaded `loadAtStartup.files` (steering rules, projects); (b) PAI Dynamic
Context (relationship opinions, signal trends, learning digest, failure patterns);
(c) ACTIVE WORK (recent 48h sessions + tracked projects, assembled from
`MEMORY/WORK/` and `MEMORY/STATE/progress/` via `lib/learning-readback.ts` and
`PAI/Tools/SessionProgress.ts`).

### 4.5 Algorithm + PRD/ISC

ALGORITHM MODE loads `PAI/Algorithm/v3.7.0.md`. Work is tracked as PRD.md files
under `MEMORY/WORK/<ts>_<slug>/` with an Ideal State Criteria (ISC) checklist that
the assistant edits directly. PRDSync mirrors PRD frontmatter into
`STATE/work.json` for the dashboard; it does not author PRD content.

### 4.6 Voice / notifications

`VoiceServer` listens on `localhost:8888`. Hooks and the Algorithm POST to
`/notify`; every event is logged to `MEMORY/VOICE/voice-events.jsonl`.

---

## 5. Session Lifecycle Walkthroughs

### New project, first session

The harness creates `projects/<encoded>/`, a new `<sessionId>.jsonl`,
`sessions/<pid>.json`, `session-env/<sessionId>/`, a shell snapshot, and a
`history.jsonl` entry. No `memory/` exists yet, so System 2 injects nothing. PAI
SessionStart hooks fire and LoadContext injects global context.

### Existing project, new session

A new `<sessionId>.jsonl` is created in the SAME `projects/<encoded>/`. The project
`.claude/` and shell snapshots are reused, and -- the key difference -- the harness
injects the existing `memory/MEMORY.md` (System 2). PAI re-runs SessionStart hooks.
The prior conversation is NOT replayed; it is a fresh thread.

### Resume (--resume / --continue)

The harness reads the target `<sessionId>.jsonl` in full, rebuilds the
conversation, and APPENDS to the same file (it grows across resumes). Shell env and
file-history context are restored. PAI SessionStart hooks still fire.

### Per-event "who writes what"

SessionStart (KittyEnvPersist, LoadContext, BuildCLAUDE) -> UserPromptSubmit
(RatingCapture, UpdateTabTitle, SessionAutoName) -> PreToolUse (guards) ->
PostToolUse (QuestionAnswered, PRDSync) -> Stop (LastResponseCache, tab reset,
voice, DocIntegrity) -> SessionEnd (learning, cleanup, relationship, counts,
integrity). See section 4.2 for the files each touches.

---

## 6. Migration Blast Radius

What happens to each system when a project's path changes (moved into
`CaptainCodeAU/`, renamed, or relocated across machines):

| System                                                           | Keyed on                            | On path change                                                        | Action required                                                                                       |
| ---------------------------------------------------------------- | ----------------------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Native transcripts `projects/<encoded>/*.jsonl`                  | encoded cwd                         | New dir at new path; old orphaned                                     | Rename old dir (`migrate-claude-projects`); transcript tool reconciles via each session's `cwd` field |
| Native auto-memory `projects/<encoded>/memory/`                  | encoded cwd                         | Orphaned; a new session sees no memory                                | Rename dir AND rewrite path refs inside the `.md` files (`migrate-claude-projects` does both)         |
| `sessions/`, `session-env/`, `shell-snapshots/`, `file-history/` | sessionId / runtime                 | Stale entries are harmless; recreated as needed                       | None                                                                                                  |
| `history.jsonl`                                                  | absolute `project` path             | Old entries keep the old path                                         | None (historical record)                                                                              |
| PAI `MEMORY/STATE/work.json`, `progress/`, `session-names.json`  | sessionId + slug (sometimes cwd)    | May reference an old path/cwd                                         | Spot-check for hardcoded old paths; usually sessionId-keyed and safe                                  |
| PAI `MEMORY/WORK/<...>/PRD.md`                                   | slug                                | `## Context` may cite an old path                                     | Optional cleanup; not load-bearing                                                                    |
| transcript archive `my-claude-code-transcripts/<display>/`       | `get_project_display_name(encoded)` | Display name changes (e.g. `Scaffoldings-...` -> `CaptainCodeAU-...`) | Rename the archive folder; reconcile                                                                  |
| `.git/config` remote URL                                         | not path-derived                    | Unaffected                                                            | None (changing the remote alias is independent of all naming)                                         |

Headline rules:

- The **encoded cwd is the linchpin.** Two native systems (transcripts and
  auto-memory) plus the transcript archive all derive from it.
- The **remote URL governs no naming.** Changing `git@github.com:...` to
  `git-cc:...` touches nothing outside `.git/config`.
- **PAI state is largely sessionId-keyed,** so it is mostly migration-safe; the
  only exception is a hardcoded absolute path inside a PRD `## Context` or a
  progress note.
- `migrate-claude-projects` already covers the two native systems. For PAI, an
  optional `grep` for stale absolute paths under `MEMORY/` is sufficient.

---

## 7. Installed vs Upstream (footnote)

This document describes the installed version: PAI 4.0.3, Algorithm 3.7.0, roughly
20 hooks, the `VoiceServer` notification server on `:8888`, and a `MEMORY/` tree of
LEARNING / RELATIONSHIP / STATE / VOICE / WORK. Upstream PAI has since moved to
v5+ with Algorithm 6.3, a unified **Pulse** daemon on `:31337` (replacing the
standalone VoiceServer), roughly 37 hooks, and additional memory tiers
(KNOWLEDGE, OBSERVABILITY) plus containment zones. None of those are installed
here. If the installed version is upgraded, re-verify sections 4.1 through 4.6
against disk before trusting them.

Sources for upstream context:
[PAI repo](https://github.com/danielmiessler/Personal_AI_Infrastructure),
[Daniel Miessler's PAI writeup](https://danielmiessler.com/blog/personal-ai-infrastructure).
