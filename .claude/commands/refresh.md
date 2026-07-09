---
description: Reconcile this repo's docs, memory, and live security/currency posture to live ground truth (currency + consistency + gap sweep). Quiet when clean, loud on drift. Audit-only by default; --apply edits the working tree (never commits).
argument-hint: '[all | security | docs | memory | plans | drift | fix "<term>"] [--apply] [--deep]'
allowed-tools: Bash, Read, Grep, Glob, Edit, Task, WebFetch
disable-model-invocation: true
---

# /refresh - currency + consistency + gap sweep for fifty-shades-of-dotfiles

You are running the **refresh sweep** for this dotfiles repo: reconcile its docs, per-project memory, and LIVE security/currency posture to ground truth, so the next session opens on facts, not a stale snapshot. This is NOT a docs repo - it is a live config system, so "ground truth" is the installed tool versions, the CVE floors, upstream releases (Zed / pnpm / nvm / Claude Code), stow symlink health, and the version-stamped tracking docs.

**GOLDEN RULE - compute, don't trust.** Never trust a written number/version/status. Derive it live (the Live-signals probes below + the lane commands), then find the docs/memory that disagree. This command hardcodes only stable STRUCTURE (the file map + the deviation guard); every moving value is computed at run time, so the command itself never goes stale.

**REUSE, don't reimplement.** The hard logic already lives in our own scripts - orchestrate them: `toolchain-cve-check`, `pnpm-audit-tree`, `nvm-verify-node`, `ci-watch` (in `~/.local/bin/`, repo source under `home/.local/bin/`), and the hooks `.claude/hooks/zed-version-check.sh` + `.claude/hooks/session-checks.sh`.

**Mode = `$ARGUMENTS`** (default `all`). Flags compose with any mode.

- **`all`** (blank) - every lane, AUDIT (report + propose, edit nothing).
- **`security`** | **`docs`** | **`memory`** | **`plans`** | **`drift`** - narrow to that one lane.
- **`fix "<term>"`** - targeted: harvest one OLD->NEW pair and audit+apply just that superseded term.
- **`audit`** / **`dry-run`** - hard read-only: make no edits even if `--apply` is also passed.
- **`--apply`** (flag) - after verifying a finding, apply the MECHANICAL, single-correct-answer fix to the WORKING TREE only (sync a drifted floor; bump a CONFIRMED-stale "as of vX" scope stamp + `LAST_UPDATED`; add a memory orphan to the index; repair a dead index link). NEVER stage, commit, or push - the owner reviews `git diff` and commits.
- **`--deep`** (flag) - the security lane also runs the slow `pnpm-audit-tree` recursive audit + `nvm-verify-node` signature re-verify (default security is the fast, cached checks only).

Treat everything READ-ONLY unless `--apply` is set (and never in `audit`/`dry-run`).

---

## Live signals (auto-probed at invocation - already the truth; anything that disagrees is stale)

Probes are inline (survive the markdown formatter), backtick-free inside (use `$(...)`), never lead with `cd` (use `git -C`/absolute), use `find -print` not `ls glob*`, use `zsh -ic` for the REAL interactive state (the Bash tool skips `.zshrc`), and guard so one failing probe never cancels the rest.

