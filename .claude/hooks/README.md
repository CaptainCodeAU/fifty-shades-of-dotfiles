# Claude Code hooks this repo owns

Current as of P5.6 (2026-09-21). Every hook the dotfiles repo owns, at every wiring level, is in the first table. Claude Code pipes JSON to stdin on every hook event; scripts read it to inspect tool names, file paths and commands.

## Wiring levels

Three ways a hook this repo owns reaches a session, and they do not overlap:

| level                       | file that registers it                                                                                                                                    | who loads it                                  |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **project**                 | `.claude/settings.json` in this repo                                                                                                                      | any session opened in this repo (`c` or `pj`) |
| **manifest `project`**      | [`settings/claude/hooks.json`](../../settings/claude/hooks.json), rendered by `claude-hooks-sync --target project` into `~/.claude/settings.project.json` | every `pj` session, in every folder           |
| **manifest `user,project`** | same manifest, rendered into both `~/.claude/settings.json` and `~/.claude/settings.project.json`                                                         | every session, either launcher                |

`pj` passes `--setting-sources project,local`, so the user file never loads there. A hook meant for every `pj` session is declared ONCE in the manifest with `targets` and never hand-wired into either settings file (D-20260920-09, F1). A manifest traveller's script lives in `home/.claude/hooks/` and is stowed to `~/.claude/hooks/`; the entry uses `test -x <path> && <path> || true`, so a registration that outlives its script costs nothing and a deny still works (JSON on stdout under exit 0).

## Every hook

| script                       | event          | matcher           | level                                           | one line                                                                                    | selftest                       |
| ---------------------------- | -------------- | ----------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------ |
| `session-checks.sh`          | `SessionStart` | `startup\|resume` | project                                         | git status count; unencrypted `.env` variants                                               | no                             |
| `vuln-scan-check.sh`         | `SessionStart` | `startup\|resume` | project                                         | installed packages vs NVD via `vuln-scan --fast`                                            | no                             |
| `zed-version-check.sh`       | `SessionStart` | `startup\|resume` | project                                         | Zed Preview doc freshness, watched PRs                                                      | no                             |
| `toolchain-cve-check.sh`     | `SessionStart` | `startup\|resume` | project                                         | pnpm/nvm/bun floors, Claude Code, brew vs OSV/GHSA/NVD                                      | `toolchain-cve-check-selftest` |
| `herdr-cooldown-check.sh`    | `SessionStart` | `startup\|resume` | project                                         | herdr upgrade eligibility and guards                                                        | no                             |
| `herdr-skill-drift-check.sh` | `SessionStart` | `startup\|resume` | project                                         | herdr skill merge base vs `docs/HERDR*.md`                                                  | no                             |
| `bun-cooldown-check.sh`      | `SessionStart` | `startup\|resume` | project                                         | global bun packages vs `minimumReleaseAge`                                                  | no                             |
| _(inline echo)_              | `SessionStart` | `compact`         | project                                         | uv/pnpm reminder after compaction                                                           | n/a                            |
| `enforce-no-cd.sh`           | `PreToolUse`   | `Bash`            | project                                         | rewrite a leading `cd DIR && rest` into a subshell, deny other `cd` (see the note below)    | `--selftest`                   |
| `enforce-builtin.sh`         | `PreToolUse`   | `Bash`            | project                                         | deny `builtin <non-builtin>`                                                                | no                             |
| `enforce-gh-ssh-only.sh`     | `PreToolUse`   | `Bash`            | project, plus a LifeOS user-level twin          | deny `gh auth login\|setup-git\|refresh`                                                    | no                             |
| `protect-files.sh`           | `PreToolUse`   | `Edit\|Write`     | project                                         | deny edits to `.env*`, lockfiles, `.git/`                                                   | no                             |
| `hook_runner.py`             | 11 events      | various           | project                                         | audio notifications (sound + speech), see below                                             | pytest on `lib/`               |
| _(inline prettier)_          | `PostToolUse`  | `Edit\|Write`     | project                                         | `pnpm dlx prettier --write` on the edited file                                              | n/a                            |
| _(inline markdownlint)_      | `PostToolUse`  | `Edit\|Write`     | project                                         | `markdownlint-cli --fix` on `.md`                                                           | n/a                            |
| `validate-bash.sh`           | `PreToolUse`   | `Bash`            | manifest `project` (`home/.claude/hooks/`)      | deny `rm -rf /`, force push to main/master, bare `git reset --hard`, `git clean -fd`        | `--selftest`                   |
| `enforce-uv.sh`              | `PreToolUse`   | `Bash`            | manifest `project` (`home/.claude/hooks/`)      | rewrite clear pip/python/pytest/ruff slips to uv, deny the rest                             | `--selftest`                   |
| `enforce-pnpm.sh`            | `PreToolUse`   | `Bash`            | manifest `project` (`home/.claude/hooks/`)      | rewrite drop-in npm/yarn/npx slips to pnpm, deny the rest and `pnpm link --global`          | `--selftest`                   |
| `pj-start-card`              | `SessionStart` | none              | manifest `project` (`home/.local/bin/`)         | the 20-line start card: open items, wrap-up warning, handoff pointer (D-20260920-04)        | `pj-start-card --selftest`     |
| `pj-session-end`             | `SessionEnd`   | none              | manifest `project` (`home/.local/bin/`)         | writes the no-wrap-up flag the next start card reads (D-20260920-03)                        | `pj-session-end --selftest`    |
| `enforce-secret-probe.sh`    | `PreToolUse`   | `Bash`            | manifest `user,project` (`home/.claude/hooks/`) | deny printing a credential-named variable                                                   | `--selftest`                   |
| `enforce-census.sh`          | `PreToolUse`   | `Bash`, `Grep`    | manifest `user,project` (`home/.claude/hooks/`) | nudge a grep toward `census.py` (Grep tool is absent under `pj`; that entry is inert there) | no                             |
| `enforce-herdr-skill.sh`     | `PreToolUse`   | `Bash`            | manifest `user,project` (`home/.claude/hooks/`) | deny `herdr` until the skill is read                                                        | no                             |
| `mark-herdr-skill-read.sh`   | `PostToolUse`  | `Skill`           | manifest `user,project` (`home/.claude/hooks/`) | lift the herdr gate (`herdr` or `herdr:herdr`)                                              | no                             |
| `ci-watch`                   | `SessionStart` | none              | manifest `user,project` (`home/.local/bin/`)    | escalating CI-red alarm                                                                     | no (`--help` only)             |
| `ccw-watch`                  | `SessionStart` | none              | manifest `user,project` (`home/.local/bin/`)    | capture-presence alarm for cc-capture (project target since 2026-09-21)                     | `ccw-watch-selftest`           |

