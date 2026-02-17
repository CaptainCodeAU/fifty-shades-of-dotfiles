# Claude Code Hook Runner

Audio notification system for Claude Code. Plays sound effects and speaks status messages when Claude finishes a task, asks a question, or requests permission.

## How it works

`hook_runner.py` is the single entrypoint. Claude Code pipes JSON to stdin on hook events. The runner detects the event type and routes to the appropriate handler:

| Hook Event | Handler | Triggers when |
|---|---|---|
| `Stop` | `StopHandler` | Claude finishes a task or stops |
| `PostToolUse` (AskUserQuestion) | `AskUserQuestionHandler` | Claude asks you a question (auto-approved) |
| `PermissionRequest` | `PermissionRequestHandler` | Claude needs tool approval |
| `Notification` | `NotificationHandler` | System notification (idle prompt, auth success) |
| `SubagentStart` | `SubagentStartHandler` | A subagent is launched |
| `SubagentStop` | `SubagentStopHandler` | A subagent finishes |
| `TeammateIdle` | `TeammateIdleHandler` | A teammate goes idle |
| `TaskCompleted` | `TaskCompletedHandler` | A task is completed |
| `PostToolUseFailure` | `PostToolUseFailureHandler` | A tool use fails (skips user interruptions) |
| `UserPromptSubmit` | `UserPromptSubmitHandler` | User submits a prompt (disabled by default) |
| `PreCompact` | `PreCompactHandler` | Context is about to be compacted |

Each handler can play a **sound effect** (via `afplay`) and/or **speak a message** (via `say` rendered to file, then `afplay` for playback). Both are independently configurable.

### Hook event flow

When Claude calls a tool, the event flow depends on whether the tool is auto-approved:

- **Auto-approved tool**: `PostToolUse` fires directly. For `AskUserQuestion`, the `AskUserQuestionHandler` extracts and speaks the actual question text.
- **Tool requiring permission**: `PermissionRequest` fires first (before execution). The `PermissionRequestHandler` reads the transcript and speaks a summary of the assistant's last text message (the same summarization logic the stop handler uses). For `AskUserQuestion` specifically, it extracts the question from `tool_input` instead. Falls back to "Approve {tool_name}?" only when there is no text to summarize. After approval, `PostToolUse` would also fire, but deduplication prevents a double notification.

This means you hear what Claude actually said (or asked) rather than a generic "Approve Bash?" prompt.

## Configuration

All settings live in `config.yaml`.

### Global

```yaml
global:
  debug: false        # Write debug logs to debug_dir
  debug_dir: "Temp"   # Relative to project_dir
  project_dir: ""     # Resolved automatically (see below)
```

`project_dir` is resolved in order: (1) value from `config.yaml`, (2) `$HOOK_PROJECT_DIR` env var, (3) current working directory. Claude Code sets the hook's CWD to the project root, so leaving `project_dir: ""` in the config works out of the box — no env var needed. Sound file paths, debug output, and transcript fallback all resolve relative to this directory.

### Per-hook settings

Each hook has:

- **sound** — play an audio file
  - `enabled`: toggle on/off
  - `file`: path to sound file (relative to project_dir or absolute)
  - `volume`: 0.0 to 1.0
  - `delay_ms`: pause before speech starts (if both sound and voice are enabled)

- **voice** — text-to-speech
  - `enabled`: toggle on/off
  - `name`: macOS voice (e.g. "Victoria", "Samantha", "Daniel")
  - `volume`: 0.0 to 1.0 (controls `afplay -v`, no system volume changes)
  - `rate`: words per minute

### Stop hook extras

```yaml
summary:
  mode: "sentences"      # "sentences" or "characters"
  max_sentences: 2       # how many sentences to speak
  max_characters: 200    # max length in characters mode
  start: "action"        # "action" finds first action verb, "beginning" starts from top
```

