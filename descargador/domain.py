"""Modelos y contratos independientes de la consola y de yt-dlp."""
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

#: Códecs que acepta el extractor de audio.
AUDIO_FORMATS = ("mp3", "m4a", "opus", "vorbis", "flac", "wav", "aac", "alac", "best")

#: Dónde se puede buscar música, todas sin cuenta ni clave.
#:
#: Medido lo mejor que da cada una: Audius, MP3 a 320 kb/s y el original sin
#: pérdida cuando el artista lo deja bajar; SoundCloud, AAC 160 si no lleva
#: DRM; YouTube, Opus ~127; Bandcamp, 128 kb/s salvo lo que el artista regala,
#: que llega en FLAC; el Archive, FLAC. Tidal, Qobuz y compañía llevan DRM, y
#: lo que se ofrece en foros para sacar su FLAC usa cuentas de pago ajenas:
#: no se contempla.
FUENTES = ("youtube", "soundcloud", "audius", "bandcamp", "archive")

#: Cuáles devuelven grabaciones completas en vez de canciones sueltas.
#:
#: El Archive guarda conciertos enteros: cada resultado es una lista de pistas,
#: no un tema. Quien lo use tiene que tratarlo como tal.
FUENTES_DE_LISTAS = ("archive",)

#: Formatos donde no se puede garantizar la normalización de volumen.
#:
#: FFmpegExtractAudio copia el flujo tal cual cuando el códec de destino ya
#: es el de origen, y entonces el filtro chocaría con «-c copy». YouTube
#: entrega opus y aac, así que con esos destinos puede no reconvertir.
FORMATOS_SIN_NORMALIZAR = ("best", "opus", "m4a", "aac")

#: Códecs que guardan el audio entero, sin tirar nada al comprimir.
CODECS_SIN_PERDIDA = ("flac", "alac", "wav", "pcm", "aiff")

#: Categorías de SponsorBlock que se eliminan con --sin-patrocinios.
SPONSOR_CATEGORIES = ("sponsor", "selfpromo", "interaction")


class DownloadError(Exception):
    """Error esperado que puede mostrarse al usuario."""


#: Guiones que pueden separar el inicio del final: normal, medio y largo.
#:
#: Van por su código y no escritos tal cual porque a simple vista los tres son
#: indistinguibles. Hacen falta los tres porque muchos teclados de móvil
#: cambian solos el guion normal por uno largo, y antes eso se rechazaba.
GUIONES = "-" + chr(0x2013) + chr(0x2014)


def parse_timestamp(text: str) -> float:
    """Convierte 90, 1:30 o 01:02:03 en segundos."""
    partes = text.strip().split(":")
    # Un punto casi siempre es un «1.30» queriendo decir un minuto y medio. Si
    # se dejara pasar saldría un fragmento de 1,3 segundos sin avisar de nada,
    # que es peor que un error: parece que la función no sirve.
    if any("." in p or "," in p for p in partes):
        raise DownloadError(
            f"Marca de tiempo inválida: {text!r}. Separa los minutos con dos puntos: 1:30.")
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
    separador = next((g for g in GUIONES if g in text), None)
    if separador is None:
        raise DownloadError("Indica el fragmento como INICIO-FIN, por ejemplo 00:30-02:15.")
    crudo_inicio, _, crudo_fin = text.partition(separador)
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
    #: Prefiere MP4 aunque exista algo mejor en otro contenedor. En el móvil es
    #: casi obligatorio: el reproductor de Android no traga MKV ni VP9.
    prefer_mp4: bool = False
    #: Iguala el volumen de lo descargado, para que una canción no reviente
    #: después de otra. Exige reconvertir, así que no vale con cualquier códec.
    normalize: bool = False
    #: Separa artista y tema del título de YouTube y los escribe en la etiqueta,
    #: en vez de dejar «Artista - Tema (Official Video) [4K]» como título.
    clean_tags: bool = False

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
        if self.normalize:
            if not self.audio_only:
                raise DownloadError("Normalizar el volumen solo se aplica al descargar audio.")
            if self.audio_format in FORMATOS_SIN_NORMALIZAR:
                validos = ", ".join(f for f in AUDIO_FORMATS if f not in FORMATOS_SIN_NORMALIZAR)
                raise DownloadError(
                    f"Normalizar obliga a reconvertir y {self.audio_format!r} puede copiarse "
                    f"tal cual. Elige entre {validos}.")


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
class AudioQuality:
    """La calidad real del audio en su origen, antes de convertirlo a nada.

    Es el techo de cualquier descarga: pasar a FLAC un Opus de 128 kb/s no le
    devuelve lo que se perdió al comprimirlo, solo ocupa cinco veces más. Por
    eso lo que se enseña y se compara es esto, no el formato del archivo final.
    """

    codec: str
    kbps: float | None = None
    hz: int | None = None
    #: Bits por muestra. Solo se sabe leyendo el archivo sin pérdida ya bajado.
    bits: int | None = None

    @property
    def lossless(self) -> bool:
        return self.codec.lower() in CODECS_SIN_PERDIDA

    @property
    def rank(self) -> tuple[int, float]:
        """Para ordenar: primero lo que no pierde nada, luego más bitrate."""
        return (1 if self.lossless else 0, float(self.kbps or 0))


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
    #: Solo lo rellenan los resultados de búsqueda, para poder descargarlos.
    url: str = ""
    #: Miniatura del video. Sin ella una lista de resultados es ilegible.
    thumbnail: str = ""
    #: La calidad, cuando la fuente ya la dice al buscar. None si hay que
    #: comprobarla, que es lo normal.
    quality: AudioQuality | None = None


@dataclass(frozen=True)
class PlaybackSource:
    """Pista reproducible en directo, sin descargar nada.

    Sirve para comprobar que un resultado es el que se busca antes de gastar
    datos en bajarlo. Las cabeceras viajan como pares para que siga siendo
    inmutable y comparable.
    """

    url: str
    headers: tuple[tuple[str, str], ...] = ()
    title: str = ""


@dataclass(frozen=True)
class SearchQuery:
    """Búsqueda por texto. Escribir URLs en un móvil es un suplicio."""

    text: str
    limit: int = 10
    source: str = "youtube"

    def __post_init__(self):
        texto = self.text.strip()
        if not texto:
            raise DownloadError("Escribe algo que buscar.")
        if not 1 <= self.limit <= 25:
            raise DownloadError("El número de resultados debe estar entre 1 y 25.")
        if self.source not in FUENTES:
            opciones = ", ".join(FUENTES)
            raise DownloadError(f"Fuente desconocida: {self.source!r}. Elige entre {opciones}.")
        object.__setattr__(self, "text", texto)


@dataclass(frozen=True)
class Playlist:
    """Una lista ajena con su nombre, para poder recrearla tal cual."""

    title: str
    items: tuple[VideoInfo, ...] = ()


@dataclass(frozen=True)
class DownloadResult:
    files: tuple[Path, ...]
    #: Qué audio llegó de verdad. None si el motor no lo dijo.
    quality: AudioQuality | None = None


class VideoDownloader(Protocol):
    def download(self, request: DownloadRequest) -> DownloadResult: ...

    def inspect(self, request: DownloadRequest) -> VideoInfo: ...

    def search(self, query: SearchQuery) -> tuple[VideoInfo, ...]: ...

    def playlist(self, url: str) -> Playlist: ...

    def stream(self, request: DownloadRequest) -> PlaybackSource: ...

    def quality(self, request: DownloadRequest) -> AudioQuality: ...
