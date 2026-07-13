"""Unit tests for Hermes plugin Orca discovery and degraded-mode handling."""

from __future__ import annotations

import importlib.util
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

_PLUGIN_PATH = Path(__file__).with_name("__init__.py")
_SPEC = importlib.util.spec_from_file_location("hermes_plugin", _PLUGIN_PATH)
assert _SPEC and _SPEC.loader
_PLUGIN = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _PLUGIN
_SPEC.loader.exec_module(_PLUGIN)


class HermesPluginDiscoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        _PLUGIN._orca_cache_env = None
        _PLUGIN._orca_cache_path = None

    def test_fail_open_defaults_on(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ORCA_HERMES_FAIL_OPEN", None)
            with mock.patch.object(_PLUGIN, "_stance_file_fail_open", return_value=None):
                self.assertTrue(_PLUGIN._fail_open_enabled())
        with mock.patch.dict(os.environ, {"ORCA_HERMES_FAIL_OPEN": "0"}):
            self.assertFalse(_PLUGIN._fail_open_enabled())

    def test_fail_open_stance_file_fail_closed_for_new_installs(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ORCA_HERMES_FAIL_OPEN", None)
            with mock.patch.object(_PLUGIN, "_stance_file_fail_open", return_value=False):
                self.assertFalse(_PLUGIN._fail_open_enabled())
            # Env wins over stance file.
            with mock.patch.dict(os.environ, {"ORCA_HERMES_FAIL_OPEN": "1"}):
                with mock.patch.object(_PLUGIN, "_stance_file_fail_open", return_value=False):
                    self.assertTrue(_PLUGIN._fail_open_enabled())

    def test_parse_fail_open_token(self) -> None:
        self.assertIs(_PLUGIN._parse_fail_open_token("fail-closed"), False)
        self.assertIs(_PLUGIN._parse_fail_open_token("0"), False)
        self.assertIs(_PLUGIN._parse_fail_open_token("fail-open"), True)
        self.assertIsNone(_PLUGIN._parse_fail_open_token(""))

    def test_orca_executable_rejects_missing_file(self) -> None:
        self.assertIsNone(_PLUGIN._orca_executable("/nonexistent/orca-binary"))

    def test_hook_smoke_passes_blocks_only(self) -> None:
        self.assertTrue(_PLUGIN._hook_smoke_passes('{"decision":"allow"}'))
        self.assertFalse(_PLUGIN._hook_smoke_passes('{"decision":"block"}'))

    def test_find_orca_skips_oserror_from_smoke_probe(self) -> None:
        with mock.patch.object(_PLUGIN, "_orca_candidates", return_value=["/tmp/orca"]):
            with mock.patch.object(_PLUGIN, "_supports_hermes_host", side_effect=OSError("spawn failed")):
                self.assertIsNone(_PLUGIN._find_orca())

    def test_pre_tool_call_fail_closed_when_disabled(self) -> None:
        ctx = mock.Mock()
        exc = RuntimeError("Orca binary not found or too old for Hermes hooks")
        with mock.patch.dict(os.environ, {"ORCA_HERMES_FAIL_OPEN": "0"}):
            result = _PLUGIN._handle_hook_error(ctx, "pre_tool_call", exc)
        self.assertIsInstance(result, dict)
        assert result is not None
        self.assertEqual(result.get("action"), "block")

    def test_pre_tool_call_fail_open_when_enabled(self) -> None:
        ctx = mock.Mock()
        exc = RuntimeError("Orca binary not found or too old for Hermes hooks")
        with mock.patch.dict(os.environ, {"ORCA_HERMES_FAIL_OPEN": "1"}):
            with mock.patch("builtins.print") as printed:
                result = _PLUGIN._handle_hook_error(ctx, "pre_tool_call", exc)
        self.assertIsNone(result)
        # Degraded allow must not be silent.
        printed.assert_called()
        warn_text = " ".join(str(c) for c in printed.call_args_list)
        self.assertIn("FAIL-OPEN", warn_text)
        self.assertIn("ORCA_HERMES_FAIL_OPEN=0", warn_text)

    def test_pre_tool_call_blocks_policy_veto_decisions(self) -> None:
        for decision in ("block", "warn", "ask"):
            with self.subTest(decision=decision):
                ctx = mock.Mock()
                _PLUGIN._register(ctx, "pre_tool_call")
                handler = ctx.register_hook.call_args.args[1]
                with mock.patch.object(
                    _PLUGIN,
                    "_call_orca",
                    return_value={"decision": decision, "message": f"{decision} by Orca"},
                ):
                    result = handler(tool_name="terminal", args={"command": "rm -rf /"})
                self.assertEqual(
                    result,
                    {"action": "block", "message": f"{decision} by Orca"},
                )

    def test_pre_tool_call_surfaces_remediation_commands(self) -> None:
        ctx = mock.Mock()
        _PLUGIN._register(ctx, "pre_tool_call")
        handler = ctx.register_hook.call_args.args[1]
        with mock.patch.object(
            _PLUGIN,
            "_call_orca",
            return_value={
                "decision": "block",
                "message": "blocked by Orca",
                "rule_id": "core.filesystem:destructive_rm",
                "remediation_commands": ["orca explain \"rm -rf /\"", "orca allowlist list"],
            },
        ):
            result = handler(tool_name="terminal", args={"command": "rm -rf /"})
        self.assertEqual(result.get("action"), "block")
        message = result.get("message", "")
        self.assertIn("orca explain", message)
        self.assertIn("rule: core.filesystem:destructive_rm", message)

    def test_pre_tool_call_allows_only_explicit_allow(self) -> None:
        ctx = mock.Mock()
        _PLUGIN._register(ctx, "pre_tool_call")
        handler = ctx.register_hook.call_args.args[1]
        with mock.patch.object(_PLUGIN, "_call_orca", return_value={"decision": "allow"}):
            self.assertIsNone(handler(tool_name="terminal", args={"command": "git status"}))

        for malformed in ([], "error", "unexpected"):
            with self.subTest(decision=malformed):
                with mock.patch.object(_PLUGIN, "_call_orca", return_value={"decision": malformed}):
                    result = handler(tool_name="terminal", args={"command": "git status"})
                self.assertEqual(result.get("action"), "block")

    def test_pre_llm_call_remains_context_only_for_non_allowing_decisions(self) -> None:
        for decision in ("block", "warn", "ask"):
            with self.subTest(decision=decision):
                ctx = mock.Mock()
                _PLUGIN._register(ctx, "pre_llm_call")
                handler = ctx.register_hook.call_args.args[1]
                with mock.patch.object(
                    _PLUGIN,
                    "_call_orca",
                    return_value={"decision": decision, "message": f"{decision} by Orca"},
                ):
                    result = handler(session_id="session-1", user_message="review me")
                self.assertEqual(result, {"context": f"Orca policy note: {decision} by Orca"})


if __name__ == "__main__":
    unittest.main()
