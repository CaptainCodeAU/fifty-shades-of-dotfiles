# tmux, archived

Gavin no longer uses tmux (herdr replaced it), but a lot of work went into this setup, so it
is kept here whole instead of deleted (Gavin, dotfiles-main Q80: 1, 19 Oct 2026). Nothing in
this folder is stowed or loaded: `archive/` is outside the `home/` package, so none of these
files reach `~`.

| File                 | What it is                                                              | Where it lived                                                                                                                     |
| -------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `.tmux.conf`         | tmux settings: prefix, panes, copy mode, tmux-tilit, TPM plugins        | `home/.tmux.conf`, linked to `~/.tmux.conf`, until 19 Oct 2026                                                                     |
| `.zsh_tmux`          | 24 zsh functions (`tdev`, `gs`, `gstatus`, `gswitch`, `gpr_quick`, ...) | `home/.zsh_tmux`, removed 15 Oct 2026 (commit 7c001cd) because no shell ever sourced it; restored here byte for byte from 7c001cd^ |
| `tmux_cheatsheet.md` | quick reference, including the functions and session layouts            | `docs/reference/tmux_cheatsheet.md`; this is its fuller version from 7c001cd^, before the 15 Oct cleanup cut those sections        |

To use tmux with these settings again, link the settings back:

```sh
ln -s ~/CODE/Scaffoldings/fifty-shades-of-dotfiles/archive/tmux/.tmux.conf ~/.tmux.conf
```

and, for the functions, add `source ~/CODE/Scaffoldings/fifty-shades-of-dotfiles/archive/tmux/.zsh_tmux` to `~/.zshrc.private`.
The `tmux()` wrapper in `home/.zsh_cursor_functions` passes `-f ~/.tmux.conf` only while that
file exists. `install.sh --skip-tmux` still skips the tmux formula and TPM.
