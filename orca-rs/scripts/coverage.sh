#!/usr/bin/env bash
# scripts/coverage.sh
# Generate local coverage reports
#
# Usage:
#   ./scripts/coverage.sh           # Generate coverage report
#   ./scripts/coverage.sh --open    # Generate and open HTML report
#   ./scripts/coverage.sh --quick   # Skip HTML, just show summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' CYAN='' YELLOW='' BOLD='' NC=''
fi

cd "$PROJECT_ROOT"

# Check for cargo-llvm-cov
if ! command -v cargo-llvm-cov &> /dev/null; then
    echo -e "${YELLOW}cargo-llvm-cov not found. Installing...${NC}"
    cargo install cargo-llvm-cov
fi

# Check for jq (used for file-level threshold checks).
if ! command -v jq &> /dev/null; then
    echo "jq is required for coverage threshold checks"
    exit 1
fi

OVERALL_MIN=70
EVALUATOR_MIN=80
HOOK_MIN=80

show_help() {
    cat << EOF
Usage: $0 [options]

Generate code coverage reports for orca.

Options:
  --open      Open HTML report in browser after generation
  --quick     Quick mode: only show text summary (no HTML)
  --lcov      Generate LCOV format (for CI/codecov)
  -h, --help  Show this help

Output:
  target/llvm-cov/html/     HTML coverage report
  coverage-summary.txt      Text summary
  coverage.json             JSON report used for threshold checks
  lcov.info                 LCOV format (with --lcov)

Thresholds:
  Overall lines             >= 70%
  src/evaluator.rs lines    >= 80%
  src/hook.rs lines         >= 80%

EOF
    exit 0
}

OPEN_BROWSER=0
QUICK_MODE=0
GENERATE_LCOV=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --open)     OPEN_BROWSER=1; shift ;;
        --quick)    QUICK_MODE=1; shift ;;
        --lcov)     GENERATE_LCOV=1; shift ;;
        -h|--help)  show_help ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BOLD}Coverage Report Generator${NC}"
echo ""

# Run tests with coverage
echo -e "${CYAN}Running tests with coverage instrumentation...${NC}"
cargo llvm-cov --all-features \
    --ignore-filename-regex='(tests/|benches/|\.cargo/)' \
    --no-report

# Generate text summary
echo -e "${CYAN}Generating coverage summary...${NC}"
cargo llvm-cov report --all-features \
    --ignore-filename-regex='(tests/|benches/|\.cargo/)' \
    --text > coverage-summary.txt

cargo llvm-cov report --all-features \
    --ignore-filename-regex='(tests/|benches/|\.cargo/)' \
    --json --output-path coverage.json

echo ""
echo -e "${BOLD}Coverage Summary:${NC}"
cat coverage-summary.txt

# Extract percentage (portable - works on macOS and Linux)
COVERAGE=$(grep 'TOTAL' coverage-summary.txt | grep -Eo '[0-9]+\.[0-9]+%' | tail -1 | tr -d '%' || echo "0")
echo ""
echo -e "${BOLD}Total coverage: ${GREEN}${COVERAGE}%${NC}"

echo ""
echo -e "${BOLD}Coverage Thresholds:${NC}"
overall=$(jq -r '.data[0].totals.lines.percent // empty' coverage.json)
evaluator=$(jq -r '.data[0].files[] | select(.filename | endswith("evaluator.rs")) | .summary.lines.percent' coverage.json)
hook=$(jq -r '.data[0].files[] | select(.filename | endswith("hook.rs")) | .summary.lines.percent' coverage.json)

check_threshold() {
    local label="$1"
    local actual="$2"
    local minimum="$3"

    if [[ -z "$actual" || "$actual" == "null" ]]; then
        echo "  ${label}: missing from coverage.json"
        return 1
    fi

    printf "  %s >= %.0f%% (observed %.2f%%)\n" "$label" "$minimum" "$actual"
    awk -v actual="$actual" -v minimum="$minimum" 'BEGIN { exit actual < minimum ? 1 : 0 }'
}

failures=0
check_threshold "Overall" "$overall" "$OVERALL_MIN" || failures=$((failures + 1))
check_threshold "src/evaluator.rs" "$evaluator" "$EVALUATOR_MIN" || failures=$((failures + 1))
check_threshold "src/hook.rs" "$hook" "$HOOK_MIN" || failures=$((failures + 1))

if [[ $failures -gt 0 ]]; then
    echo ""
    echo "Coverage thresholds not met (${failures} failure(s))"
    exit 1
fi

echo -e "${GREEN}Coverage thresholds satisfied.${NC}"

if [[ $QUICK_MODE -eq 0 ]]; then
    # Generate HTML report
    echo ""
    echo -e "${CYAN}Generating HTML report...${NC}"
    cargo llvm-cov report --all-features \
        --ignore-filename-regex='(tests/|benches/|\.cargo/)' \
        --html

    HTML_PATH="$PROJECT_ROOT/target/llvm-cov/html/index.html"
    echo -e "${GREEN}HTML report: ${HTML_PATH}${NC}"

    if [[ $OPEN_BROWSER -eq 1 ]]; then
        echo -e "${CYAN}Opening in browser...${NC}"
        if command -v xdg-open &> /dev/null; then
            xdg-open "$HTML_PATH"
        elif command -v open &> /dev/null; then
            open "$HTML_PATH"
        else
            echo -e "${YELLOW}Could not detect browser opener. Open manually: ${HTML_PATH}${NC}"
        fi
    fi
fi

if [[ $GENERATE_LCOV -eq 1 ]]; then
    echo ""
    echo -e "${CYAN}Generating LCOV report...${NC}"
    cargo llvm-cov report --all-features \
        --ignore-filename-regex='(tests/|benches/|\.cargo/)' \
        --lcov --output-path lcov.info
    echo -e "${GREEN}LCOV report: lcov.info${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}Coverage generation complete!${NC}"
