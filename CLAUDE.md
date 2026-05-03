Default branch is `master`.
Use `uv run python3` instead of calling `python3` directly.
Shell has `NULL_GLOB` + `nonomatch` — use `find -print` (not `ls glob*`) for file existence checks.
Before editing a file, run `grep -cP '\t' <file>` to detect tab indentation — match exactly or the Edit tool will fail.
