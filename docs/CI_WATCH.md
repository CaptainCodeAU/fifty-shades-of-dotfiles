# ci-watch — an escalating, un-ignorable CI-status line in the session dashboard

A red CI that nobody notices is as useless as no CI. This watcher puts the CI
status of repos you care about into the session-start dashboard — alongside the
[Zed-PR](ZED_PREVIEW_CHANGELOG.md) and [toolchain-CVE](TOOLCHAIN_CVE_CHECK.md)
watchers — and is built so a red result **cannot become wallpaper**.

## Why it exists

A sibling repo's CI was red for ~25 commits and nobody noticed — not because there
was no signal, but because the signal (GitHub "workflow failed" emails) was
**passive and identical every time**, so it habituated and got tuned out. Passive,
repeating alerts fail. The fix has to be **exception-based** (silent when fine, loud
when broken), **escalating** (louder the longer it stays broken), and
**dismiss-only-by-fixing** (you can't make it go away just by seeing it).

## What it does

| State | Meaning | Surface |
| --- | --- | --- |
| **green** | asked GitHub just now, it said success | one dim, near-invisible line |
| **red, day 0-2** (tier 1) | asked just now, it said failure | a red banner |
| **red, day 3-6** (tier 2) | as above, longer | a louder boxed banner **+ a spoken alert** |
| **red, day 7+** (tier 3) | as above, longest | the strongest banner + a spoken alert every session |
| **running / inconclusive** | observed, but the run is in progress, cancelled, skipped or neutral | one dim line naming the conclusion |
| **no runs yet** | observed, the repo has never run a workflow | one dim line |
| **STALE** | a transient failure (timeout, network); showing the last observation **with its age** | one dim line, value + age + reason |
| **BLIND** | it used to be observable and is now **refused** (403/404/401) | a loud magenta banner + the remedy; **self-clears** on the next success |
| **UNOBSERVABLE** | never successfully observed; the setup is incomplete | one quiet dim line |
| **branch gone** | the watched branch no longer exists **and a positive control proved the token can read branches** | a loud magenta banner + the re-point command |
| **snoozed** | deliberate, time-boxed | a single dim "snoozed Nd" line |

Key properties:

- **Dismiss-only-by-fixing.** A red banner clears **only** when CI goes green, or when
  you run a deliberate `ci-watch --snooze`. Merely seeing it never clears it — that is
  the whole point (a persistence counter alone still habituates; "day 12, whatever").
- **Voice varies by day count** ("…red for 4 days") and fires on the green→red
  transition, so the audio itself doesn't become monotone wallpaper.
- **Offline-sticky.** A transient network/`gh` outage does not silence a known red —
  the last-known-red banner persists, flagged stale, until a definite green clears it.
- **A cached value can never render as a live green** (rewritten 2026-09-15 — see below).
  Only a successful fetch writes the freshness stamp, so a failed refresh is
  structurally incapable of marking data fresh; any value shown from cache carries
  its age; past `CI_WATCH_HARD_TTL` (7d) no value is shown at all, only the reason.
- **The promise is proven every run, not asserted.** `ci-watch --control` renders a
  target that must not come out green, and exits non-zero if it does.

## The false green this was rewritten to kill (2026-09-15)

The original query path ended both fetch attempts in `2>/dev/null || true`. That
destroys the evidence three times over: `2>/dev/null` deletes the diagnosis,
`$(...)` collapses any failure into an empty string, and `|| true` forces a zero
exit. A 403, a 404, a timeout, a malformed body and a genuinely empty result all
arrived as the same empty string and became `unknown`.

Worse, an empty result fell back to the per-target cache and the **green** render
path threaded no staleness marker — so a repo that went green and then lost
Actions access rendered `OK CI green -- <label> (<sha>)` **forever**, identical to
a live green. Reproduced by execution before any fix was written: the same command
twice against a target whose fetch fails, one variable changed (a planted cache).

```
no cache planted  ->  .. CI unknown -- REPRO-403-target (no runs / offline)
cache planted     ->  OK CI green  -- REPRO-403-target (deadbee)
```

The doc used to promise "a skip is never a false green". It was wrong.

**What the fix borrows, and from whom.** Ubuntu's `apt` update notifier writes its
freshness stamp from a **success-only** hook, which is why `fetched_at` moves on
`ok`/`empty_ok` and on nothing else. Prometheus writes scrape health (`up`) as a
series separate from the payload and, since 2.0, marks a stale series explicitly
rather than carrying the last value forward — Prometheus 1.x had this exact bug.
RFC 5861 says a stale response SHOULD be "visibly stale"; RFC 9111 raised the age
marking to a MUST. Nagios/Icinga carry a fourth state because "the check could not
decide" is not "the thing is bad" and is really not "the thing is fine".

**Two traps found by running it against the real API, which no stub had caught:**

1. A real runs payload contains `"status":"completed"` on the run and a `"message"`
   on `head_commit`. Reading those as an HTTP status and an API error turned a
   healthy 200 into `HTTP completed: <the whole commit message>`.
2. **A 404 from `/branches/{b}` is not proof the branch is gone.** Measured: the
   endpoint returned 404 for a branch that was alive and green in the same breath,
   because the token can read Actions but not Contents and GitHub 404s rather than
   confirm a private resource exists. Shipping "branch gone" on a bare 404 would
   have invented a new false alarm to replace the false green. So the 404 path now
   runs a **positive control** against the repo's default branch: control hits, the
   404 is real; control misses, the honest answer is "cannot confirm".

**The parser is gone (2026-09-15, same day).** Three of the day's bugs came from
one cause: a hand-rolled bash-regex JSON reader. It read `"status":"completed"`
off a run object as an HTTP status, it truncated the run object at the first `}`
so a commit titled `fix: handle {} in the parser` turned a RED build into a quiet
"running", and its numeric guard let a leading-zero value abort the whole render.

`gh run list --json` already has the contract the rewrite spent a day
hand-building (measured against the real API, gh 2.98.0):

```
failure (404 / 401 / network)  ->  exit 1, stdout EMPTY, reason on stderr
no matching runs               ->  exit 0, stdout []
real runs                      ->  exit 0, stdout [{...}]
```

Failure and "nothing to report" can never be confused. So the fetch layer now
calls `gh run list --json conclusion,status,headSha,url --jq ...` and gh owns the
JSON. This adds no dependency: `gh --jq` embeds a Go jq and works with an emptied
PATH, and `gh` was already required to reach the API at all. What is lost is the
structured error body -- gh reports the reason as prose on stderr -- so the
classifier reads a status code out of prose, which is a far safer regex surface
(no nesting, no escaping, no user-controlled field), and an unrecognised message
degrades to the quiet register rather than guessing.

**Four more defects, all found AFTER the first fix looked finished.** Two
independent audits and one live run produced these, in the order they were fixed:

1. **Dismiss-by-cancel.** The rewrite folded every successful observation through
   one branch: if it is not red, clear the alarm. That `else` also caught
   `cancelled`, `neutral`, `skipped`, `in_progress` and "no runs" — so cancelling
   a workflow wiped a multi-day red alarm and the next real failure restarted at
   "red for 0d". Only a **green** clears the alarm now, and an unfixed red keeps
   its banner on screen even when the newest run is inconclusive.
2. **A brace in a commit title hid a red build.** The run object was grabbed by
   cutting at the first `}`, and GitHub orders the object with the commit title
   BEFORE the status fields, so `fix: handle {} in the parser` truncated it and a
   RED build rendered as a quiet "running". Combined with (1), a commit message
   could dismiss a CI alarm.
3. **One bad byte muted the whole dashboard.** bash reads a leading zero as octal,
   so a state value of `08` is an invalid arithmetic expression — and that aborts
   the script. Every target after the corrupt one silently vanished, at exit 0.
   Fixed three ways: strip leading zeros, force `10#` at every site reading stored
   input, and render each target in a subshell so no future bad row can end the
   loop.
4. **The branch-liveness check is silently inert on private repositories.**
   `/repos/{o}/{r}/branches/{b}` requires **Contents: read**, which a deliberately
   source-free token does not have, so it returns 403 on every private repo and
   the check never fires (`--json` shows `branch_alive:"?"`). `git ls-remote
   --heads <remote> refs/heads/<branch>` answers the same question instantly over
   SSH, and finding this turned up a real watch pointed at a branch that had been
   deleted while the API still served its runs. Replacing the API check with
   `git ls-remote` is recorded as follow-up work.

**Whose credential answered.** The tool inherits the caller's `GH_TOKEN`, so its
output depends on who runs it — and in an interactive shell here `gh` is a
function that injects a different token again (see CLAUDE.md § Git & GitHub auth).
Every refusal line and the `--json` output now name the credential in use, because
"no Actions scope" is useless advice if it sends you to fix a token that was never
the one being used. The tool deliberately does **not** retry with `GH_TOKEN`
unset: that path lands on a broader credential, and a watcher must report that it
cannot see rather than reach for a bigger key.

**Testing.** `ci-watch-selftest` (125 assertions) was written BEFORE the rewrite and
run red against the old tool first. Every failure-path case ships with its
success-path twin, because every assertion here is about an absence and an absence
reads identically whether the mechanism worked or the test never ran. The suite's
own negative control is the old binary: `CI_WATCH_TOOL=$(git show <pre-fix>:...)`
must still fail (it does, 36 cases).

## How it runs

- **Engine:** `home/.local/bin/ci-watch` (bash, stow-deployed to `~/.local/bin`).
  Read-only to your repos; the only writes are escalation state under
  `${XDG_STATE_HOME:-~/.local/state}/ci-watch/`. Queries `gh` live each session and
  falls back to a per-target cache when offline. The render path always exits 0.
- **Wiring (global, the active setup):** a `SessionStart` hook in **`~/.claude/settings.json`**
  runs `~/.local/bin/ci-watch` (guarded: `test -x … && … || true`), so the dashboard appears
  in **every** repo's session — not just this one. `~/.claude` is machine-local and untracked,
  so this hook is a one-time manual add, not versioned here.
- **Wiring (per-project, optional):** call the engine directly from any project's
  `.claude/settings.json` `SessionStart` if you want per-repo wiring instead of (or
  before) the global hook:
  `test -x "$HOME/.local/bin/ci-watch" && "$HOME/.local/bin/ci-watch" || true`.
  A `.claude/hooks/ci-watch.sh` wrapper existed for this from 2026-06-28 (`7e39550`)
  until 2026-08-01 (`9efc563`); it was removed once ci-watch went global, because its
  repo-source fallback only ever resolved inside the dotfiles repo. Recover it from
  git if per-repo wiring ever becomes the norm.
- **Self-suggest:** in any repo that has `.github/workflows` but isn't on the watchlist, the
  render adds one dim line — `untracked CI: <owner/repo> … add: ci-watch --add .` — so a
  coverage gap surfaces itself instead of relying on anyone to remember.

```bash
ci-watch                       # render the dashboard line (what the hook runs)
ci-watch --add .               # add the CURRENT repo (derives owner/repo@branch)
ci-watch --add <o/r@branch> "label"   # add a specific target
ci-watch --snooze <repo> <d>   # deliberately silence a red target for <d> days
ci-watch --list                # show the watchlist
ci-watch --json                # machine-readable status per target
ci-watch --control             # prove the watcher cannot report a false green
ci-watch-selftest              # the full suite (125 assertions, no network)
```

`gh` advisory: the live query needs `gh` + `$GH_TOKEN`, which are present **inside
Claude Code sessions** (the read-only token from `_claude_launch`). In a plain shell
without them, the watcher reports a one-line _skipped_ and never errors — a skip is
never a false "green".

## The watchlist (privacy)

The engine is generic and committed. Your **real** repo list is machine-local and
**gitignored** — the repo is public, and real `owner/repo` names must never land in
it (the same rule as [`~/.ssh/config.local`](../docs/SECURITY.md)).

- Committed, placeholders only: `home/.config/ci-watch/watchlist.example`
- Real, gitignored, never committed: `~/.config/ci-watch/watchlist`

```text
# ~/.config/ci-watch/watchlist  (one target per line)
owner/repo@branch | optional label
owner/repo                       # omit @branch -> latest run on any branch
```

`home/.config/ci-watch/watchlist` is in `.gitignore`, so even a copy placed in the
stow source tree can't be committed by accident.

## Companion change: worktree hook fallback (`_audit-chain`)

Shipped in the same change: the global git-hook dispatcher
(`home/.config/git/hooks/_audit-chain`) now falls back to the **common-dir** hook when
a linked `git worktree` has no per-worktree hook. Previously a hook installed in the
main checkout silently did **not** run for commits made from a worktree (its
`--git-dir` is `.git/worktrees/<name>`, whose `hooks/` is empty). The fallback lets a
worktree **inherit** an explicitly-installed hook.

It only ever runs a hook you **deliberately installed** — it does **not** make the
dispatcher "pre-commit aware" (auto-running a repo's `.pre-commit-config.yaml` on
commit would execute any cloned repo's hook code = supply-chain RCE). The
explicit-install opt-in is a security property and is preserved.

## Related

- [`TOOLCHAIN_CVE_CHECK.md`](TOOLCHAIN_CVE_CHECK.md) — sibling session-start watcher
  (CVE exposure of pinned tool floors).
- [`ZED_PREVIEW_CHANGELOG.md`](ZED_PREVIEW_CHANGELOG.md) — the live "watched PRs"
  pattern this query path mirrors.
- [`CLAUDE_SESSION_ATTRIBUTION.md`](CLAUDE_SESSION_ATTRIBUTION.md) — the `_audit-chain`
  dispatcher whose worktree fallback shipped alongside this.
