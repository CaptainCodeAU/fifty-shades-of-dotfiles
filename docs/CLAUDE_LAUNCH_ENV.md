# What the Claude launch sets, and why

`home/.zsh_claude_launch` holds engage's launch blocks (`__cl_*`, one piece of launch
work each, ids L1 to L11) and its own part: `__engage_screen` and `__claude_launch`,
the list engage runs. `engage` (`~/CODE/CaptainCodeAU/engage`) sources it for every
engage session. `home/.zsh_engage` (loaded by `.zshrc`) also sources it but calls nothing
in it: `ci`, its last caller there, was removed on 2026-10-14. No other launcher reads it.
Split into blocks on 2026-10-13; before that it was one function. This page lists every variable
`__claude_launch` puts on the `claude` process, each checked against Claude Code's own
references on 2026-10-06 (Claude Code 2.1.290), and how each change was tested.

## The launch chain

Each setting below comes from one block, which hands it to `__cl_add`; `__cl_run_with_env`
exports them for the `claude` process alone, inside the throwaway SSH agent when the key
file exists (`__cl_ssh_agent`) and without one when it does not. Since the split there is
one chain, so the two can no longer drift apart.

| Variable                               | Value                                     | Why                                                                                                                                                                      |
| -------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `DISABLE_TELEMETRY`                    | empty                                     | The shell exports it for every tool. Empty counts as unset, so feature flags load and Remote Control can start.                                                          |
| `DO_NOT_TRACK`                         | empty                                     | Same reason as `DISABLE_TELEMETRY`.                                                                                                                                      |
| `NVD_API_KEY`                          | from the Keychain                         | Lifts NVD's rate limit for the CVE sweep. Not a credential to anything. Open item W-20261006-A44 (parked by Gavin) asks whether it should leave the session environment. |
| `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN` | `1`, or `0` when `PJ_RENDERER=fullscreen` | The classic-renderer lock; engage lifts it for full-screen sessions.                                                                                                     |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`  | `1`                                       | Clearing `DISABLE_TELEMETRY` re-enables the "How is Claude doing?" survey; this keeps it off. Added 2026-10-06.                                                          |
| `CLAUDE_CODE_NONBLOCKING_STDOUT`       | `1`                                       | A terminal that stops reading (paused pane, stalled SSH) cannot freeze Claude. Added 2026-10-06 (Q15: 17); the freeze itself is untestable on demand.                    |
| `CLAUDE_AUTO_BACKGROUND_TASKS`         | `1`                                       | Long subagents move to the background. Engage sessions already launch subagents async, so no visible effect here; kept on Gavin's pick (Q15.1: 2).                       |
| `CLAUDE_CODE_WORKER_CHECKIN_SCHEDULE`  | `600`                                     | Reminds Claude every 10 minutes to check background work still running. Live test with 60: the check-in arrived at 60.0 s; none without it.                              |

`GH_TOKEN` was removed from the launch on 2026-09-18; the note above `__cl_run_with_env`
says why.

## A plain-Claude box (codebox), since 2026-10-15

A box installed with `--skip-claude` (`DOTFILES_PLAIN_CLAUDE=1`; the codebox profile) has no
`.zsh_claude_launch`, so before this date `claude` started bare there: the shell's
`DISABLE_TELEMETRY` and `DO_NOT_TRACK` stayed set, feature flags did not load and Remote
Control could not start. Gavin chose (dotfiles-main Q10: 1) a small `claude()` function in
`home/.zshrc`, defined only on such a box, that adds the table above minus `NVD_API_KEY`
(such a box holds no keys): telemetry emptied with the survey kept off, non-blocking stdout
(codebox is reached through `herdr --remote`, so a stalled link is a real case), the classic
renderer (`1`; no `PJ_RENDERER` there), auto-background and the 600 s check-in. No SSH agent,
hooks, pj or engage. Tested with a stand-in `claude` that prints its environment: all six
arrive and `NVD_API_KEY` stays unset; the control (no `DOTFILES_PLAIN_CLAUDE`) gets none.

Since 2026-10-16 (dotfiles-main Q21), a `claude` started inside a herdr pane on such a box
also gets `SSH_TTY` (the pane's tty), unless one is already set. Claude Code copies with
the box's own clipboard tool unless it believes it is over SSH (`SSH_CONNECTION`,
`SSH_CLIENT` or `SSH_TTY`), and a herdr pane carries none of them, so a drag-copy made
through `herdr --remote` landed on codebox's clipboard instead of the Mac's (herdr issue
# 4833). With `SSH_TTY` set it copies through the terminal (OSC 52), which herdr passes to
the attached client. Gavin tested it by hand: paste on the Mac showed Claude's words.
Outside a herdr pane nothing is added, because Claude counts even an empty `SSH_TTY` as
set. Stand-in test, four arms: herdr pane with a tty gets it; no herdr pane, none; an
existing `SSH_TTY` is kept; no tty, none.

Blind spot: only a `claude` typed in zsh reaches the function. A launch that skips the shell
starts bare. Claude's own settings file (`env`) would cover every start path, but whether it
can empty `DISABLE_TELEMETRY` early enough for feature flags is not measured.

## Removed on 2026-10-06

| Variable                          | Why it went                                                                                                                    | Live test                                                                                                           |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE_CODE_HIDE_ACCOUNT_INFO=1` | Not in the env-var reference, not in the 2.1.288-2.1.290 program files. The start header stopped showing the email on its own. | Header read "Opus 5.5 with high effort · Claude Max" in both arms; `/status` showed email and organisation in both. |
| `ENABLE_EXPERIMENTAL_MCP_CLI=1`   | Not in the reference, not in the program.                                                                                      | `/context` identical.                                                                                               |
| `ENABLE_TOOL_SEARCH=1`            | Restated the default: unset, MCP tools already load on demand. Documented values are `true`, `auto`, `auto:N`, `false`.        | `/context` identical (22 MCP tools on demand, 0 tokens).                                                            |

