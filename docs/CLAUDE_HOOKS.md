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

## Rewriting a tool call (`updatedInput`): two rules, both measured

A `PreToolUse` hook can change a Bash command before it runs instead of denying
it: `hookSpecificOutput.updatedInput` replaces the tool input. The convention
hooks (`enforce-uv.sh`, `enforce-pnpm.sh`, this repo's `enforce-no-cd.sh`) do
this since 2026-09-23 so a clear slip costs no round trip. Measured on Claude
Code 2.1.280 in headless scratch sessions with a fixture hook registered through
`--settings` only, 12 live arms, 2026-09-23.

**Rule 1: send `updatedInput` with NO `permissionDecision`.** With `"allow"`
the rewritten command runs even when nothing permits it. With no decision, the
normal permission check runs on the REWRITTEN command.

| Arm | Hook output                             | Permissions                                                | Result                                     |
| --- | --------------------------------------- | ---------------------------------------------------------- | ------------------------------------------ |
| P0  | none (control)                          | nothing allowed                                            | `touch A.txt` refused: touch needs a grant |
| P1  | rewrite to `touch B.txt`, no decision   | only `Bash(touch A.txt)` allowed                           | refused: the check ran on `touch B.txt`    |
| P2  | same                                    | only `Bash(touch B.txt)` allowed                           | ran, B.txt created                         |
| P3  | same                                    | nothing allowed                                            | refused                                    |
| P5  | same                                    | `Bash(touch A.txt)` allowed, deny rule `Bash(touch B.txt)` | refused by the deny rule                   |
| P6  | rewrite + `permissionDecision: "allow"` | NOTHING allowed                                            | **ran, B.txt created: escalation**         |

P6 is the one to remember: a hook that answers `allow` turns every rewrite into
an auto-approval, so a slip that would have prompted (or been refused) runs
silently. The docs say `allow` skips the prompt while deny and ask rules still
apply; they do not say the rewrite is re-checked, and P1 to P5 show that only
the no-decision form gets that check.

**Rule 2: never let two hooks rewrite the same call.** The official hooks
reference: "the last one to finish takes effect. Since hooks run in parallel,
the order is non-deterministic. Avoid having more than one hook modify the same
tool's input." Every hook sees the ORIGINAL input. A deny from any hook beats a
rewrite from another (P4: rewrite + allow alongside a deny hook, refused with
the deny hook's reason; P7: the same with a no-decision rewrite). So when one
command trips two rewriting hooks (`cd x && python3 y`, `npm test && pip
install z`), each hook DENIES with one combined message instead of rewriting.
The deny is deterministic; two rewrites would not be.

**What the session is told.** `additionalContext` reaches the model verbatim,
as `PreToolUse:Bash hook additional context: <text>`. `permissionDecisionReason`
on an allow did not reach it at all (0 occurrences of its marker in the stream,
2 of the context marker). The tool call in the transcript still shows the
ORIGINAL command, so the context line must say what actually ran.

A rewrite with no decision behaves like an allow for the purpose of later hooks:
none re-run on the new text. So a rewrite must never introduce anything another
guard would refuse; the convention hooks only insert `uv run`, `pnpm`,
`builtin cd` and a subshell.

```sh
~/.claude/hooks/enforce-uv.sh --selftest              # 78 arms
~/.claude/hooks/enforce-pnpm.sh --selftest            # 56 arms
.claude/hooks/enforce-no-cd.sh --selftest             # 64 arms (this repo only)
.claude/hooks/enforce-builtin.sh --selftest           # 44 arms (this repo only)
~/.claude/hooks/validate-bash.sh --selftest           # 113 arms (29 function, 84 payload)
CONV_HOOK_UNDER_TEST=<other copy> <hook> --selftest   # same arms, another copy
VB_HOOK_UNDER_TEST=<other copy> validate-bash.sh --selftest
CONV_PAYLOAD_FILE=<captured payload> <hook> --selftest   # arms on a real envelope
```

The three share `home/.claude/hooks/conv-shscan.awk` (a zsh command scanner:
quotes, `$(...)`, heredocs, `|&`, `&!`, `=(...)`, glob qualifiers) and
`conv-hooklib.sh` (JSON in and out, the log, the selftest runner). A new hook
that rewrites should reuse them rather than grow a fourth regex.

Two deny-only modes use the same scanner (2026-09-23): `builtin`, for
`enforce-builtin.sh`, and `guard`, for the three alias-and-brew rules in
`validate-bash.sh`. Deny-only modes never compose with the rewriting ones. Only
`guard` records the commands inside `$(...)`, `<(...)` and `=(...)` and reads
backtick bodies and `eval` arguments, because an alias expands there too
(measured in agent Bash: after an assignment, `time`, `nocorrect`, `!`, keywords,
`(`, `{`, in `$(...)`, backticks and `eval`; NOT after `noglob`, `nohup`,
`command`, `builtin`, `exec`, `env`, `sudo` or `xargs`). The other modes still
skip those bodies, as the old sed strip did. The scanner also marks commands
inside an explicit `( )` subshell, which is how `enforce-no-cd.sh` allows
`(cd /x && make)`.

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

**What it does.** It decides, then runs `pj-ping question "<header>" --detach`
from the payload's `cwd` (the first question's header, or its text when the
header is empty). Since 2026-09-23 the sounds, the two numbered messages, the
sanitising and the session name all belong to `pj-ping`, so a popup's ping has
the same format as every other ping (see `docs/PJ_PING.md`):

```
❓ PJ QUESTION #K3F9 17:30:41 | <session> | <header, capped at 80>
❓ #K3F9 2/2 | answer the popup | pane <HERDR_PANE_ID or ->
```

`pj-ping` is found as `$PJ_PING_BIN` when set, else `../../.local/bin/pj-ping`
beside the hook (right in the repo and once stowed), else on `PATH`.

**It never delays the popup.** The hook prints nothing and exits 0. `pj-ping
--detach` prints the id and hands the signal to a double-forked worker with
stdin, stdout and stderr on `/dev/null`. A worker that kept either output pipe
would make Claude Code wait for it; the selftest's timing arm fails in exactly
that case (measured before pj-ping: 3.0 s instead of 0.06 s; after: 0.1 s).

| Case                               | Result                                         |
| ---------------------------------- | ---------------------------------------------- |
| `PJ_NO_PING=1`                     | nothing, not logged                            |
| same session pinged under 20 s ago | nothing, logged as `debounced`                 |
| `pj-ping` missing                  | nothing, logged                                |
| `afplay` missing                   | messages only, `ping.log` names `afplay`       |
| `imsg` missing or `IMSG_TO` unset  | sounds only, `ping.log` names what was missing |

State lives under `${XDG_STATE_HOME:-~/.local/state}/pj/`: `question-ping.log`
(one decision per line with the ping id, never the message text),
`question-ping/<session>` (the debounce stamp) and `pj-ping`'s own `ping.log`,
keyed by the same id.

```sh
~/.claude/hooks/pj-question-ping.sh --selftest   # fake afplay and imsg, 26 arms
```

The selftest pins `PJ_PING_AFPLAY` and `PJ_PING_IMSG` to fake binaries, and
`pj-ping` honours them. When either is set, even to a missing path, it
replaces the PATH lookup, so no arm can reach the real `afplay` or `imsg`.
`PJ_QUESTION_PING_HOOK=<path>` points the selftest at another copy of the
hook.

---

## `enforce-no-permanent-delete.sh`: deletes that never call `rm`

Added 2026-09-23 on Gavin's ruling (option A). Registered on `PreToolUse` with
matcher `Bash` for **both** targets, because the Deletion rule is machine-wide.
It denies `git worktree remove`, `git clean` without `-n`, `reset --hard`,
checkout/restore discards, `branch -D`, `stash drop`, `find -delete`, `/bin/rm`,
`rm -P`, `SAFE_RM_OFF`, `unlink`, `shred`, `truncate`, `dd of=`, a bare `> f`,
`rsync --delete`, deleting calls in inline code, and prune/cleanup commands.
The full coverage table, including what it cannot see, lives in
[`DELETION_SAFETY.md`](DELETION_SAFETY.md); this section is only the hook side.

**A lexer, not a grep.** Every sibling guard strips quotes with `sed` one line at
a time, so a double-quoted string that spans lines (a multi-line `git commit -m`)
is not stripped and its words read as commands. Measured 2026-09-23 while
building this hook: `enforce-uv.sh` denied a commit whose message named an
interpreter flag, and `enforce-secret-probe.sh` denied an `rg` whose regex held
`|env|`. This hook lexes the whole command in one `awk` pass instead: quotes,
heredocs, comments, `$( )`, backticks, process substitution and zsh shapes, then
judges the command word of each simple command.

**Why the lexer also filters.** `/bin/bash` is 3.2 on macOS and costs about
0.15 ms per simple command it sees. A dense 5 KB command is about 330 of them.
So the `awk` pass drops every simple command that holds no trigger word, alias,
`SAFE_RM_OFF` or truncating redirection, since nothing in it can be denied.
`DEL_GUARD_NOFILTER=1` turns the filter off, and the selftest runs every arm
BOTH ways, so a filter that hid a deniable command fails an arm.

**Aliases are read live.** The lexer reads the newest
`~/.claude/shell-snapshots/snapshot-*.sh` on each call and sends the expansion of
any alias it meets; the rules classify that expansion as zsh would.

```sh
~/.claude/hooks/enforce-no-permanent-delete.sh --selftest   # 268 arms, classifier arms run twice
~/.claude/hooks/enforce-no-permanent-delete.sh --mutants    # about 8 min: removes each #M: line
~/.claude/hooks/enforce-no-permanent-delete.sh --classify '<command>' [cwd]
```

| Seam                     | Effect                                               |
| ------------------------ | ---------------------------------------------------- |
| `DEL_GUARD_LOG`          | log file (default `.../dotfiles/hooks-security.log`) |
| `DEL_GUARD_SNAPSHOT_DIR` | where snapshots are looked for                       |
| `DEL_GUARD_NOFILTER=1`   | lexer emits every command (equivalence testing)      |

---

## `enforce-no-reset-by-name.sh`: remove a directory, then reuse the name

Added 2026-09-24 for W-20260924-A32 (Stage 1), on Gavin's ruling: `rm` keeps
failing loudly with no fallback, and a hook blocks the pattern in every project.
Registered on `PreToolUse` with matcher `Bash` for **both** targets, the same
guard shape as `enforce-no-permanent-delete.sh` (`_shape_note` in the manifest, A76). Deny only.

**The class.** `rm -rf "$S/mut4" 2>/dev/null; mkdir -p "$S/mut4"; cp ... "$S/mut4/"`.
In the Claude sandbox the Trash-routed `rm` fails (rc 1) and leaves the directory;
`2>/dev/null` and `;` hide that, and the next step merges into stale files, or,
with `cp -i` and a heredoc in the same call, hangs (2026-09-19, about 23 minutes).

**What it denies.** A recursive `rm` (or `rmdir`) of a path P, then, later in the
same command, `mkdir`, `cd`, the destination of `cp`/`mv`/`ln`/`rsync`, `tar -C`,
`unzip -d`, `git init`, `touch`/`tee` or a `>` into P. Paths compare as text after
dropping quotes, `${V}` braces, `./` and trailing slashes.

**What it allows.** An `&&` chain from the `rm`; a used check of P (`test ! -e P &&`,
`[ -e P ] && exit`, `if [ -e P ]`); `rm ... || exit`; `git clone ... P &&` (a clone
refuses a non-empty survivor); a variable reassigned in between; `set -e`; a
non-recursive `cp` onto exactly P (a file overwrite cannot merge).

The rule lives in `conv-shscan.awk` as the deny-only mode `reset`; the hook is the
thin `conv-hooklib.sh` wrapper, like `enforce-uv.sh`.

```sh
~/.claude/hooks/enforce-no-reset-by-name.sh --selftest   # 41 arms; DENY arms are real transcript commands
```

Measured against every distinct Bash command in this machine's transcripts
(132,937, 2026-09-24): 362 would be denied (0.27%); a hand-graded random 40 were
all the real pattern, none a misread.

---

## `enforce-pj-workers.sh`: a conductor starting a plain Claude worker

Added 2026-09-24 for W-20260924-A59, on rulings D-20260924-A04 (layered) and A05
(pj-worker, a pane guard, and this hook). On 2026-09-24 four workers started with
`herdr agent start --kind claude` ran as plain `claude`: no pj system prompt, no
project hooks, no Mods flag. A conductor starts a Claude worker ONLY with
`pj-worker start`, and a clean-room worker with `pj-worker start --cleanroom`.
Registered on `PreToolUse`, matcher `Bash`, for **both** targets, because a
conductor launched as `cb` or `lifeos` loads only the user target. Deny only.

**What it is: the early, honest-slip layer. It is NOT the floor.** A Bash hook
sees the text of one Bash call and nothing else. It refuses the conductor's own
slip before anything reaches a pane, and its denial names the route to use. The
floor is the `claude()` guard in the pane's own zsh (`.zshrc`, active when
`HERDR_ENV=1`), because herdr TYPES `claude` into that shell whatever route
started it. redteam-3 H1 measured the routes, with a decoy `claude()` in a pane:

