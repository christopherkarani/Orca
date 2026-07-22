#!/usr/bin/env bash
# CLI stress matrix for Phase 3 fm-steward.
# Generates edge-case risk cards, classifies each, prints a results table.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

write_card() {
  local path="$1" tool="$2" executed="$3" bulk="$4" vip="$5" intent="$6" count="$7" bulk_min="$8"
  python3 - "$path" "$tool" "$executed" "$bulk" "$vip" "$intent" "$count" "$bulk_min" <<'PY'
import json, sys
path, tool, executed, bulk, vip, intent, count, bulk_min = sys.argv[1:9]

def parse_bool(s):
    if s == "null": return None
    if s == "true": return True
    if s == "false": return False
    raise SystemExit(f"bad bool {s}")

def parse_int(s):
    if s == "null": return None
    return int(s)

def parse_str(s):
    if s == "null": return None
    return s

features = {
    "executed": parse_bool(executed),
    "bulk_outbound": parse_bool(bulk),
    "vip": parse_bool(vip),
    "same_intent": parse_str(intent),
    "recipient_count": parse_int(count),
    "paths": [],
    "effect_hints": ["external-message"],
}
features = {k: v for k, v in features.items() if v is not None}

card = {
    "schema_version": 1,
    "session_id": "stress-cli",
    "tool": tool,
    "command": "stress" if tool == "bash" else None,
    "features": features,
    "meta": {"host": "stress-matrix"},
}
bm = parse_int(bulk_min)
if bm is not None:
    card["thresholds"] = {"bulk_recipient_min": bm}

with open(path, "w") as f:
    json.dump(card, f)
PY
}

classify_json() {
  local card_path="$1"
  # Prefer release binary if present; fall back to swift run.
  if [[ -x .build/release/fm-steward ]]; then
    .build/release/fm-steward classify --card "$card_path" 2>/dev/null
  elif [[ -x .build/debug/fm-steward ]]; then
    .build/debug/fm-steward classify --card "$card_path" 2>/dev/null
  else
    swift run fm-steward classify --card "$card_path" 2>/dev/null
  fi
}

# name expected tool executed bulk vip intent count bulk_min
run_case() {
  local name="$1" expected="$2"
  shift 2
  local card_path="$TMP/${name}.json"
  write_card "$card_path" "$@"
  local out verdict explain fallback timed_out ok
  out="$(classify_json "$card_path")"
  verdict="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' <<<"$out")"
  explain="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("explain") or "")' <<<"$out")"
  fallback="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("fallback"))' <<<"$out")"
  timed_out="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("timed_out"))' <<<"$out")"

  ok="FAIL"
  if [[ "$verdict" == "$expected" ]]; then
    if [[ "$expected" == "ask" || "$expected" == "ask_sticky_candidate" ]]; then
      if [[ -n "$explain" ]]; then ok="PASS"; else ok="FAIL(empty-explain)"; fi
    else
      ok="PASS"
    fi
  fi

  if [[ "$ok" == "PASS" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  local has_explain
  if [[ -n "$explain" ]]; then has_explain=yes; else has_explain=no; fi
  printf '%-28s want=%-22s got=%-22s expl=%-3s fb=%-5s to=%-5s %s\n' \
    "$name" "$expected" "$verdict" "$has_explain" "$fallback" "$timed_out" "$ok"
}

echo "Building fm-steward…"
swift build 2>&1 | tail -3

echo ""
echo "=== CLI edge-case matrix ==="
printf '%-28s %-27s %-27s %-4s %-5s %-5s %s\n' \
  "CASE" "WANT" "GOT" "EXPL" "FB" "TO" "RESULT"
echo "--------------------------------------------------------------------------------------------------------------"

# name | expected | tool | executed | bulk | vip | intent | count | bulk_min
run_case "exec_false_vip"            continue              bash false false true null null null
run_case "exec_false_bulk"           continue              bash false true false null 99999 null
run_case "test_loop_beats_vip"       continue              bash true false true test_loop null null
run_case "test_loop_beats_bulk"      continue              send_email true true false test_loop 50000 null
run_case "vip_beats_bulk"            ask_sticky_candidate  send_email true true true null 50000 null
run_case "vip_only"                  ask_sticky_candidate  send_email true false true null null null
run_case "bulk_flag_low_count"       ask                   send_email true true false null 1 null
run_case "count_999"                 continue              send_email true false false null 999 null
run_case "count_1000"                ask                   send_email true false false null 1000 null
run_case "count_1001"                ask                   send_email true false false null 1001 null
run_case "custom_min_50_at"          ask                   send_email true false false null 50 50
run_case "custom_min_50_under"       continue              send_email true false false null 49 50
run_case "neutral_backend"           continue              bash true false false null null null
run_case "same_intent_other"         continue              bash true false false deploy null null
run_case "grep_style"                continue              bash false false false null null null
run_case "huge_bulk"                 ask                   send_email true true false null 999999999 null

# Stock fixtures
for f in bulk_email vip_email grep_rm_rf npm_test_loop; do
  out="$(classify_json "Fixtures/${f}.json")"
  verdict="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' <<<"$out")"
  case "$f" in
    bulk_email) want=ask ;;
    vip_email) want=ask_sticky_candidate ;;
    *) want=continue ;;
  esac
  if [[ "$verdict" == "$want" ]]; then
    pass=$((pass + 1)); status=PASS
  else
    fail=$((fail + 1)); status=FAIL
  fi
  printf '%-28s want=%-22s got=%-22s %s\n' "fixture_${f}" "$want" "$verdict" "$status"
done

echo ""
echo "=== Summary: ${pass} PASS, ${fail} FAIL ==="
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
