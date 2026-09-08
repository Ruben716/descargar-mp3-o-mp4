"""Modelos y contratos independientes de la consola y de yt-dlp."""
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit


class DownloadError(Exception):
    """Error esperado que puede mostrarse al usuario."""


@dataclass(frozen=True)
class DownloadRequest:
    url: str
    destination: Path
    audio_only: bool = False

    def __post_init__(self):
        url = self.url.strip()
        try:
            parsed = urlsplit(url)
            valid = parsed.scheme in {"https", "http"} and parsed.hostname and parsed.port != 0
        except ValueError:
            valid = False
        if not valid or any(c.isspace() or ord(c) < 32 for c in url):
            raise DownloadError("Introduce una URL válida que empiece por https:// o http://.")
        object.__setattr__(self, "url", url)


@dataclass(frozen=True)
class DownloadResult:
    files: tuple[Path, ...]


class VideoDownloader(Protocol):
    def download(self, request: DownloadRequest) -> DownloadResult: ...
