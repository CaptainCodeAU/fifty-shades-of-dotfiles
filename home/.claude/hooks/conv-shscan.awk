# conv-shscan.awk -- the zsh command scanner shared by the convention hooks.
#
# Used by enforce-uv.sh and enforce-pnpm.sh (beside this file, stowed to
# ~/.claude/hooks/) and by this repo's project-only .claude/hooks/enforce-no-cd.sh
# (which reaches it through the repo path home/.claude/hooks/). NOT a hook itself:
# nothing registers it, the three hooks run it with `awk -f`.
#
# WHY A SCANNER AND NOT A REGEX. Until 2026-09-23 each hook stripped "$(...)",
# "..." and '...' with sed and grepped what was left. A deny can live with that; a
# REWRITE cannot, because it needs the exact position of the word to change in the
# ORIGINAL text. The sed strip was also wrong: `s/\$\([^)]*\)//` stops at the first
# ")" even inside a quoted string, so `o=$(tool "a (b) c" --x "(cd into ...)")`
# went out of step and the prose "(cd into" reached command position (a real false
# positive, 2026-09-23). This scanner walks the text once, the way zsh tokenises it:
# quotes, $'...', backslashes, $(...), ${...}, $((...)), backticks, <(...) >(...)
# =(...), here-documents (bodies skipped, <<- strips tabs), here-strings, comments,
# redirections with fd numbers, glob qualifiers like *(.), [[ ... ]], (( ... )),
# subshells, { } groups, and the separators ; && || | |& & &! &| and newline.
#
# WHAT IT DOES NOT TRY TO UNDERSTAND, and flags as UNSURE instead: case clauses,
# function definitions, coproc, select, foreach and zsh's short `for x (...)`
# forms, unbalanced quotes or brackets, and a here-document with no terminator.
# UNSURE never allows a rewrite: a hook that finds its target in an UNSURE command
# DENIES, exactly as it did before rewriting existed.
#
# Commands inside $(...), backticks and process substitutions are PARSED (to find
# where they end) but NOT RECORDED, so no hook rewrites or denies inside them. That
# matches the old strip, which deleted them before looking.
#
# Byte offsets: run with LC_ALL=C so every awk counts bytes the same way.
#
# Input:  the Bash tool's command on stdin.
# Env:    CONV_MODE = uv | pnpm | nocd   (which hook is asking)
#         CONV_CWD  = the payload's cwd (npx looks for a local binary from here)
# Output: line 1  ALLOW | DENY | REWRITE
#         line 2  one-line message for the session (DENY reason or what changed)
#         line 3+ REWRITE only: the new command, verbatim
#
# ASCII only in this file.

# ------------------------------------------------------------------ scanner

function unsure(why) { if (UNSURE == "") UNSURE = why }

function new_cmd(rec, depth, sep) {
    if (!rec) return -1
    NC++; CD[NC] = depth; CSB[NC] = sep; CSA[NC] = ""; CNW[NC] = 0; CEND[NC] = 0
    return NC
}

function add_word(k, s, e, q,    n) {
    if (k <= 0) return
    n = ++CNW[k]
    WS[k, n] = s; WE[k, n] = e; WR[k, n] = substr(S, s, e - s + 1); WQ[k, n] = q
    CEND[k] = e
}

function end_cmd(k, sep) { if (k > 0 && CSA[k] == "") CSA[k] = sep }

function skip_blanks() {
    while (P <= N) {
        if (C[P] == " " || C[P] == "\t") { P++; continue }
        if (C[P] == "\\" && C[P + 1] == "\n") { P += 2; continue }
        break
    }
}

function skip_squote() {    # P at the opening '
    P++
    while (P <= N && C[P] != "'") P++
    if (P > N) unsure("unterminated single quote")
    P++
}

function skip_backtick() {  # P at the opening `
    P++
    while (P <= N && C[P] != "`") { if (C[P] == "\\") P++; P++ }
    if (P > N) unsure("unterminated backtick")
    P++
}

function skip_cmdsub() {    # P at the "(" of $( ; handles $(( too
    if (C[P + 1] == "(") { skip_parens(); return }
    P++
    parse_list(0, ")", 0, "")
}

function parse_dq(    c) {  # P at the opening "
    P++
    while (P <= N) {
        c = C[P]
        if (c == "\\") { P += 2; continue }
        if (c == "\"") { P++; return }
        if (c == "`") { skip_backtick(); continue }
        if (c == "$" && C[P + 1] == "(") { P++; skip_cmdsub(); continue }
        if (c == "$" && C[P + 1] == "{") { P += 2; skip_brace_param(); continue }
        P++
    }
    unsure("unterminated double quote")
}

