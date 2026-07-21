#!/usr/bin/env bash
# Adversarial OS FS sandbox e2e + evidence generator (P0-I-06 / M-11 / M-12 / F-1 / F-5).
#
# Primary proofs use the production apply path unit tests (real FS deny canaries,
# neighbor RW, control-root non-writable). Full `orca run` shell evaluation
# requires the Rust daemon; when the daemon is unavailable this script still
# records proofs from the Zig test surface.
#
# Honesty (M-1 / M-4 / S-GLO-09) — dual requirement for CTRL-ATTACH:
#   CTRL-ATTACH is claimed only when BOTH are green:
#     1. Real FS deny canaries (also set TEST-DENY + CTRL-NEIGHBOR)
#     2. Production forkApply*AndExec handshake for this OS:
#        - macOS: forkApplySeatbeltAndExec ... handshake...OK
#        - Linux: forkApplyLandlockAndExec ... handshake...OK
#   FS-deny-only (no production handshake) → TEST-DENY + CTRL-NEIGHBOR only;
#   attach_detail=zig_unit_fs_deny_without_production_handshake (not attach).
#   Handshake-only / prepare/probe greps → CTRL-PREPARE only — never attach.
#   Platform SKIP of real FS deny (no backend ABI on host) is honest non-attach.
#   Z-1: platform_skip only from the HOST OS deny SKIP line — never from the
#   opposite OS's always-SKIP, and never overwrite a more specific attach_detail.
#
# Usage:
#   ./scripts/os-sandbox-adversarial-e2e.sh [--case CASE_ID] [--binary PATH] [--out DIR] [--require-attach]
#   ORCA_E2E_SELFTEST=1 ./scripts/os-sandbox-adversarial-e2e.sh
#     Fixture-driven Z-1 / attach classify checks (no test-fast, no binary build).
#
# Exit 0 when full attach is proven, or partial when platform-skip / no backend
# expected. Exit 1 on suite failure, contradictory attach claims, (on
# linux/darwin) green suite without dual attach proof when deny did not SKIP,
# or when --require-attach is set and CTRL-ATTACH is not proven.

set -euo pipefail

CASE_ID="os-fs-adversarial"
BINARY=""
OUT_DIR=""
REQUIRE_ATTACH=false
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
FIXTURE_DIR="$REPO_ROOT/scripts/fixtures/os-sandbox-e2e"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case) CASE_ID="$2"; shift 2 ;;
    --binary) BINARY="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --require-attach) REQUIRE_ATTACH=true; shift ;;
    -h|--help)
      sed -n '2,35p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

bool_json() { if [[ "$1" == true ]]; then echo true; else echo false; fi; }

# Reset classify outputs (globals used by classify_from_test_log).
reset_classify_state() {
  ctrl_prepare_ok=false
  ctrl_attach_ok=false
  test_deny_ok=false
  ctrl_neighbor_ok=false
  prepare_detail="not_proven"
  attach_detail="not_proven"
  deny_detail="not_proven"
  neighbor_detail="not_proven"
  backend_id="none"
  handshake_ok=false
  linux_deny_required=false
}

