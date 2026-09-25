# GitHub Agent — Recipes

Follow-along steps for the things you actually do. This is the **recipe book**;
`GITHUB_AGENT_USAGE.md` is the **reference** (what every flag does, what lives
where). When you want "how do I do X", start here.

Every recipe says: when to use it, the exact commands, how you know it worked,
and what to do when it doesn't.

**One rule underneath all of it:** a repo is on the new system if, and only if,
its `origin` starts with `https://x-access-token@github.com/`. Nothing else
decides it. Folder location is irrelevant.

---

## Recipe 1 — A brand new repo

**When:** you are starting a new project that will live on GitHub.

1. Create the repo on GitHub (website or `gh repo create`).
2. **On GitHub, install the right tier App on it.** Settings -> GitHub Apps ->
   `gap-cc-<tier>-value-shared` -> Configure -> add the repo.
   This step is what decides the repo's tier. Skip it and step 5 fails.
3. Clone it. A fresh clone is NOT on the system yet:
   ```
   git clone git@github.com:CaptainCodeAU/<repo>.git ~/CODE/CaptainCodeAU/<repo>
   ```
4. Flip it:
   ```
   github-agent-flip ~/CODE/CaptainCodeAU/<repo>
   ```
   It asks which tier, shows before/after, and confirms.
5. **How you know it worked:** the last line reads
   `[OK] A real token minted for this repo. It's genuinely wired up.`

**Shortcut if you already know the tier:** `github-agent-flip --tier medium-value <path>`

**Running it from an agent session, or any non-TTY.** The flip is INTERACTIVE.
Without `-y` it prints the preview, gets no answer from a non-TTY, and exits
leaving `origin` UNCHANGED. That reads as a soft no-op and is easy to misreport
as done:

```
github-agent-flip -y --tier <tier> <path>
```

`-y` deliberately implies `--no-verify`, because the verification step mints a
token and minting pulls the App's private key into the running process, which
is not something an agent's process should hold. So `-y` on its own will NOT
print the `[OK] A real token minted for this repo` line, and its absence is
expected rather than a failure.

`-y --verify` overrides that and restores the line, but only do it knowingly:
it puts the private key in the agent's process, which is the thing the default
is avoiding. **Prefer `-y` alone and then prove it with a real push** — the
recipe book's own rule is that only a real push proves a real push, and that is
a stronger check than the flip's internal mint anyway.

**If step 5 fails** with "this GitHub App isn't installed on ...", you skipped
or mis-picked step 2. Fix it on GitHub and re-run the flip; it is idempotent.

---

## Recipe 2 — A repo you just cloned

**When:** you cloned something of your own that existed before.

Same as Recipe 1 from step 4. The tier App is probably already installed (you
did that when the repo was created), so:

```
github-agent-flip ~/CODE/CaptainCodeAU/<repo>
```

**Don't remember the tier?** You don't have to. Run the bulk tool in dry-run
mode and read the answer off it:

```
github-agent-flip-all | grep <repo>
```

---

## Recipe 3 — Move everything for one account

**When:** a migration campaign, one GitHub account at a time.

1. **Always dry run first.** It writes nothing:
   ```
   github-agent-flip-all
   ```
2. Read the four lists it prints:
   - `WILL FLIP` — unambiguous, safe.
   - `AMBIGUOUS` — in more than one tier. **Fix on GitHub**, don't guess.
   - `NO TIER ON GITHUB` — install a tier App on these first.
   - `WORKTREES` / `OTHER ACCOUNTS` — correctly skipped, ignore.
3. Flip for real:
   ```
   github-agent-flip-all --apply
   ```
4. Or ease into it one tier at a time:
   ```
   github-agent-flip-all --only-tier low-value --apply
   ```
5. **How you know it worked:** `All N flipped.` — then prove it with one real
   push in one repo. The exit code is not proof.

**A different account:** `github-agent-flip-all --owner CodeWithGavin`
(needs that account to have its own tier Apps first).

**Never flip the MLBOX gateways.** `publish-mlbox` and `refresh-mlbox` push over
SSH and would break. They are excluded by default; leave it that way.

