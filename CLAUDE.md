Default branch is `master`.

## Python

Use `uv run python3` instead of calling `python3` directly. (A shell wrapper intercepts bare `python`/`python3` and version-specific calls like `py313`/`py312` and redirects to `uv run` — but invoke `uv run` directly rather than relying on the wrapper, since non-interactive Bash-tool shells skip `.zshrc` and the wrapper is absent there.)
For standalone scripts needing third-party libs, use PEP 723 inline metadata (`# /// script` block) — `uv run` resolves it automatically.
Package management is `uv`, not pip/pipx: use `uv add` / `uv remove` (not `pip install` / `pip uninstall`), and `uv tool` (not `pipx`). The same wrapper-absence caveat applies — in the Bash tool, `pip install` hits real pip, so call `uv` directly.

## Node / JS package manager

Never use `npm` or `yarn`. Use `pnpm` (or `bun`). Pick by lockfile:

- `pnpm-lock.yaml` present → use pnpm.
- `bun.lockb` / `bun.lock` present → use bun.
- No lockfile → default to pnpm.
- Only `package-lock.json` or `yarn.lock` present → disregard them, use pnpm anyway (do not run npm/yarn to honor them).
  For one-off package execution prefer `pnpm dlx` over `npx`.

## Source files — encoding

Emit only ASCII punctuation in source code: straight quotes (`"` `'`), straight apostrophes, and hyphen-minus (`-`). Never write Unicode smart quotes (`“ ” ‘ ’`), en/em dashes (`– —`), or other Unicode punctuation into code files — they pass type-checks but break the build at transform time (the JS/TS build rejects them), and hunting them down afterward wastes a session. Unicode is fine in comments, docs, and string literals meant for display; never in identifiers, keys, or code tokens.

## Verifying: a COUNT or an ABSENCE needs a positive arm

**Any check whose answer is a count or an absence must be paired with something
you KNOW is present, run in the same breath.** Those are exactly the two answers
that look identical when the check never actually ran. A check returning a real
VALUE usually fails loudly on its own; a check returning `0`, "none", or the
same number in every arm cannot distinguish "the mechanism works" from "the test
did not happen". Before trusting one, ask: *what would this print if the thing
never ran at all?* If the answer is "the same", it is not a check.

Three traps already in this file are that one rule written out three times, not
three separate lessons:

- [`census`](home/.claude/tools/census.py) refuses to report anything until its
  `--control` token hits first (Shell, below).
- `git config --get-all credential.https://github.com.helper` prints the helper
  even when the helper is broken, so only a real credential fill detects it
  (Git & GitHub auth, below).
- `stow -n` prints nothing and exits 0 at default verbosity, so an empty plan
  and a real plan look the same; hence `-v2` on every dry run (Sandbox, below).

**A tool REFUSING to answer is not the tool answering "no".** A refusal reads
like a finding, exactly the way a zero does, and it is the same failure wearing
different clothes. Two from 2026-09-13:

- `git ls-files --error-unmatch <path>` on a path that crosses a symlink returns
  `fatal: pathspec ... is beyond a symbolic link`. That means "this repo does
  not follow the link", NOT "the file is untracked". Read as the latter, it
  produced a confident report that a doctrine file had no version control, when
  it was tracked in a different repo the whole time. One `readlink -f` would
  have shown the real path.
- `git check-ignore -v <path>` exits **0 on a NEGATION match too**, printing
  `!path`. So its exit code cannot tell you whether a file is ignored or
  explicitly allowlisted. `git add --dry-run` answers that directly, and gives
  both arms cheaply: an admitted file adds, an unadmitted sibling is refused by
  name.

Measured 2026-09-13: eight errors across two sessions in one evening, every one
this shape. An invocation count that read `2` on a working helper AND on one
that died instantly. A cache-containment test whose three rows were identical
because the cache was empty the whole time. Two timeout tests invalidated by an
included config silently contributing its own helper. A sandbox negative control
run in a session that was never sandboxed. A wait that never waited. Not one was
caught by re-reading the code; each was caught by running the arm that should
have succeeded.

