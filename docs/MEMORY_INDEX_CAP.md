# The per-project memory index cap, and why CLAUDE_MEMORY_STORES stays off

**Ruling (2026-09-19): do not wire `CLAUDE_MEMORY_STORES`.** Keep `MEMORY.md` thin by
hand. Registered as `D-20260919-07`.

## What the cap is

`~/.claude/projects/<key>/memory/MEMORY.md` is injected into EVERY session, so the
harness caps it. Both limits are enforced by the Claude Code binary itself -- not by
this repo, not by PAI, not by any hook:

| limit | value | note |
|---|---|---|
| bytes | 25000 | displayed as "24.4KB" only because the formatter divides by 1024 |
| lines | 200 | co-limit; whichever is closer to its cap wins |
| warn | 80% | injects the "approaching the read limit" reminder |
| target | 70% | what the reminder tells you to compact to |

At 100% the overflow is **truncated from what the model sees**. Nothing warns you at
read time that a memory has silently stopped being loaded.

Measured against binary `2.1.186` on 2026-06-23 and re-measured against `2.1.278` on
2026-09-19. Every stable string survived 92 releases, with a negative control
(`zzz_not_a_real_symbol`, 0 hits) proving the search was live.

## Why the env var is not the answer

`CLAUDE_MEMORY_STORES` does raise a cap. Its schema is intact in 2.1.278:

```
{path, mode:"rw"|"ro", scope:"user"|"team", mount:/^[A-Za-z0-9_-]+$/,
 promptIndex, skillsDirs[], promptIndexMaxBytes:int}
```

and a store's index is read with `promptIndexMaxBytes ?? default` and **no line cap**.
That is the whole attraction, and it is real.

**It is also not a dial.** The same code path that parses the variable starts a sync
subsystem. Adjacent in the binary:

```
team_memory_sync_watcher_start    personal_memory_sync_watcher_start
memory_store_pull_ms              memory_store_pull_boot_spillover_ms
"multi-store sync error"          "backend sweep"
"This file's directory belongs to a synced project memory store"
/v1/code/local/memory/mounts      org-memory-discovery.json
```

It also changes two unrelated behaviours without saying so: org memory is disabled
whenever the variable is set, and the default index loader takes a different branch.

**The blocking unknown, stated as an unknown.** Nothing measured here establishes
whether a purely local `scope:"user"` store actually reaches that backend, or whether
the watcher stays on the filesystem and the pull machinery engages only for team
stores. Answering it needs a throwaway session with the variable set and the network
watched -- it cannot be read off the strings. Guessing it wrong sends personal memory
off the machine, so the ruling is to leave it off rather than to assume it is local.

**And it would not even be a config change.** `promptIndexMaxBytes` applies to a
STORE's index, not to the per-project one. `memory/MEMORY.md` stays capped unless all
150 memories migrate into the store. That is a migration with a sync question attached.

## Two corrections to the 2026-06-23 investigation

1. **Topic files are no longer uncapped.** 2.1.278 carries a recall surface limit on
   individual memory files: *"this write left the memory file at ... recall limit. The
   write succeeded, but recall shows other sessions only the first ... of a memory
   file, so everything past that is invisible unless they open it."* The old advice --
   push unlimited detail into topic files -- no longer holds without a size check.
2. **`promptIndexMaxBytes` is store-scoped**, not a general override. The June note
   implied a configured store escapes the caps; true, but only for that store's own
   index.

## The binary patch is still the wrong trade

`tie`/`Z7` can be widened and the binary re-signed (`codesign --force --sign -`,
required because it is Developer-ID signed with hardened runtime). It resets on every
update, taxes every session's tokens, and an internal rename breaks the patch script
silently. Not adopted.

## So the standing practice is

Keep `MEMORY.md` a one-line-per-entry index and put detail in topic files, **checking
those against the recall limit now that one exists**. Compacting means shortening
hooks, never dropping entries: several exist only to stop a past rejection being
re-proposed, and dropping one re-opens the thing it was written to close.

When compacting, verify with a control that nothing was lost -- the link set before and
after must be identical, and every linked file must still exist on disk. Done
2026-09-19: 21769 -> 20404 bytes, 150 entries unchanged, link set identical.

**Revisit trigger:** the index reaching 100% of either cap, or Anthropic documenting
the local-store sync behaviour. Not before.
