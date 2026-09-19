# Decisions register

**What this is.** One block per settled ruling, so "has this already been decided?"
is one command instead of a reading exercise. Query it with `decided <words>`.

**Why it exists.** 2026-09-17: a session spent an evening re-deriving a ruling that
was already written down in `docs/GITHUB_CREDENTIAL_LANES.md` section 4, because the
doc it was standing in did not point at it. The rule "check the project's own record
first" already existed and did not fire. Rules that keep being broken get replaced by
tooling here -- that is what `census` and `peek` are -- so decisions get a register,
the way risks and upgrades already have one.

**The discipline that keeps it fed.** A decision recorded only in a commit message is
invisible: commit messages are not greppable by topic and nobody reads them before
proposing. So the decision goes in a document, the document gets a block here, and the
commit points at the document. Commit `69de6c9` announced a ruling no document held,
and that is exactly how the contradiction happened.

**Fields.** `topic` is the grep surface, so overload it with the words someone would
actually type. `holds-in` is the document that carries the reasoning; this file is an
index, never the argument. `status` is `standing`, `deferred`, or `superseded`.

---

## D-20260917-01 -- Fix the consumers, not the launcher

topic: credentials gh GH_TOKEN herdr spawn alias _claude_launch launcher wrapper token escalation keyring
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 4
supersedes: commit 69de6c9, whose message says the alias route was picked

A tool that fetches its own credential is correct no matter who spawned it. Every
launcher-side fix only covers the launchers it knows about, and there are at least
eight paths to a bare `claude` on this machine.

## D-20260917-02 -- No shell-layer fix for the spawn-path credential gap

topic: alias claude function PATH shim zshrc spawn herdr credential snapshot skip-permissions
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 8

An alias, a `claude()` function and a PATH shim were all costed and dropped. Measured
reasons, not taste: an alias fires inside every Claude Code Bash call because the shell
snapshot is sourced there (310 aliases live); mirroring `c` would hand every spawned
agent `--dangerously-skip-permissions`; `_claude_launch` blocks at the ssh passphrase in
a pty; and zsh bakes an alias into every function defined after it, permanently, while
the source file still reads normally.

## D-20260917-03 -- Replace the keyring token BEFORE unexporting GH_TOKEN

topic: ordering migration keyring gho token unexport GH_TOKEN sequence gh fallback
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 8

The two steps are not interchangeable. Unexporting first makes `gh` fall through to its
keyring by design, turning one launcher gap into an estate-wide default: the banned
"retry with GH_TOKEN unset" escalation arriving as a migration step.

## D-20260917-04 -- Keyring token REPLACED with the read-only PAT, not deleted

topic: keyring gho token delete replace swap logout with-token public-read PAT broad repo scope fallback
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md sections 7, 8 and 9

EXECUTED 2026-09-17 evening, on Gavin's pick of option A from four. The broad `gho_`
token was REPLACED with the narrow read-only PAT rather than deleted. Replacing beats
deleting for a reason the earlier write-ups missed: the fallback and the intended
credential then become the SAME token, so a herdr-spawned agent has identical authority
to a `_claude_launch` one and the spawn gap stops being a privilege difference at all.
Deleting merely makes the gap loud; replacing makes it harmless.

Measured after the swap, each with a control in the same command: private file contents
403, writes 403, public reads fine, `~/.gitconfig` byte-identical, `hosts.yml`
byte-identical with `git_protocol: ssh` intact, and both git lanes (21 ssh origins, 44
App-flipped) still resolving real refs. Logging out stays available as the stricter
endpoint once LifeOS's consumers are done.

The old `gho_` token was REVOKED by Gavin at github.com/settings/applications the same
evening, so the grant is dead on every machine, not merely unplugged from this one.
Re-verified afterwards with controls: gh authenticates, both git lanes resolve, nothing
on this machine depended on it.

## D-20260917-05 -- A guard that anchors a command to start-of-line is not a guard

topic: hook guard bypass regex env sudo absolute path prefix anchor enforce-gh-ssh-only shell function heredoc false positive
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/.claude/hooks/enforce-gh-ssh-only.sh header

`enforce-gh-ssh-only.sh` anchored the binary name to start-of-string or a `[;&|]`
separator, so an `env` prefix, an absolute path, a `sudo` prefix and a leading variable
assignment all walked past it while the bare form blocked correctly as the positive
control. Found by accident: the authorised keyring swap ran behind an `env` prefix and
was never logged.

