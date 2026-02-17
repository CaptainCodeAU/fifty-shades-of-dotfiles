# Claude Code Hook Runner

Audio notification system for Claude Code. Plays sound effects and speaks status messages when Claude finishes a task, asks a question, or requests permission.

## How it works

`hook_runner.py` is the single entrypoint. Claude Code pipes JSON to stdin on hook events. The runner detects the event type and routes to the appropriate handler:

| Hook Event | Handler | Triggers when |
|---|---|---|
| `Stop` | `StopHandler` | Claude finishes a task or stops |
| `PostToolUse` (AskUserQuestion) | `AskUserQuestionHandler` | Claude asks you a question |
| `PermissionRequest` | `PermissionRequestHandler` | Claude needs tool approval |

Each handler can play a **sound effect** (via `afplay`) and/or **speak a message** (via `say` rendered to file, then `afplay` for playback). Both are independently configurable.

## Configuration

All settings live in `config.yaml`.

### Global

```yaml
global:
  debug: false        # Write debug logs to debug_dir
  debug_dir: "Temp"   # Relative to project_dir
  project_dir: ""     # Set via $HOOK_PROJECT_DIR env var
```

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
      base.py             # BaseHandler ABC
      stop.py             # StopHandler
      ask_user.py         # AskUserQuestionHandler
      permission.py       # PermissionRequestHandler
```

## Deduplication

The `PermissionRequest` and `PostToolUse` (AskUserQuestion) hooks fire *before* the `Stop` hook. Without deduplication, you'd hear the same notification twice. The state module (`lib/state.py`) writes a short-lived marker to `/tmp/claude-hooks/` when a permission or question event is handled, and the stop handler checks for it before playing.

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
