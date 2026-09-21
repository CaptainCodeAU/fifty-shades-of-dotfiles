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

## Cross-config-dir messaging: one shared registry

**The problem, from F5a and F5b.** `ListAgents` in a `~/.claude` session could not see a
live `~/.claude-scratch` session, and the scratch session saw **zero** peers -- not even
the Remote Control rows. So `SendMessage` could not reach a `c2` session from a normal
`pj` session, or the reverse, and herdr was the only cross-profile channel on the machine.
That was `W-20260921-A37`.

**What the registry actually is**, measured 2026-09-22 with three live sessions:

| Thing            | Where                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------- |
| the address book | `<config_dir>/sessions/`, one `<pid>.json` + one `<pid>.<hex>.key` per LIVE session       |
| the phone line   | `messagingSocketPath`, `/tmp/cc-socks/<pid>.sock` -- **global**, not under any config dir |
| the key          | **per session**, not per config dir: two live `~/.claude` sessions carry different tokens |
| the config dir   | named in **no field at all**                                                              |

**So only the address book was split.** The transport already spanned profiles. That is
why the fix is one symlink rather than a message-relay tool.

### What `pj` does now

On a REAL launch (never on `--dry-run`), a profile whose `config_dir` differs from
`~/.claude` gets:

```
<config_dir>/sessions  ->  ~/.claude/sessions
```

Both sides then appear in each other's `ListAgents` and can `SendMessage` **by name**, in
both directions, with no per-session work anywhere. `pj-health`'s `profile-registry` row
says whether the link is actually there.

### Why a directory link and not per-session links

The brief for this work asked for per-session symlinks. They cannot work, and finding that
out was the measurement that decided the design:

| Shape                                       | Result                                                      |
| ------------------------------------------- | ----------------------------------------------------------- |
| symlinked **files** into the other registry | **NOT LISTED.** The reader does not follow a symlinked file |
| **copies** of the same two files            | **LISTED**, and messaging worked both ways                  |
| the whole **directory** symlinked           | **LISTED**, both ways, by name, nothing per-session         |

The copy and the symlink were the identical registry pair, in the same folder, one minute
apart, with nothing else changed. Copies work but have two faults a shared directory does
not: the live session rewrites `status` and `updatedAt` in **its own** file and the copy
keeps the old values, and the copy **outlives the peer** -- after the session exited, its
copy sat there naming a dead pid until Claude Code's own sweep reaped it. With a shared
directory the live session writes and removes its own file, so there is nothing to go
stale and nothing to sweep.

### What the reader will and will not accept

Measured, because each of these fails silently:

- the file name **must** be `<pid>.json`. Identical content under another name is never
  listed. Control: the same content under a pid name was.
- the content is **validated against the live process**. An entry whose `procStart` does
  not match the real process start time is skipped without a word; correcting only that
  field made it appear.
- a **dangling symlink** in the folder is ignored, does not crash anything, and is removed
  by Claude Code within about a minute.
- an entry naming a **dead pid** is not listed, and is then reaped.

### A reply needs no bridge at all

Worth knowing before reaching for any of this. A session that RECEIVES a cross-session
message can always answer it, across config dirs, with nothing shared: the `from=` address
is the raw socket path and the socket is global. Measured -- the by-NAME send was refused
(`no agent named ... is reachable`) and the same reply to `uds:/tmp/cc-socks/<pid>.sock`
went straight through. **Only INITIATING by name needs the registry.**

### The cost, stated plainly

One shared address book is two-way by construction. A throwaway `c2` session can see, and
message by name, **every** `~/.claude` session that is open, including LifeOS `c-legacy`
ones. And `ListAgents` shows name, kind, status and age and **no cwd and no config dir**,
so nothing in the listing marks a peer as a scratch one.

That is why `pj` also passes `--name <profile>-<cwd>-<suffix>` for a non-default profile:
a scratch session is then called `scratch-f5c-probe-a1b2` rather than
`fifty-shades-of-dotfiles-23`, which is what it was called in the proof run and is
indistinguishable from a real session. A session launched under a forked config dir by
some other route is still indistinguishable; that is `W-20260922-A01`.

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

### The folder-trust dialog, and the one carve-out

A fresh config dir refuses a workspace until a human accepts the trust dialog, and the
standing rule is that a session stops and signals rather than answering a security prompt.
**`D-20260922-A01` carves out exactly one case**, ruled by Gavin 2026-09-22: a session may
accept the folder-trust dialog itself, via Herdr, for **c2 worktrees and for any folder
opened under the scratch config dir**. Every other trust or security dialog still stops
and waits for him.

The carve-out is narrow for a reason. A c2 worktree is a checkout of a repo he already
trusts under the default config dir, and `~/.claude-scratch` is the disposable profile, so
accepting there grants nothing already withheld elsewhere. It does **not** extend to the
default config dir, to a folder he has never opened, or to any other prompt.