Not ours, for orientation: the `cc-capture@cc-warehouse` plugin registers its own `SessionStart` freshness check and `SessionEnd` archive; they fire under both launchers. LifeOS's user-level hooks fire under `c` only.

**What a `c` session in this repo gets on top of LifeOS's set:** every project-level row above plus the manifest `user,project` rows. It does NOT get the manifest `project` rows (`validate-bash`, `enforce-uv`, `enforce-pnpm`, `pj-start-card`, `pj-session-end`): those are `pj` machinery. Before 2026-09-21 the three guards were project-level and fired here under `c`; LifeOS can register the stowed paths itself if it wants them back under `c`.

**What a `pj` session in this repo gets:** every project-level row plus every manifest row. The three moved guards fire ONCE (manifest), not twice; proven in the P5.6 report.

### The leading-`cd` rule is this repo's hook, not the harness

This repo's CLAUDE.md, and the copies of that paragraph in other projects, say the harness hard-rejects a leading `cd`. Measured 2026-09-21: in the last 20 transcripts of two other projects, 123 commands began with `cd` and every one executed without error. The rejection is `enforce-no-cd.sh`, project-level, and it would have denied 46 percent of one project's real commands, which is why it did not travel (P5.6). Correcting the sentence is W-20260921-09.

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

Each handler can play a **sound effect** (via `afplay`) and/or **speak a message** (via `say` rendered to file, then `afplay` for playback). Both are independently configurable. It is project-level: every path it reads (`config.yaml` beside the script, `.claude/sounds/` relative to the project, `lib/`) is repo-relative, so it does not travel yet. Making it travel is W-20260921-06. Under `c` in this repo it plays alongside LifeOS's own `VoiceCompletion` on Stop.

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

`project_dir` is resolved in order: (1) value from `config.yaml`, (2) `$HOOK_PROJECT_DIR` env var, (3) current working directory. Claude Code sets the hook's CWD to the project root, so leaving `project_dir: ""` in the config works out of the box. Sound file paths, debug output, and transcript fallback all resolve relative to this directory.

### Per-hook settings

Each hook has:

