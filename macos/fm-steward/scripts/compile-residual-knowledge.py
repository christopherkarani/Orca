#!/usr/bin/env python3
"""Compile residual-knowledge YAML packs → Fixtures/ambig-fewshot/seed.json.

Stdlib only (no PyYAML). Supports a restricted YAML subset used by residual packs:
  - top-level key: value (scalars, quoted strings, | blocks, [list], or nested lists of maps)
  - entries / contrasts / hard_rule_exclusions as list-of-maps or list-of-scalars

Product law: ambiguous-only seed; assist for residual FM; never security authority.

Usage:
  python3 scripts/compile-residual-knowledge.py
  python3 scripts/compile-residual-knowledge.py --check
  python3 scripts/compile-residual-knowledge.py --self-test
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

VALID_VERDICTS = frozenset({"continue", "ask", "ask_sticky_candidate"})
FILLED_DOMAINS = frozenset({"shell"})  # employee domains reserved; coding packs use shell
MIN_ENTRIES = 40
REQUIRED_PACK_SUFFIXES = (
    "shell/wipe_vs_clean.yaml",
    "shell/install_hygiene.yaml",
    "shell/git_gray.yaml",
    "shell/network_out.yaml",
    "shell/process.yaml",
    "containers/docker_compose.yaml",
)

# Global smoke exclusions (ambiguous-only seed).
GLOBAL_EXCLUSIONS = (
    "rm -rf /",
    "rm -rf/",
    "| bash",
    "|bash",
    "| sh",
    "|sh",
    "curl|bash",
    "curl|sh",
    "wget|bash",
    "wget|sh",
)


def package_root() -> Path:
    return Path(__file__).resolve().parent.parent


def residual_root(root: Path | None = None) -> Path:
    return (root or package_root()) / "residual-knowledge"


def seed_path(root: Path | None = None) -> Path:
    return (root or package_root()) / "Fixtures" / "ambig-fewshot" / "seed.json"


# ---------------------------------------------------------------------------
# Restricted YAML subset parser
# ---------------------------------------------------------------------------


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def _parse_flow_list(s: str) -> list[str]:
    inner = s.strip()
    if not (inner.startswith("[") and inner.endswith("]")):
        raise ValueError(f"expected flow list, got: {s!r}")
    body = inner[1:-1].strip()
    if not body:
        return []
    parts: list[str] = []
    buf = ""
    in_q: str | None = None
    for ch in body:
        if in_q:
            if ch == in_q:
                in_q = None
            buf += ch
        elif ch in ("'", '"'):
            in_q = ch
            buf += ch
        elif ch == ",":
            parts.append(_unquote(buf))
            buf = ""
        else:
            buf += ch
    if buf.strip():
        parts.append(_unquote(buf))
    return parts


def parse_restricted_yaml(text: str) -> dict[str, Any]:
    """Parse residual pack YAML (restricted subset) into a dict."""
    lines = text.splitlines()
    data: dict[str, Any] = {}
    i = 0
    n = len(lines)

    def skip_blank_and_comments(idx: int) -> int:
        while idx < n:
            raw = lines[idx]
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                idx += 1
                continue
            break
        return idx

    while i < n:
        i = skip_blank_and_comments(i)
        if i >= n:
            break
        line = lines[i]
        if line.startswith(" ") or line.startswith("\t"):
            raise ValueError(f"unexpected indent at line {i + 1}: {line!r}")
        if ":" not in line:
            raise ValueError(f"expected key: at line {i + 1}: {line!r}")
        key, rest = line.split(":", 1)
        key = key.strip()
        rest = rest.strip()
        i += 1

        if rest == "|":
            block: list[str] = []
            while i < n:
                nxt = lines[i]
                if not nxt.strip():
                    block.append("")
                    i += 1
                    continue
                if nxt.startswith("  ") or nxt.startswith("\t"):
                    block.append(nxt[2:] if nxt.startswith("  ") else nxt.lstrip("\t"))
                    i += 1
                    continue
                break
            # trim trailing empty lines
            while block and block[-1] == "":
                block.pop()
            data[key] = "\n".join(block)
            continue

        if rest.startswith("["):
            data[key] = _parse_flow_list(rest)
            continue

        if rest == "":
            # nested list of maps or scalars
            items: list[Any] = []
            while i < n:
                i = skip_blank_and_comments(i)
                if i >= n:
                    break
                nxt = lines[i]
                if not nxt.startswith("  - ") and not nxt.startswith("\t- "):
                    if nxt.startswith(" ") or nxt.startswith("\t"):
                        raise ValueError(f"bad list item indent line {i + 1}: {nxt!r}")
                    break
                item_body = nxt.split("-", 1)[1].strip()
                i += 1
                if item_body and ":" not in item_body and not item_body.startswith("{"):
                    # scalar list item
                    items.append(_unquote(item_body))
                    continue
                # map item
                obj: dict[str, Any] = {}
                if item_body:
                    if ":" not in item_body:
                        raise ValueError(f"bad map item line {i}: {nxt!r}")
                    k2, v2 = item_body.split(":", 1)
                    k2 = k2.strip()
                    v2 = v2.strip()
                    if v2.startswith("["):
                        obj[k2] = _parse_flow_list(v2)
                    else:
                        obj[k2] = _unquote(v2)
                # continuation lines for this map (indent >= 4 spaces)
                while i < n:
                    cont = lines[i]
                    if cont.strip() == "" or cont.strip().startswith("#"):
                        # peek: blank inside map is ok only if next is still map field
                        # treat blank as end of map if following is list or top-level
                        peek = i + 1
                        while peek < n and (not lines[peek].strip() or lines[peek].strip().startswith("#")):
                            peek += 1
                        if peek >= n:
                            i = peek
                            break
                        if lines[peek].startswith("  - ") or (
                            not lines[peek].startswith(" ") and not lines[peek].startswith("\t")
                        ):
                            i += 1
                            # only consume one blank; break map
                            if cont.strip() == "":
                                break
                            continue
                        i += 1
                        continue
                    if cont.startswith("  - ") or cont.startswith("\t- "):
                        break
                    if not (cont.startswith("    ") or cont.startswith("\t\t") or cont.startswith("\t  ")):
                        if cont.startswith(" ") or cont.startswith("\t"):
                            # 2-space continuation without dash = still map field at 2 spaces under list? 
                            # Our schema uses 4 spaces for map fields under "  - "
                            if cont.startswith("  ") and ":" in cont and not cont.startswith("  - "):
                                # allow 2-space map fields under list item
                                pass
                            else:
                                break
                        else:
                            break
                    field = cont.strip()
                    if ":" not in field:
                        raise ValueError(f"expected field: line {i + 1}: {cont!r}")
                    k2, v2 = field.split(":", 1)
                    k2 = k2.strip()
                    v2 = v2.strip()
                    if v2.startswith("["):
                        obj[k2] = _parse_flow_list(v2)
                    else:
                        obj[k2] = _unquote(v2)
                    i += 1
                items.append(obj)
            data[key] = items
            continue

        # scalar
        data[key] = _unquote(rest)

    return data


# ---------------------------------------------------------------------------
# Compile + validate
# ---------------------------------------------------------------------------


class CompileError(Exception):
    pass


def find_pack_files(rk_root: Path) -> list[Path]:
    if not rk_root.is_dir():
        raise CompileError(f"residual-knowledge dir missing: {rk_root}")
    packs = sorted(p for p in rk_root.rglob("*.yaml") if p.is_file())
    # skip anything under _fixtures or underscore-private dirs
    packs = [p for p in packs if not any(part.startswith("_") for part in p.relative_to(rk_root).parts)]
    return packs


def load_pack(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    try:
        data = parse_restricted_yaml(text)
    except Exception as e:
        raise CompileError(f"{path}: parse error: {e}") from e
    return data


def validate_and_collect(packs: list[tuple[Path, dict[str, Any]]]) -> list[dict[str, Any]]:
    errors: list[str] = []
    examples: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    id_to_pack: dict[str, str] = {}

    rel_paths = {str(p.as_posix()) for p, _ in packs}

    for req in REQUIRED_PACK_SUFFIXES:
        if not any(rp.endswith(req) for rp in rel_paths):
            errors.append(f"missing required pack ending with {req}")

    for path, pack in packs:
        rel = path.name
        schema = pack.get("schema_version")
        if schema != 1 and schema != "1":
            errors.append(f"{rel}: schema_version must be 1 (got {schema!r})")
        pack_id = pack.get("id")
        if not pack_id:
            errors.append(f"{rel}: missing id")
        domain = pack.get("domain", "shell")
        if domain not in FILLED_DOMAINS:
            errors.append(f"{rel}: domain must be one of {sorted(FILLED_DOMAINS)} for filled packs (got {domain!r})")

        exclusions = list(GLOBAL_EXCLUSIONS)
        pack_ex = pack.get("hard_rule_exclusions") or []
        if isinstance(pack_ex, list):
            exclusions.extend(str(x) for x in pack_ex)

        entries = pack.get("entries") or []
        if not isinstance(entries, list) or not entries:
            errors.append(f"{rel}: entries must be a non-empty list")
            continue

        entry_ids: set[str] = set()
        for ent in entries:
            if not isinstance(ent, dict):
                errors.append(f"{rel}: entry is not a map: {ent!r}")
                continue
            eid = ent.get("id")
            cmd = ent.get("command")
            verdict = ent.get("verdict")
            why = ent.get("why") or ""
            tags = ent.get("tags") or []
            if not eid:
                errors.append(f"{rel}: entry missing id")
                continue
            if eid in seen_ids:
                errors.append(f"{rel}: duplicate entry id {eid!r} (also in {id_to_pack.get(eid)})")
            seen_ids.add(str(eid))
            id_to_pack[str(eid)] = rel
            entry_ids.add(str(eid))
            if not cmd or not str(cmd).strip():
                errors.append(f"{rel}/{eid}: empty command")
            if verdict not in VALID_VERDICTS:
                errors.append(f"{rel}/{eid}: invalid verdict {verdict!r}")
            if not why or not str(why).strip():
                errors.append(f"{rel}/{eid}: empty why")
            cmd_l = str(cmd or "").lower()
            for ex in exclusions:
                if ex.lower() in cmd_l:
                    errors.append(f"{rel}/{eid}: command hits hard_rule_exclusion {ex!r}")
            if not isinstance(tags, list):
                tags = []
            examples.append(
                {
                    "id": str(eid),
                    "command": str(cmd).strip(),
                    "expected_verdict": str(verdict),
                    "why": str(why).strip(),
                    "tags": [str(t) for t in tags],
                    "domain": str(domain),
                }
            )

        contrasts = pack.get("contrasts") or []
        if contrasts and isinstance(contrasts, list):
            for c in contrasts:
                if not isinstance(c, dict):
                    errors.append(f"{rel}: contrast not a map")
                    continue
                safe = c.get("safe")
                risk = c.get("risk")
                if safe not in entry_ids:
                    errors.append(f"{rel}: contrast safe id {safe!r} not in pack entries")
                if risk not in entry_ids:
                    errors.append(f"{rel}: contrast risk id {risk!r} not in pack entries")

    if len(examples) < MIN_ENTRIES:
        errors.append(f"total entries {len(examples)} < minimum {MIN_ENTRIES}")

    if errors:
        raise CompileError("validation failed:\n  - " + "\n  - ".join(errors))

    # stable order: by id
    examples.sort(key=lambda e: e["id"])
    return examples


def compile_seed(root: Path | None = None) -> list[dict[str, Any]]:
    rk = residual_root(root)
    pack_files = find_pack_files(rk)
    if not pack_files:
        raise CompileError(f"no YAML packs under {rk}")
    loaded: list[tuple[Path, dict[str, Any]]] = []
    for p in pack_files:
        loaded.append((p, load_pack(p)))
    return validate_and_collect(loaded)


def write_seed(examples: list[dict[str, Any]], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(examples, indent=2, ensure_ascii=False) + "\n"
    out.write_text(text, encoding="utf-8")


def check_mode(root: Path | None = None) -> None:
    root = root or package_root()
    examples = compile_seed(root)
    out = seed_path(root)
    if not out.is_file():
        raise CompileError(f"--check: seed missing at {out}; run compiler without --check")
    existing = json.loads(out.read_text(encoding="utf-8"))
    # Normalize compare (sorted keys already by compile)
    if existing != examples:
        raise CompileError(
            f"--check: {out} is stale or diverged from YAML packs "
            f"(seed has {len(existing)} entries, compile has {len(examples)}). "
            "Re-run without --check to regenerate."
        )
    print(f"OK: {len(examples)} examples; seed matches packs; families present")


# ---------------------------------------------------------------------------
# Self-test (TDD for compiler validation)
# ---------------------------------------------------------------------------


def self_test() -> None:
    failures: list[str] = []

    def expect_fail(label: str, yaml_text: str, needle: str) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            pack_dir = root / "residual-knowledge" / "shell"
            pack_dir.mkdir(parents=True)
            (pack_dir / "bad.yaml").write_text(yaml_text, encoding="utf-8")
            # also need required packs stub — self-test tests unit validate paths differently
            try:
                load_pack(pack_dir / "bad.yaml")
                # minimal validate of single pack via hack: call collect with required relaxed
            except CompileError as e:
                if needle.lower() not in str(e).lower():
                    failures.append(f"{label}: expected {needle!r} in {e}")
                return
            # parse ok — try full compile which will fail missing required packs
            try:
                compile_seed(root)
                failures.append(f"{label}: expected failure")
            except CompileError as e:
                if needle.lower() not in str(e).lower():
                    # may fail on missing required first
                    if "invalid verdict" in needle.lower() or "exclusion" in needle.lower():
                        # inject into validate path
                        pass
                    if needle.lower() not in str(e).lower() and "missing required" in str(e).lower():
                        # re-run entry-level checks manually
                        data = load_pack(pack_dir / "bad.yaml")
                        try:
                            validate_and_collect([(pack_dir / "bad.yaml", data)])
                            failures.append(f"{label}: expected validation failure for {needle!r}")
                        except CompileError as e2:
                            if needle.lower() not in str(e2).lower():
                                failures.append(f"{label}: expected {needle!r} in {e2}")
                    elif needle.lower() not in str(e).lower():
                        failures.append(f"{label}: expected {needle!r} in {e}")

    # Invalid verdict
    bad_verdict = """
