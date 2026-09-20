"""Adaptador de yt-dlp: red, archivos, unión con FFmpeg y utilidades del sistema."""
import os
import shutil
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

from .domain import (
    SPONSOR_CATEGORIES,
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    DownloadRequest,
    DownloadResult,
    MediaFormat,
    SearchQuery,
    VideoInfo,
)

FALTAN_DEPENDENCIAS = "Faltan dependencias. Ejecuta: python -m pip install -e ."

#: Fallos del servidor que suelen desaparecer al repetir la peticion.
ERRORES_TRANSITORIOS = ("403", "forbidden", "429", "too many requests", "timed out")
INTENTOS_TRANSITORIOS = 3


def _es_transitorio(error: Exception) -> bool:
    mensaje = str(error).lower()
    return any(pista in mensaje for pista in ERRORES_TRANSITORIOS)


def _cargar_motor():
    """Importa yt-dlp tarde para poder explicar la falta de dependencias.

    No toca FFmpeg: consultar un video no lo necesita, y en Android el paquete
    imageio-ffmpeg no sirve porque sus binarios son de escritorio.
    """
    try:
        from yt_dlp import YoutubeDL
        from yt_dlp.utils import YoutubeDLError, download_range_func
    except ImportError as exc:
        raise DownloadError(FALTAN_DEPENDENCIAS) from exc
    return YoutubeDL, YoutubeDLError, download_range_func


def _cargar_ffmpeg():
    """Devuelve el localizador de FFmpeg de imageio-ffmpeg, solo al descargar."""
    try:
        from imageio_ffmpeg import get_ffmpeg_exe
    except ImportError as exc:
        raise DownloadError(FALTAN_DEPENDENCIAS) from exc
    return get_ffmpeg_exe


def _runtimes_js() -> dict:
    return {nombre: {} for nombre in ("deno", "node") if shutil.which(nombre)}


def configurar_entorno(binarios: str, librerias: str = "") -> None:
    """Registra binarios propios (FFmpeg, ffprobe) para esta plataforma.

    En Android no existe imageio-ffmpeg: los ejecutables llegan dentro del APK.
    Basta con ponerlos en el PATH para que el resto del adaptador los encuentre
    como si fueran los del sistema, sin ninguna rama especial por plataforma.
    """
    rutas = os.environ.get("PATH", "").split(os.pathsep)
    if binarios and binarios not in rutas:
        os.environ["PATH"] = binarios + os.pathsep + os.environ.get("PATH", "")
    if librerias:
        # El ejecutable de FFmpeg carga libavcodec y compania desde aqui.
        os.environ["LD_LIBRARY_PATH"] = librerias


