# Permission prompts: the ping, the log and the zsh guard

What happens when Claude Code stops a session to ask Gavin, and the guard that stops one kind of
those stops from happening at all. Built 28 Oct 2026 in dotfiles-main.

## Why

At 11:44 AM on 28 Oct 2026 an e-conductor helper ran a read-only zsh probe with no `rm` in it:

```
print -rl -- ${(s.:.)PATH} | grep -n local; BP="${(j.:.)${(s.:.)PATH}:#$HOME/.local/bin}"; ...
```

Claude Code showed "Dangerous rm operation not ruled out -- the shell may read this command
differently than it was parsed. Do you want to proceed?", and the helper waited 13 minutes until
Gavin saw it.

The cause, read in the Claude Code 2.1.312 program file: every Bash-tool command is parsed with a
bash parser (tree-sitter-bash). zsh-only syntax makes that parse fail. Claude Code then cannot rule
out a hidden `rm`, and asks. That ask is a safety check: bypass mode, allow rules and a PreToolUse
`allow` cannot pass it (also in Anthropic's permission-modes page).

## What Gavin decided

- **Ping and log every permission prompt** (dotfiles-main, 28 Oct 2026, his words: "ensure that
  everytime there are prompts like this, that I am ntfy pinged" and "LOG all these somewhere").
- **Q1 (v2): 2, a guard that turns zsh-only commands away with a reason**, chosen over the official
  off switch (below). With it: "the few prompts that still come as well as the ones that get
  caught, everything should be logged. So from time to time we can review it here."
- **Built test-first** (his ask, via the tdd skill), and **Q2: 4**: tested from the outside plus a
  live session in a herdr pane, the test session's own prompts approved by the driving session.

Recorded as draft ruling #4094 in this project's engage records; it stands once Gavin approves it.

## The three pieces

| Piece                                         | Where                                                       | What it does                                                                                                                                                                                                                                                                               |
| --------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `notify-permission-prompt.sh`                 | `home/.claude/hooks/`, PermissionRequest hook               | Prints nothing, so the dialog shows as before. Logs a `prompt` line and hands a "Needs your OK" ping to `engage-ping`.                                                                                                                                                                     |
| `enforce-zsh-parse.sh` + `zsh-parse-check.py` | `home/.claude/hooks/`, PreToolUse guard on Bash and Monitor | A quick text test for a zsh-only form, then tree-sitter-bash on the command and on any `sh/bash/zsh/dash -c` script. A parse error is denied, naming the form and the route: write the zsh to a file, run `zsh <file>`. Logs `caught`. Fails open on its own trouble and logs `unchecked`. |
| `permission-prompts`                          | `home/.local/bin/`                                          | Reviews the log: totals by kind, the zsh forms seen, prompts by session, the latest entries with a denominator.                                                                                                                                                                            |

The log is `~/.local/state/dotfiles/permission-prompts.jsonl`, one JSON object per line, mode 600:
time (12-hour Melbourne), kind, session name and id, folder, project, tool, command (known secret
shapes redacted), form and where it was found, agent id and type, permission mode, transcript,
Claude Code version, host, herdr pane, and what happened to the ping. Each script's header has
the detail; each has a `--selftest`.

## Measured

- **Which zsh forms break the parser** (tree-sitter-bash 0.25, 28 Oct): 24 forms broke it, among
  them `${(flags)v}`, `${${nested}}`, `${v:#pat}`, `$=v`, `${~v}`, `${^v}`, glob qualifiers like
  `*(.N)`, `(#i)`, `=(cmd)`, `<1-10>` and `() { }`. 9 neighbours did not, among them `${=v}`,
  `${f:t}`, `${f:A}`, `$arr[1]` and `${#arr}`. The guard's selftest holds both lists.
- **Speed:** about 40 ms for a plain command, about 90 ms when the parser runs (warm, 3 runs each).
- **Live, 2.1.312, bypass mode, herdr pane, the 11:44 AM command:** with the guard on, it was
  denied at once and no prompt appeared, one `caught` line. With the guard's parser broken on
  purpose, the same command logged `unchecked`, then showed the prompt word for word, then logged
  `prompt`.
- **A session cannot report its own prompts.** In that second arm the session answered
  "Permission prompt: none", though the screen showed the prompt and it was approved. The prompt
  goes to the person, not the model. Only this log and the screen show one happened.

## Known limits

- **Engage sessions do not have it yet.** They read only engage's own settings. The rows for
  engage's template were handed to engage-main through e-conductor on 28 Oct; this project tracks
  it as record #4092. Until then it covers plain `claude` sessions.
- **No ping from a session another session started.** `engage-ping` stays silent when
  `PJ_LAUNCHED_BY` is set, by engage's rule, so a prompt in such a worker is logged but not pinged.
  That rule is engage's to change. The log says "handed to engage-ping", never "sent".
- **The guard knows only the forms on its list.** A new zsh form that breaks the parser still
  prompts; it shows up in the log as a `prompt`, which is how the list grows.
- **Why a prompt appeared is not given to the hook** (requested upstream, claude-code #100419), so
  the log cannot say "rm check".
- **The session name** is not in the hook's environment in an engage session (measured in the live
  test); the log writer reads it from `~/.claude/sessions/<pid>.json` by session id.

## The option not taken

`CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS=1`, set in the shell that launches Claude Code,
switches off every dangerous-rm prompt in bypass mode, including for commands it cannot parse
(permission-modes docs, since 2.1.311). It does nothing in a session with any PermissionRequest
hook, a deny or ask rule on Bash, Edit or Read, or in a session another session started. It was
not chosen because it also lets a real `rm -rf ~` run unasked, and because the ping above is a
PermissionRequest hook.

## Upstream reports read (28 Oct 2026)

Same prompt, no `rm`, stalled background agents: claude-code #104925. zsh read as bash inside
`zsh -c`: #99249. Deny with a reason instead of blocking: #103764, #93392. The reason in hook
input: #100419. The only Anthropic reply found calls these prompts intended (#75588).
