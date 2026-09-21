"""Casos de uso; dependen únicamente de los contratos del dominio."""
from pathlib import Path

from .domain import (
    DownloadError,
    DownloadOptions,
    DownloadRequest,
    DownloadResult,
    PlaybackSource,
    Playlist,
    SearchQuery,
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


class SearchVideos:
    """Busca por texto, para no tener que pegar una URL."""

    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(
        self,
        text: str,
        limit: int = 10,
        source: str = "youtube",
    ) -> tuple[VideoInfo, ...]:
        return self.downloader.search(SearchQuery(text, limit, source))


class StreamVideo:
    """Obtiene una pista reproducible sin descargar nada."""

    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(self, url: str, *, audio_only: bool = True) -> PlaybackSource:
        opciones = DownloadOptions(audio_only=audio_only)
        return self.downloader.stream(DownloadRequest(url, Path("."), opciones))


class ImportPlaylist:
    """Trae el contenido de una lista ajena, para no añadirla a mano."""

    def __init__(self, downloader: VideoDownloader):
        self.downloader = downloader

    def execute(self, url: str) -> Playlist:
        limpia = url.strip()
        if not limpia:
            raise DownloadError("Pega el enlace de una lista de reproducción.")
        return self.downloader.playlist(limpia)
