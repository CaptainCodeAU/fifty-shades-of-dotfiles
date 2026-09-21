# Decisions register (moved 2026-09-21)

Until 2026-09-21 this file held every ruling for this repo and several
machine-wide ones. Under D-20260920-10 the register split into two homes,
neither of them in this repo: machine-wide rulings in the pj-owned
machine-wide home, and this project's own rulings in its private records
drawer (this repo declares `records: private` in `.claude/pj-homes`).

Query it with `decided <words>`. `decided --list` shows every block in
scope, `decided --all` every block on the machine, `decided --selftest`
proves the arms. The moved blocks remain in this file's git history; history
was not rewritten. How the tool decides where to look: `docs/DECIDED.md`.

**The IDs gained a machine letter on 2026-09-21** (P8a): a ruling is now
`D-YYYYMMDD-LNN`, where L names the machine that minted it -- `A` for every
ruling made before that date, because every one of them was made on the Mac
mini. **Every `D-YYYYMMDD-NN` cited anywhere in this repo still resolves**:
`decided` falls back to the letter form after an exact miss and says so on
stderr when it does. That fallback is what keeps this sentence true; the
filenames themselves did change.

Two blocks stay here on purpose: one is LifeOS-owned and not this project's
to move; the other was the bridge that pointed `decided` at the machine-wide
home before it could read that home itself. **The LifeOS-owned block keeps
its original ID**, unlettered: relabelling another project's ruling is not
this project's call. It is the one block on the machine still on the old
shape, and `decided` finds it exactly as before.

---

## D-20260919-04 -- Delete the dotfiles copies in lifeos-private, keep the learning

topic: lifeos-private residue SCOPES dotfiles copy MEMORY WORK ci-watch-observability github-credential-lanes incidents upgrades delete keep hash check
decided: 2026-09-19
status: standing
holds-in: fifty-shades-of-dotfiles/docs/PROJECT_LIFEOS_BOUNDARY.md section D3

After D-20260919-03 lands and a hash comparison shows nothing unique remains (AMENDED
2026-09-19 before execution: measured, 3 of the SCOPES copy's 9 content hashes are unique,
all older snapshots of live files; the gate is "every hash is shared OR classified
superseded", never a bare zero): delete
`SCOPES/dotfiles/` and the dotfiles folders under `MEMORY/WORK/` in lifeos-private.
Keep the LEARNING incidents, the UPGRADES records and the one citation in
`OPERATIONAL_RULES.md`; those are LifeOS's own lessons, and deleting evidence to tidy a
boundary is the wrong trade. Gated on the hash check, never on a date. NOT EXECUTED.

## D-20260920-A11 -- pj session framework rulings R0 to R8

topic: pj session framework rulings R0 R1 R2 R3 R4 R5 R6 R7 R8 start routine wrap-up item model homes machine-wide rules concurrent sessions machinery travels register home pj-global pointer
decided: 2026-09-20
status: superseded (the split this block bridged was done on 2026-09-21, P5.5; `decided` now reads that folder itself)
holds-in: ~/.claude/pj-global/decisions/ (D-20260920-A02 to D-20260920-A10, one file per ruling)

Pointer only. Nine rulings made on 2026-09-20 for the pj session framework programme are
recorded machine-wide, outside this repo, under D-20260920-A10 (R8). This block exists so
`decided` can find them until it learns to search that folder. No ruling text here.
Those nine were `D-20260920-02` to `-10` until 2026-09-21; both shapes resolve.