function skip_brace_param(    d, c) {  # P just after "${"
    d = 1
    while (P <= N) {
        c = C[P]
        if (c == "\\") { P += 2; continue }
        if (c == "'") { skip_squote(); continue }
        if (c == "\"") { parse_dq(); continue }
        if (c == "`") { skip_backtick(); continue }
        if (c == "$" && C[P + 1] == "(") { P++; skip_cmdsub(); continue }
        if (c == "$" && C[P + 1] == "{") { d++; P += 2; continue }
        if (c == "}") { d--; P++; if (d == 0) return; continue }
        P++
    }
    unsure("unterminated ${")
}

function skip_parens(    d, c) {  # P at "(": glob qualifiers, $((..)), ((..))
    d = 0
    while (P <= N) {
        c = C[P]
        if (c == "\\") { P += 2; continue }
        if (c == "'") { skip_squote(); continue }
        if (c == "\"") { parse_dq(); continue }
        if (c == "`") { skip_backtick(); continue }
        if (c == "(") d++
        else if (c == ")") { d--; if (d == 0) { P++; return } }
        P++
    }
    unsure("unbalanced parentheses")
}

function skip_brackets(    d, c) {  # P at "[" of $[...]
    d = 0
    while (P <= N) {
        c = C[P]
        if (c == "[") d++
        else if (c == "]") { d--; if (d == 0) { P++; return } }
        P++
    }
    unsure("unterminated $[")
}

# One word, from P. Sets WQF=1 when the word holds any quoting, escape or
# expansion, i.e. when its text is not simply what zsh would run.
function parse_word(    c, n, ws) {
    WQF = 0; ws = P
    while (P <= N) {
        c = C[P]
        if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "<" || c == ">" || c == ")") break
        if (c == "(") {
            if (P == ws + 1 && C[ws] == "=") { P++; parse_list(0, ")", 0, ""); WQF = 1; continue }  # zsh =(...)
            skip_parens(); continue                    # glob qualifier or pattern group
        }
        if (c == "'") { skip_squote(); WQF = 1; continue }
        if (c == "\"") { parse_dq(); WQF = 1; continue }
        if (c == "\\") { P += 2; WQF = 1; continue }
        if (c == "`") { skip_backtick(); WQF = 1; continue }
        if (c == "$") {
            n = C[P + 1]; WQF = 1
            if (n == "'") {
                P += 2
                while (P <= N && C[P] != "'") { if (C[P] == "\\") P++; P++ }
                if (P > N) unsure("unterminated $'")
                P++; continue
            }
            if (n == "\"") { P++; parse_dq(); continue }
            if (n == "(") { P++; skip_cmdsub(); continue }
            if (n == "{") { P += 2; skip_brace_param(); continue }
            if (n == "[") { P++; skip_brackets(); continue }
            P++; continue
        }
        P++
    }
}