# Classify attach gates from a test-fast log for a host OS.
# Args: <test_log_path> <os_name>
# Sets globals: handshake_ok, ctrl_prepare_ok, prepare_detail, test_deny_ok,
# deny_detail, ctrl_neighbor_ok, neighbor_detail, ctrl_attach_ok, attach_detail,
# backend_id, linux_deny_required.
classify_from_test_log() {
  local test_log="$1"
  local os_name="$2"

  reset_classify_state

  # CTRL-PREPARE only — probe/prepare greps never authorize CTRL-ATTACH.
  if grep -qE 'Linux Landlock prepares child plan without claiming active\.\.\.OK' "$test_log" \
    || grep -qE 'verifyApplyInChild and applySelf skip or run on Linux only\.\.\.OK' "$test_log" \
    || grep -qE 'parent apply seam never claims active \(probe/prepare only\)\.\.\.OK' "$test_log"; then
    ctrl_prepare_ok=true
    prepare_detail="zig_prepare_or_probe_only"
  fi

  # Production forkApply + status-pipe handshake (Seatbelt on macOS, Landlock on Linux).
  # Handshake alone is prepare-strength only — never paints CTRL-ATTACH green without FS deny.
  if grep -qE 'forkApplySeatbeltAndExec applies then execs on macOS with handshake\.\.\.OK' "$test_log" \
    || grep -qE 'forkApplyLandlockAndExec applies then execs on Linux with handshake\.\.\.OK' "$test_log"; then
    handshake_ok=true
    ctrl_prepare_ok=true
    prepare_detail="zig_fork_apply_handshake"
    if [[ "$os_name" == "darwin" ]]; then backend_id="seatbelt"; fi
    if [[ "$os_name" == "linux" ]]; then backend_id="landlock"; fi
  fi

  # Real FS deny canaries → TEST-DENY + CTRL-NEIGHBOR.
  # CTRL-ATTACH only when production forkApply handshake is also OK (M-1 dual requirement).
  if grep -qE 'real FS deny: outside canary denied; workspace readable and writable\.\.\.OK' "$test_log" \
    || grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$test_log"; then
    test_deny_ok=true
    deny_detail="outside_unreadable_under_sandbox"
    ctrl_neighbor_ok=true
    neighbor_detail="workspace_neighbor_rw"
    if [[ "$os_name" == "darwin" ]]; then backend_id="seatbelt"; fi
    if [[ "$os_name" == "linux" ]]; then backend_id="landlock"; fi
    if [[ "$handshake_ok" == true ]]; then
      ctrl_attach_ok=true
      attach_detail="zig_real_fs_deny_canary_and_handshake"
    else
      # Unit canary only — not production attach (M-1 honesty).
      attach_detail="zig_unit_fs_deny_without_production_handshake"
    fi
  fi

  # SKIP on wrong OS / missing ABI is honest non-attach, not failure.
  # Z-1: only the HOST OS's real FS deny test may set platform_skip. Never let the
  # other OS's always-SKIP line overwrite a more specific attach_detail
  # (e.g. zig_unit_fs_deny_without_production_handshake).
  if [[ "$ctrl_attach_ok" != true ]]; then
    local host_deny_skip=false
    case "$os_name" in
      linux)
        if grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.SKIP' "$test_log" \
          && ! grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$test_log"; then
          host_deny_skip=true
        fi
        ;;
      darwin)
        if grep -qE 'real FS deny: outside canary denied; workspace readable and writable\.\.\.SKIP' "$test_log" \
          && ! grep -qE 'real FS deny: outside canary denied; workspace readable and writable\.\.\.OK' "$test_log"; then
          host_deny_skip=true
        fi
        ;;
    esac
    if [[ "$host_deny_skip" == true && "$attach_detail" == "not_proven" ]]; then
      attach_detail="platform_skip_no_backend_on_host"
      deny_detail="platform_skip"
    fi
  fi

  # F-5: On Linux, if prepare/ABI path ran and the *Linux* real FS deny test was
  # neither OK nor SKIP, fail closed (do not treat always-SKIP macOS line as skip).
  if [[ "$os_name" == "linux" ]]; then
    if grep -qE 'Linux Landlock prepares child plan without claiming active\.\.\.OK' "$test_log" \
      || grep -qE 'verifyApplyInChild and applySelf skip or run on Linux only\.\.\.OK' "$test_log"; then
      linux_deny_required=true
    fi
    if grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$test_log"; then
      linux_deny_required=false # satisfied
    elif grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.SKIP' "$test_log"; then
      # Explicit host landlock skip (no ABI) — allow partial pass without attach.
      linux_deny_required=false
    fi
  fi
}

# --require-attach gate: fail unless CTRL-ATTACH proven (CI matrix).
# Args: <require_attach true|false> <ctrl_attach_ok> <attach_detail>
# Returns 0 if gate passes, 1 if must fail closed.
require_attach_gate() {
  local require="$1"
  local attach_ok="$2"
  local detail="$3"
  if [[ "$require" == true && "$attach_ok" != true ]]; then
    echo "FAIL: --require-attach set but CTRL-ATTACH not proven (detail=${detail})" >&2
    return 1
  fi
  return 0
}

