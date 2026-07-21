#!/usr/bin/env bash
# Pick the narrowest useful verification gate for coding agents (Zig 0.16.0).
#
# Usage:
#   ./scripts/agent-gate.sh                 # auto from git dirty + staged paths
#   ./scripts/agent-gate.sh --dry-run       # print chosen command only
#   ./scripts/agent-gate.sh --paths a.zig b.rs
#   ./scripts/agent-gate.sh compile|units|full|check|core|rust|dx|sandbox|policy|intercept
#
# Explicit modes always run that gate. Auto mode uses path heuristics.
# Domain slices: prefer test-slice.sh for -Dtest-filter; agent-gate picks the slice.
# See Agents.md → "Verification gates".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

dry_run=0
mode=""
paths=()

usage() {
  cat >&2 <<'EOF'
usage: ./scripts/agent-gate.sh [--dry-run] [--paths FILE...] [MODE]

Modes:
  check       ./scripts/compile-fast.sh check
  compile     ./scripts/test-fast.sh compile
  units       ./scripts/test-fast.sh units
  full        ./scripts/test-fast.sh full
  core        zig build test-core + test-core-contract
  sandbox     ./scripts/test-slice.sh sandbox
  policy      ./scripts/test-slice.sh policy
  intercept   ./scripts/test-slice.sh intercept
  dx          quick-install-dx-verify (builds CLI if needed)
  rust        cargo test --lib in orca-rs/
  auto        (default) choose from dirty paths / --paths
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --paths)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        paths+=("$1")
        shift
      done
      ;;
    -h|--help) usage; exit 0 ;;
    check|compile|units|full|core|sandbox|policy|intercept|dx|rust|auto)
      mode="$1"
      shift
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

mode="${mode:-auto}"

