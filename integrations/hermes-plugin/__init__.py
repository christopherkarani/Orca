"""Hermes Agent plugin bridge for Orca runtime guardrails."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SECRET_KEYS = (
    "password",
    "token",
    "secret",
    "api_key",
    "apikey",
    "api_secret",
    "auth",
    "authorization",
    "bearer",
    "private_key",
    "access_token",
    "refresh_token",
    "credential",
    "passwd",
    "pwd",
)

POLICY_EVENTS = {"pre_tool_call", "pre_llm_call"}
EVENTS = (
    "on_session_start",
    "pre_tool_call",
    "post_tool_call",
    "pre_llm_call",
    "post_llm_call",
    "on_session_end",
    "on_session_finalize",
    "on_session_reset",
    "subagent_stop",
)

_HERMES_HOST_MISMATCH_MARKERS = (
    "unknown host 'hermes'",
    "Expected codex or claude.",
)
_PRE_TOOL_CALL_DEGRADED_MARKERS = _HERMES_HOST_MISMATCH_MARKERS + (
    "too old for Hermes hooks",
    "does not support Hermes hooks",
    "not found or too old for Hermes hooks",
)
_HERMES_SMOKE_PAYLOAD = json.dumps(
    {
        "version": 1,
        "host": "hermes",
        "event": "pre_tool_call",
        "payload": {"command": "git status"},
        "timestamp": "1970-01-01T00:00:00Z",
    },
    separators=(",", ":"),
)

_orca_cache_env: str | None = None
_orca_cache_path: str | None = None


_FAIL_STANCE_FILENAMES = (".orca_fail_stance", "ORCA_FAIL_STANCE")
_FAIL_CLOSED_TOKENS = frozenset({"0", "false", "no", "off", "fail-closed", "closed"})
_FAIL_OPEN_TOKENS = frozenset({"1", "true", "yes", "on", "fail-open", "open"})


def _parse_fail_open_token(raw: str) -> bool | None:
    token = raw.strip().lower()
    if not token:
        return None
    if token in _FAIL_CLOSED_TOKENS:
        return False
    if token in _FAIL_OPEN_TOKENS:
        return True
    return None


def _stance_file_fail_open() -> bool | None:
    """Read install-time stance next to this plugin (written for *new* orca plugin install hermes)."""
    base = Path(__file__).resolve().parent
    for name in _FAIL_STANCE_FILENAMES:
        path = base / name
        try:
            if not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parsed = _parse_fail_open_token(stripped)
            if parsed is not None:
                return parsed
    return None


def _fail_open_enabled() -> bool:
    """Allow Hermes to proceed without Orca when degraded.

    Precedence: ORCA_HERMES_FAIL_OPEN env (when set) → install stance file → product default fail-open.
    New installs via `orca plugin install hermes` write `.orca_fail_stance` = fail-closed.
    """
    if "ORCA_HERMES_FAIL_OPEN" in os.environ:
        value = os.environ.get("ORCA_HERMES_FAIL_OPEN", "").strip().lower()
        if value:
            return value not in _FAIL_CLOSED_TOKENS
    stance = _stance_file_fail_open()
    if stance is not None:
        return stance
    return True


def _redact(value: Any) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            if any(secret in str(key).lower() for secret in SECRET_KEYS):
                result[key] = "[REDACTED]"
            else:
                result[key] = _redact(item)
        return result
    if isinstance(value, list):
        return [_redact(item) for item in value]
    return value


def _error_has_marker(error: BaseException, markers: tuple[str, ...]) -> bool:
    message = str(error)
    return any(marker in message for marker in markers)


def _is_degraded_orca_error(error: BaseException) -> bool:
    if isinstance(error, OSError):
        return True
    return _error_has_marker(error, _PRE_TOOL_CALL_DEGRADED_MARKERS)


def _hook_smoke_passes(stdout: str) -> bool:
    """Lenient probe: exit 0 and decision is not block (matches install scripts)."""
    trimmed = stdout.strip()
    if not trimmed:
        return True
    try:
        parsed = json.loads(trimmed)
    except json.JSONDecodeError:
        return False
    if not isinstance(parsed, dict):
        return False
    return parsed.get("decision", "allow") != "block"


def _orca_executable(candidate: str) -> str | None:
    try:
        path = Path(candidate).resolve()
    except OSError:
        return None
    if not path.is_file() or not os.access(path, os.X_OK):
        return None
    return str(path)


def _supports_hermes_host(orca: str) -> bool:
    try:
        completed = subprocess.run(
            [orca, "hook", "hermes", "pre_tool_call"],
            input=_HERMES_SMOKE_PAYLOAD,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    except OSError:
        return False
    if completed.returncode != 0:
        return False
    return _hook_smoke_passes(completed.stdout)


def _orca_candidates() -> list[str]:
    candidates: list[str] = []
    configured = os.environ.get("ORCA_BIN")
    if configured:
        resolved = _orca_executable(configured)
        if resolved:
            candidates.append(resolved)

    directory = Path.cwd()
    for _ in range(3):
        zig_out = directory / "zig-out" / "bin" / "orca"
        resolved = _orca_executable(str(zig_out))
        if resolved:
            candidates.append(resolved)
        if directory.parent == directory:
            break
        directory = directory.parent

    home = Path.home()
    for path in (home / ".local" / "bin" / "orca", home / ".orca" / "bin" / "orca"):
        resolved = _orca_executable(str(path))
        if resolved:
            candidates.append(resolved)

    found = shutil.which("orca")
    if found:
        resolved = _orca_executable(found)
        if resolved:
            candidates.append(resolved)

    deduped: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        if candidate not in seen:
            seen.add(candidate)
            deduped.append(candidate)
    return deduped


def _find_orca() -> str | None:
    global _orca_cache_env, _orca_cache_path
    env_bin = os.environ.get("ORCA_BIN")
    if _orca_cache_path is not None and _orca_cache_env == env_bin:
        return _orca_cache_path

    for candidate in _orca_candidates():
        try:
            if _supports_hermes_host(candidate):
                _orca_cache_env = env_bin
                _orca_cache_path = candidate
                return candidate
        except OSError:
            continue
    return None


def _warn_degraded(ctx: Any, event: str, message: str) -> None:
    """Always surface degraded-path warnings — never silent fail-open."""
    full = f"[orca-hermes] {message}"
    logger = getattr(ctx, "logger", None)
    if logger and hasattr(logger, "warning"):
        logger.warning(full)
    # Also print so non-logger hosts and CI logs always see the stance.
    print(f"warning: {full}", flush=True)


def _handle_hook_error(ctx: Any, event: str, exc: BaseException) -> Any:
    if event == "pre_tool_call" and _is_degraded_orca_error(exc):
        if not _fail_open_enabled():
            return {
                "action": "block",
                "message": (
                    f"Orca unavailable for Hermes pre_tool_call: {exc} "
                    "(set ORCA_HERMES_FAIL_OPEN=1 to allow without guardrails)"
                ),
            }
        _warn_degraded(
            ctx,
            event,
            "FAIL-OPEN: Orca is missing or too old for Hermes hooks; upgrade Orca or set ORCA_BIN. "
            "Allowing tool call WITHOUT Orca guardrails. "
            "Set ORCA_HERMES_FAIL_OPEN=0 to block, or use `orca run -- hermes`.",
        )
        return None
    if event == "pre_tool_call":
        return {
            "action": "block",
            "message": f"Orca unavailable for Hermes pre_tool_call: {exc}",
        }
    if _error_has_marker(exc, _HERMES_HOST_MISMATCH_MARKERS):
        _warn_degraded(
            ctx,
            event,
            "FAIL-OPEN: Orca is too old for Hermes hooks; upgrade Orca or set ORCA_BIN. "
            "Continuing without Orca guardrails for this event.",
        )
        return None
    logger = getattr(ctx, "logger", None)
    if logger and hasattr(logger, "warning"):
        logger.warning("Orca Hermes hook failed for %s: %s", event, exc)
    else:
        print(f"warning: [orca-hermes] hook failed for {event}: {exc}", flush=True)
    return None


def _event_payload(event: str, hook_args: tuple[Any, ...], hook_kwargs: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "hook_event_name": event,
        "args": hook_args,
        "kwargs": hook_kwargs,
        "extra": dict(hook_kwargs),
    }

    if event in {"pre_tool_call", "post_tool_call"}:
        if "tool_name" in hook_kwargs:
            payload["tool_name"] = hook_kwargs["tool_name"]
        elif len(hook_args) > 0:
            payload["tool_name"] = hook_args[0]

        if "args" in hook_kwargs:
            payload["tool_input"] = hook_kwargs["args"]
        elif "params" in hook_kwargs:
            payload["tool_input"] = hook_kwargs["params"]
        elif len(hook_args) > 1:
            payload["tool_input"] = hook_args[1]

    if event in {"pre_llm_call", "post_llm_call"}:
        for key in ("session_id", "user_message", "conversation_history", "model", "platform"):
            if key in hook_kwargs:
                payload[key] = hook_kwargs[key]
        if "user_message" not in payload and len(hook_args) > 1:
            payload["user_message"] = hook_args[1]

    return payload


def _payload(event: str, data: Any) -> str:
    return json.dumps(
        {
            "version": 1,
            "host": "hermes",
            "event": event,
            "payload": _redact(data),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
        separators=(",", ":"),
    )


def _call_orca(event: str, data: Any) -> dict[str, Any]:
    orca = _find_orca()
    if not orca:
        raise RuntimeError(
            "Orca binary not found or too old for Hermes hooks. "
            "Run ./scripts/install-orca-plugin.sh hermes project or set ORCA_BIN."
        )

    try:
        completed = subprocess.run(
            [orca, "hook", "hermes", event],
            input=_payload(event, data),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15 if event in POLICY_EVENTS else 10,
            check=False,
        )
    except OSError as exc:
        raise RuntimeError(f"failed to run Orca at {orca}: {exc}") from exc
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"orca exited {completed.returncode}")
    if not completed.stdout.strip():
        return {"decision": "allow"}
    return json.loads(completed.stdout)


def _ci_mode() -> bool:
    """True when interactive approval cannot be answered (CI / noninteractive)."""
    for key in ("CI", "ORCA_CI", "ORCA_NONINTERACTIVE"):
        value = os.environ.get(key, "").strip().lower()
        if value and value not in ("0", "false", "no", "off"):
            return True
    return False


def _stable_rule_key(response: dict[str, Any], tool_name: str, tool_input: Any) -> str:
    """Stable Hermes [a]lways allowlist grain for Orca ask decisions.

    Format: ``orca:{rule}:{tool}:{args_fp}``

    - ``rule`` is Orca ``rule_id``/``rule`` when present (else ``policy``).
    - ``tool`` is the Hermes tool name.
    - ``args_fp`` is a short hash of canonical tool args so approving one
      command/path under a rule does not blanket every later match of that rule.
    """
    rule = response.get("rule_id") or response.get("rule") or "policy"
    rule_s = str(rule).strip() or "policy"
    tool_s = (tool_name or "tool").strip() or "tool"
    try:
        canonical = json.dumps(tool_input, sort_keys=True, default=str, separators=(",", ":"))
    except (TypeError, ValueError):
        canonical = str(tool_input)
    fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12]
    return f"orca:{rule_s}:{tool_s}:{fingerprint}"


def _format_tool_message(response: dict[str, Any], *, default: str = "blocked by Orca") -> str:
    message = response.get("message") or response.get("reason") or default
    if not isinstance(message, str):
        message = default
    remediation = response.get("remediation_commands")
    if isinstance(remediation, list) and remediation:
        tips = "; ".join(str(item) for item in remediation if item)
        if tips:
            message = f"{message} Next: {tips}"
    rule_id = response.get("rule_id") or response.get("rule")
    if rule_id:
        message = f"{message} (rule: {rule_id})"
    return message


def _map_pre_tool_call(
    ctx: Any,
    response: dict[str, Any],
    tool_name: str,
    tool_input: Any,
) -> Any:
    """Map Orca decision → Hermes pre_tool_call directive.

    - allow → None (proceed)
    - block → {"action": "block", ...} hard deny
    - ask → {"action": "approve", "message", "rule_key"} (native human gate);
      CI/noninteractive hardens ask → block
    - warn → log advisory warning and allow (not collapsed to block)
    - other → fail-closed block
    """
    decision = response.get("decision", "allow")
    if decision == "allow":
        return None
    if decision == "warn":
        message = _format_tool_message(response, default="policy warning from Orca")
        _warn_degraded(ctx, "pre_tool_call", f"WARN (advisory, not blocked): {message}")
        return None
    if decision == "block":
        return {
            "action": "block",
            "message": _format_tool_message(response, default="blocked by Orca"),
        }
    if decision == "ask":
        message = _format_tool_message(response, default="approval required by Orca")
        if _ci_mode():
            return {
                "action": "block",
                "message": (
                    f"{message} "
                    "(CI/noninteractive: Orca ask hardened to block; no approval prompt available)"
                ),
            }
        return {
            "action": "approve",
            "message": message,
            "rule_key": _stable_rule_key(response, tool_name, tool_input),
        }
    return {
        "action": "block",
        "message": "Orca returned an invalid tool decision; blocked fail-closed.",
    }


def _map_pre_llm_call(response: dict[str, Any]) -> Any:
    """Map Orca decision → Hermes pre_llm_call context.

    Hermes only supports context injection on this hook — it cannot veto the
    turn or open an approval dialog. Context notes are therefore advisory:

    - warn / context_only: honest advisory policy note
    - ask / block: honest note that this is NOT an enforcement or approval gate;
      strongest real gate remains ``orca run -- hermes``
    """
    decision = response.get("decision", "allow")
    if decision not in ("block", "warn", "ask", "context_only"):
        return None
    message = response.get("message") or response.get("reason") or "Review this prompt under Orca policy."
    if not isinstance(message, str):
        message = "Review this prompt under Orca policy."
    if decision == "warn" or decision == "context_only":
        return {"context": f"Orca policy note (warn/observe, advisory only): {message}"}
    if decision == "ask":
        return {
            "context": (
                f"Orca policy note (ask — not an approval gate): {message} "
                "Hermes pre_llm_call cannot gate prompts or open approve-and-resume. "
                "This note does not enforce approval. Prefer `orca run -- hermes` for outer enforcement."
            )
        }
    # block
    return {
        "context": (
            f"Orca policy note (block — host cannot veto pre_llm_call): {message} "
            "Hermes pre_llm_call cannot block the turn; this note does not enforce a deny. "
            "Prefer `orca run -- hermes` for outer enforcement."
        )
    }


def _register(ctx: Any, event: str) -> None:
    def handler(*args: Any, **kwargs: Any) -> Any:
        payload = _event_payload(event, args, kwargs)
        try:
            response = _call_orca(event, payload)
        except (RuntimeError, json.JSONDecodeError, subprocess.SubprocessError, OSError) as exc:
            return _handle_hook_error(ctx, event, exc)

        if event == "pre_tool_call":
            tool_name = str(payload.get("tool_name") or kwargs.get("tool_name") or "")
            tool_input = payload.get("tool_input")
            if tool_input is None:
                tool_input = kwargs.get("args") or kwargs.get("params") or {}
            return _map_pre_tool_call(ctx, response, tool_name, tool_input)
        if event == "pre_llm_call":
            return _map_pre_llm_call(response)
        return None

    ctx.register_hook(event, handler)


def register(ctx: Any) -> None:
    for event in EVENTS:
        _register(ctx, event)
