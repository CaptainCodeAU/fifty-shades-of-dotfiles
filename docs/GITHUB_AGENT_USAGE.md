# GitHub Agent Credential System — Usage Guide

> **The real values are not in this file.** It is tracked in a public repo,
> so the credential table, the Infisical instance and paths, the App IDs and
> the Keychain service names all live in `docs/GITHUB_AGENT_USAGE.private.md`
> instead, alongside the machine's own `~/.gitconfig-githubagent`. This file
> covers how the system works and how to drive it, which is the useful half
> and gives nothing away.

> **Looking for step-by-step instructions rather than a reference?**
> `GITHUB_AGENT_RECIPES.md` is the recipe book: new repo, freshly cloned repo,
> bulk-flip a whole account, push asks for a password, check where a repo stands,
> read public repos, post to someone else's public repo. Each says when to use
> it, the exact commands, how you know it worked, and what to do when it doesn't.
> This file answers "what does this flag do"; that one answers "what do I type".

## The shape of it

Five credentials, in two families.

**Three pooled GitHub Apps**, one per tier: `high-value`, `medium-value`,
`low-value`. All three hold identical permissions (Contents, Issues, Pull
requests, read and write). The tier decides only which repos are pooled
behind one App, so a compromise is contained to that pool rather than to
everything. Each mints a fresh 1-hour, single-repo-scoped token on every
single git or `gh` call, and GitHub itself enforces the expiry.

**Two Personal Access Tokens**, for public GitHub, where a repo-installed
App cannot reach:

- a fine-grained, read-only one for browsing public repos
- a classic one holding the narrow `public_repo` scope and never the broad
  `repo` scope, for opening issues and comments on repos you do not own

Unlike the App tokens these mint nothing: each is one fixed string stored in
Infisical until its expiry date, so their rotation is manual. GitHub will not
force it the way it does for the App tokens.

A repo can also be promoted off the shared pool onto its own dedicated App
later. It then carries the flat `[githubagent]` keys in its own local config
and no tier at all; nothing in the code needs to know a repo's status.

## Setting a new credential up

The full command sequences — creating a tier App through the manifest flow,
storing its key, creating the Infisical machine identity, saving the
bootstrap secret to the Keychain, installing the App and verifying the whole
chain — are in `docs/GITHUB_AGENT_USAGE.private.md`, because every step of
them names a real path or identity.

The tools themselves are `github-agent-create-app` and
`github-agent-verify-app`, and both are run by the principal in his own
terminal, never by an agent, so a real private key never passes through an
agent's process.

## The 1-hour token expiry — how "renewal" actually works

There is no renewal step and nothing runs in the background. Every single
`git push`/`pull` or `gh` command on a flipped repo triggers
`github-agent-token`, which mints a brand-new 1-hour token from the permanent
private key on the spot, uses it once, and discards it. Nothing is ever
cached or reused, so there's nothing to manually refresh — the next call,
whenever it happens, just repeats the same mint from scratch.

## Day-to-day usage (built and tested 2026-09-12)

### Putting a repo on the system

```
github-agent-flip ~/code/some-repo
```

It asks which tier the repo belongs to, shows you the before/after, changes
two things, reads both back, then mints one real token and throws it away
just to prove the App really is installed on that repo.

The two things it changes:

1. `origin` becomes `https://x-access-token@github.com/OWNER/REPO.git`
2. one key, `githubagent.tier`, lands in that repo's own `.git/config`

That second key is the whole tier mechanism. Everything else about a tier —
App ID, Infisical path, client ID, Keychain service — lives once per tier in
`~/.gitconfig-githubagent`, never per repo, so rotating a tier's credentials
is one edit in one file.

Useful flags:

