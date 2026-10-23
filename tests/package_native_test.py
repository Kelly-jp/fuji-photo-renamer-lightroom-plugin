"""Read actual OS ZIPs and exercise only the bundled macOS runtime on temporary fixtures."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("archive", ROOT / "scripts/archive.py")
archive = importlib.util.module_from_spec(spec); spec.loader.exec_module(archive)


class PackageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != "darwin": raise RuntimeError("Native package tests require an Apple Silicon Mac")
        cls.work = tempfile.TemporaryDirectory(prefix="fuji-package-native-")
        cls.folder = Path(cls.work.name) / "日本語 plugin's folder"
        archive.extract(MAC_ZIP, cls.folder)
        cls.plugin = cls.folder / "FujiPhotoRenamer.lrplugin"
        cls.tool = cls.plugin / "vendor/macos/exiftool"
        cls.perl = cls.plugin / "vendor/macos/runtime/arm64/bin/perl"
        cls.env = {**os.environ, "PATH": "/nonexistent", "PERL5OPT": "-MNonexistentModule", "PERL5LIB": "/nonexistent/lib"}

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def tool_run(self, *args):
        return subprocess.run([str(self.tool), "-config", "", *args], check=True, capture_output=True,
                              text=True, env=self.env, timeout=60).stdout.strip()

    def check_zip(self, filename, platform):
        digest = hashlib.sha256(filename.read_bytes()).hexdigest()
        self.assertEqual(Path(str(filename) + ".sha256").read_text().split()[0], digest)
        with zipfile.ZipFile(filename) as data:
            names = data.namelist(); prefix = "FujiPhotoRenamer.lrplugin/"
            self.assertEqual(len(names), len(set(names)))
            self.assertTrue(all(n.startswith(prefix) for n in names))
            manifest = json.loads(data.read(prefix + "PACKAGE_MANIFEST.json"))
            self.assertEqual(manifest["platform"], platform)
            expected = {prefix + entry["path"] for entry in manifest["files"]} | {prefix + "PACKAGE_MANIFEST.json"}
            self.assertEqual(set(names), expected)
            for entry in manifest["files"]:
                name = prefix + entry["path"]
                self.assertEqual(hashlib.sha256(data.read(name)).hexdigest(), entry["sha256"], name)
                self.assertEqual(bool((data.getinfo(name).external_attr >> 16) & 0o111), entry["executable"], name)
            self.assertFalse(any("/tests/" in n or "/fixtures/" in n or "/.cache/" in n for n in names))
            self.assertIn(prefix + "THIRD_PARTY_NOTICES/dkjson-LICENSE.txt", names)
            self.assertIn(prefix + "THIRD_PARTY_NOTICES/ExifTool-README.txt", names)
            self.assertIn(prefix + "THIRD_PARTY_NOTICES/Perl-Artistic.txt", names)
            self.assertIn(prefix + "THIRD_PARTY_NOTICES.md", names)
            if platform == "windows":
                self.assertFalse(any("/vendor/macos/" in n for n in names))
                for name in ("exiftool.exe", "exiftool_files/LICENSE", "exiftool_files/Licenses_Strawberry_Perl.zip"):
                    self.assertIn(prefix + "vendor/windows/" + name, names)
            else:
                self.assertEqual(manifest["arch"], "arm64")
                self.assertFalse(any("/vendor/windows/" in n or "/runtime/x64/" in n for n in names))
        return manifest

    def test_macos_archive_structure_hashes_licenses_and_permissions(self):
        self.check_zip(MAC_ZIP, "macos")

    def test_windows_archive_structure_hashes_and_licenses_without_executing_windows_code(self):
        self.check_zip(WIN_ZIP, "windows")

    def test_relocated_bundle_uses_fixed_version_without_path_or_external_perl_settings(self):
        self.assertEqual(self.tool_run("-ver"), "13.59")
        result = subprocess.run([str(self.perl), "-e", "print $^V"], check=True, capture_output=True, text=True,
                                env={"PATH": "/nonexistent", "LC_ALL": "C"}, timeout=30)
        self.assertEqual(result.stdout, "v5.44.0")
        result = subprocess.run([str(self.perl), "-e", 'print join("\n", @INC)'], check=True, capture_output=True,
                                text=True, env={"PATH": "/nonexistent", "LC_ALL": "C"}, timeout=30)
        runtime = self.perl.parent.parent.resolve()
        self.assertTrue(all(Path(item).resolve().is_relative_to(runtime) for item in result.stdout.splitlines()))

    def test_every_native_runtime_file_has_a_valid_adhoc_signature(self):
        manifest = json.loads((self.plugin / "PACKAGE_MANIFEST.json").read_text())
        signing = manifest["macosSigning"]
        self.assertEqual(signing["type"], "ad-hoc"); self.assertEqual(signing["identity"], "-")
        self.assertFalse(signing["notarized"])
        magic = {bytes.fromhex(value) for value in ("feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
        native = []
        for path in (self.plugin / "vendor/macos/runtime/arm64").rglob("*"):
            if not path.is_file(): continue
            with path.open("rb") as handle: header = handle.read(4)
            if header in magic: native.append(str(path.relative_to(self.plugin)))
        self.assertEqual(set(signing["files"]), set(native)); self.assertTrue(native)
        for name in native:
            subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(self.plugin / name)], check=True, capture_output=True, timeout=30)
            result = subprocess.run(["/usr/bin/codesign", "-d", "--verbose=4", str(self.plugin / name)], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn("Signature=adhoc", result.stderr)
            self.assertIn("TeamIdentifier=not set", result.stderr)

    def test_reads_japanese_spaced_and_quoted_path_without_modifying_the_input(self):
        file = Path(self.work.name) / "写真's input.jpg"
        before = (ROOT / "fixtures/metadata/phase2-sample.jpg").read_bytes(); file.write_bytes(before)
        result = json.loads(self.tool_run("-charset", "filename=UTF8", "-j", "-G1", "-s", "-Make", "-Model", "--", str(file)))
        self.assertEqual(result[0]["IFD0:Make"], "FUJIFILM")
        self.assertEqual(file.read_bytes(), before)

    def test_reads_xmp_and_removes_only_synthetic_jumbf_on_an_owned_copy(self):
        xmp = ROOT / "fixtures/metadata/phase2-lightroom-look.xmp"; before = xmp.read_bytes()
        result = json.loads(self.tool_run("-j", "-G1", "-s", "-XMP-crs:LookName", "--", str(xmp)))
        self.assertEqual(result[0]["XMP-crs:LookName"], "Camera CLASSIC Neg")
        self.assertEqual(xmp.read_bytes(), before)
        jpeg = (ROOT / "fixtures/metadata/phase2-sample.jpg").read_bytes()
        def box(kind, data): return (len(data) + 8).to_bytes(4, "big") + kind + data
        body = box(b"jumb", box(b"jumd", b"c2pa" + b"\0" * 12 + b"\2c2pa\0") + box(b"json", b"{}"))
        packet = b"JP\x00\x01\x00\x00\x00\x01" + body
        segment = b"\xff\xeb" + (len(packet) + 2).to_bytes(2, "big") + packet
        rendered = Path(self.work.name) / "owned-render.jpg"; original = jpeg[:2] + segment + jpeg[2:]
        rendered.write_bytes(original); cleaned = Path(self.work.name) / "cleaned.jpg"
        self.tool_run("-o", str(cleaned), "-jumbf:all=", "--", str(rendered))
        self.assertEqual(cleaned.read_bytes(), jpeg); self.assertEqual(rendered.read_bytes(), original)

    def test_readonly_plugin_directory_can_start_the_bundle(self):
        paths = [self.plugin, *self.plugin.rglob("*")]
        modes = [(path, path.stat().st_mode & 0o777) for path in paths]
        try:
            for path, mode in modes: path.chmod(mode & ~0o222)
            self.assertEqual(self.tool_run("-ver"), "13.59")
        finally:
            for path, mode in modes: path.chmod(mode)


if __name__ == "__main__":
    if len(sys.argv) != 3: raise SystemExit("Pass macOS ZIP and Windows ZIP paths explicitly")
    MAC_ZIP, WIN_ZIP = [Path(p).resolve() for p in sys.argv[1:]]
    unittest.main(argv=[sys.argv[0]])
