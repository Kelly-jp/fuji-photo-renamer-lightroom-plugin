#!/usr/bin/env python3
"""Cache pinned release sources via standard HTTPS, independent of Node's HTTP parser."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def cache_source(source, directory):
    name = source['filename']
    if (not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name)
            or not re.fullmatch(r'[a-f0-9]{64}', source['sha256'])
            or not source['url'].startswith('https://')):
        raise ValueError('Invalid pinned source')
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / name
    if target.is_symlink():
        raise ValueError('Cache must be a regular file')
    if target.exists():
        if not target.is_file() or digest(target) != source['sha256']:
            raise ValueError('Cached SHA-256 mismatch: ' + name)
        return target
    partial = directory / f'{name}.{os.getpid()}.partial'
    created = False
    try:
        with partial.open('xb') as output:
            created = True
            with urllib.request.urlopen(source['url'], timeout=120) as response:
                shutil.copyfileobj(response, output)
        if digest(partial) != source['sha256']:
            raise ValueError('Downloaded SHA-256 mismatch: ' + name)
        # Link publication preserves an existing file from another process instead of replacing it.
        os.link(partial, target)
        return target
    finally:
        if created:
            partial.unlink()


def main():
    sources = json.loads((ROOT / 'scripts/exiftool-lock.json').read_text(encoding='utf-8'))['sources']
    for source in sources.values():
        cached = cache_source(source, ROOT / '.cache/downloads')
        print('Verified cache: ' + cached.name)


if __name__ == '__main__':
    main()
