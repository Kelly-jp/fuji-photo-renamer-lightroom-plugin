#!/usr/bin/env python3
"""Build helper: extract verified archives safely and write deterministic ZIPs."""
import argparse
from pathlib import Path, PurePosixPath
import shutil
import stat
import tarfile
import zipfile


def safe_name(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or ".." in path.parts or "\\" in name
            or ":" in name or any(ord(c) < 32 for c in name)):
        raise ValueError(f"Unsafe archive path: {name!r}")
    return path


def extract(archive, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    seen, total = set(), 0

    def target(name, size):
        nonlocal total
        path = safe_name(name)
        if str(path) in seen:
            raise ValueError(f"Duplicate archive entry: {name}")
        seen.add(str(path)); total += size
        if total > 1024 * 1024 * 1024 or len(seen) > 100000:
            raise ValueError("Archive expansion limit exceeded")
        return destination.joinpath(*path.parts)

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as source:
            for member in source.infolist():
                mode = member.external_attr >> 16
                if stat.S_ISLNK(mode) or stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                    raise ValueError(f"Unsupported ZIP entry: {member.filename}")
                output = target(member.filename, member.file_size)
                if member.is_dir():
                    output.mkdir(parents=True, exist_ok=True)
                else:
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with source.open(member) as data, output.open("xb") as handle:
                        shutil.copyfileobj(data, handle)
                    output.chmod(0o755 if mode & 0o111 else 0o644)
    else:
        with tarfile.open(archive, "r:gz") as source:
            for member in source:
                if not member.isfile() and not member.isdir():
                    raise ValueError(f"Unsupported TAR entry: {member.name}")
                output = target(member.name, member.size)
                if member.isdir():
                    output.mkdir(parents=True, exist_ok=True)
                else:
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with source.extractfile(member) as data, output.open("xb") as handle:
                        shutil.copyfileobj(data, handle)
                    output.chmod(0o755 if member.mode & 0o111 else 0o644)


def create_zip(directory, output):
    directory = Path(directory)
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("ZIP input must be a real directory")
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(directory.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Symlinks are not packaged: {path}")
            if path.is_dir():
                continue
            if not path.is_file():
                raise ValueError(f"Unsupported package file: {path}")
            name = str(PurePosixPath(directory.name, *path.relative_to(directory).parts))
            safe_name(name)
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("extract", "zip"))
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    if args.action == "extract":
        extract(args.source, args.destination)
    else:
        create_zip(args.source, args.destination)


if __name__ == "__main__":
    main()