How it works: `c2 start` ends in `exec pj`, which replaces the process, so the watcher is
forked **before** the exec and talks to the pane `c2` is itself running in. The decision
is a pure function, `trust_keys_for`, so it is tested without a pane, a server or a live
dialog. It sends nothing unless it sees the cursor marker -- the dialog's WORDS alone, as
they appear in a transcript or in this document, are not enough -- and it tries **once**:
a dialog still up afterwards is said out loud rather than hammered with Enter.

### The peer name, and finding the session id

`c2 start` prints the peer NAME it is about to give the session, and the exact
`SendMessage` line to use, **before** the launch. It could not print the session id there,
because the id does not exist until Claude Code has started and the exec leaves nobody to
read it back.

Since F5d it does not BUILD that name. It **asks `pj`**, with the same cwd and profile the
launch will use (`pj --dry-run-env`, which touches nothing), and prints the answer. Until
then c2 kept its own copy of pj's formula, which is one rule written twice and free to
drift in silence; `c2 --selftest` arm 13b is the arm that would catch it if it ever did.

`c2 list` carries the live half instead -- for each scratch worktree it reads the registry
and prints the running session's name, session id and pid, or `no session running`. That
is read fresh each time rather than remembered, so a session that has since exited simply
stops being shown.

## Names: sessions, panes and tabs

One convention, and it is readable cold. Ruled by Gavin at the F5d gate, 2026-09-22.

| Thing | Shape | Example | Set by |
| --- | --- | --- | --- |
| session | `<repo-or-alias>-<role>[-<topic>]` | `fifty-shades-of-dotfiles-main` | `pj`, via `CLAUDE_CODE_SESSION_NAME` |
| session, scratch | the same, role = the profile | `fifty-shades-of-dotfiles-scratch-f5d` | `pj`, launched by `c2` |
| session, a stage's control pane | the same, chosen by the session | `fifty-shades-of-dotfiles-f5d-control` | the session, exported before `pj` |
| Herdr **workspace** | left alone | `fifty-shades-of-dotfiles` (auto) | Herdr itself |
| Herdr **tab** | the purpose | `main`, `scratch/f5d`, `f5d-control` | the session that opens it |
| Herdr **pane** | the session's own name | `fifty-shades-of-dotfiles-scratch-f5d` | `pj`, at launch |

`role` is `main` for the default profile and the profile's own name otherwise. `topic` is
the working directory's basename when it is not the repo root, which is the `c2` worktree
case and nothing else. The repo part is the repo **basename**; a repo that wants a shorter
one declares `session-alias: <word>` in its own `.claude/pj-homes`. There is no hidden
alias table, so a name is always explainable from two files.

### Why the name travels in the environment

`CLAUDE_CODE_SESSION_NAME` sets the display name exactly as `-n/--name` does. Measured
2026-09-22 against Claude Code 2.1.278, with controls: the variable is honoured, and the
registry then records **no `nameSource` field at all**, where `--name` records `user` and
no name at all records `derived`. That absence is how you tell them apart.

**That is the whole reason the default profile can have a name.** A `--name` entry would
have added one to argv and broken the byte-identical guarantee that `pj --selftest` arm 12
holds. An environment variable adds nothing to argv, so the guarantee is untouched and the
default session stops being anonymous in a shared registry.

A `--name` typed after `pj` still wins: the flag beats the variable (measured). And a name
already in the environment is left alone, which is how a stage names a control pane.

### Inherited is not chosen

`pj` exports the name into the session it launches, so everything that session starts --
a nested `pj`, a `c2 start` -- inherits it. Left at that, a scratch session launched from
inside a `pj` session would take its **parent's** name and collide with it.

So `pj` exports a second variable, `PJ_SESSION_NAME`, holding the same string:

| In the environment | `pj` concludes | What it does |
| --- | --- | --- |
| both set, and **equal** | inherited from a parent `pj` | **recomputes** the name for this launch |
| only `CLAUDE_CODE_SESSION_NAME` | a human or a stage chose it | **keeps** it |
| neither | a fresh launch | computes one |

A stage that wants to name a control pane exports `CLAUDE_CODE_SESSION_NAME` and not the
marker, which is what "export it before `pj`" already meant. `c2` reads `PJ_SESSION_NAME`
when it asks `pj` for the name, because that one is emitted on every launch while
`CLAUDE_CODE_SESSION_NAME` is emitted only when `pj` computed the name itself.

### What happens on a collision

Claude Code renames the loser and **keeps the prefix**. Measured 2026-09-22: two
interactive sessions launched as `f5d-dup` ended up `f5d-dup` and `f5d-dup-twinkly-lake`,
the second recording `nameSource: collision`, and `ListAgents` listed both, distinctly.

So there is no random suffix any more. F5c added one because a comment in `pj` said a
collision would lose the prefix; that sentence was never measured and is false.

**One hole, left open deliberately.** That check runs only for `entrypoint: cli`, a real
terminal launch. A headless `claude -p` is `entrypoint: sdk-cli` and does not check at all:
measured, a `-p` probe took the name of a **live** interactive session and both kept it.
Note that `kind` says `interactive` for both, so `kind` is not the field to read.
Probes only; no real `pj` or `c2` session is affected.

