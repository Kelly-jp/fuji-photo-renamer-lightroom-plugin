#!/usr/bin/env python3
"""Exercise the actual bundled Windows ExifTool without Lightroom or external Perl."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from archive import extract

ROOT = Path(__file__).resolve().parents[1]


def verify_files(plugin):
    manifest = json.loads((plugin / 'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
    if manifest['platform'] != 'windows' or manifest['arch'] != 'x64':
        raise ValueError('Expected a Windows x64 package')
    expected = {entry['path']: entry['sha256'] for entry in manifest['files']}
    actual = {p.relative_to(plugin).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in plugin.rglob('*') if p.is_file() and p.name != 'PACKAGE_MANIFEST.json'}
    if expected != actual:
        raise ValueError('Windows payload differs from its manifest')


def main():
    if sys.platform != 'win32':
        raise ValueError('Run this smoke test on Windows x64')
    if len(sys.argv) != 2:
        raise ValueError('Pass the Windows release ZIP path')
    lock = json.loads((ROOT / 'scripts/exiftool-lock.json').read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='fuji-release-') as work:
        target = Path(work) / "日本語 plugin's folder"
        extract(Path(sys.argv[1]), target)
        plugin = target / 'FujiPhotoRenamer.lrplugin'
        verify_files(plugin)
        tool = plugin / 'vendor/windows/exiftool.exe'
        env = {key: value for key, value in os.environ.items() if not key.upper().startswith('PERL')}
        env['PATH'] = ''
        fixture = ROOT / 'fixtures/metadata/phase2-sample.jpg'
        before = hashlib.sha256(fixture.read_bytes()).hexdigest()

        def run(*arguments):
            return subprocess.run([str(tool), '-config', '', *arguments], env=env, check=True,
                                  capture_output=True, text=True, encoding='utf-8', timeout=60).stdout.strip()

        if run('-ver') != lock['exiftoolVersion']:
            raise ValueError('Unexpected bundled ExifTool version')
        metadata = json.loads(run('-j', '-Make', '-Model', str(fixture)))[0]
        if metadata.get('Make') != 'FUJIFILM' or metadata.get('Model') != 'X-H2S':
            raise ValueError('Bundled ExifTool did not read the JPEG fixture')
        if before != hashlib.sha256(fixture.read_bytes()).hexdigest():
            raise ValueError('Input JPEG changed')
        print('Windows bundled ExifTool: version, JPEG read and input hash passed.')


if __name__ == '__main__':
    main()
