#!/usr/bin/env python3
"""Run each Lua 5.1 test file in a separate process, without private photo inputs."""
import argparse
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    "core": [
        "filename_safety_test", "jpeg_integrity_test", "manufacturer_normalizer_test",
        "metadata_resolver_test", "template_engine_test",
    ],
    "sdk": [
        "export_artifact_test", "export_dialog_test", "export_pipeline_test",
        "export_preview_test", "metadata_reader_test", "metadata_source_resolver_test",
        "phase1_provider_test",
    ],
    "native": [
        "c2pa_native_test", "exiftool_read_test", "export_pipeline_native_test",
        "metadata_resolver_native_test", "metadata_source_resolver_native_test",
    ],
}


def execute(command, timeout):
    # An argument array keeps paths with spaces and shell metacharacters as data.
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)


def require_success(result, label):
    if result.returncode:
        raise ValueError(f"{label} failed (exit {result.returncode}):\n{result.stdout}{result.stderr}")


def run(args):
    groups = list(SUITES) if args.suite == "all" else [args.suite]
    if "native" in groups:
        if sys.platform != "darwin":
            raise ValueError("Native tests currently require macOS; SDK doubles are separate.")
        if not args.exiftool or not Path(args.exiftool).is_absolute():
            raise ValueError("Native tests require --exiftool with an explicit absolute path.")
        tool = execute([args.exiftool, "-config", "", "-ver"], args.timeout)
        require_success(tool, "ExifTool version check")
        print("ExifTool: " + tool.stdout.strip(), flush=True)
    version = execute([args.lua, "-v"], args.timeout)
    require_success(version, "Lua version check")
    if not re.search(r"\bLua 5\.1(?:\.|\s)", version.stdout + version.stderr):
        raise ValueError("Use Lua 5.1; other Lua versions are not the tested runtime.")
    print((version.stdout + version.stderr).strip(), flush=True)
    compiler = execute([args.luac, "-v"], args.timeout)
    require_success(compiler, "luac version check")
    if not re.search(r"\bLua 5\.1(?:\.|\s)", compiler.stdout + compiler.stderr):
        raise ValueError("Use luac 5.1 for syntax checks.")
    syntax_files = sorted((ROOT / "src").rglob("*.lua")) + sorted((ROOT / "tests").rglob("*.lua"))
    for path in syntax_files:
        checked = execute([args.luac, "-p", str(path)], args.timeout)
        require_success(checked, f"Syntax: {path.relative_to(ROOT)}")
    print(f"Syntax: {len(syntax_files)} Lua files passed", flush=True)
    tests = []
    for group in groups:
        directory = "core" if group == "core" else "integration"
        tests.extend((group, f"tests/{directory}/{name}.lua") for name in SUITES[group])
    if args.shuffle_seed is not None:
        random.Random(args.shuffle_seed).shuffle(tests)
        print(f"Test order seed: {args.shuffle_seed}", flush=True)
    failures, total = [], 0
    for group, path in tests:
        command = [args.lua, path]
        if group == "native" and not path.endswith("metadata_source_resolver_native_test.lua"):
            command.append(args.exiftool)
        try:
            result = execute(command, args.timeout)
            summaries = re.findall(r"^(\d+) [^\n]*tests passed[^\n]*$", result.stdout, re.MULTILINE)
            if result.returncode or not summaries or int(summaries[-1]) < 1:
                failures.append(path)
                print(f"FAIL {path}\n{result.stdout}{result.stderr}", flush=True)
            else:
                total += int(summaries[-1])
                print(f"PASS {path}: {summaries[-1]} cases", flush=True)
        except (OSError, subprocess.TimeoutExpired) as error:
            failures.append(path)
            print(f"FAIL {path}: {error}", flush=True)
    print(f"{total} cases passed; {len(tests) - len(failures)}/{len(tests)} test files passed.")
    if failures:
        print("Failed files: " + ", ".join(failures))
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default="lua", help="Lua 5.1 executable name or path")
    parser.add_argument("--luac", default="luac", help="Lua 5.1 compiler name or path")
    parser.add_argument("--suite", choices=["all", *SUITES], default="all")
    parser.add_argument("--exiftool", help="Explicit absolute path; required for native/all")
    parser.add_argument("--shuffle-seed", type=int, help="Reproducible test-file order")
    parser.add_argument("--timeout", type=int, default=180, help="Per-process limit in seconds")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    try:
        return run(args)
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"Preflight failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