| Flag | Effect |
| --- | --- |
| `--tier medium-value` | say the tier up front instead of being asked |
| `-y` / `--yes` | no prompts (agent use, after you've said go-ahead) |
| `--no-verify` | skip the live mint check |
| `--verify` | force the live check on, even with `-y` |

`-y` implies `--no-verify` on purpose: minting pulls the App's private key
into the running process, which isn't something an agent's process should
hold. `--verify` alongside `-y` overrides that deliberately.

Re-running `github-agent-flip` on a repo that's already correct doesn't
change anything, but **does** still run the live check — so it doubles as
"is this still working?", which is the question you actually have when you
re-run it.

### Nothing guesses a tier

A flipped repo with no `githubagent.tier` is refused with instructions, not
quietly pointed at some default App. The one place that bites is a fresh
`git clone`, which has no repo on disk yet to read the key from. Say it
explicitly:

```
git -c githubagent.tier=high-value clone https://x-access-token@github.com/OWNER/REPO.git
```

(That works because git exports `-c` settings to child processes via
`GIT_CONFIG_PARAMETERS`, which the credential helper inherits — measured
2026-09-12, not assumed.)

One edge worth knowing: git runs the credential helper from your **current
directory**. Cloning while standing inside another flipped repo reads *that*
repo's tier. It fails cleanly (wrong App, refused by GitHub) rather than
doing anything dangerous, but the error will look confusing if you don't
know why.

### After a flip, `git` and `gh` just work

Every `git push`/`pull` runs `github-agent-token` as git's credential helper,
which mints a brand-new 1-hour, single-repo-scoped token on the spot. `gh`
doesn't consult git's credential helper, so the `gh` wrapper in `.zshrc`
covers it separately via `github-agent-token token`. Nothing is cached and
there is nothing to refresh.

### The two PATs

```
GH_TOKEN="$(github-agent-token pat public-read)" gh api /repos/golang/go
```

That's the read-only browsing token. It is printable on purpose — it can
read public repos and nothing else.

**There is deliberately no print mode for the public-write PAT.** That token
can open issues and post comments on any public repo as you, so nothing on
this machine puts it on a screen:

```
$ github-agent-token pat public-write
[FAIL] there is deliberately no print mode for the 'public-write' PAT.
```

The only way to use it is `github-agent-public-post`, which fetches it
internally and never prints it. You cannot bypass a print command that was
never built. If you need the raw value to rotate it, read it from
Infisical's own web UI.

### Posting to someone else's public repo

```
github-agent-public-post issue   --repo owner/repo --title "..." --body-file draft.md --dry-run
github-agent-public-post comment --repo owner/repo --number 123   --body-file reply.md
github-agent-public-post check
```

The flow is draft → show → confirm → post, and the draft prints **every
time**, including under `-y`, so a session transcript always carries a record
of exactly what went out.

| Flag | Effect |
| --- | --- |
| `--dry-run` | show the draft and stop. **Fetches no token at all** — safe for an agent to run freely |
| `-y` / `--yes` | skip the typed confirmation. Draft still prints |
| `--allow-own-repo` | permit a target you own (refused by default) |

Without `-y` it asks you to type `post`. If there's no terminal attached and
`-y` wasn't given, it refuses rather than hanging.

Guards that fire before anything is written:

- **Your own repos are refused.** They belong on the tier Apps — scoped,
  1-hour, revocable per repo — not on a permanent PAT. `--allow-own-repo`
  exists for the genuine exception and says so out loud in the draft.
- Private repos are refused (a `public_repo` PAT can't write there anyway).
- Archived repos, disabled issues, closed and locked issues are all flagged
  in the draft before you confirm.

`github-agent-public-post check` proves the token's scope without printing
it — verified 2026-09-12:

```
[1/4] Fetched from Infisical via Keychain. (never printed)
[2/4] GitHub accepts it. Posts publicly as CaptainCodeAU.
[3/4] Scope is exactly public_repo — the narrow one. Expires: 2027-01-31 13:00:00 UTC
[4/4] Negative control: it can see 0 private repos. Boundary holds.
```

## What `~/.gitconfig-githubagent` looks like now

Filled in 2026-09-12. Structure, not values:

```
[credential "https://github.com"]
	helper = !~/.local/bin/github-agent-token   # real config uses the absolute path
	useHttpPath = true

[githubagent]                          # ONLY the 3 values every profile shares
	infisicalBaseUrl = ...
	infisicalProjectSlug = ...
	infisicalEnvironment = ...

[githubagent "high-value"]             # x3 tiers: appId, clientId, secret path,
	appId = ...                        #   secret name, keychain service, description
	...

[githubagent "public-read"]            # x2 PATs: same minus appId
	...
```

The flat block is deliberately tiny. A secret path, client ID, App ID or
Keychain service is never put there, so a mistyped tier name can't quietly
fall through onto some other credential's settings — it errors instead.

Nothing in that file is a secret. App IDs and Infisical Client IDs are
identifiers; each identity's Client **Secret** lives only in the macOS
Keychain.

A repo promoted off the shared pool onto its own dedicated App skips tiers
entirely: it sets the flat keys (`appId`, `infisicalClientId`,
`infisicalSecretPath`, `infisicalSecretName`, `keychainService`) in its own
local config and no tier at all.