| Route                                                                                       | Does this hook see it?                                                   |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `herdr agent start ... --kind claude` (any case, `claude-code`, `--machine X`)              | yes, denied                                                              |
| `herdr pane run P "claude ..."`, `"cb"`, `"lifeos"`, `"claude-clean"`                       | yes, denied                                                              |
| `herdr pane send-keys P c l a u d e enter` in ONE call                                      | yes, denied (keys are reassembled)                                       |
| any of the above inside `$(...)`, backticks, a function body, `bash -c`, `eval`, `ssh host` | yes, denied                                                              |
| `send-text P "cla"`, then `send-text P "ude"` in a SECOND Bash call                         | **no**: each call alone is harmless text                                 |
| a script or `python3` talking to herdr's socket (`agent.start`)                             | **no**: the text is `zsh x.sh`                                           |
| `herdr-quick-task`                                                                          | no, and it does not need to: it routes kind `claude` through `pj-worker` |
| the Monitor tool                                                                            | **no**: no Bash hook runs there at all (W-20260924-A71)                  |
| a claude binary behind a variable (`pane run P "$CMD"`)                                     | **no**: the text is not known until it runs                              |

**What it denies.** `herdr [--machine X] agent start ... --kind K` unless `K`,
trimmed and lowercased, is one of the non-claude kinds herdr 0.9.1 lists (`codex`,
`gemini`, ...): so `claude`, `claude-code`, `Claude`, a kind from an expansion, or
no readable `--kind` at all. The old clean-room text exemption
(`-- --setting-sources ''`) is refused by name. `herdr pane run|send-text|send-keys`
whose text, re-scanned the way the pane's zsh would run it, has a command whose
COMMAND WORD is `claude` (bare, by path, or `~/.local/share/claude/versions/X`),
or a `.zshrc` launcher: `cb cr ci cpr cd_ cskip ct lifeos claude-clean`, or
`__claude_launch claude`.

