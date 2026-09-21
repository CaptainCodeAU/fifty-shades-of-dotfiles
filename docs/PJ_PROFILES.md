# pj profiles, the three roots, and `c2`

A **profile** lets one moving part of a `pj` launch vary while everything that
records work stays in one place. It is a `key: value` file, the same shape as the
`~/.config/pj/machine` file `install.sh` already writes.

```
pj                      the default profile
pj --profile scratch    a named one
PJ_PROFILE=scratch pj   the same, without a flag
```

Shipped 2026-09-21 (F5a). Ruled by Gavin at that stage's gate.

---

## The three roots

Everything the framework touches belongs to exactly one of three roots. Getting a
path into the wrong one is not a cosmetic mistake: it is how a second machine or a
second account quietly diverges.

| Root        | Where                                       | Holds                                                                                             | Moves with a profile? |
| ----------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------- | --------------------- |
| **CONFIG**  | the profile's `config_dir`                  | login, folder trust, `.claude.json`, transcripts, **auto memory**                                 | **yes**               |
| **RECORDS** | always `~/.claude`                          | the drawer, the rulings, `pj-global/`, `settings.project.json`, the plugin dirs, the hook scripts | **never**             |
| **MACHINE** | `~/.local/state/pj`, `~/.config/pj/machine` | the launch log, the no-wrap-up flags, this machine's letter                                       | **never**             |

**RECORDS never forks.** `open-items` and `decided` spell `$HOME/.claude` literally
and nothing derives it from `CLAUDE_CONFIG_DIR`. If the drawer forked, a scratch
session would file items into a register nobody else reads, and `decided` would
answer "not decided" about something that was. `pj-health`'s `records-pinned` row
enforces it by running `open-items --where` twice, once with a foreign
`CLAUDE_CONFIG_DIR`, and failing if the answer moves.

**MACHINE never forks either, and that is what makes the launch log useful.** It is
the one file shared by every profile, so it is the only place that maps a session id
to the config dir holding that session's transcript.

---

## The profile file

`~/.config/pj/profiles/<name>`, stowed from `home/.config/pj/profiles/`. Paths only.
It is tracked in a public repo, so nothing in it is ever a secret.

| Key               | Feeds                         | Notes                                                                                                        |
| ----------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `config_dir`      | `CLAUDE_CONFIG_DIR`           | `~/.claude` means **do not export the variable at all** (see below)                                          |
| `setting_sources` | `--setting-sources`           |                                                                                                              |
| `settings`        | `--settings`                  |                                                                                                              |
| `prompt`          | `--append-system-prompt-file` | the literal word `pj-prompt-file` runs that tool; anything else is used as a path                            |
| `plugins`         | one `--plugin-dir` each       | names are relative to `~/.claude`. `none` passes no `--plugin-dir` at all                                    |
| `required`        | flags appended last           | the **default** profile's `required` is appended to every profile, so none can drop them by omitting the key |
| `mode`            | `normal` \| `safe`            | `safe` adds `--safe-mode`. Supported, but no shipped profile uses it -- see below                            |
| `card`            | `on` \| `off`                 | `off` exports `PJ_NO_CARD=1`, and `pj-start-card` stays silent                                               |
| `model`           | `--model <name>`              | unset = the account default (Opus 5 1M here). Added F5b                                                      |
| `remote_control`  | `remoteControlAtStartup`      | `on` \| `off`, via an overlay `--settings`. Unset = leave it to the organisation default. Added F5b          |
| `voice`           | `voiceEnabled`                | `on` \| `off`, via the same overlay. Claude Code's OWN voice, not this repo's audio hooks. Added F5b         |

### The last three keys, and why they ride a second `--settings`

Added in F5b, 2026-09-21, out of the `W-20260920-A03` settings audit: of the 47 user
settings keys `pj` was dropping, Gavin ruled these three are a **per-profile** choice
rather than something every `pj` session should get.

`model` has its own flag. The other two are settings keys with no command-line flag, so
`pj` appends a **second `--settings`** carrying a JSON string. That works because the
flag repeats and **merges** — measured against 2.1.278 with three arms, because two
arms cannot tell merging from last-one-wins:

| Argv                                  | `API_TIMEOUT_MS` (from the file) | `F5B_OVERLAY` (from the string) |
| ------------------------------------- | -------------------------------- | ------------------------------- |
| `--settings <file>`                   | `1800000`                        | — (control)                     |
| `--settings <file> --settings <json>` | —                                | `OVERLAYSET`                    |
| `--settings <file> --settings <json>` | **`1800000`**                    | —                               |

The third row is the one that decided it. Had the flag been last-one-wins, the overlay
would have silently replaced the whole of `settings.project.json` — every hook, every
env var — and the first two rows would have looked exactly the same.

**Unset means emit NOTHING, never "emit the default value".** That is what keeps the
default profile's argv byte-identical to the pre-profile launcher, which `pj --selftest`
arm 1 checks and arm 19d guards from the other side.

### There is no `audio` key, deliberately

F5b was asked to add one and Gavin **parked** it instead (`W-20260921-A06`). LifeOS's
audio pipeline is the better one, and this repo's `hook_runner.py` stays repo-local
rather than travelling with `pj`. If a `pj` session ever makes a sound, it comes from
LifeOS, decided in a lifeos session. Two things were measured before it was parked and
are worth knowing:

- `config.yaml` names its sounds as `.claude/sounds/...`, resolved against `os.getcwd()`,
  so **outside this repo the sound files are simply missing** and `play_sound` returns
  `False` in silence while the voice still speaks.
- The 11 hook rows live in this repo's `.claude/settings.json`, which **both** `pj` and
  `c` read, while `~/.claude/settings.json` (which `c` alone reads) carries LifeOS's
  `VoiceCompletion`. That is why a `c` session **in this repo** speaks twice. Understood,
  not fixed.

### `config_dir: ~/.claude` means "do not export"

A `CLAUDE_CONFIG_DIR` set to its own default is **not** the same fact as one that is
unset, and the default launch has to keep it unset to stay byte-for-byte identical
to the pre-profile launcher. `pj --selftest` arm 13 is what keeps the two apart.

### With no profiles dir at all, `pj` still launches

Every value falls back to the constant the script carried before profiles existed. A
machine with nothing stowed behaves exactly as it always did. That is a supported
state, not a fault, and `install.sh` reports it as a note rather than a cross.

---

## Why `card: off` and not `--safe-mode`

The F5a brief originally said the scratch profile would run in safe mode. It does
not, and the reason is worth keeping.

Per the Claude Code docs, `--safe-mode` starts "with all customizations disabled:
CLAUDE.md, skills, plugins, hooks, MCP servers, custom commands and agents, output
styles, workflows, custom themes, custom keybindings, status line and
file-suggestion commands, LSP servers, and auto memory do not load."

That is one switch for two very different things. Using it to quieten the start card
would also disarm `enforce-secret-probe.sh`, `validate-bash.sh`, `enforce-uv`,
`enforce-pnpm` and `MemoryRootGuard` -- making a throwaway worktree the least guarded
session on the machine, which is exactly backwards. `card: off` drops only the card.

`mode: safe` remains supported for P9's baseline measurement, where a session with
nothing loaded is the point.

---

## What actually moves with the config dir

All measured 2026-09-21 against Claude Code 2.1.278, not inferred.

**The whole pj rig travels.** `pj`'s real argv was run with `CLAUDE_CONFIG_DIR`
pointed at a scratch folder and the resulting prompt snapshot read back:

| Probe                      | Result                             |
| -------------------------- | ---------------------------------- |
| control `Claude Code`      | 3 hits -- the instrument was alive |
| `OPERATIONAL_RULES`        | 5 hits -- the appended file landed |
| `pj-global RULES`          | 1 hit                              |
| `pj-voice`, `Output Style` | 1 hit each -- the style loaded     |
| skill listing              | herdr, AgentRelay, ISA all present |

Every path `pj` passes is absolute under `~/.claude`, so none of it follows the
config dir. GitHub issue `anthropics/claude-code#92645` is about `claude plugin
install`, whose installs are scoped to one config dir; `pj` never touches the plugin
store, so it is not affected.

