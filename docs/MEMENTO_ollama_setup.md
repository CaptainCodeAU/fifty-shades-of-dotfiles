# Ollama Local AI Setup

> **Memento File** - A complete guide for future-you who has forgotten everything.
>
> Last Updated: February 23, 2026

**Machine:** Mac Mini (Apple M4, 32 GB unified memory, macOS 26.3)
**Ollama version:** 0.16.2 (installed via Homebrew)

---

## TL;DR - Quick Reference

```bash
# Start Ollama (server + preload)
ollama-up

# Stop Ollama
ollama-down

# Check loaded models
ollama ps

# System monitor (includes Ollama status)
sysinfo

# Manually load a model (keep forever)
curl -s http://localhost:11434/api/generate -d '{"model": "coreworxlab/caal-ministral:latest", "keep_alive": -1}'

# Manually unload a model
curl -s http://localhost:11434/api/generate -d '{"model": "coreworxlab/caal-ministral:latest", "keep_alive": 0}'
```

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  launchctl (macOS LaunchAgent)                      │
│                                                     │
│  com.ollama.serve     → ollama serve (API server)   │
│  com.ollama.preload   → curl loop (model loader)    │
│                                                     │
├─────────────────────────────────────────────────────┤
│  Ollama API: http://localhost:11434                  │
│  Endpoints: /api/generate, /api/chat, /api/ps       │
├─────────────────────────────────────────────────────┤
│  Model: coreworxlab/caal-ministral:latest           │
│  Size: ~7.8 GB VRAM (100% GPU)                      │
│  Context: 16384 tokens                              │
│  Keep-alive: forever (-1)                           │
└─────────────────────────────────────────────────────┘
```

---

## Installed Models

| Model                             | ID           | Size on Disk | VRAM When Loaded |
| --------------------------------- | ------------ | ------------ | ---------------- |
| coreworxlab/caal-ministral:latest | 6f87eab214dc | 5.2 GB       | 7.8 GB           |
| mistral:7b                        | 6577803aa9a0 | 4.4 GB       | ~5 GB            |

Only `coreworxlab/caal-ministral:latest` is auto-loaded. `mistral:7b` is available but not preloaded.

---

## LaunchAgent Configuration

We use `launchctl` directly instead of `brew services` because Homebrew regenerates/overwrites its plist files on start/stop, which destroys custom environment variables and configuration.

### File Locations

| File           | Path                                              | Purpose                 |
| -------------- | ------------------------------------------------- | ----------------------- |
| Server plist   | `~/Library/LaunchAgents/ollama-custom.plist`      | Runs `ollama serve`     |
| Preload plist  | `~/Library/LaunchAgents/com.ollama.preload.plist` | Keeps model loaded      |
| Server log     | `/opt/homebrew/var/log/ollama.log`                | Server output           |
| Preload log    | `/opt/homebrew/var/log/ollama-preload.log`        | Preload output          |
| Ollama binary  | `/opt/homebrew/opt/ollama/bin/ollama`             | Installed via Homebrew  |
| sysinfo script | `~/sysinfo.sh`                                    | System & Ollama monitor |

### Environment Variables (Server)

| Variable               | Value         | Purpose                                                       |
| ---------------------- | ------------- | ------------------------------------------------------------- |
| OLLAMA_FLASH_ATTENTION | 1             | Enables flash attention for faster inference on Apple Silicon |
| OLLAMA_KV_CACHE_TYPE   | q8_0          | Quantized KV cache to reduce memory usage                     |
| OLLAMA_NUM_PARALLEL    | 2             | Allows 2 concurrent requests (default is 1)                   |
| OLLAMA_HOST            | 0.0.0.0:11434 | Listens on all interfaces (accessible from local network)     |

### ollama-custom.plist (Server)

**Label:** `com.ollama.serve`

- `RunAtLoad: true` — starts automatically on login
- `KeepAlive: true` — launchd restarts it if it crashes

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
 <key>EnvironmentVariables</key>
 <dict>
  <key>OLLAMA_FLASH_ATTENTION</key>
  <string>1</string>
  <key>OLLAMA_KV_CACHE_TYPE</key>
  <string>q8_0</string>
  <key>OLLAMA_NUM_PARALLEL</key>
  <string>2</string>
  <key>OLLAMA_HOST</key>
  <string>0.0.0.0:11434</string>
 </dict>
 <key>KeepAlive</key>
 <true/>
 <key>Label</key>
 <string>com.ollama.serve</string>
 <key>LimitLoadToSessionType</key>
 <array>
  <string>Aqua</string>
  <string>Background</string>
  <string>LoginWindow</string>
  <string>StandardIO</string>
  <string>System</string>
 </array>
 <key>ProgramArguments</key>
 <array>
  <string>/opt/homebrew/opt/ollama/bin/ollama</string>
  <string>serve</string>
 </array>
 <key>RunAtLoad</key>
 <true/>
 <key>StandardErrorPath</key>
 <string>/opt/homebrew/var/log/ollama.log</string>
 <key>StandardOutPath</key>
 <string>/opt/homebrew/var/log/ollama.log</string>
 <key>WorkingDirectory</key>
 <string>/opt/homebrew/var</string>
</dict>
</plist>
```

### com.ollama.preload.plist (Model Loader)

**Label:** `com.ollama.preload`

Runs a bash loop that:

