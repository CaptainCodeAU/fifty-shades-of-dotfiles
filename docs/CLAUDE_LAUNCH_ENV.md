# What the Claude launch sets, and why

`home/.zsh_claude_launch` defines `__claude_launch`, the one function that starts Claude
Code on this machine. `engage` (`~/CODE/CaptainCodeAU/engage`) sources it for every
engage session, and `.zshrc` uses it for `ci`. This page lists every variable it puts on
the `claude` process, each checked against Claude Code's own references on 2026-10-06
(Claude Code 2.1.290), and how each change was tested.

## The launch chain (both branches identical)

The function has two chains, one with the throwaway SSH agent and one without (no key
file). They must stay identical; a variable added to one belongs in both.

| Variable                               | Value                                     | Why                                                                                                                                                                      |
| -------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `DISABLE_TELEMETRY`                    | empty                                     | The shell exports it for every tool. Empty counts as unset, so feature flags load and Remote Control can start.                                                          |
| `DO_NOT_TRACK`                         | empty                                     | Same reason as `DISABLE_TELEMETRY`.                                                                                                                                      |
| `NVD_API_KEY`                          | from the Keychain                         | Lifts NVD's rate limit for the CVE sweep. Not a credential to anything. Open item W-20261006-A44 (parked by Gavin) asks whether it should leave the session environment. |
| `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN` | `1`, or `0` when `PJ_RENDERER=fullscreen` | The classic-renderer lock; engage lifts it for full-screen sessions.                                                                                                     |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`  | `1`                                       | Clearing `DISABLE_TELEMETRY` re-enables the "How is Claude doing?" survey; this keeps it off. Added 2026-10-06.                                                          |

`GH_TOKEN` was removed from both chains on 2026-09-18; the note in the `if` branch says
why and how to revert.

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
- **This repo's hook guards:** a plain `claude` here runs them; an engage session runs
  engage's own copies (`~/CODE/CaptainCodeAU/engage/hooks/`), which follow by a parity test.
- An arm needs a reading that would differ if the change worked. Where none exists (the
  feedback survey appears at random; voice state shows nowhere read-only), the test is
  reported as void rather than passed.
