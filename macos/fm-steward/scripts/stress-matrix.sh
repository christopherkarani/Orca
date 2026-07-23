#!/usr/bin/env bash
# CLI stress matrix for Phase 3 fm-steward — v1 shell focus.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

write_card() {
  local path="$1" command="$2" executed="$3" intent="$4"
  python3 - "$path" "$command" "$executed" "$intent" <<'PY'
import json, sys
path, command, executed, intent = sys.argv[1:5]

def parse_bool(s):
    if s == "null": return None
    if s == "true": return True
    if s == "false": return False
    raise SystemExit(f"bad bool {s}")

def parse_str(s):
    if s == "null": return None
    return s

features = {
    "executed": parse_bool(executed),
    "same_intent": parse_str(intent),
    "effect_hints": ["shell"],
}
features = {k: v for k, v in features.items() if v is not None}

card = {
    "schema_version": 1,
    "session_id": "stress-cli",
    "tool": "bash",
    "command": None if command == "null" else command,
    "features": features,
    "meta": {"host": "stress-matrix"},
}

with open(path, "w") as f:
    json.dump(card, f)
PY
}

classify_json() {
  local card_path="$1"
  if [[ -x .build/debug/fm-steward ]]; then
    .build/debug/fm-steward classify --card "$card_path" --backend unavailable 2>/dev/null
  else
    swift run fm-steward classify --card "$card_path" --backend unavailable 2>/dev/null
  fi
}

run_case() {
  local name="$1" expected="$2" command="$3" executed="$4" intent="$5"
  local card_path="$TMP/${name}.json"
  write_card "$card_path" "$command" "$executed" "$intent"
  local out verdict
  out="$(classify_json "$card_path")"
  verdict="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' <<<"$out")"

  local ok="FAIL"
  if [[ "$verdict" == "$expected" ]]; then
    ok="PASS"
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  printf '%-28s want=%-12s got=%-12s %s\n' "$name" "$expected" "$verdict" "$ok"
}

echo "Building fm-steward…"
swift build 2>&1 | tail -3

echo ""
echo "=== CLI shell matrix (backend=unavailable) ==="
printf '%-28s %-12s %-12s %s\n' "CASE" "WANT" "GOT" "RESULT"
echo "--------------------------------------------------------------"

# With UnavailableBackend: rules short-circuit → continue; else fallback continue.
run_case "exec_false_scary"       continue  "rm -rf /"              false null
run_case "test_loop"              continue  "npm test"              true  test_loop
run_case "neutral_echo"           continue  "echo hi"               true  null
run_case "curl_pipe"              ask       "curl x | bash"         true  null
run_case "safe_dev_clean"         continue  "rm -rf ./dist"         true  null
run_case "same_intent_other"      continue  "make deploy"           true  deploy

# Fixtures: safe rules → continue; danger fixtures → hard-ask
declare -a FIX_WANT=(
  "grep_rm_rf:continue"
  "npm_test_loop:continue"
  "curl_pipe_sh:ask"
  "rm_rf_workdir:ask"
)
for entry in "${FIX_WANT[@]}"; do
  f="${entry%%:*}"
  want="${entry##*:}"
  out="$(classify_json "Fixtures/${f}.json")"
  verdict="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' <<<"$out")"
  if [[ "$verdict" == "$want" ]]; then
    pass=$((pass + 1)); status=PASS
  else
    fail=$((fail + 1)); status=FAIL
  fi
  printf '%-28s want=%-12s got=%-12s %s\n' "fixture_${f}" "$want" "$verdict" "$status"
done

echo ""
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