1. Waits 10 seconds (for the server to be ready)
2. Sends a curl request to load `coreworxlab/caal-ministral:latest` with `keep_alive: -1` (forever)
3. Sleeps 300 seconds (5 minutes)
4. Repeats

This ensures the model stays loaded even if the Ollama server restarts. The curl call is a no-op if the model is already loaded.

- `RunAtLoad: true` — starts automatically on login
- `KeepAlive: true` — launchd restarts it if it dies

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
 <key>Label</key>
 <string>com.ollama.preload</string>
 <key>ProgramArguments</key>
 <array>
  <string>/bin/bash</string>
  <string>-c</string>
  <string>while true; do sleep 10; /usr/bin/curl -s -o /dev/null http://localhost:11434/api/generate -d '{"model": "coreworxlab/caal-ministral:latest", "keep_alive": -1}' 2>/dev/null; sleep 300; done</string>
 </array>
 <key>RunAtLoad</key>
 <true/>
 <key>KeepAlive</key>
 <true/>
 <key>StandardErrorPath</key>
 <string>/opt/homebrew/var/log/ollama-preload.log</string>
 <key>StandardOutPath</key>
 <string>/opt/homebrew/var/log/ollama-preload.log</string>
</dict>
</plist>
```

---

## Common Operations

### Start/Stop Services

```bash
# Load both services (or use: ollama-up)
launchctl load ~/Library/LaunchAgents/ollama-custom.plist
launchctl load ~/Library/LaunchAgents/com.ollama.preload.plist

# Stop both services (or use: ollama-down)
launchctl unload ~/Library/LaunchAgents/com.ollama.preload.plist
launchctl unload ~/Library/LaunchAgents/ollama-custom.plist

# Check status
launchctl list | grep ollama
```

**Note:** Always unload the preload before the server when stopping, and load the server before the preload when starting.

### Manually Load/Unload a Model

```bash
# Load a model (keep forever)
curl -s http://localhost:11434/api/generate -d '{"model": "coreworxlab/caal-ministral:latest", "keep_alive": -1}'

# Unload a model
curl -s http://localhost:11434/api/generate -d '{"model": "coreworxlab/caal-ministral:latest", "keep_alive": 0}'

# Check loaded models
ollama ps
```

### Check Logs

```bash
# Server logs
tail -f /opt/homebrew/var/log/ollama.log

# Preload logs
cat /opt/homebrew/var/log/ollama-preload.log
```

### List/Manage Models

```bash
ollama list              # List all downloaded models
ollama ps                # List currently loaded models
ollama pull <model>      # Download a new model
ollama rm <model>        # Remove a model
ollama show <model>      # Show model details
```

---

## API Usage

The local macOS application communicates with Ollama via HTTP on `http://localhost:11434`.

### Generate (single response)

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "coreworxlab/caal-ministral:latest",
  "prompt": "Your prompt here",
  "stream": false
}'
```

### Chat (multi-turn conversation)

```bash
curl http://localhost:11434/api/chat -d '{
  "model": "coreworxlab/caal-ministral:latest",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"}
  ],
  "stream": false
}'
```

### Check Loaded Models

```bash
curl -s http://localhost:11434/api/ps
```

---

## Memory Considerations

- Total system RAM: 32 GB (unified, shared between CPU and GPU)
- `coreworxlab/caal-ministral:latest` uses ~7.8 GB when loaded
- Loading both models simultaneously would use ~13 GB, leaving limited headroom
- Default model timeout is 5 minutes; we override with `keep_alive: -1` (forever)
- The preload loop re-checks every 5 minutes, so after a server restart the model will be reloaded within 5 minutes
- Context window (16384 tokens) can be increased with `"options": {"num_ctx": 32768}` in the API call, at the cost of more memory

---

## Monitoring

A custom system monitor script is available at `~/sysinfo.sh` (aliased as `sysinfo`). It displays:

- Memory usage with health status and pressure
- CPU usage and load average
- Ollama server status and loaded models (tabular)
- App memory totals (grouped by application)
- Top processes by memory and CPU
- LaunchAgent status

---

## Troubleshooting

| Symptom                          | Cause                                             | Fix                                                                              |
| -------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------- |
| "Server not running" in sysinfo  | ollama-custom.plist not loaded                    | `ollama-up` or `launchctl load ~/Library/LaunchAgents/ollama-custom.plist`       |
| "No models loaded"               | Preload hasn't cycled yet, or preload not running | Wait 5 min, or manually curl to load, or check `launchctl list \| grep ollama`   |
| MLX dynamic library warning      | Normal on Homebrew installs                       | No action needed (can be ignored)                                                |
| brew services overwrites plist   | Used `brew services start` instead of `launchctl` | Always use `launchctl load/unload` with our custom plists                        |
| Model loads slowly after restart | Model being loaded from disk into GPU memory      | Normal; takes 10-30 seconds depending on model size                              |
| High memory usage                | Model + apps exceeding 32 GB                      | Check `sysinfo`, close unused apps, or unload unused models with `keep_alive: 0` |

---

## Important Notes

- **Do not use `brew services` for Ollama.** It will overwrite the custom plist and lose environment variables. Always use `launchctl load/unload` or the `ollama-up`/`ollama-down` aliases.
- **OLLAMA_HOST is set to 0.0.0.0** which exposes the API to the local network. Change to `127.0.0.1:11434` in the plist if local-only access is preferred.
- **The preload agent is a long-running loop**, not a one-shot. It will show as `running` in `launchctl list`, not `done`.
- **Port 11434** is the default Ollama port.