## Shell

Shell has `NULL_GLOB` + `nonomatch` — use `find -print` (not `ls glob*`) for file existence checks. Caveat: `find -print` exits 0 on an empty match only when the search root EXISTS; pointed at a missing path it still exits non-zero (1 on this BSD `find`). For a path that may not exist, use `test -e`/`test -d` (exits 0 either way, reports via its echo) or append `|| true` — otherwise the non-zero exit cancels batched siblings (see batching paragraph below).
For port listing use the `ports` function (OS-aware: `lsof` on macOS, `ss`/`netstat` on Linux/WSL) rather than calling those tools directly.

Before you state a COUNT or a "none anywhere", corroborate it with [`census`](home/.claude/tools/census.py) — `uv run python3 ~/.claude/tools/census.py --control <a-token-you-KNOW-is-present> PATTERN...` (`--help` for the rest; `--include-ignored` also searches gitignored files, `--ignored-only` searches just those, `--json` for scripts). It refuses to report anything unless the control hits first, always prints the denominator and how the population was drawn, and never truncates — none of which `grep` or `rg` do. Using a grep to LOCATE is fine; using one to CONCLUDE is what keeps going wrong. Deployed machine-globally by stow from `home/.claude/tools/`, so it is present in every project on this box but not on a machine without these dotfiles.

Never start a Bash command with `cd` — the harness hard-rejects any leading `cd` (it tells you to use `git -C <path>`, an absolute path, or `builtin cd`). This is a built-in Claude Code guard, not a repo hook. Treat the rejection as a signal to change the command _shape_ (reach for `git -C`/absolute paths), not to retry the same `cd`-prefixed command. A rejected `cd` exits non-zero, so if it was batched with sibling calls it cancels all of them (see next paragraph) — which reads as a "stuck loop" but is really one repeated mistake.

A non-zero exit from any Bash call cancels the other tool calls batched in the same message (Claude Code aborts parallel siblings on error). Never batch state-changing commands (`git add`/`commit`/`push`, file writes) in the same message as read-only probes — a probe that exits non-zero (e.g. `ls`/`grep`/`cat` on a missing path) silently cancels the mutation, so a commit can vanish with no error you'd notice. Sequence mutations as their own calls, and prefer `find -print` over `ls`/`grep` for existence checks (it exits 0 on an empty match — but only when the search root exists; for a possibly-missing path use `test -e` or append `|| true`, per the Shell-section caveat above).

## Sandbox: `home/.ssh` breaks whole-tree sweeps

The Claude sandbox denies reads under any `.ssh` directory (`**/.ssh` is in its deny list) and this repo has a real one at `home/.ssh`, so **any command that walks all of `home/` hits it**. Two consequences, and the second is the one that matters:

- **Noise.** `rg`, `find` and friends print `Operation not permitted (os error 1)` and continue. Harmless in itself, but it means an empty result is not proof of absence.
- **Partial failure.** A tool that ENUMERATES and then ACTS can die between the two phases. A sandboxed `stow -n -R --no-folding -t ~ home` returned **59 UNLINK and 0 LINK** before aborting on `home/.ssh` — a plan which, taken at face value, tears down every stowed file and restores none: `.gitconfig`, `.p10k.zsh`, `direnvrc`, all the git hooks, everything in `~/.local/bin`. Outside the sandbox the same command returned a correct, symmetric **70 UNLINK / 71 LINK**.

(GNU stow builds its full task list before touching the filesystem, so a real run would most likely have aborted harmlessly at the same point. That was not tested and does not change the rule: the printed plan was wrong, and acting on a wrong plan to find out is not worth it.)

**So for anything that sweeps `home/`: dry-run first, and verify the dry run itself SUCCEEDED** — not merely that it produced output. A truncated plan looks like a plan. If it aborts on `home/.ssh`, re-run with `dangerouslyDisableSandbox: true` and compare, rather than trusting the short version.

