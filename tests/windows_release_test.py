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
    def test_failure_includes_runner_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory) / 'work'

            def execute(*args, **kwargs):
                (work / 'exit-code.txt').write_text('1', encoding='utf-8')
                (work / 'stderr.txt').write_text('missing runtime detail', encoding='utf-8')
                return subprocess.CompletedProcess([], 1, '', '')

            with patch.object(windows_release.subprocess, 'run', side_effect=execute):
                with self.assertRaisesRegex(RuntimeError, 'missing runtime detail'):
                    windows_release.run_runner(Path(directory), Path('tool.exe'), work, ['-ver'], {'SYSTEMROOT': '/windows'})

    def test_success_preserves_utf8_argument_file_and_reads_status(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory) / 'work'

            def execute(*args, **kwargs):
                (work / 'exit-code.txt').write_text('0', encoding='utf-8')
                (work / 'stdout.json').write_text('13.59\n', encoding='utf-8')
                return subprocess.CompletedProcess([], 0, '', '')

            with patch.object(windows_release.subprocess, 'run', side_effect=execute):
                output = windows_release.run_runner(Path(directory), Path('folder with spaces/tool.exe'), work,
                                                    ['-j', '写真.jpg'], {'SYSTEMROOT': '/windows'})
            self.assertEqual(output, '13.59')
            self.assertEqual((work / 'arguments.txt').read_text(encoding='utf-8'), '-j\n写真.jpg\n')


if __name__ == '__main__':
    unittest.main()