# ORCA_E2E_SELFTEST=1: fixture-driven Z-1 / require-attach checks (no test-fast).
run_e2e_selftest() {
  local fails=0
  local f

  echo "ORCA_E2E_SELFTEST: classifying fixtures under $FIXTURE_DIR"

  f="$FIXTURE_DIR/linux-macos-skip-only.log"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing fixture $f" >&2
    return 1
  fi
  classify_from_test_log "$f" "linux"
  if [[ "$attach_detail" == "platform_skip_no_backend_on_host" ]]; then
    echo "FAIL fixture linux-macos-skip-only: false platform_skip from opposite-OS SKIP (got $attach_detail)" >&2
    fails=$((fails + 1))
  elif [[ "$ctrl_attach_ok" == true ]]; then
    echo "FAIL fixture linux-macos-skip-only: attach must not be proven" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-macos-skip-only: no false platform_skip (attach_detail=$attach_detail)"
  fi
  if require_attach_gate true "$ctrl_attach_ok" "$attach_detail" 2>/dev/null; then
    echo "FAIL fixture linux-macos-skip-only: --require-attach should fail without attach" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-macos-skip-only: --require-attach fails closed"
  fi

  f="$FIXTURE_DIR/linux-deny-ok-no-handshake.log"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing fixture $f" >&2
    return 1
  fi
  classify_from_test_log "$f" "linux"
  if [[ "$attach_detail" != "zig_unit_fs_deny_without_production_handshake" ]]; then
    echo "FAIL fixture linux-deny-ok-no-handshake: expected zig_unit_fs_deny_without_production_handshake got $attach_detail" >&2
    fails=$((fails + 1))
  elif [[ "$ctrl_attach_ok" == true ]]; then
    echo "FAIL fixture linux-deny-ok-no-handshake: attach must not be proven without handshake" >&2
    fails=$((fails + 1))
  elif [[ "$test_deny_ok" != true ]]; then
    echo "FAIL fixture linux-deny-ok-no-handshake: TEST-DENY should be ok" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-deny-ok-no-handshake: unit deny without handshake (no platform_skip overwrite)"
  fi
  if require_attach_gate true "$ctrl_attach_ok" "$attach_detail" 2>/dev/null; then
    echo "FAIL fixture linux-deny-ok-no-handshake: --require-attach should fail" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-deny-ok-no-handshake: --require-attach fails closed"
  fi

  f="$FIXTURE_DIR/linux-host-deny-skip.log"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing fixture $f" >&2
    return 1
  fi
  classify_from_test_log "$f" "linux"
  if [[ "$attach_detail" != "platform_skip_no_backend_on_host" ]]; then
    echo "FAIL fixture linux-host-deny-skip: expected platform_skip_no_backend_on_host got $attach_detail" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-host-deny-skip: host deny SKIP → platform_skip"
  fi
  if require_attach_gate true "$ctrl_attach_ok" "$attach_detail" 2>/dev/null; then
    echo "FAIL fixture linux-host-deny-skip: --require-attach should fail on platform_skip" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-host-deny-skip: --require-attach fails closed on platform_skip"
  fi

  f="$FIXTURE_DIR/linux-deny-ok-and-handshake.log"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing fixture $f" >&2
    return 1
  fi
  classify_from_test_log "$f" "linux"
  if [[ "$ctrl_attach_ok" != true || "$attach_detail" != "zig_real_fs_deny_canary_and_handshake" ]]; then
    echo "FAIL fixture linux-deny-ok-and-handshake: expected attach ok+handshake detail (attach_ok=$ctrl_attach_ok detail=$attach_detail)" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-deny-ok-and-handshake: CTRL-ATTACH proven"
  fi
  if ! require_attach_gate true "$ctrl_attach_ok" "$attach_detail"; then
    echo "FAIL fixture linux-deny-ok-and-handshake: --require-attach should pass when attach proven" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture linux-deny-ok-and-handshake: --require-attach passes"
  fi

  # Darwin host: log with only Linux SKIP (no macOS line) → not platform_skip.
  local tmp_darwin
  tmp_darwin="$(mktemp)"
  cat >"$tmp_darwin" <<'EOF'
1/99 real FS deny: outside denied; neighbor RW; control root not writable...SKIP
1/99 parent apply seam never claims active (probe/prepare only)...OK
EOF
  classify_from_test_log "$tmp_darwin" "darwin"
  rm -f "$tmp_darwin"
  if [[ "$attach_detail" == "platform_skip_no_backend_on_host" ]]; then
    echo "FAIL fixture darwin-linux-skip-only: false platform_skip from opposite-OS SKIP" >&2
    fails=$((fails + 1))
  else
    echo "OK fixture darwin-linux-skip-only: no false platform_skip (attach_detail=$attach_detail)"
  fi

  if [[ $fails -ne 0 ]]; then
    echo "ORCA_E2E_SELFTEST: FAILED ($fails assertion(s))" >&2
    return 1
  fi
  echo "ORCA_E2E_SELFTEST: PASS"
  return 0
}

