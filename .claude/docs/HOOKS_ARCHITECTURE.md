# Claude Hooks Architecture

> A comprehensive reference for the **architecture** of the `.claude/hooks` notification
> and safety system: handler class hierarchy, event lifecycle, data flow, configuration
> schema, dedup/state model, and the audio pipeline.
>
> **This is not the hook inventory.** For what is actually installed — one section per
> shell hook, with its event, matcher and wiring level — see
> [`.claude/hooks/README.md`](../hooks/README.md), which the root README links to and
> which is kept current.
>
> Last updated: July 30, 2026 (v5 — per-hook inventory retired to `hooks/README.md`, and
> the architecture content **re-verified against the code** on 2026-07-30).
>
> What that re-verification actually checked, so a future reader knows its weight: every
> class the doc names exists; all 11 handlers in `lib/handlers/` are documented and none is
> missing in either direction; the Event → Handler Routing table matches `hook_runner.py`'s
> dispatch exactly, including that `AskUserQuestion` is a `PostToolUse` sub-case keyed on
> `tool_name` rather than an event of its own; every cell of the Handler Override Table
> matches the methods the handlers really define; `config.yaml`'s 3 global keys and 11 hook
> blocks are all documented with none undocumented; every `lib/` and `lib/handlers/` file
> appears in File Purposes; `state.py`'s 6 public functions are documented (private
> `_helpers` deliberately not); all 9 sound files named here exist on disk and are
> referenced in `config.yaml`; and all 14 events registered in `settings.json` appear here.
>
> NOT re-verified line by line: the prose walkthroughs and ASCII timelines in sections 3,
> 5 and 8 were checked for consistency with the code's structure, not traced call by call.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [File Structure](#2-file-structure)
3. [Hook Event Lifecycle](#3-hook-event-lifecycle)
4. [Handler Architecture](#4-handler-architecture)
5. [Data Flow](#5-data-flow)
6. [Configuration Reference](#6-configuration-reference)
7. [State Management & Deduplication](#7-state-management--deduplication)
8. [Audio Pipeline](#8-audio-pipeline)
9. [Shell Hook Scripts](#9-shell-hook-scripts)
10. [Quick Reference](#10-quick-reference)

---

## 1. System Overview

The hooks system provides audio notifications, safety guardrails, code quality
gates, and session lifecycle automation for Claude Code. It spans 13 event
types, 12 Python handlers (via `hook_runner.py`), 4 shell guard scripts, and 3
inline hooks registered directly in `settings.json`.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CLAUDE CODE SESSION                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Events
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              settings.json                                  │
│                                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │ SessionStart │ │ PreToolUse   │ │ PostToolUse  │ │    Stop      │       │
│  │ startup|     │ │ Bash         │ │ AskUser      │ │              │       │
│  │  resume /    │ │ Edit|Write   │ │ Edit|Write   │ │              │       │
│  │  compact     │ │              │ │              │ │              │       │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘       │
│         │                │                │                │               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │ Permission   │ │ Notification │ │ Subagent     │ │ TeammateIdle │       │
│  │   Request    │ │ idle|auth|   │ │ Start / Stop │ │              │       │
│  │              │ │  perm|dialog │ │              │ │              │       │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘       │
│         │                │                │                │               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │ TaskComplete │ │ PostToolUse  │ │ UserPrompt   │ │ PreCompact   │       │
│  │              │ │   Failure    │ │   Submit     │ │              │       │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘       │
│         │                │                │                │               │
│  ┌──────────────┐                                                          │
│  │  SessionEnd  │                                                          │
│  └──────┬───────┘                                                          │
└─────────┼──────────────────┼──────────────────┼──────────────────┼─────────┘
          │                  │                  │                  │
    ┌─────┴──────┐    ┌──────┴───────┐   ┌─────┴───────┐  ┌──────┴───────┐
    │ Shell      │    │ hook_runner  │   │  Inline     │  │ export_      │
    │ Scripts    │    │   .py        │   │  Hooks      │  │ transcript   │
    │            │    │  (Python)    │   │  (shell)    │  │    .sh       │
    │ session-   │    │              │   │             │  │              │
    │  checks.sh │    │  11 active   │   │ prettier    │  └──────────────┘
    │ validate-  │    │  handlers    │   │ markdownlint│
    │  bash.sh   │    │  + 1 skeleton│   │ compact echo│
    │ pre-commit │    └──────┬───────┘   └─────────────┘
    │  -check.sh │           │
    │ protect-   │    ┌──────┴───────┐
    │  files.sh  │    │ Notification │
    └────────────┘    │    Layer     │
                      │ ┌──────────┐ │
                      │ │  Sound   │ │
                      │ │  afplay  │ │
                      │ └──────────┘ │
                      │ ┌──────────┐ │
                      │ │  Voice   │ │
                      │ │ say → .  │ │
                      │ │ aiff →   │ │
                      │ │ afplay   │ │
                      │ └──────────┘ │
                      └──────────────┘
```

### Key Components

| Component        | Purpose                                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `settings.json`  | Registers which events trigger which hooks (shell scripts, Python runner, inline commands)                                                 |
| `config.yaml`    | Configures audio notification behavior (sounds, voices, messages) per handler                                                              |
| `hook_runner.py` | Python entry point — routes events to the appropriate handler                                                                              |
| Shell scripts    | Safety guardrails (`validate-bash.sh`, `protect-files.sh`), quality gates (`pre-commit-check.sh`), session lifecycle (`session-checks.sh`) |
| Inline hooks     | Auto-formatting (prettier, markdownlint) and post-compact context re-injection                                                             |
| Handlers (12)    | Process events, extract notification content, manage deduplication                                                                         |
| Audio layer      | Delivers notifications via `afplay` (sound) and `say` → `.aiff` → `afplay` (voice)                                                         |

---

## 2. File Structure

```text
.claude/
├── settings.json              # Hook registration (events → commands, matchers, timeouts)
├── settings.local.json        # Local permission overrides (allowed commands)
├── sounds/                    # MP3 sound effect files (32 files)
│   ├── bell_call.mp3          # Permission requests
│   ├── bell_ring_1.mp3        # Questions, notifications
│   ├── blink.mp3              # Pre-compact
│   ├── coin_simple.mp3        # Subagent start
│   ├── error_buzz.mp3         # Tool failures
│   ├── harp_finish.mp3        # Task completed
│   ├── marimba_complete.mp3   # Subagent stop
│   ├── marimba_nudge_1.mp3    # Teammate idle
│   ├── ui_open_1.mp3          # Task completion (stop)
│   └── ... (23 more)
│
├── hooks/
│   ├── config.yaml            # Audio notification configuration (12 hook sections)
│   ├── hook_runner.py         # Python entry point (reads stdin JSON, routes to handler)
│   ├── session-checks.sh      # SessionStart — git status + .env encryption check
│   ├── validate-bash.sh       # PreToolUse Bash — block destructive commands
│   ├── pre-commit-check.sh    # PreToolUse Bash — lint/build gate before git commit
│   ├── protect-files.sh       # PreToolUse Edit|Write — block edits to protected files
│   ├── export_transcript.sh   # SessionEnd — export session transcript
│   ├── security.log           # Audit log of blocked commands/edits (append-only)
│   │
│   ├── lib/                   # Python library modules
│   │   ├── __init__.py
│   │   ├── config.py          # YAML loading, 12 hook dataclasses, env var overrides
│   │   ├── state.py           # Dedup state (mark/check markers, last-spoken hash)
│   │   ├── audio.py           # play_sound(), speak(), play_notification()
│   │   ├── summary.py         # Sentence extraction, action verb detection
│   │   ├── transcript.py      # JSONL transcript parsing, text extraction
│   │   │
│   │   └── handlers/          # Event handlers (12 total)
│   │       ├── __init__.py
│   │       ├── base.py            # BaseHandler ABC — Template Method in handle()
│   │       ├── stop.py            # StopHandler — transcript summary, input-waiting detection
│   │       ├── ask_user.py        # AskUserQuestionHandler — question extraction + dedup
│   │       ├── permission.py      # PermissionRequestHandler — transcript summary + dedup
│   │       ├── notification.py    # NotificationHandler — idle/auth + dedup
│   │       ├── subagent_start.py  # SubagentStartHandler — subagent launch
│   │       ├── subagent_stop.py   # SubagentStopHandler — subagent completion + dedup
│   │       ├── teammate_idle.py   # TeammateIdleHandler — teammate went idle
│   │       ├── task_completed.py  # TaskCompletedHandler — subject truncation
│   │       ├── tool_failure.py    # PostToolUseFailureHandler — skip interrupts + dedup
│   │       ├── user_prompt_submit.py  # UserPromptSubmitHandler — silent skeleton
│   │       └── pre_compact.py     # PreCompactHandler — static compaction message
│   │
│   └── tests/
│       ├── test_state.py      # Dedup state machine tests
│       ├── test_summary.py    # Text extraction tests
│       └── test_transcript.py # JSONL parsing tests
│
└── docs/
    └── HOOKS_ARCHITECTURE.md  # This document
```

### File Purposes

| File                   | Type    | Purpose                                                                                           |
| ---------------------- | ------- | ------------------------------------------------------------------------------------------------- |
| `settings.json`        | Config  | Maps Claude events to hook commands with matchers and timeouts                                    |
| `config.yaml`          | Config  | Sound files, voice settings, message templates for all 12 hooks                                   |
| `hook_runner.py`       | Entry   | Reads stdin JSON, routes to 1 of 11 active handlers                                               |
| `config.py`            | Lib     | Loads YAML into typed dataclasses; env var overrides; CWD fallback                                |
| `state.py`             | Lib     | Dedup markers, last-spoken hash, 60-second auto-expiry                                            |
| `audio.py`             | Lib     | `afplay` (sound) and `say -o` → `.aiff` → `afplay -v` (voice)                                     |
| `summary.py`           | Lib     | Sentence splitting, action verb detection, character/sentence limits                              |
| `transcript.py`        | Lib     | Parses JSONL transcripts; finds text, tool_use, AskUserQuestion                                   |
| `base.py`              | Handler | Abstract base — Template Method: should_handle → pre_message → get_message → resolve_audio → play |
| `session-checks.sh`    | Shell   | Git status count + `.env` encryption check on session start                                       |
| `validate-bash.sh`     | Shell   | Blocks `rm -rf /`, force push to main/master, hard reset, `git clean`                             |
| `pre-commit-check.sh`  | Shell   | Runs lint + build (Node.js or Python) + markdownlint before `git commit`                          |
| `protect-files.sh`     | Shell   | Blocks edits to `.env*`, lockfiles, `.git/`                                                       |
| `export_transcript.sh` | Shell   | Exports transcript via `claude-code-transcripts` on session end                                   |
| `security.log`         | Log     | Append-only audit trail of blocked commands and edits                                             |

---

## 3. Hook Event Lifecycle

### Event Types

| Event                | When Fired                | Matcher                                                            | Handler / Script                             | Timeout   |
| -------------------- | ------------------------- | ------------------------------------------------------------------ | -------------------------------------------- | --------- |
| `SessionStart`       | Session starts or resumes | `startup\|resume`                                                  | `session-checks.sh`                          | 10s       |
| `SessionStart`       | Context compacted         | `compact`                                                          | Inline echo (conventions reminder)           | 5s        |
| `PreToolUse`         | Before Bash tool          | `Bash`                                                             | `validate-bash.sh` + `pre-commit-check.sh`   | 10s / 30s |
| `PreToolUse`         | Before Edit/Write tool    | `Edit\|Write`                                                      | `protect-files.sh`                           | 10s       |
| `PostToolUse`        | After AskUserQuestion     | `AskUserQuestion`                                                  | `hook_runner.py` → AskUserQuestionHandler    | 5s        |
| `PostToolUse`        | After Edit/Write          | `Edit\|Write`                                                      | Inline prettier + inline markdownlint        | 10s       |
| `Stop`               | Claude stops responding   | (none)                                                             | `hook_runner.py` → StopHandler               | 5s        |
| `PermissionRequest`  | Tool needs approval       | (none)                                                             | `hook_runner.py` → PermissionRequestHandler  | 5s        |
| `Notification`       | System notification       | `idle_prompt\|auth_success\|permission_prompt\|elicitation_dialog` | `hook_runner.py` → NotificationHandler       | 5s        |
| `SubagentStart`      | Subagent launched         | (none)                                                             | `hook_runner.py` → SubagentStartHandler      | 5s        |
| `SubagentStop`       | Subagent finished         | (none)                                                             | `hook_runner.py` → SubagentStopHandler       | 5s        |
| `TeammateIdle`       | Teammate goes idle        | (none)                                                             | `hook_runner.py` → TeammateIdleHandler       | 5s        |
| `TaskCompleted`      | Task completed            | (none)                                                             | `hook_runner.py` → TaskCompletedHandler      | 5s        |
| `PostToolUseFailure` | Tool use fails            | (none)                                                             | `hook_runner.py` → PostToolUseFailureHandler | 5s        |
| `UserPromptSubmit`   | User submits prompt       | (none)                                                             | `hook_runner.py` → UserPromptSubmitHandler   | 5s        |
| `PreCompact`         | Before context compaction | (none)                                                             | `hook_runner.py` → PreCompactHandler         | 5s        |
| `SessionEnd`         | Session terminates        | `prompt_input_exit\|logout\|other`                                 | `export_transcript.sh`                       | (none)    |

### Timeline: AskUserQuestion Flow

```text
Time ──────────────────────────────────────────────────────────────────────────►

Claude generates AskUserQuestion
        │
        ▼
┌───────────────────┐
│ PermissionRequest │ ◄─── If tool requires approval, fires FIRST
│   Event Fired     │      PermissionHandler reads transcript, speaks
│                   │      summary of assistant's last text (not
│                   │      "Approve AskUserQuestion?" — extracts the
│                   │      actual question from tool_input instead)
│                   │      Marks "permission" handled
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  User Approves    │ ◄─── User clicks approve
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│   PostToolUse     │ ◄─── AskUserQuestionHandler extracts question text
│   Event Fired     │      Marks "ask_user" handled
│                   │      (dedup prevents double notification)
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Question Form    │ ◄─── User sees and answers the question
│   Displayed       │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│   Stop Event      │ ◄─── StopHandler checks dedup markers:
│   Fired           │      "ask_user" or "permission" found → suppressed
│                   │      Falls through to summary extraction if text
│                   │      available, otherwise silent
└───────────────────┘
```

**Key insight:** When AskUserQuestion is auto-approved, only `PostToolUse`
fires (no `PermissionRequest`). When it requires approval, `PermissionRequest`
fires first and speaks the question; `PostToolUse` fires after approval but
dedup prevents a second notification.

### Timeline: Task Completion Flow

```text
Time ──────────────────────────────────────────────────────────────────────────►

Claude finishes work
        │
        ▼
┌───────────────────┐
│   Stop Event      │ ◄─── StopHandler reads transcript
│   Fired           │      Extracts summary (action verb sentences)
│                   │      Voice: "Created the authentication module."
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  User sees        │
│  completed work   │
└───────────────────┘
```

### Timeline: Permission with Transcript Summary

```text
Time ──────────────────────────────────────────────────────────────────────────►

Claude writes explanation, then calls Bash
        │
        ▼
┌───────────────────────────────┐
│ PermissionRequest Event       │
│                               │
│ 1. Read transcript            │
│ 2. Find last assistant text   │
│ 3. Extract summary            │
│ 4. Check was_already_spoken   │ ◄─── Dedup for burst of calls
│ 5. Speak summary OR template  │
│ 6. Mark "permission" handled  │
│ 7. Store last_spoken hash     │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ Stop Event                    │
│ Checks dedup → "permission"   │
│ found → falls through to      │
│ summary extraction (speaks    │
│ summary if available, else    │
│ silent)                       │
└───────────────────────────────┘
```

### Timeline: Subagent Lifecycle

```text
Time ──────────────────────────────────────────────────────────────────────────►

Claude launches subagent
        │
        ▼
┌───────────────────┐
│ SubagentStart     │ ◄─── "Subagent Explore started"
│ Event Fired       │      (coin_simple.mp3)
└─────────┬─────────┘
          │
          │ ... subagent works ...
          │
          ▼
┌───────────────────┐
│ SubagentStop      │ ◄─── "Subagent Explore finished"
│ Event Fired       │      (marimba_complete.mp3)
│                   │      Marks "subagent_stop" handled
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Stop Event        │ ◄─── Checks dedup → "subagent_stop"
│ Fired             │      found → suppressed (falls through
│                   │      to summary if text available)
└───────────────────┘
```

### Event Priority & Deduplication

```text
                    ┌────────────────────────────────────────┐
                    │     Claude stops / event fires         │
                    └───────────────────┬────────────────────┘
                                        │
         ┌──────────────┬───────────────┼───────────────┬──────────────┐
         │              │               │               │              │
         ▼              ▼               ▼               ▼              ▼
    PostToolUse   Permission      Notification    SubagentStop   PostToolUse
   (AskUser)       Request       (idle_prompt)                   Failure
         │              │               │               │              │
         ▼              ▼               ▼               ▼              ▼
   AskUserHandler PermHandler   NotifyHandler   SubStopHandler FailHandler
         │              │               │               │              │
    mark_handled   mark_handled   mark_handled   mark_handled  mark_handled
    "ask_user"     "permission"  "notification_  "subagent_    "tool_failure"
         │              │         idle"    │       stop"  │              │
         └──────────────┴────────────┬────┴──────────┴───┘──────────────┘
                                     │
                                     ▼
                              ┌──────────────┐
                              │ StopHandler  │
                              │              │
                              │ Input-waiting│
                              │ detected?    │
                              │   │          │
                              │   ├── Yes ──►│ Check markers
                              │   │          │ ┌── Found? ──► Suppress
                              │   │          │ │  (fall through to
                              │   │          │ │   summary extraction)
                              │   │          │ └── Not found ──► Speak
                              │   │          │
                              │   └── No ───►│ Task-completion summary
                              │              │ (never checks dedup)
                              └──────────────┘
```

---

## 4. Handler Architecture

### Class Hierarchy

```text
                    ┌─────────────────────────────────────┐
                    │           BaseHandler               │
                    │          (Abstract)                 │
                    ├─────────────────────────────────────┤
                    │ + config: Config                    │
                    │ + _debug_log: list[str]             │
                    │ + project_dir: str     (property)   │
                    │ + debug_enabled: bool  (property)   │
                    │ + debug_dir: Path      (property)   │
                    ├─────────────────────────────────────┤
                    │ # should_handle(data) → bool        │
                    │ # get_message(data) → str|None      │
                    │ # get_audio_settings() → Settings   │
                    │ + _pre_message_hook(data) → None    │
                    │ + _resolve_audio_settings(data) →   │
                    │       AudioSettings                 │
                    │ + handle(data) → None               │
                    │ + log(msg) → None                   │
                    │ + write_debug_log() → None          │
                    └──────────────┬──────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
┌───────────────┐        ┌───────────────┐        ┌───────────────────┐
│  StopHandler  │        │AskUserQuestion│        │PermissionRequest  │
│               │        │   Handler     │        │   Handler         │
├───────────────┤        ├───────────────┤        ├───────────────────┤
│ Transcript    │        │ Extract       │        │ Read transcript   │
│ summary +     │        │ question from │        │ for text summary  │
│ input-waiting │        │ tool_input    │        │ + repeated-summary│
│ detection     │        │               │        │   dedup           │
│               │        │ Dedup:        │        │                   │
│ Overrides:    │        │  ask_user     │        │ Dedup:            │
│ _resolve_audio│        │               │        │  permission       │
│ _settings()   │        │ Overrides:    │        │                   │
│               │        │ _pre_message  │        │ Overrides:        │
│               │        │  _hook()      │        │ _pre_message      │
│               │        │               │        │  _hook()          │
│               │        │               │        │ get_message()     │
└───────────────┘        └───────────────┘        └───────────────────┘
        │                          │                          │
        ├──────────────────────────┼──────────────────────────┤
        │                          │                          │
        ▼                          ▼                          ▼
┌───────────────┐        ┌───────────────┐        ┌───────────────────┐
│ Notification  │        │SubagentStart  │        │ SubagentStop      │
│   Handler     │        │  Handler      │        │   Handler         │
├───────────────┤        ├───────────────┤        ├───────────────────┤
│ Maps type to  │        │ Template with │        │ Template with     │
│ message       │        │ {agent_type}  │        │ {agent_type}      │
│               │        │               │        │                   │
│ Dedup:        │        │ No dedup      │        │ Dedup:            │
│ notification  │        │               │        │  subagent_stop    │
│  _idle        │        │               │        │                   │
└───────────────┘        └───────────────┘        └───────────────────┘
        │                          │                          │
        ▼                          ▼                          ▼
┌───────────────┐        ┌───────────────┐        ┌───────────────────┐
│TeammateIdle   │        │TaskCompleted  │        │PostToolUseFailure │
│  Handler      │        │  Handler      │        │   Handler         │
├───────────────┤        ├───────────────┤        ├───────────────────┤
│ Template with │        │ Template with │        │ Template with     │
│ {teammate_    │        │ {task_subject}│        │ {tool_name}       │
│  name}        │        │ + truncation  │        │                   │
│               │        │               │        │ Skips is_interrupt │
│ No dedup      │        │ No dedup      │        │                   │
│               │        │               │        │ Dedup:            │
│               │        │               │        │  tool_failure     │
└───────────────┘        └───────────────┘        └───────────────────┘
        │                          │
        ▼                          ▼
┌───────────────┐        ┌───────────────┐
│UserPrompt     │        │ PreCompact    │
│Submit Handler │        │   Handler     │
├───────────────┤        ├───────────────┤
│ Disabled by   │        │ Static        │
│ default       │        │ message from  │
│               │        │ config        │
│ get_message() │        │               │
│ → None        │        │ No dedup      │
└───────────────┘        └───────────────┘
```

### Template Method: BaseHandler.handle()

```text
handle(data)
  │
  ├── 1. Log handler name, hook event, tool name
  │
  ├── 2. should_handle(data) ──── False ──► return (skip)
  │                                          │
  │                               True ◄─────┘
  │
  ├── 3. _pre_message_hook(data)     ◄── no-op by default
  │                                       (AskUser marks "ask_user",
  │                                        Permission marks "permission",
  │                                        Notification marks "notification_idle",
  │                                        SubagentStop marks "subagent_stop",
  │                                        ToolFailure marks "tool_failure")
  │
  ├── 4. get_message(data) ────── None ──► return (skip)
  │                                          │
  │                               str ◄──────┘
  │
  ├── 5. _resolve_audio_settings(data)  ◄── defaults to get_audio_settings()
  │                                          (StopHandler overrides: uses
  │                                           input-waiting settings when
  │                                           _use_input_settings is True)
  │
  ├── 6. play_notification(message, settings, project_dir)
  │
  └── 7. write_debug_log()
```

### Handler Override Table

Covers the four interesting hooks only. Every concrete handler also overrides
`hook_config` and `get_audio_settings` — universal, so they are not tabulated.

| Handler                     |          `should_handle`          |         `_pre_message_hook`          |               `get_message`                |   `_resolve_audio_settings`   |
| --------------------------- | :-------------------------------: | :----------------------------------: | :----------------------------------------: | :---------------------------: |
| `StopHandler`               |           check enabled           |                  —                   |    transcript summary + input detection    | **overrides** (input vs task) |
| `AskUserQuestionHandler`    |           check enabled           |          **mark ask_user**           |      extract question from tool_input      |               —               |
| `PermissionRequestHandler`  |           check enabled           |         **mark permission**          | **overrides** (transcript summary + dedup) |               —               |
| `NotificationHandler`       |           check enabled           | **mark notification_idle** (if idle) |             map type → message             |               —               |
| `SubagentStartHandler`      |           check enabled           |                  —                   |         template with {agent_type}         |               —               |
| `SubagentStopHandler`       |           check enabled           |        **mark subagent_stop**        |         template with {agent_type}         |               —               |
| `TeammateIdleHandler`       |           check enabled           |                  —                   |       template with {teammate_name}        |               —               |
| `TaskCompletedHandler`      |           check enabled           |                  —                   |  template with {task_subject} (truncated)  |               —               |
| `PostToolUseFailureHandler` | **overrides** (skip is_interrupt) |        **mark tool_failure**         |         template with {tool_name}          |               —               |
| `UserPromptSubmitHandler`   |           check enabled           |                  —                   |        **overrides** (returns None)        |               —               |
| `PreCompactHandler`         |           check enabled           |                  —                   |         static message from config         |               —               |

---

## 5. Data Flow

### Complete Flow: Event to Notification

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                              CLAUDE CODE                                      │
│                                                                               │
│  1. Event occurs (any of 13 types)                                           │
│  2. Writes event JSON to stdin                                               │
│  3. Calls: uv run "$CLAUDE_PROJECT_DIR"/.claude/hooks/hook_runner.py         │
│     (timeout: 5 seconds)                                                     │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     │
                                     │ stdin (JSON)
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           hook_runner.py                                      │
│                                                                               │
│  1. Read JSON from stdin                                                     │
│  2. Load config.yaml (cached)                                                │
│  3. Detect hook_event_name                                                   │
│  4. Route to handler (if-elif chain)                                         │
│     PostToolUse only routes AskUserQuestion                                  │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     │
                                     │ data dict
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Handler                                          │
│                                                                               │
│  1. should_handle(data) → proceed?                                           │
│  2. _pre_message_hook(data) → mark dedup state                               │
│  3. get_message(data) → extract notification text                            │
│  4. _resolve_audio_settings(data) → sound + voice config                     │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     │
                                     │ message + settings
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                         play_notification()                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐     │
│  │  1. Play Sound (if enabled + file exists)                           │     │
│  │     └─► afplay -v 0.5 .claude/sounds/bell_ring_1.mp3              │     │
│  │                                                                      │     │
│  │  2. Wait delay_ms (200ms) — only if sound played AND voice enabled │     │
│  │                                                                      │     │
│  │  3. Play Voice (if enabled)                                         │     │
│  │     ├─► say -v Victoria -r 350 -o /tmp/xxx.aiff "message"         │     │
│  │     └─► afplay -v 0.2 /tmp/xxx.aiff                               │     │
│  │         (cleanup thread deletes .aiff after 30s)                   │     │
│  └─────────────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Input JSON Schemas

```text
Common fields (all events)
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "Stop" | "PostToolUse" | "PermissionRequest" | ...,
  "session_id": "uuid-string",
  "transcript_path": "/path/to/transcript.jsonl"
}

PreToolUse / PostToolUse (AskUserQuestion)
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "PostToolUse",
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "Which approach should I use?",
        "header": "Approach",
        "options": [...]
      }
    ]
  }
}

PermissionRequest
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": { "command": "git commit ..." }
}

Notification
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "Notification",
  "notification_type": "idle_prompt" | "auth_success" | "permission_prompt" | "elicitation_dialog"
}

