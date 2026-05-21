#!/usr/bin/env bash
# Convenience wrapper for the Orca Sub-Agent Orchestrator
# Usage: ./scripts/orchestrator.sh [options]
#
# Examples:
#   ./scripts/orchestrator.sh           # Run all ready tasks
#   ./scripts/orchestrator.sh --dry-run # Preview ready tasks
#   ./scripts/orchestrator.sh --status  # Show task status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATOR_DIR="$PROJECT_ROOT/.pi/orchestrator"

cd "$ORCHESTRATOR_DIR"

# Auto-build if dist/ is missing or stale
if [[ ! -d dist ]] || [[ src/index.ts -nt dist/index.js ]]; then
  echo "[orchestrator] Building..."
  npm run build >/dev/null 2>&1 || npx tsc
fi

cd "$PROJECT_ROOT"
node "$ORCHESTRATOR_DIR/dist/index.js" "$@"
