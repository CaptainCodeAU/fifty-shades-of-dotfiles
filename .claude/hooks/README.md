# Claude Code Hooks

Hook scripts for Claude Code. Includes an audio notification system (`hook_runner.py`), session lifecycle scripts, code quality gates, and safety guardrails.

All hooks are registered in `.claude/settings.json`. Claude Code pipes JSON to stdin on every hook event — scripts read this JSON to inspect tool names, file paths, commands, and other context.

## Overview

| Script                  | Hook Event     | Matcher                            | Purpose                                                   |
| ----------------------- | -------------- | ---------------------------------- | --------------------------------------------------------- |
| `session-checks.sh`     | `SessionStart` | `startup\|resume`                  | Git status + `.env` encryption check                      |
| _(inline echo)_         | `SessionStart` | `compact`                          | Re-inject project conventions after compaction            |
| `validate-bash.sh`      | `PreToolUse`   | `Bash`                             | Block destructive commands (`rm -rf /`, force push, etc.) |
| `pre-commit-check.sh`   | `PreToolUse`   | `Bash`                             | Lint/build gate before `git commit`                       |
| `protect-files.sh`      | `PreToolUse`   | `Edit\|Write`                      | Block edits to `.env`, lockfiles, `.git/`                 |
| `hook_runner.py`        | Multiple       | Various                            | Audio notifications (sound + speech)                      |
| _(inline prettier)_     | `PostToolUse`  | `Edit\|Write`                      | Auto-format with prettier after file changes              |
| _(inline markdownlint)_ | `PostToolUse`  | `Edit\|Write`                      | Auto-fix markdown lint issues on `.md` files              |
| `export_transcript.sh`  | `SessionEnd`   | `prompt_input_exit\|logout\|other` | Export session transcript (skips `/clear`)                |

## Audio notification system

`hook_runner.py` is the entrypoint for audio hooks. Claude Code pipes JSON to stdin on hook events. The runner detects the event type and routes to the appropriate handler:

| Hook Event                      | Handler                     | Triggers when                                   |
| ------------------------------- | --------------------------- | ----------------------------------------------- |
| `Stop`                          | `StopHandler`               | Claude finishes a task or stops                 |
| `PostToolUse` (AskUserQuestion) | `AskUserQuestionHandler`    | Claude asks you a question (auto-approved)      |
| `PermissionRequest`             | `PermissionRequestHandler`  | Claude needs tool approval                      |
| `Notification`                  | `NotificationHandler`       | System notification (idle prompt, auth success) |
| `SubagentStart`                 | `SubagentStartHandler`      | A subagent is launched                          |
| `SubagentStop`                  | `SubagentStopHandler`       | A subagent finishes                             |
| `TeammateIdle`                  | `TeammateIdleHandler`       | A teammate goes idle                            |
| `TaskCompleted`                 | `TaskCompletedHandler`      | A task is completed                             |
| `PostToolUseFailure`            | `PostToolUseFailureHandler` | A tool use fails (skips user interruptions)     |
| `UserPromptSubmit`              | `UserPromptSubmitHandler`   | User submits a prompt (disabled by default)     |
| `PreCompact`                    | `PreCompactHandler`         | Context is about to be compacted                |

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
  debug: false # Write debug logs to debug_dir
  debug_dir: "Temp" # Relative to project_dir
  project_dir: "" # Resolved automatically (see below)
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
  mode: "sentences" # "sentences" or "characters"
  max_sentences: 2 # how many sentences to speak
  max_characters: 200 # max length in characters mode
  start: "action" # "action" finds first action verb, "beginning" starts from top
```

The stop handler reads Claude's transcript, extracts a summary of what it did, and speaks it. It also detects if Claude is waiting for input (question or permission) and uses the appropriate voice/sound settings for that case.

When text ends with `?`, the handler uses input-waiting audio settings but prioritizes speaking the action summary over the trailing question. For example, "Committed as 034f960. Want me to push?" speaks the commit summary, not the follow-up question. If no action summary is found (the text is purely a question like "Should I continue?"), it falls back to speaking the question itself.

### Ask user question hook extras

```yaml
message_mode: "extract" # "extract" pulls actual question text, "generic" uses default
default_message: "Claude has a question for you"
```

### Permission request hook extras

```yaml
message_template: "Approve {tool_name}?" # {tool_name} is replaced with the tool name
```

### Notification hook extras

```yaml
idle_message: "Claude is idle" # Spoken for idle_prompt notifications
auth_message: "Auth successful" # Spoken for auth_success notifications
default_message: "Notification" # Fallback for unrecognized notification types
```

### Subagent hooks extras

```yaml
# subagent_start / subagent_stop
message_template: "Subagent {agent_type} started" # {agent_type} is replaced
```

### Teammate idle hook extras

```yaml
message_template: "{teammate_name} is idle" # {teammate_name} is replaced
```

### Task completed hook extras

```yaml
message_template: "Task completed: {task_subject}" # {task_subject} is replaced
max_subject_length: 80 # Truncates long subjects with "..."
```

### Post tool use failure hook extras

```yaml
message_template: "{tool_name} failed" # {tool_name} is replaced
```

The handler skips events where `is_interrupt` is `true` (user-caused interruptions, not real failures).

### User prompt submit hook

Disabled by default (`enabled: false`). Playing audio on your own input is redundant. Exists as a skeleton for future use — `get_message()` returns `None`.

### Pre-compact hook extras

```yaml
message: "Compacting context" # Static message spoken before compaction
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