SubagentStart / SubagentStop
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "SubagentStart",
  "agent_type": "Explore"
}

TeammateIdle
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "TeammateIdle",
  "teammate_name": "agent-1"
}

TaskCompleted
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "TaskCompleted",
  "task_subject": "Fix authentication bug in login flow"
}

PostToolUseFailure
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "is_interrupt": false
}

PreToolUse (Bash) — for shell scripts
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /" }
}

PreToolUse (Edit|Write) — for shell scripts
──────────────────────────────────────────────────────────────────────
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": { "file_path": ".env.local" }
}
```

### Internal Data Structures

```text
MessageInfo (from transcript.py)
──────────────────────────────────────────────────────────────────────

┌─────────────────────────────────────────────────────────────────────┐
│  MessageInfo                                                        │
├─────────────────────────────────────────────────────────────────────┤
│  text: str | None            │ Combined text from all blocks        │
│  tool_names: list[str]       │ All tools used in message            │
│  ends_with_tool_use: bool    │ True if last block is tool_use       │
│  last_tool_name: str | None  │ Name of final tool                   │
│  ask_user_question_input:    │ AskUserQuestion tool params          │
│    dict | None               │                                      │
└─────────────────────────────────────────────────────────────────────┘


AudioSettings (from audio.py)
──────────────────────────────────────────────────────────────────────

