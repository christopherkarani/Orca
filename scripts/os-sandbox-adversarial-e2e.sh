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
#
# Usage:
#   ./scripts/os-sandbox-adversarial-e2e.sh [--case CASE_ID] [--binary PATH] [--out DIR]
#
# Exit 0 when full attach is proven, or partial when platform-skip / no backend
# expected. Exit 1 on suite failure, contradictory attach claims, or (on
# linux/darwin) green suite without dual attach proof when deny did not SKIP.

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
      sed -n '2,28p' "$0"
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

# M-12: baseline starts false; set true only after BINARY --version succeeds.
ctrl_baseline_ok=false
ctrl_prepare_ok=false
ctrl_attach_ok=false
test_deny_ok=false
ctrl_neighbor_ok=false
ctrl_off_ok=false
prepare_detail="not_proven"
attach_detail="not_proven"
deny_detail="not_proven"
neighbor_detail="not_proven"
off_detail="not_run"
backend_id="none"
exit_code=0
linux_deny_required=false

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

# CTRL-PREPARE only — probe/prepare greps never authorize CTRL-ATTACH.
if grep -qE 'Linux Landlock prepares child plan without claiming active\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'verifyApplyInChild and applySelf skip or run on Linux only\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'parent apply seam never claims active \(probe/prepare only\)\.\.\.OK' "$TEST_LOG"; then
  ctrl_prepare_ok=true
  prepare_detail="zig_prepare_or_probe_only"
fi

# Production forkApply + status-pipe handshake (Seatbelt on macOS, Landlock on Linux).
# Either platform's production path sets handshake_ok. Handshake alone is
# prepare-strength only — never paints CTRL-ATTACH green without FS deny (M-1/M-4).
handshake_ok=false
if grep -qE 'forkApplySeatbeltAndExec applies then execs on macOS with handshake\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'forkApplyLandlockAndExec applies then execs on Linux with handshake\.\.\.OK' "$TEST_LOG"; then
  handshake_ok=true
  ctrl_prepare_ok=true
  prepare_detail="zig_fork_apply_handshake"
  if [[ "$OS_NAME" == "darwin" ]]; then backend_id="seatbelt"; fi
  if [[ "$OS_NAME" == "linux" ]]; then backend_id="landlock"; fi
fi

# Real FS deny canaries → TEST-DENY + CTRL-NEIGHBOR.
# CTRL-ATTACH only when production forkApply handshake is also OK (M-1 dual requirement).
if grep -qE 'real FS deny: outside canary denied; workspace readable and writable\.\.\.OK' "$TEST_LOG" \
  || grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$TEST_LOG"; then
  test_deny_ok=true
  deny_detail="outside_unreadable_under_sandbox"
  ctrl_neighbor_ok=true
  neighbor_detail="workspace_neighbor_rw"
  if [[ "$OS_NAME" == "darwin" ]]; then backend_id="seatbelt"; fi
  if [[ "$OS_NAME" == "linux" ]]; then backend_id="landlock"; fi
  if [[ "$handshake_ok" == true ]]; then
    ctrl_attach_ok=true
    attach_detail="zig_real_fs_deny_canary_and_handshake"
  else
    # Unit canary only — not production attach (M-1 honesty).
    attach_detail="zig_unit_fs_deny_without_production_handshake"
  fi
fi

# SKIP on wrong OS / missing ABI is honest non-attach, not failure.
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

# F-5: On Linux CI hosts, Landlock is expected. If the suite ran and the real FS
# deny test was neither OK nor SKIP, or we detect ABI via a Landlock prepare OK
# without deny, fail closed rather than greenwash.
if [[ "$OS_NAME" == "linux" ]]; then
  if grep -qE 'Linux Landlock prepares child plan without claiming active\.\.\.OK' "$TEST_LOG" \
    || grep -qE 'verifyApplyInChild and applySelf skip or run on Linux only\.\.\.OK' "$TEST_LOG"; then
    # ABI/prepare path exercised — require real deny for a green attach gate.
    linux_deny_required=true
  fi
  if grep -qE 'real FS deny: outside denied; neighbor RW; control root not writable\.\.\.OK' "$TEST_LOG"; then
    linux_deny_required=false # satisfied
  elif grep -qE 'real FS deny:.*\.\.\.SKIP' "$TEST_LOG"; then
    # Explicit skip (no ABI) — allow partial pass without attach.
    linux_deny_required=false
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
  echo "PASS: sandbox proofs green (attach=${attach_detail})"
  exit 0
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
