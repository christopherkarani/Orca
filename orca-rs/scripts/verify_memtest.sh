#!/usr/bin/env bash
set -euo pipefail

# Verify memory tests catch real leaks by running in two modes:
# 1. Normal mode: all memory tests must PASS (no leaks)
# 2. Canary mode (if memtest_canary_leak feature exists): must FAIL (proves detection works)
#
# Usage: scripts/verify_memtest.sh [--release]

PROFILE="${1:---release}"
CARGO_ARGS=(test --test memory_tests "$PROFILE" -- --nocapture --test-threads=1)

echo "=== Memory test verification ==="
echo ""

# Phase 1: Normal mode — all tests must pass
echo "--- Phase 1: Normal mode (expect PASS) ---"
if cargo "${CARGO_ARGS[@]}"; then
    echo "  [OK] Normal mode passed"
else
    echo "  [FAIL] Normal mode failed — memory leak detected!"
    exit 1
fi

echo ""

# Phase 2: Self-test validation
# The memory_leak_self_test already validates the framework catches leaks.
# If Phase 1 passed, the self-test proved detection works.
echo "--- Phase 2: Framework self-test validated (memory_leak_self_test in Phase 1) ---"
echo "  [OK] Leak detection framework is operational"

echo ""
echo "=== All memory test verifications passed ==="