### `stow -n` PRINTS NOTHING AT DEFAULT VERBOSITY — always pass `-v2`

The sibling trap, and the more dangerous one, because it has no error message at all. Measured 2026-09-04 with GNU Stow 2.4.1:

```
$ stow -n -R --no-folding -t ~ -d <repo> home        # 57 bytes, exit 0
WARNING: in simulation mode so not modifying filesystem.

$ stow -n -v2 -R --no-folding -t ~ -d <repo> home    # the actual plan
95 UNLINK · 95 LINK (reverts previous action) · 1 LINK (genuinely new)
```

Same command, same moment. The default-verbosity run reports **zero actions and exits 0** while the real plan contains a file that is about to be linked for the first time. A newly added file under `home/` is invisible in exactly the run you would use to check whether it needs stowing.

This is how `~/.claude/tools/enforce-census-selftest` sat unstowed after being committed: the file existed in the repo, the documented `~/.claude/tools/…` invocation did not work, and a default dry run said there was nothing to do. Another project's agent found it by running the documented command and getting "No such file". **An empty plan looks like a plan too** — that is the same sentence as the paragraph above, and both failure modes are silence.

So: **`-v2` on every stow dry run**, and read the three counts. `UNLINK == LINK-that-reverts` means a symmetric restow with nothing new; a `LINK:` line WITHOUT `(reverts previous action)` is the only thing a restow actually adds. After a real run, verify the specific path you expected — `ls -la` the link and run the tool through its `~/` path, not its repo path.

**Adding any file under `home/` is not finished until it is stowed and reached through `~/`.** A repo-path invocation proves nothing about what a fresh session, another project, or another machine can run.

## Editing

Before editing a file, count its tab-indented lines with `awk '/^\t/{n++} END{print n+0}' <file>` — match the file's existing indentation exactly or the Edit tool will fail.

**Do not use `grep -P '\t'` for this.** `-P` is a GNU/PCRE extension that BSD grep does not have. On this Mac it _appears_ to work only because Claude Code shims `grep` to `ugrep` via a shell function; the same command against the real binary fails outright:

```
$ command grep -cP '\t' home/.zshrc
grep: invalid option -- P
```

So any shell without that shim — a plain terminal, a script, a cron job, a non-Claude session, a Linux box whose grep lacks PCRE — silently loses the check, and the Edit tool then fails on indentation you never measured. `awk` is POSIX and behaves identically everywhere.

**No count is quoted here on purpose.** An earlier version of this line recorded "77 tab-indented lines in `home/.zshrc`" as of 2026-08-04; on 2026-09-06 the same command returned **141**, because the file grew. The number was never wrong — it stopped reproducing, which is worse, because a figure that fails to reproduce reads as a broken instrument rather than a moved target. **Run the command; do not trust a number written in a document about a file that changes.** (Verified 2026-09-06 that the two forms still agree with each other, which is the property that actually matters.)

## End-of-stage leak audit

**Never hand-type `git diff --cached | grep …` as an end-of-stage or end-of-session leak check. Run `git-leak-scan --since <ref>`.**

This repo commits constantly, so by the end of a stage **nothing is staged** — a `--cached` audit then scans zero bytes and satisfies its own "must return empty" test. It cannot fail. A scan that quietly checks nothing is worse than no scan, because it looks like a pass. (The broken form is still written in `Plans/i-have-an-approved-kind-horizon.md`, deliberately unpatched: fixing one historical document would leave the pattern free to reappear.)

**Read the exit code, never the text.** `0` clean · `1` a leak is in committed history (scrubbing needs a rewrite, not a bypass) · **`2` REFUSED — it scanned nothing, and that is NOT a pass.** Exit 2 covers an empty range, a bad revision, and a scan skipped by `leakscan.disable` / `LEAK_SCAN_DISABLE`. Every refusal announces on stderr and every one exits non-zero, because an automated `… && echo PASS` reads only the code.