**And the name is cut at 200 characters -- by `pj`, on purpose.** Claude Code truncates
silently at 200 (measured by bisection: 200 verbatim, 201 to 200, `nameSource` still
`user`, exit 0, no warning). Nothing here comes close, but a truncation you did not ask for
is worth making visible.

### Why the pane, and not the workspace or the tab

**`herdr agent list` does not carry the session name.** It carries `terminal_title`, and
Claude Code overwrites that with the current task summary and then, after exit, with the
shell prompt. So a fresh idle session shows its name there and a working one does not --
a field that is right only while nothing is happening cannot distinguish anything.

The pane **label** is stable, survives the process exiting, and can be cleared. So `pj`
sets it at launch, and `ListAgents` and the Herdr sidebar read the same string.

- **Workspace: never touched.** Its label already auto-tracks the live cwd, and
  `herdr workspace rename` writes a permanent override with no supported way back
  (upstream herdr#3252, closed `not_planned`). Renaming it would buy a string it already
  shows and cost the tracking for ever.
- **Tab: the session's job, not the launcher's.** One tab can hold several panes doing
  different things, so a launcher naming it would clobber whatever else is in there.
- **Pane: one pane, one session.** `pane rename` takes any characters and has `--clear`.

**The cost, stated rather than hidden:** the label outlives the session. A pane whose
Claude has exited keeps its label until the next `pj` launch overwrites it or someone runs
`herdr pane rename <id> --clear`. `pj` cannot clear it on the way out, because it `exec`s
and leaves nobody behind to do it.

## `direnv` in a `c2` worktree

`c2 start` runs `direnv allow` in the new worktree **only** when its `.envrc` is
byte-identical to the main repo's already-allowed one. Anything else prints the diff and
**stops the launch**. Ruled by Gavin at the F5d gate: a byte-identical file is the same
trust he has already given, moved to a new path.

**Why it needs doing at all.** Measured live 2026-09-22, with a control in the same
command: the worktree's `.envrc` is byte-identical to the main repo's -- it is a tracked
file, so git simply checks the same blob out -- and direnv blocks it anyway. Main repo
`Found RC allowed 0`, worktree `Found RC allowed 1`, same second.

The reason is the allow token's name. It is a file under `~/.local/share/direnv/allow`
called `sha256(<absolute path> + "\n" + <file content>)` -- reproduced exactly against this
repo's live token, with a different-path control that produced a different digest. **The
path is inside the hash**, so identical content at a new path is a file direnv has never
been shown. Correct of direnv, and merely inconvenient here.

At `c2 start` the two are always identical, so in practice this is silent. It earns its
keep later, if a scratch branch edits `.envrc`: what runs on every `cd` into that folder is
then something you have not read, and that is worth stopping for.

Every other case is a note and never a stop, because none of them is a change `c2` should
make on its own: no `.envrc` at all, no `.envrc` in the main repo to compare with, no
`direnv` installed, or a main-repo `.envrc` that is not itself allowed.

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

## The five plugin dirs, and where a Claude Mod may NOT live

`plugins:` names dirs under `~/.claude`, one `--plugin-dir` each. Measured 2026-09-22
(F8a), because the question "are they writable by a session standing in this repo?" had
been assumed rather than checked, and the assumption was wrong in the safe direction.

**All five are real directories under `~/.claude`, and a sandboxed Bash write into every
one of them is refused.** Both controls fired in the same command: a write to `.` (the
cwd) succeeded, and a write to `~/.claude/settings.json.f8a` was refused, so the denials
are the sandbox rather than a broken probe.

| dir | sandboxed write | symlinked top-level entries |
| --- | --- | --- |
| `~/.claude/skills/herdr` | DENIED | **3 of 3** |
| `~/.claude/skills/AgentRelay` | DENIED | 0 of 6 |
| `~/.claude/skills/ISA` | DENIED | 0 of 2 |
| `~/.claude/pj` | DENIED | 0 of 1 |
| `~/.claude/pj-voice` | DENIED | 0 of 1 |

**And stow links FILES, not directories**, so a file newly added on the repo side does not
appear under `~/` at all until a restow. That is the second reason the dirs are hard to
tamper with from a session.

**The one hole is herdr's three entries.** `SKILL.md`, `UPSTREAM.md` and
`UPSTREAM.version` are symlinks resolving into the dotfiles repo, which is the cwd, and
the cwd is writable. Proven and reverted byte-exact: appending a marker to the repo-side
`UPSTREAM.version` made it visible through the `~/` path the launcher loads.

**So, ruled at the F8a gate (D-20260922-A06): nothing moves, and a hooks module never
lives under `~/.claude/skills/herdr`.** The other four dirs are protected as they stand.

This is not a claim that the estate is tamper-proof. A user-tier mod is outermost only
because it was *listed* first, so anything that can edit this launcher can reorder it;
there is no protected seat without managed settings. It is the narrow rule that follows
from where the one measured hole actually is.