**What does move**, observed on disk in the scratch config dir:

- `.claude.json` is created there, with its own `machineID`, `userID` and `projects`
  block. `$HOME/.claude.json` was untouched.
- `projects/<key>/*.jsonl` -- transcripts land there, under the same key encoding.
- `projects/<key>/memory/` -- created **empty**. **Auto memory does not travel.** A
  session under a new profile loads no `MEMORY.md`.
- `sessions/` -- its own. This machine registers one file per running session by PID.
- `.credentials.json` -- present in `~/.claude` (471 bytes), absent in the new dir.

### A new config dir needs a human, once

Unsandboxed, same minute, same flags:

```
default config dir  -> rc 0, "PROBE_OK"
scratch config dir  -> rc 1, "Not logged in - Please run /login"
```

And with `pj`'s real argv, the trust half, in the tool's own words:

```
Ignoring 138 permissions.allow entries from .claude/settings.local.json: this
workspace has not been trusted. ... or set projects["<repo>"].hasTrustDialogAccepted:
true in <CLAUDE_CONFIG_DIR>/.claude.json
```

So the first launch on any new profile stops for a `/login` and a trust dialog.
Nothing automates that. Three places now say so in the same words: `install.sh`'s
prereq block, `pj-health`'s `profile` row, and `c2` before it launches.

---

## The sibling rule

Profiles are **sibling directories under `~`** -- `~/.claude`, `~/.claude-scratch`,
`~/.claude-b` -- never nested inside one another. `pj-health`'s `profile-siblings`
row enforces it:

| Finding                                        | State    | Why                                                                                                                 |
| ---------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------- |
| one `config_dir` inside another                | **FAIL** | `~/.claude/<x>` would put a profile's transcripts inside the RECORDS repo, where dot-claude would try to track them |
| a `config_dir` deeper than one level under `~` | WARN     | odd, but nothing is measured to break                                                                               |
| a `config_dir` not under `~` at all            | WARN     | said in its own words: it is not "deep", it is somewhere else                                                       |
| a declared `config_dir` that does not exist    | WARN     | the normal state of a fresh profile; it names the login that is owed                                                |

None of the three WARNs is a FAIL, deliberately. A FAIL on an unmeasured hazard is a
false alarm, and false alarms are how a row stops being read.

---

## `c2`, the throwaway session

```
c2 start <topic>             worktree + pj --profile scratch inside it
c2 done  <topic>             teardown, only if both guards pass
c2 done  <topic> --discard   teardown anyway
c2 list                      this repo's scratch worktrees
```

The worktree goes to `<repo>/.worktree/scratch/<topic>` on branch
`scratch/<topic>` -- `D-20260914-A01` applied literally. `hwt` is the default route;
`--no-herdr` uses plain `git worktree add` at the identical path, because the ruling
is about where a worktree lives rather than which tool digs the hole, and a scratch
checkout should not depend on the herdr server being up. `c2` says which route it
took.

The learnings folder `~/Scratch/<project>/` is created on `start` and lives **outside**
the worktree on purpose: everything inside the worktree is what `done` may destroy,
so anything worth keeping has to leave first.

### The two guards

Both **refuse**. Neither asks.

1. **Uncopied work** -- any uncommitted change in the worktree: tracked-modified,
   staged, or untracked and not ignored. Those files exist nowhere else.
2. **Unmerged commits** -- commits on `scratch/<topic>` that no other local branch or
   remote-tracking ref contains, so a topic merged into a release branch rather than
   the base still counts as merged.

`--discard` skips both. It is the only way to lose work here and it has to be typed.

`c2` **never pushes**, on any path. And it contains no `rm`: teardown is `git worktree
remove` and `git branch -D`, so the deletion-safety rule's banned list is never
reached.

---

## The worktree transcript, and a 64-character cap

Every pj tool keys the project by `git rev-parse --git-common-dir` -- the **main**
repo. Claude Code derives `projects/<name>` from the **working directory**. Inside a
`c2` worktree those disagree, so the session's transcript lands under a key nothing
else looks in and `pj-health` cannot find its own evidence.