That prefix defeats the interactive shell wrapper too, because `env` execs the binary
and never consults shell functions. One ordinary word defeated both layers of the same
guard at once.

Widening the anchor then introduced the opposite defect, which is worth as much as the
first: the pattern began matching the command name written as PROSE inside a heredoc,
so documenting the guard was blocked on the first attempt. A guard that blocks people
from documenting it is a guard that gets switched off. Heredoc bodies are now stripped
before matching. Proven with 17 cases: 9 must-block, 8 must-allow, including a heredoc
of prose (allowed) versus a heredoc feeding a real invocation (blocked). The genuinely
undetectable case, a path assembled in a variable, is documented in the hook rather
than pretended away.

## D-20260918-02 -- Open items are scoped per project; every item names its owner

topic: open items scope per project MEMORY WORK drawer shared machine-wide OPEN.md ownership routing
decided: 2026-09-18
status: standing
holds-in: this block until the scoped layout exists; then the scoped index

Gavin's ruling, closing OPEN.md item 2, which had sat costed-but-undecided since
2026-09-15 while a peer session was already building the scoped layout. Open items belong
to their project. Each item must name the project that owns it; a machine-wide index is
derived from the per-project lists by script, never maintained by hand, because a hand
copy drifts the first time someone closes an item.

THE HONEST CAVEAT, recorded so nobody reads this as a bigger win than it is. At the moment
of the ruling the drawer held TWO live items, and one of them was this question. The
original argument for scoping -- "other projects' items will start showing up in every
session" -- describes a pressure that is not currently being felt, because thirteen items
were closed in the preceding two days.

That is an argument FOR doing it now rather than against. Restructuring a drawer holding
two items is nearly free; restructuring one holding twenty is the kind of job that never
gets done and quietly justifies itself forever. The decision is right for the state this
drawer will be in again, not for the state it is in tonight.

Gavin also offered to weigh in on individual items' ownership rather than have it inferred,
so a routing that is not obvious is a question for him, not a guess.

ADDED 2026-09-18 by the ci-watch session, which was asked the same question independently and
gave the same answer. Two points from that pass, folded in here rather than filed as a second
block -- one decision must have one record, or the two drift.

WHY A HOOK RATHER THAN A COMMAND. The rejected alternative was a flat drawer with a `project:`
tag and an `open` command that filters by current repo. It loses on the thing that actually
matters: the mechanism that gets an item IN FRONT of Gavin is a SessionStart hook, not a file.
A list he has to remember to type is a list he will not see, which is the same habituation
failure ci-watch exists to prevent.

RULED OUT EXPLICITLY, so it is not revisited: items living in the project repo as
`.claude/OPEN.md`. fifty-shades-of-dotfiles is PUBLIC, and private open items must never sit
in a repo that can be pushed publicly. Version control is not worth that trade.

AMENDED 2026-09-19, executing D-20260919-03 step 1. The "machine-wide index derived by
script" is `open-items --all`, computed live on every call. The derived `INDEX.md` FILE
is dropped: census over the repo, user settings, hooks and OPERATIONAL_RULES.md found no
reader but the tool that wrote it, and a file regenerated only by hand is exactly the stale
surface D-20260919-01 retired. Same ruling, one fewer thing that can lie.

## D-20260917-09 -- The SSH key stays, keychain-backed, scoped to one Host block

topic: ssh key passphrase keychain AddKeysToAgent UseKeychain claude launch agent expiry branch liveness ci-watch unattended
decided: 2026-09-17
status: standing
holds-in: ssh-key-and-branch-liveness/DECISION.md in this repo's open-items drawer (`open-items --where`; moved 2026-09-19, D-20260919-03)

Option A of four. The key is NOT removed from the launcher; its passphrase moves into the
login keychain, so unattended starts stop blocking and the 12-hour agent expiry stops
mattering, while the read-only token stays narrow and ci-watch keeps branch-liveness.

The scoping is the part to preserve: `AddKeysToAgent yes` and `UseKeychain yes` went into
the `Host git-cc` block in `~/.ssh/config.local`, never into `Host *`, which also governs
proxmox, codebox, mlbox, bl-2, adminmbp and hermes-o. It takes effect because the Include
sits above the global defaults and ssh keeps the FIRST value it obtains per keyword.
Verified: git-cc resolves true, nine other hosts still resolve false.

