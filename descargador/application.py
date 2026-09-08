"""Caso de uso; depende únicamente del contrato del dominio."""
from pathlib import Path
from .domain import DownloadRequest, DownloadResult, VideoDownloader


class DownloadVideo:
    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(self, url: str, destination: Path, *, audio_only: bool = False) -> DownloadResult:
        return self.downloader.download(DownloadRequest(url, destination, audio_only))