- **sound**: play an audio file (`enabled`, `file` relative to project_dir or absolute, `volume` 0.0 to 1.0, `delay_ms` pause before speech when both are enabled)
- **voice**: text-to-speech (`enabled`, `name` macOS voice, `volume` controls `afplay -v` only, `rate` words per minute)

### Stop hook extras

```yaml
summary:
  mode: "sentences" # "sentences" or "characters"
  max_sentences: 2 # how many sentences to speak
  max_characters: 200 # max length in characters mode
  start: "action" # "action" finds first action verb, "beginning" starts from top
```

The stop handler reads Claude's transcript, extracts a summary of what it did, and speaks it. It also detects if Claude is waiting for input (question or permission) and uses the appropriate voice/sound settings for that case. When text ends with `?`, the handler uses input-waiting audio settings but prioritizes speaking the action summary over the trailing question; if no action summary is found, it speaks the question itself.

### Other handler extras

- ask_user_question: `message_mode` (`extract` or `generic`), `default_message`
- permission_request: `message_template` with `{tool_name}`; resolves AskUserQuestion text first, then a transcript summary (falling back to the template when the same summary was already spoken this turn), then the template
- notification: `idle_message`, `auth_message`, `default_message`
- subagent_start / subagent_stop: `message_template` with `{agent_type}`
- teammate_idle: `message_template` with `{teammate_name}`
- task_completed: `message_template` with `{task_subject}`, `max_subject_length`
- post_tool_use_failure: `message_template` with `{tool_name}`; skips `is_interrupt`
- user_prompt_submit: disabled by default; `get_message()` returns `None`
- pre_compact: static `message`

## Handler architecture

`BaseHandler.handle()` implements a Template Method that all handlers share: log, `should_handle(data)`, `_pre_message_hook(data)`, `get_message(data)`, `_resolve_audio_settings(data)`, `play_notification()`, debug log.

| Handler                     | Overrides                            | Why                                                                                                |
| --------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `AskUserQuestionHandler`    | `_pre_message_hook`                  | Calls `mark_handled()` before message extraction for dedup                                         |
| `PermissionRequestHandler`  | `_pre_message_hook`, `get_message`   | Marks permission as handled; reads transcript for text summary before falling back to template     |
| `StopHandler`               | `_resolve_audio_settings`            | Selects input-waiting vs task-completion audio settings based on a flag set during `get_message()` |
| `NotificationHandler`       | `_pre_message_hook`                  | Marks `notification_idle` for Stop dedup when type is `idle_prompt`                                |
| `SubagentStopHandler`       | `_pre_message_hook`                  | Marks `subagent_stop` for Stop dedup                                                               |
| `PostToolUseFailureHandler` | `should_handle`, `_pre_message_hook` | Skips user interruptions (`is_interrupt`); marks `tool_failure` for Stop dedup                     |
| `UserPromptSubmitHandler`   | `get_message`                        | Returns `None`: silent skeleton (disabled by default)                                              |

## File structure

```text
.claude/hooks/                      project-level (this directory)
  session-checks.sh                 SessionStart: git status + .env encryption check
  vuln-scan-check.sh                SessionStart: installed packages vs NVD
  zed-version-check.sh              SessionStart: Zed Preview changelog freshness
  toolchain-cve-check.sh            SessionStart: pnpm/nvm/bun floors + installed vs advisories
  toolchain-cve-check-selftest      controls for the banner above
  herdr-cooldown-check.sh           SessionStart: herdr release cooldown + guards
  herdr-skill-drift-check.sh        SessionStart: herdr skill vs docs
  bun-cooldown-check.sh             SessionStart: global bun packages vs cooldown
  enforce-no-cd.sh                  PreToolUse Bash: rewrite a leading cd into a subshell, deny other cd
  enforce-builtin.sh                PreToolUse Bash: block builtin with non-builtins
  enforce-gh-ssh-only.sh            PreToolUse Bash: block gh auth login/setup-git/refresh
  protect-files.sh                  PreToolUse Edit|Write: block edits to protected files
  hook_runner.py                    audio entrypoint, routes to lib/handlers
  config.yaml                       audio configuration
  security.log                      audit log of the project-level blockers (gitignored)
  lib/                              audio.py, config.py, summary.py, transcript.py, state.py, handlers/
  tests/                            pytest for state, summary, transcript

home/.claude/hooks/                 stowed to ~/.claude/hooks/, registered by the manifest
  validate-bash.sh                  manifest project: destructive git and rm
  enforce-uv.sh                     manifest project: uv over bare Python tooling (rewrites)
  enforce-pnpm.sh                   manifest project: pnpm or bun over npm/yarn/npx (rewrites)
  conv-shscan.awk                   not a hook: the zsh scanner the three convention hooks share
  conv-hooklib.sh                   not a hook: their shared plumbing and selftest runner
  enforce-secret-probe.sh           manifest user,project: no credential printing
  enforce-census.sh                 manifest user,project: grep nudge
  enforce-herdr-skill.sh            manifest user,project: herdr gate
  mark-herdr-skill-read.sh          manifest user,project: herdr gate release

home/.local/bin/                    stowed to ~/.local/bin/, run BY a manifest entry
  ci-watch  ccw-watch  pj-start-card  pj-session-end
```

