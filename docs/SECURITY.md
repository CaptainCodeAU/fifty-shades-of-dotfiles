# Security posture

This document captures _why_ the repo's SSH configuration uses a
maximum-paranoia strict posture, what alternatives were considered,
and the daily commands you'll actually use to live with it. It
complements the four-layer defence-in-depth recap in
[README.md §Security](../README.md#security).

## Overview

The threat being defended against is an **in-process attacker
running as your user** — for example, a malicious dependency, a
compromised CLI, or a postinstall script. Such an attacker doesn't
need to escalate privileges to do damage; if SSH keys are sitting
unlocked in an `ssh-agent` (or in the system Keychain with
`UseKeychain yes`), the attacker can silently authenticate to
GitHub _as you_ and push, fork, or rewrite history without ever
asking you to type a passphrase.

The posture chosen here removes that capability by refusing to
cache keys at all. Every SSH operation prompts for the passphrase.
Friction is the price; the deliberate inability of any process to
silently auth as you is the product.

## Why we chose friction

The `Host *` block in the stowed `~/.ssh/config` sets:

```sshconfig
Host *
    AddKeysToAgent no
    UseKeychain no
    IdentitiesOnly yes
```

Each setting is doing specific work:

- **`AddKeysToAgent no`** — first use of a key does not implicitly
  load it into the running `ssh-agent`. Without explicit
  `ssh-add`, the key stays on disk encrypted and must be unlocked
  per operation.
- **`UseKeychain no`** — macOS does not pull the passphrase from
  the login Keychain. A key isn't silently unlocked just because
  you logged into the Mac.
- **`IdentitiesOnly yes`** — only the `IdentityFile` named in the
  matching host block is offered. Prevents the agent from spraying
  every loaded key at every host (which both leaks key fingerprints
  and can lock you out for too many bad attempts).

The cost: each `git fetch`, `git push`, or `ssh git-<alias>` asks
for a passphrase. The benefit: a compromised process cannot reuse
a cached unlock, because there is no cache.

## Alternative postures considered

| Posture               | How it looks                                                                                                                                      | Friction                                          | Protection vs in-process attacker                                               | What would prompt switching                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Strict (current)**  | `Host *` with `AddKeysToAgent no`, `UseKeychain no`, `IdentitiesOnly yes`. Passphrase per operation.                                              | High — every op                                   | High — no silent auth path exists                                               | (this is the chosen posture)                                                                      |
| **Pragmatic-strict**  | Strict on `Host *`; selectively `UseKeychain yes` and `AddKeysToAgent yes` on specific host blocks (e.g. one frequently-used `Host git-<alias>`). | Medium — friction reduced for chosen aliases only | Medium — attacker can act as you against the chosen aliases, but not the others | Friction on a single alias becomes the dominant cost and you accept silent auth on that one alias |
| **Pragmatic-default** | `Host *` with `UseKeychain yes` and `AddKeysToAgent yes`. Apple Keychain holds the passphrase; first use unlocks for the session.                 | Low — passphrase on first use only                | Low — once unlocked, any process running as you can auth                        | You decide convenience outweighs the in-process supply-chain risk                                 |
| **Hardware-backed**   | Key material lives on a YubiKey or in the Secure Enclave; SSH talks to a hardware-backed agent. Touch / biometric required per use.               | Low-to-medium — a tap, not a passphrase           | High — key material never reaches user-space memory in a usable form            | You acquire the hardware and migrate keys onto it                                                 |

The choice between these is not "which is correct" but "which
matches the threat you actually have". This repo's posture treats
in-process attackers as a real, ongoing concern.

## Triggers to revisit

Re-evaluate the posture if any of these change:

- **You adopt hardware-backed keys** (YubiKey / Secure Enclave).
  Hardware-backed gives you the same protection as Strict with
  much lower friction; the trade evaporates.
- **The threat model shifts.** If the realistic attacker stops
  being "code running as me" and becomes something else (lost
  laptop, network adversary, etc.), strictness is solving the
  wrong problem and other controls matter more.
- **Friction starts producing observable bad behaviour.** If you
  notice yourself shortening passphrases, reusing them across
  keys, or otherwise weakening the keys themselves to make the
  friction tolerable, the friction has become a _negative_
  security signal — it's now causing the harm it was meant to
  prevent.

Absent one of these, drift away from strict is drift away from a
deliberate choice.

## Daily SSH operations

The strict posture means you will run `ssh-add` explicitly. These
four commands cover almost every interaction:

```sh
ssh-add -t 8h ~/.ssh/<your-github-key>   # load for the day
ssh-add -l                                # list loaded keys
ssh-add -d ~/.ssh/<your-github-key>      # remove one key
ssh-add -D                                # remove all keys
```

- **`ssh-add -t 8h <key>`** — at the start of a working session,
  unlock the key once and keep it in the agent for 8 hours. After
  that, the agent forgets it and you'll be prompted again. Use
  this when you know you'll do many GitHub operations in a
  session.
- **`ssh-add -l`** — list whatever's currently in the agent. Use
  this to check whether a passphrase prompt is going to happen
  before a long-running script tries to push.
- **`ssh-add -d <key>`** — remove a single key from the agent.
  Use this when stepping away from the machine in a context
  where you don't want a logged-in session to retain auth.
- **`ssh-add -D`** — remove _all_ keys. The hard reset; use this
  before handing the machine to anyone else, or when you're
  unsure what's loaded.

For longer ad-hoc sessions, prefer `-t` with an explicit timeout
over loading without one — a forgotten unlocked key is exactly
what the strict posture was meant to prevent.

## Drift checks

The strict posture is only meaningful if it actually applies. If
something later quietly flips `UseKeychain yes` or
`AddKeysToAgent yes` (e.g. an installer running `ssh-add` once
that triggers a GUI prompt to save to Keychain), the protection is
gone but the config file might still _look_ strict. Check the
effective config, not the file:

```sh
ssh -G git-<alias> | grep -iE "usekeychain|addkeystoagent"
# expected: both 'no'
```

`ssh -G` resolves all `Host` matches and `Include` files and prints
what SSH will actually use. If either line says `yes`, find what
changed before continuing.

A second drift check, for whether a key has been silently cached:

```sh
ssh-add -l
# expected: "The agent has no identities." at the start of a session
# (until you explicitly run ssh-add)
```

If the agent has identities you didn't load, something added them
on your behalf. Investigate before pushing.

## What this document is not

This is not advocacy for everyone to adopt strict. It is a record
of why this repo uses it, so that someone reading the SSH config
six months from now (including future-me) doesn't mistake the
strictness for an oversight and "fix" it back to defaults. The
postures table exists precisely so that a reasoned switch is
possible; the triggers section names the conditions under which
that switch would make sense.
