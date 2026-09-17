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

## D-20260917-09 -- The SSH key stays, keychain-backed, scoped to one Host block

topic: ssh key passphrase keychain AddKeysToAgent UseKeychain claude launch agent expiry branch liveness ci-watch unattended
decided: 2026-09-17
status: standing
holds-in: ~/.claude/MEMORY/WORK/ssh-key-and-branch-liveness/DECISION.md

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
holds-in: ~/.claude/MEMORY/WORK/ci-watch-observability/APP-MIGRATION-DECISION.md

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