if [[ ${#paths[@]} -eq 0 && "${mode}" == "auto" ]]; then
  # Dirty + staged; fall back to empty (→ check).
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    paths+=("${line}")
  done < <(git status --porcelain 2>/dev/null | awk '{print $NF}' || true)
fi

choose_auto() {
  local p
  local has_zig=0 has_core=0 has_rust=0 has_policy=0 has_scripts=0 has_other=0
  local has_sandbox=0 has_intercept=0 has_policy_src=0
  local only_md=1
  local only_sandbox=1 only_intercept=1 only_policy_src=1

  if [[ ${#paths[@]} -eq 0 ]]; then
    echo check
    return
  fi

  for p in "${paths[@]}"; do
    case "${p}" in
      *.md|docs/*|planning/*|.grok/*) ;;
      *) only_md=0 ;;
    esac
    case "${p}" in
      src/*|packages/*|build.zig|build.zig.zon|tests/*) has_zig=1 ;;
    esac
    case "${p}" in
      packages/core/*|src/core/*|src/core_engine.zig|src/policy/*|src/audit/*) has_core=1 ;;
    esac
    case "${p}" in
      src/sandbox/*|tests/slices/sandbox.zig) has_sandbox=1 ;;
      *)
        case "${p}" in
          *.md|docs/*|planning/*|.grok/*) ;;
          *) only_sandbox=0 ;;
        esac
        ;;
    esac
    case "${p}" in
      src/intercept/*|tests/slices/intercept.zig) has_intercept=1 ;;
      *)
        case "${p}" in
          *.md|docs/*|planning/*|.grok/*) ;;
          *) only_intercept=0 ;;
        esac
        ;;
    esac
    case "${p}" in
      src/policy/*|tests/slices/policy.zig) has_policy_src=1 ;;
      *)
        case "${p}" in
          *.md|docs/*|planning/*|.grok/*|packages/core/*|src/core/*|src/core_engine.zig|src/audit/*) ;;
          *) only_policy_src=0 ;;
        esac
        ;;
    esac
    case "${p}" in
      orca-rs/*) has_rust=1 ;;
    esac
    case "${p}" in
      policies/*|schemas/policy*|src/policy/presets.zig) has_policy=1 ;;
    esac
    case "${p}" in
      scripts/*) has_scripts=1 ;;
    esac
    case "${p}" in
      orca-dashboard-ui/*|integrations/*) has_other=1 ;;
    esac
  done

  if [[ "${only_md}" -eq 1 && "${has_zig}" -eq 0 && "${has_rust}" -eq 0 ]]; then
    echo check
    return
  fi
  if [[ "${has_rust}" -eq 1 && "${has_zig}" -eq 0 && "${has_policy}" -eq 0 ]]; then
    echo rust
    return
  fi
  if [[ "${has_policy}" -eq 1 && "${has_zig}" -eq 0 ]]; then
    echo dx
    return
  fi
  if [[ "${has_zig}" -eq 1 ]]; then
    # Prefer domain slices when dirty paths stay inside one domain.
    if [[ "${has_sandbox}" -eq 1 && "${only_sandbox}" -eq 1 ]]; then
      echo sandbox
      return
    fi
    if [[ "${has_intercept}" -eq 1 && "${only_intercept}" -eq 1 ]]; then
      echo intercept
      return
    fi
    if [[ "${has_policy_src}" -eq 1 && "${only_policy_src}" -eq 1 ]]; then
      echo policy
      return
    fi
    # Core-only surface → focused core tests (still cheap).
    if [[ "${has_core}" -eq 1 ]]; then
      local non_core=0
      for p in "${paths[@]}"; do
        case "${p}" in
          packages/core/*|src/core/*|src/core_engine.zig|src/policy/*|src/audit/*|*.md|docs/*|planning/*) ;;
          src/*|packages/*|build.zig|tests/*) non_core=1 ;;
        esac
      done
      if [[ "${non_core}" -eq 0 ]]; then
        echo core
        return
      fi
    fi
    echo units
    return
  fi
  if [[ "${has_scripts}" -eq 1 ]]; then
    echo check
    return
  fi
  if [[ "${has_other}" -eq 1 ]]; then
    echo check
    return
  fi
  echo check
}

run_gate() {
  local g="$1"

  echo "[agent-gate] selected=${g}"
  if [[ "${dry_run}" -eq 1 ]]; then
    case "${g}" in
      check) echo "[agent-gate] dry-run: ./scripts/compile-fast.sh check" ;;
      compile) echo "[agent-gate] dry-run: ./scripts/test-fast.sh compile" ;;
      units) echo "[agent-gate] dry-run: ./scripts/test-fast.sh units" ;;
      full) echo "[agent-gate] dry-run: ./scripts/test-fast.sh full" ;;
      core) echo "[agent-gate] dry-run: ./scripts/zig build … test-core && test-core-contract" ;;
      sandbox) echo "[agent-gate] dry-run: ./scripts/test-slice.sh sandbox" ;;
      policy) echo "[agent-gate] dry-run: ./scripts/test-slice.sh policy" ;;
      intercept) echo "[agent-gate] dry-run: ./scripts/test-slice.sh intercept" ;;
      dx) echo "[agent-gate] dry-run: ./scripts/quick-install-dx-verify.sh" ;;
      rust) echo "[agent-gate] dry-run: (cd orca-rs && cargo test --lib)" ;;
      *)
        echo "error: internal unknown gate ${g}" >&2
        exit 3
        ;;
    esac
    return 0
  fi

  case "${g}" in
    check) ./scripts/compile-fast.sh check ;;
    compile) ./scripts/test-fast.sh compile ;;
    units) ./scripts/test-fast.sh units ;;
    full) ./scripts/test-fast.sh full ;;
    core)
      ./scripts/zig build -fincremental -j1 -Dincremental=true test-core
      ./scripts/zig build -fincremental -j1 -Dincremental=true test-core-contract
      ;;
    sandbox) ./scripts/test-slice.sh sandbox ;;
    policy) ./scripts/test-slice.sh policy ;;
    intercept) ./scripts/test-slice.sh intercept ;;
    dx)
      if [[ ! -x zig-out/bin/orca ]]; then
        echo "[agent-gate] building CLI for DX matrix"
        ./scripts/zig build -fincremental -Dincremental=true
      fi
      ./scripts/quick-install-dx-verify.sh
      ;;
    rust) (cd orca-rs && cargo test --lib) ;;
    *)
      echo "error: internal unknown gate ${g}" >&2
      exit 3
      ;;
  esac
}

if [[ "${mode}" == "auto" ]]; then
  selected="$(choose_auto)"
else
  selected="${mode}"
fi

run_gate "${selected}"