if [[ "${ORCA_E2E_SELFTEST:-}" == "1" ]]; then
  run_e2e_selftest
  exit $?
fi

if [[ -z "$BINARY" ]]; then
  if [[ -x ./zig-out/bin/orca ]]; then
    BINARY=./zig-out/bin/orca
  else
    echo "building orca..."
    ./scripts/zig build
    BINARY=./zig-out/bin/orca
  fi
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$REPO_ROOT/planning/security/evidence"
fi
mkdir -p "$OUT_DIR"

OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_NAME="$(uname -m)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BINARY_SHA="unknown"
if command -v shasum >/dev/null 2>&1; then
  BINARY_SHA="$(shasum -a 256 "$BINARY" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  BINARY_SHA="$(sha256sum "$BINARY" | awk '{print $1}')"
fi

# M-12: baseline starts false; set true only after BINARY --version succeeds.
ctrl_baseline_ok=false
ctrl_off_ok=false
off_detail="not_run"
exit_code=0
reset_classify_state

# --- Zig production-path proofs (apply_posix / landlock / seatbelt) ----------
# Single test-fast run produces both unit results and evidence greps (CI must not
# double-run test-fast before calling this script).
echo "Running sandbox apply/landlock/seatbelt proofs via test-fast..."
set +e
TEST_LOG="$(mktemp)"
./scripts/zig build test-fast >"$TEST_LOG" 2>&1
TEST_RC=$?
set -e

if [[ ! -s "$TEST_LOG" ]]; then
  echo "FAIL: test-fast produced empty log; cannot prove sandbox evidence" >&2
  exit 1
fi

classify_from_test_log "$TEST_LOG" "$OS_NAME"

# Mode-off unit proof
if grep -qE 'mode off returns disabled receipt without scrub or active claim\.\.\.OK' "$TEST_LOG"; then
  ctrl_off_ok=true
  off_detail="apply_mode_off_disabled_receipt"
fi

# Parent seam never claims active without child
if ! grep -qE 'parent apply seam never claims active \(probe/prepare only\)\.\.\.OK' "$TEST_LOG" \
  && ! grep -qE 'parent apply seam never claims active.*SKIP' "$TEST_LOG"; then
  if [[ $TEST_RC -ne 0 ]]; then
    echo "WARN: parent-seam honesty test missing or suite failed (rc=$TEST_RC)" >&2
  fi
fi

# --- Optional: orca binary smoke (does not require daemon allow) ----
set +e
"$BINARY" --version >/dev/null 2>&1
BIN_RC=$?
set -e
if [[ $BIN_RC -eq 0 ]]; then
  ctrl_baseline_ok=true
fi

if [[ $TEST_RC -ne 0 ]]; then
  exit_code=$TEST_RC
  echo "test-fast failed (rc=$TEST_RC); see evidence for details" >&2
  tail -40 "$TEST_LOG" >&2 || true
fi