┌─────────────────────────────────────────────────────────────────────┐
│  AudioSettings                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  sound: SoundConfig                                                 │
│    ├─ enabled: bool                                                 │
│    ├─ file: str              (relative path to MP3)                │
│    ├─ volume: float          (0.0 - 1.0)                           │
│    └─ delay_ms: int          (pause before voice)                  │
│                                                                     │
│  voice: VoiceConfig                                                 │
│    ├─ enabled: bool                                                 │
│    ├─ name: str              (macOS voice name)                    │
│    ├─ volume: float          (0.0 - 1.0, used by afplay -v)       │
│    └─ rate: int              (words per minute)                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. Configuration Reference

### settings.json (Hook Registration)

Full current version — all hooks use `$CLAUDE_PROJECT_DIR` for paths:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-checks.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Context compacted. Reminder: use uv for Python, pnpm or bun for Node.js. Read CLAUDE.md for project conventions.'",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/validate-bash.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-commit-check.sh",
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // .tool_input.filePath // empty' | xargs -I{} pnpm dlx prettier --write {} 2>/dev/null || true",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // .tool_input.filePath // empty' | xargs -I{} sh -c 'case \"{}\" in *.md) pnpm dlx markdownlint-cli --fix \"{}\" 2>/dev/null ;; esac' || true",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt|auth_success|permission_prompt|elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/hook_runner.py",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "prompt_input_exit|logout|other",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/export_transcript.sh"
          }
        ]
      }
    ]
  }
}
```

### config.yaml (Hook Behavior)

```yaml
global:
  debug: false # Enable debug logging (or HOOK_DEBUG=1 env var)
  debug_dir: "Temp" # Directory for debug files (relative to project_dir)
  project_dir: "" # Resolved: config value → $HOOK_PROJECT_DIR → CWD

