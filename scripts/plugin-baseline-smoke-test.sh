#!/usr/bin/env bash
# Aegis Plugin Baseline Smoke Test
# Safe checks only. No drone hardware. No network. No secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AEGIS="${REPO_ROOT}/zig-out/bin/aegis"
AEGIS_EDGE="${REPO_ROOT}/zig-out/bin/aegis-edge"

ERRORS=0

log_info() { echo "[INFO]  $1"; }
log_pass() { echo "[PASS]  $1"; }
log_fail() { echo "[FAIL]  $1"; ERRORS=$((ERRORS + 1)); }

cd "${REPO_ROOT}"

log_info "=== Aegis Plugin Baseline Smoke Test ==="
log_info "Repo: ${REPO_ROOT}"
log_info "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Build
log_info "Running zig build..."
if zig build 2>/dev/null; then
    log_pass "zig build"
else
    log_fail "zig build"
fi
echo ""

# 2. Tests
log_info "Running zig build test..."
if zig build test 2>/dev/null; then
    log_pass "zig build test"
else
    log_fail "zig build test"
fi
echo ""

# 3. CLI smoke tests
log_info "Running CLI smoke tests..."

if [[ -x "${AEGIS}" ]]; then
    if "${AEGIS}" --help >/dev/null 2>&1; then
        log_pass "aegis --help"
    else
        log_fail "aegis --help"
    fi

    if "${AEGIS}" version >/dev/null 2>&1; then
        log_pass "aegis version"
    else
        log_fail "aegis version"
    fi

    if "${AEGIS}" doctor >/dev/null 2>&1; then
        log_pass "aegis doctor"
    else
        log_fail "aegis doctor"
    fi

    if "${AEGIS}" redteam --ci >/dev/null 2>&1; then
        log_pass "aegis redteam --ci"
    else
        log_fail "aegis redteam --ci"
    fi
else
    log_fail "aegis binary not found at ${AEGIS}"
fi
echo ""

# 4. Edge CLI smoke tests
log_info "Running Edge CLI smoke tests..."

if [[ -x "${AEGIS_EDGE}" ]]; then
    if "${AEGIS_EDGE}" --help >/dev/null 2>&1; then
        log_pass "aegis-edge --help"
    else
        log_fail "aegis-edge --help"
    fi

    if "${AEGIS_EDGE}" doctor >/dev/null 2>&1; then
        log_pass "aegis-edge doctor"
    else
        log_fail "aegis-edge doctor"
    fi

    # Run Edge redteam in CI mode (safe, deterministic, no hardware)
    if "${AEGIS_EDGE}" redteam --ci >/dev/null 2>&1; then
        log_pass "aegis-edge redteam --ci"
    else
        log_fail "aegis-edge redteam --ci"
    fi
else
    log_fail "aegis-edge binary not found at ${AEGIS_EDGE}"
fi
echo ""

# 5. Check baseline docs exist
log_info "Checking baseline docs..."

if [[ -f "${REPO_ROOT}/docs/integrations/current-baseline.md" ]]; then
    log_pass "docs/integrations/current-baseline.md exists"
else
    log_fail "docs/integrations/current-baseline.md missing"
fi

if [[ -f "${REPO_ROOT}/docs/integrations/drone-safepoint.md" ]]; then
    log_pass "docs/integrations/drone-safepoint.md exists"
else
    log_fail "docs/integrations/drone-safepoint.md missing"
fi
echo ""

# Summary
log_info "=== Smoke Test Summary ==="
if [[ ${ERRORS} -eq 0 ]]; then
    echo "All checks passed."
    exit 0
else
    echo "${ERRORS} check(s) failed."
    exit 1
fi