The stop handler reads Claude's transcript, extracts a summary of what it did, and speaks it. It also detects if Claude is waiting for input (question or permission) and uses the appropriate voice/sound settings for that case.

When text ends with `?`, the handler uses input-waiting audio settings but prioritizes speaking the action summary over the trailing question. For example, "Committed as 034f960. Want me to push?" speaks the commit summary, not the follow-up question. If no action summary is found (the text is purely a question like "Should I continue?"), it falls back to speaking the question itself.

### Ask user question hook extras

```yaml
message_mode: "extract"                        # "extract" pulls actual question text, "generic" uses default
default_message: "Claude has a question for you"
```

### Permission request hook extras

```yaml
message_template: "Approve {tool_name}?"    # {tool_name} is replaced with the tool name
```

### Notification hook extras

```yaml
idle_message: "Claude is idle"         # Spoken for idle_prompt notifications
auth_message: "Auth successful"        # Spoken for auth_success notifications
default_message: "Notification"        # Fallback for unrecognized notification types
```

### Subagent hooks extras

```yaml
# subagent_start / subagent_stop
message_template: "Subagent {agent_type} started"   # {agent_type} is replaced
```

### Teammate idle hook extras

```yaml
message_template: "{teammate_name} is idle"   # {teammate_name} is replaced
```

### Task completed hook extras

```yaml
message_template: "Task completed: {task_subject}"   # {task_subject} is replaced
max_subject_length: 80                               # Truncates long subjects with "..."
```

### Post tool use failure hook extras

```yaml
message_template: "{tool_name} failed"   # {tool_name} is replaced
```

The handler skips events where `is_interrupt` is `true` (user-caused interruptions, not real failures).

### User prompt submit hook

Disabled by default (`enabled: false`). Playing audio on your own input is redundant. Exists as a skeleton for future use — `get_message()` returns `None`.

### Pre-compact hook extras

```yaml
message: "Compacting context"   # Static message spoken before compaction
```

The permission handler resolves the spoken message in priority order:

1. **AskUserQuestion**: extracts the actual question text from `tool_input`.
2. **Transcript text**: reads the transcript to find the most recent assistant message with text content, then summarizes it using the stop handler's `summary` config. This handles the common case where Claude writes a detailed explanation and then calls a tool — you hear the summary instead of "Approve Bash?". If the same summary was already spoken (e.g., during a burst of tool calls in one turn), it falls back to the template instead of repeating itself.
3. **Template fallback**: uses `message_template` only when no text is available (e.g., the assistant message was purely tool calls with no prose), or when the transcript summary was already spoken.

## Handler architecture

`BaseHandler.handle()` implements a Template Method that all handlers share:

1. Log handler name, hook event, tool name
2. `should_handle(data)` — gate (abstract)
3. `_pre_message_hook(data)` — optional pre-processing (no-op by default)
4. `get_message(data)` — extract the message to speak (abstract)
5. `_resolve_audio_settings(data)` — pick audio settings (defaults to `get_audio_settings()`)
6. `play_notification()` — play sound and/or speak
7. Write debug log

Subclasses override only the steps they need:

| Handler | Overrides | Why |
|---|---|---|
| `AskUserQuestionHandler` | `_pre_message_hook` | Calls `mark_handled()` before message extraction for dedup |
| `PermissionRequestHandler` | `_pre_message_hook`, `get_message` | Marks permission as handled; reads transcript for text summary before falling back to template |
| `StopHandler` | `_resolve_audio_settings` | Selects input-waiting vs. task-completion audio settings based on a flag set during `get_message()` |
| `NotificationHandler` | `_pre_message_hook` | Marks `notification_idle` for Stop dedup when type is `idle_prompt` |
| `SubagentStopHandler` | `_pre_message_hook` | Marks `subagent_stop` for Stop dedup |
| `PostToolUseFailureHandler` | `should_handle`, `_pre_message_hook` | Skips user interruptions (`is_interrupt`); marks `tool_failure` for Stop dedup |
| `UserPromptSubmitHandler` | `get_message` | Returns `None` — silent skeleton (disabled by default) |