# Never claim attach without deny (F-1 invariant).
if [[ "$ctrl_attach_ok" == true && "$test_deny_ok" != true ]]; then
  echo "FAIL: CTRL-ATTACH set without TEST-DENY" >&2
  ctrl_attach_ok=false
  attach_detail="invalid_attach_without_deny"
  exit_code=1
fi

MANIFEST="$OUT_DIR/${CASE_ID}-${OS_NAME}-${ARCH_NAME}.json"
# Prefer jq for string-safe JSON (M-9); heredoc fallback when jq is absent.
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --argjson schema_version 1 \
    --argjson gate_ids '["P1-I-01", "P0-I-06", "M-11", "M-12", "F-1", "F-5"]' \
    --arg case_id "$CASE_ID" \
    --arg source_commit "$COMMIT" \
    --arg binary_sha256 "$BINARY_SHA" \
    --arg os "$OS_NAME" \
    --arg arch "$ARCH_NAME" \
    --arg backend_id "$backend_id" \
    --arg profile_hash "" \
    --arg command './scripts/zig build test-fast (sandbox apply real-FS-deny proofs only for CTRL-ATTACH)' \
    --argjson exit_code "$exit_code" \
    --argjson ctrl_baseline_ok "$(bool_json "$ctrl_baseline_ok")" \
    --argjson ctrl_prepare_ok "$(bool_json "$ctrl_prepare_ok")" \
    --arg prepare_detail "$prepare_detail" \
    --argjson ctrl_attach_ok "$(bool_json "$ctrl_attach_ok")" \
    --arg attach_detail "$attach_detail" \
    --argjson test_deny_ok "$(bool_json "$test_deny_ok")" \
    --arg deny_detail "$deny_detail" \
    --argjson ctrl_neighbor_ok "$(bool_json "$ctrl_neighbor_ok")" \
    --arg neighbor_detail "$neighbor_detail" \
    --argjson ctrl_off_ok "$(bool_json "$ctrl_off_ok")" \
    --arg off_detail "$off_detail" \
    --arg canary_fingerprint "zig-unit:real-fs-deny" \
    --arg rerun "./scripts/os-sandbox-adversarial-e2e.sh --case ${CASE_ID}" \
    '{
      schema_version: $schema_version,
      gate_ids: $gate_ids,
      case_id: $case_id,
      source_commit: $source_commit,
      binary_sha256: $binary_sha256,
      platform: {os: $os, arch: $arch},
      backend_id: $backend_id,
      profile_hash: $profile_hash,
      command: $command,
      exit_code: $exit_code,
      controls: {
        "CTRL-BASELINE": {ok: $ctrl_baseline_ok, detail: "binary_present"},
        "CTRL-PREPARE": {ok: $ctrl_prepare_ok, detail: $prepare_detail},
        "CTRL-ATTACH": {ok: $ctrl_attach_ok, detail: $attach_detail},
        "TEST-DENY": {ok: $test_deny_ok, detail: $deny_detail},
        "CTRL-NEIGHBOR": {ok: $ctrl_neighbor_ok, detail: $neighbor_detail},
        "CTRL-OFF": {ok: $ctrl_off_ok, detail: $off_detail}
      },
      canary_fingerprint: $canary_fingerprint,
      rerun: $rerun
    }' >"$MANIFEST"
else
  cat >"$MANIFEST" <<JSON
{
  "schema_version": 1,
  "gate_ids": ["P1-I-01", "P0-I-06", "M-11", "M-12", "F-1", "F-5"],
  "case_id": "${CASE_ID}",
  "source_commit": "${COMMIT}",
  "binary_sha256": "${BINARY_SHA}",
  "platform": {"os": "${OS_NAME}", "arch": "${ARCH_NAME}"},
  "backend_id": "${backend_id}",
  "profile_hash": "",
  "command": "./scripts/zig build test-fast (sandbox apply real-FS-deny proofs only for CTRL-ATTACH)",
  "exit_code": ${exit_code},
  "controls": {
    "CTRL-BASELINE": {"ok": $(bool_json $ctrl_baseline_ok), "detail": "binary_present"},
    "CTRL-PREPARE": {"ok": $(bool_json $ctrl_prepare_ok), "detail": "${prepare_detail}"},
    "CTRL-ATTACH": {"ok": $(bool_json $ctrl_attach_ok), "detail": "${attach_detail}"},
    "TEST-DENY": {"ok": $(bool_json $test_deny_ok), "detail": "${deny_detail}"},
    "CTRL-NEIGHBOR": {"ok": $(bool_json $ctrl_neighbor_ok), "detail": "${neighbor_detail}"},
    "CTRL-OFF": {"ok": $(bool_json $ctrl_off_ok), "detail": "${off_detail}"}
  },
  "canary_fingerprint": "zig-unit:real-fs-deny",
  "rerun": "./scripts/os-sandbox-adversarial-e2e.sh --case ${CASE_ID}"
}
JSON
fi