function unquote_delim(w) { gsub(/["'\\]/, "", w); return w }

function read_heredocs(    h, e, line, cmp) {  # P just after the newline
    for (h = 1; h <= HDN; h++) {
        while (1) {
            if (P > N) { unsure("here-document " HD[h] " has no terminator"); break }
            e = P
            while (e <= N && C[e] != "\n") e++
            line = substr(S, P, e - P)
            cmp = line
            if (HDD[h]) sub(/^\t+/, "", cmp)
            P = e + 1
            if (cmp == HD[h]) break
        }
    }
    HDN = 0
}

# A redirection starting at P (at <, > or the & of &>). Its target is not a word.
function handle_redir(k,    c, ws, d) {
    c = C[P]
    if (c == "<" && C[P + 1] == "<" && C[P + 2] == "<") {
        P += 3; skip_blanks(); parse_word()
    } else if (c == "<" && C[P + 1] == "<") {
        P += 2; d = 0
        if (C[P] == "-") { d = 1; P++ }
        skip_blanks(); ws = P; parse_word()
        HDN++; HD[HDN] = unquote_delim(substr(S, ws, P - ws)); HDD[HDN] = d
        if (HD[HDN] == "") unsure("here-document with no delimiter")
    } else if ((c == "<" || c == ">") && C[P + 1] == "(") {
        P += 2; parse_list(0, ")", 0, "")          # process substitution, an argument
    } else {
        if (c == "&") P++
        P++
        while (P <= N && (C[P] == ">" || C[P] == "|" || C[P] == "!" || C[P] == "&")) {
            if (C[P] == "&") { P++; break }
            P++
        }
        skip_blanks()
        if ((C[P] == "<" || C[P] == ">") && C[P + 1] == "(") { P += 2; parse_list(0, ")", 0, "") }
        else {
            ws = P; parse_word()
            if (P == ws) unsure("redirection with no target")
        }
    }
    if (k > 0) CEND[k] = P - 1
}

function skip_dbracket(k,    ws, c) {  # after the word [[ ; up to the word ]]
    while (P <= N) {
        skip_blanks()
        if (P > N) break
        if (C[P] == "\n") { unsure("newline inside [["); return }
        ws = P
        while (P <= N && C[P] != " " && C[P] != "\t" && C[P] != "\n") {
            c = C[P]
            if (c == "'") { skip_squote(); continue }
            if (c == "\"") { parse_dq(); continue }
            if (c == "\\") { P += 2; continue }
            if (c == "`") { skip_backtick(); continue }
            if (c == "$" && C[P + 1] == "(") { P++; skip_cmdsub(); continue }
            if (c == "$" && C[P + 1] == "{") { P += 2; skip_brace_param(); continue }
            P++
        }
        if (substr(S, ws, P - ws) == "]]") { if (k > 0) CEND[k] = P - 1; return }
    }
    unsure("unterminated [[")
}

# A command list, from P until `closer` (")" or "}" or "" for end of input).
# rec=1 records every simple command; rec=0 only finds where the list ends.
function parse_list(rec, closer, depth, sep,    k, c, ws, raw, q) {
    k = 0
    while (P <= N) {
        c = C[P]
        if (c == " " || c == "\t") { P++; continue }
        if (c == "\\" && C[P + 1] == "\n") { P += 2; continue }
        if (c == "\n") { end_cmd(k, "nl"); k = 0; sep = "nl"; P++; if (HDN) read_heredocs(); continue }
        if (c == "#") { while (P <= N && C[P] != "\n") P++; continue }
        if (c == ")") {
            if (closer == ")") { end_cmd(k, ")"); P++; return }
            unsure("unmatched )"); end_cmd(k, ")"); k = 0; sep = ")"; P++; continue
        }
        if (c == ";") {
            if (C[P + 1] == ";" || C[P + 1] == "&" || C[P + 1] == "|") { unsure("case clause"); P += 2 } else P++
            end_cmd(k, ";"); k = 0; sep = ";"; continue
        }
        if (c == "&") {
            if (C[P + 1] == "&") { end_cmd(k, "&&"); k = 0; sep = "&&"; P += 2; continue }
            if (C[P + 1] == ">") { handle_redir(k); continue }
            BG = 1
            if (C[P + 1] == "!" || C[P + 1] == "|") P += 2; else P++
            end_cmd(k, "&"); k = 0; sep = "&"; continue
        }
        if (c == "|") {
            if (C[P + 1] == "|") { end_cmd(k, "||"); sep = "||"; P += 2 }
            else if (C[P + 1] == "&") { end_cmd(k, "|&"); sep = "|&"; P += 2 }
            else { end_cmd(k, "|"); sep = "|"; P++ }
            k = 0; continue
        }
        if (c == "<" || c == ">") { handle_redir(k); continue }
        if (c == "(") {
            if (k == 0 && C[P + 1] == "(") {          # (( arithmetic ))
                k = new_cmd(rec, depth, sep); ws = P; skip_parens(); add_word(k, ws, P - 1, 1); continue
            }
            if (k == 0) { P++; parse_list(rec, ")", depth + 1, "("); sep = ")"; continue }
            if (C[P + 1] == ")") {                      # f () { ... }: a function definition
                unsure("function definition"); P += 2; end_cmd(k, "kw"); k = 0; sep = "kw"; continue
            }
            unsure("parenthesis after words"); skip_parens(); continue
        }
        ws = P; parse_word(); q = WQF
        if (P == ws) { P++; continue }                 # no progress: never loop forever
        raw = substr(S, ws, P - ws)
        if (raw ~ /^[0-9]+$/ && (C[P] == "<" || C[P] == ">")) continue   # 2>file: the 2 is an fd
        if (k == 0) {
            if (!q && (raw == "if" || raw == "then" || raw == "elif" || raw == "else" || raw == "do" || raw == "while" || raw == "until" || raw == "!" || raw == "fi" || raw == "done" || raw == "esac")) { sep = "kw"; continue }
            if (!q && raw == "{") { parse_list(rec, "}", depth + 1, "{"); sep = "}"; continue }
            if (!q && raw == "}") { if (closer == "}") return; unsure("unmatched }"); continue }
            if (!q && raw == "[[") { k = new_cmd(rec, depth, sep); add_word(k, ws, P - 1, 0); skip_dbracket(k); continue }
            # A function body must still be scanned as commands: record nothing for
            # the header, so the { that follows opens a group at command position.
            if (!q && raw == "function") {
                unsure("function definition"); skip_blanks(); parse_word()
                if (C[P] == "(" && C[P + 1] == ")") P += 2
                sep = "kw"; continue
            }
            if (raw ~ /\(\)$/) { unsure("function definition"); sep = "kw"; continue }
            if (!q && (raw == "case" || raw == "coproc" || raw == "select" || raw == "foreach")) unsure("zsh construct " raw)
            k = new_cmd(rec, depth, sep)
        } else if (!q && raw == "}" && closer == "}") { end_cmd(k, "}"); return }
        add_word(k, ws, P - 1, q)
    }
    end_cmd(k, "$")
    if (closer != "") unsure("unterminated " (closer == ")" ? "(" : "{"))
}

# ------------------------------------------------------------------ word helpers

function base(w) { sub(/.*\//, "", w); return w }
# The text zsh would run for a word, or "" when it holds an expansion we cannot know.
function unq(w) { if (w ~ /[$`]/) return ""; gsub(/["'\\]/, "", w); return w }
function isopt(k, a) { return WR[k, a] ~ /^-/ }

# Index of the effective command word of simple command k, after assignments and
# precommand modifiers. Sets EM to the modifiers seen: " assign", " env",
# " envopt", " time", " nohup", " noglob", " nocorrect", " hard:<name>", " probe".
# A "hard" modifier (sudo doas exec xargs command builtin -) or an env option means
# the words after it cannot be read reliably, so no hook rewrites past one.
function eff(k,    j, n, w) {
    EM = ""; n = CNW[k]; j = 1
    while (j <= n) {
        w = WR[k, j]
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) { EM = EM " assign"; j++; continue }
        if (WQ[k, j]) break
        if (base(w) == "env") {
            EM = EM " env"; j++
            while (j <= n && (WR[k, j] ~ /^-/ || WR[k, j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
                if (WR[k, j] ~ /^-/) EM = EM " envopt"
                j++
            }
            continue
        }
        if (w == "time" || w == "nohup" || w == "noglob" || w == "nocorrect") { EM = EM " " w; j++; continue }
        if (w == "sudo" || w == "doas" || w == "exec" || w == "xargs" || w == "command" || w == "builtin" || w == "-") {
            EM = EM " hard:" w; j++
            while (j <= n && WR[k, j] ~ /^-/) {
                if (w == "command" && WR[k, j] ~ /^-[a-zA-Z]*[vV]/) EM = EM " probe"
                j++
            }
            continue
        }
        break
    }
    return j
}

# ------------------------------------------------------------------ results

function verdict(o, v, m) {           # first DENY wins; REWRITEs accumulate
    if (V[o] == "DENY") return
    if (v == "DENY") { V[o] = "DENY"; M[o] = m; return }
    V[o] = "REWRITE"; M[o] = (M[o] == "" ? m : M[o] "; " m)
}

function splice(o, s, e, r,    n) { n = ++SPN[o]; SPS[o, n] = s; SPE[o, n] = e; SPR[o, n] = r }

# Remove word a of command k together with the blanks after it.
function drop_word(o, k, a,    e) {
    e = WE[k, a]
    while (C[e + 1] == " " || C[e + 1] == "\t") e++
    splice(o, WS[k, a], e, "")
}

function apply(o,    i, j, n, t, out, pos) {
    n = SPN[o]
    for (i = 2; i <= n; i++)                         # sort by start; a pure insert first
        for (j = i; j > 1 && (SPS[o, j - 1] > SPS[o, j] || (SPS[o, j - 1] == SPS[o, j] && SPE[o, j - 1] > SPE[o, j])); j--) {
            t = SPS[o, j]; SPS[o, j] = SPS[o, j - 1]; SPS[o, j - 1] = t
            t = SPE[o, j]; SPE[o, j] = SPE[o, j - 1]; SPE[o, j - 1] = t
            t = SPR[o, j]; SPR[o, j] = SPR[o, j - 1]; SPR[o, j - 1] = t
        }
    out = ""; pos = 1
    for (i = 1; i <= n; i++) {
        out = out substr(S, pos, SPS[o, i] - pos) SPR[o, i]
        pos = SPE[o, i] + 1
    }
    return out substr(S, pos)
}

function hardname() { return (match(EM, /hard:[^ ]+/) ? substr(EM, RSTART + 5, RLENGTH - 5) : "env with options") }

# ------------------------------------------------------------------ uv

function uv_name(b) { return b == "python" || b == "python3" || b == "pip" || b == "pip3" || b == "pytest" || b == "ruff" || b == "pipx" || b ~ /^py31[0-3]$/ }

function uv_msg(b, s1) {
    if (b ~ /^pip3?$/ && s1 == "install")   return "Use 'uv add <package>' instead of pip install"
    if (b ~ /^pip3?$/ && s1 == "uninstall") return "Use 'uv remove <package>' instead of pip uninstall"
    if (b ~ /^pip3?$/)                      return "Use 'uv run pip' or 'uv pip' instead of bare pip"
    if (b ~ /^python3?$/)                   return "Use 'uv run python' instead of bare python"
    if (b == "pipx")                        return "Use 'uv tool' instead of pipx (install, uninstall, upgrade, list; 'uvx' for run)"
    if (b ~ /^py31[0-3]$/)                  return "Use 'uv run --python 3." substr(b, 4) " python' instead of " b
    return "Use 'uv run " b "' instead of bare " b
}

function uv_check(    k, j, n, a, v, b, s1, pk) {
    V["uv"] = "ALLOW"; M["uv"] = ""
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n || EM ~ /probe/) continue
        if (EM ~ /hard:|envopt/) {
            for (a = j; a <= n; a++) {
                b = base(unq(WR[k, a]))
                if (uv_name(b)) { verdict("uv", "DENY", uv_msg(b, unq(WR[k, a + 1])) " (after '" hardname() "', so it is not rewritten)"); break }
            }
            continue
        }
        v = unq(WR[k, j]); b = base(v)
        if (!uv_name(b)) continue
        s1 = (j < n) ? unq(WR[k, j + 1]) : ""
        if (WQ[k, j] || v != b) { verdict("uv", "DENY", uv_msg(b, s1) " (quoted, escaped or path-prefixed, so it is not rewritten)"); continue }
        if (UNSURE != "") { verdict("uv", "DENY", uv_msg(b, s1) " (the command has a " UNSURE ", so it is not rewritten)"); continue }
        if (b ~ /^python3?$/) {
            if (j == n) continue                        # bare interpreter: never matched, unchanged
            splice("uv", WS[k, j], WS[k, j] - 1, "uv run "); verdict("uv", "REWRITE", b " -> uv run " b); continue
        }
        if (b ~ /^py31[0-3]$/) {                   # the .zshrc wrappers' own advice
            if (j == n) continue                        # bare interpreter: unchanged
            splice("uv", WS[k, j], WE[k, j], "uv run --python 3." substr(b, 4) " python")
            verdict("uv", "REWRITE", b " -> uv run --python 3." substr(b, 4) " python"); continue
        }
        if (b == "pipx") {                             # mapping from the .zshrc pipx() wrapper
            if (j < n && WQ[k, j + 1]) { verdict("uv", "DENY", uv_msg(b, s1)); continue }
            pk = pn_pkgs(k, j, "")                     # words after the subcommand, no options
            if ((s1 == "install" || s1 == "uninstall" || s1 == "upgrade") && pk > 0) {
                splice("uv", WS[k, j], WE[k, j], "uv tool"); verdict("uv", "REWRITE", "pipx " s1 " -> uv tool " s1); continue
            }
            if (s1 == "run" && j + 2 <= n && !isopt(k, j + 2)) {
                splice("uv", WS[k, j], WE[k, j + 1], "uvx"); verdict("uv", "REWRITE", "pipx run -> uvx"); continue
            }
            if (s1 == "list" && j + 1 == n) {
                splice("uv", WS[k, j], WE[k, j + 1], "uv tool list --show-paths"); verdict("uv", "REWRITE", "pipx list -> uv tool list --show-paths"); continue
            }
            if (s1 == "upgrade-all" && j + 1 == n) {
                splice("uv", WS[k, j], WE[k, j + 1], "uv tool upgrade --all"); verdict("uv", "REWRITE", "pipx upgrade-all -> uv tool upgrade --all"); continue
            }
            verdict("uv", "DENY", uv_msg(b, s1) " (only install, uninstall, upgrade, upgrade-all, run and list, without options, are rewritten)"); continue
        }
        if (b == "pytest" || b == "ruff") {
            splice("uv", WS[k, j], WS[k, j] - 1, "uv run "); verdict("uv", "REWRITE", b " -> uv run " b); continue
        }
        # pip / pip3
        if (j < n && WQ[k, j + 1]) { verdict("uv", "DENY", uv_msg(b, s1)); continue }
        if (s1 == "install") {
            pk = 0
            for (a = j + 2; a <= n; a++) {
                if (WR[k, a] == "-r" || WR[k, a] == "--requirement") {
                    if (a == n || isopt(k, a + 1)) { pk = -1; break }
                    a++; pk++; continue
                }
                if (isopt(k, a)) { pk = -1; break }
                pk++
            }
            if (pk <= 0) { verdict("uv", "DENY", uv_msg(b, s1) " (options other than -r are not rewritten)"); continue }
            splice("uv", WS[k, j], WE[k, j + 1], "uv add"); verdict("uv", "REWRITE", b " install -> uv add"); continue
        }
        if (s1 == "uninstall") {
            pk = 0
            for (a = j + 2; a <= n; a++) {
                if (WR[k, a] == "-y" || WR[k, a] == "--yes") { drop_word("uv", k, a); continue }
                if (isopt(k, a)) { pk = -1; break }
                pk++
            }
            if (pk <= 0) { verdict("uv", "DENY", uv_msg(b, s1) " (options other than -y are not rewritten)"); continue }
            splice("uv", WS[k, j], WE[k, j + 1], "uv remove"); verdict("uv", "REWRITE", b " uninstall -> uv remove"); continue
        }
        if (s1 == "list" || s1 == "show" || s1 == "freeze" || s1 == "check") {
            splice("uv", WS[k, j], WE[k, j], "uv pip"); verdict("uv", "REWRITE", b " " s1 " -> uv pip " s1); continue
        }
        verdict("uv", "DENY", uv_msg(b, s1))
    }
}

# ------------------------------------------------------------------ pnpm

function pn_name(b) { return b == "npm" || b == "yarn" || b == "npx" || b == "pnpm" }

function pn_msg(b) {
    if (b == "npm")  return "Use 'pnpm' or 'bun' instead of npm"
    if (b == "yarn") return "Use 'pnpm' or 'bun' instead of yarn"
    if (b == "npx")  return "Use 'pnpm dlx' or 'bunx' instead of npx"
    return "Use 'pnpm install -g .' instead of 'pnpm link --global' (v11 shim layout bug)"
}

# pnpm link --global: deny only, exactly as before.
function pn_link_global(k, j,    a, n) {
    n = CNW[k]
    if (j >= n) return 0
    a = unq(WR[k, j + 1]); if (a != "link" && a != "ln") return 0
    for (a = j + 2; a <= n; a++) {
        if (WR[k, a] == "--") return 0
        if (WR[k, a] == "-g" || WR[k, a] == "--global") return 1
    }
    return 0
}

# Words j+2..n of command k are package names, plus only the options in `ok`
# (a space-separated list). Returns the number of packages, or -1.
function pn_pkgs(k, j, ok,    a, n, c) {
    n = CNW[k]; c = 0
    for (a = j + 2; a <= n; a++) {
        if (isopt(k, a)) { if (index(" " ok " ", " " WR[k, a] " ") == 0) return -1; continue }
        c++
    }
    return c
}

# An npx target that resolves to a LOCAL binary must not become pnpm dlx, which
# always fetches from the registry: `npx tsc` in a project runs the local
# typescript, while `pnpm dlx tsc` would download the unrelated "tsc" package.
function npx_local(name,    d, f, line, r) {
    d = ENVIRON["CONV_CWD"]
    if (d == "") return 1                            # unknown cwd: assume local, deny
    while (d != "") {
        f = d "/node_modules/.bin/" name
        r = (getline line < f); close(f)
        if (r >= 0) return 1
        if (d == "/") break
        sub(/\/[^\/]*$/, "", d); if (d == "") d = "/"
    }
    return 0
}

function pnpm_check(    k, j, n, a, v, b, s1, c, name, first, nm) {
    V["pnpm"] = "ALLOW"; M["pnpm"] = ""
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n || EM ~ /probe/) continue
        if (EM ~ /hard:|envopt/) {
            for (a = j; a <= n; a++) {
                b = base(unq(WR[k, a]))
                if (b == "npm" || b == "yarn" || b == "npx") { verdict("pnpm", "DENY", pn_msg(b) " (after '" hardname() "', so it is not rewritten)"); break }
            }
            continue
        }
        v = unq(WR[k, j]); b = base(v)
        if (!pn_name(b)) continue
        if (b == "pnpm") { if (!WQ[k, j] && pn_link_global(k, j)) verdict("pnpm", "DENY", pn_msg("pnpm")); continue }
        if (WQ[k, j] || v != b) { verdict("pnpm", "DENY", pn_msg(b) " (quoted, escaped or path-prefixed, so it is not rewritten)"); continue }
        if (UNSURE != "") { verdict("pnpm", "DENY", pn_msg(b) " (the command has a " UNSURE ", so it is not rewritten)"); continue }
        s1 = (j < n) ? WR[k, j + 1] : ""
        if (j < n && WQ[k, j + 1]) { verdict("pnpm", "DENY", pn_msg(b)); continue }
        if (b == "npm") {
            if ((s1 == "install" || s1 == "i") && j + 1 == n) {
                splice("pnpm", WS[k, j], WE[k, j], "pnpm"); verdict("pnpm", "REWRITE", "npm " s1 " -> pnpm " s1); continue
            }
            if (s1 == "install" || s1 == "i" || s1 == "add") {
                if (pn_pkgs(k, j, "-D --save-dev -E --save-exact -g --global") > 0) {
                    splice("pnpm", WS[k, j], WE[k, j + 1], "pnpm add"); verdict("pnpm", "REWRITE", "npm " s1 " <pkg> -> pnpm add <pkg>"); continue
                }
            } else if (s1 == "uninstall" || s1 == "remove" || s1 == "rm" || s1 == "un" || s1 == "r") {
                if (pn_pkgs(k, j, "-g --global") > 0) {
                    splice("pnpm", WS[k, j], WE[k, j + 1], "pnpm remove"); verdict("pnpm", "REWRITE", "npm " s1 " -> pnpm remove"); continue
                }
            } else if (s1 == "run" || s1 == "run-script") {
                if (j + 2 == n && !isopt(k, n)) {
                    splice("pnpm", WS[k, j], WE[k, j + 1], "pnpm run"); verdict("pnpm", "REWRITE", "npm " s1 " -> pnpm run"); continue
                }
            } else if ((s1 == "test" || s1 == "t" || s1 == "start") && j + 1 == n) {
                splice("pnpm", WS[k, j], WE[k, j + 1], "pnpm " (s1 == "t" ? "test" : s1)); verdict("pnpm", "REWRITE", "npm " s1 " -> pnpm " (s1 == "t" ? "test" : s1)); continue
            }
            verdict("pnpm", "DENY", pn_msg(b) (s1 == "ci" ? " ('pnpm install --frozen-lockfile' is the ci form)" : " (only install, add, remove, run, test and start are rewritten)")); continue
        }
        if (b == "yarn") {
            if (j == n) { splice("pnpm", WS[k, j], WE[k, j], "pnpm install"); verdict("pnpm", "REWRITE", "yarn -> pnpm install"); continue }
            if (s1 == "install" && j + 1 == n) { splice("pnpm", WS[k, j], WE[k, j], "pnpm"); verdict("pnpm", "REWRITE", "yarn install -> pnpm install"); continue }
            if ((s1 == "add" && pn_pkgs(k, j, "-D -E") > 0) || (s1 == "remove" && pn_pkgs(k, j, "") > 0) || \
                ((s1 == "run" || s1 == "dlx") && j + 2 == n && !isopt(k, n)) || ((s1 == "test" || s1 == "start") && j + 1 == n)) {
                splice("pnpm", WS[k, j], WE[k, j], "pnpm"); verdict("pnpm", "REWRITE", "yarn " s1 " -> pnpm " s1); continue
            }
            verdict("pnpm", "DENY", pn_msg(b) " (only install, add, remove, run, dlx, test and start are rewritten)"); continue
        }
        # npx
        first = 0
        for (a = j + 1; a <= n; a++) {
            if (WR[k, a] == "-y" || WR[k, a] == "--yes") continue
            if (isopt(k, a)) { first = -1; break }
            first = a; break
        }
        if (first <= 0 || WQ[k, first]) { verdict("pnpm", "DENY", pn_msg(b) " (options other than -y are not rewritten)"); continue }
        name = WR[k, first]
        if (name !~ /^@?[A-Za-z0-9._\/-]+(@[A-Za-z0-9._^~<>=*-]+)?$/) { verdict("pnpm", "DENY", pn_msg(b)); continue }
        nm = name; if (nm ~ /^@/) sub(/^@[^\/]*\//, "", nm); sub(/@.*$/, "", nm)
        c = 0
        for (a = 1; a < k; a++) if (unq(WR[a, eff(a)]) ~ /^(cd|pushd|popd)$/) c = 1
        if (c || npx_local(nm)) { verdict("pnpm", "DENY", "npx " nm " may be a LOCAL binary here; use 'pnpm exec " nm "' for a local one or 'pnpm dlx " name "' to fetch it"); continue }
        for (a = j + 1; a < first; a++) drop_word("pnpm", k, a)
        splice("pnpm", WS[k, j], WE[k, j], "pnpm dlx"); verdict("pnpm", "REWRITE", "npx -> pnpm dlx")
    }
}

# ------------------------------------------------------------------ no-cd

function cd_alias(w) {        # .zshrc aliases that expand to cd; "" if w is not one
    if (w == "..") return ".."
    if (w == "...") return "../.."
    if (w == "....") return "../../.."
    if (w == ".....") return "../../../.."
    if (w == "~") return "~"
    return ""
}

# Aliases live in agent Bash (measured 2026-09-23: 310 from the shell snapshot)
# that ALSO change directory but cannot be rewritten safely: - is `cd -`, 1..9
# are `cd -N` (the directory stack), grt is cd to the git top level. Deny only.
function cd_deny_alias(w) { return w ~ /^[1-9]$/ || w == "grt" }

function nocd_check(    k, j, n, v, cnt, first, fj, dir, why) {
    V["nocd"] = "ALLOW"; M["nocd"] = ""; cnt = 0
    for (k = 1; k <= NC; k++) {
        if (CNW[k] >= 1 && WR[k, 1] == "-" && !WQ[k, 1]) {   # alias - = cd - (eff reads it as zsh's - modifier)
            verdict("nocd", "DENY", "'-' is an alias for 'cd -' here; use an absolute path, git -C, or builtin cd"); return
        }
        j = eff(k); n = CNW[k]
        if (j <= n && !WQ[k, j] && cd_deny_alias(WR[k, j]) && EM !~ /hard:builtin/) {
            verdict("nocd", "DENY", "'" WR[k, j] "' is an alias that changes directory here; use an absolute path, git -C, or builtin cd"); return
        }
        if (j > n || EM ~ /hard:builtin/) continue
        v = unq(WR[k, j])
        if (v == "cd" || (!WQ[k, j] && cd_alias(WR[k, j]) != "")) { if (++cnt == 1) { first = k; fj = j } }
    }
    if (cnt == 0) return
    why = "Don't use 'cd' -- use absolute paths, 'git -C <path>', or 'builtin cd' instead"
    k = first; j = fj; n = CNW[k]; eff(k)
    if (cnt > 1 || k != 1 || CD[k] != 0 || CSB[k] != "^" || EM != "" || j != 1 || UNSURE != "" || BG) {
        verdict("nocd", "DENY", why); return
    }
    if (CSA[k] != "&&" && CSA[k] != ";" && CSA[k] != "nl") { verdict("nocd", "DENY", why); return }
    if (NC < 2) { verdict("nocd", "DENY", why); return }
    if (WR[k, 1] == "cd" && !WQ[k, 1]) {
        if (n != 2 || isopt(k, 2)) { verdict("nocd", "DENY", why); return }
        dir = WR[k, 2]
        splice("nocd", WS[k, 1], WE[k, 1], "builtin cd")
    } else if (!WQ[k, 1] && cd_alias(WR[k, 1]) != "" && n == 1) {
        dir = cd_alias(WR[k, 1])
        splice("nocd", WS[k, 1], WE[k, 1], "builtin cd " dir)
    } else { verdict("nocd", "DENY", why); return }
    splice("nocd", 1, 0, "(")
    splice("nocd", N + 1, N, "\n)")
    verdict("nocd", "REWRITE", "leading cd " dir " -> (builtin cd " dir " ...) in a subshell, so the session's working directory did not change")
}

# ------------------------------------------------------------------ main

{ S = (NR > 1 ? S "\n" : "") $0 }

END {
    N = split(S, C, "")
    P = 1; NC = 0; HDN = 0; BG = 0; UNSURE = ""
    parse_list(1, "", 0, "^")
    if (HDN) unsure("here-document with no body")
    mode = ENVIRON["CONV_MODE"]
    if (mode == "uv")        { own = "uv";   uv_check(); pnpm_check(); others = "pnpm" }
    else if (mode == "pnpm") { own = "pnpm"; pnpm_check(); uv_check(); others = "uv" }
    else if (mode == "nocd") { own = "nocd"; nocd_check(); uv_check(); pnpm_check(); others = "uv pnpm" }
    else { print "DENY"; print "conv-shscan: unknown CONV_MODE '" mode "'"; exit 0 }
    tag["uv"] = "enforce-uv"; tag["pnpm"] = "enforce-pnpm"; tag["nocd"] = "enforce-no-cd"
    if (V[own] == "ALLOW") { print "ALLOW"; print ""; exit 0 }
    extra = ""
    no = split(others, ol, " ")
    for (i = 1; i <= no; i++) if (V[ol[i]] != "ALLOW") extra = extra "; " (V[ol[i]] == "REWRITE" ? "also needed: " M[ol[i]] : M[ol[i]])
    if (V[own] == "DENY") { print "DENY"; print M[own] extra; exit 0 }
    if (extra != "") {                  # two conventions in one command: never race two rewrites
        print "DENY"
        print "Two conventions in one command, so nothing was rewritten; fix both and resend: " M[own] extra
        exit 0
    }
    new = apply(own)
    shown = (length(new) > 300 ? substr(new, 1, 300) " ..." : new)
    gsub(/\n/, " ", shown)                     # line 2 of the protocol is one line
    print "REWRITE"
    print tag[own] " rewrote this command before it ran (" M[own] "). What ran: " shown
    printf "%s", new
}
