"""Test runner failure reporting, isolation and command construction without external tools."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("run_tests", Path(__file__).resolve().parents[1] / "scripts/run-tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self.args = SimpleNamespace(suite="core", lua="/tools/Lua 5.1/lua", luac="/tools/Lua 5.1/luac",
                                    exiftool="/tools/Exif Tool/exiftool", timeout=180, shuffle_seed=None)
        self.commands = []

    def execute(self, command, timeout):
        self.commands.append(command)
        if command[-1] == "-v":
            return subprocess.CompletedProcess(command, 0, "", "Lua 5.1.5\n")
        if command[-1] == "-ver":
            return subprocess.CompletedProcess(command, 0, "13.55\n", "")
        if "-p" in command:
            return subprocess.CompletedProcess(command, 0, "", "")
        return subprocess.CompletedProcess(command, 0, "2 fixture tests passed.\n", "")

    def run_with(self, callback=None):
        with patch.object(runner, "execute", side_effect=callback or self.execute), contextlib.redirect_stdout(io.StringIO()):
            return runner.run(self.args)

    def test_each_file_runs_in_a_separate_process(self):
        self.assertEqual(self.run_with(), 0)
        tests = [c for c in self.commands if c[1].endswith("_test.lua")]
        self.assertEqual(len(tests), len(runner.SUITES["core"]))
        self.assertTrue(all(len(c) == 2 for c in tests))

    def test_every_lua_test_is_in_the_suite_inventory(self):
        listed = {f"tests/{'core' if group == 'core' else 'integration'}/{name}.lua"
                  for group, names in runner.SUITES.items() for name in names}
        discovered = {str(p.relative_to(runner.ROOT)) for p in (runner.ROOT / "tests").rglob("*_test.lua")}
        self.assertEqual(listed, discovered)

    def test_rejects_wrong_runtime_before_tests(self):
        with self.assertRaisesRegex(ValueError, "Lua 5.1"):
            self.run_with(lambda c, t: subprocess.CompletedProcess(c, 0, "Lua 5.4.8", ""))

    def test_rejects_wrong_compiler(self):
        def callback(c, t):
            if c[0] == self.args.luac:
                return subprocess.CompletedProcess(c, 0, "Lua 5.4.8", "")
            return self.execute(c, t)
        with self.assertRaisesRegex(ValueError, "luac 5.1"):
            self.run_with(callback)

    def test_syntax_error_stops_before_running_test_files(self):
        def callback(c, t):
            if "-p" in c:
                return subprocess.CompletedProcess(c, 1, "", "syntax error")
            return self.execute(c, t)
        with self.assertRaisesRegex(ValueError, "syntax error"):
            self.run_with(callback)
        self.assertFalse(any(c[1].endswith("_test.lua") for c in self.commands))

    def test_native_requires_explicit_absolute_tool_path(self):
        self.args.suite = "native"
        for tool in (None, "relative-exiftool"):
            self.args.exiftool = tool
            with patch.object(sys, "platform", "darwin"), self.assertRaisesRegex(ValueError, "absolute path"):
                self.run_with()

    def test_native_does_not_claim_windows_support(self):
        self.args.suite = "native"
        with patch.object(sys, "platform", "win32"), self.assertRaisesRegex(ValueError, "macOS"):
            self.run_with()

    def test_invalid_native_tool_fails_preflight(self):
        self.args.suite = "native"
        with patch.object(sys, "platform", "darwin"), self.assertRaisesRegex(ValueError, "ExifTool version"):
            self.run_with(lambda c, t: subprocess.CompletedProcess(c, 7, "", "bad tool"))

    def test_nonzero_exit_is_failure_even_with_success_text_and_remaining_files_run(self):
        def callback(c, t):
            if c[1].endswith("filename_safety_test.lua"):
                self.commands.append(c)
                return subprocess.CompletedProcess(c, 1, "2 tests passed.\n", "failure")
            return self.execute(c, t)
        self.assertEqual(self.run_with(callback), 1)
        self.assertEqual(sum(c[1].endswith("_test.lua") for c in self.commands), len(runner.SUITES["core"]))

    def test_zero_exit_without_test_summary_is_failure(self):
        def callback(c, t):
            if c[1].endswith("filename_safety_test.lua"):
                return subprocess.CompletedProcess(c, 0, "No tests ran", "")
            return self.execute(c, t)
        self.assertEqual(self.run_with(callback), 1)

    def test_zero_executed_cases_is_failure(self):
        def callback(c, t):
            if c[1].endswith("filename_safety_test.lua"):
                return subprocess.CompletedProcess(c, 0, "0 fixture tests passed.\n", "")
            return self.execute(c, t)
        self.assertEqual(self.run_with(callback), 1)

    def test_timeout_and_missing_executable_are_reported_as_failure(self):
        for error in (subprocess.TimeoutExpired(["lua"], 180), FileNotFoundError("missing lua")):
            def callback(c, t):
                if c[1].endswith("filename_safety_test.lua"):
                    raise error
                return self.execute(c, t)
            self.assertEqual(self.run_with(callback), 1)

    def test_shuffle_order_is_reproducible(self):
        self.args.shuffle_seed = 11
        self.run_with(); first = [c for c in self.commands if c[1].endswith("_test.lua")]
        self.commands = []; self.run_with()
        self.assertEqual(first, [c for c in self.commands if c[1].endswith("_test.lua")])

    def test_command_paths_remain_arguments_and_execution_uses_repository_root(self):
        command = ["/tools/Lua 5.1/lua", "a;$(name).lua"]
        with patch.object(subprocess, "run") as run:
            runner.execute(command, 9)
        run.assert_called_once_with(command, cwd=runner.ROOT, capture_output=True, text=True, timeout=9)


if __name__ == "__main__":
    unittest.main()