hooks:
  stop: # StopHandler — task completion / input waiting
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/ui_open_1.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    summary:
      mode: "sentences"
      max_sentences: 1
      max_characters: 80
      start: "action"

  ask_user_question: # AskUserQuestionHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/bell_ring_1.mp3"
      volume: 0.6
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.6
      rate: 350
    message_mode: "extract" # "extract" or "generic"
    default_message: "Claude has a question for you"

  permission_request: # PermissionRequestHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/bell_call.mp3"
      volume: 0.4
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.4
      rate: 350
    message_template: "Approve {tool_name}?"

  notification: # NotificationHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/bell_ring_1.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    idle_message: "Claude is idle"
    auth_message: "Auth successful"
    default_message: "Notification"

  subagent_start: # SubagentStartHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/coin_simple.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    message_template: "Subagent {agent_type} started"

  subagent_stop: # SubagentStopHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/marimba_complete.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    message_template: "Subagent {agent_type} finished"

  teammate_idle: # TeammateIdleHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/marimba_nudge_1.mp3"
      volume: 0.5
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.5
      rate: 350
    message_template: "{teammate_name} is idle"

  task_completed: # TaskCompletedHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/harp_finish.mp3"
      volume: 0.5
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.5
      rate: 350
    message_template: "Task completed: {task_subject}"
    max_subject_length: 80

  post_tool_use_failure: # PostToolUseFailureHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/error_buzz.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    message_template: "{tool_name} failed"

  user_prompt_submit: # UserPromptSubmitHandler (disabled)
    enabled: false
    sound:
      enabled: false
      file: ""
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: false
      name: "Victoria"
      volume: 0.2
      rate: 350

  pre_compact: # PreCompactHandler
    enabled: true
    sound:
      enabled: true
      file: ".claude/sounds/blink.mp3"
      volume: 0.2
      delay_ms: 200
    voice:
      enabled: true
      name: "Victoria"
      volume: 0.2
      rate: 350
    message: "Compacting context"
