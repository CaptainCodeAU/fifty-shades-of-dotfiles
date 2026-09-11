# GitHub Agent Credential System — Usage Guide

Started early (during the medium/low-value build) instead of waiting until the
whole rollout is finished, since the exact command sequence is freshest right
after actually running it once for real (`gap-cc-high-value-shared`). This
doc is the living reference — update it as new tiers/repos get added.

## The credential table

Shared by every row: Infisical instance `https://REDACTED-INFISICAL-HOST`,
project `REDACTED-INFISICAL-PROJECT`, environment `prod`.

| Tier/PAT                         | Type             | Covers                            | Permissions                     | Infisical Path                    | Secret Key Name          | Infisical Identity Name     | Keychain Service Name                      | Status                      |
| -------------------------------- | ---------------- | --------------------------------- | ------------------------------- | --------------------------------- | ------------------------ | --------------------------- | ------------------------------------------ | --------------------------- |
| `gap-cc-high-value-shared`       | GitHub App       | Most important repos, pooled      | Contents/Issues/PRs, read+write | `/github-agent-apps/high-value`   | `GITHUB_APP_PRIVATE_KEY` | `REDACTED-IDENTITY`   | `REDACTED-KEYCHAIN-gap-high-value-shared`       | **Done** — App ID `REDACTED-APP-ID` |
| `gap-cc-medium-value-shared`     | GitHub App       | Everyday active repos, pooled     | Same                            | `/github-agent-apps/medium-value` | `GITHUB_APP_PRIVATE_KEY` | `REDACTED-IDENTITY` | `REDACTED-KEYCHAIN-gap-medium-value-shared`     | **Done** — verified         |
| `gap-cc-low-value-shared`        | GitHub App       | Old/low-stakes repos, pooled      | Same                            | `/github-agent-apps/low-value`    | `GITHUB_APP_PRIVATE_KEY` | `REDACTED-IDENTITY`    | `REDACTED-KEYCHAIN-gap-low-value-shared`        | **Done** — verified         |
| `pat-cc-public-read-browse`      | Fine-grained PAT | Reading public GitHub content     | Public Repositories, read-only  | `/github-agent-apps/public-read`  | `PAT_VALUE`              | `REDACTED-IDENTITY`  | `REDACTED-KEYCHAIN-pat-public-read-browse`      | **Done**                    |
| `pat-cc-public-write-thirdparty` | Classic PAT      | Issues/PRs on repos you don't own | `public_repo` scope only        | `/github-agent-apps/public-write` | `PAT_VALUE`              | `REDACTED-IDENTITY` | `REDACTED-KEYCHAIN-pat-public-write-thirdparty` | **Done**                    |

## Creating and wiring up one tier App — full command sequence

Worked example below uses `high-value` throughout (the one already done).
For `medium-value` / `low-value`, swap the tier name everywhere it appears —
same commands, same order, nothing else changes.

**1. Create the App** (you run this, one browser click when GitHub asks):

```
github-agent-create-app --tier high-value
```

Note the printed App ID and the "secrets staged at" file path from the receipt.

