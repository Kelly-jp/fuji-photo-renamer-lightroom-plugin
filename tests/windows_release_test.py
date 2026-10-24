"""Portable integrity tests; actual Windows execution is a separate CI job."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('windows_release', ROOT / 'scripts/verify-windows-release.py')
windows_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows_release)


class IntegrityTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.plugin = Path(self.work.name)
        (self.plugin / 'payload').write_bytes(b'original')
        self.manifest = {'platform': 'windows', 'arch': 'x64', 'files': [
            {'path': 'payload', 'sha256': hashlib.sha256(b'original').hexdigest()}]}
        self.save_manifest()

    def save_manifest(self):
        (self.plugin / 'PACKAGE_MANIFEST.json').write_text(json.dumps(self.manifest), encoding='utf-8')

    def test_accepts_exact_windows_payload(self):
        windows_release.verify_files(self.plugin)

    def test_rejects_changed_file(self):
        (self.plugin / 'payload').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'manifest'):
            windows_release.verify_files(self.plugin)

    def test_rejects_missing_file(self):
        (self.plugin / 'payload').unlink()
        with self.assertRaisesRegex(ValueError, 'manifest'):
            windows_release.verify_files(self.plugin)

    def test_rejects_extra_file(self):
        (self.plugin / 'unexpected').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'manifest'):
            windows_release.verify_files(self.plugin)

    def test_rejects_wrong_platform_or_architecture(self):
        for field, value in [('platform', 'macos'), ('arch', 'arm64')]:
            original = self.manifest[field]
            self.manifest[field] = value
            self.save_manifest()
            with self.assertRaisesRegex(ValueError, 'Windows x64'):
                windows_release.verify_files(self.plugin)
            self.manifest[field] = original


class ProcessTest(unittest.TestCase):
    def test_failure_includes_exit_code_and_captured_diagnostics(self):
        result = subprocess.CompletedProcess([], 1, 'launcher output', 'missing runtime detail')
        with patch.object(windows_release.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(RuntimeError, 'exit 1') as error:
                windows_release.run_tool(Path('tool.exe'), ['-ver'], {})
        self.assertIn('launcher output', str(error.exception))
        self.assertIn('missing runtime detail', str(error.exception))

    def test_success_returns_stdout_and_preserves_arguments(self):
        result = subprocess.CompletedProcess([], 0, '13.59\n', '')
        with patch.object(windows_release.subprocess, 'run', return_value=result) as run:
            self.assertEqual(windows_release.run_tool(Path('folder with spaces/tool.exe'), ['-ver'], {}), '13.59')
        self.assertEqual(run.call_args.args[0], [str(Path('folder with spaces/tool.exe')), '-config', '', '-ver'])


if __name__ == '__main__':
    unittest.main()
