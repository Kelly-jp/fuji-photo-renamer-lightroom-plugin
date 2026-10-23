import importlib.util
import io
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("archive", Path(__file__).resolve().parents[1] / "scripts/archive.py")
archive = importlib.util.module_from_spec(spec); spec.loader.exec_module(archive)


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="fuji-archive-test-")
        self.root = Path(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def test_zip_contains_only_plugin_root_and_preserves_execute_permissions(self):
        plugin = self.root / "FujiPhotoRenamer.lrplugin"; plugin.mkdir()
        (plugin / "Info.lua").write_text("return {}")
        launcher = plugin / "exiftool"; launcher.write_text("#!/bin/sh\n"); launcher.chmod(0o755)
        output = self.root / "plugin.zip"; archive.create_zip(plugin, output)
        with zipfile.ZipFile(output) as data:
            self.assertEqual(data.namelist(), ["FujiPhotoRenamer.lrplugin/Info.lua", "FujiPhotoRenamer.lrplugin/exiftool"])
            self.assertEqual((data.getinfo("FujiPhotoRenamer.lrplugin/exiftool").external_attr >> 16) & 0o777, 0o755)
        archive.extract(output, self.root / "extracted")
        self.assertEqual((self.root / "extracted/FujiPhotoRenamer.lrplugin/Info.lua").read_text(), "return {}")

    def test_same_input_produces_same_zip_bytes_regardless_of_mtime(self):
        plugin = self.root / "FujiPhotoRenamer.lrplugin"; plugin.mkdir()
        file = plugin / "Info.lua"; file.write_text("return {}")
        archive.create_zip(plugin, self.root / "one.zip")
        import os
        os.utime(file, (2000000000, 2000000000))
        archive.create_zip(plugin, self.root / "two.zip")
        self.assertEqual((self.root / "one.zip").read_bytes(), (self.root / "two.zip").read_bytes())

    def test_never_replaces_existing_zip_or_extract_directory(self):
        plugin = self.root / "FujiPhotoRenamer.lrplugin"; plugin.mkdir()
        output = self.root / "existing.zip"; output.write_bytes(b"existing")
        with self.assertRaises(FileExistsError): archive.create_zip(plugin, output)
        self.assertEqual(output.read_bytes(), b"existing")
        with self.assertRaises(FileExistsError): archive.extract(output, plugin)

    def test_zip_traversal_is_rejected_without_writing_outside_destination(self):
        for index, name in enumerate(("../escape", "/absolute", "C:/drive", "a\\..\\escape", "line\nname")):
            output = self.root / f"bad{index}.zip"
            with zipfile.ZipFile(output, "w") as data: data.writestr(name, "bad")
            with self.assertRaises(ValueError): archive.extract(output, self.root / f"out{index}")
        self.assertFalse((self.root / "escape").exists())

    def test_zip_symlinks_and_duplicate_entries_are_rejected(self):
        output = self.root / "link.zip"
        info = zipfile.ZipInfo("link"); info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(output, "w") as data: data.writestr(info, "../escape")
        with self.assertRaises(ValueError): archive.extract(output, self.root / "link-out")
        output = self.root / "duplicate.zip"
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(output, "w") as data:
                data.writestr("same", "one"); data.writestr("same", "two")
        with self.assertRaises(ValueError): archive.extract(output, self.root / "duplicate-out")

    def test_tar_traversal_and_links_are_rejected(self):
        for index, (name, kind) in enumerate((("../escape", tarfile.REGTYPE), ("link", tarfile.SYMTYPE), ("hard", tarfile.LNKTYPE))):
            output = self.root / f"bad{index}.tar.gz"
            info = tarfile.TarInfo(name); info.type = kind
            if kind == tarfile.REGTYPE: info.size = 3
            else: info.linkname = "../escape"
            with tarfile.open(output, "w:gz") as data: data.addfile(info, io.BytesIO(b"bad") if kind == tarfile.REGTYPE else None)
            with self.assertRaises(ValueError): archive.extract(output, self.root / f"tar-out{index}")
        self.assertFalse((self.root / "escape").exists())

    def test_packaging_refuses_symlinks(self):
        plugin = self.root / "FujiPhotoRenamer.lrplugin"; plugin.mkdir()
        (plugin / "alias").symlink_to("../private")
        with self.assertRaises(ValueError): archive.create_zip(plugin, self.root / "plugin.zip")

    def test_regular_tar_preserves_bytes_and_execute_permissions(self):
        output = self.root / "good.tar.gz"
        info = tarfile.TarInfo("tool/exiftool"); info.size = 4; info.mode = 0o755
        with tarfile.open(output, "w:gz") as data: data.addfile(info, io.BytesIO(b"data"))
        archive.extract(output, self.root / "out")
        self.assertEqual((self.root / "out/tool/exiftool").read_bytes(), b"data")
        self.assertEqual((self.root / "out/tool/exiftool").stat().st_mode & 0o777, 0o755)


if __name__ == "__main__": unittest.main()
