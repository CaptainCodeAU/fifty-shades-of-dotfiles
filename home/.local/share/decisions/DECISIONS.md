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

## D-20260917-04 -- Keyring token replacement: authorised in principle, deferred

topic: keyring gho token delete replace gh auth logout public-read PAT broad repo scope
decided: 2026-09-17
status: deferred
holds-in: fifty-shades-of-dotfiles/docs/GITHUB_CREDENTIAL_LANES.md sections 7 and 8

Gavin's call: write up first, replace next session. Sized but not executed. The cost is
read-only browsing across 30 third-party clones and 2 plugin marketplaces, which
`github-agent-token pat public-read` already serves; 18 local-only repos need no
credential and 44 flipped repos mint their own. Section 7 item 1 still stands: "all
consumers fixed" is not implicit permission.

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
