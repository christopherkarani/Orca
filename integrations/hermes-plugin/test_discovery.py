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
            self.assertTrue(_PLUGIN._fail_open_enabled())
        with mock.patch.dict(os.environ, {"ORCA_HERMES_FAIL_OPEN": "0"}):
            self.assertFalse(_PLUGIN._fail_open_enabled())

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
            result = _PLUGIN._handle_hook_error(ctx, "pre_tool_call", exc)
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
