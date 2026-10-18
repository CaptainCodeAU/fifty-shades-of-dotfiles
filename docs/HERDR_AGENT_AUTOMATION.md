# herdr: Agent Automation (Group B)

**Audience: an AI coding agent, not a human.** This replaces reading
<https://herdr.dev/docs/preview/agent-automation/>.

herdr-verified: 0.9.5

**THE 0.9.5 RE-CHECK (2026-10-18) WAS NARROW TOO**, scoped to the 0.9.3 to 0.9.5
delta, against a running 0.9.5 server from inside a herdr pane. RE-RAN: every
command in section 3 is still in 0.9.5's group listings and `--help` (a
misspelt `--timeoutt` exits 2, the real `--timeout` parses); `agent list` and
`agent get` keep their different result keys (`agents`+`type` vs
`agent`+`type`); `agent explain` text and `--json` on this session's own pane;
`herdr integration status`; and, in ONE throwaway pane closed afterwards,
`pane send-keys` validating a bogus key (`invalid_key`, exit 1) and `pane run`
plus `pane wait-output`. CHANGED and written in below: the kinds list is now 24
(section 3); the Claude hook reads `outdated (v10 < v11)` (section 2); detection
now reports a `bundled` manifest (section 2); and the Trap 1 wait regex matched
this repo's banner, not its prompt (section 4). RE-READ FROM --help ONLY: the
`agent prompt --wait` stall rule (section 6). DOC ONLY (0.9.4/0.9.5 notes and
upstream's 0.9.5 skill, not measured here): Claude Code questions now show
`blocked` in named sessions (#4573); Antigravity and Grok read `idle` with
background work still running (#3530); Ctrl+Z keeps an agent's identity while
its process lives (#1647); on macOS `agent start`/`pane run` refuse a command
too long for a still-starting shell (#4950); closing a workspace's only pane
now asks first in the TUI (#5143), which a CLI/API close does not; closing the
shell that launched herdr no longer stops the server (#4920). NOT RE-MEASURED:
everything that needs a live agent we started (`agent start`,
`agent_pane_busy`, `agent prompt`, `agent wait`, `agent send-keys`), because
starting one is outside a re-check (D-20260924-A05); the last-pane close
prompt, which needs a throwaway workspace; Codex status, because no Codex agent
was started (the Codex program is installed here, at `~/.bun/bin/codex`, but
herdr's Codex integration is not: `herdr integration status` reads
`codex: not installed`; both checked read-only, 2026-10-18 on 0.9.5). A
coverage audit of every 0.9.2 to 0.9.5 release-note bullet against this
document followed the same day, and the gaps it found are written in below
(section 2 and the 0.9.3 note).

**THE 0.9.3 RE-VERIFY (2026-10-07) WAS NARROW, and says so.** Against a running
0.9.3 server, scope the 0.9.1 to 0.9.3 delta. RE-RUN and unchanged: every
command in section 3 is in 0.9.3's group listings (an invented control
misses); `agent list` still answers `{"result":{"agents":[...],"type":...}}`;
the pane/tab/workspace create and close commands, in a throwaway workspace.
OBSERVED: closing a workspace's LAST tab from the CLI (`tab close`) closes it
with no prompt and removes the workspace; 0.9.2's new last-tab confirmation
(#4379) is a TUI behaviour only. CHANGED: the Claude integration hook
(section 2) is now reported `outdated (v8 < v10)` by `herdr integration
status`; the 0.9.3 Homebrew upgrade did NOT rewrite it (file still dated 6 Sep).
NOT RE-RUN: everything that needs a live agent (`agent start` /
`agent_pane_busy`, `agent prompt`, `agent wait`, `agent get` key shape,
`agent explain`). No agent was running (all 21 panes `agent_status: unknown`)
and starting one is outside a re-verify (D-20260924-A05). The 0.9.2 changes
that touch those claims are DOC only here: an agent's first task now counts as
`done` even when started with a prompt (#3338); starting the server, restoring
sessions and Pi's `/new` no longer fire false `done` notifications (#3990); and
hook-reported status survives a live handoff (#3916). So on 0.9.2 and later a
`done` right after a restart or restore is worth reading, not dismissing as
restart noise (per the 0.9.2 release notes, not measured). Also: agents may self-report a resume
command (#4687), and an event reader that falls behind gets `events_lost`
instead of silently skipped events (#4178).

Written against **herdr 0.7.5** on 2026-08-02 by executing every command.
Reviewed against **0.8.2** on 2026-09-17. Re-verified against **0.9.1** on
2026-09-22 (F9b), against a running server. What each review did and did not do
is stated at each claim: several traps here are about agent STARTUP, which 0.8.2
reworked, and re-running them means starting real agents in the user's live
session. Where a claim was not re-run it says so rather than carrying a stamp it
has not earned.

**THE 0.9.1 RE-VERIFY DID START REAL AGENTS**, which is why it reaches further
than the 0.8.2 review did. Three were started in a scratch tab and all of them
closed afterwards: a named `claude` agent, a settled `pj --profile scratch`
session, and a fresh `pj` prompted on its first ever turn. OBSERVED against
those: `agent start` refusing a pane still running its shell startup with
`agent_pane_busy`, then succeeding on the retry; `agent prompt` with and without
`--wait`, 21 submissions, all 21 producing a real turn, verified by a reversed
sentinel that cannot appear in the echoed prompt; `agent_prompt_stalled` firing
ZERO times, including under pj's per-turn hook overhead, so the trap this
document and the skill both warn about did not reproduce on 0.9.1; `agent wait`
timing out cleanly at its bounded timeout in a background task, with a
satisfiable wait returning in 0s as the control; `agent get` and `agent list`
keeping their different result-key shapes; and `pane send-keys <id> enter`
submitting text left sitting in an agent's input box, which is the documented
fix for the trap. NOT RE-RUN: anything needing a server restart, and the
Windows and Codex paste-boundary behaviour, which this estate cannot exercise.

The `herdr-verified:` line is machine-read by `herdr-skill-drift-check`.
OBSERVED = produced by a real run. DOC = upstream claim, not confirmed here.

**The upstream page is labelled "preview / unreleased `master` work". That
label is wrong for 0.7.5 stable: every command below already exists in the
shipped Homebrew build.** Do not go chasing the preview channel for these.

Read [`HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md) sections 3 and 4 first --
the sandbox trap and the JSON-vs-plain-text map apply to everything here.

---

## 1. The model

Three primitives, not a trigger/rule engine:

- **Layout** (`workspace`, `tab`, `pane`) creates terminal locations.
- **Pane** controls a raw terminal.
- **Agent** controls a _recognised coding agent_ occupying a pane.

A pane exists whether or not an agent is in it. `agent start` requires an
existing shell pane and never creates, splits or moves layout. Use pane
commands for ordinary processes; use agent commands when herdr must validate
agent identity or interpret lifecycle state.

Agent targets are either a unique live agent **name** or the **pane ID** hosting
it. Not terminal IDs, not bare kind labels. Names must match
`[a-z][a-z0-9_-]{0,31}` and be unique among live agents. A name follows the
pane occupant and is cleared when that agent exits or is replaced.

DOC (0.9.4, #1647): suspending an agent with Ctrl+Z and resuming it with `fg`
keeps its name and saved conversation, as long as the process lives. Kept is
not foreground: while it is suspended the pane's foreground is the shell.

---

## 2. Lifecycle states

| State     | Meaning                                                                     |
| --------- | --------------------------------------------------------------------------- |
| `idle`    | ready for input, and its tab has been seen in the focused UI                |
| `done`    | same underlying idle state, after _unseen_ background work finished         |
| `blocked` | herdr recognised an approval or question UI                                 |
| `working` | actively processing                                                         |
| `unknown` | an agent is present but cannot be classified; **does not prove completion** |

`done` vs `idle` is purely about whether you have looked at it. Focusing the
tab, or `pane focus` / `agent focus`, marks it seen. CLI **reads do not**.

DOC (0.9.4/0.9.5): `idle` and `done` NORMALLY mean ready, not "nothing is
running". Antigravity and Grok count as `idle` once back at their prompt even
while their own background tasks or subagents still run (#3530). And since
0.9.5 a Claude Code question shows as `blocked` in a named session too (#4573);
before that, a named Claude session could sit at a question and not read
`blocked`, so the section 7 script could miss it.

### How herdr actually knows

OBSERVED, and important: herdr does **not** get told the state by Claude. It
**reads the terminal** and pattern-matches against a downloaded detection
manifest.

```
$ herdr agent explain wR:p1
agent: claude
state: blocked
manifest: remote:~/.local/state/herdr/agent-detection/remote/claude.toml 2026.07.13.1
rule: live_blocked_form (region=after_last_horizontal_rule priority=980)
evidence: "  6. Chat about this\n\nEnter to select - Up/Down to navigate - Esc to cancel\n"
```

Consequences:

- `manifest: remote:` means herdr **fetches detection manifests from upstream**
  on a schedule, versioned by date. Treat that as a phone-home channel when
  auditing network posture.
- Detection is heuristic. A UI change upstream can silently degrade it to
  `unknown`. Never treat `unknown` as "finished".
- `agent explain` outputs plain text; add `--json` for machine parsing.

OBSERVED on 0.9.5 (2026-10-18): the same command now reports `manifest:
bundled 2026.10.11.1`, and `--json` carries the reason in `warning`: the remote
cache (`claude.toml`, `2026.07.13.1`, files dated 29 Jul) is IGNORED because
the bundled manifest is newer, while `remote_update_status` still reads
`current`. So the remote channel still exists, but the manifest in force here
came with the binary. Read `manifest_source` before assuming either.

The Claude-side integration hook (`~/.claude/hooks/herdr-agent-state.sh`,
`HERDR_INTEGRATION_VERSION=10` since 2026-10-07, `claude: current (v10)` on
herdr 0.9.3; wired as a `session` hook in `settings.json`) reports only **session
identity**, not lifecycle state: v10 exits on every event except SessionStart.
Check with `herdr integration status`. **On 0.9.5 it reads `claude: outdated
(v10 < v11)`** (OBSERVED 2026-10-18; the Homebrew upgrade again did not rewrite
the file, still dated 7 Oct). The v11 script embedded in the 0.9.5 binary,
pulled out read-only and diffed against
`docs/reference/herdr-agent-state.UPSTREAM.sh`, differs in ONE line: the
version number (both 3070 bytes). Not installed here; that is a separate step. The file is herdr-managed and is
overwritten on reinstall -- add custom hooks beside it, never edit it. To update
it, follow "Updating the Claude hook" in [`HERDR.md`](HERDR.md): compare against
`docs/reference/herdr-agent-state.UPSTREAM.sh` first, never install blind.

**Codex status comes from the screen, with no hook, since 0.9.5.** Per the
release notes, not measured (no Codex agent was started):

- 0.9.2 (#4507, #4196): Codex is no longer reported `idle` during active
  output, its mention popups are recognised, and remapped interrupt keys no
  longer break detection. Before 0.9.2, `idle` on a busy Codex was a false
  reading.
- 0.9.4 (#4507, #4811, #4756, #5174): Codex's startup update screen shows as
  `blocked`. So an agent started with `--kind codex` can read `blocked` before
  its first prompt; that is the update chooser, not a question from the work.
  The same bullet's claim that finished turns arrive through the integration
  (with `--no-daemon`) was undone in 0.9.5, next item.
- 0.9.5 (#5246, #5278): herdr no longer installs Codex turn hooks (they made
  Codex start with a "clamping Interrupt hook timeout" warning), and Codex
  status comes from screen detection again. `herdr integration install codex`
  updates an older install.

MEASURED 2026-10-18 on 0.9.5, read-only: `herdr integration status` reads
`codex: not installed` (and `claude: outdated (v10 < v11)` in the same run),
while `command -v codex` finds the Codex program at `~/.bun/bin/codex`. So
herdr's Codex integration was never installed here and there is nothing to
update; the program and the integration are separate things. Either way,
confirm Codex output by reading the pane, not the status.

---

## 3. Command cheat sheet

```bash
# --- observe (READ-ONLY, safe against other people's sessions) -------------
herdr agent list
herdr agent get <name|pane>
herdr agent explain <name|pane> [--json]
herdr agent read <name|pane> --source visible --lines 400
herdr integration status

# --- create --------------------------------------------------------------
herdr pane split --current --direction down --cwd "$PWD" --no-focus
herdr agent start <name> --kind <kind> --pane <pane> --timeout 120000
herdr agent start <name> --kind codex --pane <pane> -- -m gpt-5.4   # native args after --

# --- drive ---------------------------------------------------------------
herdr agent prompt <name> "text" --wait --timeout 120000
herdr agent wait <name> --timeout 90000
herdr agent wait <name> --until blocked --timeout 120000
herdr agent send-keys <name> esc
herdr agent send-keys <name> ctrl+c
herdr agent rename <name> <newname>
herdr agent focus <name>          # WARNING: marks the tab seen
```

**Kinds** (OBSERVED on 0.9.5, 24, from `herdr agent` and `agent start --help`):
`pi`, `claude`, `codex`, `gemini`, `cursor`, `devin`, `agy`, `cline`, `omp`,
`mastracode`, `opencode`, `copilot`, `kimi`, `kiro`, `droid`, `amp`, `grok`,
`hermes`, `kilo`, `qodercli`, `qwen`, `letta`, `maki`, `muse`. The earlier list
of 21 lacked `qwen`, `letta` and `muse`.

---

## 4. Starting an agent: two traps

### Trap 1 -- `agent_pane_busy`

```json
{
  "error": {
    "code": "agent_pane_busy",
    "message": "agent target pane wJ:p8 is not an available shell"
  }
}
```

OBSERVED immediately after `pane split`. The pane exists but the shell is still
executing its rc file (a heavy `.zshrc` banner takes seconds). An "available
shell pane" means at an interactive prompt with no foreground command.

STILL REAL ON 0.8.2, but smaller. 0.8.2 made `agent start` wait for new
pane shells and first-run agent prompts instead of racing them
(#2410, #2537, #2773, #2774). It did not remove `agent_pane_busy`: a pane
mid-startup still refuses, and `herdr-quick-task` in this repo keeps a
bounded retry loop for exactly that. The retry below is still the right shape. NOT re-run on 0.8.2 -- reproducing it
means starting real agents in a live session, so this is upstream's account plus
our own script's behaviour, not a fresh measurement.

Fix -- wait for the prompt, then retry with backoff. (The example uses `codex`: since 2026-09-24 a
Claude worker starts only through `pj-worker start`, which does this handshake itself, and the
pane guard and `enforce-pj-workers.sh` refuse `--kind claude`; ruling D-20260924-A05.)

```bash
herdr pane wait-output "$P" --regex "$(basename "$PWD")" --timeout 30000
for i in 1 2 3 4 5 6 7 8; do
  sleep 2
  R=$(herdr agent start demo --kind codex --pane "$P" --timeout 120000 2>&1)
  echo "$R" | grep -q agent_pane_busy || break
done
```

**THAT WAIT REGEX IS WEAK IN THIS REPO.** OBSERVED on 0.9.5 (2026-10-18), in a
throwaway pane: `wait-output --regex "$(basename "$PWD")"` returned at once,
because this repo's `.zshrc` banner prints `Repo: fifty-shades-of-dotfiles`
while it is still painting. Three seconds later the banner was still going,
and a `pane run` sent then returned exit 0 yet failed in the shell
(`zsh: bad pattern: [200~echo`, the paste start arriving as literal text; a
stray `esc` sent just before may have contributed, so the cause is not
isolated). The same `pane run` at the settled prompt printed its sentinel. Two
lessons: match something only the prompt prints, and a `pane run` exit 0
means ADMITTED, not executed -- confirm by reading output.

DOC (0.9.4, #4950): on macOS, `agent start` and `pane run` now REFUSE a
command too long for a shell that is still starting, instead of silently
cutting it off. Long native args after `--` can hit this. NOT re-measured.

### Trap 2 -- `interactive_ready: true` is not ready enough

OBSERVED: `agent start` returned `"interactive_ready": true, "agent_status":
"idle"`, but a prompt submitted immediately afterwards was **silently
swallowed**. The agent's own startup banner was still painting. `--wait`
returned in 6s having settled on the _startup_ lifecycle change, not on any
answer. No error was raised. Cost telemetry stayed at `$0`, which is how the
loss was detected.

The re-sent prompt against a genuinely settled agent worked: 18s, `state=done`,
cost moved to `$0.096`.

**Mitigation:** after `agent start`, poll `agent get` until stable, sleep, then
prompt. Confirm the answer actually arrived by grepping for expected content --
never trust `--wait` returning as proof that work happened.

0.8.2 CLAIMS THIS EXACT BUG IS FIXED: "`agent start` now waits for new pane
shells and first-run agent prompts to become ready instead of racing them or
**reporting premature readiness**" (#2773, #2774). That is this trap by name.

Kept anyway, and deliberately. It is NOT re-verified here, and the failure mode
is a silently swallowed prompt that raises no error -- the original was only
caught because cost telemetry stayed at $0. Deleting a warning of that shape on
the strength of a changelog line is a bad trade: if upstream is right you lose
nothing by still confirming the answer arrived, and if it is not you lose work
silently. The last sentence of the mitigation is the durable part and does not
depend on this bug at all.

---

## 5. Reading a reply

OBSERVED: the reply sits **above** the agent's statusline. `tail` returns the
statusline and looks like an empty answer. Grep instead:

```bash
herdr agent read demo-lab --source visible --lines 400 | grep -i -B6 -A3 'pineapple'
```

DOC: if a larger `--lines` never reveals more of a completed response, the pane
is probably rendering on the terminal's alternate screen; those rows never
enter herdr's host scrollback and cannot be recovered. Fallback: ask the agent
to write its response to a temp file and reply only with the path, then read
the file. Use only as a fallback.

Sources as in `HERDR_AGENT_SKILL.md` section 6. **The small-`--lines`-returns-zero
trap this used to point at no longer reproduces**: re-measured on 0.8.2,
2026-09-17, `--lines 15` returns a truncated tail (325 bytes) rather than
nothing, and degrades smoothly down to `--lines 5`. The numbers for both
versions are in that section. The advice that followed from it is also
withdrawn there: prefer `recent-unwrapped` for transcripts again, since at
`--lines 400` it returned eight times more than `visible`.

---

## 6. `agent prompt --wait` semantics

- Submits text and Enter atomically, honouring the pane's bracketed-paste mode.
- `--wait` waits for the first settled `idle`, `done` or `blocked`. Do not also
  pass `--until` for that; use `--until` only for a state-specific workflow.
- A prompt sent from a non-working state must produce an observed lifecycle
  change within 5 seconds, else herdr returns `agent_prompt_stalled` rather than
  hanging. 0.9.5's `--help` words it precisely: with `--wait`, an accepted
  submission must reach an observed `working` or `blocked` within 5000ms, and
  a caller `--timeout` that expires first returns `timeout` instead (re-read
  from `--help` only).
- The wait tracks lifecycle state, not an individual turn. If the agent was
  already working, completion of the _previous_ turn satisfies it.
- **0.8.2: `agent prompt` now REFUSES an agent already waiting at an approval or
  question dialog**, returning `agent_blocked` without sending text or Enter
  (#2788). herdr now enforces at the CLI what sections 7 and 8 argue for on
  policy grounds: automation detects `blocked` and reports it, a human answers
  it. Your script should still check, because a refusal you ignore is a prompt
  that never ran.

---

## 7. The genuinely useful pattern: exception-based blocked detection

This is the highest-value thing in Group B. It reports and never answers.

```bash
#!/usr/bin/env bash
set -uo pipefail
BLOCKED=$(herdr agent list 2>/dev/null \
  | jq -r '.result.agents[] | select(.agent_status=="blocked") | "\(.pane_id)\t\(.cwd)"')
[ -z "$BLOCKED" ] && exit 0        # silence when nothing needs a human
echo "!! $(printf '%s\n' "$BLOCKED" | wc -l | tr -d ' ') agent(s) waiting on YOU"
while IFS=$'\t' read -r pane cwd; do
  [ -z "$pane" ] && continue
  printf '  %-8s %s\n' "$pane" "$(basename "$cwd")"
  herdr agent explain "$pane" 2>/dev/null | sed -n 's/^rule: /      rule: /p'
  herdr agent read "$pane" --source detection --lines 400 2>/dev/null \
    | grep -v '^[[:space:]]*$' | tail -3 | sed 's/^/      > /'
done <<< "$BLOCKED"
```

OBSERVED output with two real blocked sessions: it named both, gave the
matching rule, and printed the actual pending question. Silent otherwise.

Note `--source detection --lines 400`: `detection` is the snapshot herdr itself
matched against, so it is the most reliable source for "what is it asking".

---

## 8. `send-keys` -- capability and hazard

```bash
herdr agent send-keys <name> esc        # -> {"result":{"type":"ok"}}, exit 0
herdr agent send-keys <name> bogus-key  # -> {"error":{"code":"invalid_key",...}}, exit 1
```

OBSERVED: herdr validates the key name **before writing any bytes**, so a typo
cannot send garbage into a live agent.

0.8.2 ADDED REACH HERE: `pane send-keys` and `agent send-keys` now preserve
Shift when sending `shift+tab`, specifically so agent permission modes can be
cycled programmatically (#1561). Read that as the hazard growing, not shrinking
-- permission mode is the setting that decides what an agent may do without
asking, and it is now scriptable.

That safety does not extend to semantics. `send-keys` is exactly the primitive
that can dismiss or answer an approval prompt. **Automation should detect
`blocked` and report it; it should not answer it.** Restrict `send-keys` to
agents your own automation started. Never point it at a human's session.

---

## 9. Safe-by-default checklist for any automation you write

1. Enumerate with `agent list` first; act only on names you started.
2. Never `agent focus` another party's pane -- it changes their `done`/`idle`.
3. Always pass `--timeout`. Unbounded waits hang the caller.
4. Treat `unknown` as "no information", never as "finished".
5. Verify effects by reading content, not by trusting a `--wait` return.
6. Never `herdr server stop` (macOS) / `systemctl --user stop herdr.service`
   (Linux) with live sessions. (`brew services stop herdr` no longer applies:
   Homebrew removed herdr's service definition on 2026-09-24.) Since 0.9.4,
   closing the shell that started herdr no longer stops the server on macOS
   or Linux, and `SIGHUP` no longer does either; only `herdr server stop` or
   `SIGTERM` (DOC, #4920).

Related: [`HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md),
[`HERDR_PLUGINS.md`](HERDR_PLUGINS.md), [`HERDR.md`](HERDR.md).
