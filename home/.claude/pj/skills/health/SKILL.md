---
name: health
description: Is the pj framework wired on this machine? Runs pj-health and reports the rows. Invoke as /pj:health; never auto-invoked.
disable-model-invocation: true
---
# Health

Run `pj-health` (add `--full` or `--live` only when asked) and paste its output verbatim
in a code block. Then one sentence per FAIL row naming the fix command it printed, and
nothing for PASS, WARN or NOT MEASURED rows beyond the pasted lines. Never run a fix.
`docs/PJ_HEALTH.md` in the dotfiles repo explains every row.