def _preparar_ffmpeg() -> str:
    """Devuelve la ruta de FFmpeg y se asegura de que también esté en el PATH.

    Para el recorte de fragmentos, yt-dlp comprueba la disponibilidad de FFmpeg
    buscándolo en el PATH e ignora ffmpeg_location (así lo documenta su propio
    código). El binario de imageio-ffmpeg no se llama ffmpeg, de modo que se
    crea un alias junto al original la primera vez.
    """
    encontrado = shutil.which("ffmpeg")
    if encontrado:
        return encontrado
    try:
        localizador = _cargar_ffmpeg()
    except DownloadError:
        # Sin imageio-ffmpeg y sin FFmpeg en el PATH: pasa en Android si los
        # binarios del APK no llegaron a registrarse. Hablar de pip no ayuda.
        raise DownloadError(
            "No se encontró FFmpeg, necesario para unir video y audio o crear MP3.") from None
    original = Path(localizador())
    alias = original.with_name("ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    if not alias.exists():
        try:
            os.link(original, alias)
        except OSError:
            try:
                shutil.copy2(original, alias)
            except OSError:
                return str(original)
    carpeta = str(alias.parent)
    if carpeta not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = carpeta + os.pathsep + os.environ.get("PATH", "")
    return str(alias)


def incrusta_caratula(audio_only: bool) -> bool:
    """Indica si la carátula puede incrustarse sin abortar el postprocesado.

    En audio se resuelve con mutagen o con FFmpeg. En video el contenedor puede
    acabar siendo MKV, y ahí yt-dlp necesita ffprobe, que no acompaña a
    imageio-ffmpeg; sin él se omite la carátula en lugar de perder la descarga.
    """
    return audio_only or bool(shutil.which("ffprobe"))


class YtDlpDownloader:
    def __init__(
        self,
        on_progress: Callable[[DownloadProgress], None] | None = None,
        registro: object | None = None,
    ):
        self._on_progress = on_progress
        #: Receptor opcional del log detallado del motor (debug/warning/error).
        #: Sirve para diagnosticar fallos donde no hay consola, como el móvil.
        self._registro = registro

    # -- consulta ---------------------------------------------------------
    def inspect(self, request: DownloadRequest) -> VideoInfo:
        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
        }
        try:
            with YoutubeDL(opciones) as engine:
                info = engine.extract_info(request.url, download=False)
            if not info:
                raise DownloadError("No se obtuvo información. Comprueba la URL.")
            if info.get("_type") in {"playlist", "multi_video"}:
                raise DownloadError("Pasa la URL de un video individual, no de una lista o canal.")
            return VideoInfo(
                title=info.get("title") or "(sin título)",
                uploader=info.get("uploader") or info.get("channel"),
                duration=info.get("duration"),
                formats=tuple(self._formato(f) for f in (info.get("formats") or [])),
            )
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo consultar el video: {exc}") from exc

    # -- busqueda ---------------------------------------------------------
    def search(self, query: SearchQuery) -> tuple[VideoInfo, ...]:
        """Busca por texto en YouTube y devuelve resultados con su URL.

        Usa extraccion plana: solo interesan titulo, autor y duracion para
        pintar la lista, y pedir la ficha completa de cada resultado seria
        lentisimo. Esta es la unica ruta del adaptador que acepta una lista,
        porque una busqueda es precisamente eso.
        """
        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "quiet": True,
            "no_warnings": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
            "extract_flat": "in_playlist",
        }
        try:
            with YoutubeDL(opciones) as engine:
                info = engine.extract_info(f"ytsearch{query.limit}:{query.text}", download=False)
            entradas = (info or {}).get("entries") or []
            return tuple(self._resultado(e) for e in entradas if e)
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo buscar: {exc}") from exc

    @staticmethod
    def _resultado(datos: dict) -> VideoInfo:
        identificador = datos.get("id") or ""
        return VideoInfo(
            title=datos.get("title") or "(sin título)",
            uploader=datos.get("uploader") or datos.get("channel"),
            duration=datos.get("duration"),
            url=datos.get("url") or f"https://www.youtube.com/watch?v={identificador}",
        )

    @staticmethod
    def _formato(datos: dict) -> MediaFormat:
        alto = datos.get("height")
        return MediaFormat(
            format_id=datos.get("format_id") or "",
            ext=datos.get("ext") or "",
            resolution=datos.get("resolution") or (f"{alto}p" if alto else "solo audio"),
            filesize=datos.get("filesize") or datos.get("filesize_approx"),
            note=datos.get("format_note") or "",
        )

    # -- descarga ---------------------------------------------------------
    def download(self, request: DownloadRequest) -> DownloadResult:
        """Descarga reintentando los fallos pasajeros del servidor.

        yt-dlp solo reintenta errores 5xx: un 403 aborta. Pero YouTube devuelve
        403 de vez en cuando cuando la URL del stream rota, y eso tiraba la
        descarga entera. Reintentar desde el principio vuelve a extraer la URL,
        y lo ya bajado se conserva porque continuedl esta activo.
        """
        ultimo: DownloadError | None = None
        for intento in range(INTENTOS_TRANSITORIOS):
            try:
                return self._intentar(request)
            except DownloadError as exc:
                ultimo = exc
                if intento == INTENTOS_TRANSITORIOS - 1 or not _es_transitorio(exc):
                    raise
        raise ultimo if ultimo else DownloadError("No se pudo completar la descarga.")

    def _intentar(self, request: DownloadRequest) -> DownloadResult:
        YoutubeDL, YoutubeDLError, download_range_func = _cargar_motor()
        opts = request.options
        archivos: list[Path] = []

        def terminado(nombre):
            if nombre:
                archivos.append(Path(nombre).resolve())

        try:
            destino = request.destination.expanduser().resolve()
            if opts.audio_only:
                destino = destino / "audio"
            destino.mkdir(parents=True, exist_ok=True)
            ffmpeg = _preparar_ffmpeg()
            caratula = incrusta_caratula(opts.audio_only)
            options = {
                "paths": {"home": str(destino)},
                "outtmpl": {"default": "%(title).120B [%(id)s].%(ext)s"},
                "windowsfilenames": True,
                "format": self._seleccion_formato(opts),
                "ffmpeg_location": ffmpeg,
                "merge_output_format": "mp4" if opts.prefer_mp4 else "mp4/mkv",
                "noplaylist": True,
                "match_filter": self._single_video,
                "continuedl": True,
                "overwrites": False,
                "retries": 5,
                "fragment_retries": 5,
                "skip_unavailable_fragments": False,
                "socket_timeout": 30,
                "color": "no_color",
                "post_hooks": [terminado],
                "postprocessors": self._postprocesadores(opts, caratula),
                "writethumbnail": caratula,
                "js_runtimes": _runtimes_js(),
            }
            if opts.subtitles:
                options |= {
                    "writesubtitles": True,
                    "writeautomaticsub": True,
                    "subtitleslangs": list(opts.subtitles),
                }
            if opts.section:
                options["download_ranges"] = download_range_func([], [opts.section])
                options["force_keyframes_at_cuts"] = True
            if opts.use_archive:
                options["download_archive"] = str(destino / ".descargadas.txt")
            if self._on_progress is not None:
                options |= {"progress_hooks": [self._notificar], "noprogress": True, "quiet": True}
            if self._registro is not None:
                options |= {"logger": self._registro, "verbose": True}

            with YoutubeDL(options) as engine:
                info = engine.extract_info(request.url, download=False, process=False)
                if info and info.get("_type") in {"playlist", "multi_video"}:
                    raise DownloadError("Pasa la URL de un video individual, no de una lista o canal.")
                if info:
                    engine.process_ie_result(info, download=True)
            existentes = tuple(dict.fromkeys(p for p in archivos if p.is_file()))
            if not existentes:
                if opts.use_archive:
                    # Ya figuraba en el registro: se omite, no es un fallo.
                    return DownloadResult(())
                raise DownloadError("No se obtuvo ningún archivo. Comprueba la URL.")
            return DownloadResult(existentes)
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo completar la descarga: {exc}") from exc

    @staticmethod
    def _seleccion_formato(opts: DownloadOptions) -> str:
        if opts.audio_only:
            return "ba/b"
        alto = f"[height<={opts.quality}]" if opts.quality else ""
        general = f"bv*{alto}+ba/b{alto}" if alto else "bv*+ba/b"
        if not opts.prefer_mp4:
            return general
        # H.264 primero: es el unico codec que decodifica por hardware
        # cualquier movil. Un MP4 con AV1 o VP9 se reproduce a tirones o no se
        # reproduce. Si no lo hay, se baja a cualquier MP4 y luego a lo general.
        return (f"bv*[vcodec^=avc1]{alto}+ba[ext=m4a]/"
                f"bv*[ext=mp4]{alto}+ba[ext=m4a]/"
                f"b[ext=mp4]{alto}/{general}")

    @staticmethod
    def _postprocesadores(opts: DownloadOptions, caratula: bool = True) -> list[dict]:
        pps: list[dict] = []
        if opts.audio_only:
            pps.append({
                "key": "FFmpegExtractAudio",
                "preferredcodec": opts.audio_format,
                "preferredquality": opts.audio_bitrate,
            })
        if opts.skip_sponsors:
            pps.append({"key": "SponsorBlock", "categories": list(SPONSOR_CATEGORIES),
                        "when": "after_filter"})
            pps.append({"key": "ModifyChapters", "remove_sponsor_segments": list(SPONSOR_CATEGORIES)})
        pps.append({"key": "FFmpegMetadata", "add_metadata": True, "add_chapters": True})
        if opts.subtitles and not opts.audio_only:
            pps.append({"key": "FFmpegEmbedSubtitle", "already_have_subtitle": False})
        if caratula:
            pps.append({"key": "EmbedThumbnail", "already_have_thumbnail": False})
        return pps

    def _notificar(self, datos: dict) -> None:
        if self._on_progress is None:
            return
        nombre = datos.get("filename") or ""
        self._on_progress(DownloadProgress(
            status=datos.get("status") or "",
            filename=Path(nombre).name if nombre else "",
            downloaded=datos.get("downloaded_bytes") or 0,
            total=datos.get("total_bytes") or datos.get("total_bytes_estimate"),
            speed=datos.get("speed"),
            eta=datos.get("eta"),
        ))

    @staticmethod
    def _single_video(info, *, incomplete=False):
        if info.get("_type") in {"playlist", "multi_video"}:
            return "Pasa la URL de un video individual, no de una lista o canal."
        if info.get("is_live"):
            return "El video está en directo. Usa la URL cuando la transmisión termine."
        return None