## File structure

```
.claude/hooks/
  hook_runner.py          # Entrypoint — reads stdin, routes to handler
  config.yaml             # All configuration
  lib/
    audio.py              # play_sound(), speak(), play_notification()
    config.py             # YAML loading, dataclass definitions
    summary.py            # Text summarization (sentence extraction, action verb detection)
    transcript.py         # Transcript JSONL parsing, file discovery, text extraction
    state.py              # Deduplication state (prevents double notifications)
    handlers/
      base.py             # BaseHandler ABC — Template Method in handle()
      stop.py             # StopHandler — overrides _resolve_audio_settings()
      ask_user.py         # AskUserQuestionHandler — overrides _pre_message_hook()
      permission.py       # PermissionRequestHandler — transcript summary + dedup
      notification.py     # NotificationHandler — idle/auth notifications + dedup
      subagent_start.py   # SubagentStartHandler — subagent launch
      subagent_stop.py    # SubagentStopHandler — subagent completion + dedup
      teammate_idle.py    # TeammateIdleHandler — teammate went idle
      task_completed.py   # TaskCompletedHandler — task completion with subject truncation
      tool_failure.py     # PostToolUseFailureHandler — tool failures + dedup
      user_prompt_submit.py # UserPromptSubmitHandler — silent skeleton (disabled)
      pre_compact.py      # PreCompactHandler — context compaction
```

## Deduplication

Several hooks fire *before* the `Stop` hook. Without deduplication, you'd hear the same notification twice — the earlier hook speaks the prompt, then the stop handler detects the same state and tries to speak it again.

The state module (`lib/state.py`) writes a short-lived marker to `/tmp/claude-hooks/` when an event is handled. The stop handler checks for these markers **only when it detects that Claude is waiting for input** (pending tool_use, text ending with `?`, or AskUserQuestion tool). If a marker exists, the input-waiting notification is suppressed.

Dedup markers checked by the stop handler:

| Marker | Set by | Prevents |
|---|---|---|
| `ask_user` | `AskUserQuestionHandler` | Stop re-announcing a question |
| `permission` | `PermissionRequestHandler` | Stop re-announcing a permission prompt |
| `notification_idle` | `NotificationHandler` (idle_prompt) | Stop re-announcing idle state |
| `tool_failure` | `PostToolUseFailureHandler` | Stop re-announcing a failure |
| `subagent_stop` | `SubagentStopHandler` | Stop re-announcing subagent completion |

Task-completion summaries (the normal "Claude finished work" path) **never consult dedup state**. This is intentional: when a permission or question hook fires and Claude then continues working and eventually stops, the stop is a genuinely new event — the task-completion summary should always play through.

### Repeated summary dedup

During a burst of tool calls in the same turn (e.g., 4 parallel `Edit` calls), the transcript text doesn't change between calls — so the permission handler would speak the same summary repeatedly. To prevent this, `state.py` stores an MD5 hash of the last spoken summary. Before speaking a transcript summary, the permission handler checks if it matches the stored hash. If it does, it falls back to the template ("Approve {tool_name}?") instead of repeating the same sentence.

The hash is stored in the same per-session state file as the dedup markers, so it shares the same 60-second expiry. This means stale hashes from a previous turn won't suppress a new summary.

State files auto-expire after 60 seconds.

## Debugging

Set `global.debug: true` in `config.yaml` (or `HOOK_DEBUG=1` env var). Debug output goes to `{project_dir}/{debug_dir}/`:

- `hook_debug.log` — handler execution trace
- `hook_raw_input.json` — raw stdin data (stop handler only)
- `transcript_dump.jsonl` — copy of the transcript file (stop handler only)

## Dependencies

- macOS (uses `say` and `afplay`)
- Python 3.11+
- PyYAML (declared via PEP 723 inline metadata in `hook_runner.py`)