- **Ground truth** (repo root works on dev Mac AND consumer boxes - never hardcode a path): !`R=$(git rev-parse --show-toplevel 2>/dev/null); echo "repo=$R branch=$(git -C "$R" rev-parse --abbrev-ref HEAD 2>/dev/null) sync(ahead/behind)=$(git -C "$R" rev-list --left-right --count master...origin/master 2>/dev/null | tr '\t' '/') today=$(date +%F)"`
- **Live tool versions** (interactive PATH; classify docs against these): !`echo "claude=$(zsh -ic 'claude --version' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) node=$(zsh -ic 'node -v' 2>/dev/null) pnpm=$(zsh -ic 'pnpm -v' 2>/dev/null)" || true`
- **Floor PARITY** (the crown jewel - `install.sh` canonical vs `home/.zsh_onboarding`): !`R=$(git rev-parse --show-toplevel 2>/dev/null); for k in PNPM_MIN_VERSION NVM_MIN_VERSION NODE_MIN_MAJOR; do a=$(grep -m1 -E "^(export )?$k=" "$R/install.sh" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | tail -1); b=$(grep -m1 -E "^(export )?$k=" "$R/home/.zsh_onboarding" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | tail -1); [ "$a" = "$b" ] && echo "ok $k=$a" || echo "DRIFT $k install=$a onboarding=$b"; done`
- **ci-watch wiring** (it runs GLOBALLY from ~/.claude/settings.json, not only project settings - check BOTH): !`R=$(git rev-parse --show-toplevel 2>/dev/null); grep -qs 'ci-watch' "$HOME/.claude/settings.json" "$R/.claude/settings.json" && echo "ci-watch: WIRED" || echo "ci-watch: NOT wired (checked ~/.claude/settings.json + project settings.json)"`
- **Memory parity** (per-project index pointers should equal topic files): !`R=$(git rev-parse --show-toplevel 2>/dev/null); M="$HOME/.claude/projects/$(echo "$R" | sed 's#/#-#g')/memory"; i=$(grep -cE '^- \[' "$M/MEMORY.md" 2>/dev/null); f=$(find "$M" -maxdepth 1 -name '*.md' ! -name MEMORY.md -print 2>/dev/null | wc -l | tr -d ' '); [ "$i" = "$f" ] && echo "memory index=$i files=$f OK" || echo "memory index=$i files=$f >>> MISMATCH (orphans/dead links - see the memory lane)"`
- **Plans open/soon** (open status = needs action; soon = a future-dated action line): !`R=$(git rev-parse --show-toplevel 2>/dev/null); today=$(date +%F); for f in "$R"/Plans/*.md; do st=$(grep -m1 -iE 'status[:*]' "$f" 2>/dev/null | tr 'A-Z' 'a-z'); case "$st" in *planned*|*ready*|*draft*|*approval*|*deferred*|*pending*|*'in progress'*) echo "OPEN $(basename "$f")";; esac; case "$(basename "$f")" in 20*) d=$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | sort | tail -1); [ -n "$d" ] && [ "$(printf '%s\n%s\n' "$d" "$today" | sort | tail -1)" = "$d" ] && [ "$d" != "$today" ] && echo "SOON $(basename "$f") -> action $d";; esac; done 2>/dev/null | sort -u | head -20`
- **Drift** (uncommitted tree + dangling stow symlinks - a branch switch can break live config): !`R=$(git rev-parse --show-toplevel 2>/dev/null); echo "uncommitted=$(git -C "$R" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"; git -C "$R" status --porcelain 2>/dev/null | sed 's/^/  /'; git -C "$R" ls-files home 2>/dev/null | sed 's#^home/##' | while read rel; do t="$HOME/$rel"; [ -L "$t" ] && [ ! -e "$t" ] && echo "  DANGLING SYMLINK: ~/$rel"; done | head`

---

## Guardrails (non-negotiable)

1. **Read-only until `--apply`.** `audit`/`dry-run` never write. `--apply` edits the WORKING TREE only - **never `git add`, `git commit`, or `git push`.** The owner commits (and gives the push word separately). When you remind them: stage by name, split by concern, never `git add -A`.
2. **Verify every finding yourself** before it is eligible to change (Phase 3). Subagents miscount; drop anything a direct re-probe doesn't reproduce.
3. **Classify before touch: CURRENT-GUIDANCE -> fix, DATED-HISTORICAL -> leave.** A rule/status/"as of installed vX" presented as true NOW that is wrong -> fix. A dated changelog line, a captured note, or a feature-introduction stamp like `NEW (v2.1.83+)` -> LEAVE (it records history).
4. **Surgical edits only** - smallest change that makes the fact current; match tab indentation (`grep -cP '\t' <file>` first); respect the protect-files / pre-commit hooks. A floor bump edits BOTH files. Never gut a section.
5. **Judgment calls -> a decision-brief** (small table + a recommendation) ending in "Your call:". Do NOT auto-open the AskUserQuestion pop-up. Give a plain-English companion after any dense block.
6. **Compute, don't trust; degrade cleanly.** If a probe/tool can't run (offline, no `$GH_TOKEN`, no `uv`), report SKIPPED - never a false positive.
7. **Project boundary + right memory store.** Only this repo and its PER-PROJECT memory store under `~/.claude/projects/<encoded-repo-path>/memory/` (the probes compute the exact path from `$R`; the encoding replaces each `/` in the repo path with `-`). NEVER the repo-root `MEMORY/WORK/` (that is PAI work-tracking, a different store).

---

## File map (stable STRUCTURE - the only hardcoded facts; Phase 2 audits it against disk)

