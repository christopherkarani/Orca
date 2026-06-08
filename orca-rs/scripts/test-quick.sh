#!/usr/bin/env bash
# scripts/test-quick.sh
# Fast feedback loop for development - runs essential tests
#
# Usage:
#   ./scripts/test-quick.sh           # Run all unit tests
#   ./scripts/test-quick.sh --e2e     # Run E2E tests too
#   ./scripts/test-quick.sh --check   # Run clippy + fmt first

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors (only if terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' RED='' CYAN='' BOLD='' NC=''
fi

# Check for nextest
USE_NEXTEST=0
if command -v cargo-nextest &> /dev/null || cargo nextest --version &> /dev/null 2>&1; then
    USE_NEXTEST=1
fi

cd "$PROJECT_ROOT"

show_help() {
    cat << EOF
Usage: $0 [options]

Fast feedback loop for orca development.

Options:
  --check     Run clippy and fmt checks first
  --e2e       Also run E2E tests after unit tests
  --all       Run check + unit + e2e (comprehensive)
  -h, --help  Show this help

EOF
    exit 0
}

run_checks() {
    echo -e "${CYAN}Checking formatting...${NC}"
    cargo fmt -- --check
    echo -e "${CYAN}Running clippy...${NC}"
    cargo clippy --all-targets -- -D warnings
}

run_unit_tests() {
    echo -e "${CYAN}Running unit tests...${NC}"
    if [[ $USE_NEXTEST -eq 1 ]]; then
        cargo nextest run --color=always
    else
        cargo test --color=always
    fi
}

run_e2e_tests() {
    echo -e "${CYAN}Running E2E tests...${NC}"
    cargo build --release
    "$SCRIPT_DIR/e2e_test.sh"
}

# Parse arguments
RUN_CHECK=0
RUN_E2E=0
RUN_ALL=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --check)    RUN_CHECK=1; shift ;;
        --e2e)      RUN_E2E=1; shift ;;
        --all)      RUN_ALL=1; shift ;;
        -h|--help)  show_help ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ $RUN_ALL -eq 1 ]]; then
    RUN_CHECK=1
    RUN_E2E=1
fi

echo -e "${BOLD}Quick Test Runner${NC}"
echo "Using: $([ $USE_NEXTEST -eq 1 ] && echo 'cargo-nextest' || echo 'cargo test')"
echo ""

START_TIME=$(date +%s)
FAILED=0

if [[ $RUN_CHECK -eq 1 ]]; then
    run_checks || FAILED=1
fi

if [[ $FAILED -eq 0 ]]; then
    run_unit_tests || FAILED=1
fi

if [[ $FAILED -eq 0 ]] && [[ $RUN_E2E -eq 1 ]]; then
    run_e2e_tests || FAILED=1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All tests passed${NC} (${DURATION}s)"
    exit 0
else
    echo -e "${RED}${BOLD}Tests failed${NC} (${DURATION}s)"
    exit 1
fi
