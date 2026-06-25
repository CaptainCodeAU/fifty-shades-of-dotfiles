# Claude Code security surface (the agent's own model)

**Audience:** the principal / any agent who wants to know how Claude Code -- the agent
that edits these dotfiles -- is itself sandboxed and permissioned, separate from the
repo's SSH transport posture in [`SECURITY.md`](./SECURITY.md). Generic, public-safe.

**Scope:** Claude Code behaviour as captured in the 2026-06-25 investigation (host
v2.1.191, Opus 4.8 default). Marked **[official]** (Anthropic docs), **[verified]**
(checked this machine/session), or **[inferred]**. Release cadence is ~daily; re-check
`claude update` and the linked docs before trusting version-specific detail.

---

## 1. Permission modes [official]

Six modes; `Shift+Tab` cycles the first three:

| Mode                | Runs without asking                                                  | Notes                                                                                                                             |
| ------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `default`           | reads only                                                           | baseline                                                                                                                          |
| `acceptEdits`       | reads + edits + common FS Bash (`mkdir/touch/rm/mv/cp/sed`) in-scope | review after the fact                                                                                                             |
| `plan`              | reads only                                                           | research/propose, no edits                                                                                                        |
| `auto`              | everything, with a background classifier                             | NEW (v2.1.83+); a Sonnet-4.6 classifier blocks risky/escalating/hostile-driven actions; no longer needs opt-in consent (v2.1.152) |
| `dontAsk`           | only pre-approved tools                                              | NEW; CI-style -- denies (not prompts) anything else                                                                               |
| `bypassPermissions` | everything                                                           | containers/VMs only; no prompt-injection protection                                                                               |

Layer `permissions.allow`/`ask`/`deny` rules on top. Deny + explicit ask rules apply in
every mode incl. `bypassPermissions`. A repo cannot grant itself `auto`/`bypass`:
`defaultMode:"auto"` is ignored from project/local settings (must live in `~/.claude/`).

## 2. Protected paths -- the un-bypassable dotfile guard [official + verified 2026-06-25]

Writes to a fixed set of paths are NEVER auto-approved except in `bypassPermissions`:

| Mode                               | Protected-path write                                 |
| ---------------------------------- | ---------------------------------------------------- |
| `default` / `acceptEdits` / `plan` | prompted                                             |
| `auto`                             | routed to the classifier                             |
| `dontAsk`                          | denied                                               |
| `bypassPermissions`                | allowed (but `rm -rf /` and `rm -rf ~` still prompt) |

Critically, **neither `permissions.allow` rules NOR a `PreToolUse` allow-hook can
pre-approve a protected-path write** -- the guard runs before both (verified vs docs +
issue #41615). The guarded set: dirs `.git`, `.config/git`, `.claude`, `.cargo`,
`.husky`, `.vscode`, `.idea`, `.yarn`, `.mvn`, `.devcontainer`; files
`.zshrc/.zshenv/.zprofile/.zlogin/.bashrc/.bash_profile/.profile/.envrc`,
`.npmrc/.yarnrc/.yarnrc.yml/bunfig.toml/.pnpmfile.cjs`, `.gitconfig/.gitmodules`,
`.bazelrc`, `.pre-commit-config.yaml`, `.mcp.json/.claude.json`.

**Why this matters for a paranoid posture (the upside):** because a hook's `allow`
cannot silence the guard, a malicious project-supplied `.claude/settings.json` hook
CANNOT auto-approve writes to your `.zshrc`/`.npmrc`/`.gitconfig`. The one-keystroke
prompt on a deliberate dotfile edit is the floor, and it is tamper-resistant.
Trade-off: there is no scalpel to silence it for a single file -- only the
all-or-nothing `bypassPermissions`, which you should not use here.

## 3. The OS Bash sandbox [official]

A built-in sandbox runs most shell commands without per-command prompts (Anthropic
reports ~84% fewer prompts). Enable via `/sandbox` or `"sandbox.enabled": true`.

- **Enforcement:** macOS Seatbelt (no deps); Linux/WSL2 bubblewrap + socat. Native
  Windows unsupported.
- **Filesystem:** writes limited to CWD + session temp; **reads the whole machine by
  default -- including `~/.ssh` and `~/.aws`** unless restricted. Tune via
  `sandbox.filesystem.allowRead/denyRead/allowWrite/denyWrite`.
- **Network:** routed through an out-of-sandbox proxy; no domains pre-allowed (first use
  prompts). The proxy filters by hostname and **does NOT terminate TLS**, so a broad
  allow like `github.com` is domain-frontable. Lock down with `allowManagedDomainsOnly`
  or a real TLS-inspecting proxy.
- **`sandbox.credentials` (v2.1.187):** denies credential-file reads + unsets secret env
  vars for sandboxed commands. There is no built-in credential deny-list -- only what you
  list. The sandbox covers Bash only (Read/Write/Edit/Grep run with full perms).

**Recommendation for this repo (NOT yet adopted):** given the strict SSH posture and
Keychain-held tokens, enabling `sandbox.enabled` + `sandbox.credentials` closes the
"a sandboxed command reads `~/.ssh`" gap at near-zero cost on macOS (Seatbelt, no deps).

## 4. 2026 CVEs -- all patched below the installed v2.1.191 [official]

The host is past every patched version below; this is a "stay current" lesson, not a
current exposure:

| CVE                    | What                                                                                          | Fixed in               |
| ---------------------- | --------------------------------------------------------------------------------------------- | ---------------------- |
| CVE-2025-59536         | RCE via malicious **hooks in `.claude/settings.json`** on project load                        | trust-dialog hardening |
| CVE-2026-21852         | API-key exfil via malicious **`ANTHROPIC_BASE_URL` in repo settings** before the trust dialog | 2.0.65                 |
| CVE-2026-25722 / 25723 | protected-dir / write-restriction bypass (`cd`, piped `sed`)                                  | 2.0.57 / 2.0.55        |
| CVE-2026-39861         | **sandbox escape via symlink** -> RCE                                                         | 2.1.64                 |

The high-severity ones (CVE-2025-59536, CVE-2026-21852) are the untrusted-repo vector:
opening a booby-trapped repo. Keep trusting repos deliberately and keep Claude Code
current (the protected-paths guard in section 2 is what neutered the malicious-hook CVE).

---

## Sources

- Permission modes: <https://code.claude.com/docs/en/permission-modes>
- Sandboxing: <https://code.claude.com/docs/en/sandboxing> , <https://www.anthropic.com/engineering/claude-code-sandboxing>
- Auto mode: <https://www.anthropic.com/engineering/claude-code-auto-mode>
- Issue #41615 (allow-rules / PreToolUse hooks cannot override the protected-path prompt): <https://github.com/anthropics/claude-code/issues/41615>
- CVEs: GHSA-jh7p-qr78-84p7 (CVE-2026-21852); NVD CVE-2026-25723; GHSA-66q4-vfjg-2qhh (CVE-2026-25722); Check Point Research (CVE-2025-59536); SentinelOne (CVE-2026-39861)
- Full investigation report (local): `~/.claude/MEMORY/WORK/20260625-110731_claude-code-updates-investigation/PRD.md`

---

Complements [`SECURITY.md`](./SECURITY.md) (SSH transport posture) and
[`CLAUDE_CODE_RESEARCH_NOTES.md`](./CLAUDE_CODE_RESEARCH_NOTES.md) (behaviour & mechanics).