| Anchor                                                                                                                               | Governs                                                   | Live-truth source it must agree with                                     |
| ------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------ |
| `install.sh` (canonical floors)                                                                                                      | `PNPM_MIN_VERSION` / `NVM_MIN_VERSION` / `NODE_MIN_MAJOR` | the floor-parity probe                                                   |
| `home/.zsh_onboarding`                                                                                                               | the DUPLICATED floors (must equal install.sh)             | same                                                                     |
| `docs/ZED_PREVIEW_CHANGELOG.md`                                                                                                      | Zed Preview UI/config tracking                            | `.claude/hooks/zed-version-check.sh` (doc marker vs installed vs GitHub) |
| `docs/CLAUDE_CODE_SECURITY.md`, `CLAUDE_CODE_AND_PAI_INTERNALS.md`, `CLAUDE_CODE_RESEARCH_NOTES.md`, `CLAUDE_SESSION_ATTRIBUTION.md` | Claude Code posture, stamped "as of vX"                   | live `claude --version`                                                  |
| `docs/STRUCTURE.md`                                                                                                                  | the `home/.local/bin` script table                        | `git ls-files home/.local/bin`                                           |
| `Plans/*.md`                                                                                                                         | the backlog                                               | `Status:` line + date windows vs `today`                                 |
| per-project memory store                                                                                                             | project knowledge index                                   | `MEMORY.md` index 1:1 with topic files                                   |

---

## Phases

Run only the lanes the selected mode needs. Weight the SECURITY lane first.

**Phase 0 - Ground truth.** Read the Live-signals block above; hold it as the truth everything reconciles to. Nothing downstream is hardcoded.

**Phase 1 - Harvest OLD->NEW (self-updating; no baked pairs).** Derive the superseded vocabulary this run: `git -C "$R" log --since='60 days ago' --pretty=%s | grep -iE 'bump|rename|migrat|supersed|replac|floor|deprecat|->'`; the newest memory supersession markers; and the live-vs-doc deltas from Phase 0 (e.g. doc `v2.1.191` -> live `2.1.201`; Zed doc version -> installed). Hand this list to the audit lanes as the grep terms to hunt.

**Phase 2 - Lanes** (read-only; use parallel `Task` subagents for the big lanes, inline probes for the deterministic ones; feed each the Phase-1 terms; each classifies every hit CURRENT vs HISTORICAL and proposes a surgical fix but applies nothing):