`git-leak-scan --control` proves every armed rule still fires. **A green control is not a clean repo** — it proves the instrument, not the scope. Pair them: `git-leak-scan --control && git-leak-scan --since <ref>`.

Known limits, all measured: commit messages and annotated tag messages are invisible to any diff-based scan; so is binary content; removed lines are deliberately not scanned, so a secret added _before_ a range and removed inside it stays invisible. **A range scan certifies the RANGE, never the repo.**

Prefer `git config leakscan.skip "<rule-ids>"` over `leakscan.disable` when one rule is noisy — the blunt knob switches off tokens and private keys as collateral.

## Deletion safety

### NEVER invoke the real deleter (BINDING — no exceptions, no judgement calls)

No agent, subagent, script, hook, Makefile, or subprocess may EVER call the real `rm`, in any form:

- `/bin/rm` — and every variation: `/usr/bin/rm`, `env rm`, `xargs /bin/rm`, `sh -c '/bin/rm …'`, an absolute path built from a variable, or any other spelling that reaches the binary directly.
- **`/bin/rm -P`** — the worst one. `-P` OVERWRITES the file's contents before unlinking. Nothing recovers it: not the Trash, not an APFS snapshot, not Time Machine unless the last backup predates the delete. Never type it, never generate it, never suggest it.
- `SAFE_RM_OFF=1 rm …` — the documented bypass. Still permanent. Reserved for a human.
- Any other route that destroys data without passing through the Trash: `unlink`, `find … -delete`, `truncate -s0`, `> file`, `dd of=…`, `shred`, `srm`.

**Always use bare `rm`.** It resolves to the Trash-routed wrapper — a zsh function when interactive, the `~/.local/bin/rm` PATH shim everywhere else (scripts, `xargs`, `make`, hooks). `command rm` and `\rm` are also safe: they bypass shell functions, not PATH.

**If you think you need a permanent delete, STOP and ask.** That decision belongs to the user, never to an agent. `/bin/rm` exists for a human's deliberate, informed choice — not for an agent's convenience, tidiness, or cleanup step. This rule outranks "it's only a temp file", "it's only build output", and "the disk is full".

See [`docs/DELETION_SAFETY.md`](docs/DELETION_SAFETY.md) for the coverage table, the measured evidence, and the two escape hatches that exist for humans.

### How the wrappers work

`rm`, `cp`, and `mv` are shell-function wrappers with safety behavior (rm routes to trash; cp/mv default to `-i` overwrite prompts). These wrappers are usually ACTIVE in Bash tool calls — Claude Code snapshots the interactive shell's functions to `~/.claude/shell-snapshots/snapshot-zsh-*.sh` and sources that file before every command, so the rm-to-trash wrapper comes along even though `.zshrc` itself isn't read. Verified 2026-06-08: `type -a rm` reported the snapshot function and a delete printed `Trashed ... (recover: Finder, Put Back)`, recoverable via Finder or the `trash` CLI. Caveats: confirmed for `rm` only (cp/mv presumably share the mechanism, untested).

**`type rm` REPORTING THE WRAPPER DOES NOT MEAN THE DELETE WILL SUCCEED — measured 2026-09-06, twice.** The wrapper was correctly in place and the trash call still FAILED, leaving the file exactly where it was:

```
trash[...]: Error attempting to move <path in this repo> to the trash folder …
  "couldn't be moved to the trash because you don't have permission to access it"
  Error Domain=NSOSStatusErrorDomain Code=-5000 "afpAccessDenied"
safe-rm: these paths still exist after the trash call: <path>
```

So a Bash-tool `rm` has **three** outcomes, not two: trashed, or refused-and-left-in-place, or (never, by design) permanently deleted. `safe-rm` is behaving correctly — it will not silently fall back to the real deleter — but **the file is neither gone nor in the Trash.** Hit twice on 2026-09-06 on paths inside this repo; a stray `.bak` had to be moved out by hand afterwards.