```

### Dataclass Reference

```text
Config
├── global_config: GlobalConfig
│   ├── debug: bool = True
│   ├── debug_dir: str = "Temp"
│   └── project_dir: str = ""          ← resolved via env var / CWD fallback
│
├── stop: StopHookConfig
│   ├── enabled, sound, voice          (from HookConfig)
│   └── summary: SummaryConfig
│       ├── mode: str = "sentences"
│       ├── max_sentences: int = 2
│       ├── max_characters: int = 200
│       └── start: str = "action"
│
├── ask_user_question: AskUserQuestionHookConfig
│   ├── enabled, sound, voice
│   ├── message_mode: str = "extract"
│   └── default_message: str = "Claude has a question for you"
│
├── permission_request: PermissionRequestHookConfig
│   ├── enabled, sound, voice
│   └── message_template: str = "Approve {tool_name}?"
│
├── notification: NotificationHookConfig
│   ├── enabled, sound, voice
│   ├── idle_message: str = "Claude is idle"
│   ├── auth_message: str = "Auth successful"
│   └── default_message: str = "Notification"
│
├── subagent_start: SubagentStartHookConfig
│   ├── enabled, sound, voice
│   └── message_template: str = "Subagent {agent_type} started"
│
├── subagent_stop: SubagentStopHookConfig
│   ├── enabled, sound, voice
│   └── message_template: str = "Subagent {agent_type} finished"
│
├── teammate_idle: TeammateIdleHookConfig
│   ├── enabled, sound, voice
│   └── message_template: str = "{teammate_name} is idle"
│
├── task_completed: TaskCompletedHookConfig
│   ├── enabled, sound, voice
│   ├── message_template: str = "Task completed: {task_subject}"
│   └── max_subject_length: int = 80
│
├── post_tool_use_failure: PostToolUseFailureHookConfig
│   ├── enabled, sound, voice
│   └── message_template: str = "{tool_name} failed"
│
├── user_prompt_submit: UserPromptSubmitHookConfig
│   ├── enabled: bool = False          ← disabled by default
│   └── sound, voice
│
└── pre_compact: PreCompactHookConfig
    ├── enabled, sound, voice
    └── message: str = "Compacting context"