| Handler                     | Overrides                            | Why                                                                                                 |
| --------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `AskUserQuestionHandler`    | `_pre_message_hook`                  | Calls `mark_handled()` before message extraction for dedup                                          |
| `PermissionRequestHandler`  | `_pre_message_hook`, `get_message`   | Marks permission as handled; reads transcript for text summary before falling back to template      |
| `StopHandler`               | `_resolve_audio_settings`            | Selects input-waiting vs. task-completion audio settings based on a flag set during `get_message()` |
| `NotificationHandler`       | `_pre_message_hook`                  | Marks `notification_idle` for Stop dedup when type is `idle_prompt`                                 |
| `SubagentStopHandler`       | `_pre_message_hook`                  | Marks `subagent_stop` for Stop dedup                                                                |
| `PostToolUseFailureHandler` | `should_handle`, `_pre_message_hook` | Skips user interruptions (`is_interrupt`); marks `tool_failure` for Stop dedup                      |
| `UserPromptSubmitHandler`   | `get_message`                        | Returns `None` — silent skeleton (disabled by default)                                              |

## File structure

```
.claude/hooks/
  session-checks.sh       # SessionStart — git status + .env encryption check
  pre-commit-check.sh     # PreToolUse Bash — lint/build gate before git commit
  validate-bash.sh        # PreToolUse Bash — block destructive commands
  protect-files.sh        # PreToolUse Edit|Write — block edits to protected files
  export_transcript.sh    # SessionEnd — export session transcript
  hook_runner.py          # Audio entrypoint — reads stdin, routes to handler
  config.yaml             # Audio notification configuration
  security.log            # Audit log of blocked commands/edits (created on first block)
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
  tests/
    test_state.py         # Dedup state machine tests
    test_summary.py       # Text extraction tests
    test_transcript.py    # JSONL parsing tests
```

## Shell hook scripts

### session-checks.sh

Runs on `SessionStart` with matcher `startup|resume` (skips `compact` and `clear`). Performs two checks:

1. **Git status** — counts uncommitted changes and prints a one-line summary.
2. **`.env` encryption** — checks if `dotenvx` is installed, whether `.env` files are encrypted, and whether `.env.keys` exists for decryption. Warns about unencrypted variants (`.env.local`, `.env.development`, etc.).

### pre-commit-check.sh

Runs on `PreToolUse` for `Bash` tools. Reads the stdin JSON and extracts `tool_input.command`. If the command contains `git commit`, runs a project-appropriate quality gate:

- **Node.js** (`package.json`): `pnpm run lint && pnpm run build`
- **Python** (`pyproject.toml`): `uv run ruff check . && uv run ruff format --check .`

After the language-specific gate, **markdownlint** runs for all project types — it lints any staged `.md` files (`git diff --cached --name-only --diff-filter=ACM -- '*.md'`). No `--fix` here; this is a blocking gate. If it fails, Claude sees the errors and fixes them. Uses `pnpm dlx markdownlint-cli` consistently. Configuration lives in `.markdownlint.jsonc` at the repo root.

Non-commit Bash commands pass through with no effect.

### validate-bash.sh

Runs on `PreToolUse` for `Bash` tools. Reads the stdin JSON and blocks destructive commands by exiting with code 2:

- `rm -rf /` or `rm -rf ~` (root/home deletion)
- `git push --force`, `git push --force-with-lease`, or `git push -f` to `main` or `master`
- `git reset --hard` without a ref
- `git clean -fd` or `git clean -f -d` (removes untracked files)

