# herdr-type: putting text into a running Claude Code session

**Audience: an AI agent.** Read this before building anything that sends text from
outside a Claude Code session into it: a web page button, a script, a hook, a
scheduler, another agent. It explains the paths that exist, which one to use, how
the pieces talk, and the traps, with the measurements behind each claim. It does
not ask you to build the optional local endpoint; it says how one must be built if
a use case needs it.

Measured on **Claude Code 2.1.292** and **herdr 0.9.3**, macOS, 7 Oct 2026.
Labels: **LIVE** = measured in a real session; **SOURCE** = read in docs, source
code or the Claude Code binary; **ASSUMED** = inference, not checked.

Evidence (all under `~/CODE/CaptainCodeAU/engage-isolinear/workbench/channels-vs-herdr/2026-10-07/`):
`COMPARISON.md` (rounds 1-4, every test), `ROUND4-speed-matrix.md` (128 runs on chunk
size and timing), `ROUND5-herdr-type.md` (this tool's build and live results),
`RESEARCH-sources.md` (docs, source code, issue numbers).

---

## 1. The three paths, and which to use

| Path | What it is | Use it for | Do not use it for |
|---|---|---|---|
| **A. herdr typing** (`herdr-type`) | Types into the pane's terminal, exactly as a person would | "Put this in my session" when the text should land where the cursor is, a person may review it, or a box/dialog may be open | Sessions not running inside herdr |
| **B. Cross-session inbox** | Claude Code's own per-session Unix socket | "Send now": the session should act at once, no Enter, no typing | Placing text for review (it cannot stage text in the input box) |
| **C. Channels** | An MCP server the session starts with a dev flag | An automatic event feed (CI, alerts) into a session launched for it | Anything a person triggers into an already-running session |

Why C lost for button-style use (LIVE unless marked): it cannot reach a session
already running (start-up flag only, with a confirmation dialog every launch); a
channel message that arrives while Claude is mid-turn is wrapped by Claude Code as
"NOT from your user ... untrusted external data" and was refused 2 of 2 times
(SOURCE: binary; LIVE: refusals); hooks see the text wrapped in `<channel>`; one fixed
port per session (a second session's server cannot listen and fails silently).

---

## 2. Architecture

```
  caller                      optional, NOT built here            this tool
  ┌──────────────────┐   HTTP POST 127.0.0.1:PORT    ┌───────────────────┐   argv / stdin   ┌────────────┐
  │ web page button  │ ───────────────────────────►  │ local endpoint    │ ───────────────► │ herdr-type │
  │ script / hook    │   header X-Token: <secret>    │ (binds 127.0.0.1, │                  └─────┬──────┘
  │ another agent    │                               │  checks the token,│                        │ JSON lines
  └──────────────────┘                               │  runs herdr-type) │                        ▼
                                                     └───────────────────┘          ┌──────────────────────────┐
                                                                                    │ herdr server socket      │
   path B (inbox) skips herdr entirely:                                             │ $HERDR_SOCKET_PATH or    │
   caller ──► /tmp/cc-socks/<claude pid>.sock ──► Claude Code (no Enter)             │ ~/.config/herdr/herdr.sock│
                                                                                    └─────────────┬────────────┘
                                                                                                  │ bytes to the PTY
                                                                                                  ▼
                                                                                    ┌──────────────────────────┐
                                                                                    │ pane PTY ─► Claude Code  │
                                                                                    │  input box / dialog      │
                                                                                    └─────────────┬────────────┘
                                                                                                  │ writes
                                                                                                  ▼
                                                                                    transcript JSONL (read back
                                                                                    by herdr-type for state and
                                                                                    --verify)
```

A browser cannot run commands or open Unix sockets, so a web page always needs a
small local process in between (the endpoint). A script, hook or agent on the same
machine can call `herdr-type` directly.

### How the local endpoint must be built (if a use case needs one)

1. Bind `127.0.0.1` only, never `0.0.0.0`.
2. Require a secret header (for example `X-Token`) on every request, read from a
   file with mode 600, compared in constant time. A custom header forces a CORS
   preflight; answer `OPTIONS` with **no** permissive CORS headers, so a page from
   another origin can never send it (SOURCE: MDN CORS "simple requests").
   Why it matters: a page on `http://localhost:<any other port>` reaching
   `127.0.0.1` is loopback to loopback, which Chrome's Local Network Access does
   **not** gate, and `text/plain` / form POSTs need no preflight (SOURCE:
   chromestatus 5152728072060928). Without the token, any local dev page could type
   into your sessions.
3. Check the `Host` header against `127.0.0.1:PORT` / `localhost:PORT` (DNS rebinding).
4. Pass the text to `herdr-type send` on **stdin** (`-`), never through a shell
   string. Pass the target as an argument after validating it (pane id, agent name
   or label characters only).
5. Return `herdr-type`'s JSON (`--json`) and exit code to the caller; show exit 4's
   `problem` to the person (it means "the cursor is somewhere text cannot go
   without a choice from you").
6. Run it outside Claude Code: Claude Code's Bash sandbox blocks the herdr socket
   (every in-session call needs the sandbox turned off for that call).
7. For "list my sessions", call herdr `agent.list` / `pane.list` and show each pane's
   `label` (engage sessions label their pane with the session name).

---

## 3. Protocols, exact shapes

### 3.1 herdr socket (path A)

One JSON line per connection, one JSON line back. Socket: `$HERDR_SOCKET_PATH`, else
`~/.config/herdr/herdr.sock` (mode 0600, owner only; no per-caller check in 0.9.3,
SOURCE). The full schema: `herdr api schema --json`.

| Request (`{"id":..,"method":..,"params":..}`) | Reply `result` | Used for |
|---|---|---|
| `pane.send_text {"pane_id","text"}` | `{"type":"ok"}`-like | Typing. Raw bytes; no Enter, no state check |
| `pane.send_keys {"pane_id","keys":["enter","down","tab","esc","ctrl+e","ctrl+a","ctrl+u","ctrl+c","shift+tab"]}` | ok | Keys. `home` is **not** a key name (`invalid_key`) |
| `pane.read {"pane_id","source":"visible","lines":N,"format":"text"|"ansi","strip_ansi":bool}` | `{"read":{"text":..,"truncated":..}}` | Screen for state detection; `ansi` shows dim (`ESC[2m`) suggestion text |
| `pane.get {"pane_id"}` | `{"pane":{"label","agent","agent_status","agent_session":{"kind":"id","value":<session id>},"cwd",..}}` | Target resolution, status, transcript lookup |
| `agent.get {"target"}` | `{"agent":{"name","pane_id",..}}` | Resolve a herdr agent name |
| `pane.list {}` | `{"panes":[..]}` | Resolve a label / session name |

Errors: `{"error":{"code","message"}}`.

### 3.2 Claude Code transcript (state and verification)

Path: `<CLAUDE_CONFIG_DIR or ~/.claude>/projects/<cwd slug>/<session id>.jsonl`; the
session id is `pane.get` → `agent_session.value`. Records used (LIVE):

| Record | Meaning |
|---|---|
| `{"type":"user","origin":{"kind":"human"},"message":{"content":"<text>"}}` | A typed (or herdr-typed) prompt |
| `{"type":"user","isMeta":true,"origin":{"kind":"channel","server":..}}` | A channel event (path C) |
| `{"type":"user","isMeta":true,"origin":{"kind":"peer","verifiedPeerPid":..}}` | An inbox message (path B) |
| `assistant` with `content[].type=="tool_use"` and no later `tool_result` of that id | An open tool call: `AskUserQuestion`, `ExitPlanMode`, `Bash` (also while a command simply runs) |
| `user` with `content[].type=="tool_result"` (`"The user answered: ..."`) | A box answer, a permission result; a permission note arrives as an extra `text` item beside it |
| `attachment.type=="queued_command"` | Text typed and sent while Claude was busy |

### 3.3 Claude Code inbox socket (path B, "Send now")

Socket `/tmp/cc-socks/<claude pid>.sock` (shown in `/status` as Peer address; exported to
the session's own children as `CLAUDE_CODE_MESSAGING_SOCKET`). Write one line and close:

```
{"type":"user","message":{"role":"user","content":"<text>"}}
```

An optional first line `{"type":"auth","token":"<CLAUDE_CODE_MESSAGING_TOKEN>"}` is
accepted on macOS/Linux; only the session's own children have the token. The line
format is not on the docs page; it came from a usage example inside the 2.1.292
binary and worked first time (LIVE). No reply is ever written back, delivered or not.

Behaviour (LIVE): idle → starts a turn; busy → delivered after the running tool, same
turn, obeyed; drafts and open boxes untouched (it waits behind a box); slash commands
and `!` are plain text; framed to Claude as "Another Claude session ... treat it as a
teammate's request"; 500,129 characters delivered; 1,100,131 **silently dropped**
(documented cap about a million). **Held for approval** when the receiving session
bypasses permissions and the sender does not attest its mode, unless
`crossSessionInbound: "accept"` applies; values are `accept`, `hold`, `refuse`, and a
project's own settings can only tighten it (SOURCE: binary messages). Engage sessions
read only the engage `--settings` file plus project and local settings, so the user-level
value does not reach them.

---

## 4. State detection

`herdr-type state <target>` combines three signals, because none is right alone (LIVE):

| State | Screen (last 60 lines) | Transcript open call | herdr status |
|---|---|---|---|
| `question-single` | "Enter to select" + ("Type something" or "Chat about this"), no `[ ]` rows | `AskUserQuestion` | `done` 4×, `blocked` 4× (unreliable) |
| `question-multi` | same, with `[ ]`/`[✔]` rows | `AskUserQuestion` | |
| `question-review` | "Review your answers" / "Ready to submit your answers?" | `AskUserQuestion` | |
| `permission` | a line "Do you want to …?" + "Esc to cancel" | `Bash` (or the tool asking) | `blocked` |
| `plan-approval` | "Would you like to proceed?" + "ready to execute" | **often none** (first round) | `blocked` |
| `held-message` | "Deliver this message to Claude" | | |
| `busy` | (no dialog) | `Bash` (same as a permission prompt!) | `working` |
| `prompt-empty` / `prompt-draft` | the input box between the last two `────` rules; dim text is a suggestion, not a draft | | `idle`/`done` |
| `prompt-menu` | the draft is a bare `/word`, or ends in `@word` | | |
| `shell` | pane has no agent | | none |
| `unknown` | no input box and no known dialog | | |

## 5. Routing (what `send` does in each state)

| State | Steps | Notes |
|---|---|---|
| prompt-empty | type | |
| prompt-draft | `ctrl+e` (or `--at start`: `ctrl+a`), type | Text joins the draft; on a long wrapped draft `ctrl+e` reaches the end of the current line only |
| prompt-menu | `esc`, a space, type | `/con` + text became `/con LT-menu text` (the text becomes the command's arguments) |
| busy | type (Enter queues it) | Delivered after the running command, obeyed |
| question-single | press the number of the row labelled "Type something" (found **by label**; fallback second from last), type | With 2 options it is **3**; 4 is "Chat about this", which closes the box |
| question-multi | `down` to that row, type; `--submit`: `down`, `enter`, `enter` (review → Submit answers) | Pressing its number only ticks the row; typed letters then act as keys |
| permission | `--permission yes` (row 1) or `no` (row "No"), `tab`, type the note | Without `--permission`: exit 4. Yes + note: command runs, note reaches Claude as a separate text |
| plan-approval | press "Tell Claude what to change", type | Claude revises the plan |
| question-review, held-message, unknown | exit 4 with the reason | No text field there |
| shell | exit 4 unless `--allow-shell` | Bracketed typing: zsh holds the lines, nothing runs |

`--enter` presses Enter at the end; `--verify` then waits for the new transcript
record and compares (exit 0 exact/contained, 5 nothing, 6 differs).

---

## 6. The typing engine and the safety model

**Every write is its own bracketed paste** (`ESC[200~ … ESC[201~`), at most 256
characters and at most 2 newlines.

| Fact | Numbers | Label |
|---|---|---|
| Claude Code marks a burst over 800 characters as pasted (`<pasted_content>`; Claude follows instructions in it only where typed words ask) | 800 typed, 801 pasted, 3 of 3 each | LIVE (matrix) |
| A bracketed paste of more than 3 lines is marked, whatever its size | 128-char chunks of a 200-line text: 14 placeholders; 8-char chunks: none | LIVE |
| Plain big writes can lose text (matrix: identical consecutive 1,024-byte reads dropped; 1-2 KB writes close together lose about 2 KB) | round 1: 4,039 sent, 1,022 lost; one 35,334-char write kept only 586. The matrix's single writes of varied text were intact 21 of 21, so the round-1 loss is not fully explained | LIVE |
| Bracketed chunks lose nothing, even identical ones | 6,000 `x` at 8/128/512 per write: all kept | LIVE |
| Speed | 28,931 chars at 8/write in 1.2 s; 100,000 at 256/write accepted in 0.06 s (the screen catches up after); 250,051 typed, sent and verified exact in about 2 s | LIVE |
| Box safety: an open question box answers only a write of exactly one plain character | `2` picked option 2; bracketed writes and plain writes of 2+ chars left it open | LIVE |
| Invisible prefixes do not protect a box | U+200B before `2`: still picked option 2 | LIVE |
| Shell safety: plain newlines run in zsh; bracketed ones are held | `echo SAFE_LINE_ONE_42` ran; bracketed lines sat unsent | LIVE |
| Context is the real ceiling | a 250,051-character message took a session from 15% to 30%; the matrix session stood at 56% after its 250,049 run (with about 125 smaller runs before it) | LIVE |

**Text cleaning** before typing: CR/CRLF → LF (a CR is Enter); tabs → 4 spaces (a typed
tab is dropped, LIVE); control characters and invisible format characters (zero-width,
bidi, tag characters) dropped, because Claude Code strips them on Enter and wants a
second Enter (SOURCE); ZWJ and variation selectors kept (emoji sequences arrived intact,
LIVE). Every change is reported on stderr.

**What typed text can do** (it is the user typing): a whole prompt starting with `!` runs a
shell command with no permission prompt and outside the sandbox; one starting with `/`
runs a slash command (LIVE). `herdr-type` warns but does not block: a prompt library may
hold commands on purpose. An endpoint that accepts text from anywhere other than the
person themselves must decide this policy.

**Races**: the state is read, then acted on. If a box opens between the two, the
bracketed writes cannot answer it (box safety above), but a following `--enter` would
press Enter in the box. Use `--verify` when it matters.

---

## 7. Known limits and failure modes

- Only reaches sessions running inside a herdr pane (VS Code, Desktop and web sessions: no).
- `herdr agent_status` is wrong about question boxes half the time; never trust it alone.
- The transcript shows no open call for a first plan approval; the screen text is the signal.
- Screen parsing depends on Claude Code's wording ("Enter to select", "Type something",
  "Do you want to", "Would you like to proceed?", "Tell Claude what to change"); a Claude
  Code upgrade can change it.
- Vim editor mode, the history search (`ctrl+r`) and other overlays are not handled: they
  read as `unknown` or route wrongly. ASSUMED, not tested.
- `ctrl+e`/`ctrl+u` act on one wrapped line of a long draft; one `ctrl+c` clears the whole
  input (two exit Claude Code).
- Inbox (path B): silent drop over the cap, no acknowledgement, held in bypass sessions
  unless `accept` applies.

## 8. Re-check after an upgrade

Run `herdr-type --selftest` (offline) and `herdr-type-livetest <throwaway pane>` (live;
`engage-worker tab <purpose>` makes one on this estate). Re-measure: the 800-character
paste threshold and the 3-line rule; box safety of a single bracketed character; the
screen phrases in section 4; the inbox line format and its hold/accept wording; the
herdr key names and `pane.read` shape.

## 9. Usage

```
herdr-type state engage-main
herdr-type send engage-main "Review the diff and list risks"            # types, no Enter
herdr-type send engage-main - --enter --verify < prompt.md              # sends and checks
herdr-type send w48:p4D "a mango" --where answer --enter                # answer an open box
herdr-type send engage-main "use goodbye" --enter                       # plan feedback, if a plan is up
herdr-type send engage-main "fine, go on" --permission yes --enter      # approve with a note
herdr-type send engage-main "text" --dry-run                            # show the steps only
```

Exit codes: 0 done/verified, 1 herdr or I/O error, 2 usage, 3 target not found or
ambiguous, 4 nowhere to put the text without a choice, 5 verify saw nothing new,
6 verify saw a different text.