**What it allows.** `pj` (the Mods probe launches too), `pj-worker`,
`herdr-quick-task`, other kinds, `herdr agent start --help`, claude's info forms in
a pane (`--version`, `--help`, `agents`, `mcp`, `doctor`, `plugin`, `update`, ...),
`claude` as an argument (`alias claude`, `which claude`), and prose: quotes,
heredoc bodies, commit messages.

**One named override** (redteam-3 H6). A proof whose control needs a plain worker
prefixes the herdr command with `PJ_WORKERS_CONTROL=<W-YYYYMMDD-XNN>`. It is
allowed with no permission decision (the normal permission check still runs),
logged as `CONTROL` to `hooks-security.log`, and named back in the hook's reply
and a `systemMessage`. A malformed id, or the prefix on a different command,
does not count.

**It fails closed** (redteam-3 H4). No `jq`, a payload that is not JSON, or a
payload with no `tool_input.command`: when the raw stdin mentions `herdr` with a
launch verb it denies by name, in pure bash. Every deny is
`permissionDecision: deny` with exit 0, so even the old `test -x ... || true` wrapper
could not swallow it (a selftest arm runs the wrapper). A missing scanner falls back
to a crude word match. The script not being there is covered by the registration
since A76 (2026-09-25): a missing guard denies every Bash call by name; under the old
wrapper it allowed everything. `pj-health`'s `pj-workers-hook` row
checks that it is stowed and registered in both settings files.

The rule lives in `conv-shscan.awk` as the deny-only mode `pjw`, which records
commands inside `$(...)` the way `guard` does and re-scans the nested strings.

```sh
~/.claude/hooks/enforce-pj-workers.sh --selftest   # 80 arms; DENY and ALLOW arms are real transcript commands
```

Measured 2026-09-24 against every distinct Bash command in this machine's
transcripts that mentions herdr (4,123 from 3,806 transcripts): 147 would be
denied. 133 of them hold `--kind claude` and every one read was a live launch;
the other 14 are real `claude`, `cb` or `lifeos` pane launches and redteam-3's
kind probes. The first pass also denied 11 `herdr agent start --help` probes,
which is how the `--help` rule got in. 27 one-fault mutants, 27 killed.