---

## Recipe 4 — Push asks for a password

**When:** `git push` prompts `Password for 'https://x-access-token@github.com/...'`.

**Do not type anything. Press Ctrl+C.** A prompt means the credential helper
returned nothing, so there is no password to give.

Diagnose in this order:

1. **Is the helper actually being called?**

   ```
   printf 'protocol=https\nhost=github.com\nusername=x-access-token\n\n' \
     | GIT_TERMINAL_PROMPT=0 GIT_TRACE=1 git credential fill 2>&1 | grep run_command
   ```

   You want a line running `github-agent-token get`. If it is absent, the helper
   is not in the effective list — check the config order below.

2. **Config order in `~/.gitconfig`.** A blank `[credential] helper =` wipes every
   helper collected so far, url-scoped ones included, so it MUST sit ABOVE
   `[include] path = ~/.gitconfig.private`. This is the bug that bit on
   2026-09-13. Note that `git config --get-all credential.https://github.com.helper`
   **still prints the helper when it is broken**, so that command cannot detect it.

3. **Is the tier App installed on this repo?**
   ```
   git config --local --get githubagent.tier      # what the repo thinks
   github-agent-token token > /dev/null           # mints, or tells you why not
   ```

---

## Recipe 5 — Check where a repo stands

```
git remote -v                                    # x-access-token@ = on the system
git config --local --get githubagent.tier        # which tier
github-agent-flip <path>                          # re-run: reports and health-checks
```

Re-running `github-agent-flip` on an already-correct repo changes nothing and
still runs the live mint check, so it doubles as a health check.

---

## Recipe 6 — Read public repos

```
GH_TOKEN="$(github-agent-token pat public-read)" gh api /repos/<owner>/<repo>
```

Read-only and public-only by construction: it sees 0 private repos and any write
returns 403.

---

## Recipe 7 — Post to someone else's public repo

```
github-agent-public-post --dry-run ...    # fetches no credential at all
github-agent-public-post ...              # shows the full draft, waits
```

There is deliberately **no** print mode for that token. This tool is the only
route to it.

---

## Recipe 8 — The token cache: check it, clear it, prove it

**When:** pushes suddenly feel slow, or you want to know whether the cache is
doing anything, or you want a token gone from memory right now.

Since 2026-09-13 the first git operation mints a token and the next 50 minutes
are served from memory. Full detail in `GITHUB_AGENT_USAGE.md`.

**Is it running?** Run this UNSANDBOXED. Inside the Claude sandbox `pgrep`
returns 0 whether or not the process exists:

```
pgrep -f 'credential-cache--daemon'
ls -la ~/.cache/git/credential/socket
```

**Clear it now** (after rotating a credential, or if you just want it gone):

```
git credential-cache exit
```

**Prove it is actually working.** Count helper invocations cold versus warm.
The cold reading is the positive arm, and without it a warm `0` looks exactly
like a helper that never ran:

```
git credential-cache exit
GIT_TRACE=1 git push --dry-run origin master 2>&1 >/dev/null | grep -c 'github-agent-token get'   # cold: 2
GIT_TRACE=1 git push --dry-run origin master 2>&1 >/dev/null | grep -c 'github-agent-token get'   # warm: 0
```

**If both readings are 2**, the cache is not engaging. Check helper order in
`~/.gitconfig-githubagent`: `cache` must come ABOVE the minting helper, because
git stops at the first helper that answers.

```
git config --get-all credential.https://github.com.helper
```

**A push says "Invalid username or token" (W-20260925-A30).** The cache handed
back a token that had already expired. Its 50-minute timer did not stop it: on
2026-09-25 a dot-claude push got that error at 03:42:32 UTC. Best guess, not
established: the daemon's timer does not count time the Mac is asleep.

Since A30, `github-agent-token` also returns `password_expiry_utc` (GitHub's
`expires_at` minus 10 minutes). git 2.41+ drops an expired password that any
helper returns, the cache included, and asks the minting helper for a new one.
A token cached BEFORE that change carries no expiry, so for up to 50 minutes
after upgrading, the old failure can still show once. Clear it with
`git credential-cache exit`.