## Shell hook scripts, project level

### session-checks.sh

Runs on `SessionStart` with matcher `startup|resume` (skips `compact` and `clear`). Counts uncommitted changes and prints a one-line summary; checks whether `dotenvx` is installed, whether `.env` files are encrypted, and warns about unencrypted variants (`.env.local`, `.env.development`, and so on).

### vuln-scan-check.sh

Runs on `SessionStart`, read-only. `vuln-scan --fast --no-progress`; gates on the exit code, never on a string. On a HIGH or CRITICAL finding it instructs the assistant to raise a tracked task before anything else, because startup text is skimmed. See [`docs/VULN_SCAN.md`](../../docs/VULN_SCAN.md).

### zed-version-check.sh

Runs on `SessionStart`, read-only. Compares the version recorded in `docs/ZED_PREVIEW_CHANGELOG.md` against the latest GitHub prerelease (6h-cached in `$TMPDIR`) and reports the merge status of watched upstream PRs. Nudges the assistant to refresh that doc. Never edits anything; always exits 0.

### toolchain-cve-check.sh

Runs on `SessionStart`, read-only. CVE check of the pinned pnpm/nvm/bun floors (read from `install.sh`), the installed versions, the installed Claude Code, and (from a 24h background verdict) the Homebrew formulae, via the standalone `toolchain-cve-check` tool. 6h-cached. Never blocks. `toolchain-cve-check-selftest` proves the banner wording. See [`docs/TOOLCHAIN_CVE_CHECK.md`](../../docs/TOOLCHAIN_CVE_CHECK.md). The brew arm does not escalate: W-20260920-05.

### herdr-cooldown-check.sh and herdr-skill-drift-check.sh

Both `SessionStart`, read-only, silent when herdr is not installed. The first reports whether a herdr upgrade is eligible under the release cooldown (its length is `HERDR_COOLDOWN_DAYS` in `install.sh`, which the hook reads) and whether the guards enforcing it are in place. The second reports whether a herdr upgrade moved the agent skill or left a `docs/HERDR*.md` behind (deliberately uncached: no network call). See [`docs/HERDR.md`](../../docs/HERDR.md).

### bun-cooldown-check.sh

Runs on `SessionStart`, read-only. Whether a globally installed bun package is silently held behind `~/.bunfig.toml` `minimumReleaseAge`, via the standalone `bun-cooldown-check` tool. 6h-cached. Loud only when something is blocked.

### enforce-no-cd.sh

Runs on `PreToolUse` for `Bash`. Since 2026-09-23 a LEADING `cd DIR && rest` (or `;`, or a newline) is REWRITTEN to `(builtin cd DIR && rest` plus a newline and `)`, so the session's working directory cannot move; the `.zshrc` aliases that expand to `cd` (`..` `...` `....` `.....` `~`) are rewritten the same way. Every other `cd` shape is still denied: use absolute paths, `git -C <path>`, or `builtin cd`. It uses the shared scanner in `home/.claude/hooks/conv-shscan.awk` (reached through this repo's path), which reads quotes, `$(...)`, heredocs and zsh operators properly; the old sed strip denied a quoted `)` inside `$(...)` and a multi-line `"..."` commit message. A command that also trips the uv or pnpm rule is denied with one combined message, because two rewriting hooks race (`docs/CLAUDE_HOOKS.md`, "Rewriting a tool call"). Project-level on purpose; see the note above and W-20260921-07 (shadow-mode traveller).

### enforce-builtin.sh

Runs on `PreToolUse` for `Bash`. Blocks `builtin` with non-builtins (`builtin git`, `builtin swift`), which zsh rejects anyway; allows real builtins (`cd`, `echo`, `printf`, `pushd`, `export`, and so on). Companion of `enforce-no-cd.sh`.

