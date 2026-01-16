# tmux Cheatsheet - Your Personal Configuration

## 🔑 **Prefix Key**
Your prefix is **`Ctrl + Space`** (not the default Ctrl+b)

---

## 📱 **Session Management**
| Action | Shortcut | Notes |
|--------|----------|-------|
| Start new session | `tmux new -s name` | Create named session |
| Attach to session | `tmux attach -t name` | Or use your `tat` function |
| List sessions | `tmux ls` | See all active sessions |
| Detach from session | `prefix + d` | Session keeps running in background |
| Kill current session | `prefix + x` → `y` | Completely closes session |

---

## 🪟 **Window Management**
| Action | Shortcut | Notes |
|--------|----------|-------|
| Create new window | `prefix + c` | Opens in current directory |
| Switch windows | `Shift + ←/→` | **No prefix needed!** |
| Switch windows (vim) | `Alt + H/L` | **No prefix needed!** |
| Previous window | `prefix + p` | |
| Next window | `prefix + n` | |
| Close window | `prefix + &` | Confirms before closing |
| Rename window | `prefix + ,` | |

---

## 🔲 **Pane Management**
| Action | Shortcut | Notes |
|--------|----------|-------|
| **Split vertically** | `prefix + %` | Creates side-by-side panes |
| **Split horizontally** | `prefix + "` | Creates top/bottom panes |
| **Switch panes (vim)** | `prefix + h/j/k/l` | Like vim navigation |
| **Switch panes (arrows)** | `Alt + ←/↑/↓/→` | **No prefix needed!** |
| **Break pane to window** | `prefix + b` | Promote pane to its own window |
| **Zoom pane** | `prefix + z` | Toggle fullscreen, press again to unzoom |
| **Kill current pane** | `prefix + x` | Confirms before closing |
| **Show pane numbers** | `prefix + q` | Numbers appear briefly on each pane |

---

## 📋 **Copy Mode (Scrolling & Copying)**
| Action | Shortcut | Notes |
|--------|----------|-------|
| **Enter copy mode** | `prefix + [` | Now you can scroll and select text |
| **Exit copy mode** | `q` or `Esc` | |
| **Start selection** | `v` | Like vim visual mode |
| **Rectangle selection** | `Ctrl + v` | Block selection |
| **Copy selection** | `y` | Copies and exits copy mode |
| **Search up** | `/` then type | Like vim search |
| **Search down** | `?` then type | |
| **Next search result** | `n` | |
| **Previous search result** | `N` | |

---

## ⚙️ **Configuration**
| Action | Shortcut | Notes |
|--------|----------|-------|
| **Reload config** | `prefix + r` | Test changes without restarting |
| **Install plugins** | `prefix + I` | After adding new plugins |
| **Update plugins** | `prefix + U` | Updates all plugins |

---

## 🔧 **Essential Commands**
| Action | Command | Notes |
|--------|---------|-------|
| Kill tmux server | `tmux kill-server` | Closes everything |
| List all commands | `prefix + ?` | Shows all available shortcuts |
| Show tmux info | `prefix + :` → `info` | System and session details |

---

## 💡 **Pro Tips**

### **Mouse Support**
- **Click** to switch panes
- **Drag** borders to resize panes  
- **Scroll** to navigate history
- **Select text** with mouse to copy

### **Quick Navigation**
- Use **Alt + arrows** for pane switching (fastest)
- Use **Shift + arrows** for window switching (fastest)
- Your vim-style `h/j/k/l` work great too with prefix

### **Workflow Tips**
- Use `prefix + z` to zoom a pane when you need focus
- Use `prefix + b` to break busy panes into separate windows
- Name your sessions with `tmux new -s project-name`
- Use copy mode (`prefix + [`) to search through command output

### **Status Bar Info**
Your status bar shows:
- **Current directory name** (right side)
- **CPU and RAM usage** (middle-right) 
- **Session name** (far right)

The CPU/RAM display format: "CPU: 15.2% RAM: 45.8%"
- Green = normal usage
- Yellow = medium usage (30%+)  
- Red = high usage (80%+)

---

## 🆘 **Emergency Commands**
- **Stuck?** → `Ctrl + C` to cancel current command
- **Can't type?** → `prefix + :` → `respawn-pane` → Enter
- **Lost session?** → `tmux attach` (attaches to last session)
- **Everything broken?** → `tmux kill-server` then start fresh