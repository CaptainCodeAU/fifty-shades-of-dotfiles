# Claude Code hooks: how they get deployed

## The problem this solves

A Claude Code hook needs **three** things. This repo can only stow one of them.

| Part                        | Lives in                      | Deployed by                           |
| --------------------------- | ----------------------------- | ------------------------------------- |
| 1. The hook script          | `~/.claude/hooks/*.sh`        | **stow** (from `home/.claude/hooks/`) |
| 2. The registration         | `~/.claude/settings.json`     | **`claude-hooks-sync`** (this doc)    |
| 3. Whatever the hook guards | e.g. `~/.claude/skills/herdr` | nothing -- machine-local              |

Before 2026-09-05 only part 1 existed. `grep -n '\.claude' install.sh` returned
**zero** matches, so every newly added hook was stowed and inert on every machine
until somebody hand-edited a 44KB JSON file, which in practice nobody did.

It surfaced on the Intel MacBook Pro: the login banner reported 13 tracked files
not linked, the first three being `enforce-herdr-skill.sh`,
`mark-herdr-skill-read.sh` and `census-selftest`. Stowing them would have put the
scripts in place and changed nothing about whether they ran.

`~/.claude/settings.json` **cannot** be stowed. It is machine-local: the model,
MCP servers, voice config, permissions and the whole PAI hook set share that file.

## The pieces

| Path                                         | What it is                                       |
| -------------------------------------------- | ------------------------------------------------ |
| `settings/claude/hooks.json`                 | The manifest -- the registrations this repo owns |
| `home/.local/bin/claude-hooks-sync`          | The merger. Add-only.                            |
| `home/.local/bin/claude-hooks-sync-selftest` | 21 tests; proves the merger behaves              |
| `install.sh`                                 | Calls the merger. Three lines, three call sites. |

The manifest lives under `settings/`, not `home/`, because it is installer input
rather than a dotfile -- the same reason `settings/iterm2` and `settings/wezterm`
live there (`install.sh:975`: "NOT stow-managed").

## Using it

```sh
claude-hooks-sync --check              # what is unregistered? writes nothing
claude-hooks-sync --install            # register what is missing
claude-hooks-sync --install --dry-run  # say what would change
claude-hooks-sync-selftest             # 21 tests
```

Exit codes: `0` nothing pending / success, `1` pending (check) or write failed
(install), `2` cannot run (no jq, no manifest, no settings.json, malformed JSON).

`./install.sh` and `./install.sh --stow-only` both run `--install` after stow.
`./install.sh --check` runs `--check` and folds the result into Deploy Parity, so
an unregistered hook fails the audit exactly like a missing symlink does.

## Adding a hook

1. Put the script in `home/.claude/hooks/`.
2. Add an entry to `settings/claude/hooks.json`.
3. `./install.sh --stow-only`.
4. Restart Claude Code (or open `/hooks`) so it re-reads settings.

```json
{
  "event": "PreToolUse",
  "matcher": "Bash",
  "script": "my-hook.sh",
  "entry": {
    "type": "command",
    "command": "$HOME/.claude/hooks/my-hook.sh",
    "timeout": 5
  },
  "requires": ["$HOME/.claude/skills/something"],
  "why": "One line, printed when the entry is skipped"
}
```

Use `$HOME`, never a literal path -- the same JSON has to work on every machine.

## The two gates

An entry is registered only if **both** pass. Either failing is a skip with a
printed reason, never an error.

**The script must exist on disk.** Registering a hook whose file is missing turns
every matching tool call into an error -- strictly worse than not registering it.

**Every `requires` path must exist.** This one is load-bearing.
`enforce-herdr-skill.sh` _denies_ every `herdr` command until the herdr skill is
invoked in the session, and the only thing that lifts the block is the sibling
hook seeing that skill run. `~/.claude/skills/herdr` is a symlink into
`~/.agents/`, is not tracked here, and nothing deploys it. On a machine with the
hook registered and no skill, **herdr is blocked permanently with no way to
unlock it** -- and the laptop is precisely the box that drives herdr against the
mini.

## Why add-only

`claude-hooks-sync` never removes an entry and never edits one. A registration
pointing at a hook this repo has retired is left for a human.

The reason is blast radius. `settings.json` is not ours; an installer that can
delete from it is an installer that can lose your MCP servers. Pruning was
offered and deliberately declined on 2026-09-05.

## Why jq is safe here (measured, not assumed)

`jq '.' ~/.claude/settings.json` returned **byte-identical** output: 44335 bytes
in, 44335 out, `cmp` silent, 51 keys both sides. The file is strict JSON with no
`//` comments -- unlike the Cursor/VSCode settings, which `install.sh` has to
text-match for exactly that reason (`install.sh:185`) -- and it is 2-space
indented, which is jq's default.

Stronger still: a copy of the real 44KB file with one registration deleted, run
through `--install`, came back **byte-for-byte identical to the original**.

Re-check this if `settings.json` ever gains comments.

## Two traps worth keeping

**`IFS=$'\t' read` drops empty fields.** Tab is an IFS _whitespace_ character, so
bash collapses a run of tabs into one delimiter. An entry with no `requires`
emitted two adjacent tabs, every later field shifted left by one, `cmd` received
the `why` text, nothing ever looked registered, and each run appended a
duplicate. Measured: `already-there.sh` hit count=2 after one `--install`. Fixed
by joining with US (``), which is not whitespace.

