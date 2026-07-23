#!/usr/bin/env bash
# Demo bar for Phase 3 fm-steward — v1 shell fixtures.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE_FLAG="--human"
if [[ "${1:-}" == "--json" ]]; then
  MODE_FLAG="--json"
fi

run_one() {
  local card="$1"
  local label="$2"
  local extra=("${@:3}")
  echo "======== ${label} (${card}) ========"
  swift run fm-steward classify --card "Fixtures/${card}" ${MODE_FLAG} "${extra[@]}"
  echo
}

echo "fm-steward demo (v1 shell focus; rules + live FM residual)"
echo "Package: ${ROOT}"
echo

run_one "grep_rm_rf.json" "non-executed grep → continue (rules)" --backend unavailable
run_one "npm_test_loop.json" "test loop → continue (rules)" --backend unavailable
run_one "curl_pipe_sh.json" "curl|bash danger → hard-ask (rules)" --backend unavailable
run_one "rm_rf_workdir.json" "rm -rf ~/Documents… → hard-ask (rules)" --backend unavailable

echo "Done. (W4 hook wiring NOT done; email bulk/VIP out of v1; Linux skips FM.)"
