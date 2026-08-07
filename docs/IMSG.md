# `imsg` - send one iMessage from the command line

A send-only iMessage CLI for agents, hooks and cron jobs. It never reads message
history, never opens `chat.db`, and needs no Full Disk Access.

- Script: `home/.local/bin/imsg` (stowed to `~/.local/bin/imsg`)
- Platform: macOS only (it drives Messages.app through `osascript`)
- Dependencies: none - bash and the system `osascript`

## Never send anything sensitive through this

**Messages' AppleScript layer can deliver to the wrong recipient.** This is not a
defect in `imsg` and no addressing form avoids it.

The clearest account is from Peter Lewis, the Keyboard Maestro developer, who
ships this capability commercially and has chased the bug for years:

> Messages AppleScript can return entirely the wrong buddy information in certain
> circumstances.

He reports it persisting **whether the target is a phone number, an email address,
or a UUID**. Keyboard Maestro 10.2 did not fix the routing; it changed the action
to "ensure that it either fails or goes to the correct person" - the vendor
settling for fail-safe because correctness could not be guaranteed. Lewis: "it's
hard to make promises given the odd behaviours I've seen in Messages' AppleScript
support."

Messages was rewritten in macOS 11 and its AppleScript support has been unreliable
since.

**Practical rule:** treat `imsg` as a notification channel for things you would be
happy to see arrive at the wrong contact. Build alerts, CI status, "the sweep
finished" - fine. Credentials, tokens, personal detail, anything private - never.

We have not reproduced wrong-recipient delivery here. The warning is recorded
because a third party who has watched this closely reports it, and this tool is
the kind of thing that ends up wired into a hook and forgotten.

## Why this exists rather than a Claude Code plugin

Every off-the-shelf plugin that sends iMessage also reads the thread, and reading
means **Full Disk Access** - a permanent, machine-wide grant, handed over to buy a
one-way notification.

Sending needs none of that. AppleScript's Messages interface asks only for
**Automation** consent, scoped to the app doing the calling, and it cannot read
anything. So the whole capability is one small script with a tighter permission
footprint than the plugin, and no plugin-loading latency on every session.

## Usage

```bash
imsg <recipient> <message...>          # send; the message may be several words
imsg --dry-run <recipient> <message>   # show exactly what would be sent, send nothing
imsg --max N <recipient> <message>     # truncation cap in characters (default 1500)
imsg --help
```

`<recipient>` is an email address or phone number. The message is everything
after it, joined with spaces, so quoting is optional for simple text:

```bash
imsg you@example.com build finished
imsg you@example.com "$(git log -1 --oneline)"
imsg +61400000000 "deploy failed - see CI"
```

### Exit codes

| Code | Meaning                                                            |
| ---- | ------------------------------------------------------------------ |
| `0`  | Handed to Messages. **Not** proof of delivery - see below          |
| `1`  | Usage error: bad or missing recipient, empty message, or not macOS |
| `2`  | Messages or `osascript` refused the send                           |

### Exit 0 means "handed to Messages", not "delivered"

`osascript` returns as soon as Messages accepts the send. Delivery is
asynchronous, and Messages reports failures in its own UI rather than back to the
caller. A zero exit means "queued successfully" and nothing more. There is no way
to get a delivery receipt out of the scripting interface, so do not build a
retry-on-failure loop on top of this exit code - it will never fire.

## Two design decisions worth knowing

### 1. The message is passed as an argument, never interpolated

The idiom found everywhere online splices the message into the AppleScript source:

```bash
# DO NOT DO THIS
osascript -e "tell application \"Messages\" to send \"$msg\" to ..."
```

That is code injection wearing a quoting bug's clothing: a message containing a
double quote closes the AppleScript string early and everything after it is parsed
as **code**. An agent pasting a compiler error or a diff hits this within a day.

`imsg` instead passes the text as an argument to an `on run argv` handler, so it
never transits an AppleScript string literal. Quotes, backslashes, dollar signs,
backticks, newlines and emoji all arrive verbatim, and nothing inside a message can
be interpreted as script.

No `--` separator is needed anywhere. The recipient comes first and an address
never begins with `-`, so `osascript` stops option parsing there - which is exactly
what allows a _message_ to begin with a dash.

### 2. The recipient is an argument, not a constant

This repo is public, and `git-leak-scan` does not pattern-match email addresses. An
address baked into a tracked file would be published permanently, in history, even
if later removed - and no gate in this repo would stop that commit.

