# conv-shscan.awk -- the zsh command scanner shared by the convention hooks.
#
# Used by enforce-uv.sh and enforce-pnpm.sh (beside this file, stowed to
# ~/.claude/hooks/) and by this repo's project-only .claude/hooks/enforce-no-cd.sh
# (which reaches it through the repo path home/.claude/hooks/). NOT a hook itself:
# nothing registers it, the three hooks run it with `awk -f`. Also read by
# validate-bash.sh, enforce-pj-workers.sh, enforce-no-reset-by-name.sh,
# enforce-builtin.sh and warn-install-telemetry.sh (CONV_MODE=install, advisory).
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
# Env:    CONV_MODE = uv | pnpm | nocd | guard | builtin | reset | pjw | install
#         (which hook is asking; install prints HIT lines instead, see its section)
#         CONV_CWD  = the payload's cwd (npx looks for a local binary from here)
# Output: line 1  ALLOW | DENY | REWRITE
#         line 2  one-line message for the session (DENY reason or what changed)
#         line 3+ REWRITE only: the new command, verbatim
#
# ASCII only in this file.

# ------------------------------------------------------------------ scanner

function unsure(why) {
    if (UNSURE == "") UNSURE = why
    if (why != "function definition" && why != "zsh construct case" && UNSURE_NF == "") UNSURE_NF = why   # fp_check, W-20260929-A53, A123
}

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
            if (HDK[h] > 0) HBODY[HDK[h]] = HBODY[HDK[h]] "\n" line   # A47: kept for fp_check
            if (HDK[h] > 0 && !HDQ[h]) UHB[HDK[h]] = UHB[HDK[h]] "\n" line   # A118: $(...) here runs
        }
    }
    HDN = 0
}