`c2` closes that by setting `CLAUDE_CODE_PROJECT_DIR_NAME` to the main repo's key.
The variable is ignored unless `CLAUDE_CONFIG_DIR` is also set, and it is read only
from the launch environment, never from a settings `env` block -- so `c2 start` is
the only place it can be set.

**It is capped at 64 characters and a longer value is ignored in silence.** Bisected
2026-09-21 against Claude Code 2.1.278, one live probe per length:

| Length                      | Honoured |
| --------------------------- | -------- |
| 62, 64                      | yes      |
| 65, 66, 70, 78, 88, 99, 149 | **no**   |

No warning, no error, normal exit -- the transcript simply lands under the
cwd-derived name instead. A leading dash is fine (tested separately), so length is
the whole of it. The cap appears in no documentation found in that session.

So `c2` measures the key first. Under the cap it passes it; over the cap it says so
and launches without it, rather than passing a value that will be quietly dropped.
Most real keys fit: `~/CODE/CaptainCodeAU/Network_Plan` is 48 characters and this
dotfiles repo is 59. A repo under a deep scratch path does not.

---

## One profile must not read another's transcripts

The launch log is the index from session to config dir, and it is matched on
**`profile=` as well as `project=`**. Matching the project key alone was measured
wrong on 2026-09-21: with a `scratch` session and a `b-test` session in one repo,
`pj-health --profile scratch` reported `PASS evidence-card transcript 89f89c44` --
the **b-test** session's transcript. Since `scratch` sets `card: off`, a start card
in its own transcript would have been a real fault, and the row would have hidden it
behind someone else's green.

A row that cannot see must say so. Scoped correctly it now reads `NOT MEASURED ...
searched: ~/.claude-scratch/projects`, which is the true answer.

---

## Adding a second account

1. Write `~/.config/pj/profiles/<name>` with `config_dir: ~/.claude-<name>` (a
   sibling of `~/.claude`, never inside it) and whatever `plugins` and `card` you
   want. Add it under `home/.config/pj/profiles/` in the dotfiles repo and re-stow,
   or it will not exist on the other machines.
2. `pj-health --profile <name>` -- the `profile` row will WARN that the config dir
   does not exist yet and name the login you owe.
3. `pj --profile <name>` in a real pane. Run `/login`, then accept the trust dialog.
   Both are one-time, and only a human can do either.
4. `pj-health --profile <name>` again. The WARN becomes a PASS.

The drawer, the rulings and `pj-global` are **the same ones** from that account's
sessions: RECORDS does not fork. Auto memory is **not** shared, because it lives
under the config dir.

---

## Where each tool sits

| Tool                    | Root it follows                                                                                      |
| ----------------------- | ---------------------------------------------------------------------------------------------------- |
| `pj`                    | exports CONFIG; passes RECORDS paths absolutely                                                      |
| `pj-prompt-file`        | RECORDS for its sources, MACHINE for its cache                                                       |
| `pj-launch-check`       | RECORDS for the expected argv, MACHINE for the log; records `profile=` and `config_dir=`             |
| `pj-start-card`         | RECORDS + MACHINE; silent under `PJ_NO_CARD`                                                         |
| `pj-session-end`        | MACHINE for the flag; follows CONFIG automatically via the hook JSON's absolute `transcript_path`    |
| `pj-wrap`               | MACHINE + RECORDS; reads the transcript path out of the flag record, so it is already CONFIG-correct |
| `pj-health`             | all three; `--profile <n>` selects which CONFIG to read transcripts from                             |
| `open-items`, `decided` | **RECORDS only, always**                                                                             |
| `pj-id`                 | MACHINE only                                                                                         |
| `c2`                    | RECORDS for the repo, CONFIG through the profile it launches                                         |

## The project key

`open-items`, `decided`, `pj-start-card`, `pj-session-end`, `pj-launch-check` and
`pj-health` all derive the project key from `git rev-parse --git-common-dir`, not
`--show-toplevel`. From inside a linked worktree the first returns the **main** repo
and the second returns the worktree, so a `c2` session shares its parent project's
drawer instead of inventing a key nothing else writes to.