schema_version: 1
id: residual.test
name: Test
domain: shell
description: |
  test
entries:
  - id: T_bad
    command: "echo hi"
    verdict: deny
    why: "no"
    tags: [ambig]
"""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        p = root / "residual-knowledge" / "shell" / "bad.yaml"
        p.parent.mkdir(parents=True)
        p.write_text(bad_verdict, encoding="utf-8")
        data = load_pack(p)
        try:
            validate_and_collect([(p, data)])
            failures.append("invalid verdict: expected failure")
        except CompileError as e:
            if "invalid verdict" not in str(e).lower():
                failures.append(f"invalid verdict: {e}")

    # Exclusion
    bad_ex = """
schema_version: 1
id: residual.test
name: Test
domain: shell
description: test
entries:
  - id: T_root
    command: "rm -rf /"
    verdict: ask
    why: "catastrophe"
    tags: [ambig]
"""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        p = root / "residual-knowledge" / "shell" / "bad.yaml"
        p.parent.mkdir(parents=True)
        p.write_text(bad_ex, encoding="utf-8")
        data = load_pack(p)
        try:
            validate_and_collect([(p, data)])
            failures.append("exclusion: expected failure")
        except CompileError as e:
            if "hard_rule_exclusion" not in str(e).lower() and "rm -rf /" not in str(e).lower():
                failures.append(f"exclusion: {e}")

    # Happy path min count — build enough stubs
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rk = root / "residual-knowledge"
        families = [
            ("shell", "wipe_vs_clean"),
            ("shell", "install_hygiene"),
            ("shell", "git_gray"),
            ("shell", "network_out"),
            ("shell", "process"),
            ("containers", "docker_compose"),
        ]
        n = 0
        for folder, name in families:
            d = rk / folder
            d.mkdir(parents=True, exist_ok=True)
            entries = []
            for j in range(8):
                n += 1
                entries.append(
                    f"""  - id: E_{name}_{j}
    command: "cmd {name} {j}"
    verdict: continue
    why: "gray example {j}"
    tags: [ambig]
