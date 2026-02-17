# Claude Code Hook Runner

Audio notification system for Claude Code. Plays sound effects and speaks status messages when Claude finishes a task, asks a question, or requests permission.

## How it works

`hook_runner.py` is the single entrypoint. Claude Code pipes JSON to stdin on hook events. The runner detects the event type and routes to the appropriate handler:

| Hook Event | Handler | Triggers when |
|---|---|---|
| `Stop` | `StopHandler` | Claude finishes a task or stops |
| `PostToolUse` (AskUserQuestion) | `AskUserQuestionHandler` | Claude asks you a question (auto-approved) |
| `PermissionRequest` | `PermissionRequestHandler` | Claude needs tool approval |

Each handler can play a **sound effect** (via `afplay`) and/or **speak a message** (via `say` rendered to file, then `afplay` for playback). Both are independently configurable.

### Hook event flow

When Claude calls a tool, the event flow depends on whether the tool is auto-approved:

- **Auto-approved tool**: `PostToolUse` fires directly. For `AskUserQuestion`, the `AskUserQuestionHandler` extracts and speaks the actual question text.
- **Tool requiring permission**: `PermissionRequest` fires first (before execution). If `AskUserQuestion` needs permission, the `PermissionRequestHandler` extracts the question from `tool_input` and speaks it instead of the generic "Approve {tool_name}?" message. After approval, `PostToolUse` would also fire, but deduplication prevents a double notification.

This means you hear the actual question text regardless of whether the tool is auto-approved or needs permission.

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

Each hook (`stop`, `ask_user_question`, `permission_request`) has:

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

### Ask user question hook extras

```yaml
message_mode: "extract"                        # "extract" pulls actual question text, "generic" uses default
default_message: "Claude has a question for you"
```

### Permission request hook extras

```yaml
message_template: "Approve {tool_name}?"    # {tool_name} is replaced with the tool name
```

For `AskUserQuestion`, the handler ignores the template and speaks the actual question text extracted from `tool_input`. Falls back to the template if the question can't be parsed.

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
| `PermissionRequestHandler` | `_pre_message_hook` | Same — marks permission as handled |
| `StopHandler` | `_resolve_audio_settings` | Selects input-waiting vs. task-completion audio settings based on a flag set during `get_message()` |

## File structure

```
.claude/hooks/
  hook_runner.py          # Entrypoint — reads stdin, routes to handler
  config.yaml             # All configuration
  lib/
    audio.py              # play_sound(), speak(), play_notification()
    config.py             # YAML loading, dataclass definitions
    summary.py            # Text summarization (sentence extraction, action verb detection)
    transcript.py         # Transcript JSONL parsing, file discovery
    state.py              # Deduplication state (prevents double notifications)
    handlers/
      base.py             # BaseHandler ABC — Template Method in handle()
      stop.py             # StopHandler — overrides _resolve_audio_settings()
      ask_user.py         # AskUserQuestionHandler — overrides _pre_message_hook()
      permission.py       # PermissionRequestHandler — overrides _pre_message_hook()
```

## Deduplication

The `PermissionRequest` and `PostToolUse` (AskUserQuestion) hooks fire *before* the `Stop` hook. Without deduplication, you'd hear the same notification twice when Claude is waiting for input — the earlier hook speaks the prompt, then the stop handler detects the same input-waiting state and tries to speak it again.

The state module (`lib/state.py`) writes a short-lived marker to `/tmp/claude-hooks/` when a permission or question event is handled. The stop handler checks for these markers **only when it detects that Claude is waiting for input** (pending tool_use, text ending with `?`, or AskUserQuestion tool). If a marker exists, the input-waiting notification is suppressed.

Task-completion summaries (the normal "Claude finished work" path) **never consult dedup state**. This is intentional: when a permission or question hook fires and Claude then continues working and eventually stops, the stop is a genuinely new event — the task-completion summary should always play through.

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