```

### Configuration Options Table

#### Global Settings

| Option        | Type   | Default  | Description                                              |
| ------------- | ------ | -------- | -------------------------------------------------------- |
| `debug`       | bool   | `false`  | Enable debug log output (overridable via `HOOK_DEBUG=1`) |
| `debug_dir`   | string | `"Temp"` | Directory for debug files (relative to project_dir)      |
| `project_dir` | string | `""`     | Resolved: config value → `$HOOK_PROJECT_DIR` → CWD       |

#### Sound Settings (per hook)

| Option     | Type   | Default | Description                                            |
| ---------- | ------ | ------- | ------------------------------------------------------ |
| `enabled`  | bool   | `true`  | Play sound effect                                      |
| `file`     | string | `""`    | Path to MP3 file (relative to project_dir or absolute) |
| `volume`   | float  | `0.5`   | Playback volume (0.0–1.0, passed to `afplay -v`)       |
| `delay_ms` | int    | `200`   | Delay after sound before voice (ms)                    |

#### Voice Settings (per hook)

| Option    | Type   | Default      | Description                                                       |
| --------- | ------ | ------------ | ----------------------------------------------------------------- |
| `enabled` | bool   | `true`       | Speak notification                                                |
| `name`    | string | `"Victoria"` | macOS voice name                                                  |
| `volume`  | float  | `0.6`        | Speech volume (0.0–1.0, controls `afplay -v` on rendered `.aiff`) |
| `rate`    | int    | `280`        | Words per minute                                                  |

#### Summary Settings (stop hook only)

| Option           | Type   | Default       | Description                                            |
| ---------------- | ------ | ------------- | ------------------------------------------------------ |
| `mode`           | string | `"sentences"` | `"sentences"` or `"characters"` — which limit to apply |
| `max_sentences`  | int    | `2`           | Max sentences to speak (sentence mode)                 |
| `max_characters` | int    | `200`         | Max characters to speak (character mode)               |
| `start`          | string | `"action"`    | `"action"` (find action verbs) or `"beginning"`        |

#### Message Settings

| Option               | Hook           | Type   | Description                                  |
| -------------------- | -------------- | ------ | -------------------------------------------- |
| `message_mode`       | ask_user       | string | `"extract"` (actual question) or `"generic"` |
| `default_message`    | ask_user       | string | Fallback if extraction fails                 |
| `message_template`   | permission     | string | Template with `{tool_name}`                  |
| `idle_message`       | notification   | string | Spoken for `idle_prompt`                     |
| `auth_message`       | notification   | string | Spoken for `auth_success`                    |
| `default_message`    | notification   | string | Fallback for other notification types        |
| `message_template`   | subagent_start | string | Template with `{agent_type}`                 |
| `message_template`   | subagent_stop  | string | Template with `{agent_type}`                 |
| `message_template`   | teammate_idle  | string | Template with `{teammate_name}`              |
| `message_template`   | task_completed | string | Template with `{task_subject}`               |
| `max_subject_length` | task_completed | int    | Truncate long subjects with "..."            |
| `message_template`   | tool_failure   | string | Template with `{tool_name}`                  |
| `message`            | pre_compact    | string | Static message spoken before compaction      |

### Available macOS Voices

`say -v '?'` is the only authority — the installed set varies by macOS version and by which
voices have actually been downloaded. Checked on this Mac 2026-07-30: `Samantha`, `Daniel`,
`Karen`, `Moira` and `Tessa` are listed; **`Alex` is not, and neither is `Victoria`** — which
is the voice `config.yaml` currently sets for every hook.

**`say` never errors on an unknown voice.** Verified 2026-07-30: a deliberately bogus
`say -v ZZZNotARealVoice` exits 0, exactly like a valid name. So a mistyped or uninstalled
voice degrades silently — you get speech in some other voice, with nothing in the logs to
say so. If a hook sounds wrong, check the configured name against `say -v '?'` before
looking anywhere else.

> **Settled 2026-07-30, by ear (the owner — no tooling can do this):** the configured
> `Victoria` does produce the intended voice in practice, most likely the system default
> resolving through an unlisted name. It is deliberately left as `Victoria`; do not
> "correct" it to a name from the list.
>
> The silent-fallback behaviour above still matters, though: because `say` never errors,
> a genuinely mistyped voice would also sound plausible. Change voice names deliberately
> and listen once afterwards — there is no log line to check.

---

## 7. State Management & Deduplication

### Why Deduplication?

Multiple hooks fire for the same user-facing event. Without deduplication, the
user hears duplicate notifications:

- `PermissionRequest` fires, then `Stop` fires
- `PostToolUse` (AskUserQuestion) fires, then `Stop` fires
- `Notification` (idle_prompt) fires, then `Stop` fires
- `SubagentStop` fires, then `Stop` fires
- `PostToolUseFailure` fires, then `Stop` fires

### State Storage

```text
/tmp/claude-hooks/
└── .hook_state_{session_id}.json
```

Example state file:

```json
{
  "timestamp": 1706054321.123,
  "handled": ["ask_user", "permission"],
  "last_spoken_hash": "a1b2c3d4e5f6..."
}
```

### Deduplication Markers

| Marker              | Set by                              | Prevents                               |
| ------------------- | ----------------------------------- | -------------------------------------- |
| `ask_user`          | `AskUserQuestionHandler`            | Stop re-announcing a question          |
| `permission`        | `PermissionRequestHandler`          | Stop re-announcing a permission prompt |
| `notification_idle` | `NotificationHandler` (idle_prompt) | Stop re-announcing idle state          |
| `subagent_stop`     | `SubagentStopHandler`               | Stop re-announcing subagent completion |
| `tool_failure`      | `PostToolUseFailureHandler`         | Stop re-announcing a failure           |

### When Dedup Is Checked

The stop handler checks dedup markers **only when it detects that Claude is
waiting for input** (pending tool_use, text ending with `?`, or AskUserQuestion
tool). If a marker exists, the input-waiting notification is suppressed — but
the handler falls through to summary extraction. If there is transcript text
available from an earlier assistant message, it speaks the summary instead of
going silent.

Task-completion summaries (the normal "Claude finished work" path) **never
consult dedup state**. This is intentional: when a permission or question hook
fires and Claude then continues working and eventually stops, the stop is a
genuinely new event — the task-completion summary should always play through.

### Repeated Summary Dedup

During a burst of tool calls in the same turn (e.g., 4 parallel `Edit` calls),
the transcript text does not change between calls. Without mitigation, the
permission handler would speak the same summary repeatedly.

The state module stores an MD5 hash of the last spoken summary
(`last_spoken_hash`). Before speaking a transcript summary, the permission
handler calls `was_already_spoken()` to check if the hash matches. If it does,
it falls back to the template ("Approve {tool_name}?") instead of repeating
the same sentence.

The hash shares the per-session state file and its 60-second expiry, so stale
hashes from a previous turn do not suppress new summaries.

### State Lifecycle

```text
   Session Start                                         Session End
        │                                                      │
        ▼                                                      ▼
   ┌─────────┐   Event 1      ┌──────────────┐   Event 2 ┌─────────┐
   │ No      │ ──────────────►│ State Exists  │ ────────►│ State   │
   │ State   │   mark_handled │              │  was_     │ Checked │
   │ File    │                │ handled:     │  handled  │         │
   └─────────┘                │  - ask_user  │  → True   └─────────┘
                              │ last_spoken  │
                              │  _hash: "a1."│
                              └──────┬───────┘
                                     │
                                     │ After 60 seconds
                                     ▼
                              ┌──────────────┐
                              │ State        │
                              │ Expired      │
                              │ Deleted      │
                              └──────────────┘
