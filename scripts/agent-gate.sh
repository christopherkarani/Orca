#!/usr/bin/env bash
# Pick the narrowest useful verification gate for coding agents (Zig 0.16.0).
#
# Usage:
#   ./scripts/agent-gate.sh                 # auto from git dirty + staged paths
#   ./scripts/agent-gate.sh --dry-run       # print chosen command only
#   ./scripts/agent-gate.sh --paths a.zig b.rs
#   ./scripts/agent-gate.sh compile|units|full|check|core|rust|dx|sandbox|policy|intercept|dashboard|plugin
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
  dashboard   npm test in orca-dashboard-ui/
  plugin      package-local tests for dirty integrations/*-plugin paths
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
    check|compile|units|full|core|sandbox|policy|intercept|dx|rust|dashboard|plugin|auto)
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

# Collect unique plugin package roots touched by $paths (integrations/<name>-plugin).
plugin_dirs_from_paths() {
  local p dir
  local -a seen=()
  for p in "${paths[@]}"; do
    case "${p}" in
      integrations/*-plugin|integrations/*-plugin/*)
        dir="${p#integrations/}"
        dir="integrations/${dir%%/*}"
        local s
        local found=0
        for s in "${seen[@]+"${seen[@]}"}"; do
          if [[ "${s}" == "${dir}" ]]; then found=1; break; fi
        done
        if [[ "${found}" -eq 0 ]]; then
          seen+=("${dir}")
          printf '%s\n' "${dir}"
        fi
        ;;
    esac
  done
}

choose_auto() {
  local p
  local has_zig=0 has_core=0 has_rust=0 has_policy=0 has_scripts=0 has_other=0
  local has_sandbox=0 has_intercept=0 has_policy_src=0
  local has_dashboard=0 has_plugin=0
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
    # Legacy dashboard assets are covered by orca-dashboard-ui contract tests,
    # not the Zig monopath — keep them out of has_zig so pure asset PRs route
    # to the dashboard gate (matches CI path filter).
    case "${p}" in
      src/dashboard/*) has_dashboard=1 ;;
      src/*|packages/*|build.zig|build.zig.zon|tests/*) has_zig=1 ;;
    esac
    case "${p}" in
      packages/core/*|src/core/*|src/core_engine.zig|src/policy/*|src/audit/*) has_core=1 ;;
    esac
    case "${p}" in
      src/sandbox/*|src/sandbox_slice_root.zig) has_sandbox=1 ;;
      *)
        case "${p}" in
          *.md|docs/*|planning/*|.grok/*) ;;
          *) only_sandbox=0 ;;
        esac
        ;;
    esac
    case "${p}" in
      src/intercept/*|src/intercept_slice_root.zig) has_intercept=1 ;;
      *)
        case "${p}" in
          *.md|docs/*|planning/*|.grok/*) ;;
          *) only_intercept=0 ;;
        esac
        ;;
    esac
    case "${p}" in
      src/policy/*) has_policy_src=1 ;;
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
      orca-dashboard-ui/*) has_dashboard=1 ;;
      integrations/*-plugin|integrations/*-plugin/*) has_plugin=1 ;;
      integrations/*) has_other=1 ;;
    esac
  done

  if [[ "${only_md}" -eq 1 && "${has_zig}" -eq 0 && "${has_rust}" -eq 0 && "${has_dashboard}" -eq 0 && "${has_plugin}" -eq 0 ]]; then
    echo check
    return
  fi
  if [[ "${has_rust}" -eq 1 && "${has_zig}" -eq 0 && "${has_policy}" -eq 0 && "${has_dashboard}" -eq 0 && "${has_plugin}" -eq 0 ]]; then
    echo rust
    return
  fi
  if [[ "${has_policy}" -eq 1 && "${has_zig}" -eq 0 ]]; then
    # Mixed policy + rust still needs both when rust paths are present.
    if [[ "${has_rust}" -eq 1 ]]; then
      echo "dx rust"
    else
      echo dx
    fi
    return
  fi
  if [[ "${has_zig}" -eq 1 ]]; then
    local zig_gate=""
    # Prefer domain slices when dirty paths stay inside one domain.
    if [[ "${has_sandbox}" -eq 1 && "${only_sandbox}" -eq 1 ]]; then
      zig_gate=sandbox
    elif [[ "${has_intercept}" -eq 1 && "${only_intercept}" -eq 1 ]]; then
      zig_gate=intercept
    elif [[ "${has_policy_src}" -eq 1 && "${only_policy_src}" -eq 1 ]]; then
      zig_gate=policy
    elif [[ "${has_core}" -eq 1 ]]; then
      # Core-only surface → focused core tests (still cheap).
      local non_core=0
      for p in "${paths[@]}"; do
        case "${p}" in
          packages/core/*|src/core/*|src/core_engine.zig|src/policy/*|src/audit/*|*.md|docs/*|planning/*) ;;
          src/*|packages/*|build.zig|tests/*) non_core=1 ;;
        esac
      done
      if [[ "${non_core}" -eq 0 ]]; then
        zig_gate=core
      fi
    fi
    if [[ -z "${zig_gate}" ]]; then
      zig_gate=units
    fi
    # Mixed Zig + orca-rs: run both stacks so auto cannot green only half (Codex).
    local out="${zig_gate}"
    if [[ "${has_rust}" -eq 1 ]]; then
      out+=" rust"
    fi
    echo "${out}"
    return
  fi
  # Package-local surfaces (no Zig): never green via compile-fast check alone.
  if [[ "${has_dashboard}" -eq 1 || "${has_plugin}" -eq 1 ]]; then
    local out=""
    if [[ "${has_dashboard}" -eq 1 ]]; then
      out="dashboard"
    fi
    if [[ "${has_plugin}" -eq 1 ]]; then
      if [[ -n "${out}" ]]; then out+=" "; fi
      out+="plugin"
    fi
    if [[ "${has_rust}" -eq 1 ]]; then
      out+=" rust"
    fi
    echo "${out}"
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

run_dashboard_gate() {
  if [[ "${dry_run}" -eq 1 ]]; then
    echo "[agent-gate] dry-run: (cd orca-dashboard-ui && npm test)"
    return 0
  fi
  if [[ ! -d orca-dashboard-ui ]]; then
    echo "error: orca-dashboard-ui/ missing" >&2
    exit 3
  fi
  (cd orca-dashboard-ui && npm test)
}

run_plugin_gate() {
  local -a dirs=()
  local d

  if [[ ${#paths[@]} -gt 0 ]]; then
    while IFS= read -r d; do
      [[ -n "${d}" ]] || continue
      dirs+=("${d}")
    done < <(plugin_dirs_from_paths)
  fi

  # Forced `plugin` mode with no paths: exercise packages that ship npm/python tests.
  if [[ ${#dirs[@]} -eq 0 ]]; then
    dirs=(
      integrations/openclaw-plugin
      integrations/opencode-plugin
      integrations/hermes-plugin
    )
  fi

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "error: plugin gate selected but no integrations/*-plugin paths found" >&2
    exit 3
  fi

  for d in "${dirs[@]}"; do
    if [[ ! -d "${d}" ]]; then
      echo "[agent-gate] skip missing plugin dir: ${d}"
      continue
    fi
    if [[ -f "${d}/package.json" ]]; then
      if [[ "${dry_run}" -eq 1 ]]; then
        echo "[agent-gate] dry-run: (cd ${d} && npm test)"
      else
        echo "[agent-gate] plugin npm test: ${d}"
        (cd "${d}" && npm test)
      fi
    elif [[ -f "${d}/test_discovery.py" ]] || compgen -G "${d}/test_*.py" >/dev/null 2>&1; then
      if [[ "${dry_run}" -eq 1 ]]; then
        echo "[agent-gate] dry-run: (cd ${d} && python3 -m unittest discover -s . -p 'test_*.py' -v)"
      else
        echo "[agent-gate] plugin python tests: ${d}"
        (cd "${d}" && python3 -m unittest discover -s . -p 'test_*.py' -v)
      fi
    else
      echo "[agent-gate] no package-local test runner for ${d} (hooks/skills-only); skip"
    fi
  done
}

run_gate() {
  local g="$1"

  echo "[agent-gate] selected=${g}"
  if [[ "${g}" == "dashboard" ]]; then
    run_dashboard_gate
    return
  fi
  if [[ "${g}" == "plugin" ]]; then
    run_plugin_gate
    return
  fi

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

# Auto may emit multiple gates (e.g. "units rust", "dashboard plugin") for mixed trees.
# shellcheck disable=SC2206
gates=( ${selected} )
for g in "${gates[@]}"; do
  run_gate "${g}"
done
