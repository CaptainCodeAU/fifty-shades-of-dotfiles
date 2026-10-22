#!/usr/bin/env bash
# run-selftests.sh -- run every codebox hook's own selftest, from this folder's copy of the hooks
# (Gavin, dotfiles-main Q50: 1, 23 Oct 2026). Runs on the Mac and on codebox (Linux) alike; each
# selftest works in its own temp folders, so nothing live is touched. Prints one line per
# selftest and a total; exit 0 only when every selftest passed.
#
#   bash settings/codebox/hooks/tests/run-selftests.sh
#
# The two warners' selftests are Python; on a box without uv they run with plain python3.
D="$(cd "$(dirname "$0")/.." && pwd)"
pass=0 fail=0
run() { # run <label> <command...>
  local label="$1" out rc
  shift
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then pass=$((pass + 1)); printf '  ok   %s -- %s\n' "$label" "$(printf '%s\n' "$out" | grep -E 'passed|PASS|ok|arms' | tail -1)"
  else fail=$((fail + 1)); printf '  FAIL %s (exit %s) -- %s\n' "$label" "$rc" "$(printf '%s\n' "$out" | tail -3 | tr '\n' ' ')"; fi
}
for h in enforce-secret-probe.sh enforce-no-permanent-delete.sh enforce-no-reset-by-name.sh \
         enforce-no-worktree-discard.sh validate-bash.sh enforce-live-file-edit.sh warn-zsh-word-split.sh \
         warn-install-telemetry.sh; do
  if grep -q -- '--selftest' "$D/$h"; then run "$h --selftest" "$D/$h" --selftest; fi
done
if command -v uv >/dev/null 2>&1; then py=(uv run python3); else py=(python3); fi
run "warn-zsh-word-split-selftest" "${py[@]}" "$D/tests/warn-zsh-word-split-selftest" --hook "$D/warn-zsh-word-split.sh"
run "warn-install-telemetry-selftest" "${py[@]}" "$D/tests/warn-install-telemetry-selftest" --hook "$D/warn-install-telemetry.sh"
printf 'codebox hooks selftests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
