# START HERE — install the operator standard into this project

**You are reading the opening prompt of a folder that was copied into this project.** It carries
the operator's portable working standard, prepared elsewhere on a machine you cannot reach.

Your job: install it, prove it works, then prove this folder can be deleted.

⚠️ **Do not start writing.** The order below is the point: survey, inventory, ask, then write.

---

## A. What this folder is

```
_adopt/                          ← temporary. The operator deletes it when you are done.
  START-HERE.md                  ← this file
  payload/
    operator-standard.md         ← a marker-delimited block for the instruction file
    memory-convention.md         ← the shape of the memory store + rules for writing into it
```

**It is a transport, not an installation.** Nothing you write may reference a path inside it,
because it will not exist tomorrow. That is the single most likely way to get this wrong.

## B. The finish line, stated up front

You are done when **all** of these are true, and not before:

1. The block from `payload/operator-standard.md` is in this project's instruction file, verbatim,
   between its markers.
2. Whatever memory work was agreed is written and indexed.
3. **Every check still passes with this folder renamed away.**
4. A **fresh session that never saw this conversation** has been probed and behaved correctly.
5. You have told the operator it is safe to delete `_adopt/`, naming which checks you re-ran
   without it.

You do not delete this folder. The operator does.

## C. Rules that bind you for the whole job

These are stated here in full rather than referenced, because naming a file carries nothing.

1. **Inventory before change.** Produce one table covering the entire payload, with a proposed
   verdict per row, and show it before touching anything. The operator must be able to redirect
   the whole shape at the start rather than discovering it item by item.
2. **Before and after, as exact text — never a description.** There must be zero gap between
   what you described and what they get.
3. **A real "leave it as is" option, every round.** If every choice is a variant of "change it",
   the confirmation is theatre.
4. **One decision per round.** Related is not the same as one fork. Coming back is the process,
   not a failure of it.
5. **Reasoning and recommendation BEFORE the options**, in the same view.
6. **KEEP-LOCAL is the default for anything already here that you cannot explain.** You did not
   write this project's rules and cannot see what they are load-bearing for. A rule you cannot
   explain is a rule you do not touch.
7. **Facts before questions.** Never ask what you can look up. Every question must be a genuine
   decision, not a research request.
8. **Write nowhere except this project and its own memory store.** Not another project, not
   another project's memory, not anything outside this repo and its store. No exceptions, and no
   permission path — if it looks necessary, stop and say so instead.
9. **Snapshot the memory store before the first write to it.** It is not version controlled and
   an overwrite is unrecoverable. Say where you put the snapshot.
   ⚠️ If this machine's `cp` is an interactive-by-default wrapper, a plain `cp -R` will HANG on a
   prompt a non-interactive call cannot answer. Force it explicitly.
10. **Report what checks RETURNED, never that they succeeded.**

## D. How to run it

**Use the `MemoryCuration` skill, `Workflows/Adopt.md`.** It is the workflow for exactly this
job and it holds the full method. Invoke it and follow it.

**If that skill is not installed on this machine**, say so plainly and follow section C plus the
steps below by hand. Do NOT copy the skill into this project — a per-repo copy drifts and still
misses the next repo. Installing it globally is the operator's call, not yours.

### The steps, in order

1. **Survey.** Read the whole payload. Read this project's instruction file in full. Find out
   whether a memory store exists for this project and where this harness puts it — if you are not
   certain of the convention, ASK. Never guess a path.
2. **Inventory.** One table: item · destination · already here? · verdict · why. State how many
   rounds it implies.
3. **The instruction-file block.** Replace between the markers, never merge — that is what makes
   a re-run idempotent instead of accumulating a second copy, and it is what "replace the
   overlapping version" means. If a rule *outside* the markers conflicts with one inside, that is
   a fork for the operator with both texts shown — never a resolution you take quietly. If this
   project has no instruction file, creating one is its own round.
4. **Memory.** Follow `payload/memory-convention.md`. Note that this kit deliberately seeds no
   memories, and why: the rules live in the instruction file, so writing them into memory too
   would be one fact in two homes. What memory needs here is its shape and its writing rules.
5. **Tooling.** If the payload's rules mention tooling that is not present, say so and give the
   install step. Do not vendor a copy into this project to make a check pass.
6. **Verify with the folder renamed away** — see section E.
7. **Probe a fresh session** — see section F.
8. **Close** with the two-part question: the last decision plus the green light. Then the
   safe-to-delete statement.

## E. The deletability proof

Rename this folder — do not delete it — and re-run every check with it gone:

- the block is present and complete in the instruction file
- every memory file has an index line and every index line resolves to a file
- no dangling links; any deliberate forward marker is annotated with the date its condition was
  last tested
- **no surviving reference to this folder's path anywhere in the project or its memory store** —
  this is the whole point of the step
- anything the installed rules depend on resolves from its real location, not from here

Then restore the folder name and report what the checks returned.

## F. The fresh-session probe

**A behavioural change cannot be measured in the session that applied it.** Being shown a rule
temporarily raises compliance and contaminates the test, so "I am following it now" is not
evidence of anything.

Start a session that has not seen this conversation — a second pane, a parallel window, a
spawned session — or hand the operator the probe to run. Then probe for **behaviour**:

- ask something that should trigger the presentation rules, and read the shape of what comes back
  — lettered sections, a plain-English gloss under anything dense, the answer first
- ask something that should trigger a decision, and check the discipline appears — options in
  plain English, each trade-off on its own line, the recommendation after them, and nothing
  offered that the session would argue against
- ask for a count of something, and check it reaches for a census and states a denominator rather
  than quoting a bare number

**A file-existence check proves the write happened and proves nothing about whether the rule
fires.** Report the probe's actual output. A probe that "looked fine" was not run.

## G. What this kit does not do

State these to the operator rather than leaving them implied:

- It carries **no machine-specific facts** — branch conventions, package managers, shell wrappers,
  paths. Those belong to a machine, not to a person, and this folder may have crossed machines.
- It carries **no domain content** from wherever it was authored — no product, project or
  vocabulary. If any leaked in, that is a defect: report it rather than adapting it.
- It does **not** install or configure tooling. It can only verify and tell you what is missing.
- It does **not** know what this project already decided. Everything already here wins by
  default; the block is additive.