```

### State API

```python
from lib.state import (
    mark_handled,
    was_handled,
    set_last_spoken,
    was_already_spoken,
    clear_state,
    cleanup_stale_states,
)

# Mark event as handled (prevents duplicate in Stop handler)
mark_handled(session_id, "ask_user")

# Check if already handled
if was_handled(session_id, "ask_user"):
    return  # Skip notification

# Store hash of spoken message (repeated-summary dedup)
set_last_spoken(session_id, "Created the auth module.")

# Check if same message was already spoken
if was_already_spoken(session_id, "Created the auth module."):
    # Fall back to template instead of repeating

# Clear state (for testing)
clear_state(session_id)

# Cleanup old states (auto-called)
cleanup_stale_states()
```

---

## 8. Audio Pipeline

### Notification Sequence

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                       play_notification() Sequence                            │
└──────────────────────────────────────────────────────────────────────────────┘

Time ──────────────────────────────────────────────────────────────────────────►

     │                    │                      │
     ▼                    ▼                      ▼
┌───────────┐       ┌─────────┐        ┌──────────────────┐
│   Sound   │       │  Delay  │        │      Voice       │
│   Effect  │       │  200ms  │        │                  │
│           │       │         │        │  1. Render .aiff │
│  afplay   │ ───►  │  sleep  │  ───►  │  2. Play .aiff   │
│  -v 0.2   │       │         │        │  3. Cleanup      │
│           │       │(only if │        │     (30s thread) │
│           │       │ sound   │        │                  │
│           │       │ played) │        │                  │
└───────────┘       └─────────┘        └──────────────────┘
  ~0.5s               0.2s              ~1-5s (varies)
```

### Sound Playback

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                            Sound Playback                                     │
│                                                                               │
│  Input: file path, volume (0.0-1.0)                                          │
│                                                                               │
│  Command: afplay -v {volume} {file_path}                                     │
│                                                                               │
│  Example: afplay -v 0.2 .claude/sounds/ui_open_1.mp3                        │
│                                                                               │
│  Notes:                                                                       │
│  - Runs via Popen (start_new_session=True) — non-blocking                    │
│  - macOS only (uses afplay)                                                  │
│  - Volume is linear scale, clamped to 0.0-1.0                               │
│  - Silently fails if file missing                                            │
│  - Resolves relative paths against project_dir                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Voice Playback (Render-to-File)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                   Voice Playback (render-to-file approach)                    │
└──────────────────────────────────────────────────────────────────────────────┘

        Start                                              Finish
          │                                                  │
          ▼                                                  ▼
    ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐
    │ Create    │───►│ Render to │───►│ Play with │───►│ Cleanup   │
    │ temp file │    │ .aiff     │    │ volume    │    │ thread    │
    └───────────┘    └───────────┘    └───────────┘    └───────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
    NamedTempFile    say -v Victoria   afplay -v 0.2     daemon thread
    (suffix=.aiff)   -r 350           /tmp/xxx.aiff      sleeps 30s
                     -o /tmp/xxx.aiff                    then unlinks
                     "message"                           temp file
                     (timeout: 10s)

No system volume manipulation. Volume is controlled entirely through
afplay's -v flag on the rendered .aiff file.
```

---

## 9. Shell Hook Scripts

> **The per-script inventory lives in [`.claude/hooks/README.md`](../hooks/README.md),
> not here.** This section used to describe four scripts individually. There are now
> **14**, and the duplicated copies here fell four months behind — so they were retired
> on 2026-07-30 rather than maintained in two places. That file has one section per
> hook, with its event, matcher, behaviour, and (importantly) whether it is wired at
> project or user level.
>
> What remains below is architecture rather than inventory: how inline hooks differ from
> script hooks, and how the audit log works. Both are stable regardless of which
> individual hooks happen to be installed.

### Inline Hooks

Three inline hooks are registered directly in `settings.json` without separate
script files:

#### PostToolUse prettier (Edit|Write)

```text
jq -r '.tool_input.file_path // .tool_input.filePath // empty' \
  | xargs -I{} pnpm dlx prettier --write {} 2>/dev/null || true
```

Auto-formats files after Edit/Write. Failures silently ignored.

#### PostToolUse markdownlint (Edit|Write)

```text
jq -r '.tool_input.file_path // .tool_input.filePath // empty' \
  | xargs -I{} sh -c 'case "{}" in *.md) pnpm dlx markdownlint-cli --fix "{}" 2>/dev/null ;; esac' || true