"""
                )
            text = f"""schema_version: 1
id: residual.{name}
name: {name}
domain: shell
description: |
  test pack
entries:
{''.join(entries)}
"""
            (d / f"{name}.yaml").write_text(text, encoding="utf-8")
        try:
            examples = compile_seed(root)
            if len(examples) < MIN_ENTRIES:
                failures.append(f"happy path count: got {len(examples)}")
        except CompileError as e:
            failures.append(f"happy path: {e}")

    # Contrast resolve
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        p = root / "residual-knowledge" / "shell" / "c.yaml"
        p.parent.mkdir(parents=True)
        p.write_text(
            """
schema_version: 1
id: residual.c
name: c
domain: shell
description: x
entries:
  - id: A1
    command: "echo a"
    verdict: continue
    why: "a"
    tags: [ambig]
contrasts:
  - safe: A1
    risk: MISSING
    note: "bad"
""",
            encoding="utf-8",
        )
        data = load_pack(p)
        try:
            validate_and_collect([(p, data)])
            failures.append("contrast: expected failure")
        except CompileError as e:
            if "MISSING" not in str(e):
                failures.append(f"contrast: {e}")

    if failures:
        print("SELF-TEST FAILED:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        sys.exit(1)
    print("SELF-TEST OK")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Compile residual-knowledge YAML → seed.json")
    parser.add_argument("--check", action="store_true", help="Validate packs and match checked-in seed")
    parser.add_argument("--self-test", action="store_true", help="Run compiler unit self-tests")
    parser.add_argument("--root", type=Path, default=None, help="Package root (default: auto)")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return 0

    root = args.root.resolve() if args.root else package_root()
    try:
        if args.check:
            check_mode(root)
        else:
            examples = compile_seed(root)
            out = seed_path(root)
            write_seed(examples, out)
            print(f"Wrote {len(examples)} examples → {out}")
    except CompileError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