**`mktemp -d` with no template ignores `$TMPDIR` on BSD/macOS.** It uses the
confstr default under `/var/folders`, which is not writable everywhere. Always
pass an explicit template. Same family as the `stat -f` / `stat -c` split.

**A FAILED APPEND is a redirection error, and the command's own `2>/dev/null`
cannot catch it.** `printf ... >>"$LOG" 2>/dev/null` still prints
`Operation not permitted` when the shell cannot open `$LOG`, because the shell
raises that before the command runs. A hook that logs on every turn then prints
an error on every turn, which is the false alarm this repo cares most about.
Wrap the whole thing: `{ printf ... >>"$LOG"; } 2>/dev/null`. Measured
2026-09-22 in `pj-voice-contract.sh`, whose log lives outside the Bash sandbox's
writable set.

---

## `pj-voice-contract.sh`: the first `UserPromptSubmit` entry, and why not `Stop`

Added at the P9 gate, 2026-09-22. It states the voice contract before a reply is
written, names what the previous reply broke, and appends one TSV row per
measured turn to `${XDG_STATE_HOME:-~/.local/state}/pj/voice-drift.log`:
timestamp, session, turn, **model**, em dashes, prose chars.

**Why the event matters more than the hook.** `DriftReminder.hook.ts`, the
LifeOS equivalent, records the measurement in its own header: `FormatGate` was a
`Stop` hook, went observation-only on 2026-07-11, and drift went from **0%
across 168 turns** to **61-91% every day across 2,608**. A `Stop` hook fires
after the text is on screen and can only block, which forces a doubled re-emit.
Separately, on this machine `peer-reply-check.sh` prints on `Stop` with exit 0
and nothing sees it. Checking **before** the answer is written is the only point
that works.

**Why the LifeOS hook was not simply carried.** It runs standalone, and the
`script_path` plus `targets: ["project"]` route would have taken one manifest
entry, exactly the `MemoryRootGuard.sh` precedent. But its contract is hardcoded
to `banner first, closer last, max 2 em-dashes`, `pj-voice` defines no banner and
no closer and its rule says zero, and the only environment seam is `LIFEOS_DIR`,
a path. Carrying it would have put a contract wrong in all three clauses into
every `pj` turn, and written state into `lifeos-private` on each one.

**The model field is the point, not decoration.** The defect this hook exists for
is model-specific. Across the same 17 `pj` transcripts, same rules file, same
output style:

| Model              | Prose chars | Em dashes | Rate      |
| ------------------ | ----------: | --------: | --------- |
| `claude-opus-5`    |     157,774 |   **371** | 1 per 425 |
| `claude-fable-5-1` |      15,725 |     **0** | none      |

So a count taken without naming the model cannot be read at all, and the `c`
family's clean record is thinner evidence than it first looks: 15,831 of its
19,505 prose characters are Fable, which is clean everywhere. The arm that
actually compares is `c` on Opus, 3,674 characters, 0 observed against about 9
predicted.

---

## `pj-question-ping.sh`: a ping at every question popup

Added 2026-09-23 for D-20260921-A10, widened that day by Gavin to "whenever
there is one of those Ask User Question tool popups". Registered on
`PreToolUse` with matcher `AskUserQuestion`, project target only.

**What it does.** Four sounds (Ping, Glass, Glass, Glass) through `afplay`,
then two `imsg` messages one second apart:

```
<session>: question waiting: <header, or first 80 chars of the question>
answer the popup in <session>
```

`<session>` is `$CLAUDE_CODE_SESSION_NAME`, else the basename of the git
toplevel of the payload's `cwd`. `imsg` sends only to `$IMSG_TO`.

**It never delays the popup.** The hook prints nothing, exits 0, and hands the
signal to a double-forked worker with stdin, stdout and stderr on `/dev/null`.
A worker that kept either output pipe would make Claude Code wait for it; the
selftest's timing arm fails in exactly that case (measured: 3.0 s instead of
0.06 s).

| Case                                    | Result                                         |
| --------------------------------------- | ---------------------------------------------- |
| `PJ_NO_PING=1`                          | nothing, not logged                            |
| same session pinged under 20 s ago      | nothing, logged as `debounced`                 |
| `afplay` missing                        | messages only, log names `afplay`              |
| `imsg` missing or `IMSG_TO` unset       | sounds only, log names what was missing        |

The question text is agent-written, so control and bidi characters are
replaced, token-shaped strings become `[redacted]`, and every part is capped.

State lives under `${XDG_STATE_HOME:-~/.local/state}/pj/`: `question-ping.log`
(one decision per line, never the message text) and `question-ping/<session>`
(the debounce stamp).

```sh
~/.claude/hooks/pj-question-ping.sh --selftest   # fake afplay and imsg, 24 arms
```

The selftest pins `PJ_PING_AFPLAY` and `PJ_PING_IMSG` to fake binaries. When
either is set, even to a missing path, it replaces the PATH lookup, so no arm
can reach the real `afplay` or `imsg`.
