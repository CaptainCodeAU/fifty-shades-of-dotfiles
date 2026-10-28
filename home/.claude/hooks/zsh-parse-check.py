# /// script
# requires-python = ">=3.11"
# dependencies = ["tree-sitter>=0.23", "tree-sitter-bash>=0.23"]
# ///
"""zsh-parse-check.py -- does a bash parser fail on this command? Helper of enforce-zsh-parse.sh.

Reads the command on stdin and prints {"error": true|false, "where": "command" | "-c script" | null}.
Claude Code also parses the script of `sh|bash|zsh|dash -c '...'` (claude-code #99249), so each
such script is parsed too, its quotes undone the way the shell undoes them.
"""
import json
import re
import sys

import tree_sitter_bash as tsb
from tree_sitter import Language, Parser

SHELLS = {"sh", "bash", "zsh", "dash"}
LAUNCHERS = {"env", "command", "exec", "nice", "nohup", "timeout", "sudo"}
PARSER = Parser(Language(tsb.language()))


def unquote(node) -> str:
    raw = node.text.decode()
    if node.type == "raw_string":  # '...': taken as it is
        return raw[1:-1]
    if node.type == "string":  # "...": \$ \` \" \\ lose their backslash
        return re.sub(r'\\([$`"\\])', r"\1", raw[1:-1])
    if node.type == "ansi_c_string":  # $'...'
        return raw[2:-1]
    return raw


def inline_scripts(node):
    """Yield the text of each `<shell> -c <script>` in the tree."""
    if node.type == "command":
        name = node.child_by_field_name("name")
        args = [c for c in node.children if c.type not in ("command_name", "variable_assignment")]
        words = ([name] if name is not None else []) + args
        base = [w.text.decode().rsplit("/", 1)[-1] for w in words]
        start = None
        if base and base[0] in SHELLS:
            start = 1
        elif base and base[0] in LAUNCHERS:  # env PATH=x zsh -c ..., sudo bash -c ...
            start = next((k + 1 for k, b in enumerate(base[1:], 1) if b in SHELLS), None)
        if start is not None:
            for i, w in enumerate(words[start:-1], start):
                t = w.text.decode()
                if t.startswith("-") and not t.startswith("--") and "c" in t[1:]:
                    yield unquote(words[i + 1])
                    break
    for c in node.children:
        yield from inline_scripts(c)


root = PARSER.parse(sys.stdin.read().encode()).root_node
where = "command" if root.has_error else None
if where is None:
    for script in inline_scripts(root):
        if PARSER.parse(script.encode()).root_node.has_error:
            where = "-c script"
            break
print(json.dumps({"error": where is not None, "where": where}))
