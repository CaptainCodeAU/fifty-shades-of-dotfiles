# Claude Code - Researched Behaviour & Mechanics (living notes)

**Audience:** the principal and any agent working on PAI / dotfiles who needs to
know how Claude Code actually _behaves_ - how instructions load, how hooks
enforce, how the terminal renders markdown, and why a loaded rule is not the same
as a followed rule.

**Relationship to other docs:** `CLAUDE_CODE_AND_PAI_INTERNALS.md` is the
_structural_ reference (what lives under `~/.claude/`, the three-system model, the
PAI hook-event table, migration blast radius). This file is the _behavioural_
reference: empirical and doc-verified findings about loading, enforcement, and
rendering. Where the two overlap (e.g. the SessionStart load chain) this file
points back rather than restating.

**Status:** living document - append findings over time with a dated entry in the
Update Log at the bottom. Mark each fact as **[official]** (from Anthropic docs),
**[verified]** (checked against live code/behaviour this machine), or
**[inferred]**.

**Privacy:** committed to the public repo (`451d8eb`), unlike the still-untracked
`CLAUDE_CODE_AND_PAI_INTERNALS.md`. Keep it public-safe: scrub absolute user paths
(use `~/`) and never include credentials, real LAN hosts, or secrets. The Claude Code
findings below are generic and public-safe.

**Last updated:** 2026-06-25

---

## 1. Instruction & memory loading [official]

Source: Anthropic memory docs (`https://code.claude.com/docs/en/memory`).

- **CLAUDE.md is context, not enforced config.** Verbatim: it "is delivered as a
  user message after the system prompt, not as part of the system prompt itself...
  there's no guarantee of strict compliance." To block an action regardless of
  what the model decides, "use a PreToolUse hook instead."
- **Hierarchy / load order** (broadest to most specific; specific is read _last_,
  so it wins): managed policy > user (`~/.claude/CLAUDE.md`) > project
  (`./CLAUDE.md` or `./.claude/CLAUDE.md`) > local (`CLAUDE.local.md`).
- **Eager vs lazy:** CLAUDE.md / CLAUDE.local.md in the directory hierarchy _above_
  the working dir load in full at launch. Files in _subdirectories_ load on demand
  when the model reads files there.
- **`@path` imports: maximum recursion depth is FOUR hops** (official, verbatim:
  "maximum depth of four hops"). The "five hops" figure seen in community blogs is
  wrong/outdated. Imports still load into the context window at launch - `@import`
  is for organisation, NOT token savings.
- **Auto-memory (`MEMORY.md`):** the first 200 lines OR first 25KB (whichever comes
  first) load each session; topic files are lazy (read on demand).
- **`.claude/rules/*.md`:** loaded at launch (or only when matching files are
  opened, if they carry `paths:` frontmatter).
- **Adherence lever (official):** "the more specific and concise your instructions,
  the more consistently Claude follows them." This endorses tightening wording as
  the cheap first move before reaching for hooks.

Takeaway: CLAUDE.md, `.claude/rules`, and PAI steering rules are all _nudges_. Only
hooks _enforce_.

---

## 2. Hooks - enforcement & injection mechanics [official + verified]

Sources: Anthropic hooks docs (`https://code.claude.com/docs/en/hooks`), GitHub
issues, and reading the local PAI hooks. For the PAI-specific event->hook table see
`CLAUDE_CODE_AND_PAI_INTERNALS.md` section 4.2.

