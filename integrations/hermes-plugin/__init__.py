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


def _supports_hermes_host(orca: str) -> bool:
    payload = json.dumps(
        {
            "version": 1,
            "host": "hermes",
            "event": "pre_tool_call",
            "payload": {"command": "git status"},
            "timestamp": "1970-01-01T00:00:00Z",
        },
        separators=(",", ":"),
    )
    completed = subprocess.run(
        [orca, "hook", "hermes", "pre_tool_call"],
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    return completed.returncode == 0


def _is_hermes_host_mismatch(error: BaseException) -> bool:
    message = str(error)
    return any(marker in message for marker in _HERMES_HOST_MISMATCH_MARKERS)


def _orca_candidates() -> list[str]:
    candidates: list[str] = []
    configured = os.environ.get("ORCA_BIN")
    if configured:
        candidates.append(configured)

    home = Path.home()
    for path in (
        home / ".local" / "bin" / "orca",
        home / ".orca" / "bin" / "orca",
    ):
        if path.exists():
            candidates.append(str(path))

    cwd = Path.cwd()
    for path in (
        cwd / "zig-out" / "bin" / "orca",
        cwd.parent / "zig-out" / "bin" / "orca",
        cwd.parent.parent / "zig-out" / "bin" / "orca",
    ):
        if path.exists():
            candidates.append(str(path))

    found = shutil.which("orca")
    if found:
        candidates.append(found)

    deduped: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        if candidate not in seen:
            seen.add(candidate)
            deduped.append(candidate)
    return deduped


def _find_orca() -> str | None:
    for candidate in _orca_candidates():
        if _supports_hermes_host(candidate):
            return candidate
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

    completed = subprocess.run(
        [orca, "hook", "hermes", event],
        input=_payload(event, data),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15 if event in POLICY_EVENTS else 10,
        check=False,
    )
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
        except Exception as exc:
            logger = getattr(ctx, "logger", None)
            if _is_hermes_host_mismatch(exc):
                message = (
                    "Orca is too old for Hermes hooks; upgrade Orca or set ORCA_BIN. "
                    "Allowing tool call without Orca guardrails."
                )
                if logger and hasattr(logger, "warning"):
                    logger.warning(message)
                elif event in POLICY_EVENTS:
                    print(f"warning: {message}", flush=True)
                return None

            if event == "pre_tool_call":
                return {
                    "action": "block",
                    "message": f"Orca unavailable for Hermes pre_tool_call: {exc}",
                }
            if logger and hasattr(logger, "warning"):
                logger.warning("Orca Hermes hook failed for %s: %s", event, exc)
            return None

        decision = response.get("decision", "allow")
        if event == "pre_tool_call" and decision == "block":
            message = response.get("message") or response.get("reason") or "blocked by Orca"
            return {"action": "block", "message": message}
        if event == "pre_llm_call" and decision in {"block", "warn", "ask"}:
            message = response.get("message") or response.get("reason") or "Review this prompt under Orca policy."
            return {"context": f"Orca policy note: {message}"}
        return None

    ctx.register_hook(event, handler)


def register(ctx: Any) -> None:
    for event in EVENTS:
        _register(ctx, event)