### enforce-gh-ssh-only.sh

Runs on `PreToolUse` for `Bash`. Blocks `gh auth login`, `gh auth setup-git` and `gh auth refresh`, which re-add HTTPS credential helpers and undermine the SSH-only auth model. Mirrors the interactive `gh()` wrapper, which does not apply to the non-interactive Bash tool. A byte-identical copy is a REAL file at `~/.claude/hooks/enforce-gh-ssh-only.sh`, tracked in dot-claude and registered in the user settings (LifeOS's), so under `c` in this repo it fires twice and under `pj` elsewhere not at all. Folding the two into one stowed copy needs LifeOS to yield its file first; noted for LifeOS in the P5.6 report.

### protect-files.sh

Runs on `PreToolUse` for `Edit|Write`. Blocks edits to `.env`, `.env.keys`, `.env.*` (except `.env.example`), `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, and anything under `.git/`.

### PostToolUse prettier and markdownlint (inline)

Both on `PostToolUse` for `Edit|Write`, both `|| true`. prettier rewrites the edited file; markdownlint `--fix` runs on `.md` only. Configuration lives in `.markdownlint.jsonc` at the repo root. These REWRITE files after every edit, which moves another session's `git diff` under it (W-20260920-07).

### SessionStart compact (inline)

Matcher `compact`. Echoes a reminder of project conventions (uv for Python, pnpm for Node.js) so Claude retains them after compaction.

## Shell hook scripts, manifest travellers

### validate-bash.sh, enforce-uv.sh, enforce-pnpm.sh

Moved from this directory to `home/.claude/hooks/` on 2026-09-21 (P5.6) and declared in the manifest with `targets: ["project"]`, so every `pj` session in every folder has them and this repo's `.claude/settings.json` no longer does. Before the move their match logic was run over every Bash command in the last 20 transcripts of two other projects (51 and 245 commands): 0, 0 and 1 would-denies for validate-bash, enforce-pnpm and enforce-uv, the 1 being a real bare `python3 -c`. Each has `--selftest` with positive and negative arms; run it through `~/.claude/hooks/<name> --selftest`, not the repo path, so the stow is proven too. `validate-bash.sh` gained the heredoc-and-quote stripping its siblings had: before that, a commit message mentioning `git clean -fd` was denied.

### enforce-secret-probe.sh, enforce-census.sh, enforce-herdr-skill.sh, mark-herdr-skill-read.sh

Machine-wide safety, declared with `targets: ["user", "project"]` and registered by `claude-hooks-sync` into both settings files. Until 2026-09-20 they were user-only, so no `pj` session was guarded (F1). Under `pj` the herdr skill loads as a plugin, so the Skill parameter is `herdr:herdr`; the mark hook accepts exactly `herdr` or `herdr:herdr`.

### ci-watch, ccw-watch, pj-start-card, pj-session-end, pj-launch-check

Ordinary CLI tools stowed to `~/.local/bin/`, run BY a manifest entry (`script_path` in the manifest). `ci-watch` and `ccw-watch` are `user,project`; the three `pj-*` are `project` only because `pj` is the launcher they serve. There is deliberately no wrapper script for any of them in this directory. See [`docs/CI_WATCH.md`](../../docs/CI_WATCH.md), [`docs/OPEN_ITEMS.md`](../../docs/OPEN_ITEMS.md), [`docs/PJ_HEALTH.md`](../../docs/PJ_HEALTH.md).

`pj-launch-check` (SessionStart, F3, 2026-09-21) reads the running `claude` process's argv (`CLAUDE_PID` is exported into every hook; measured, and the hook's parent is that pid when the command is a bare path) and prints ONE line, `LAUNCH WARNING: stale launcher, missing <what>. Open a new shell and relaunch pj.`, when the appended system-prompt file is not the `pj-prompt-file` cache (that is where `pj-global/RULES.md` lands), a plugin dir is absent or `--setting-sources` drifted. Silent on a match, silent on `compact`. Every launch appends one `ts= session= project= tty= shell_start= zshrc_mtime= result=` line to `~/.local/state/pj/launches.log`; `pj-health`'s `launch-log` row reads it. It is a separate hook from `pj-start-card` on purpose: the card is read-only (P5.2) and this one writes a log. Hooks run concurrently, so the warning is the first line of its own hook block, not necessarily of the card's.

## Retired

| hook                   | when                   | why                                                                                                                                                                                                                                                            |
| ---------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pre-commit-check.sh`  | 2026-09-21 (P5.6)      | Ran lint/build/markdownlint on `git commit` but never exited 2, so under the hook contract a failure reached only the transcript view and the commit proceeded; its README claim that Claude would see the errors was false. Nothing executable referenced it. |
| `peer-reply-check.sh`  | 2026-09-21 (P5.6)      | Printed "PEER REPLY OWED" on Stop with exit 0; a Stop hook reaches the model only through `{"decision":"block"}`, so the model never saw a line of it. A fixed, travelling version is W-20260921-08.                                                           |
| `export_transcript.sh` | 2026-08-18 (`cca4a6f`) | A second exporter beside cc-capture. Do not re-add. Its `github_pat_`/`gh[posru]_` scrubbing went with it; cc-capture keeps the archive at full fidelity by design and blocks secrets at `ccw share` instead (W-20260920-04).                                  |

## Deduplication

Several hooks fire before the `Stop` hook. The state module (`lib/state.py`) writes a short-lived marker to `/tmp/claude-hooks/` when an event is handled. The stop handler checks for these markers only when it detects that Claude is waiting for input (pending tool_use, text ending with `?`, or AskUserQuestion). If a marker exists, the input-waiting notification is suppressed.

| Marker              | Set by                              | Prevents                               |
| ------------------- | ----------------------------------- | -------------------------------------- |
| `ask_user`          | `AskUserQuestionHandler`            | Stop re-announcing a question          |
| `permission`        | `PermissionRequestHandler`          | Stop re-announcing a permission prompt |
| `notification_idle` | `NotificationHandler` (idle_prompt) | Stop re-announcing idle state          |
| `tool_failure`      | `PostToolUseFailureHandler`         | Stop re-announcing a failure           |
| `subagent_stop`     | `SubagentStopHandler`               | Stop re-announcing subagent completion |

Task-completion summaries never consult dedup state. During a burst of tool calls in one turn, `state.py` also stores an MD5 of the last spoken summary so the permission handler falls back to the template instead of repeating itself. State files auto-expire after 60 seconds.

## Audit logging

Two logs, by wiring level:

- Project-level blockers (`enforce-no-cd`, `enforce-builtin`, `enforce-gh-ssh-only`, `protect-files`) append to `.claude/hooks/security.log` beside the scripts (gitignored).
- Manifest travellers (`validate-bash`, `enforce-uv`, `enforce-pnpm`) append to `${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log`, the same state home `vuln-scan` uses, because they run in every folder and must not write beside a stowed symlink.

Format, both:

```text
[2026-02-18T14:30:22Z] BLOCKED validate-bash "Force push to main/master is not allowed" "git push --force main"
[2026-02-18T14:31:05Z] BLOCKED protect-files "Secrets file" ".env.local"
[2026-09-23T07:54:13Z] REWROTE enforce-pnpm "<the one line the session saw>" "npm test" -> "pnpm test"
```

`REWROTE` lines come from the three convention hooks when they change a command instead of denying it.

Append-only; the hooks never truncate them.

## Testing

```bash
PYTHONPATH=.claude/hooks uv run --with pytest pytest .claude/hooks/tests/ -v   # audio lib
~/.claude/hooks/validate-bash.sh --selftest
~/.claude/hooks/enforce-uv.sh --selftest
~/.claude/hooks/enforce-pnpm.sh --selftest
.claude/hooks/enforce-no-cd.sh --selftest
~/.claude/hooks/enforce-secret-probe.sh --selftest
.claude/hooks/toolchain-cve-check-selftest
claude-hooks-sync-selftest && claude-hooks-sync --target project --check
```

## Debugging

Set `global.debug: true` in `config.yaml` (or `HOOK_DEBUG=1`). Debug output goes to `{project_dir}/{debug_dir}/`: `hook_debug.log`, `hook_raw_input.json` and `transcript_dump.jsonl` (stop handler only, unredacted, so keep it off).

## Dependencies

- macOS (`say`, `afplay`) for the audio system
- Python 3.11+ and PyYAML (PEP 723 metadata in `hook_runner.py`), run through `uv`
- `jq` (every shell hook parses stdin JSON with it)
- `pnpm` (prettier and markdownlint via `pnpm dlx`)
- `dotenvx` (optional: `.env` encryption check in `session-checks.sh`)
- GNU Stow and `claude-hooks-sync` (via `install.sh`) for the manifest travellers