Blocked commands are logged to `security.log` (see [Audit logging](#audit-logging)).

### protect-files.sh

Runs on `PreToolUse` for `Edit|Write` tools. Reads the stdin JSON and blocks edits to protected files by exiting with code 2:

- `.env`, `.env.keys`, `.env.local`, `.env.*` (except `.env.example`)
- Lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- `.git/` directory

Blocked edits are logged to `security.log` (see [Audit logging](#audit-logging)).

### export_transcript.sh

Runs on `SessionEnd` with matcher `prompt_input_exit|logout|other` (skips `/clear`). Reads `transcript_path` from stdin JSON and exports it via `claude-code-transcripts`. Respects `SKIP_SESSION_END_HOOK=1` to disable.

### PostToolUse prettier (inline)

Runs on `PostToolUse` for `Edit|Write` tools. Reads `tool_input.file_path` from stdin JSON and runs `pnpm dlx prettier --write` on the file. Failures are silently ignored (`|| true`) to avoid blocking Claude.

### PostToolUse markdownlint (inline)

Runs on `PostToolUse` for `Edit|Write` tools. Reads `tool_input.file_path` from stdin JSON and runs `pnpm dlx markdownlint-cli --fix` on the file, but only if it ends in `.md` (filtered via a `case` shell pattern). Failures are silently ignored (`|| true`, `2>/dev/null`) to avoid blocking Claude. Configuration lives in `.markdownlint.jsonc` at the repo root.

### SessionStart compact (inline)

Runs on `SessionStart` with matcher `compact`. Echoes a reminder of project conventions (uv for Python, pnpm for Node.js) so Claude retains context after compaction.

## Deduplication

Several hooks fire _before_ the `Stop` hook. Without deduplication, you'd hear the same notification twice — the earlier hook speaks the prompt, then the stop handler detects the same state and tries to speak it again.

The state module (`lib/state.py`) writes a short-lived marker to `/tmp/claude-hooks/` when an event is handled. The stop handler checks for these markers **only when it detects that Claude is waiting for input** (pending tool_use, text ending with `?`, or AskUserQuestion tool). If a marker exists, the input-waiting notification is suppressed.

Dedup markers checked by the stop handler:

| Marker              | Set by                              | Prevents                               |
| ------------------- | ----------------------------------- | -------------------------------------- |
| `ask_user`          | `AskUserQuestionHandler`            | Stop re-announcing a question          |
| `permission`        | `PermissionRequestHandler`          | Stop re-announcing a permission prompt |
| `notification_idle` | `NotificationHandler` (idle_prompt) | Stop re-announcing idle state          |
| `tool_failure`      | `PostToolUseFailureHandler`         | Stop re-announcing a failure           |
| `subagent_stop`     | `SubagentStopHandler`               | Stop re-announcing subagent completion |

Task-completion summaries (the normal "Claude finished work" path) **never consult dedup state**. This is intentional: when a permission or question hook fires and Claude then continues working and eventually stops, the stop is a genuinely new event — the task-completion summary should always play through.

### Repeated summary dedup

During a burst of tool calls in the same turn (e.g., 4 parallel `Edit` calls), the transcript text doesn't change between calls — so the permission handler would speak the same summary repeatedly. To prevent this, `state.py` stores an MD5 hash of the last spoken summary. Before speaking a transcript summary, the permission handler checks if it matches the stored hash. If it does, it falls back to the template ("Approve {tool_name}?") instead of repeating the same sentence.

The hash is stored in the same per-session state file as the dedup markers, so it shares the same 60-second expiry. This means stale hashes from a previous turn won't suppress a new summary.

State files auto-expire after 60 seconds.

## Audit logging

Both `validate-bash.sh` and `protect-files.sh` append a timestamped entry to `.claude/hooks/security.log` whenever a command or file edit is blocked. The log is append-only and never truncated by the hooks themselves.

Format:

```
[2026-02-18T14:30:22Z] BLOCKED validate-bash "Force push to main/master" "git push --force main"
[2026-02-18T14:31:05Z] BLOCKED protect-files "Secrets file" ".env.local"
```

The log file is created on first blocked event. It lives alongside the hook scripts so it's easy to find and review.

## Testing

Unit tests cover the Python library modules (`state.py`, `summary.py`, `transcript.py`).

Run tests:

```bash
PYTHONPATH=.claude/hooks uv run --with pytest pytest .claude/hooks/tests/ -v
```

Test files:

| File                 | Covers                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| `test_state.py`      | Dedup state machine: mark/check roundtrips, expiry, session isolation, corrupted files, cleanup   |
| `test_summary.py`    | Text extraction: action verb detection, sentence/character modes, question extraction, edge cases |
| `test_transcript.py` | JSONL parsing: text extraction, tool use detection, malformed input handling                      |

## Debugging

Set `global.debug: true` in `config.yaml` (or `HOOK_DEBUG=1` env var). Debug output goes to `{project_dir}/{debug_dir}/`:

- `hook_debug.log` — handler execution trace
- `hook_raw_input.json` — raw stdin data (stop handler only)
- `transcript_dump.jsonl` — copy of the transcript file (stop handler only)

## Dependencies

- macOS (uses `say` and `afplay` for audio)
- Python 3.11+ (for `hook_runner.py`)
- PyYAML (declared via PEP 723 inline metadata in `hook_runner.py`)
- `jq` (used by shell hooks to parse stdin JSON)
- `pnpm` (used by prettier formatting and Node.js pre-commit checks)
- `uv` (used by Python pre-commit checks and `hook_runner.py` execution)
- `markdownlint-cli` (used via `pnpm dlx` — markdown linting in PostToolUse and pre-commit gate)
- `dotenvx` (optional — `.env` encryption check in `session-checks.sh`)
- `claude-code-transcripts` (optional — transcript export in `export_transcript.sh`)