- **SessionStart context injection [official]:** a SessionStart hook adds context
  _either_ via plain **stdout** ("any text your hook script prints to stdout is
  added as context") _or_ via JSON `hookSpecificOutput.additionalContext`. A hook
  that only loads context can just print to stdout.
- **Stop hook can block & force a retry [official, via claude-code-guide]:** return
  `{"decision":"block","reason":"..."}` (exit 0) or `exit 2` (stderr becomes the
  reason). It receives `transcript_path` (JSONL) and the final assistant text.
  `stop_hook_active` exists to prevent infinite loops - the safe pattern is "block
  once on the first pass, allow on the retry," so in practice it gives ONE forced
  correction, not unlimited. Stop has no matcher; it always fires.
- **`InstructionsLoaded` hook [official]:** fires when a _native_ `CLAUDE.md` or
  `.claude/rules/*.md` file loads. It does **not** fire for content a custom hook
  injects via stdout - so it cannot observe the PAI `loadAtStartup` injection. To
  observe PAI loads, use the loader's own per-file log instead (see section 3).
- **Known issues:**
  - **#16538** (`closed` / `not_planned`): "Plugin SessionStart hooks don't surface
    `hookSpecificOutput.additionalContext` to Claude." Only affects hooks defined
    in a _plugin_ that inject via the `additionalContext` field; the hook runs but
    the text is dropped (Claude sees only a generic success message). A hook in
    user `settings.json` that injects via **stdout** is immune on both counts.
  - **#10373** (`OPEN`): "SessionStart hooks not working for new conversations." A
    latent risk; not currently observed (SessionStart hooks demonstrably fire).

- **New hook events (2026-06) [official]:** `MessageDisplay` (v2.1.152, display-only),
  `ConfigChange`, `CwdChanged`/`FileChanged`, `WorktreeCreate`/`WorktreeRemove`, and a
  self-hosted-runner `post-session` hook (v2.1.169). `Stop`/`SubagentStop` can now
  return `hookSpecificOutput.additionalContext` (v2.1.163) to feed Claude and continue
  the turn; `SessionStart` can set `reloadSkills:true` and `sessionTitle` (v2.1.152).
- **A hook can DENY but cannot force-ALLOW a protected path [official + verified 2026-06-25]:**
  a `PreToolUse` hook returning an `allow` decision is honoured for ordinary files, but
  writes to protected paths (`.zshrc`/`.zshenv`/`.envrc`/`.npmrc`/`.yarnrc`/`bunfig.toml`/
  `.gitconfig`/`.mcp.json`/`.claude` etc.) are NEVER auto-approved by a hook OR by
  `permissions.allow` -- only `bypassPermissions` skips that prompt. The guard runs before
  allow-rules and hook decisions (verified vs docs + issue #41615). Upshot: hooks are
  strong for blocking, powerless for granting protected-path writes -- so a malicious
  repo-supplied hook cannot auto-approve edits to your dotfiles. See section 6.

Determinism summary: only hooks give a hard guarantee, and only for tool-call
gating (PreToolUse deny) or a structural string check on output (Stop-hook
marker) -- and even a hook cannot force-approve a protected-path write. No mechanism
can deterministically guarantee the _meaning/quality_ of free-form prose.

---

## 3. PAI `loadAtStartup` loader - internals & silent drop points [verified]

Verified by reading `~/.claude/hooks/LoadContext.hook.ts` and `lib/paths.ts`.
Cross-ref `CLAUDE_CODE_AND_PAI_INTERNALS.md` section 4.4 for the broader load chain.

- **`loadAtStartup` is a PAI-custom settings key, NOT native Claude Code.** Claude
  Code silently ignores the unknown top-level key; only PAI's `LoadContext.hook.ts`
  (registered on the documented `SessionStart` event) consumes it.
- **`loadStartupFiles()` is a flat read:** a `for` loop over `loadAtStartup.files`
  (an explicit array), each entry `existsSync` -> `readFileSync` -> `trim` ->
  concatenated with `---`, then printed as ONE `<system-reminder>` to **stdout**
  (`console.log`). No recursion, no `@import` expansion, no hop limit, no token
  budget. (So the 4-hop import cap is irrelevant here - there are no hops.)
- **`getPaiDir()`** = `PAI_DIR` env var, else `~/.claude` fallback.
- **Every failure mode is SILENT** because all warnings go to **stderr**, and
  SessionStart only injects **stdout**. Drop points, most-likely first:
  1. **File missing at the startup snapshot** (`existsSync` false -> `continue`).
     The list is read once, at session start, so a file created _mid-session_ will
     not appear until the next session. Deterministic, not a race.
  2. **Malformed `settings.json`** (`JSON.parse` throws -> returns `{}` ->
     `loadAtStartup` undefined -> ALL files dropped). One stray comma blacks out
     every rule.
  3. **Wrong/unset `PAI_DIR`** (wrong base path -> all "not found"; or the hook
     _command_ path `${PAI_DIR}/hooks/LoadContext.hook.ts` breaks and the hook
     never runs - the in-code `~/.claude` fallback can't save a broken command).
  4. **Read error** on an existing file (`continue`, skipped).
  5. **Any throw before the inject line** (top-level try/catch exits 0, "non-fatal").
  6. **Subagent sessions** (`CLAUDE_AGENT_TYPE` set -> early exit by design).
- **Observability that already exists:** the loader logs `console.error("Force-
loaded: <file> (<n> chars)")` per file to stderr - visible via `claude --debug`.
  This is the real per-session "did it load?" readout (NOT `InstructionsLoaded`).

The historical "hit or miss" loading was always deterministic: the file either
existed at session start or it did not. The only genuinely non-deterministic link
in the chain is the model's _compliance_ with a rule once it is loaded (section 5).

---

## 4. Terminal markdown rendering & styling [verified, theme-dependent]

Responses render as GitHub-flavoured markdown in the terminal; the active THEME
assigns the colours. Important: the model cannot see its own rendered output, so
colour judgements must come from the user (screenshots).

- **Cannot force arbitrary colour.** Raw ANSI escape codes are not injectable (no
  way to emit a raw ESC byte in a markdown message; the renderer sanitises them).
  Inline HTML like `<span style=...>` is stripped or shown literally.
- **Colour levers that DO work (theme-applied):**
  - Inline code span (single backticks): theme code colour (teal in this theme).
  - Fenced code block with a forced language: syntax-highlighted by that language.
  - **Comment inside a code block: renders muted** - grey in one tested theme,
    GREEN in another. The muted colour is theme-dependent.
  - `diff` block: `-` lines reddish, `+` lines near-normal (green is less reliable).
  - Leading comment chars (`#`, `//`, `--`, `;`, `%`, `"`, `/*`, `<!--`) -> the
    theme's comment colour, usually uniform across languages.
  - Non-comment sigils (`$`, `@`, `&`, `:`, `%`, `<`) -> variable/other colours;
    this is where real colour variety lives, NOT the dozen languages that share `#`.
- **Indentation without a code box is hard:** a real tab or 4 leading spaces
  triggers a CODE BLOCK; 1-3 leading spaces collapse; non-breaking spaces are the
  no-box indent trick (but the renderer may strip them); blockquotes and lists
  indent but add a quote bar / bullet.
- **Italic (`*...*`)** renders slant-only in this theme (no colour/grey shift), and
  is harder to read with dyslexia.
- **The grey `Churned for ...` and `recap:` lines are Claude Code UI chrome**, not
  markdown - they cannot be reproduced from response content.

### Locked style for plain-English companions (decided 2026-06-19)

The plain-English restatement uses a fenced **`csharp`** block with a single
`#`-led line, which renders GREY (C# treats `#...` as a preprocessor directive):

```csharp
# a short, jargon-free restatement a non-engineer could follow
```

- Chosen over python `@` (which also greys) because `csharp #` is robust to
  quotation marks in the text, whereas a python decorator can tokenise quotes as
  strings and break the grey.
- **Caveat:** do not start the line with a C# preprocessor keyword - especially
  `if` (`# if ...` is parsed as the `#if` directive and colours instead of
  greying). Use "when"/"should". Also avoid leading else/elif/endif/define/undef/
  region/error/warning/pragma. No backticks inside the text.
- This is encoded as a standing rule in `~/.claude/PAI/USER/AISTEERINGRULES.md`.

---

## 5. The compliance meta-lesson [verified this session]

- **A loaded rule is not a followed rule.** Loading is deterministic; compliance is
  probabilistic. In one session the personal steering rule loaded correctly (it was
  in the SessionStart system-reminder) and was still ignored for several turns.
- **In-session correction temporarily boosts compliance**, so the only honest test
  of whether a change _persists_ is a FRESH session where the model is not
  pre-warned - observed in the first few technical turns.
- **Determinism ladder:** wording/specificity, channel (system-reminder vs native
  CLAUDE.md), and recency are _nudges_ that raise the odds. Only a hook _guarantees_
  - and only for tool-action gating or a structural check, not prose quality.
- **Cross-session-artifact footgun:** a note from another session that says "today"
  / "this session" or cites a line number is a point-in-time snapshot. Line numbers
  drift; "today" is session-relative. Trust live state over any saved note.

---

## 6. Permission modes, protected paths & shell/mouse mechanics [official, 2026-06-25]

Sources: Claude Code permission-modes, fullscreen, and interactive-mode docs (links in
the Sources section). Verified against docs + the live CLI (v2.1.191) this session.

- **Six permission modes** (`Shift+Tab` cycles the first three): `default` (reads only),
  `acceptEdits` (edits + common FS commands in-scope), `plan` (read-only research),
  **`auto`** (NEW, v2.1.83+ -- a Sonnet-4.6 classifier approves safe actions and blocks
  risky ones; no longer needs opt-in consent as of v2.1.152), **`dontAsk`** (NEW --
  CI-style: only pre-approved tools run, everything else is denied not prompted), and
  `bypassPermissions` (skips everything; container/VM only).
- **Protected paths** are never auto-approved except in `bypassPermissions` (and even
  there `rm -rf /` and `~` still prompt). Per mode: default/acceptEdits/plan -> prompt;
  `auto` -> classifier; `dontAsk` -> denied; `bypassPermissions` -> allowed. Neither
  `permissions.allow` rules NOR `PreToolUse` allow-hooks can pre-approve them (section 2).
  Guarded set includes `.git`, `.config/git`, `.claude`, `.cargo`, `.husky`, and the
  files `.zshrc/.zshenv/.zprofile/.envrc/.bashrc`, `.npmrc/.yarnrc/bunfig.toml`,
  `.gitconfig/.gitmodules`, `.mcp.json/.claude.json`. Full model in
  `CLAUDE_CODE_SECURITY.md`.
- **`!` shell mode (v2.1.186 behaviour change):** `! <cmd>` runs outside the model and
  ALWAYS adds the command + output to context. Since v2.1.186 Claude also auto-responds
  to that output (costs a normal prompt); `respondToBashCommands:false` reverts to
  silent-but-still-ingested. The context ingestion is unconditional; only the
  auto-response is toggle-able.
- **Fullscreen renderer + mouse:** the opt-in fullscreen renderer (`/tui fullscreen`)
  draws on the alternate screen and CAPTURES mouse events, breaking native click-drag
  selection. Levers: hold a per-terminal modifier for a one-off native selection (Apple
  Terminal `Fn`, iTerm2 `Option`, Kitty/most `Shift`); `CLAUDE_CODE_DISABLE_MOUSE=1` to
  opt out of capture permanently (loses click-to-expand, `Cmd`+click URLs, in-app wheel
  scroll; bug #62294 = wheel becomes full-page-only); or `/tui default` to drop
  fullscreen entirely. Trialed + rejected on this machine 2026-06-25 (see auto-memory).

---

## Update Log

- **2026-06-19** - Initial version. Captured from the investigation into why a
  personal steering rule "wasn't loaded" (it was; compliance was the gap) and the
  follow-on work designing the grey `csharp #` plain-English style. Sections 1-5.
- **2026-06-25** - Added section 6 (permission modes, protected paths, `!` shell mode,
  fullscreen mouse) and, in section 2, the 2026-06 hook events plus the refinement that
  a `PreToolUse` hook can DENY but cannot force-ALLOW a protected path (only
  `bypassPermissions` can; verified vs issue #41615). From the 2026-06-25 deep
  investigation of H1-2026 Claude Code changes; full cited report in
  `~/.claude/MEMORY/WORK/20260625-110731_*`. New companion doc: `CLAUDE_CODE_SECURITY.md`.

---

## Sources

- Claude Code memory docs: https://code.claude.com/docs/en/memory
- Claude Code hooks docs: https://code.claude.com/docs/en/hooks
- Claude Code settings docs: https://code.claude.com/docs/en/settings
- Claude Code permission-modes docs: https://code.claude.com/docs/en/permission-modes
- Claude Code fullscreen / interactive-mode docs: https://code.claude.com/docs/en/fullscreen , https://code.claude.com/docs/en/interactive-mode
- Issue #41615 (permissions.allow + PreToolUse hooks cannot override the protected-path prompt): https://github.com/anthropics/claude-code/issues/41615
- Issue #62294 (CLAUDE_CODE_DISABLE_MOUSE makes the wheel full-page-only): https://github.com/anthropics/claude-code/issues/62294
- Issue #16538 (plugin SessionStart additionalContext dropped, closed/not_planned):
  https://github.com/anthropics/claude-code/issues/16538
- Issue #10373 (SessionStart hooks not working for new conversations, open):
  https://github.com/anthropics/claude-code/issues/10373
- Local code: `~/.claude/hooks/LoadContext.hook.ts`, `~/.claude/hooks/lib/paths.ts`,
  `~/.claude/settings.json` (`loadAtStartup`, `hooks.SessionStart`).
