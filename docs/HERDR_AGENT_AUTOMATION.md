# herdr: Agent Automation (Group B)

**Audience: an AI coding agent, not a human.** This replaces reading
https://herdr.dev/docs/preview/agent-automation/.

herdr-verified: 0.9.1

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

The Claude-side integration hook (`~/.claude/hooks/herdr-agent-state.sh`,
`HERDR_INTEGRATION_VERSION=7`, wired as a `session` hook in `settings.json`)
reports only **session identity**, not lifecycle state. Check with
`herdr integration status`. The file is herdr-managed and is overwritten on
reinstall -- add custom hooks beside it, never edit it.

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

**Kinds** (OBSERVED, 21): `pi`, `claude`, `codex`, `gemini`, `cursor`, `devin`,
`agy`, `cline`, `omp`, `mastracode`, `opencode`, `copilot`, `kimi`, `kiro`,
`droid`, `amp`, `grok`, `hermes`, `kilo`, `qodercli`, `maki`.

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

STILL REAL ON 0.8.2, but smaller. 0.8.2 made `agent start` wait for new pane
shells and first-run agent prompts instead of racing them (#2410, #2537, #2773,
#2774). It did not remove `agent_pane_busy`: a pane mid-startup still refuses,
and `herdr-quick-task` in this repo keeps a bounded retry loop for exactly that.
The retry below is still the right shape. NOT re-run on 0.8.2 -- reproducing it
means starting real agents in a live session, so this is upstream's account plus
our own script's behaviour, not a fresh measurement.

Fix -- wait for the prompt, then retry with backoff:

```bash
herdr pane wait-output "$P" --regex "$(basename "$PWD")" --timeout 30000
for i in 1 2 3 4 5 6 7 8; do
  sleep 2
  R=$(herdr agent start demo --kind claude --pane "$P" --timeout 120000 2>&1)
  echo "$R" | grep -q agent_pane_busy || break
done
```

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
  hanging.
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
6. Never `herdr server stop` / `brew services stop herdr` with live sessions.

Related: [`HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md),
[`HERDR_PLUGINS.md`](HERDR_PLUGINS.md), [`HERDR.md`](HERDR.md).
