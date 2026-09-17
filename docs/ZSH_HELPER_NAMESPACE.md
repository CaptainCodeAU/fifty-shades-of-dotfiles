# Private shell helpers use `__double_underscore`

**Settled 2026-09-17.** Every private helper function in `home/.zsh*` is named
`__like_this`. A single leading underscore is reserved for real zsh completion
functions and nothing else. `zsh-helper-namespace-check` enforces it.

## 1. Why, in one line

Claude Code deletes single-underscore functions from the shell it hands its Bash
tool, so a helper named `_foo` does not exist inside any Claude session, while
the public function that calls it survives and fails.

## 2. The mechanism

Claude Code snapshots the interactive shell's functions at session start, writes
them to `~/.claude/shell-snapshots/snapshot-zsh-*.sh`, and sources that file
before every Bash tool call. It **drops every function whose name begins with a
single underscore**. That is a defensible choice on their side: in zsh, `_name`
is where the completion system lives, roughly 1,500 functions, and dumping them
into a snapshot file would be absurd. Double-underscore names are not filtered.

This is a naming collision with a Claude Code design decision, not a bug in this
repo. The breakage lands here, so the fix lives here.

Measured on this machine, same moment, two shells:

| pattern  | real interactive zsh | Claude Code shell |
| -------- | -------------------- | ----------------- |
| `^_[^_]` | 1563                 | **0**             |
| `^__`    | 18                   | 16                |

The second row is the control, and it is the reason the zero is a finding rather
than a broken probe. A count that reads `0` looks identical whether the
mechanism fired or the test never ran. Reproduce both arms together:

```sh
print -l ${(k)functions} | /usr/bin/grep -cE '^_[^_]'
print -l ${(k)functions} | /usr/bin/grep -cE '^__'
zsh -ic 'print -l ${(k)functions} | /usr/bin/grep -cE "^_[^_]"'
zsh -ic 'print -l ${(k)functions} | /usr/bin/grep -cE "^__"'
```

Use `/usr/bin/grep`, not bare `grep`. Inside a Claude session `grep` is a shell
function wrapping a bundled ugrep, and on a file with very long lines it has been
measured returning an empty count where the real binary returns 13.

## 3. What it actually broke

**17 public functions**, because each called at least one helper:

`create_node_envrc`, `node_check_global`, `node_clean`, `node_info`, `node_link`,
`node_new_project`, `node_setup`, `node_unlink`, `pnpm_update`,
`python_new_project`, `python_setup`, `run_onboarding`, `tmux`,
`uv_tool_check_current_project`, `uv_tool_install_current_project`,
`uv_tool_mode`, `uv_tool_reinstall_current_project`.

Two of those deserve singling out. `run_onboarding` needs 14 helpers, so
onboarding a new machine from inside a Claude session could not work at all.
`tmux` is a function override, so a command used constantly was degraded.

Plus **8 aliases** (`c`, `cb`, `cd_`, `ci`, `cpr`, `cr`, `cskip`, `ct`), which
the snapshot shipped as dangling references to `_claude_launch`, a function the
same snapshot had just deleted.

## 4. The part that mattered more than an error

Most of the 17 failed loudly with `command not found`. Two did not. They printed
the error on **stderr** and a **wrong answer on stdout**, which anything reading
`$(...)` believes. Measured against `cc-warehouse`, which IS installed and IS
frozen:

```
uv_tool_mode cc-warehouse
  Claude shell -> not-installed        (rc=1, error on stderr only)
  zsh -ic      -> frozen

uv_tool_check_current_project
  Claude shell -> "Not Found: Project 'cc-warehouse' is not currently installed
                   via uv tool. To install it, run: uv_tool_install_current_project"
  zsh -ic      -> "Found ... v0.1.4 ... Mode: FROZEN ... 2 executables"
```

The second one instructs you to install a tool that is already installed and
frozen. A caller branching on `uv_tool_mode` silently takes the wrong path.

