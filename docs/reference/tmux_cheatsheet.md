# tmux Cheatsheet — Your Personal Configuration

## Prefix Key

Your prefix is **`Ctrl + Space`** (not the default Ctrl+b)

---

## Session Management

| Action               | Shortcut / Command    | Notes                               |
| -------------------- | --------------------- | ----------------------------------- |
| Start new session    | `tmux new -s name`    | Create named session                |
| Attach to session    | `tmux attach -t name` | Reattach to existing                |
| List sessions        | `tmux ls`             | See all active sessions             |
| Detach from session  | `prefix + d`          | Session keeps running in background |
| Kill current session | `prefix + x` then `y` | Completely closes session           |
| Kill tmux server     | `tmux kill-server`    | Closes everything                   |
| List all keybindings | `prefix + ?`          | Shows all available shortcuts       |
| Command prompt       | `prefix + :`          | Enter tmux commands                 |

---

## Window Management

| Action               | Shortcut             | Notes                      |
| -------------------- | -------------------- | -------------------------- |
| Create new window    | `prefix + c`         | Opens in current directory |
| Switch windows       | `Shift + Left/Right` | **No prefix needed**       |
| Switch windows (vim) | `Alt + H / L`        | **No prefix needed**       |
| Previous window      | `prefix + p`         |                            |
| Next window          | `prefix + n`         |                            |
| Go to window N       | `prefix + 1-9`       | Windows start at 1         |
| Close window         | `prefix + &`         | Confirms before closing    |
| Rename window        | `prefix + ,`         |                            |

---

## Pane Management

| Action                    | Shortcut           | Notes                          |
| ------------------------- | ------------------ | ------------------------------ |
| Split horizontal (bottom) | `prefix + "`       | Preserves current path         |
| Split vertical (right)    | `prefix + %`       | Preserves current path         |
| Split horizontal (alt)    | `prefix + -`       | More intuitive                 |
| Split vertical (alt)      | `prefix + \|`      | More intuitive                 |
| Split right (arrow)       | `prefix + Right`   | Arrow-like binding             |
| Split down (arrow)        | `prefix + Down`    | Arrow-like binding             |
| Switch panes (vim)        | `prefix + h/j/k/l` | Like vim navigation            |
| Switch panes (arrows)     | `Alt + Arrow`      | **No prefix needed**           |
| Break pane to window      | `prefix + b`       | Promote pane to its own window |
| Zoom pane (toggle)        | `prefix + z`       | Fullscreen toggle              |
| Kill current pane         | `prefix + x`       | Confirms before closing        |
| Show pane numbers         | `prefix + q`       | Numbers appear briefly         |

---

## Copy Mode (Scrolling & Copying)

Uses vim keybindings.

| Action                 | Shortcut      | Notes                      |
| ---------------------- | ------------- | -------------------------- |
| Enter copy mode        | `prefix + [`  | Enables scroll and select  |
| Exit copy mode         | `q` or `Esc`  |                            |
| Start selection        | `v`           | Like vim visual mode       |
| Rectangle selection    | `Ctrl + v`    | Block selection            |
| Copy selection         | `y`           | Copies and exits copy mode |
| Search up              | `/` then type | Like vim search            |
| Search down            | `?` then type |                            |
| Next search result     | `n`           |                            |
| Previous search result | `N`           |                            |

---

## Configuration & Plugins

| Action                | Shortcut     | Notes                      |
| --------------------- | ------------ | -------------------------- |
| Reload config         | `prefix + r` | Shows "Config 2 reloaded!" |
| Install plugins (TPM) | `prefix + I` | After adding to .tmux.conf |
| Update plugins (TPM)  | `prefix + U` | Updates all plugins        |

### Installed Plugins

| Plugin             | Purpose                          |
| ------------------ | -------------------------------- |
| tpm                | Plugin manager                   |
| tmux-sensible      | Sensible defaults                |
| tmux-cpu           | CPU/RAM in status bar            |
| catppuccin/tmux    | Mocha theme                      |
| vim-tmux-navigator | Seamless vim/tmux pane switching |
| tmux-yank          | System clipboard integration     |
| tmux-tilit         | Tiling window management         |

### Status Bar

Right side shows: **directory** | **CPU: X% RAM: X%** | **session name**

---

## Mouse Support

- **Click** to switch panes
- **Drag** borders to resize panes
- **Scroll** to navigate history
- **Select text** with mouse to copy

---

## Tips

- `Shift + Enter` sends a normal Enter (reclaimed from tmux-tilit for Claude Code newlines)
- Cursor/VSCode env vars auto-sync to all panes on `tmux attach` via client-attached hook
- Window numbering starts at 1 and auto-renumbers on close (no gaps)
- History limit is 102,400 lines (50x default)
- ESC delay reduced to 10ms for snappy vim/nvim

---

## Emergency

| Problem           | Fix                                         |
| ----------------- | ------------------------------------------- |
| Stuck / frozen    | `Ctrl + C` to cancel                        |
| Can't type        | `prefix + :` then `respawn-pane` then Enter |
| Lost session      | `tmux attach` (attaches to last)            |
| Everything broken | `tmux kill-server` then start fresh         |