# Fail closed if evidence artifact is missing or empty (M-11).
if [[ ! -s "$MANIFEST" ]]; then
  echo "FAIL: evidence manifest missing or empty: $MANIFEST" >&2
  rm -f "$TEST_LOG"
  exit 1
fi

rm -f "$TEST_LOG"

echo "Wrote evidence: $MANIFEST"
echo "CTRL-BASELINE=$(bool_json $ctrl_baseline_ok) CTRL-PREPARE=$(bool_json $ctrl_prepare_ok) CTRL-ATTACH=$(bool_json $ctrl_attach_ok) TEST-DENY=$(bool_json $test_deny_ok) CTRL-NEIGHBOR=$(bool_json $ctrl_neighbor_ok) CTRL-OFF=$(bool_json $ctrl_off_ok)"

if [[ $TEST_RC -ne 0 ]]; then
  exit 1
fi

# F-5: Linux ABI/prepare present but real FS deny not green is fail.
if [[ "$linux_deny_required" == true && "$test_deny_ok" != true ]]; then
  echo "FAIL: Linux Landlock ABI/prepare path ran but real FS deny was not OK (F-5)" >&2
  exit 1
fi

# Mode-off receipt is always expected from the Zig suite (not platform-gated).
if [[ "$ctrl_off_ok" != true ]]; then
  echo "FAIL: expected CTRL-OFF (mode off receipt) evidence missing from test-fast log" >&2
  exit 1
fi

# Any CTRL-ATTACH claim requires TEST-DENY + CTRL-NEIGHBOR + production handshake.
if [[ "$ctrl_attach_ok" == true ]]; then
  if [[ "$test_deny_ok" != true || "$ctrl_neighbor_ok" != true || "$handshake_ok" != true ]]; then
    echo "FAIL: CTRL-ATTACH claimed (${attach_detail}) but dual proof incomplete (deny=${test_deny_ok} neighbor=${ctrl_neighbor_ok} handshake=${handshake_ok})" >&2
    exit 1
  fi
  # Z-2 / CI: --require-attach satisfied when attach proven.
  require_attach_gate "$REQUIRE_ATTACH" "$ctrl_attach_ok" "$attach_detail" || exit 1
  echo "PASS: sandbox proofs green (attach=${attach_detail})"
  exit 0
fi

# Z-2: CI matrix jobs pass --require-attach so platform_skip / partial is not green.
if ! require_attach_gate "$REQUIRE_ATTACH" "$ctrl_attach_ok" "$attach_detail"; then
  exit 1
fi

# M-15: on linux/darwin, green suite without dual attach proof is FAIL unless
# real FS deny platform-skipped (no backend ABI) — prepare-only is not enough.
if [[ "$OS_NAME" == "linux" || "$OS_NAME" == "darwin" ]]; then
  if [[ "$attach_detail" != "platform_skip_no_backend_on_host" ]]; then
    echo "FAIL: CTRL-ATTACH not proven on ${OS_NAME}; require production forkApply handshake + real FS deny (detail=${attach_detail})" >&2
    exit 1
  fi
fi

if [[ "$ctrl_prepare_ok" == true ]]; then
  echo "PASS (partial): prepare/probe only (detail=${prepare_detail}); no CTRL-ATTACH claimed (attach=${attach_detail})"
  exit 0
fi

echo "PASS (partial): no full attach on this host; suite green without false active claim (attach=${attach_detail})"
exit 0
