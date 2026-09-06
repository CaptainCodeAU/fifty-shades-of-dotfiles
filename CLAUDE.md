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

**Always use bare `rm`.** It resolves to the Trash-routed wrapper — a zsh function when interactive, the `~/.local/bin/rm` PATH shim everywhere else (scripts, `xargs`, `make`, hooks). `command rm` and `\rm` are also safe now: they bypass shell functions, not PATH.

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

**Therefore: after any `rm` you depend on, CHECK. `test -e <path>` — do not assume.** Especially before reporting a cleanup as done, and especially for a path under `home/`, where a leftover file can be picked up by stow. To relocate rather than delete, `command mv` it to the scratchpad; that always works.

The discipline does NOT change: ALWAYS get explicit user confirmation before deleting or overwriting — treat Trash recovery as a safety net, never a license to delete freely.

## GitHub CLI (`gh`)

Never run `gh auth login` / `gh auth setup-git` / `gh auth refresh` - they re-add HTTPS credential helpers and break SSH-only auth (a `gh()` shell wrapper and a PreToolUse hook block them). For GitHub API reads use `gh api` / `gh run` / `gh pr` / `gh issue` (or `curl` with `$GH_TOKEN`); a fine-grained read-only token is provided as `$GH_TOKEN` in Claude sessions, so any write call returns 403.