**2. Copy the private key onto your clipboard** (real line breaks, not the
file's escaped ones):

```
python3 -c "import json; print(json.load(open('<path-from-step-1>'))['pem'], end='')" | pbcopy
```

**3. Paste it into Infisical** (manual, in your browser):

- Project `REDACTED-INFISICAL-PROJECT`, environment `prod`
- Folder `github-agent-apps / high-value`
- Secret name `GITHUB_APP_PRIVATE_KEY`
- Value: paste from clipboard (check for an expand/resize icon on the value
  field first — pasting into the tiny collapsed box has previously flattened
  the key onto one line and broken it)

**4. Create the Infisical Machine Identity** (manual, in Infisical's UI):

- Auth method: Universal Auth
- Identity name: `REDACTED-IDENTITY`
- Access: No Access by default, then one Additional Privilege:
  - Privilege name: `read-high-value-key`
  - Scope: read-only on `/github-agent-apps/high-value`, environment `prod`
- Client Secret Description: `REDACTED-IDENTITY-client-secret`
- Note down the **Client ID** (not secret) and the **Client Secret** (shown once)

**5. Save the Client Secret to macOS Keychain** (copy the Client Secret to
your clipboard first):

```
security add-generic-password -a "$(whoami)" -s "REDACTED-KEYCHAIN-gap-high-value-shared" -w "$(pbpaste)" && pbcopy < /dev/null
```

**6. (Optional) confirm it landed:**

```
security find-generic-password -s "REDACTED-KEYCHAIN-gap-high-value-shared"
```

**7. Install the App on at least one repo** (manual, in your browser):
`https://github.com/settings/apps/gap-cc-high-value-shared/installations` ->
Install -> pick specific repo(s), never "All repositories".

**8. Verify the whole chain actually works:**

```
github-agent-verify-app --tier high-value --infisical-client-id <client-id-from-step-4> --app-id <app-id-from-step-1>
```

Add `--staged-file <path>` only if you moved the file from where step 1 put
it. Add `--check-repo owner/repo1,owner/repo2` to also confirm specific repos
one at a time (comma-separated) — use a repo it should have, one it shouldn't,
or both.

**9. Shred the staged secrets file** (only after step 8 passes):

```
/bin/rm -P <path-from-step-1>
```

## Creating and storing the two PATs — full command sequence

Unlike the GitHub Apps, these are made by hand on GitHub's website directly —
no manifest tool, no browser-click-and-listen flow. There is currently no
`github-agent-verify-app`-style check for these two (the code that would
consume them, `github-agent-token`'s PAT-fetch mode and
`github-agent-public-post`, hasn't been built yet — that's still ahead).

### `pat-cc-public-read-browse`

**1. Create it** (manual, in your browser):
`https://github.com/settings/personal-access-tokens/new`

- Name: `pat-cc-public-read-browse`, set a real expiration date
- Repository access → **Public Repositories (read-only)**
- Generate, then copy the value GitHub shows you (its own copy button)

**2. Paste it into Infisical** (manual):

- Folder `github-agent-apps / public-read`, secret name `PAT_VALUE`

**3. Create the Infisical Machine Identity** (manual):

- Identity name: `REDACTED-IDENTITY`
- One Additional Privilege, read-only on `/github-agent-apps/public-read`,
  environment `prod`
- Client Secret Description: `REDACTED-IDENTITY-client-secret`

**4. Save the Client Secret to Keychain** (copy it to your clipboard first):

```
security add-generic-password -a "$(whoami)" -s "REDACTED-KEYCHAIN-pat-public-read-browse" -w "$(pbpaste)" && pbcopy < /dev/null
```

**5. (Optional) confirm it landed:**

```
security find-generic-password -s "REDACTED-KEYCHAIN-pat-public-read-browse"
```

### `pat-cc-public-write-thirdparty`

**1. Create it** (manual, in your browser):
`https://github.com/settings/tokens/new` (the **classic** token page, not
fine-grained)

- Name: `pat-cc-public-write-thirdparty`, set a real expiration date
- Check **only** the `public_repo` scope — never the broader `repo` scope
- Generate, then copy the value

**2. Paste it into Infisical** (manual):

- Folder `github-agent-apps / public-write`, secret name `PAT_VALUE`

**3. Create the Infisical Machine Identity** (manual):

- Identity name: `REDACTED-IDENTITY`
- One Additional Privilege, read-only on `/github-agent-apps/public-write`,
  environment `prod`
- Client Secret Description: `REDACTED-IDENTITY-client-secret`

**4. Save the Client Secret to Keychain** (copy it to your clipboard first):

```
security add-generic-password -a "$(whoami)" -s "REDACTED-KEYCHAIN-pat-public-write-thirdparty" -w "$(pbpaste)" && pbcopy < /dev/null
```

**5. (Optional) confirm it landed:**

```
security find-generic-password -s "REDACTED-KEYCHAIN-pat-public-write-thirdparty"
```

## The 1-hour token expiry — how "renewal" actually works

There is no renewal step and nothing runs in the background. Every single
`git push`/`pull` or `gh` command on a flipped repo triggers
`github-agent-token`, which mints a brand-new 1-hour token from the permanent
private key on the spot, uses it once, and discards it. Nothing is ever
cached or reused, so there's nothing to manually refresh — the next call,
whenever it happens, just repeats the same mint from scratch.