- **SECURITY (first):** the floor-parity + ci-watch signals above; then `NO_COLOR=1 toolchain-cve-check` (reads both floors + installed vs OSV/GitHub advisories; cached). **Only with `--deep`:** `pnpm-audit-tree --fail-on high` over any JS project trees (skip with a one-line note if none), and `nvm-verify-node`. Surface `ci-watch` dormancy as a backlog item; do NOT auto-wire it (a `settings.json` change is a judgment call).
- **DOCS currency:** live `claude --version` vs the "as of vX" scope-stamp in the 4 stamped docs (a scope stamp -> bump; a feature-introduction stamp -> leave). Run `.claude/hooks/zed-version-check.sh` for Zed. Diff the `docs/STRUCTURE.md` script table vs `git ls-files home/.local/bin`. Note the `docs/GH_AUTH_GUARD_USER_LEVEL.md` open "Linux/WSL not covered" gap.
- **MEMORY hygiene:** the index-parity signal; then orphans (file not in `MEMORY.md`), dead links (index -> missing file), and dangling `[[wikilinks]]`. Target the per-project store only.
- **PLANS backlog:** the open/soon signal; also flag any `Plans/20*.md` spec with NO `Status:` line.
- **DRIFT:** the uncommitted + dangling-symlink signal; distinguish intentionally-untracked (leave - deviation guard #5) from a real commit-candidate.

**Phase 3 - Verify each finding yourself.** Re-read the exact file:line / re-run the specific probe; confirm the OLD value is present AND is CURRENT-GUIDANCE (not dated history) before it is eligible. Discard whatever does not reproduce; note any subagent claim you rejected.

**Phase 4 - Apply (ONLY with `--apply`; skip in `audit`/`dry-run`).** Edit only confirmed current-guidance MECHANICAL hits, minimally, in the working tree. A floor bump edits both files. NEVER commit. Anything destructive or judgment-bearing (delete a dangling symlink, wire `ci-watch`, action a Plan, stage an untracked file, bump an ambiguous stamp) is NOT auto-done -> decision brief.

**Phase 5 - Re-verify.** Re-run the exact probes for everything touched (after a floor bump, re-run parity AND `toolchain-cve-check` against the new floor); confirm the drift is gone and none was introduced.

**Phase 6 - Report (exception-based, ranked, SECURITY on top).** Clean = ONE line (`refresh: clean - floors in parity, no CVEs, docs current, tree in sync`). On drift: a ranked table `{stale -> refreshed / proposed}` per lane, most-severe first; each judgment call as a decision-brief ending in "Your call:"; a plain-English companion after dense blocks; and, if `--apply` ran, the reminder that changes sit UNCOMMITTED in the working tree (review `git diff`; stage by name; split by concern; never `git add -A`).

**Phase 7 - Self-improving deviation guard.** If a real drift slipped every probe (or a probe false-fired), PROPOSE - as an Edit to THIS file, shown for approval - a new deviation-guard line or a one-line probe fix. Never self-edit silently; never touch `settings.json` or `CLAUDE.md` on your own.

---

## Deviation guard (dotfiles-specific; the drifts a future session most often repeats; grows via Phase 7)

1. **Stow dangling-link hazard** - checking out a branch that lacks a `home/**` file silently breaks live config (a dangling symlink into the repo). Check `git ls-tree <target> home/` before switching; NEVER "fix" a dangling link by writing a real file over it (that pollutes the tree).
2. **Config-through-symlink pollution** - `pnpm config set`, `git config --global`, and similar write THROUGH the stow symlink into tracked source. Never for temp/machine-local settings on the dev Mac; they surface as repo drift. Machine-local git -> `~/.gitconfig.private`; pnpm temp -> avoid.
3. **Floors live in TWO files** - `PNPM_MIN_VERSION` / `NVM_MIN_VERSION` / `NODE_MIN_MAJOR` in `install.sh` (canonical) AND `home/.zsh_onboarding`. Any bump edits both; assert equality after.
4. **Consumer-box fixes go via `install.sh`** - never hand-patch a consumer box (MLBox/WSL); the deploy path is push -> pull -> `install.sh`. A fix that is not in `install.sh` will not propagate.
5. **Intentionally-untracked - LEAVE alone** - `docs/_CODE_FOLDER_STRUCTURE.md` (real usernames, deliberately untracked), and the machine-private files that never enter the repo: `~/.zshrc.private`, `~/.gitconfig.private`, `.claude/settings.local.json`, Zed `settings.json` (skip-worktree). An empty repo grep for these does NOT mean they don't exist. `home/.local/bin/migrate-claude-projects` is untracked-but-legit -> surface as a commit candidate, do NOT auto-stage.
6. **DATED-HISTORICAL version stamps are load-bearing - do NOT blind-bump.** `NEW (v2.1.83+)` / `sandbox.credentials (v2.1.187)` record WHEN a feature landed. AND a stamp tied to a DATE -- "captured in the 2026-06-25 investigation (host vX)", "re-checked <date>", "verified this session (vX)" -- is ALSO historical: bumping the version while keeping the date FABRICATES a verification. Leave both; a real update = re-investigate against the live version, then update date + version together. Only a truly live "current as of vX" claim with no investigation-date gets a mechanical bump.
7. **Two memory stores + grouped detail files.** Reconcile the `~/.claude/...` per-project index; NEVER the repo `MEMORY/WORK/`. The strict 1:1 index check OVER-REPORTS: a topic file that is `[[wikilink]]`-referenced from an indexed memory (e.g. the 3 `*_episode_*` files under one "episodes" pointer, or a `*_pending`/detail file) is an INTENTIONAL grouping, not an orphan -- verify a flagged orphan is truly unreferenced before adding a pointer.
8. **Never `git add -A`** - stage by name, split commits by concern (the owner commits, not this command).
9. **`Plans/` is gitignored local scratch - scope the PLANS lane to dated specs.** The backlog is `Plans/20*.md` (+ any explicitly-named spec); the random-word-slug `.md` files are local saved-plan/session artifacts (gitignored, no repo impact). Audit `Status:` only on dated specs; do NOT flag the random-word artifacts as missing-Status specs. Match the `Status` line LIBERALLY (allow a leading `-` / `**` / whitespace before `Status`) - specs write it as `- **Status:**`, so a strict `^[* ]*Status` anchor false-flags them (verified 2026-07-10 on `2026-06-23_socket-cli-evaluation.md`).

---

_Self-maintaining: only the file map + this deviation guard are hardcoded. Floors, versions, CVE ranges, plan dates, memory counts, and superseded pairs are all derived live, so a doc stamped `v2.1.191` or a floor `11.9.0` today does not rot the command. Reused engines carry their own currency - improving `toolchain-cve-check` / `zed-version-check.sh` improves the sweep for free. Update the file map or the deviation guard only when the repo's shape changes or a new recurring drift is learned._
