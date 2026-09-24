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
# Env:    CONV_MODE = uv | pnpm | nocd | guard | builtin | reset   (which hook is asking)
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
    NC++; CD[NC] = depth; CSB[NC] = sep; CSA[NC] = ""; CNW[NC] = 0; CEND[NC] = 0; RDN[NC] = 0
    CSS[NC] = SUBSH                   # >0: inside an explicit ( ) subshell
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

function skip_backtick(    s) {  # P at the opening `
    s = ++P
    while (P <= N && C[P] != "`") { if (C[P] == "\\") P++; P++ }
    if (P > N) unsure("unterminated backtick")
    if (REC_NESTED) BT[++BTN] = substr(S, s, P - s)   # guard mode reads the body
    P++
}

function skip_cmdsub() {    # P at the "(" of $( ; handles $(( too
    if (C[P + 1] == "(") { skip_parens(); return }
    P++
    parse_list(REC_NESTED, ")", 1, "$(")
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
            if (P == ws + 1 && C[ws] == "=") { P++; parse_list(REC_NESTED, ")", 1, "=("); WQF = 1; continue }  # zsh =(...)
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
        P += 2; parse_list(REC_NESTED, ")", 1, c "(")   # process substitution, an argument
    } else {
        if (c == "&") P++
        P++
        while (P <= N && (C[P] == ">" || C[P] == "|" || C[P] == "!" || C[P] == "&")) {
            if (C[P] == "&") { P++; break }
            P++
        }
        skip_blanks()
        if ((C[P] == "<" || C[P] == ">") && C[P + 1] == "(") { P += 2; parse_list(REC_NESTED, ")", 1, C[P - 2] "(") }
        else {
            ws = P; parse_word()
            if (P == ws) unsure("redirection with no target")
            # reset mode reads where output goes: > >> &> >| >! and fd forms
            else if (k > 0 && c != "<") { RDN[k]++; RDT[k, RDN[k]] = substr(S, ws, P - ws) }
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
            if (k == 0) { P++; SUBSH++; parse_list(rec, ")", depth + 1, "("); SUBSH--; sep = ")"; continue }
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

# A cd inside an explicit ( ) subshell cannot outlive it, so it is not counted
# (ruled by Gavin 2026-09-23, proposal E). A { } group runs in the CURRENT shell
# and its cd persists (measured in zsh 5.9), so a { } cd is counted as before.
# One exception keeps the old deny: a subshell cd in a command the scanner is
# UNSURE of, because then the subshell boundaries themselves are in doubt.
function nocd_check(    k, j, n, v, cnt, first, fj, dir, why, subcd) {
    V["nocd"] = "ALLOW"; M["nocd"] = ""; cnt = 0; subcd = 0
    why = "Don't use 'cd' -- use absolute paths, 'git -C <path>', or 'builtin cd' instead"
    for (k = 1; k <= NC; k++) {
        if (CSS[k] > 0) {
            j = eff(k)
            if (j <= CNW[k] && EM !~ /hard:builtin/ && (unq(WR[k, j]) == "cd" || WR[k, 1] == "-" || (!WQ[k, j] && (cd_alias(WR[k, j]) != "" || cd_deny_alias(WR[k, j]))))) subcd++
            continue
        }
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
    if (cnt == 0) {
        if (subcd && UNSURE != "") verdict("nocd", "DENY", why " (a cd inside ( ) is allowed, but this command has a " UNSURE ")")
        return
    }
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

# ------------------------------------------------------------------ guard
# Used by validate-bash.sh (CONV_MODE=guard). Deny only, never a rewrite. Three
# rules approved by Gavin 2026-09-23 from the conv-hooks survey:
#   A. the six aliases that launch a NESTED Claude with --dangerously-skip-permissions
#      (ci cr ct cpr cd_ cskip; cb launches one WITHOUT it and is left alone)
#   B. gpf!, the oh-my-zsh alias for `git push --force` (gpf and gpsupf are
#      --force-with-lease and are left alone)
#   C. brew install / instal / reinstall / upgrade: ask Gavin. The .zshrc brew()
#      guard is [[ -o interactive ]] only, measured inert in agent Bash.
# An alias expands only at command position: after assignments, time, nocorrect, !,
# keywords, ( and {, and inside $(...), backticks and eval (all measured in agent
# Bash, zsh 5.9). This mode records $(...) and process substitution bodies
# (REC_NESTED), reads backtick bodies and eval arguments with a cruder word match,
# and denies the alias names after ANY precommand modifier too, where zsh would not
# expand them: a false positive there costs nothing, no such command exists.
# A quoted or escaped alias name (\ci, "ci") does not expand and is allowed.

function g_alias_msg(w) {
    if (w == "gpf!") return "'gpf!' is the oh-my-zsh alias for 'git push --force'. A force push is Gavin's call: ask him. 'gpf' (--force-with-lease --force-if-includes) is the safer form when he agrees"
    return "'" w "' is a .zshrc alias that launches a NESTED Claude session with --dangerously-skip-permissions. Nesting a skip-permissions session is Gavin's call, not an agent's: ask him"
}
function g_is_alias(w) { return w == "ci" || w == "cr" || w == "ct" || w == "cpr" || w == "cd_" || w == "cskip" || w == "gpf!" }
function g_brew_sub(s) { return s == "install" || s == "instal" || s == "reinstall" || s == "upgrade" }
function g_brew_msg(s) { return "'brew " s "' changes what is installed on Gavin's machine: ask Gavin to run it. brew list, info, search, outdated and deps stay allowed" }

# The crude match, for text the scanner cannot parse as commands (backtick
# bodies, eval arguments). Returns a deny message or "".
function g_crude(t,    m) {
    if (match(t, /(^|[;&|({\n])[ \t]*(ci|cr|ct|cpr|cd_|cskip|gpf!)([ \t\n;&|)}]|$)/)) {
        m = substr(t, RSTART, RLENGTH); gsub(/^[;&|({\n \t]+|[ \t\n;&|)}]+$/, "", m)
        return g_alias_msg(m)
    }
    if (match(t, /(^|[;&|({\n])[ \t]*([^ \t\n;&|]*\/)?brew[ \t]+(-[^ \t\n]+[ \t]+)*(install|instal|reinstall|upgrade)([ \t\n;&|)}]|$)/)) {
        m = substr(t, RSTART, RLENGTH); sub(/[ \t\n;&|)}]+$/, "", m); sub(/.*[ \t]/, "", m)
        return g_brew_msg(m)
    }
    return ""
}

function guard_check(    k, j, n, a, w, b, s, i, t) {
    V["guard"] = "ALLOW"; M["guard"] = ""
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n || EM ~ /probe/) continue
        w = WR[k, j]
        if (!WQ[k, j] && g_is_alias(w)) { verdict("guard", "DENY", g_alias_msg(w)); return }
        # brew: a quoted or path-prefixed name still runs brew, so unq and base.
        # After a hard modifier (sudo -u x brew ...) eff cannot find the command
        # word reliably, so look at every word, as the uv rule does.
        for (a = j; a <= n; a++) {
            if (base(unq(WR[k, a])) == "brew") break
            if (EM !~ /hard:|envopt/) { a = n + 1; break }
        }
        if (a <= n) {
            for (i = a + 1; i <= n && isopt(k, i); i++) ;
            if (i <= n) {
                s = unq(WR[k, i])
                if (s == "") { verdict("guard", "DENY", "brew with a subcommand held in a variable or expansion (" WR[k, i] "): it may be an install. Ask Gavin, or spell the subcommand out"); return }
                if (g_brew_sub(s)) { verdict("guard", "DENY", g_brew_msg(s)); return }
            }
        }
        if (unq(w) == "eval" && !WQ[k, j]) {
            t = ""
            for (a = j + 1; a <= n; a++) t = t " " WR[k, a]
            gsub(/["']/, "", t)
            s = g_crude(t)
            if (s != "") { verdict("guard", "DENY", s " (inside eval)"); return }
        }
    }
    for (i = 1; i <= BTN; i++) {
        s = g_crude(BT[i])
        if (s != "") { verdict("guard", "DENY", s " (inside backticks)"); return }
    }
}

# ------------------------------------------------------------------ builtin
# Used by this repo's .claude/hooks/enforce-builtin.sh (CONV_MODE=builtin), which
# denies `builtin <word>` when <word> is not a zsh builtin. Until 2026-09-23 it
# stripped "$(...)", "..." and '...' with sed, the same flaw the other hooks had:
# a quoted ) inside $(...) put prose at command position. Kept as it was: the
# allowed list, the prefixes it saw through (assignments, then env sudo command
# nohup time exec doas xargs followed by options, assignments or plain words), a
# path-prefixed builtin, a quoted builtin ignored, nothing inside $(...) checked.

function bi_ok(w) {
    return w ~ /^(cd|echo|printf|print|pushd|popd|pwd|read|set|shift|test|trap|true|false|type|typeset|ulimit|umask|unset|wait|export|local|return|exit|source|eval|exec|hash|kill|let|unalias|unfunction|declare|readonly|dirs|bg|fg|jobs|disown|suspend|times|builtin|command|whence|where|which|getopts|break|continue|:|\.)$/
}
function bi_mod(w) { return w ~ /^(env|sudo|command|nohup|time|exec|doas|xargs)$/ }

function builtin_check(    k, j, n, w, arg, mod) {
    V["builtin"] = "ALLOW"; M["builtin"] = ""
    for (k = 1; k <= NC; k++) {
        n = CNW[k]; j = 1; mod = 0
        while (j <= n && WR[k, j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) j++
        while (j <= n) {              # a quoted VALUE (env FOO="a b") is still skipped
            w = WR[k, j]
            if (w ~ /^([A-Za-z0-9_.\/-]*\/)?builtin$/) break
            if (bi_mod(w)) { mod = 1; j++; continue }
            if (mod && (w ~ /^-/ || w ~ /^[A-Za-z_][A-Za-z0-9_]*(=.*)?$/)) { j++; continue }
            j = n + 1
        }
        if (j >= n || WQ[k, j]) continue
        arg = unq(WR[k, j + 1]); if (arg == "") arg = WR[k, j + 1]
        if (bi_ok(arg)) continue
        verdict("builtin", "DENY", "'builtin " arg "' is invalid -- builtin only works with zsh builtins (cd, echo, printf, etc.)")
        return
    }
}

# ------------------------------------------------------------------ reset
# Used by enforce-no-reset-by-name.sh (CONV_MODE=reset). Deny only, never a
# rewrite. The class is RESET-BY-NAME (W-20260924-A32, Stage 1): one command
# removes a directory P, then recreates or writes into P, as if the rm worked:
#     rm -rf "$S/mut4" 2>/dev/null; mkdir -p "$S/mut4"; cp x "$S/mut4/"
# In the Claude sandbox the Trash-routed rm FAILS (rc 1, P left in place); with
# 2>/dev/null and ; nobody sees it, and the reuse merges into stale files.
#
# A remove is: rm/grm with -r, -R or --recursive in an option word, or rmdir.
# `rm -rf P/*` counts as a reset of P. A path with any other glob is skipped.
# A reuse of P, in a LATER simple command of the same Bash call:
#   mkdir P or P/...; cd/pushd P or P/...; the destination (last word, or -t) of
#   cp mv ln rsync install ditto (a cp with no -r/-R/-a onto exactly P is a file
#   overwrite, not a merge: skipped); tar -C P or -f P/...; unzip -d P; git init P;
#   touch/tee P/...; a > or >> redirection into P/...
# Words are compared as text after dropping quotes and backslashes, ${V} -> $V,
# a leading ./, doubled and trailing slashes. So "$S/mut4" == $S/mut4 == ${S}/mut4/.
# P stops being tracked (ALLOW) when, between the rm and the reuse:
#   - a test / [ / [[ naming P has its result used (&&, ||, or after if/while), or
#     a `git clone ... P &&` / `git worktree add ... P &&` (both refuse a
#     non-empty P, so the && stops the chain), or
#   - every separator from the rm up to the reuse is && (a failed rm stops it), or
#   - the rm is followed by || and an exit/return comes before the reuse, or
#   - a variable P is built from is reassigned (D=$(mktemp -d), for D in, read D)
#   - `set -e` (or -o errexit) ran earlier in the command.
# Words inside $(...), backticks and heredoc bodies are not commands here.

function rs_norm(w) {
    if (w ~ /\$\(|`/) return ""
    gsub(/["'\\]/, "", w)
    while (match(w, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/))
        w = substr(w, 1, RSTART - 1) "$" substr(w, RSTART + 2, RLENGTH - 3) substr(w, RSTART + RLENGTH)
    gsub(/\/\/+/, "/", w)
    while (substr(w, 1, 2) == "./" && length(w) > 2) w = substr(w, 3)
    while (length(w) > 1 && w ~ /\/\.?$/) sub(/\/\.?$/, "", w)
    return w
}
function rs_under(t, p) { return t != "" && (t == p || index(t, p "/") == 1) }
function rs_strict(t, p) { return t != "" && index(t, p "/") == 1 }

# The path a word names, if it may be reset; "" to skip it.
function rs_target(w) {
    w = rs_norm(w)
    if (w ~ /\/\*$/) w = substr(w, 1, length(w) - 2)
    if (w == "" || w ~ /[*?[]/ || w == "/" || w == "." || w == ".." || w == "~") return ""
    return w
}

# Does simple command c reuse path p? Returns the verb, or "".
function rs_reuse(c, p,    j, n, b, a, w, last, i) {
    for (i = 1; i <= RDN[c]; i++) if (rs_strict(rs_norm(RDT[c, i]), p)) return "a > redirection into it"
    j = eff(c); n = CNW[c]
    if (j > n) return ""
    b = base(rs_norm(WR[c, j]))
    if (b == "mkdir") {
        for (a = j + 1; a <= n; a++) {
            w = WR[c, a]
            if (w == "-m") { a++; continue }
            if (w ~ /^-/) continue
            if (rs_under(rs_norm(w), p)) return "mkdir"
        }
        return ""
    }
    if (b == "cd" || b == "pushd") {
        for (a = j + 1; a <= n && WR[c, a] ~ /^-/; a++) ;
        return (a <= n && rs_under(rs_norm(WR[c, a]), p)) ? b : ""
    }
    if (b == "cp" || b == "gcp" || b == "mv" || b == "gmv" || b == "ln" || b == "rsync" || b == "install" || b == "ditto") {
        last = ""; i = 0
        for (a = j + 1; a <= n; a++) {
            w = WR[c, a]
            if (w == "-t" || w == "--target-directory") { if (rs_under(rs_norm(WR[c, a + 1]), p)) return b; a++; continue }
            if (w ~ /^--target-directory=/) { sub(/^--target-directory=/, "", w); if (rs_under(rs_norm(w), p)) return b; continue }
            if (w ~ /^--recursive$|^--archive$|^-[a-zA-Z]*[rRa]/) i = 1
            if (w ~ /^-/) continue
            last = w
        }
        last = rs_norm(last)
        # A non-recursive cp onto exactly P overwrites a FILE: no merge, out of scope.
        if ((b == "cp" || b == "gcp") && !i && last == p) return ""
        return rs_under(last, p) ? b : ""
    }
    if (b == "tar" || b == "gtar" || b == "bsdtar") {
        for (a = j + 1; a <= n; a++) {
            w = WR[c, a]
            if (w == "-C" || w == "--directory") { if (rs_under(rs_norm(WR[c, a + 1]), p)) return "tar -C"; a++; continue }
            if (w ~ /^--directory=/) { sub(/^--directory=/, "", w); if (rs_under(rs_norm(w), p)) return "tar -C"; continue }
            if ((w == "-f" || w ~ /^-?[a-zA-Z]*f$/) && a < n && rs_strict(rs_norm(WR[c, a + 1]), p)) return "tar -f"
        }
        return ""
    }
    if (b == "unzip") {
        for (a = j + 1; a < n; a++) if (WR[c, a] == "-d" && rs_under(rs_norm(WR[c, a + 1]), p)) return "unzip -d"
        return ""
    }
    if (b == "git") {
        for (a = j + 1; a <= n && WR[c, a] ~ /^-/; a++) ;
        if (a > n || WR[c, a] != "init") return ""
        for (a++; a <= n; a++) if (WR[c, a] !~ /^-/ && rs_under(rs_norm(WR[c, a]), p)) return "git init"
        return ""
    }
    if (b == "touch" || b == "tee") {
        for (a = j + 1; a <= n; a++) if (WR[c, a] !~ /^-/ && rs_strict(rs_norm(WR[c, a]), p)) return b
        return ""
    }
    return ""
}

# Does command c test path p (a check whose result is USED)? A `git clone` or
# `git worktree add` into p, followed by &&, is one too: both refuse a directory
# that exists and is not empty, so a survivor stops the chain there.
function rs_checks(c, p,    j, n, b, a, seg) {
    if (!(CSA[c] == "&&" || CSA[c] == "||" || CSB[c] == "kw")) return 0
    j = eff(c); n = CNW[c]
    if (j > n) return 0
    b = rs_norm(WR[c, j])
    if (base(b) == "git" && CSA[c] == "&&") {
        for (a = j + 1; a <= n && WR[c, a] ~ /^-/; a++) if (WR[c, a] == "-C" || WR[c, a] == "-c") a++
        if (a < n && (WR[c, a] == "clone" || (WR[c, a] == "worktree" && WR[c, a + 1] == "add")))
            for (a++; a <= n; a++) if (rs_norm(WR[c, a]) == p) return 1
        return 0
    }
    if (b == "[[") {
        seg = rs_norm(substr(S, WS[c, j], CEND[c] - WS[c, j] + 1))
        return index(seg " ", " " p " ") > 0 || index(seg, " " p "]") > 0
    }
    if (b != "test" && b != "[") return 0
    for (a = j + 1; a <= n; a++) if (rs_norm(WR[c, a]) == p) return 1
    return 0
}

# Is a variable that p is built from (re)assigned in command c?
function rs_reassigns(c, p,    t, v, a, n, w) {
    n = CNW[c]; t = p
    while (match(t, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
        v = substr(t, RSTART + 1, RLENGTH - 1); t = substr(t, RSTART + RLENGTH)
        if (WR[c, 1] == "for" && WR[c, 2] == v) return 1
        for (a = 1; a <= n; a++) {
            w = WR[c, a]
            if (index(w, v "=") == 1 || index(w, v "+=") == 1) return 1
            if (WR[c, 1] == "read" && w == v) return 1
        }
    }
    return 0
}

function rs_errexit(c,    a, n) {
    if (WR[c, 1] != "set") return 0
    n = CNW[c]
    for (a = 2; a <= n; a++) {
        if (WR[c, a] ~ /^-[a-zA-Z]*e/) return 1
        if (WR[c, a] == "-o" && WR[c, a + 1] == "errexit") return 1
    }
    return 0
}

function reset_check(    k, j, n, b, a, w, rec, p, c, v, chain, exited, shown) {
    V["reset"] = "ALLOW"; M["reset"] = ""
    for (k = 1; k <= NC; k++) {
        if (rs_errexit(k)) return
        j = eff(k); n = CNW[k]
        if (j > n) continue
        b = base(rs_norm(WR[k, j]))
        if (b == "rm" || b == "grm") {
            rec = 0
            for (a = j + 1; a <= n; a++) {
                w = WR[k, a]
                if (w == "--") break
                if (w == "--recursive" || w ~ /^-[a-zA-Z]*[rR]/) rec = 1
            }
            if (!rec) continue
        } else if (b != "rmdir") continue
        for (a = j + 1; a <= n; a++) {
            w = WR[k, a]
            if (w ~ /^-/ && w != "-") continue
            p = rs_target(w)
            if (p == "") continue
            chain = (CSA[k] == "&&"); exited = 0
            for (c = k + 1; c <= NC; c++) {
                if (rs_checks(c, p) || rs_reassigns(c, p)) break
                if (CSA[k] == "||" && (base(WR[c, 1]) == "exit" || base(WR[c, 1]) == "return")) exited = 1
                if (exited) break
                v = rs_reuse(c, p)
                if (v != "") {
                    if (chain) break
                    shown = w; gsub(/["']/, "", shown)
                    verdict("reset", "DENY", "enforce-no-reset-by-name: this command removes " shown " and then reuses it (" v ") without checking the remove worked. rm can FAIL and leave the directory in place (in the Claude sandbox the Trash is refused, rc 1), and with 2>/dev/null or ; the chain carries on, so the reuse silently merges into STALE files. Safe routes: a fresh directory per run, d=$(mktemp -d \"$TMPDIR/name.XXXXXX\") (always pass a template: BSD mktemp ignores TMPDIR without one); or stop the chain when the remove fails: rm -rf " shown " && test ! -e " shown " && mkdir -p " shown ". The rm keeps failing loudly by design (no fallback); do not hide its stderr.")
                    return
                }
                if (CSA[c] != "&&") chain = 0
            }
        }
    }
}

# ------------------------------------------------------------------ pjw
# Used by enforce-pj-workers.sh (CONV_MODE=pjw). Deny only, never a rewrite.
# W-20260924-A59, rulings D-20260924-A04/A05: a conductor starts a Claude worker
# ONLY through `pj-worker start` (clean room: `pj-worker start --cleanroom`).
# This mode refuses the conductor's honest slip, early. It is NOT the floor: the
# `claude()` guard in the pane's own zsh is, because herdr TYPES `claude` into the
# pane and a Bash hook sees only this call's text (redteam-3 H1: send-keys letter
# by letter, send-text split over two calls, a script on the socket all pass here).
#
# Denied:
#   herdr [global opts] agent start ... --kind K   K (trimmed, lowercased) not in
#       the known list of NON-claude kinds from herdr 0.9.1's --help: so claude,
#       claude-code, Claude, an expansion, or no readable --kind at all
#   herdr pane run|send-text <pane> <text>, and send-keys spelling text: the text
#       is re-scanned as the pane's zsh would run it, and denied when the COMMAND
#       WORD of any command in it is claude (bare or by path) or a .zshrc alias or
#       function that launches it (cb cr ci cpr cd_ cskip ct lifeos claude-clean,
#       __claude_launch claude). claude's info forms pass: --version, --help and
#       the subcommands in pj_info().
# Seen through: $(...), backticks, function bodies, and the string argument of
#   bash/sh/zsh/dash/ksh -c, eval, and ssh's remote command (all re-scanned).
# Allowed: pj, pj-worker, herdr-quick-task (not herdr), other kinds, claude as an
#   ARGUMENT (alias claude, which claude), prose in quotes, heredocs and commits.
# Override: a PJ_WORKERS_CONTROL=W-YYYYMMDD-XNN assignment on the herdr command
#   turns its deny into CONTROL: allowed, logged and named by the hook.
# Output: ALLOW | DENY | CONTROL, then one message line (CONTROL: the item id,
#   then the message).

function pj_kind_ok(k) {
    return k ~ /^(pi|codex|gemini|cursor|devin|agy|cline|omp|mastracode|opencode|copilot|kimi|kiro|droid|amp|grok|hermes|kilo|qodercli|qwen|letta|maki|muse)$/
}
function pj_alias(b) { return b ~ /^(cb|cr|ci|cpr|cd_|cskip|ct|lifeos|claude-clean)$/ }
# claude words that print or manage, and never start a session.
function pj_info(w) {
    return w ~ /^(-v|-V|--version|-h|--help|agents|mcp|doctor|plugin|plugins|update|upgrade|install|config|migrate-installer|setup-token|auth)$/
}
function pj_is_claude(v) { return base(v) == "claude" || v ~ /\/claude\/versions\/[^\/]+$/ }

# The text zsh passes as the argument, quotes removed, expansions left as written.
function pj_dq(w,    i, n, c, out) {
    n = length(w); out = ""; i = 1
    while (i <= n) {
        c = substr(w, i, 1)
        if (c == "'") { i++; while (i <= n && substr(w, i, 1) != "'") { out = out substr(w, i, 1); i++ }; i++; continue }
        if (c == "$" && substr(w, i + 1, 1) == "'") {
            i += 2
            while (i <= n && substr(w, i, 1) != "'") {
                c = substr(w, i, 1)
                if (c == "\\") { i++; c = substr(w, i, 1); if (c == "n") c = "\n"; else if (c == "t") c = "\t" }
                out = out c; i++
            }
            i++; continue
        }
        if (c == "\"") {
            i++
            while (i <= n && substr(w, i, 1) != "\"") {
                c = substr(w, i, 1)
                if (c == "\\" && index("$`\"\\\n", substr(w, i + 1, 1)) > 0) { i++; c = substr(w, i, 1) }
                out = out c; i++
            }
            i++; continue
        }
        if (c == "\\") { i++; out = out substr(w, i, 1); i++; continue }
        out = out c; i++
    }
    return out
}

