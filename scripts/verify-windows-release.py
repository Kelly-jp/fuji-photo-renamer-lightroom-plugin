#!/usr/bin/env python3
"""Exercise the actual bundled Windows ExifTool without Lightroom or external Perl."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
from archive import extract

ROOT = Path(__file__).resolve().parents[1]


def run_tool(tool, arguments, env):
    result = subprocess.run([str(tool), '-config', '', *arguments], env=env,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60)
    if result.returncode:
        raise RuntimeError(f'Bundled ExifTool failed (exit {result.returncode}).\n'
                           f'stdout: {result.stdout[-8000:]}\nstderr: {result.stderr[-8000:]}')
    return result.stdout.strip()


def run_runner(plugin, tool, work, arguments, env):
    work.mkdir()
    (work / 'arguments.txt').write_text('\n'.join(arguments) + '\n', encoding='utf-8')
    powershell = Path(env['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    result = subprocess.run([str(powershell), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                             str(plugin / 'infrastructure/ExifToolRead.ps1'), '-Executable', str(tool),
                             '-WorkDirectory', str(work), '-TimeoutSeconds', '60'],
                            env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=80)
    status = work / 'exit-code.txt'
    if result.returncode or not status.exists() or status.read_text(encoding='utf-8-sig').strip() != '0':
        error = work / 'stderr.txt'
        detail = error.read_text(encoding='utf-8-sig') if error.exists() else result.stderr
        raise RuntimeError(f'Windows plugin runner failed (exit {result.returncode}): {detail}')
    return (work / 'stdout.json').read_text(encoding='utf-8-sig').strip()


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
        fixture = Path(work) / '写真 sample.jpg'
        shutil.copyfile(ROOT / 'fixtures/metadata/phase2-sample.jpg', fixture)
        before = hashlib.sha256(fixture.read_bytes()).hexdigest()
        calls = 0

        def run(*arguments):
            nonlocal calls
            calls += 1
            return run_runner(plugin, tool, Path(work) / f'日本語 work {calls}', arguments, env)

        if run('-ver') != lock['exiftoolVersion']:
            raise ValueError('Unexpected bundled ExifTool version')
        metadata = json.loads(run('-j', '-Make', '-Model', str(fixture)))[0]
        if metadata.get('Make') != 'FUJIFILM' or metadata.get('Model') != 'X-H2S':
            raise ValueError('Bundled ExifTool did not read the JPEG fixture')
        if before != hashlib.sha256(fixture.read_bytes()).hexdigest():
            raise ValueError('Input JPEG changed')
        print('Windows plugin runner: Unicode installation/work/photo paths, bundled version, JPEG read and input hash passed.')


if __name__ == '__main__':
    main()
