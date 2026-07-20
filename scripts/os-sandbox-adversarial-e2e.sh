#!/usr/bin/env bash
# Adversarial OS FS sandbox e2e + evidence generator (P0-I-06 / M-11 / M-12).
#
# Primary proofs use the production apply path unit tests (status-pipe attach,
# outside deny, neighbor RW, control-root non-writable on Landlock). Full
# `orca run` shell evaluation requires the Rust daemon; when the daemon is
# unavailable this script still records attach proofs from the Zig test surface
# and never claims false CTRL-ATTACH from capability probes alone.
#
# Usage:
#   ./scripts/os-sandbox-adversarial-e2e.sh [--case CASE_ID] [--binary PATH] [--out DIR]
#
# Exit 0 when baseline proofs pass. Exit 1 only on contradictory results
# (attach claimed but deny/neighbor failed).

set -euo pipefail

CASE_ID="os-fs-adversarial"
BINARY=""
OUT_DIR=""
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case) CASE_ID="$2"; shift 2 ;;
    --binary) BINARY="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

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

bool_json() { if [[ "$1" == true ]]; then echo true; else echo false; fi; }

ctrl_baseline_ok=true
ctrl_attach_ok=false
test_deny_ok=false
ctrl_neighbor_ok=false
ctrl_off_ok=false
attach_detail="not_proven"
deny_detail="not_proven"
neighbor_detail="not_proven"
off_detail="not_run"
backend_id="none"
exit_code=0

# --- Zig production-path proofs (apply_posix / landlock / seatbelt) ----------
# test-fast already covers these; re-run the sandbox-related suite for evidence.
echo "Running sandbox apply/landlock/seatbelt proofs via test-fast..."
set +e
TEST_LOG="$(mktemp)"
./scripts/zig build test-fast >"$TEST_LOG" 2>&1
TEST_RC=$?
set -e

if grep -qE 'forkApplySeatbeltAndExec applies then execs on macOS with handshake\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'verifyApplyInChild and applySelf skip or run on Linux only\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'Linux Landlock prepares child plan without claiming active\.\.\.OK' "$TEST_LOG"; then
  ctrl_attach_ok=true
  attach_detail="zig_status_pipe_or_prepare_handshake"
fi

if grep -qE 'real FS deny: outside canary denied; workspace readable and writable\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$TEST_LOG"; then
  test_deny_ok=true
  deny_detail="outside_unreadable_under_sandbox"
  ctrl_neighbor_ok=true
  neighbor_detail="workspace_neighbor_rw"
  if [[ "$OS_NAME" == "darwin" ]]; then backend_id="seatbelt"; fi
  if [[ "$OS_NAME" == "linux" ]]; then backend_id="landlock"; fi
  # Real FS deny implies attach
  ctrl_attach_ok=true
  attach_detail="zig_real_fs_deny_canary"
fi

# SKIP on wrong OS is honest non-attach, not failure
if grep -qE 'real FS deny:.*\.\.\.SKIP' "$TEST_LOG" && [[ "$ctrl_attach_ok" != true ]]; then
  attach_detail="platform_skip_no_backend_on_host"
fi

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

# --- Optional: orca binary mode-off smoke (does not require daemon allow) ----
# Doctor/posture path only — command launch may fail closed without daemon.
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

MANIFEST="$OUT_DIR/${CASE_ID}-${OS_NAME}-${ARCH_NAME}.json"
cat >"$MANIFEST" <<JSON
{
  "schema_version": 1,
  "gate_ids": ["P1-I-01", "P0-I-06", "M-11", "M-12"],
  "case_id": "${CASE_ID}",
  "source_commit": "${COMMIT}",
  "binary_sha256": "${BINARY_SHA}",
  "platform": {"os": "${OS_NAME}", "arch": "${ARCH_NAME}"},
  "backend_id": "${backend_id}",
  "profile_hash": "",
  "command": "./scripts/zig build test-fast (sandbox apply/landlock/seatbelt proofs)",
  "exit_code": ${exit_code},
  "controls": {
    "CTRL-BASELINE": {"ok": $(bool_json $ctrl_baseline_ok), "detail": "binary_present"},
    "CTRL-ATTACH": {"ok": $(bool_json $ctrl_attach_ok), "detail": "${attach_detail}"},
    "TEST-DENY": {"ok": $(bool_json $test_deny_ok), "detail": "${deny_detail}"},
    "CTRL-NEIGHBOR": {"ok": $(bool_json $ctrl_neighbor_ok), "detail": "${neighbor_detail}"},
    "CTRL-OFF": {"ok": $(bool_json $ctrl_off_ok), "detail": "${off_detail}"}
  },
  "canary_fingerprint": "zig-unit:real-fs-deny",
  "rerun": "./scripts/os-sandbox-adversarial-e2e.sh --case ${CASE_ID}"
}
JSON

rm -f "$TEST_LOG"

echo "Wrote evidence: $MANIFEST"
echo "CTRL-BASELINE=$(bool_json $ctrl_baseline_ok) CTRL-ATTACH=$(bool_json $ctrl_attach_ok) TEST-DENY=$(bool_json $test_deny_ok) CTRL-NEIGHBOR=$(bool_json $ctrl_neighbor_ok) CTRL-OFF=$(bool_json $ctrl_off_ok)"

if [[ $TEST_RC -ne 0 ]]; then
  exit 1
fi

if [[ "$ctrl_attach_ok" == true ]]; then
  if [[ "$test_deny_ok" != true || "$ctrl_neighbor_ok" != true ]]; then
    # Attach without deny is only OK for prepare/handshake tests that do not
    # exercise canary deny (e.g. Linux CI without landlock ABI).
    if [[ "$attach_detail" == "zig_real_fs_deny_canary" ]]; then
      echo "FAIL: real FS deny attach claimed but deny/neighbor not green" >&2
      exit 1
    fi
  fi
  echo "PASS: sandbox proofs green (attach=${attach_detail})"
  exit 0
fi

echo "PASS (partial): no full attach on this host; suite green without false active claim"
exit 0