**A token minted seconds ago can fail ONCE with "Repository not found".** Same
push, 11 seconds later (03:42:43 UTC), after `git credential-cache exit`: the fresh
token got `remote: Repository not found.`, and a plain retry about 30 seconds later went through. It
looks like a missing repo or a missing install, but it was neither. Retry once
before you debug anything.

**Prove the expiry fix still holds** (after a git upgrade, say). Run it UNSANDBOXED.
Inside the sandbox the throwaway cache daemon cannot bind its socket, and the
selftest exits 2 (invalid, nothing tested) rather than passing:

```
github-agent-token-selftest            # fake helper + throwaway cache: 3 arms
builtin cd <a flipped repo> && github-agent-token-selftest --live   # + the real helper, token never printed
```

---

## Recipe 9 — Probe the API from a session whose token is stale or revoked

You are inside a session, a GitHub call fails, and you suspect the token the
session was launched with is no longer good. **The obvious move is wrong.**

```bash
# DO THIS — supply the correct narrow credential explicitly
GH_TOKEN="$(security find-generic-password -a "$USER" -s github-api-readonly -w)" ci-watch

# If this returns exit 44, that is the sandbox denying ~/Library/Keychains, NOT a missing
# credential. Lift the sandbox for that single command. Never unset GH_TOKEN instead.
# Exit 0 does not mean this is wrong; it means this session is not sandboxed.
```

```bash
# NOT THIS — it looks like reducing privilege and does the opposite
env -u GH_TOKEN gh api ...
```

**Why the obvious move is backwards.** Unsetting a token feels like dropping to
fewer permissions. It is not: `gh` then falls through to whatever it finds next,
which here is its own keyring holding a broad OAuth token with **`repo` scope** —
full source read across every repository the account owns. The fine-grained
`github-api-readonly` PAT deliberately has **no contents access at all**. So the
"safer-looking" command quietly hands the tool far more authority than the one it
replaced, and nothing in the output says so.

**Why both exit codes are written above.** Three sessions measured this on
2026-09-15 and got two different answers. One sandboxed session returned exit 44,
with `security list-keychains` seeing only `System.keychain` and a write outside
the project refused. Two unsandboxed sessions returned exit 0 with both keychains
visible. All three results were correct — the variable is simply whether the Bash
sandbox is constraining that session, which nobody was checking. A reader who
gets exit 0 and concludes the caveat is stale will delete it and go straight back
to unsetting the variable; that nearly happened the day this was written.

**Am I sandboxed right now?** Use `security list-keychains`. It probes the same
subsystem the caveat is about rather than a proxy for it, has no side effects, and
needs no cleanup line that a copier can drop:

```bash
security list-keychains
#   sandboxed   -> ONLY /Library/Keychains/System.keychain
#   unsandboxed -> ALSO /Users/<you>/Library/Keychains/login.keychain-db
#   NEITHER     -> INVALID TRIAL. If System.keychain is missing too, `security`
#                  itself did not answer, and the result says nothing either way.
```

Measured 2026-09-15 as a controlled pair: the same command, in the same session,
with the sandbox as the only variable, three consecutive runs per arm. Sandboxed
returned System.keychain alone every time with the credential fetch at exit 44;
unsandboxed returned both keychains every time with the fetch at exit 0. The link
between the sandbox and the 44 is therefore causal, not coincidental.

That third line is not padding. "Sandboxed shows only System.keychain" treats a
SHORT LIST as proof, and a short list reads identically whether the sandbox
trimmed it or `security` failed outright. The presence of System.keychain is what
makes a short answer a finding rather than a silence.

Do NOT use a write test for this. `$TMPDIR` and the working directory are writable
in **both** conditions, so a probe there reports "not sandboxed" either way — an
answer that cannot separate the two cases it exists to separate. A write to `/tmp`
or `~/Desktop` does discriminate (both were refused under the sandbox, measured),
but it needs a cleanup line, and a cleanup line is the part a copier drops.