function pj_enqueue(t, ctx, ov, where) {
    if (QN >= 64) { pj_hit("DENY", "enforce-pj-workers: more than 64 nested strings to re-scan; refusing rather than guessing", ""); return }
    QN++; QT[QN] = t; QX[QN] = ctx; QO[QN] = ov; QW[QN] = where
}

# First DENY wins; a CONTROL (override) is kept only while nothing is denied.
function pj_hit(v, m, ov) {
    if (PV == "DENY") return
    if (v == "DENY" && ov != "") { if (PV == "") { PV = "CONTROL"; PM = m; PO = ov }; return }
    PV = v; PM = m
}

function pj_msg_worker(what) {
    return "enforce-pj-workers: " what ". A conductor starts a Claude worker ONLY with `pj-worker start` (it launches a pj session, checks it, and counts the 4-session cap), and a clean-room worker with `pj-worker start --cleanroom` (D-20260924-A04/A05; the text exemption -- --setting-sources '' is refused). Other agent kinds (codex, gemini, ...) are allowed. A proof that needs a plain worker as its control: prefix the herdr command with PJ_WORKERS_CONTROL=<item id>; it is allowed, logged and named."
}

# herdr command k, its command word at j. Reads global options, then the group.
function pj_herdr(k, j, ov, ctx, where,    a, n, g, s, kind, gotk, clean, t, w, sep) {
    n = CNW[k]
    for (a = j + 1; a <= n; a++) {
        w = unq(WR[k, a])
        if (w == "--machine" || w == "--session" || w == "--remote" || w == "--remote-keybindings") { a++; continue }
        if (w ~ /^-/) continue
        break
    }
    if (a > n) return
    g = unq(WR[k, a]); s = unq(WR[k, a + 1])
    if (g == "agent" && s == "start") {
        gotk = 0; clean = 0; kind = ""
        for (a += 2; a <= n; a++) {
            w = WR[k, a]
            if (w == "--") {
                for (a++; a <= n; a++) if (unq(WR[k, a]) ~ /^--setting-sources(=|$)/) clean = 1
                break
            }
            if (w == "--kind" || w ~ /^--kind=/) {
                if (w == "--kind") { a++; w = (a <= n) ? WR[k, a] : "" } else sub(/^--kind=/, "", w)
                gotk = 1; kind = (w ~ /[$`]/) ? "" : tolower(pj_dq(w))
                gsub(/^[ \t]+|[ \t]+$/, "", kind)
            }
        }
        if (gotk && pj_kind_ok(kind)) return
        if (clean) t = "`herdr agent start --kind claude -- --setting-sources ''` is the clean-room text exemption, refused by ruling"
        else if (!gotk) t = "`herdr agent start` with no --kind this hook can read (herdr needs one, and it may be claude)"
        else if (kind == "") t = "`herdr agent start --kind` from an expansion this hook cannot read (it may be claude)"
        else if (kind == "claude" || kind == "claude-code") t = "`herdr agent start --kind " kind "` starts plain claude, not a pj session"
        else t = "`herdr agent start --kind " kind "`: not a kind herdr 0.9.1 lists besides claude"
        pj_hit("DENY", pj_msg_worker(t (where != "" ? " (" where ")" : "")), ov)
        return
    }
    if (g == "pane" && (s == "run" || s == "send-text" || s == "send-keys")) {
        t = ""; sep = ""
        for (a += 3; a <= n; a++) {
            w = pj_dq(WR[k, a])
            if (s == "send-keys") {
                if (w == "space") w = " "
                else if (w == "enter" || w == "return") w = "\n"
                else if (w == "tab") w = "\t"
                else if (length(w) > 1 && w ~ /^(ctrl|alt|shift|meta|cmd)\+|^(esc|escape|up|down|left|right|home|end|backspace|delete|pageup|pagedown|f[0-9]+)$/) w = ""
                t = t w
            } else { t = t sep w; sep = " " }
        }
        pj_enqueue(t, "pane", ov, "typed into a pane by herdr pane " s)
    }
}

# Is simple command k (typed into a pane) a claude session? Returns a label or "".
function pj_pane_claude(k, j,    n, a, v, w) {
    n = CNW[k]
    v = unq(WR[k, j])
    if (v == "") {                    # the command word is an expansion: read every word
        for (a = j; a <= n; a++) { w = base(unq(WR[k, a])); if (w == "claude" || pj_alias(w)) return w " (after an expansion)" }
        return ""
    }
    if (base(v) == "__claude_launch" || base(v) == "_claude_launch") {
        for (j++; j <= n && WR[k, j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/; j++) ;
        if (j > n) return ""
        v = unq(WR[k, j])
    }
    if (pj_alias(base(v))) return base(v)
    if (!pj_is_claude(v)) return ""
    for (a = j + 1; a <= n; a++) {
        w = unq(WR[k, a])
        if (pj_info(w)) return ""
        if (w !~ /^-/) break
    }
    for (a = j + 1; a <= n; a++) if (unq(WR[k, a]) ~ /^--setting-sources(=|$)/) return "claude --setting-sources (the clean-room text exemption)"
    return "claude"
}

function pj_scan(ctx, ov, where,    k, j, n, a, w, b, ovk, t, lab) {
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n) continue
        ovk = ov
        for (a = 1; a < j; a++) if (WR[k, a] ~ /^PJ_WORKERS_CONTROL=/) {
            w = unq(WR[k, a]); sub(/^PJ_WORKERS_CONTROL=/, "", w)
            if (w ~ /^W-[0-9]{8}-[A-Z][0-9]+$/) ovk = w
        }
        w = unq(WR[k, j]); b = base(w)
        if (ctx == "pane") {
            lab = pj_pane_claude(k, j)
            if (lab != "") { pj_hit("DENY", pj_msg_worker("`" lab "` " (where != "" ? where : "typed into a pane") ", which starts plain claude, not a pj session"), ovk); if (PV == "DENY") return }
        }
        if (b == "herdr") { pj_herdr(k, j, ovk, ctx, where); if (PV == "DENY") return; continue }
        if (b ~ /^(bash|sh|zsh|dash|ksh)$/) {
            for (a = j + 1; a <= n; a++) {
                w = unq(WR[k, a])
                if (w ~ /^-[a-zA-Z]*c[a-zA-Z]*$/) { if (a < n) pj_enqueue(pj_dq(WR[k, a + 1]), ctx, ovk, "inside " b " -c"); break }
                if (w !~ /^[-+]/) break
            }
            continue
        }
        if (b == "eval") {
            t = ""; for (a = j + 1; a <= n; a++) t = t (a > j + 1 ? " " : "") pj_dq(WR[k, a])
            pj_enqueue(t, ctx, ovk, "inside eval"); continue
        }
        if (b == "ssh") {
            for (a = j + 1; a <= n; a++) {
                w = unq(WR[k, a])
                if (w ~ /^-[bcDEeFIiJLlmOoPpQRSWw]$/) { a++; continue }
                if (w ~ /^-/) continue
                break
            }
            t = ""; for (a++; a <= n; a++) t = t (t != "" ? " " : "") pj_dq(WR[k, a])
            if (t != "") pj_enqueue(t, ctx, ovk, "inside ssh's remote command")
            continue
        }
        # herdr behind a wrapper eff() does not know (timeout 60 herdr ...,
        # caffeinate herdr ...): any later UNQUOTED word that is herdr.
        for (a = j + 1; a <= n; a++) if (!WQ[k, a] && base(WR[k, a]) == "herdr") { pj_herdr(k, a, ovk, ctx, where); break }
        if (PV == "DENY") return
    }
}

function pj_load(t) { S = t; N = split(S, C, ""); P = 1; NC = 0; HDN = 0; BG = 0; UNSURE = ""; SUBSH = 0; BTN = 0 }

function pjw_main(    qi, i) {
    PV = ""; PM = ""; PO = ""; QN = 1; QT[1] = S; QX[1] = "bash"; QO[1] = ""; QW[1] = ""
    for (qi = 1; qi <= QN; qi++) {
        pj_load(QT[qi])
        parse_list(1, "", 0, "^")
        pj_scan(QX[qi], QO[qi], QW[qi])
        if (PV == "DENY") break
        for (i = 1; i <= BTN; i++) pj_enqueue(BT[i], QX[qi], QO[qi], "inside backticks")
    }
    if (PV == "DENY") { print "DENY"; print PM; exit 0 }
    if (PV == "CONTROL") { print "CONTROL"; print PO " " PM; exit 0 }
    print "ALLOW"; print ""; exit 0
}

# ------------------------------------------------------------------ main

{ S = (NR > 1 ? S "\n" : "") $0 }

END {
    N = split(S, C, "")
    mode = ENVIRON["CONV_MODE"]
    P = 1; NC = 0; HDN = 0; BG = 0; UNSURE = ""; SUBSH = 0; BTN = 0
    REC_NESTED = (mode == "guard" || mode == "pjw")   # only these look inside $(...) and backticks
    if (mode == "pjw") pjw_main()
    parse_list(1, "", 0, "^")
    if (HDN) unsure("here-document with no body")
    if (mode == "guard" || mode == "builtin" || mode == "reset") {   # deny-only modes: never compose
        if (mode == "guard") guard_check(); else if (mode == "builtin") builtin_check(); else reset_check()
        print V[mode]; print M[mode]; exit 0
    }
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
