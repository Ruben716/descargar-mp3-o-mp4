"""Casos de uso; dependen únicamente de los contratos del dominio."""
from pathlib import Path

from .domain import (
    DownloadOptions,
    DownloadRequest,
    DownloadResult,
    VideoDownloader,
    VideoInfo,
)


class DownloadVideo:
    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(self, url: str, destination: Path, options: DownloadOptions | None = None) -> DownloadResult:
        return self.downloader.download(DownloadRequest(url, destination, options or DownloadOptions()))


class InspectVideo:
    """Consulta los datos del video sin descargar nada."""

    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(self, url: str, destination: Path, options: DownloadOptions | None = None) -> VideoInfo:
        return self.downloader.inspect(DownloadRequest(url, destination, options or DownloadOptions()))