**THE CAUSE IS THE SANDBOX, isolated 2026-09-06** — same path, same wrapper, same session, one variable changed:

```
sandboxed (the default)          → afpAccessDenied, file REMAINS
dangerouslyDisableSandbox: true  → "Trashed: … (recover: Finder → Put Back)", file gone
```

A sibling project could not reproduce the failure at all; their session runs in bypass mode, which is exactly the passing half of that table. So **"the wrapper is installed" and "the wrapper works here" are two different facts, and only the second matters at the moment you need it.**

**And `type rm` cannot tell them apart** — it reported the wrapper in the failing case AND the passing one. _A check that returns the same answer either way is not a check_ (their phrasing; it is the all-cases-identical rule from `reference_measurement_harness_traps` applied to a check this file used to recommend).

**Therefore: after any `rm` you depend on, CHECK. `test -e <path>` — do not assume.** Especially before reporting a cleanup as done, and especially for a path under `home/`, where a leftover file can be picked up by stow. To relocate rather than delete, `command mv` it to the scratchpad; that always works.

The discipline does NOT change: ALWAYS get explicit user confirmation before deleting or overwriting — treat Trash recovery as a safety net, never a license to delete freely.

## Git & GitHub auth

Two systems run side by side. Which one a repo uses is decided by its `origin` URL, nothing else.

| `origin` looks like | Auth used | Notes |
|---|---|---|
| `git-cc:owner/repo` (or any `git@`/alias form) | SSH key `~/.ssh/captaincodeau` | The legacy path. Still the majority. |
| `https://x-access-token@github.com/owner/repo.git` | GitHub App, short-lived token | The new path. A repo joins ONLY via `github-agent-flip`. |
| plain `https://github.com/...` | nothing | The helper sees it and declines by design (no `x-access-token` username). |

Git invokes a credential helper only for an HTTPS remote, so an untouched SSH repo never touches the new system. Nothing migrates on its own.

**Flipped repos.** `github-agent-flip [--tier <tier>] <path>` rewrites `origin` to the HTTPS form and writes ONE key, `githubagent.tier`, into that repo's `.git/config`. Nothing guesses a tier — a flipped repo with no tier is refused with instructions. Tier App must already be installed on that repo on GitHub, or the flip's live check fails. Full reference: `docs/GITHUB_AGENT_USAGE.md`.

**Config order in `~/.gitconfig` is load-bearing.** A blank `[credential] helper =` clears every helper collected so far, url-scoped ones included, so it MUST stay ABOVE `[include] path = ~/.gitconfig.private`. With it below, the App helper is registered and then wiped, and every push falls back to a password prompt (hit 2026-09-13). `git config --get-all credential.https://github.com.helper` still PRINTS the helper when it is broken, so that command cannot detect this — only a real credential fill or `GIT_TRACE=1` can.

**In a Claude session, commits and tags work; pushes from a flipped repo do NOT.** The Bash sandbox blocks the login Keychain, and the helper's first step reads a bootstrap secret from there. Measured: a known-present entry returns exit 44 sandboxed, exit 0 unsandboxed. It fails cleanly, it does not hang. Push yourself, or run that one command with the sandbox off.

**`gh` does not use the credential helper.** It has its own auth and prefers `$GH_TOKEN` over everything. Consequences:

- `_claude_launch` exports a read-only fine-grained PAT as `$GH_TOKEN` in every Claude session, so reads work and writes return 403.
- Outside a Claude session, `gh` falls through to its own keyring, which currently holds a broad `gho_` OAuth token with `repo` scope. Any `gh` test run that way proves nothing about the App system.
- To exercise the App path, pass it in explicitly **to the real binary**: `GH_TOKEN="$(github-agent-token token)" "$(type -P gh)" <cmd>` (run from inside a flipped repo). An App token is an installation, not a user, so `/user/repos` correctly 403s; `/installation/repositories` is its endpoint. **The bare `gh` form of this line was wrong and is corrected here (2026-09-15):** interactively `gh` is a shell function that injects its own token, so `GH_TOKEN=... gh ...` silently tests the wrapper's credential instead of the one you passed — see the next section.
- Read-only public browsing: `GH_TOKEN="$(github-agent-token pat public-read)" "$(type -P gh)" api ...`.
- Posting to a public repo you do not own goes through `github-agent-public-post`. There is deliberately no print mode for that token.