Unblocks the ci-watch branch-liveness swap, which was waiting on this and nothing else.

## D-20260917-08 -- A relayed instruction NOT to act is safe; a relayed go-ahead is not

topic: peer agent relay authority permission laundering second-hand instruction cross-session consent build create prohibition authorisation
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 10, "Relayed instructions"

A relayed prohibition can be acted on: if the relay is wrong, the worst case is that a
thing does not exist, which costs nothing and is undone by inaction. A relayed
authorisation cannot: the worst case is a structure, push, deletion or grant existing
because a PEER said so. Confirm a go-ahead with your own principal; a "do not" needs no
round trip. Corollary: when relaying, say which direction it is.

Formulated by the peer session in the worktree exchange. Evidence and full reasoning in
the holds-in document.

## D-20260917-07 -- Two sessions share ONE checkout; the pathspec form is a MITIGATION

topic: shared checkout worktree index race git add commit pathspec two sessions concurrent collision staging
decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 10

Gavin's call, from four options. Sessions stay in the one checkout of this repo and both
use `git add <paths> && git commit -F msg -- <paths>` AS ONE SHELL COMMAND. Separate
worktrees were recommended by both sessions and declined.

**It is a mitigation, not a fix, and it must keep being called that.** The failure it
addresses happens in the gap between a single session's own tool calls: on 2026-09-17 a
staging check reported zero foreign files staged, and two calls later a bare `git commit`
swept 7 files a peer had staged in the interval, then pushed them under the wrong message
(eb9880f). No discipline reaches inside that window, which is why a convention here
guards a race rather than removing it. Keeping the add and the commit in ONE tool call
shrinks the window to near zero; it does not close it.

Two consequences worth having written down rather than rediscovered:

- A pathspec commit REFUSES a path git does not yet track, so a NEW file needs the add
  and the commit joined as one command anyway. "Use a pathspec" alone does not cover it,
  and that gap is exactly when someone reaches for a bare commit again.
- zsh does NOT word-split an unquoted variable, so a path list held in a shell variable
  collapses into one nonexistent path. Write the paths out literally, or use an array.

Revisit if a second collision happens. The first one cost a wrong-authored pushed commit
and about forty minutes across two sessions.

## D-20260913-01 -- Lift the sandbox per command for pushes; never allow-list the keychain

topic: sandbox keychain push github app credential helper allow-list standing grant bash
decided: 2026-09-13
status: standing
holds-in: OPERATIONAL_RULES.md, GitHub pushes entry

Both sessions consulted and chose per-command. An allow-list is per path and a keychain
is one file, so it would permanently expose every non-prompting login-keychain item to
every Bash command in every session. A separate App-only keychain was measured as viable
and declined: it trades a visible per-command act for a permanent standing grant.
Revisit only on evidence the per-command route is a real nuisance.

## D-20260909-01 -- Do not re-test cheap or lite Gemini models for research synthesis

topic: gemini flash lite cheap model research synthesis thinking minimal quality bake-off
decided: 2026-09-09
status: standing
holds-in: OPERATIONAL_RULES.md, Vendor-specific rules

Confirmed across three separate tests, not one fluke. Recorded here because Gavin wrote
in the rule itself that he will ask again and will have forgotten. A different, easier
task type is a legitimate reason to revisit; "it is cheap" on its own is not.

## D-20260914-01 -- Git worktrees live inside their own project, never herdr's shared default

topic: worktree hwt herdr branch path shared default project layout
decided: 2026-09-14
status: standing
holds-in: skills/herdr/SKILL.md, Create a worktree

Every worktree goes to `<repo>/.worktree/<branch>` via the `hwt` wrapper. Not
`~/.herdr/worktrees`, and not the sidebar "New worktree" button, which uses that shared
default too. `herdr worktree create` without `--path` silently uses the shared folder.

## D-20260917-06 -- Private shell helpers are named __double_underscore

topic: zsh helper function naming single underscore double underscore snapshot Claude Code filtered completion compdef uv_tool_mode run_onboarding broken helper not found silent wrong answer

decided: 2026-09-17
status: standing
holds-in: fifty-shades-of-dotfiles/docs/ZSH_HELPER_NAMESPACE.md

