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

## Things that will trip you up

| Symptom | Cause |
|---|---|
| `gh` works but proves nothing | `gh` ignores the credential helper. It prefers `$GH_TOKEN`, then its own keyring (which holds an old broad `gho_` token). Use `GH_TOKEN="$(github-agent-token token)" gh ...` to exercise the App path. |
| `/user/repos` returns 403 | Correct. An App token is an installation, not a user. Its endpoint is `/installation/repositories`. |
| Push fails inside a Claude session | The Bash sandbox blocks the login Keychain, which the helper reads first. Commits and tags are fine. Push yourself, or run that one command with the sandbox off. |
| A flip "succeeded" but push fails | The flip's own check mints through its own code path and never exercises git's credential path. Only a real push proves a real push. |
| A repo in the wrong folder | Doesn't matter. Matching is by origin URL. Move folders whenever you like. |
| `git clone` of a flipped repo | Arrives with no tier. Either flip it after, or clone with `git -c githubagent.tier=<tier> clone ...`. |
