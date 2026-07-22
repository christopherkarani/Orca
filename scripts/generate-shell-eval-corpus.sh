#!/usr/bin/env bash
# Regenerate MVP shell-eval goldens from Rust `orca test --format json` when available.
# Usage: ./scripts/generate-shell-eval-corpus.sh [commands.txt]
# Without a live daemon/binary, the checked-in JSONL remains the oracle freeze.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/src/shell_engine/mvp_corpus.jsonl"
CMDS="${1:-}"

ORCA_BIN=""
if command -v orca >/dev/null 2>&1; then
  ORCA_BIN="$(command -v orca)"
elif [[ -x "${ROOT}/zig-out/bin/orca" ]]; then
  ORCA_BIN="${ROOT}/zig-out/bin/orca"
elif [[ -x "${ROOT}/orca-rs/target/release/orca-daemon" ]]; then
  ORCA_BIN="${ROOT}/orca-rs/target/release/orca-daemon"
fi

if [[ -z "${ORCA_BIN}" ]]; then
  echo "No orca/orca-daemon binary found; leaving ${OUT} unchanged." >&2
  exit 0
fi

if [[ -z "${CMDS}" ]]; then
  echo "Pass a commands file (one command per line) to regenerate goldens from Rust." >&2
  echo "Example: ./scripts/generate-shell-eval-corpus.sh /tmp/cmds.txt" >&2
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
while IFS= read -r cmd || [[ -n "${cmd}" ]]; do
  [[ -z "${cmd}" || "${cmd}" == \#* ]] && continue
  json="$("${ORCA_BIN}" test --format json "${cmd}" 2>/dev/null || true)"
  if [[ -z "${json}" ]]; then
    echo "skip (no json): ${cmd}" >&2
    continue
  fi
  decision="$(printf '%s' "${json}" | sed -n 's/.*"decision"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  rule_id="$(printf '%s' "${json}" | sed -n 's/.*"rule_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "${decision}" ]]; then
    echo "skip (no decision): ${cmd}" >&2
    continue
  fi
  if [[ -n "${rule_id}" ]]; then
    printf '{"command":%s,"expected":"%s","rule_id":"%s"}\n' "$(printf '%s' "${cmd}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')" "${decision}" "${rule_id}" >>"${tmp}"
  else
    printf '{"command":%s,"expected":"%s"}\n' "$(printf '%s' "${cmd}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')" "${decision}" >>"${tmp}"
  fi
done <"${CMDS}"

if [[ -s "${tmp}" ]]; then
  mv "${tmp}" "${OUT}"
  echo "Wrote $(wc -l <"${OUT}") goldens to ${OUT}"
else
  echo "No goldens produced." >&2
  exit 1
fi