Claude Code drops every function whose name starts with a SINGLE underscore from the
shell snapshot it sources before each Bash tool call, because that namespace holds
zsh's ~1,500 completion functions. Measured: `^_[^_]` is 1563 in a real interactive
zsh and 0 in a Claude shell, with `^__` at 18 vs 16 as the control. So 54 private
helpers vanished while the 17 public functions calling them survived and failed, and
`uv_tool_mode` / `uv_tool_check_current_project` returned a confident WRONG answer
rather than failing -- the second told you to install a tool already installed and
frozen. 52 helpers renamed to `__name`; single underscore is now reserved for the two
real `compdef` functions. Enforced by `zsh-helper-namespace-check`, whose `--selftest`
proves it can fail and that an empty scan REFUSES rather than reporting clean.

## D-20260918-01 -- ci-watch keeps the fine-grained PAT; the GitHub App is NOT adopted

topic: ci-watch github app github-agent installation token PAT fine-grained credential migration contents read actions read one hour lifetime minting per repo branch liveness

decided: 2026-09-18
status: standing
holds-in: ci-watch-observability/APP-MIGRATION-DECISION.md in this repo's open-items drawer (`open-items --where`; moved 2026-09-19, D-20260919-03)

Asked for on 2026-09-15 after the PAT was found in 12 transcripts, oldest 14 June. Measured
2026-09-18 and declined by Gavin the same day, on four grounds, each with a control.

The motivating leak is closed at source, not by rotation: a PreToolUse hook blocks the three
env-printing probe shapes that wrote it, `__claude_launch` no longer exports GH_TOKEN at all,
and the broad keyring token is replaced and revoked. The App would shorten a fuse that is no
longer lit.

Installing the App on a repo grants it Contents: read -- measured 200 on /branches/master for
the one repo it IS installed on. The PAT deliberately has none. That is option C of
D-20260917-09, already costed there and called "the one to avoid", arriving by another door.
A status line should be the last thing able to read source.

`github-agent-token` cannot mint for a repo you are not standing in: it derives owner/repo
from git's credential stdin or the cwd's origin, and reads the tier from that repo's own
.git/config. Measured from /tmp: rc=1, "could not read this repo's 'origin' remote". ci-watch
is multi-repo and runs from wherever the session is, so adoption needs a new
`--repo owner/name --tier` mode, not a config change. NEXT.md's "mints from any directory:
yes" row is WRONG and is superseded.

The sandbox objection is a wash, not a reason either way. The PAT path is equally dead inside
a sandboxed Bash call (security exit 44, ci-watch reports NONE and fails closed), and it does
not matter, because ci-watch's real execution context is the SessionStart hook, which is not
sandboxed -- proven by a live green render at session start in the same session where the
sandboxed probe failed.

Also settled here so it is not re-derived: the App's 404 on private repos was never a missing
permission. `/installation/repositories` returns total_count 1, and Actions:read answers 200
on that repo. The App is simply not installed on the watched ones.

## D-20260918-03 -- The two gh guards stay deliberately mismatched

topic: gh auth login git-protocol ssh zshrc wrapper PreToolUse hook guard mismatch carve-out verified safe

decided: 2026-09-18
status: standing
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md section 10

The `.zshrc` wrapper ALLOWS `gh auth login --git-protocol ssh`, calling it verified safe; the
PreToolUse hook BLOCKS every form. They disagree, and they stay that way.

Nothing is broken and no gate weakens, which is the whole argument. Tightening the wrapper
would delete a carve-out another author built and tested, on no new evidence. Loosening the
hook would relax a safety catch on evidence covering ONE of the three ways that command can
run: the token-on-stdin form is measured harmless, while the interactive and browser flows
are NOT measured and cannot be from inside a Claude session -- they need Gavin at a terminal.

The general shape, and the reason this is written down rather than left as a nagging
inconsistency: two guards disagreeing is not itself a defect. Reconciling them by moving
EITHER one costs something real, and an unmeasured case is not evidence for relaxing a gate.
Revisit only if someone measures the interactive and browser flows.

## D-20260919-01 -- The CLAUDE.md OPEN WORK banner is retired; `open-items` replaces it

topic: open work banner CLAUDE.md OPEN.md clearing condition wallpaper habituation session start hook open-items index per-project drawer stale banner

decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/CLAUDE.md line 3

The banner opened 2026-09-15 carried its own clearing condition: delete it only when
`OPEN.md` has no items left, and not before, explicitly "do not soften it". It was replaced
on 2026-09-19 by the one-liner `Open items: run open-items --all` while two items were still
open (W-20260918-01, W-20260918-02). Gavin ruled the override directly, having been shown the
conflict first.

Why the condition no longer binds. It was written to stop open work going unseen, and at that
time a static banner in an always-loaded file was the only surface that could do it. The
`session-open-items` SessionStart hook now prints the live per-project list at the top of every
session, derived from the per-project files by `open-items --index` rather than maintained by
hand (D-20260918-02). So the banner had become the WEAKER of two surfaces and the one that
could go stale -- and it had: it advertised eight items, named the GH_TOKEN leak cause as the
highest-value open work when D-20260918-01 had already closed it at source, and called branch
liveness "blocked on the SSH decision" after `a6e734b` had shipped it.

The general shape, which is why this is recorded rather than left as a quiet deletion: a
clearing condition protects a mechanism, not a file. When something better takes over the job,
honouring the condition literally preserves the exact failure it was written to prevent --
a stale banner that everyone has learned to read past.

## D-20260919-02 -- Project memory lives in the harness dir, not in lifeos-private SCOPES

topic: memory home harness projects dir dot-claude lifeos-private SCOPES scopes.json pj c launcher auto-memory separation resolver symlink
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PROJECT_LIFEOS_BOUNDARY.md section D1
supersedes: steps b-e of lifeos-private/MEMORY/WORK/memory-store-separation/FINDINGS.md

`~/.claude/projects/<encoded-repo-path>/memory/` is the single source for this project's
notes. Measured 2026-09-19: a `pj` session has auto-memory ON and reads and writes it
natively; a `c` session never loads it. The separation already exists at the launcher
level, so moving notes into LifeOS's private store would add the coupling being removed.
The SCOPES registry has a writer and no reader, and the LoadContext leak the earlier plan
was built on does not occur today.

## D-20260919-03 -- The unversioned work drawer moves under the harness memory dir

topic: open items drawer MEMORY WORK unversioned gitignored move harness memory WORK folder open-items OPEN_ITEMS_DIR per repo enumerate
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PROJECT_LIFEOS_BOUNDARY.md section D2

Dotfiles-owned folders in `~/.claude/MEMORY/WORK/` move to a `WORK/` folder inside this
repo's harness memory dir, which is versioned in `dot-claude` and already a path LifeOS's
harvester recognises. The one LifeOS-owned decision file moves to lifeos-private.
`open-items` must resolve per repo BEFORE the move; today it refuses loudly (exit 2) on a
missing drawer, which is the safe failure. Public files keep saying "run open-items" with
no path. NOT EXECUTED at the time of recording.

## D-20260919-04 -- Delete the dotfiles copies in lifeos-private, keep the learning

topic: lifeos-private residue SCOPES dotfiles copy MEMORY WORK ci-watch-observability github-credential-lanes incidents upgrades delete keep hash check
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PROJECT_LIFEOS_BOUNDARY.md section D3

