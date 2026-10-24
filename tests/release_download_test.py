import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_download', ROOT / 'scripts/cache-release-sources.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DownloadTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.directory = Path(self.work.name)
        self.payload = b'official fixture bytes'
        self.source = {'filename': 'fixture.zip', 'sha256': hashlib.sha256(self.payload).hexdigest(),
                       'url': 'https://example.invalid/fixture.zip'}

    def test_verified_download_preserves_bytes_and_cleans_partial(self):
        with patch.object(module.urllib.request, 'urlopen', return_value=io.BytesIO(self.payload)):
            target = module.cache_source(self.source, self.directory)
        self.assertEqual(target.read_bytes(), self.payload)
        self.assertEqual(list(self.directory.iterdir()), [target])

    def test_verified_cache_does_not_access_network(self):
        (self.directory / 'fixture.zip').write_bytes(self.payload)
        with patch.object(module.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            module.cache_source(self.source, self.directory)

    def test_bad_cache_is_not_overwritten_or_refetched(self):
        target = self.directory / 'fixture.zip'
        target.write_bytes(b'wrong')
        with patch.object(module.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            with self.assertRaisesRegex(ValueError, 'Cached SHA-256'):
                module.cache_source(self.source, self.directory)
        self.assertEqual(target.read_bytes(), b'wrong')

    def test_bad_download_is_not_published(self):
        with patch.object(module.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong')):
            with self.assertRaisesRegex(ValueError, 'Downloaded SHA-256'):
                module.cache_source(self.source, self.directory)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_http_failure_cleans_owned_partial(self):
        with patch.object(module.urllib.request, 'urlopen', side_effect=urllib.error.URLError('offline')):
            with self.assertRaises(urllib.error.URLError):
                module.cache_source(self.source, self.directory)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_preexisting_partial_is_not_deleted(self):
        partial = self.directory / f'fixture.zip.{os.getpid()}.partial'
        partial.write_bytes(b'preexisting')
        with self.assertRaises(FileExistsError):
            module.cache_source(self.source, self.directory)
        self.assertEqual(partial.read_bytes(), b'preexisting')

    def test_concurrent_published_file_is_not_overwritten(self):
        target = self.directory / 'fixture.zip'

        def response(*args, **kwargs):
            target.write_bytes(b'other process')
            return io.BytesIO(self.payload)

        with patch.object(module.urllib.request, 'urlopen', side_effect=response):
            with self.assertRaises(FileExistsError):
                module.cache_source(self.source, self.directory)
        self.assertEqual(target.read_bytes(), b'other process')
        self.assertEqual(list(self.directory.iterdir()), [target])

    def test_invalid_source_is_rejected(self):
        for field, value in [('filename', '../escape'), ('url', 'http://example.invalid/file'), ('sha256', 'bad')]:
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, 'Invalid pinned'):
                    module.cache_source({**self.source, field: value}, self.directory)


if __name__ == '__main__':
    unittest.main()