The principle this implements lives in `OPERATIONAL_RULES.md` § Engineering
discipline ("supply the correct narrow credential explicitly; never remove a
credential in order to fall through to a broader one"). **This entry deliberately
does not restate it** — the rule is the doctrine, this is the invocation.
Background: `INC-20260915-ci-watch-observability`.

**A related trap, same family.** A launcher that never supplies the narrow
credential produces the same escalation without anyone choosing it. See
`INC-20260915-herdr-spawn-bypasses-credential-path`.

## Things that will trip you up

| Symptom                                                       | Cause                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gh` works but proves nothing                                 | `gh` ignores the credential helper. It prefers `$GH_TOKEN`, then its own keyring (which holds an old broad `gho_` token). Use `GH_TOKEN="$(github-agent-token token)" gh ...` to exercise the App path.                                                                                                                                                                                                                                                                             |
| `/user/repos` returns 403                                     | Correct. An App token is an installation, not a user. Its endpoint is `/installation/repositories`.                                                                                                                                                                                                                                                                                                                                                                                 |
| Push fails inside a Claude session                            | The Bash sandbox blocks the login Keychain, which the helper reads first. Commits and tags are fine. Push yourself, or run that one command with the sandbox off.                                                                                                                                                                                                                                                                                                                   |
| A flip "succeeded" but push fails                             | The flip's own check mints through its own code path and never exercises git's credential path. Only a real push proves a real push.                                                                                                                                                                                                                                                                                                                                                |
| A repo in the wrong folder                                    | Doesn't matter. Matching is by origin URL. Move folders whenever you like.                                                                                                                                                                                                                                                                                                                                                                                                          |
| `git clone` of a flipped repo                                 | Arrives with no tier. Either flip it after, or clone with `git -c githubagent.tier=<tier> clone ...`.                                                                                                                                                                                                                                                                                                                                                                               |
| A push works, then "stops using" the helper                   | Correct and expected. The token cache serves the next 50 minutes from memory, so `github-agent-token` is not invoked again. 0 invocations on a warm repeat is the cache working, not a broken helper.                                                                                                                                                                                                                                                                               |
| The cache seems to do nothing                                 | Two usual causes. Helper ORDER: `cache` must sit above the minting helper in `~/.gitconfig-githubagent`. Or the daemon could not bind its socket: inside the Claude sandbox git prints `unable to bind to '<socket>': Operation not permitted` and `cache daemon did not start`, then mints every time. (This row used to blame any custom `--socket` path. Measured 2026-09-25 unsandboxed: a custom socket under `$TMPDIR` served from the cache. Only the sandboxed run failed.) |
| Push fails "Invalid username or token"                        | The cache served an expired token. Fixed by A30 (the helper now sends `password_expiry_utc`), except for a token cached before the upgrade. `git credential-cache exit`, then retry. See Recipe 8.                                                                                                                                                                                                                                                                                  |
| A freshly minted token fails once with "Repository not found" | Seen 2026-09-25, 11 seconds after a cache clear; a retry about 30 seconds later went through. Retry once before suspecting the repo or the install.                                                                                                                                                                                                                                                                                                                                 |
| `pgrep` says the cache daemon is not running                  | Not evidence. Inside the Claude sandbox `pgrep` fails with "Cannot get process list" and the count reads 0 either way. Check it unsandboxed.                                                                                                                                                                                                                                                                                                                                        |
| A push fails 403 "denied to gap-cc-...[bot]"                  | Do NOT conclude the App lost write access from one 403. Seen 2026-09-13 during a GitHub wobble while the installation record read `contents: write` and the next push succeeded. Retry first. `GET /installation/repositories` also reported `permissions.push: false` three times while real pushes worked, so that field is not a reliable indicator either.                                                                                                                      |
| Mint fails with a 500 or 502                                  | GitHub's token endpoint, not you. Measured 6 failures in 10 calls on 2026-09-13 with githubstatus.com showing all green. `github-agent-token` retries 5xx six times with jitter and says so on stderr; a 4xx still fails instantly.                                                                                                                                                                                                                                                 |