### `gh` IS A SHELL FUNCTION HERE, AND IT SHADOWS THE TOKEN YOU PASS

Measured 2026-09-15, and it cost two sessions a full day of confidently
disagreeing about the same repository.

```
$ type gh
gh is a shell function from ~/.claude/shell-snapshots/snapshot-zsh-*.sh
```

That function injects its own token. So **`GH_TOKEN=<something> gh api ...` does
NOT use the token you passed** — the wrapper replaces it. Raw `curl` with an
explicit `Authorization` header against the same URL returned 200 while the same
token "through" `gh` returned 404. Two people running what they believed was the
same command got different answers, and neither could see why.

Consequences, all measured:

- **`gh auth status` describes the WRAPPER's world, not a script's.** A script
  gets the real binary via PATH; an interactive shell gets the function. They can
  disagree completely about which credential is active.
- **`command -v gh` is NOT a safe resolver.** Given a shell function named `gh` it
  returns the string `gh`, i.e. the function. Use **`type -P gh`**, which searches
  PATH only. This exact substitution was caught by a test written for the line.
- A correct probe is one of:
  ```bash
  env -u GH_TOKEN -u GITHUB_TOKEN "$(type -P gh)" api <path>
  curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/<path>"
  ```

Same family as the refusal-is-not-an-answer rule above: the tool answered, it
just answered about something other than what was asked.

### Dating a credential change from the status codes alone

A useful diagnostic, learned 2026-09-15 when a token was regenerated mid-session
and two sessions spent an afternoon disagreeing about the same repository.

**A token does not move from "valid but insufficient" to "unauthenticated" on its
own.** So on ONE endpoint, over time:

```
403 "Resource not accessible by integration"   -> the token is valid, the
                                                  permission is missing
401                                            -> the token itself is no longer
                                                  accepted: revoked, regenerated,
                                                  or expired
```

A **403 -> 401 transition on the same URL dates a credential rotation** to
somewhere between the two measurements. Both readings were correct when taken;
what changed was the world, not the instrument.

The practical consequence: **a session launched before a rotation carries the
revoked secret until it is restarted**, because the token is read from the
Keychain once at launch. Restart the session; do not file the bad output under
"it always looks wrong in here". That phrasing converts a transient, fixable
failure into background noise, which is the same habituation the session-start
watchers exist to prevent, just relocated to the human.

### NEVER wire a "retry with GH_TOKEN unset" fallback into any tool

Proposed as a usability fix on 2026-09-15 and withdrawn once the consequence was
named. It is a **privilege escalation dressed as a retry**.

Unsetting `GH_TOKEN` does not mean "no credential" — it means gh falls through to
its own keyring, which here holds a broad OAuth token carrying **`repo` scope**:
full source read across every repository the account owns. The fine-grained PAT a
read-only tool is meant to use deliberately has **no contents access at all**.

So a status-line tool that retries without `GH_TOKEN` whenever it sees a 403 would
silently upgrade itself to reading all your source, and the upgrade would be
invisible in its output. **A watcher that cannot see must say so, not go looking
for a bigger key.** The correct fix is to NAME the credential that answered, so a
disagreement is one line of output instead of two sessions of archaeology.

**Never run `gh auth login` / `gh auth setup-git` / `gh auth refresh`** — they re-add HTTPS credential helpers and break SSH-only auth (a `gh()` shell wrapper and a PreToolUse hook block them).
