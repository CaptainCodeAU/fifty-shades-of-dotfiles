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