`IS_DEMO=1` is the documented way to hide the email and organisation, but it also hides
them from `/status`, which Gavin wants visible, and skips onboarding.

## Tried and rejected: `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`

It strips credential-looking variables (such as `NVD_API_KEY`) from Bash, hooks and MCP
servers. Live test, 2026-10-06: with it set, an engage session started in **manual mode**
instead of bypass permissions and stopped for a prompt on a command the arm without it
ran silently. Not adopted. For a narrower way to hide one variable from sandboxed
commands, see `sandbox.credentials.envVars` in the settings reference.

## The shell exports that reach every session

Pane shells source `.zshrc`, so these reach engage sessions too:
`DISABLE_FEEDBACK_COMMAND=1` (renamed from the older `DISABLE_BUG_COMMAND` on
2026-10-06; `/feedback` now answers "disabled via the DISABLE_FEEDBACK_COMMAND
environment variable"), `DISABLE_ERROR_REPORTING=1`, `CLAUDE_CODE_ENABLE_TELEMETRY=0`
and `USE_BUILTIN_RIPGREP=0`.

A pane shell also inherits the herdr server's environment from when the server started.
After a rename, the OLD name lingers in new panes (seen: `DISABLE_BUG_COMMAND` still set
beside the new name) until herdr restarts. Harmless here; the effect is the same.

## How each change was tested

Gavin's ruling D-20261006-A05: every change gets a live before/after in a herdr pane,
reported to him, and D-20261006-A04: one commit per fix, after its test.

- **Launch file and shell exports:** `engage-worker start <name>` opens a real engage
  session in a pane, which re-reads `~/.zsh_claude_launch` and `.zshrc` from disk. Read
  the surface the change touches (start header, `/status`, `/context`, `/feedback`), or
  have the session report variables as `set len=N` / `unset`, never their values.
- **User settings (`~/.claude/settings.json`):** engage never loads them
  (`--setting-sources project,local`), so test with a plain `claude` in a pane through the
  logged control route: prefix both the herdr command and the in-pane launch with
  `PJ_WORKERS_CONTROL=<item id>`.
- **This repo's hook guards:** a plain `claude` here runs them. An engage session runs
  engage's own copy of the worker guard and the shell scanner
  (`~/CODE/CaptainCodeAU/engage/hooks/`, kept equal by a parity test), but the same stowed
  `~/.claude/hooks/` files for the other guards, such as `enforce-secret-probe.sh`.
- An arm needs a reading that would differ if the change worked. Where none exists (the
  feedback survey appears at random; voice state shows nowhere read-only), the test is
  reported as void rather than passed.

## User settings changed the same day (`~/.claude/settings.json`, dot-claude repo)

These reach plain `claude` (and reached `ci` until it was removed on 2026-10-14), not engage sessions (engage loads
`--setting-sources project,local` plus its own `--settings` file; engage's copies of these
keys are with engage-main, pending Gavin). Each was a separate commit after a plain-claude
A/B in a herdr pane.

| Change                                                                                             | Reading before → after                                                                        |
| -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `modelSettings` `claude-opus-5-5` `effortLevel: high` (Opus 5.5 ignores a top-level `effortLevel`) | effort medium → high                                                                          |
| `voiceEnabled` → `voice.enabled` (deprecated key)                                                  | no change; voice state has no read-only surface (void)                                        |
| `leftArrowOpensAgents` dropped (global-config key, read only from `~/.claude.json`)                | no change                                                                                     |
| empty `mcpServers` dropped (not a settings key)                                                    | no change                                                                                     |
| `timeFormat: 12-hour`, `timeZone: Australia/Melbourne`                                             | "done 2:56 pm" → "done 2:55 pm": the Mac's locale already matched; pins it for other machines |
| `maxProseWidth: 100`                                                                               | widest prose line 184 → 102 columns                                                           |
| `prefersReducedMotion: true`, `spinnerTipsEnabled: false`                                          | spinner 6 cycling glyphs → 1 static; tips void                                                |
| `footerLinksRegexes` for W-/D- IDs → dot-claude code search                                        | 0 → 2 footer badges                                                                           |
| `fallbackModel: ["claude-opus-5", "sonnet"]`                                                       | clean start both arms; the switch needs an overload (void)                                    |
| `sandbox.failIfUnavailable: true`                                                                  | clean start both arms; the refusal needs a broken sandbox (void)                              |

LifeOS keeps its own keys in this file (`notifications`, `max_tokens`, `principal` and
others). Claude Code ignores them; LifeOS's notification system reads `notifications`.

## Guard fixes the same day

- `conv-shscan.awk`: `2>&1`, `>&2` and `>&-` are descriptor duplication, not a write to a
  file named `1` (W-20261006-A45, `3ec9555`).
- `conv-shscan.awk`: `command -v` and `command -V` are lookups, not launches (engage #1090,
  `9117c64`).
- `enforce-secret-probe.sh`: a jq filter selecting the key `.env` is not a `.env` file read
  (W-20261006-A47, `1258ce1`; report in
  `~/CODE/CaptainCodeAU/CaptainCodeAU-isolinear/workbench/dotfiles-secret-guard/2026-10-06/`).

## Plain `claude` and `ci` are refused everywhere (Gavin Q10, 2026-10-06)

The `claude()` function in `.zshrc` used to guard only herdr panes; outside herdr it passed
everything through. Since `febfad6` it refuses a plain `claude` or `ci` in any interactive
zsh, saying "REFUSED outside herdr" or "REFUSED in a herdr pane" and naming engage. Still
allowed: `command claude` (the way round), `--version` and `--help`, every `claude`
subcommand (`doctor`, `mcp`, `purge`, ...), a launch carrying a system-prompt file, the
logged `PJ_WORKERS_CONTROL=<item id>` override, and every script (engage and lifeos run
`claude` from PATH and never see the function). Selftest: `zsh-claude-paneguard-selftest
--mutants` (72 arms, 4 mutants).

`ci` was removed on 2026-10-14 (Gavin, dotfiles-main): this refusal left it with no working
caller, and scripts never see aliases. Its two refusal arms went with it, so the selftest is
70 arms, and 75 passed with `--mutants`, measured 2026-10-14. The one-shot form now is
`command claude -p "..."`.

So `~/.claude/settings.json` (user settings) now reaches only `command claude` and LifeOS
sessions; engage sessions read their own settings file.