# -- utilidades del sistema ------------------------------------------------
def actualizar_motor() -> int:
    """Actualiza yt-dlp en el intérprete actual."""
    orden = [sys.executable, "-m", "pip", "install", "--upgrade", "yt-dlp[default]"]
    try:
        return subprocess.call(orden)
    except OSError as exc:
        raise DownloadError(f"No se pudo actualizar el motor: {exc}") from exc


def abrir_carpeta(ruta: Path) -> None:
    """Abre la carpeta en el explorador del sistema; nunca interrumpe la descarga."""
    try:
        if sys.platform == "win32":
            os.startfile(ruta)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.call(["open", str(ruta)])
        else:
            subprocess.call(["xdg-open", str(ruta)])
    except OSError:
        pass


def leer_portapapeles() -> str:
    """Devuelve el texto del portapapeles sin dependencias externas."""
    try:
        if sys.platform == "win32":
            orden = ["powershell", "-NoProfile", "-Command", "Get-Clipboard"]
        elif sys.platform == "darwin":
            orden = ["pbpaste"]
        else:
            orden = ["xclip", "-selection", "clipboard", "-o"]
        salida = subprocess.run(orden, capture_output=True, text=True, timeout=15, check=False)
        return salida.stdout.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise DownloadError(f"No se pudo leer el portapapeles: {exc}") from exc