**The corollary matters as much as the rule:** whatever calls `imsg` has to supply
the address, so do not hardcode one into a tracked git hook, alias or crontab
either. That is the same leak, one level up. Keep it in `~/.zshrc.private` or
another untracked file:

```bash
# ~/.zshrc.private
export MY_IMSG=you@example.com
alias pingme='imsg "$MY_IMSG"'
```

Because the recipient is a plain argument, `imsg` is a general iMessage sender, not
a send-to-me-only tool. Argument order is guarded by a shape check on the first
argument, so the common slip fails loudly:

```
$ imsg "build finished" you@example.com
imsg: 'build finished' does not look like an email address or phone number.
      Recipient comes FIRST:  imsg <recipient> <message...>
```

## Permissions

### The one-time Automation prompt

The first run from any given parent app raises a macOS prompt: _"<app> wants to
control Messages"_. It must be clicked by a human, once per calling app - Terminal,
iTerm2, Claude, `cron` and `launchd` each count separately. A denied grant shows up
as AppleScript error `-1743`; fix it in **System Settings > Privacy & Security >
Automation**.

This is Automation only. `imsg` is never granted, and never asks for, Full Disk
Access.

### Claude Code's Bash sandbox blocks Apple Events

Verified 2026-08-07. Inside the sandbox every Apple Event fails, regardless of
Messages' actual state. The symptom is a misleading pair of errors:

```
osascript[...] Connection Invalid error for service com.apple.hiservices-xpcservice.
execution error: Messages got an error: Application isn't running. (-600)
```

The second line is a red herring - Messages _was_ running. Agents must call `imsg`
with `dangerouslyDisableSandbox: true`. (`excludedCommands` is not a workaround; it
is broken upstream.) The failure is clean: exit `2`, nothing sent.

## Verified behaviour

Live-tested end to end on 2026-08-07, macOS 25.5, bash 5.3. Each row below was
confirmed by reading the received message, not merely by a zero exit code:

| Case                                             | Result                                                  |
| ------------------------------------------------ | ------------------------------------------------------- |
| Plain ASCII                                      | Delivered as sent                                       |
| `'` `"` `\` `$HOME` `` `id` `` `&` `\|` `;` `<>` | Verbatim; nothing evaluated or parsed as script         |
| Embedded newlines                                | Arrives as **one** message, not several                 |
| Emoji, accents, umlauts, kanji                   | Round-trips intact                                      |
| Message beginning with `--`                      | Sent as text; not parsed as a flag                      |
| Over-length message                              | Truncated with a `...(truncated, N chars total)` marker |
| Reversed arguments                               | Rejected, exit `1`, nothing sent                        |
| Empty / whitespace-only message                  | Rejected, exit `1`, no empty bubble                     |
| Invoked inside Claude's sandbox                  | Fails clean, exit `2`, nothing sent                     |

Truncation counts **characters, not bytes**, so a cap never splits an emoji. The
script sets `LC_CTYPE` itself when the caller left it unset, because a
non-interactive shell (Claude's Bash tool, `cron`) inherits no `.zshrc` and would
otherwise run under the `C` locale.

## Not tested

- Behaviour when Messages.app is **closed**. `tell application "Messages"` should
  launch it, but every live test here ran with Messages already open. If you see
  `-600` outside the sandbox, that is the case to suspect first.
- SMS fallback to a non-iMessage recipient. `imsg` always selects the iMessage
  service explicitly, so a green-bubble contact is expected to fail rather than
  silently downgrade.

**A wrong-but-well-formed address fails silently.** The shape check only proves an
argument _looks_ like a handle; it cannot know whether it is the one you meant. A
mistyped address returns exit `0`, opens a conversation nobody reads, and delivers
nothing useful - or, worse, delivers to a real stranger who owns that address.
There is no guard for this and there cannot be one. **Confirm the recipient before
the first send, especially when it was produced by a script or copied from a
listing rather than typed deliberately.**

## Troubleshooting

| Symptom                                    | Cause                                                    |
| ------------------------------------------ | -------------------------------------------------------- |
| `-1743`                                    | Automation consent denied for the calling app            |
| `-600` + `hiservices-xpcservice`           | Running inside Claude Code's Bash sandbox                |
| `-600` alone                               | Messages.app genuinely not running                       |
| Recipient rejected as "does not look like" | Arguments reversed, or an address with no `@` and no dot |
