"""Modelos y contratos independientes de la consola y de yt-dlp."""
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

#: Códecs que acepta el extractor de audio.
AUDIO_FORMATS = ("mp3", "m4a", "opus", "vorbis", "flac", "wav", "aac", "alac", "best")

#: Categorías de SponsorBlock que se eliminan con --sin-patrocinios.
SPONSOR_CATEGORIES = ("sponsor", "selfpromo", "interaction")


class DownloadError(Exception):
    """Error esperado que puede mostrarse al usuario."""


def parse_timestamp(text: str) -> float:
    """Convierte 90, 1:30 o 01:02:03 en segundos."""
    partes = text.strip().split(":")
    if not 1 <= len(partes) <= 3:
        raise DownloadError(f"Marca de tiempo inválida: {text!r}. Usa SS, MM:SS o HH:MM:SS.")
    try:
        valores = [float(p) for p in partes]
    except ValueError:
        raise DownloadError(f"Marca de tiempo inválida: {text!r}. Usa SS, MM:SS o HH:MM:SS.") from None
    if any(v < 0 for v in valores):
        raise DownloadError(f"Marca de tiempo inválida: {text!r}. No admite valores negativos.")
    segundos = 0.0
    for valor in valores:
        segundos = segundos * 60 + valor
    return segundos


def parse_section(text: str) -> tuple[float, float]:
    """Convierte '00:30-02:15' en (30.0, 135.0). Los extremos pueden omitirse."""
    if "-" not in text:
        raise DownloadError("Indica el fragmento como INICIO-FIN, por ejemplo 00:30-02:15.")
    crudo_inicio, _, crudo_fin = text.partition("-")
    inicio = parse_timestamp(crudo_inicio) if crudo_inicio.strip() else 0.0
    fin = parse_timestamp(crudo_fin) if crudo_fin.strip() else float("inf")
    if fin <= inicio:
        raise DownloadError("El final del fragmento debe ser posterior al inicio.")
    return inicio, fin


@dataclass(frozen=True)
class DownloadOptions:
    """Ajustes de la descarga; el caso de uso los traslada sin interpretarlos."""

    audio_only: bool = False
    quality: int | None = None
    audio_format: str = "mp3"
    audio_bitrate: str = "192"
    subtitles: tuple[str, ...] = ()
    section: tuple[float, float] | None = None
    skip_sponsors: bool = False
    use_archive: bool = False

    def __post_init__(self):
        if self.quality is not None and self.quality <= 0:
            raise DownloadError("La calidad debe ser un alto en píxeles mayor que cero, por ejemplo 1080.")
        if self.audio_format not in AUDIO_FORMATS:
            opciones = ", ".join(AUDIO_FORMATS)
            raise DownloadError(
                f"Formato de audio no admitido: {self.audio_format!r}. Elige entre {opciones}.")
        if not self.audio_bitrate.isdigit():
            raise DownloadError("El bitrate se indica en kb/s, por ejemplo 192.")
        if self.section is not None:
            inicio, fin = self.section
            if inicio < 0 or fin <= inicio:
                raise DownloadError("El final del fragmento debe ser posterior al inicio.")


@dataclass(frozen=True)
class DownloadRequest:
    url: str
    destination: Path
    options: DownloadOptions = field(default_factory=DownloadOptions)

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
class DownloadProgress:
    """Avance de la descarga, tal y como lo publica el motor."""

    status: str
    filename: str = ""
    downloaded: int = 0
    total: int | None = None
    speed: float | None = None
    eta: int | None = None

    @property
    def percent(self) -> float | None:
        if not self.total:
            return None
        return min(100.0, self.downloaded * 100 / self.total)


@dataclass(frozen=True)
class MediaFormat:
    format_id: str
    ext: str
    resolution: str
    filesize: int | None = None
    note: str = ""


@dataclass(frozen=True)
class VideoInfo:
    title: str
    uploader: str | None = None
    duration: float | None = None
    formats: tuple[MediaFormat, ...] = ()


@dataclass(frozen=True)
class DownloadResult:
    files: tuple[Path, ...]


class VideoDownloader(Protocol):
    def download(self, request: DownloadRequest) -> DownloadResult: ...

    def inspect(self, request: DownloadRequest) -> VideoInfo: ...
