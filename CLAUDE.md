Default branch is `master`.
Use `uv run python3` instead of calling `python3` directly.
Shell has `NULL_GLOB` + `nonomatch` — use `find -print` (not `ls glob*`) for file existence checks.
Before editing a file, run `grep -cP '\t' <file>` to detect tab indentation — match exactly or the Edit tool will fail.
rm is a shell function wrapper that routes deletions to trash — it is never active in Bash tool calls (non-interactive shells skip .zshrc entirely), so any rm here hits /bin/rm directly and deletes permanently; always get explicit user confirmation before deleting files.