```

Auto-fixes markdown lint issues on `.md` files after Edit/Write. Failures
silently ignored. Config in `.markdownlint.jsonc`.

#### SessionStart compact echo

```text
echo 'Context compacted. Reminder: use uv for Python, pnpm or bun for Node.js. Read CLAUDE.md for project conventions.'
```

Re-injects project conventions after context compaction so Claude retains
tooling preferences.

### Audit Logging

Both `validate-bash.sh` and `protect-files.sh` append timestamped entries to
`.claude/hooks/security.log` whenever a command or file edit is blocked:

```text
[2026-02-18T14:30:22Z] BLOCKED validate-bash "Force push to main/master" "git push --force main"
[2026-02-18T14:31:05Z] BLOCKED protect-files "Secrets file" ".env.local"
```

The log is append-only and never truncated by the hooks. Created on first
blocked event.

---

## 10. Quick Reference

### Event → Handler Routing

| Event                | Matcher                          | Handler                     | Sound                  | Message                                 |
| -------------------- | -------------------------------- | --------------------------- | ---------------------- | --------------------------------------- |
| `Stop`               | (none)                           | `StopHandler`               | `ui_open_1.mp3`        | Transcript summary or question          |
| `PostToolUse`        | `AskUserQuestion`                | `AskUserQuestionHandler`    | `bell_ring_1.mp3`      | Extracted question text                 |
| `PermissionRequest`  | (none)                           | `PermissionRequestHandler`  | `bell_call.mp3`        | Transcript summary or "Approve {tool}?" |
| `Notification`       | `idle_prompt\|auth_success\|...` | `NotificationHandler`       | `bell_ring_1.mp3`      | Mapped message (idle/auth/default)      |
| `SubagentStart`      | (none)                           | `SubagentStartHandler`      | `coin_simple.mp3`      | "Subagent {type} started"               |
| `SubagentStop`       | (none)                           | `SubagentStopHandler`       | `marimba_complete.mp3` | "Subagent {type} finished"              |
| `TeammateIdle`       | (none)                           | `TeammateIdleHandler`       | `marimba_nudge_1.mp3`  | "{name} is idle"                        |
| `TaskCompleted`      | (none)                           | `TaskCompletedHandler`      | `harp_finish.mp3`      | "Task completed: {subject}"             |
| `PostToolUseFailure` | (none)                           | `PostToolUseFailureHandler` | `error_buzz.mp3`       | "{tool} failed"                         |
| `UserPromptSubmit`   | (none)                           | `UserPromptSubmitHandler`   | (disabled)             | (silent — returns None)                 |
| `PreCompact`         | (none)                           | `PreCompactHandler`         | `blink.mp3`            | "Compacting context"                    |

### Shell Script Routing

**Illustrative, not exhaustive** — this shows the event-to-script routing _pattern_ as of
February 2026. The current set is larger (14 scripts); see
[`.claude/hooks/README.md`](../hooks/README.md) for the live list.

| Event          | Matcher                  | Script                 | Behavior                   |
| -------------- | ------------------------ | ---------------------- | -------------------------- |
| `SessionStart` | `startup\|resume`        | `session-checks.sh`    | Git status + .env check    |
| `SessionStart` | `compact`                | (inline echo)          | Conventions reminder       |
| `PreToolUse`   | `Bash`                   | `validate-bash.sh`     | Block destructive commands |
| `PreToolUse`   | `Bash`                   | `pre-commit-check.sh`  | Lint/build before commit   |
| `PreToolUse`   | `Edit\|Write`            | `protect-files.sh`     | Block protected file edits |
| `PostToolUse`  | `Edit\|Write`            | (inline prettier)      | Auto-format                |
| `PostToolUse`  | `Edit\|Write`            | (inline markdownlint)  | Auto-fix .md files         |
| `SessionEnd`   | `prompt_input_exit\|...` | `export_transcript.sh` | Export transcript          |

### Debug Mode

Enable in `config.yaml`:

```yaml
global:
  debug: true
  debug_dir: "Temp"
```

Or via environment: `HOOK_DEBUG=1`

Output files:

- `Temp/hook_debug.log` — handler execution trace
- `Temp/hook_raw_input.json` — raw stdin JSON (stop handler only)
- `Temp/transcript_dump.jsonl` — copy of transcript (stop handler only)
- `Temp/hook_error.log` — exception details (on error)

### Common Issues

| Issue                               | Cause                               | Fix                                            |
| ----------------------------------- | ----------------------------------- | ---------------------------------------------- |
| Duplicate notifications             | Missing deduplication               | Check `_pre_message_hook()` sets marker        |
| No voice output                     | Volume 0 or voice disabled          | Check `voice.enabled` and `voice.volume`       |
| Sound but no voice                  | Long `delay_ms` or `say` timeout    | Reduce `delay_ms`; check `say` works           |
| "Approve Bash?" instead of summary  | No transcript text found            | Ensure `transcript_path` is in stdin JSON      |
| Same summary repeated during bursts | `was_already_spoken` not called     | Check permission handler uses last_spoken hash |
| Hook timeout (5s) exceeded          | Voice message too long              | Reduce summary length or disable voice         |
| Protected file edit blocked         | `protect-files.sh` exit code 2      | Check if file matches protected patterns       |
| Git commit blocked by lint          | `pre-commit-check.sh` ran lint gate | Fix lint errors, then retry commit             |
| `session-checks.sh` fails           | `jq` not installed                  | Install jq: `brew install jq`                  |

### Adding a New Handler

1. Create handler file in `lib/handlers/` (inherit from `BaseHandler`)
2. Implement: `should_handle()`, `get_message()`, `get_audio_settings()`
3. Override `_pre_message_hook()` if dedup marker needed
4. Override `_resolve_audio_settings()` if dynamic audio switching needed
5. Add import to `lib/handlers/__init__.py`
6. Add routing in `hook_runner.py` (if-elif for the event name)
7. Add dataclass in `lib/config.py` (extend `HookConfig`)
8. Add field to `Config` dataclass
9. Add loading block in `load_config()`
10. Add config section in `config.yaml`
11. Register event in `settings.json` with matcher and timeout
12. If dedup needed, add marker check in `StopHandler._check_deduplication()`

### Dependencies

- macOS (uses `say` and `afplay` for audio)
- Python 3.11+ (for `hook_runner.py`)
- PyYAML (declared via PEP 723 inline metadata in `hook_runner.py`)
- `jq` (used by shell hooks to parse stdin JSON)
- `pnpm` (used by prettier, markdownlint, and Node.js pre-commit checks)
- `uv` (used by Python pre-commit checks and `hook_runner.py` execution)
- `markdownlint-cli` (used via `pnpm dlx`)
- `dotenvx` (optional — `.env` encryption check in `session-checks.sh`)
- `claude-code-transcripts` (optional — transcript export in `export_transcript.sh`)

### Testing

```bash
PYTHONPATH=.claude/hooks uv run --with pytest pytest .claude/hooks/tests/ -v
```

| File                 | Covers                                                                         |
| -------------------- | ------------------------------------------------------------------------------ |
| `test_state.py`      | Dedup state: mark/check, expiry, session isolation, corrupted files, cleanup   |
| `test_summary.py`    | Text extraction: action verbs, sentence/character modes, questions, edge cases |
| `test_transcript.py` | JSONL parsing: text extraction, tool use detection, malformed input            |

---

## Appendix: Available Sound Files

```text
.claude/sounds/
├── bell_call.mp3          # Permission requests
├── bell_confident.mp3
├── bell_ring_1.mp3        # Questions, notifications
├── bell_ring_2.mp3
├── bell_ring_3.mp3
├── blink.mp3              # Pre-compact
├── coin_dual.mp3
├── coin_simple.mp3        # Subagent start
├── error_buzz.mp3         # Tool failures
├── error_deny.mp3
├── error_fast.mp3
├── error_slow.mp3
├── error_synth.mp3
├── glitch1.mp3
├── glitch_distortion.mp3
├── glitch_shutdown.mp3
├── harp_finish.mp3        # Task completed
├── harp_message.mp3
├── jump1.mp3
├── marimba_complete.mp3   # Subagent stop
├── marimba_finish.mp3
├── marimba_nudge_1.mp3    # Teammate idle
├── marimba_nudge_2.mp3
├── marimba_success.mp3
├── marimba_warning.mp3
├── ping_cute.mp3
├── preview.mp3
├── ui_open_1.mp3          # Task completion (stop)
├── ui_open_2.mp3
└── ui_open_3.mp3
```
