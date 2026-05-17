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


def _find_orca() -> str | None:
    configured = os.environ.get("ORCA_BIN")
    if configured:
        return configured

    found = shutil.which("orca")
    if found:
        return found

    cwd = Path.cwd()
    for candidate in (
        cwd / "zig-out" / "bin" / "orca",
        cwd.parent / "zig-out" / "bin" / "orca",
        cwd.parent.parent / "zig-out" / "bin" / "orca",
    ):
        if candidate.exists():
            return str(candidate)

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
            "Orca binary not found. Run ./scripts/install-orca-plugin.sh hermes project."
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
            if event == "pre_tool_call":
                return {
                    "action": "block",
                    "message": f"Orca unavailable for Hermes pre_tool_call: {exc}",
                }
            logger = getattr(ctx, "logger", None)
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