# A redirection starting at P (at <, > or the & of &>). Its target is not a word.
function handle_redir(k,    c, ws, d, dup) {
    c = C[P]
    if (c == "<" && C[P + 1] == "<" && C[P + 2] == "<") {
        P += 3; skip_blanks(); ws = P; parse_word()
        if (k > 0) HBODY[k] = HBODY[k] "\n" pj_dq(substr(S, ws, P - ws))   # A47/A50: a here-string's text, unquoted
    } else if (c == "<" && C[P + 1] == "<") {
        P += 2; d = 0
        if (C[P] == "-") { d = 1; P++ }
        skip_blanks(); ws = P; parse_word()
        HDN++; HD[HDN] = unquote_delim(substr(S, ws, P - ws)); HDD[HDN] = d
        HDK[HDN] = k                                  # A47: whose body this is
        HDQ[HDN] = (substr(S, ws, P - ws) ~ /["'\\]/)  # A118: a quoted marker keeps the body literal
        if (HD[HDN] == "") unsure("here-document with no delimiter")
    } else if ((c == "<" || c == ">") && C[P + 1] == "(") {
        P += 2; ws = P; parse_list(REC_NESTED, ")", 1, c "(")   # process substitution, an argument
        if (k > 0 && c == "<") PSB[k] = substr(S, ws, P - ws - 1)   # A118: source <(...) runs its output
    } else {
        dup = 0
        if (c == "&") P++
        P++
        while (P <= N && (C[P] == ">" || C[P] == "|" || C[P] == "!" || C[P] == "&")) {
            if (C[P] == "&") { P++; dup = 1; break }   # >& : fd duplication, or >&file
            P++
        }
        skip_blanks()
        if ((C[P] == "<" || C[P] == ">") && C[P + 1] == "(") { P += 2; parse_list(REC_NESTED, ")", 1, C[P - 2] "(") }
        else {
            ws = P; parse_word()
            if (P == ws) unsure("redirection with no target")
            # reset mode reads where output goes: > >> &> >| >! and fd forms
            # W-20261006-A45: >&N and >&- duplicate or close a descriptor and write no file,
            # so a target of only digits or - is not recorded; >&file still is.
            else if (k > 0 && c != "<" && !(dup && substr(S, ws, P - ws) ~ /^([0-9]+|-)$/)) { RDN[k]++; RDT[k, RDN[k]] = substr(S, ws, P - ws) }
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
            if (CASEPAT) { CASEPAT = 0; end_cmd(k, "kw"); k = 0; sep = "kw"; P++; continue }   # A123: a case pattern ends
            if (closer == ")") { end_cmd(k, ")"); P++; return }
            unsure("unmatched )"); end_cmd(k, ")"); k = 0; sep = ")"; P++; continue
        }
        if (c == ";") {
            if (C[P + 1] == ";" || C[P + 1] == "&" || C[P + 1] == "|") {
                if (CASEOPEN > 0) CASEPAT = 1; else unsure("case clause")   # A123: ;; inside a case is expected
                P += 2
            } else P++
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
            if (k == 0 && CASEPAT) { P++; continue }   # A123: (pattern) in a case
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
            if (!q && raw == "esac" && CASEOPEN > 0) { CASEOPEN--; CASEPAT = 0 }   # A123
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
            if (!q && raw == "case") { CASEOPEN++; CASEIN = 0 }   # A123
            k = new_cmd(rec, depth, sep)
        } else if (!q && raw == "}" && closer == "}") { end_cmd(k, "}"); return }
        add_word(k, ws, P - 1, q)
        if (!q && raw == "in" && CASEOPEN > 0 && !CASEIN) { CASEIN = 1; CASEPAT = 1; end_cmd(k, "kw"); k = 0; sep = "kw" }   # A123
    }
    end_cmd(k, "$")
    if (closer != "") unsure("unterminated " (closer == ")" ? "(" : "{"))
}

# ------------------------------------------------------------------ word helpers

function base(w) { sub(/.*\//, "", w); return w }
# The text zsh would run for a word, or "" when it holds an expansion we cannot know.
function unq(w) {   # A123: \<newline> joins a word; $'...' is decoded
    gsub(/\\\n/, "", w)
    if (w ~ /^[$]'[^'$`]*'$/) return pj_dq(w)
    if (w ~ /[$`]/) return ""; gsub(/["'\\]/, "", w); return w
}
function isopt(k, a) { return WR[k, a] ~ /^-/ }

# Index of the effective command word of simple command k, after assignments and
# precommand modifiers. Sets EM to the modifiers seen: " assign", " env",
# " envopt", " time", " nohup", " noglob", " nocorrect", " hard:<name>", " probe".
# A "hard" modifier (sudo doas exec xargs command builtin -) or an env option means
# the words after it cannot be read reliably, so no hook rewrites past one.
# A123: does option o of prefix command c take the next word as its value?
function effval(c, o) {
    if (c == "timeout" || c == "gtimeout") return o == "-s" || o == "-k" || o == "--signal" || o == "--kill-after"
    if (c == "nice") return o == "-n" || o == "--adjustment"
    if (c == "caffeinate") return o == "-t" || o == "-w"
    if (c == "stdbuf" || c == "gstdbuf") return o == "-i" || o == "-o" || o == "-e"
    if (c == "watch") return o == "-n" || o == "--interval" || o == "-q" || o == "--equexit"
    return 0
}
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
        if (w == "time") { EM = EM " time"; j++; while (j <= n && WR[k, j] ~ /^-/) j++; continue }   # A123: time -p
        if (w == "nohup" || w == "noglob" || w == "nocorrect") { EM = EM " " w; j++; continue }
        # A123 (lexer comparison S39-S45): prefixes that run the command after their options
        if (w == "timeout" || w == "gtimeout" || w == "nice" || w == "caffeinate" || w == "stdbuf" || w == "gstdbuf" || w == "watch") {
            EM = EM " hard:" w; j++
            while (j <= n && WR[k, j] ~ /^-/) {
                if (effval(w, WR[k, j])) j++
                j++
            }
            if (w == "timeout" || w == "gtimeout") j++   # the duration
            continue
        }
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
#   B. gpf!, the oh-my-zsh alias for `git push --force`. gpf and gpsupf are
#      --force-with-lease and are not denied here: rule D below reads them since
#      2026-09-29 (D-20260929-A08), deny on main, allow on a feature branch.
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
    }
    s = rd_check()
    if (s != "") { verdict("guard", "DENY", s); return }
    s = tu_check()
    if (s != "") { verdict("guard", "DENY", s); return }
    s = lk_check()
    if (s != "") { verdict("guard", "DENY", s); return }
    s = pp_check()
    if (s != "") { verdict("guard", "DENY", s); return }
    s = fp_check()
    if (s != "") { verdict("guard", "DENY", s); return }
}

# ------------------------------------------------------------------ guard: protected live files
# Rule E of guard mode, W-20260929-A35 (red-team H5), ruled by Gavin 2026-09-29
# (D-20260929-A14): a session must not weaken the LIVE guards or config from inside.
# Protected: ~/.claude/hooks (and below), ~/.gitconfig, ~/.claude/CLAUDE.md, and
# ~/.claude/projects/<key>/memory (and below). The dotfiles repo copies stay editable,
# so a guard fix goes through the repo and a commit.
# Denied: an output redirection into one; sed/gsed -i, perl -i, tee, truncate, touch,
# chmod, chown, rm, unlink, mv on one; cp, install, rsync, ditto or ln with one as the
# destination; dd of=<one>; git config --global (or --file ~/.gitconfig) unless it only
# reads (--get*, --list, -l). Paths: ~, $HOME and ${HOME} are expanded, a relative path
# is joined to the payload's cwd or a cd earlier in the command.
# NOT read: a path held in any other variable, .. inside a path, Python or other
# languages, a script file. The Edit and Write tools are covered by the settings deny list.

function pp_path(w, cwd,    h) {
    if (w ~ /\$\(|`/) return ""
    gsub(/["'\\]/, "", w)
    h = ENVIRON["HOME"]
    if (w == "~" || substr(w, 1, 2) == "~/") w = h substr(w, 2)
    else if (substr(w, 1, 7) == "${HOME}") w = h substr(w, 8)
    else if (substr(w, 1, 5) == "$HOME") w = h substr(w, 6)
    if (w ~ /\$/ || w == "") return ""
    if (substr(w, 1, 1) != "/") { if (cwd == "") return ""; w = cwd "/" w }
    gsub(/\/\/+/, "/", w)
    while (substr(w, length(w)) == "/" && length(w) > 1) w = substr(w, 1, length(w) - 1)
    return w
}
function pp_protected(p,    h, r) {
    if (p == "") return 0
    h = ENVIRON["HOME"]
    if (h == "") return 0
    if (p == h "/.gitconfig" || p == h "/.claude/CLAUDE.md" || p == h "/.claude/hooks") return 1
    if (index(p, h "/.claude/hooks/") == 1) return 1
    if (index(p, h "/.claude/projects/") == 1) {
        r = substr(p, length(h "/.claude/projects/") + 1)
        # the auto-memory: memory/ itself and its top-level entries; the open-items drawer in
        # memory/WORK/ stays writable (D-20260929-A14 narrowed, Gavin 2026-09-29)
        if (r ~ /^[^\/]+\/memory$/) return 1
        if (r ~ /^[^\/]+\/memory\/[^\/]+$/ && r !~ /\/memory\/WORK$/) return 1
    }
    return 0
}
function pp_msg(p, how) {
    sub("^" ENVIRON["HOME"], "~", p)
    return "Protected live file (D-20260929-A14): " how " would change " p ". The live guards, ~/.gitconfig, ~/.claude/CLAUDE.md and the memory folders are locked so a session cannot weaken them from inside. Edit the dotfiles repo copy and commit, or ask Gavin"
}
function pp_check(    k, j, n, a, b, w, cwd, p, i, last, inpl, rd, v) {
    cwd = ENVIRON["CONV_CWD"]
    for (k = 1; k <= NC; k++) {
        for (i = 1; i <= RDN[k]; i++) { p = pp_path(RDT[k, i], cwd); if (pp_protected(p)) return pp_msg(p, "a > redirection") }
        j = eff(k); n = CNW[k]
        if (j > n) continue
        b = base(unq(WR[k, j]))
        if (b == "cd" || b == "pushd") {
            for (a = j + 1; a <= n && WR[k, a] ~ /^-[A-Za-z]/; a++) ;
            p = (a > n) ? ENVIRON["HOME"] : pp_path(WR[k, a], cwd)
            cwd = p; continue
        }
        if (b == "sed" || b == "gsed" || b == "perl") {
            inpl = 0
            for (a = j + 1; a <= n; a++) { v = unq(WR[k, a]); if (v ~ /^--in-place/ || v ~ /^-[A-Za-z]*i/) inpl = 1 }
            if (!inpl) continue
            for (a = j + 1; a <= n; a++) { p = pp_path(WR[k, a], cwd); if (pp_protected(p)) return pp_msg(p, b " -i") }
            continue
        }
        if (b == "tee" || b == "truncate" || b == "touch" || b == "chmod" || b == "chown" || b == "rm" || b == "grm" || b == "unlink" || b == "mv" || b == "gmv") {
            for (a = j + 1; a <= n; a++) { p = pp_path(WR[k, a], cwd); if (pp_protected(p)) return pp_msg(p, b) }
            continue
        }
        if (b == "cp" || b == "gcp" || b == "install" || b == "rsync" || b == "ditto" || b == "ln") {
            last = ""
            for (a = j + 1; a <= n; a++) {
                w = WR[k, a]
                if (w == "-t" || w == "--target-directory") { p = pp_path(WR[k, a + 1], cwd); if (pp_protected(p)) return pp_msg(p, b); a++; continue }
                if (w ~ /^-/) continue
                last = w
            }
            p = pp_path(last, cwd); if (pp_protected(p)) return pp_msg(p, b " into it")
            continue
        }
        if (b == "dd") {
            for (a = j + 1; a <= n; a++) { v = WR[k, a]; if (v ~ /^["']?of=/) { sub(/^["']?of=/, "", v); p = pp_path(v, cwd); if (pp_protected(p)) return pp_msg(p, "dd of=") } }
            continue
        }
        if (b == "git") {
            for (a = j + 1; a <= n && unq(WR[k, a]) ~ /^-/; a++) if (unq(WR[k, a]) == "-C" || unq(WR[k, a]) == "-c") a++
            if (a > n || unq(WR[k, a]) != "config") continue
            rd = 0; v = 0
            for (i = a + 1; i <= n; i++) {
                w = unq(WR[k, i])
                if (w == "--global") v = 1
                if ((w == "--file" || w == "-f") && pp_protected(pp_path(WR[k, i + 1], cwd))) v = 1
                if (w ~ /^--file=/ && pp_protected(pp_path(substr(w, 8), cwd))) v = 1
                if (w ~ /^--get/ || w == "--list" || w == "-l") rd = 1
            }
            if (v && !rd) return pp_msg(ENVIRON["HOME"] "/.gitconfig", "git config --global")
        }
    }
    return ""
}

# ------------------------------------------------------------------ guard: leak-scan bypass
# Rule F of guard mode, W-20260929-A32 (red-team H2), ruled by Gavin 2026-09-29
# (D-20260929-A13): every way to skip the leak scan is denied. git push --no-verify
# skips the pre-push scan (and the whole hook chain); git commit --no-verify or -n (in any
# short cluster before a value-taking letter) skips the pre-commit one; so do
# LEAK_SCAN_DISABLE=<value> (as a prefix, or export/typeset/declare), git config
# leakscan.disable <truthy> and a git config or git -c that SETS core.hooksPath. Allowed:
# leakscan.skip (the narrow, named knob), reading config, --unset, push -n (a dry run).
# NOT read: a knob held in a variable, a script file, git aliases.

function lk_msg(what) {
    return "Leak-scan bypass (D-20260929-A13): " what ". A skipped scan is how a token reaches a public repo. Fix what the scan found, or silence one noisy rule with git config leakscan.skip <rule-id>, or ask Gavin"
}
function lk_truthy(v) { v = tolower(v); return v == "true" || v == "1" || v == "yes" || v == "on" }
function lk_check(    k, j, n, a, w, b, sub_, key, val, rd, c, ch, ga) {
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        for (a = 1; a < j && a <= n; a++) {
            w = unq(WR[k, a])
            if (w ~ /^LEAK_SCAN_DISABLE=./) return lk_msg("LEAK_SCAN_DISABLE set on the command")
        }
        if (j > n) continue
        b = base(unq(WR[k, j]))
        if (b == "export" || b == "typeset" || b == "declare" || b == "local") {
            for (a = j + 1; a <= n; a++) if (unq(WR[k, a]) ~ /^LEAK_SCAN_DISABLE=./) return lk_msg(b " LEAK_SCAN_DISABLE")
            continue
        }
        if (b != "git") continue
        for (a = j + 1; a <= n; a++) {
            w = unq(WR[k, a])
            if (w == "-c") {
                val = unq(WR[k, a + 1]); key = tolower(val); sub(/=.*/, "", key)
                if (key == "core.hookspath") return lk_msg("git -c core.hooksPath")
                if (key == "leakscan.disable" && (val !~ /=/ || lk_truthy(substr(val, index(val, "=") + 1)))) return lk_msg("git -c leakscan.disable")
                a++; continue
            }
            if (w == "-C" || w == "--git-dir" || w == "--work-tree" || w == "--namespace") { a++; continue }
            if (w ~ /^-/) continue
            break
        }
        if (a > n) continue
        sub_ = unq(WR[k, a])
        if (sub_ == "push") {
            for (ga = a + 1; ga <= n; ga++) if (unq(WR[k, ga]) == "--no-verify") return lk_msg("git push --no-verify skips the pre-push leak scan")
            continue
        }
        if (sub_ == "commit" || sub_ == "merge") {
            for (ga = a + 1; ga <= n; ga++) {
                w = unq(WR[k, ga])
                if (w == "--no-verify") return lk_msg("git " sub_ " --no-verify skips the pre-commit leak scan")
                if (w == "--") break
                if (sub_ == "commit" && w ~ /^-[A-Za-z]+$/) {
                    for (c = 2; c <= length(w); c++) {
                        ch = substr(w, c, 1)
                        if (ch == "n") return lk_msg("git commit -n (--no-verify) skips the pre-commit leak scan")
                        if (index("mFcCtS", ch)) break
                    }
                    if (w ~ /^-[mFcCt]$/) ga++
                }
            }
            continue
        }
        if (sub_ == "config") {
            rd = 0; key = ""; val = ""
            for (ga = a + 1; ga <= n; ga++) {
                w = unq(WR[k, ga])
                if (w ~ /^--(get|list|unset|remove-section|rename-section|show-origin|get-regexp|get-all|get-urlmatch|name-only)/ || w == "-l" || w == "--edit" || w == "-e") { if (w !~ /^--show-origin/ && w !~ /^--name-only/) rd = 1; continue }
                if (w == "--file" || w == "-f" || w == "--blob" || w == "--type") { ga++; continue }
                if (w ~ /^-/) continue
                if (key == "") { key = tolower(w); continue }
                if (val == "") { val = w; break }
            }
            if (rd || key == "" || val == "") continue
            if (key == "core.hookspath") return lk_msg("git config core.hooksPath replaces every hook, the leak scan included")
            if (key == "leakscan.disable" && lk_truthy(val)) return lk_msg("git config leakscan.disable")
        }
    }
    return ""
}

# ------------------------------------------------------------------ guard: token in a URL
# Rule G of guard mode, W-20260929-A51: curl, wget, http/https (httpie), xh or aria2c
# given a URL whose user part (before the @) holds a token-shaped string: gh[pousr]_,
# github_pat_, sk-, xox?-, glpat-, npm_. The command sends the secret to that host, and
# the typed line already put it in the transcript. git remotes with a token are
# enforce-gh-ssh-only's; -u user (curl prompts) and x-access-token with no secret pass.
# NOT read: a URL held in a variable, a token in a header or a --data body.

function tu_cred(w,    ui) {
    gsub(/["'\\]/, "", w)
    if (w !~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/]*@/) return 0
    ui = w; sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "", ui); sub(/@.*/, "", ui)
    return ui ~ /(^|:)(gh[pousr]_|github_pat_|sk-|xox[a-z]-|glpat-|npm_)[A-Za-z0-9_-]/
}
function tu_check(    k, j, n, a, b) {
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n) continue
        b = base(unq(WR[k, j]))
        if (b != "curl" && b != "wget" && b != "http" && b != "https" && b != "xh" && b != "aria2c") continue
        for (a = j + 1; a <= n; a++) if (tu_cred(WR[k, a]))
            return "A token in a URL (W-20260929-A51): " b " would send the credential before the @ to that host. Use a credential helper, a -H header read from a file you do not print, or ask Gavin; the typed token is also now in this transcript, so rotate it if it was real"
    }
    return ""
}

# ------------------------------------------------------------------ guard: remote deletes
# Rule H of guard mode, W-20260929-A37 (red-team H7, cases D27 D28 D37 D38 D39): a delete
# on a remote has no Trash and no undo. Denied: git push --delete / -d (in any short
# cluster), a refspec starting with : (git push origin :feature), the push aliases with
# the same; gh repo delete, gh release delete / delete-asset, gh gist delete; gh api with
# -X / --method DELETE. Allowed: every other push, gh api reads, git branch -d (local).
# NOT read: a flag or method held in a variable, curl -X DELETE to an API.

function rd_msg(what) { return "Remote delete (W-20260929-A37): " what ". A deleted remote branch, repo or release has no Trash and no undo, for everyone. Ask Gavin" }
function rd_push(k, s,    a, v, c) {           # the words after push start at s
    for (a = s; a <= CNW[k]; a++) {
        v = unq(WR[k, a])
        if (v == "--delete") return rd_msg("git push --delete")
        if (v ~ /^-[A-Za-z]+$/) { for (c = 2; c <= length(v); c++) { if (substr(v, c, 1) == "d") return rd_msg("git push -d"); if (substr(v, c, 1) == "o") break } ; continue }
        if (v ~ /^\+?:[^:]/) return rd_msg("git push " v " (an empty source deletes the remote ref)")
    }
    return ""
}
function rd_check(    k, j, n, a, b, w, s, x, m) {
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n) continue
        w = unq(WR[k, j]); b = base(w)
        if (!WQ[k, j] && fp_alias(WR[k, j]) ~ /^push/) { s = rd_push(k, j + 1); if (s != "") return s; continue }
        if (b == "git") {
            for (a = j + 1; a <= n; a++) { x = unq(WR[k, a]); if (x == "-C" || x == "-c") { a++; continue }; if (x ~ /^-/) continue; break }
            if (a <= n && unq(WR[k, a]) == "push") { s = rd_push(k, a + 1); if (s != "") return s }
            continue
        }
        if (b != "gh") continue
        for (a = j + 1; a <= n; a++) { x = unq(WR[k, a]); if (x == "-R" || x == "--repo") { a++; continue }; if (x ~ /^-/) continue; break }
        if (a > n) continue
        x = unq(WR[k, a])
        if ((x == "repo" || x == "gist") && unq(WR[k, a + 1]) == "delete") return rd_msg("gh " x " delete")
        if (x == "release" && (unq(WR[k, a + 1]) == "delete" || unq(WR[k, a + 1]) == "delete-asset")) return rd_msg("gh release " unq(WR[k, a + 1]))
        if (x == "api") {
            for (a++; a <= n; a++) {
                w = unq(WR[k, a]); m = ""
                if (w == "-X" || w == "--method") m = unq(WR[k, a + 1])
                else if (w ~ /^-X./) m = substr(w, 3)
                else if (w ~ /^--method=/) m = substr(w, 10)
                if (toupper(m) == "DELETE") return rd_msg("gh api " w " DELETE")
            }
        }
    }
    return ""
}

# ------------------------------------------------------------------ guard: force push
# Rule D of guard mode, W-20260929-A31 (red-team H1, 2026-09-28). A force push that
# can update main or master is denied. Until 2026-09-29 validate-bash matched three
# regexes that needed main or master typed as its own word beside the flag, so bare
# `git push -f` on main, +main, HEAD:main --force, main -f and --mirror all passed,
# and --no-verify was denied only because -[a-z]*f matched the f in "verify".
#
# Parsed like git parses it (git 2.55, measured): force is --force, -f in any short
# cluster (-uf), --force-with-lease[=...], --force-if-includes (alone it does not
# force; counted anyway, the conservative side), any unambiguous prefix of those
# (--force-w works, --forc is an error), last of --force/--no-force wins, and a +
# on one refspec forces that refspec only. --mirror always counts. -o takes a value
# (-of is -o f). A refspec's destination is after the colon, or the source when
# there is none; refs/heads/ and heads/ are dropped before comparing, so main-feature
# and fix-main are not main.
#
# A force push whose destination is the CURRENT branch (no refspec, or HEAD, or @)
# asks git in the payload's cwd, after any -C and any earlier cd in the same call.
# It FAILS CLOSED: no cwd, not a repo, git failing, a detached HEAD, remote.*.push
# configured, or -c/--git-dir/GIT_* changing what git reads all deny by name.
# push.default=matching denies; so does an upstream of main (push.default=upstream).
# Every earlier cd target is checked as well as the cwd, since a ( ) subshell may
# have undone it: a false positive there costs naming the branch.
#
# Also read: the zsh aliases gp gpd gpu gpv gpsup ggpush gpf gpsupf (expanded here),
# commands inside $(...), and a crude match on eval, backticks and sh/bash/zsh -c
# strings. gpf and gpsupf are lease forces: since D-20260929-A08 they deny on main
# like the long form and pass on a feature branch (until then, allowed everywhere).
# Function bodies are parsed commands like any other. Any other construct the
# scanner is UNSURE of sends the whole text to the crude match; a function
# definition does so only when some word is push or a push alias (W-20260929-A53).
# A47 (2026-09-29): an expansion before -- in the repository slot, or with a plain word
# anywhere beside a plain refspec, counts as a possible force flag (git push $F origin main,
# git push origin main $F; -- says it is not),
# and a here-document or here-string read by a shell (bash <<EOF, cat <<EOF | sh) gets
# the crude match. NOT read: scripts and
# other languages (python -c, a script file), a heredoc read by a non-shell; a push that DELETES main (:main, --delete) is not a
# force push and is out of this rule.

function fp_msg(why) { return "Force push to main/master is not allowed: " why ". A force push to main is Gavin's call: ask him" }
function fp_unk(why) { return "validate-bash cannot tell which branch this force push updates (" why "), so it is denied. Name the branch on the command line (git push --force origin <branch>), or ask Gavin" }
function fp_is_main(b) { sub(/^refs\/heads\//, "", b); sub(/^heads\//, "", b); return b == "main" || b == "master" }

# A single-quoted sh word, built without gsub (a backslash in its replacement
# string differs between awks).
function fp_shq(s,    out, i) {
    out = ""
    while ((i = index(s, "'")) > 0) { out = out substr(s, 1, i - 1) "'\\''"; s = substr(s, i + 1) }
    return "'" out s "'"
}

# Path p resolved against directory b; "" when it cannot be known.
function fp_join(b, p) {
    if (p == "") return ""
    if (p == "~") return ENVIRON["HOME"]
    if (substr(p, 1, 2) == "~/") return ENVIRON["HOME"] substr(p, 2)
    if (substr(p, 1, 1) == "~") return ""
    if (substr(p, 1, 1) == "/") return p
    if (b == "") return ""
    return b "/" p
}

# What a push to "the current branch" means in directory d. Returns "ok",
# "main:<why>" or "unk:<why>". One sh call per directory, cached.
function fp_head(d,    cmd, line, norepo, ended, rc, head, pd, rp, up, r) {
    if (d == "") return "unk:the working directory is not known"
    if (d in FPH) return FPH[d]
    cmd = "d=" fp_shq(d) "; git -C \"$d\" rev-parse --git-dir >/dev/null 2>&1 || { echo NOREPO; exit 0; }; " \
          "b=$(git -C \"$d\" symbolic-ref -q --short HEAD 2>/dev/null); echo \"RC=$?\"; echo \"HEAD=$b\"; " \
          "echo \"PD=$(git -C \"$d\" config --get push.default 2>/dev/null)\"; " \
          "echo \"RP=$(git -C \"$d\" config --get-regexp '^remote[.].*[.]push$' 2>/dev/null | head -n 1)\"; " \
          "[ -n \"$b\" ] && echo \"UP=$(git -C \"$d\" for-each-ref --format='%(upstream:remoteref)' \"refs/heads/$b\" 2>/dev/null)\"; " \
          "echo END"
    norepo = 0; ended = 0; rc = ""; head = ""; pd = ""; rp = ""; up = ""
    while ((cmd | getline line) > 0) {
        if (line == "NOREPO") norepo = 1
        else if (line == "END") ended = 1
        else if (line ~ /^RC=/) rc = substr(line, 4)
        else if (line ~ /^HEAD=/) head = substr(line, 6)
        else if (line ~ /^PD=/) pd = substr(line, 4)
        else if (line ~ /^RP=/) rp = substr(line, 4)
        else if (line ~ /^UP=/) up = substr(line, 4)
    }
    close(cmd)
    if (norepo) r = "unk:" d " is not a git repository, or git could not read it"
    else if (!ended) r = "unk:git failed while reading " d
    else if (rc == "1") r = "unk:HEAD is detached in " d
    else if (rc != "0" || head == "") r = "unk:git could not name the branch checked out in " d
    else if (tolower(pd) == "matching") r = "main:push.default=matching in " d " pushes every matching branch, main included"
    else if (rp != "") r = "unk:" d " has remote.*.push refspecs configured"
    else if (fp_is_main(head)) r = "main:" d " has " head " checked out and the push names no other branch"
    else if (fp_is_main(up)) r = "main:" head " in " d " tracks " up ", so a push with no refspec can land on it"
    else r = "ok"
    FPH[d] = r
    return r
}

# The words typed after a zsh push alias stand in for its expansion.
# $(git_current_branch) in gpsup and ggpush is the current branch: HEAD.
function fp_alias(w) {
    if (w == "gp") return "push"
    if (w == "gpd") return "push --dry-run"
    if (w == "gpu") return "push upstream"
    if (w == "gpv") return "push --verbose"
    if (w == "gpsup") return "push --set-upstream origin HEAD"
    if (w == "ggpush") return "push origin HEAD"
    if (w == "gpf") return "push --force-with-lease --force-if-includes"
    if (w == "gpsupf") return "push --set-upstream origin HEAD --force-with-lease --force-if-includes"
    return ""
}

# Crude, for text the scanner does not parse as commands. A push word plus
# anything that looks like a force: deny, and say why.
function fp_crude(t) {
    gsub(/["'\\]/, "", t)
    if (t ~ /(^|[^A-Za-z0-9_.-])(gpf|gpsupf)([ \t\n;&|)]|$)/)
        return "the lease alias gpf or gpsupf (a force push) sits where validate-bash cannot parse it"
    if (t !~ /(^|[^A-Za-z0-9_.-])(push|gp|gpu|gpv|gpsup|ggpush)([ \t\n;&|)]|$)/) return ""
    if (t ~ /(^|[ \t\n])(-[A-Za-z0-9]*f[A-Za-z0-9]*|--f[a-z-]*|--m[a-z]*)([ \t\n=;&|)]|$)/ || t ~ /(^|[ \t\n])\+[^ \t\n]/)
        return "a git push that may force (a force flag, --mirror or a +refspec) sits where validate-bash cannot parse it"
    return ""
}

# Push arguments TV[1..tn] (TX[i] = 1: an expansion, value unknown). Needs the
# candidate directories FC[1..FCN], the -C paths GC[1..GCN] and FPCFG.
function fp_push(tn,    i, v, name, eq, c, ch, fF, fL, fI, mirror, all, endopt, repoopt, npos, nref, r, src, dst, cur, d, m, h, s, fX, pendX) {
    fF = 0; fL = 0; fI = 0; mirror = 0; all = 0; endopt = 0; repoopt = 0; npos = 0; nref = 0
    fX = 0; pendX = ""; FPXONLY = 0; FPXW = ""
    for (i = 1; i <= tn; i++) {
        v = TV[i]
        if (TX[i]) { 
            # A47: before --, an expansion in the repository slot, or with a plain word after
            # it, may be a force flag (git push $F origin main).
            if (!endopt) { if (npos == 0 && !repoopt) { fX = 1; FPXW = TW[i] } else if (pendX == "") pendX = TW[i] }
            npos++; if (npos > 1 || repoopt) { nref++; RF[nref] = ""; RX[nref] = 1 }; continue }
        if (!endopt && v == "--") { endopt = 1; continue }
        if (!endopt && substr(v, 1, 2) == "--") {
            name = substr(v, 3); eq = index(name, "=")
            if (eq) name = substr(name, 1, eq - 1)
            if (name == "no-force") fF = 0
            else if (name == "no-force-with-lease") fL = 0
            else if (name == "no-force-if-includes") fI = 0
            else if (name != "" && index("force", name) == 1) fF = 1
            else if (length(name) > 5 && index("force-with-lease", name) == 1) fL = 1
            else if (length(name) > 5 && index("force-if-includes", name) == 1) fI = 1
            else if (name != "" && index("mirror", name) == 1) mirror = 1
            else if (length(name) >= 2 && (index("all", name) == 1 || index("branches", name) == 1)) all = 1
            else if (!eq && length(name) >= 3 && (index("repo", name) == 1 || index("receive-pack", name) == 1 || index("exec", name) == 1 || index("push-option", name) == 1 || index("recurse-submodules", name) == 1)) {
                if (index("repo", name) == 1) repoopt = 1
                i++
            }
            else if (eq && length(name) >= 3 && index("repo", name) == 1) repoopt = 1
            continue
        }
        if (!endopt && v ~ /^-./) {
            for (c = 2; c <= length(v); c++) {
                ch = substr(v, c, 1)
                if (ch == "f") fF = 1
                else if (ch == "o") { if (c == length(v)) i++; break }
            }
            continue
        }
        npos++
        if (npos == 1 && !repoopt) continue            # the repository
        nref++; RF[nref] = v; RX[nref] = 0
    }
    if (!fX && pendX != "") for (r = 1; r <= nref; r++) if (!RX[r]) { fX = 1; FPXW = pendX; break }   # with a plain refspec
    if (mirror) return fp_msg("--mirror force-pushes every ref, main included")
    if (fX && !(fF || fL || fI)) { FPXONLY = 1; fF = 1 }
    cur = 0
    for (r = 1; r <= nref; r++) {
        if (RX[r]) { if (fF || fL || fI) return fp_unk("a refspec is held in a variable or $(...)"); continue }
        v = RF[r]
        if (substr(v, 1, 1) == "+") v = substr(v, 2)
        else if (!(fF || fL || fI)) continue
        if (v == ":") return fp_msg("the refspec " RF[r] " force-pushes every matching branch, main included")
        c = index(v, ":")
        src = c ? substr(v, 1, c - 1) : v
        dst = c ? substr(v, c + 1) : v
        if (dst == "") continue
        if (dst ~ /[*]/) return fp_msg("the glob refspec " RF[r] " can match main")
        if (dst == "HEAD" || dst == "@") cur = 1
        else if (fp_is_main(dst)) return fp_msg("the refspec " RF[r] " updates " dst)
    }
    if ((fF || fL || fI) && nref == 0) {
        if (all) return fp_msg("--all force-pushes every branch, main included")
        cur = 1
    }
    if (!cur) return ""
    if (FPCFG != "") return fp_unk(FPCFG)
    for (h = 1; h <= FCN; h++) {
        d = FC[h]
        for (m = 1; m <= GCN; m++) d = (GC[m] == "" ? "" : fp_join(d, GC[m]))
        s = fp_head(d)
        if (s ~ /^main:/) return fp_msg(substr(s, 6))
        if (s ~ /^unk:/) return fp_unk(substr(s, 5))
    }
    return ""
}

function fp_check(    k, j, n, a, w, v, gi, tn, b, s, t, ex, i) {
    FCN = 1; FC[1] = ENVIRON["CONV_CWD"]; FPCLEAN = 0
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n || EM ~ /probe/) continue
        w = unq(WR[k, j])
        # cd, pushd, popd: each new directory is one more candidate (see header).
        if (base(w) == "cd" || w == "pushd" || w == "popd") {
            for (a = j + 1; a <= n && WR[k, a] ~ /^-[A-Za-z]/; a++) ;
            if (w == "popd") FC[++FCN] = ""
            else if (a > n) FC[++FCN] = ENVIRON["HOME"]
            else { v = unq(WR[k, a]); FC[FCN + 1] = (v == "" || v == "-" ? "" : fp_join(FC[FCN], v)); FCN++ }
            continue
        }
        # A50: eval, sh -c and friends are re-read as commands by gd_main. eval of a
        # command substitution cannot be read (its text exists only at run time), so it
        # keeps the crude match.
        if (w == "eval" && !WQ[k, j]) {
            t = ""
            for (a = j + 1; a <= n; a++) t = t " " WR[k, a]
            if (t ~ /\$\(|`/) { s = fp_crude(t); if (s != "") return fp_msg(s " (inside eval of a substitution)") }
        }
        b = base(w)
        # Find git: the command word, or any word after a hard modifier (sudo -u x git).
        gi = 0; tn = 0; FPCFG = ""
        if (base(w) == "git") gi = j
        else if (!WQ[k, j] && WR[k, j] !~ /^\\/ && fp_alias(WR[k, j]) != "") {
            tn = split(fp_alias(WR[k, j]), ex, " ")
            if (ex[1] == "push") {
                for (i = 2; i <= tn; i++) { TV[i - 1] = ex[i]; TX[i - 1] = 0 }
                tn--
                for (a = j + 1; a <= n; a++) { tn++; TV[tn] = unq(WR[k, a]); TW[tn] = WR[k, a]; TX[tn] = (TV[tn] == "" && WR[k, a] != "") }
                GCN = 0
                for (a = 1; a < j; a++) if (WR[k, a] ~ /^GIT_[A-Z_]*=/) FPCFG = "a GIT_ variable is set on the command"
                s = fp_push(tn)
                if (s != "") return fp_xnote(s)
                FPCLEAN += fp_clean(tn)   # A123
                continue
            }
        }
        else if (EM ~ /hard:|envopt/) { for (a = j + 1; a <= n; a++) if (base(unq(WR[k, a])) == "git") { gi = a; break } }
        if (!gi) continue
        for (a = 1; a < gi; a++) if (WR[k, a] ~ /^GIT_[A-Z_]*=/) FPCFG = "a GIT_ variable is set on the command"
        # git's own options before the subcommand.
        GCN = 0; a = gi + 1
        while (a <= n) {
            v = unq(WR[k, a])
            if (v == "-C") { GC[++GCN] = unq(WR[k, a + 1]); a += 2; continue }
            if (v == "-c") {
                if (tolower(unq(WR[k, a + 1])) ~ /^(push|remote|branch|include|includeif)\./ || unq(WR[k, a + 1]) == "")
                    FPCFG = "git -c changes push, remote or branch config"
                a += 2; continue
            }
            if (v ~ /^--(git-dir|work-tree|namespace|config-env)(=|$)/) {
                FPCFG = "git " v " changes which repository or config git reads"
                if (v !~ /=/) a++
                a++; continue
            }
            if (v == "--super-prefix" || v == "--attr-source") { a += 2; continue }
            if (v ~ /^-/) { a++; continue }
            break
        }
        if (a > n || unq(WR[k, a]) != "push") continue
        tn = 0
        for (a = a + 1; a <= n; a++) { tn++; TV[tn] = unq(WR[k, a]); TW[tn] = WR[k, a]; TX[tn] = (TV[tn] == "" && WR[k, a] != "") }
        s = fp_push(tn)
        if (s != "") return fp_xnote(s)
        FPCLEAN += fp_clean(tn)   # A123
    }
    # A47, then A50: here-documents and here-strings read by a shell, and backticks,
    # are re-read as commands by gd_main, with every rule.
    # W-20260929-A53: a function definition alone no longer sends the whole text
    # to the crude match, because the scanner does record a function body's
    # commands and the loop above has read them. It still does when some word is
    # push or a push alias (git push "$@" in a body, or a call like p git push -f),
    # since then the flags may arrive through the function's arguments.
    if (UNSURE_NF != "" || (UNSURE != "" && fp_push_word() > FPCLEAN)) {
        s = fp_crude(S)
        if (s != "") return fp_msg(s " (the command has a " (UNSURE_NF != "" ? UNSURE_NF : UNSURE) ")")
    }
    return ""
}

# A47: when the only possible force is a variable in a flag position, say so.
function fp_xnote(s) {
    if (!FPXONLY) return s
    return s " (" FPXW " is held in a variable and sits where a force flag can go; if it is not a flag, put -- before the repository)"
}

# The shell that reads command k's here-document: k itself, or a later command in
# the same pipeline. "" when no shell reads it.
function fp_shell_of(k,    c, b) {
    for (c = k; c <= NC; c++) {
        b = base(unq(WR[c, eff(c)]))
        if (b == "bash" || b == "sh" || b == "zsh" || b == "dash" || b == "ksh") return b
        if ((b == "source" || b == ".") && gd_stdin_arg(c)) return b " /dev/stdin"   # A118
        if (CSA[c] != "|" && CSA[c] != "|&") return ""
    }
    return ""
}

# How many recorded words, quotes removed, are push or a push alias (A123: a count, so
# fp_check can compare it with the pushes it read in full).
function fp_push_word(    k, a, w, c) {
    c = 0
    for (k = 1; k <= NC; k++)
        for (a = 1; a <= CNW[k]; a++) {
            w = WR[k, a]; gsub(/["'\\]/, "", w)
            if (w == "push" || fp_alias(w) != "") c++
        }
    return c
}
# A123: 1 when push arguments TV[1..tn] held no expansion, so fp_push read them all
function fp_clean(tn,    i) { for (i = 1; i <= tn; i++) if (TX[i]) return 0; return 1 }

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
            if (unq(w) == "--help" || unq(w) == "-h") return     # prints usage, starts nothing
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
        # engage #1090: `command -v X` / `command -V X` only look X up (eff marks it probe),
        # as the other rules already honour; `command X` and `command -p X` still launch.
        if (j > n || EM ~ /probe/) continue
        ovk = ov
        for (a = 1; a < j; a++) if (WR[k, a] ~ /^PJ_WORKERS_CONTROL=/) {
            w = unq(WR[k, a]); sub(/^PJ_WORKERS_CONTROL=/, "", w)
            if (w ~ /^W-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[A-Z][0-9]+$/) ovk = w   # no {8}: mawk lacks intervals
        }
        w = unq(WR[k, j]); b = base(w)
        if (ctx == "pane") {
            lab = pj_pane_claude(k, j)
            if (lab != "") { pj_hit("DENY", pj_msg_worker("`" lab "` " (where != "" ? where : "typed into a pane") ", which starts plain claude, not a pj session"), ovk); if (PV == "DENY") return }
        }
        # W-20260929-A36 (red-team H6): a claude started from the Bash tool itself runs outside
        # herdr, the pj rules and both session caps. Info forms (--version, mcp, agents ...) pass.
        if (ctx == "bash") {
            lab = pj_pane_claude(k, j)
            if (lab != "") { pj_hit("DENY", pj_msg_worker("`" lab "` started from the Bash tool" (where != "" ? " (" where ")" : "") " runs outside herdr, the pj rules and both session caps (W-20260929-A36)"), ovk); if (PV == "DENY") return }
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

# ------------------------------------------------------------------ guard: nested text
# W-20260929-A50 (D-20260929-A24, option B). The text of bash/sh/zsh/dash/ksh -c, eval,
# backticks, a here-document or here-string read by a shell, and echo/printf piped into a
# shell, is parsed again as commands and every guard rule runs on it, the way the delete
# guard's lexer and enforce-pj-workers already do. Until then guard mode guessed from the
# words of those texts, which denied harmless text (bash -c "echo '...force...'") and
# missed echo '...' | bash. eval of a command substitution still gets fp_check's crude
# match: its text exists only at run time. At most 64 texts; more is denied.

function gd_enqueue(t, where) {
    if (QN >= 64) { GDOVER = 1; return }
    QN++; QT[QN] = t; QW[QN] = where
}
function gd_nested(pw,    k, j, n, a, w, b, b2, t, i, pre) {
    pre = (pw != "" ? pw ", then " : "")
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j <= n) {
            b = base(unq(WR[k, j]))
            if (b ~ /^(bash|sh|zsh|dash|ksh)$/) {
                for (a = j + 1; a <= n; a++) {
                    w = unq(WR[k, a])
                    if (w ~ /^-[a-zA-Z]*c[a-zA-Z]*$/) { if (a < n) gd_enqueue(pj_dq(WR[k, a + 1]), pre b " -c"); break }
                    if (w !~ /^[-+]/) break
                }
            } else if (b == "eval" && !WQ[k, j]) {
                t = ""; for (a = j + 1; a <= n; a++) t = t (a > j + 1 ? " " : "") pj_dq(WR[k, a])
                gd_enqueue(t, pre "eval")
            } else if ((b == "echo" || b == "printf" || b == "print") && k < NC && (CSA[k] == "|" || CSA[k] == "|&") && (b2 = fp_shell_of(k + 1)) != "") {
                t = ""
                for (a = j + 1; a <= n; a++) {
                    w = unq(WR[k, a])
                    if (b != "printf" && t == "" && w ~ /^-[neE]+$/) continue
                    t = t (t != "" ? " " : "") pj_dq(WR[k, a])
                }
                gd_enqueue(t, pre b " piped to " b2)
            }
        }
        if (HBODY[k] != "" && (b2 = fp_shell_of(k)) != "") gd_enqueue(HBODY[k], pre "a here-document fed to " b2)
        # W-20260929-A118: script runs its command; source/. or a shell given <(...) runs
        # what that body prints; an unquoted heredoc runs every $(...) and backtick in it.
        if (j <= n && b == "script") gd_script(k, j, n, pre)
        if (j <= n && PSB[k] != "" && (b == "source" || b == "." || b ~ /^(bash|sh|zsh|dash|ksh)$/)) gd_enqueue(PSB[k] " | sh", pre b " <(...)")
        if (UHB[k] != "") gd_subs(UHB[k], pre "an unquoted here-document")
    }
    for (i = 1; i <= BTN; i++) gd_enqueue(BT[i], pre "backticks")
}
function gd_stdin_arg(k,    a) {
    for (a = eff(k) + 1; a <= CNW[k]; a++) if (unq(WR[k, a]) ~ /^(\/dev\/stdin|\/dev\/fd\/0|\/proc\/self\/fd\/0|-)$/) return 1
    return 0
}
function gd_script(k, j, n, pre,    a, w, t) {   # BSD: script [-adkpqr] [-F pipe] [-t n] [file [cmd ...]]; Linux: -c CMD
    for (a = j + 1; a <= n; a++) {
        w = unq(WR[k, a])
        if (w == "-c" || w == "--command") { if (a < n) gd_enqueue(pj_dq(WR[k, a + 1]), pre "script -c"); return }
        if (w ~ /^--command=/) { gd_enqueue(substr(w, 11), pre "script -c"); return }
        if (w == "-F" || w == "-t" || w == "-T" || w == "-I" || w == "-O" || w == "-B" || w == "-E") { a++; continue }
        if (w ~ /^-/) continue
        break
    }
    t = ""
    for (a++; a <= n; a++) t = t (t != "" ? " " : "") pj_dq(WR[k, a])   # the words after the file
    if (t != "") gd_enqueue(t, pre "script")
}
function gd_subs(t, where,    i, n, c, d, st) {   # every $(...) and backtick span in t
    n = length(t); i = 1
    while (i <= n) {
        c = substr(t, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "$" && substr(t, i + 1, 1) == "(" && substr(t, i + 2, 1) != "(") {
            d = 1; st = i + 2; i += 2
            while (i <= n && d > 0) { c = substr(t, i, 1); if (c == "(") d++; else if (c == ")") d--; i++ }
            gd_enqueue(substr(t, st, i - 1 - st), where); continue
        }
        if (c == "`") {
            st = i + 1; i++
            while (i <= n && substr(t, i, 1) != "`") i++
            gd_enqueue(substr(t, st, i - st), where); i++; continue
        }
        i++
    }
}
function gd_main(    qi) {
    QN = 1; QT[1] = S; QW[1] = ""; GDOVER = 0
    for (qi = 1; qi <= QN; qi++) {
        if (qi > 1) { pj_load(QT[qi]); parse_list(1, "", 0, "^"); if (HDN) unsure("here-document with no body") }
        guard_check()
        if (V["guard"] == "DENY") { if (QW[qi] != "") M["guard"] = M["guard"] " (read inside " QW[qi] ")"; return }
        gd_nested(QW[qi])
    }
    if (GDOVER) verdict("guard", "DENY", "validate-bash: more than 64 nested shell texts (-c, eval, backticks, heredocs) to read; refusing rather than guessing")
}

function pj_load(t) { S = t; N = split(S, C, ""); P = 1; NC = 0; HDN = 0; BG = 0; UNSURE = ""; UNSURE_NF = ""; SUBSH = 0; BTN = 0; split("", HBODY); split("", UHB); split("", PSB); CASEOPEN = 0; CASEPAT = 0; CASEIN = 0 }

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

# ------------------------------------------------------------------ install
# Used by warn-install-telemetry.sh (CONV_MODE=install), #1110, engage-main Q13.
# ADVISORY: never ALLOW/DENY. Prints one line per install of a new tool it reads,
#   HIT<TAB><manager><TAB><tool>[, <tool>...]
# and nothing at all when there is none. It reads the commands the scanner records,
# plus every text guard mode reads as commands (gd_nested: $(...) and backtick
# bodies, sh/bash/zsh -c, eval, text piped or fed to a shell), so prose inside
# quotes, heredocs and comments stays quiet and `zsh -ic 'brew install x'` does not.
#
# Fires on: brew install/instal (and --cask); npm i/install/add -g (--global,
# --location=global); pnpm add/install/i -g; bun add/install/i -g; uv tool install;
# pipx install; cargo install; go install <module>@<version>; gem install;
# mas install; curl/wget piped into a shell, bash <(curl ...), sh -c "$(curl ...)".
# Quiet on: a project dependency (no -g), brew reinstall/upgrade, uv tool install
# --reinstall/--upgrade, cargo install --list, go install of a local path, anything
# with --help, -h or --dry-run, uninstalls, and an install with no tool named.
# NOT read: a command run on another machine (ssh host '...'), a script file.

function in_hit(m, t,    i) {
    gsub(/[\t\n]/, " ", t)
    for (i = 1; i <= INN; i++) if (INM[i] == m && INT[i] == t) return
    INN++; INM[INN] = m; INT[INN] = t
}
# Does option o of manager m take the next word as its value? (an attached
# --opt=value is one word and needs nothing)
function in_val(m, o) {
    if (m == "uv") return o ~ /^(-p|--python|-w|--with|--from|--with-requirements|--with-editable|--index|--index-url|--extra-index-url|--default-index|-f|--find-links|-c|--constraints|--overrides|--exclude-newer|--python-preference|--directory|--project|--config-file|--cache-dir|--color|--index-strategy|--keyring-provider|--resolution|--prerelease|--link-mode|--refresh-package|--reinstall-package|--upgrade-package|-P|--build-constraints|--no-build-package|--no-binary-package|--only-binary-package)$/
    if (m == "pipx") return o ~ /^(--python|--pip-args|--suffix|--index-url|-i|--preinstall|--global-dir)$/
    if (m == "cargo") return o ~ /^(--version|--vers|--git|--branch|--tag|--rev|--path|--root|--registry|--index|-F|--features|--target|--target-dir|--profile|-j|--jobs|--bin|--example|--config|-Z|--color)$/
    if (m == "gem") return o ~ /^(-v|--version|-i|--install-dir|-n|--bindir|-s|--source|-P|--trust-policy|--platform|-g|--file)$/
    if (m == "npm" || m == "pnpm" || m == "bun") return o ~ /^(--prefix|--registry|--location|-C|--dir|--filter|--store-dir|--cwd|--cache-dir|--config|--workspace|-w)$/
    if (m == "brew") return o ~ /^(--appdir|--fontdir|--colorpickerdir|--prefpanedir|--qlplugindir|--mdimporterdir|--dictionarydir|--input-methoddir|--servicedir|--audio-unit-plugindir|--vst-plugindir|--vst3-plugindir|--screen-saverdir|--language|--cc)$/
    return 0
}
# The tool words of command k from word s on, joined by ", ". Sets INOPT to the
# options seen, space-separated and padded, so a caller can test " -g "; an option
# that takes a value is stored as --opt=value.
function in_names(k, s, m,    a, n, w, out) {
    INOPT = " "; out = ""; n = CNW[k]
    for (a = s; a <= n; a++) {
        w = unq(WR[k, a])
        if (w == "" && WR[k, a] ~ /^-/) w = WR[k, a]
        if (w ~ /^-/) {
            if (w !~ /=/ && in_val(m, w) && a < n) { a++; w = w "=" unq(WR[k, a]) }   # one word: --opt=value
            INOPT = INOPT w " "
            continue
        }
        if (w == "") w = WR[k, a]          # an expansion: name it as written
        out = out (out != "" ? ", " : "") w
    }
    return out
}
function in_quiet() { return INOPT ~ / (--help|-h|--dry-run)( |=)/ }
function in_global() { return INOPT ~ / (-g|--global|--location=global) / }
function in_url(k, j,    a, n, w) {
    n = CNW[k]
    for (a = j + 1; a <= n; a++) {
        w = unq(WR[k, a])
        if (w ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) { sub(/[?#].*/, "", w); return w }
    }
    return "an install script"
}
# A shell given the piped text: no -c and no script file, or `-` / -s. (-c takes its
# command as the next word, which reads as a script file here: either way the pipe is
# not what runs.)
function in_pipesh(k,    c, j, n, a, w) {
    for (c = k + 1; c <= NC; c++) {
        j = eff(c); n = CNW[c]
        if (j > n) return 0
        w = base(unq(WR[c, j]))
        if (w ~ /^(bash|sh|zsh|dash|ksh)$/) {
            for (a = j + 1; a <= n; a++) {
                w = unq(WR[c, a])
                if (w == "-" || w == "--") return 1
                if (w !~ /^[-+]/) return 0          # a script file, or -c's command text
            }
            return 1
        }
        if (CSA[c - 1] != "|" && CSA[c - 1] != "|&") return 0
        if (CSA[c] != "|" && CSA[c] != "|&") return 0
    }
    return 0
}
function in_one(k, j,    n, m, i, s, t, w) {
    n = CNW[k]; m = base(unq(WR[k, j]))
    if (m == "brew") {
        for (i = j + 1; i <= n && isopt(k, i); i++) ;
        if (i > n) return
        s = unq(WR[k, i])
        if (s != "install" && s != "instal") return
        t = in_names(k, i + 1, m)
        if (t == "" && EM ~ /hard:xargs/) t = "the names xargs reads"
        if (in_quiet() || t == "") return
        in_hit((INOPT ~ / --cask / ? "brew --cask" : "brew"), t); return
    }
    if (m == "npm" || m == "pnpm" || m == "bun") {
        for (i = j + 1; i <= n && isopt(k, i); i++) ;
        if (i > n) return
        s = unq(WR[k, i])
        if (m == "npm" && s !~ /^(i|in|ins|inst|insta|instal|install|isnt|isnta|isntal|isntall|add)$/) return
        if (m != "npm" && s != "add" && s != "install" && s != "i") return
        t = in_names(k, j + 1, m)
        sub("^" s "(, |$)", "", t)
        if (!in_global() || in_quiet()) return
        in_hit(m " -g", (t == "" ? "the current folder" : t)); return
    }
    if (m == "uv") {
        for (i = j + 1; i <= n && isopt(k, i); i++) ;
        if (i + 1 > n || unq(WR[k, i]) != "tool" || unq(WR[k, i + 1]) != "install") return
        t = in_names(k, i + 2, m)
        if (in_quiet() || t == "" || INOPT ~ / (--reinstall|--upgrade|-U)( |=)/) return
        in_hit("uv tool", t); return
    }
    if (m == "pipx" || m == "cargo" || m == "gem" || m == "mas") {
        for (i = j + 1; i <= n && isopt(k, i); i++) ;
        if (i > n || unq(WR[k, i]) != "install") return
        t = in_names(k, i + 1, m)
        if (in_quiet()) return
        if (t == "" && m == "cargo" && match(INOPT, / --(git|path)=[^ ]+/)) { t = substr(INOPT, RSTART + 1, RLENGTH - 1); sub(/^[^=]*=/, "", t) }
        if (t == "") return
        in_hit(m, t); return
    }
    if (m == "go") {
        for (i = j + 1; i <= n && isopt(k, i); i++) ;
        if (i > n || unq(WR[k, i]) != "install") return
        t = ""
        for (i++; i <= n; i++) { w = unq(WR[k, i]); if (w !~ /^-/ && w ~ /@/) t = t (t != "" ? ", " : "") w }
        if (t != "") in_hit("go", t)
        return
    }
    if ((m == "curl" || m == "wget") && (CSA[k] == "|" || CSA[k] == "|&") && in_pipesh(k)) {
        in_hit("a curl | sh installer", in_url(k, j)); return
    }
    # sh -c "$(curl ...)" and eval "$(curl ...)": the shell runs what curl fetched.
    if (m ~ /^(bash|sh|zsh|dash|ksh|eval)$/) {
        for (i = j + 1; i <= n; i++) {
            w = WR[k, i]
            if (w ~ /^"?\$\([ \t]*(curl|wget)[ \t]/) { in_hit("a curl | sh installer", (match(w, /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ \t")?#]+/) ? substr(w, RSTART, RLENGTH) : "an install script")); return }
        }
    }
}
function install_check(    k, j, n, a, b) {
    for (k = 1; k <= NC; k++) {
        j = eff(k); n = CNW[k]
        if (j > n || EM ~ /probe/) continue
        if (EM !~ /hard:|envopt/) { in_one(k, j); continue }
        # After sudo -u x, xargs, command ... eff cannot be sure which word is the
        # command (guard mode reads brew the same way), so take the first one that is
        # a manager, a fetcher or a shell. A shell found this way is read as text too.
        for (a = j; a <= n; a++) {
            b = base(unq(WR[k, a]))
            if (b ~ /^(brew|npm|pnpm|bun|uv|pipx|cargo|go|gem|mas|curl|wget|bash|sh|zsh|dash|ksh|eval)$/) break
        }
        if (a > n) continue
        in_one(k, a)
        if (a > j && b ~ /^(bash|sh|zsh|dash|ksh)$/) {
            for (j = a + 1; j <= n; j++) {
                if (unq(WR[k, j]) ~ /^-[a-zA-Z]*c[a-zA-Z]*$/) { if (j < n) gd_enqueue(pj_dq(WR[k, j + 1]), b " -c"); break }
                if (unq(WR[k, j]) !~ /^[-+]/) break
            }
        }
    }
}
function install_main(    qi, i) {
    QN = 1; QT[1] = S; QW[1] = ""; GDOVER = 0; INN = 0
    for (qi = 1; qi <= QN; qi++) {
        if (qi > 1) { pj_load(QT[qi]); parse_list(1, "", 0, "^") }
        install_check()
        gd_nested(QW[qi])
    }
    for (i = 1; i <= INN; i++) print "HIT\t" INM[i] "\t" INT[i]
}

# ------------------------------------------------------------------ main

{ S = (NR > 1 ? S "\n" : "") $0 }

END {
    N = split(S, C, "")
    mode = ENVIRON["CONV_MODE"]
    P = 1; NC = 0; HDN = 0; BG = 0; UNSURE = ""; UNSURE_NF = ""; SUBSH = 0; BTN = 0; split("", HBODY); split("", UHB); split("", PSB); CASEOPEN = 0; CASEPAT = 0; CASEIN = 0
    REC_NESTED = (mode == "guard" || mode == "pjw" || mode == "install")   # only these look inside $(...) and backticks
    if (mode == "pjw") pjw_main()
    parse_list(1, "", 0, "^")
    if (HDN) unsure("here-document with no body")
    if (mode == "install") { install_main(); exit 0 }   # advisory: HIT lines only
    if (mode == "guard" || mode == "builtin" || mode == "reset") {   # deny-only modes: never compose
        if (mode == "guard") gd_main(); else if (mode == "builtin") builtin_check(); else reset_check()
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
