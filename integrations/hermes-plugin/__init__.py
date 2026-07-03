"""Hermes Agent plugin bridge for Orca runtime guardrails."""

from __future__ import annotations

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


def _fail_open_enabled() -> bool:
    """Allow Hermes to proceed without Orca when degraded (default on). Set ORCA_HERMES_FAIL_OPEN=0 to block."""
    value = os.environ.get("ORCA_HERMES_FAIL_OPEN", "1").strip().lower()
    return value not in ("0", "false", "no", "off")


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
    logger = getattr(ctx, "logger", None)
    if logger and hasattr(logger, "warning"):
        logger.warning(message)
    elif event in POLICY_EVENTS:
        print(f"warning: {message}", flush=True)


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
            "Orca is missing or too old for Hermes hooks; upgrade Orca or set ORCA_BIN. "
            "Allowing tool call without Orca guardrails.",
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
            "Orca is too old for Hermes hooks; upgrade Orca or set ORCA_BIN. "
            "Continuing without Orca guardrails for this event.",
        )
        return None
    logger = getattr(ctx, "logger", None)
    if logger and hasattr(logger, "warning"):
        logger.warning("Orca Hermes hook failed for %s: %s", event, exc)
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


def _register(ctx: Any, event: str) -> None:
    def handler(*args: Any, **kwargs: Any) -> Any:
        payload = _event_payload(event, args, kwargs)
        try:
            response = _call_orca(event, payload)
        except (RuntimeError, json.JSONDecodeError, subprocess.SubprocessError, OSError) as exc:
            return _handle_hook_error(ctx, event, exc)

        decision = response.get("decision", "allow")
        if event == "pre_tool_call":
            if decision == "allow":
                return None
            if isinstance(decision, str) and decision in ("block", "warn", "ask"):
                message = response.get("message") or response.get("reason") or "blocked by Orca"
                return {"action": "block", "message": message}
            return {"action": "block", "message": "Orca returned an invalid tool decision; blocked fail-closed."}
        if event == "pre_llm_call" and isinstance(decision, str) and decision in ("block", "warn", "ask"):
            message = response.get("message") or response.get("reason") or "Review this prompt under Orca policy."
            return {"context": f"Orca policy note: {message}"}
        return None

    ctx.register_hook(event, handler)


def register(ctx: Any) -> None:
    for event in EVENTS:
        _register(ctx, event)