After D-20260919-03 lands and a hash comparison shows nothing unique remains (AMENDED
2026-09-19 before execution: measured, 3 of the SCOPES copy's 9 content hashes are unique,
all older snapshots of live files; the gate is "every hash is shared OR classified
superseded", never a bare zero): delete
`SCOPES/dotfiles/` and the dotfiles folders under `MEMORY/WORK/` in lifeos-private.
Keep the LEARNING incidents, the UPGRADES records and the one citation in
`OPERATIONAL_RULES.md`; those are LifeOS's own lessons, and deleting evidence to tidy a
boundary is the wrong trade. Gated on the hash check, never on a date. NOT EXECUTED.

## D-20260919-05 -- pj keeps appending the whole OPERATIONAL_RULES.md; no split

topic: pj launcher OPERATIONAL_RULES append-system-prompt-file project rules split drift doctrine global lifeos-private
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PROJECT_LIFEOS_BOUNDARY.md section D4

Measured 2026-09-19: the file is global doctrine with one citation of this repo. A project
copy would be a second source of the same rules, which drifts. Accepted cost: `pj` depends
on lifeos-private existing at that path, and LifeOS-only sections cost tokens in `pj`.
Reversible later without touching D-20260919-02 to -04.

## D-20260919-07 -- CLAUDE_MEMORY_STORES stays off; keep MEMORY.md thin by hand

topic: memory index cap MEMORY.md 24.4KB 25000 bytes 200 lines CLAUDE_MEMORY_STORES promptIndexMaxBytes memory stores sync watcher binary patch codesign compact prune
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/MEMORY_INDEX_CAP.md

Re-measured against binary 2.1.278 on 2026-09-19 (parked since 2026-06-23 against
2.1.186; every stable string survived, negative control clean). The variable does raise
a store index's cap and drops the line cap -- and the same code path starts a sync
subsystem (`personal_memory_sync_watcher_start`, `memory_store_pull_ms`, "backend
sweep", `/v1/code/local/memory/mounts`) and silently disables org memory. Whether a
purely local scope:"user" store reaches that backend is NOT established by reading
strings, and guessing wrong sends personal memory off the machine. It would also be a
migration rather than a config change, since promptIndexMaxBytes is store-scoped and
the per-project MEMORY.md stays capped either way. Binary patching is rejected
separately: resets every update, needs re-signing, breaks silently on a rename.

Two corrections the doc carries: individual topic files now DO have a recall surface
limit, so "push detail into topic files" needs a size check; and compaction shortens
hooks rather than dropping entries, because several entries exist only to stop a past
rejection being re-proposed.

Revisit only when the index hits 100% of a cap, or Anthropic documents local-store sync.

## D-20260919-06 -- pnpm 12 is live; globalShims off; floor 12.3.2

topic: pnpm 12 major upgrade globalShims nvm node shim PNPM_MIN_VERSION floor 12.3.2 12.3.0 trap pnpm_update deferral lifted
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7

Supersedes the 2026-09-04 deferral (11.25.0 by choice). Gavin took 12.4.1 by hand via
`pnpm_update`. `globalShims: false` is set in the stowed config so nvm keeps `node`; the
SSH url rewrites were already in place. Floor is 12.3.2 in install.sh and .zsh_onboarding
(12.3.0 breaks global node/npm/yarn; 12.3.2 fixes the npm wrapper). Never land on 12.3.0.

## D-20260919-08 -- pnpm: supportedArchitectures pinned to `current`; python and cargo ecosystems off

topic: pnpm 12 supportedArchitectures current darwin-arm64 platform list os cpu libc optional dependencies python.enabled cargo.enabled ecosystem interpreter download config.yaml stow linux wsl
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7.1

Approved 2026-09-19 with D-20260919-09 to -11 in one round; measured and landed 2026-09-20
on pnpm 12.4.1. The one stowed `config.yaml` serves macOS, Linux and WSL, so the platform
pin is the literal `current` on every axis (object form: os, cpu, libc), never a hard-coded
`darwin-arm64`. The 12.5.0 platform-list form is REJECTED by the 12.4.1 parser on every
pnpm command ("load configuration"), so the object form stays until the floor passes 12.5.
`python.enabled` and `cargo.enabled` are pinned false: uv owns Python here and pnpm must not
start fetching interpreters on a default flip. Arms used, since `pnpm config get` reads all
three back as undefined: typed rejection (`enabled: banana` and `os: banana` fail parse,
an unknown key with the same bad value passes) and, for supportedArchitectures, a scratch
install of esbuild that landed only `@esbuild/linux-x64` under an os:[linux] pin and only
`@esbuild/darwin-arm64` under `current`. Existing projects see no change: `current` is the
default value.

## D-20260919-09 -- pnpm: prune stale exclusions, keep build cache local, enforce engines

topic: pnpm 12 trustPolicyExcludePrune audit.ignorePrune audit ignore prune sideEffectsCache read write remote pnpr engineStrict engines ERR_PNPM_UNSUPPORTED_ENGINE optionalDependencies install fails config.yaml
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7.1

Four policy knobs in the stowed config.yaml, all measured on 12.4.1 on 2026-09-20 and all
four read back through `pnpm config get`. `trustPolicyExcludePrune: true` (12.4.0) drops
`trustPolicyExclude` name@version entries that a rewritten lockfile no longer contains, so a
hand-approved exception dies with the version it was approved for. `audit.ignorePrune: true`
(12.0) does the same to `audit.ignore` on `pnpm audit --fix`. `sideEffectsCache` is spelled
out as read true, write true, remote null: `remote` is the pnpr server object that restores
build output from other machines, and it stays unset; `remote: false` is REJECTED by the
parser, `null` accepted. `engineStrict: true` makes `pnpm install` REFUSE a dependency whose
engines exclude the running Node instead of warning (behaviour arm: a file: dep with
engines.node "<1" installed with the key unset and failed ERR_PNPM_UNSUPPORTED_ENGINE with it
set). Accepted cost: an existing project can start failing to install after Node moves past a
dependency's upper bound; the fix is the Node version, or `engineStrict: false` in that
project's pnpm-workspace.yaml. Note `--config.engineStrict=true` on the command line did
nothing in the probe; `--engine-strict` and the file key both work.

## D-20260919-10 -- pnpm_update carries a version deny list beside the floor

topic: pnpm_update deny list denylist refuse version 12.3.0 PNPM_DENY_VERSIONS floor PNPM_MIN_VERSION self-update eligible zsh_node_functions selftest
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7.1

A floor says "not below"; it cannot say "never this one". 12.3.0 broke global node/npm/yarn
after self-update and was fixed in 12.3.1, and nothing in `pnpm_update` would have stopped a
box on 12.2.x taking it while it was the latest eligible. `PNPM_DENY_VERSIONS` in
`home/.zsh_node_functions` holds "version|reason" entries, starting with 12.3.0, consulted at
both places the function can land on a version: before the eligible-version download (refuse,
print the reason, exit 1, no self-update) and after the blind fallback self-update that runs
when the eligible version is unknown (the target cannot be checked beforehand, so the landed
version is checked and a roll-back command printed). `zsh-node-functions-selftest` sources
the real file with stubbed network and pnpm and drives denied, allowed, empty-list and
fallback arms. The floor stays where it is; the deny list is not a second floor.

## D-20260919-11 -- Welcome banner warns when pnpm's bin precedes nvm's on PATH

topic: zsh_welcome PATH order nvm bin Library/pnpm/bin PNPM_HOME globalShims node owner banner warning exception-based silent selftest
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7.1

`globalShims: false` (D-20260919-06) keeps `node` with nvm only while nvm's bin precedes
`$PNPM_HOME/bin` on PATH (measured 2026-09-19: entry 1 versus entry 22 in a login shell).
Nothing watched that order. `__welcome_pnpm_path_check` in `home/.zsh_welcome` runs beside
the nvm block and is exception-based: silent when nvm's bin comes first, one red line when
`$PNPM_HOME/bin` precedes it, one red line when no nvm bin is on PATH at all. No green "PATH
ok" line, because a passive identical alert habituates. `zsh-welcome-selftest` extracts the
real function from the file and drives all three arms with fixture PATH strings.

## D-20260920-01 -- pnpm_update asks the registry every run; the binary guard knows pnpm 12 package names

topic: pnpm_update cache TTL PNPM_CHECK_TTL_DAYS stale dist-tag 12.4.2 security patch hidden __pnpm_platform_pkg @pnpm/exe.darwin-arm64 @pnpm/macos-arm64 binary-less guard fails open v12 naming selftest
decided: 2026-09-20
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PNPM_SETUP_GUIDE.md section 7.2

Two blind spots found while taking the 12.4.2 security patch, both measured. (1) The
version cache is trusted for PNPM_CHECK_TTL_DAYS (7). It was written on 2026-09-15 hours
before 12.4.2 was published, so `pnpm_update` answered "already latest" twice and never asked
the registry; a security patch can hide for a week. Fix: every `pnpm_update` run fetches the
registry dist-tag (one 5-second call) and, when it differs from the cached raw, refreshes the
cache in the FOREGROUND before choosing a target. The banner keeps the cheap cached path.
(2) `__pnpm_platform_pkg` returned the pnpm 11 artifact name (`@pnpm/macos-arm64`); pnpm 12
ships `@pnpm/exe.<os>-<arch>[-musl]`. The lookup 404'd, `__pnpm_version_has_binary` answered
"unknown" and the 11.12-class binary-less guard failed OPEN on every v12 update. Fix: the
helper takes the target version and picks the naming by major. Both arms are in
`zsh-node-functions-selftest`. Fail-open on "unknown" stays: offline must not block.
