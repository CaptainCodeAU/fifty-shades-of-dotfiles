# Red team 2026-09-28: Gavin's rulings on the open gaps

Ruled 2026-09-29 by Gavin in his own AskUserQuestion boxes, session dotfiles-doer
(two boxes, every answer his, none applied by a timer). The gaps come from the red team
report `~/CODE/CaptainCodeAU/CaptainCodeAU-isolinear/workbench/records-system/2026-09-28/research/rules-leftout-redteam.md`,
section 5 (H2, H5, H8, H9, H10, H11) and item W-20260929-A50.

| Item                 | Gap                                                                                                                        | Ruling                                                                                                                                                                                                                                                                        | Rejected                                                                                                     |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| W-20260929-A32 (H2)  | No leak scan at push time; `--no-verify`, `LEAK_SCAN_DISABLE=1`, `leakscan.disable`, `core.hooksPath` skip the commit scan | Build a pre-push leak scan for public remotes, and a Bash guard that denies the four bypass knobs                                                                                                                                                                             | Pre-push scan only (the knobs stay usable); leave as is                                                      |
| W-20260929-A35 (H5)  | A session can edit the live guards, `~/.gitconfig`, `~/.claude/CLAUDE.md` and memory                                       | Lock the live files: a deny list for Edit and Write on `~/.claude/hooks/**`, `~/.gitconfig`, `~/.claude/CLAUDE.md` and the memory folders, plus a Bash guard for write verbs on them. The dotfiles repo copies stay editable, so guard fixes go through the repo and a commit | Also lock the dotfiles hook sources (the repo could not fix its own guards without an override); leave as is |
| W-20260929-A38 (H8)  | Write and Edit have no PreToolUse hook                                                                                     | A35's deny list is the interim; engage's planned first-touch hook is the real fix. No second Write/Edit hook is built here                                                                                                                                                    | Build a Write/Edit hook now (engage would replace it)                                                        |
| W-20260929-A39 (H9)  | OPERATIONAL_RULES line 17 allows `/bin/rm -P` on a secret temp file, the delete guard denies it                            | Ban secret temp files outright: a secret moves by pipe or environment, never a file. The delete guard stays as it is. Gavin changes line 17 by hand                                                                                                                           | Allow `rm -P` on a file the session created (new per-session state, a new way to be wrong)                   |
| W-20260929-A40 (H10) | When pj-worker is missing, pj launches with a NOTE and no cap check                                                        | Refuse the launch, naming the fix (restow the dotfiles). A cap that cannot count is not a pass                                                                                                                                                                                | Keep the NOTE and launch                                                                                     |
| W-20260929-A41 (H11) | Posting as Gavin to third parties has no guard                                                                             | Text rules only, as now. No Bash guard                                                                                                                                                                                                                                        | Bash guard with a named override (recommended, not chosen)                                                   |
| W-20260929-A50       | Three shell lexers                                                                                                         | Compare first: a read-only report of which cases each lexer gets wrong, then a ruling with that evidence                                                                                                                                                                      | Move every guard onto one lexer now; keep three                                                              |

## Second round, W-20260929-A46 and A40 (2026-09-29)

Ruled by Gavin in his own box in session dotfiles-doer, after he asked for the views of
engage-main and factory_researcher-main. Both sessions' answers were shown to him side by side.

| Item | Question | Ruling | Views |
|---|---|---|---|
| W-20260929-A46 (S18, S19) | `github-agent-token token` / `pat public-read` print a live token | The secret guard denies the printing forms; `GH_TOKEN="$(github-agent-token ...)"` and `... \| cut -c1-4` stay allowed. Gavin changes OPERATIONAL_RULES git-auth step 2 by hand to the 4-character form | Both sessions: same. engage uses only the allowed forms |
| W-20260929-A46 (S23, S34, others) | Inline code reading a credential-named variable (python os.environ, node process.env, perl $ENV, ruby ENV), `security export`, `infisical secrets`, `${(P)name}`, DATABASE_URL / *_DSN names | Deny them all, each with a near-miss allow arm | Both sessions: same |
| W-20260929-A46 (S14) | `rg -uuu API_KEY ~/.config` prints values | Deny a search only when it starts in a secret-bearing folder AND the pattern is credential-shaped; code searches in repos stay allowed; the denial offers `rg -l` | factory_researcher-main proposed this; engage-main preferred an accepted limit |
| W-20260929-A40 | pj refuses when its counter is missing | Keep. engage now refuses the same way (engage d01d43f), so the launchers match | Both sessions: keep |

## Third round, W-20260929-A50 (2026-09-29)

Ruled by Gavin in his own box in session dotfiles-doer, after factory_researcher-main's view.
The evidence is the read-only comparison in docs/lexer-comparison/ (132 shapes through the 4
real hooks). conv-shscan.awk, shared by 6 hooks, scored lowest: 17 missed denies and all 4
wrong denies, because it does not read inside bash/sh/zsh -c, eval, backticks, shell-fed
heredocs or case.

| Question | Ruling | Rejected |
|---|---|---|
| Which way for the three lexers | B: teach conv-shscan.awk to read inside -c, eval, backticks and shell-fed heredocs, as the delete guard's lexer already does | A: fix only the named gaps per hook (the wrong denies stay); C: one shared awk lexer (engage's Go parser, internal/cmdclass, becomes the shared reader when pj retires) |
| A shared test set | Keep the 132 shapes, each with its expected answer, as a test set in dotfiles, and give engage-main a copy for the Go parser, so parity is measured | No shared set |