**A trap when reproducing this.** Inside the Bash sandbox, `uv` cannot open
`~/.cache/uv`, so `uv tool list` returns empty and `uv_tool_mode` prints
`not-installed` **even with the helper present**. Run the repro with the sandbox
lifted, or you get the right answer for the wrong reason.

## 5. The rule

- Private helper in `home/.zsh*` → `__name`. No exceptions.
- Single underscore is reserved for functions registered with `compdef`. There
  are exactly two, and no public function calls either:
  `_node_new_project_completions` and `_uv_tool_project_extras`.
- A rename moves the definition **and every call site**, including alias bodies
  and comments.

## 6. The guard

`zsh-helper-namespace-check` sources the function files in a clean `zsh -f`,
applies the real filter by `unfunction`-ing every `^_[^_]` function, then reports
any surviving public function that still references a name which just vanished.
It tests against zsh's own parser rather than a regex over the files, so
reformatting is free and only a real behaviour change moves it.

```
zsh-helper-namespace-check              # 0 clean · 1 violation · 2 REFUSED
zsh-helper-namespace-check --selftest   # proves all three arms
zsh-helper-namespace-check --verbose    # list what got filtered
```

**Exit 2 is not a pass.** It means the check scanned nothing, or its control
function was missing after sourcing. Read the code, never the text, and treat a
refusal as an invalid trial rather than a clean bill of health.

## 7. Scope of the 2026-09-17 rename

52 helpers, 205 occurrences, 6 files (`.zshrc`, `.zsh_python_functions`,
`.zsh_node_functions`, `.zsh_onboarding`, `.zsh_welcome`,
`.zsh_cursor_functions`). Word-boundary replacement only.

Checks run before touching anything, each with a control:

- **External callers: zero.** All 54 names swept individually against
  `home/.local/bin`, `home/.config`, `home/.claude` and `install.sh`. The only
  hit was a docstring mention of `_claude_launch` in `vulnlib.py`.
- **Prefix hazard: exactly one pair**, `_ensure_nvm` inside `_ensure_nvm_current`.
  Handled by the word boundary, and the rename is idempotent because a preceding
  `_` blocks the match.
- **zsh-only**, but note the reason: there are no `.bash*` files in `home/` at
  all. The conclusion is drawn from an empty population, not a clean scan.

Verified after: `zsh -n` clean on all six with a known-bad file as the control,
and the filter simulated, after which `uv_tool_mode` returns `frozen` and
`uv_tool_check_current_project` reports `FROZEN` correctly.

## 8. Two method notes worth keeping

**A text scan attributes a doc comment to the wrong function.** The original
report listed 19 broken public functions. The real number is 17. `python_delete`
and `update_vscode_settings` call no helper at all; the doc-comment block sitting
_above_ a helper definition was being counted into the function _before_ it. Ask
zsh instead: `${functions[name]}` returns the parsed body, with comments already
gone. Two independent scans made this identical mistake before the parser settled
it.

**Fixing half a bad measurement is worse than fixing none.** The same report used
`\s*\(\)` in BSD grep ERE, where `\s` is a literal `s`. It ate the trailing `s`
from `_uv_tool_parse_flags` and `_node_new_project_completions`. The pattern was
corrected and the count re-run, but the **old mangled name list** was reused in
the write-up. The number was right and the names were wrong, which is harder to
spot than either being wrong alone.

## 9. Provenance

Found by the `cc-warehouse` session, which handed over the mechanism, the counts
and the `uv_tool_mode` symptom. Every number was re-derived here independently
against zsh's own parser before acting, which corrected the public count from 19
to 17, both named traps, and the `tmux` helper count.

The rename landed in commit `eb9880f`, whose message describes a concurrent herdr
hook fix instead: a second session committed while this one was staging, and its
`git commit` swept these files in. The code is correct and pushed; only the
commit message on record is silent about it. That is the whole reason this
document exists, and it is the rule this repo already had: **a decision recorded
only in a commit message does not exist.**
