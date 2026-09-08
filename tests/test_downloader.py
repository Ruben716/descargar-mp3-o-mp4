import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import Mock

from descargador.application import DownloadVideo
from descargador.cli import main
from descargador.domain import DownloadError, DownloadRequest, DownloadResult


class DownloadTests(unittest.TestCase):
    def test_rejects_invalid_urls_before_adapter(self):
        for url in ("", "hola", "file:///video.mp4", "ftp://example.com/a", "https://", "https://a:bad/v", "https://a/a b"):
            with self.subTest(url=url):
                adapter = Mock()
                with self.assertRaises(DownloadError):
                    DownloadVideo(adapter).execute(url, Path("out"))
                adapter.download.assert_not_called()

    def test_normalizes_url_and_passes_destination(self):
        adapter = Mock()
        adapter.download.return_value = DownloadResult((Path("out/video.mp4"),))
        result = DownloadVideo(adapter).execute("  https://example.com/v?a=1&b=2  ", Path("out"))
        adapter.download.assert_called_once_with(DownloadRequest("https://example.com/v?a=1&b=2", Path("out")))
        self.assertEqual(result.files, (Path("out/video.mp4"),))

    def test_cli_invalid_url_returns_failure_without_traceback(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            code = main(["incorrecta"])
        self.assertEqual(code, 1)
        self.assertIn("URL válida", output.getvalue())
        self.assertNotIn("Traceback", output.getvalue())


if __name__ == "__main__":
    unittest.main()
