# adopt-kit — carry the operator standard into a project

Copy this folder into a project, point a session at `START-HERE.md`, let it install and test
itself, then delete the folder. Works in any project, any language, on any machine.

---

## How to use it

```
# 1. copy it in  (see the warning below — the -L is not optional)
cp -RL ~/.claude/adopt-kit /path/to/the/project/_adopt

# 2. open a session in that project and say:
#      read _adopt/START-HERE.md and do what it says

# 3. it installs, verifies with the folder renamed away, and probes a fresh session
# 4. when it tells you the folder is safe to delete, delete it yourself
```

### ⚠️ `-L` is load-bearing

On a machine where this kit is deployed by stow, `~/.claude/adopt-kit` is a **symlink**. A plain
`cp -R` copies the _link_, not the contents:

- on another machine the link dangles and the kit is empty
- on this machine, editing inside the copy edits the master

`cp -RL` dereferences it and produces a real, self-contained folder. **Check it:**
`find /path/to/project/_adopt -type l` must return nothing.

### ⚠️ If a copy or delete hangs, or silently does nothing

Some shells wrap `cp`, `mv` and `rm` with interactive-by-default or route-to-Trash behaviour,
and Claude Code snapshots those shell functions into its own non-interactive calls. Symptoms: a
copy that waits forever for an overwrite prompt, or a delete that reports a warning and removes
nothing.

- `\cp` escapes an **alias**. It does **not** escape a shell **function**.
- For a copy, use the absolute path when you mean it: `/bin/cp`.
- For the delete, you (the human) choose the tool. An agent never runs `/bin/rm`; if the
  Trash-routed `rm` refuses, the agent reports it and leaves the delete to you.
- `type rm` tells you which you are dealing with.

## What travels, and what does not

| Travels                                                       | Does not                                          |
| ------------------------------------------------------------- | ------------------------------------------------- |
| how to write to the operator, and how to present a decision   | any product, project or domain content            |
| the working contract — sequencing, ownership, pushing back    | any particular harness's modes, banners or voice  |
| the verification discipline, and the discovery rule           | machine facts — branches, package managers, paths |
| the SHAPE of a memory store and the rules for writing into it | seeded memories — see below                       |

**It seeds no memories on purpose.** The rules live in the project's instruction file, because a
rule stored only in memory is consulted rather than obeyed. Writing them into memory as well
would put one fact in two homes, and two copies go unnoticed and only drift. Everything else a
memory store holds is project-specific and accretes as work happens.

## What it will ask you

It will not act like a hammer. Before replacing anything it shows the whole inventory with a
verdict per row, then takes one decision per round with the exact before-and-after text and a
real "leave it as is" option. Anything already in the project that it cannot explain is kept by
default — it did not write those rules and cannot see what they hold up.

The memory store is not version controlled, so it snapshots before writing and tells you where.

## Editing the kit

Edit it **here**, in the dotfiles repo, never in a copy. A copy is a transport that gets
deleted; a change made there is lost, and a change made through the symlink is a change to this
master without a commit message.
