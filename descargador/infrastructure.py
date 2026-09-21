"""Adaptador de yt-dlp: red, archivos, unión con FFmpeg y utilidades del sistema."""
import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .domain import (
    SPONSOR_CATEGORIES,
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    DownloadRequest,
    DownloadResult,
    MediaFormat,
    PlaybackSource,
    Playlist,
    SearchQuery,
    VideoInfo,
)

FALTAN_DEPENDENCIAS = "Faltan dependencias. Ejecuta: python -m pip install -e ."

#: Fallos del servidor que suelen desaparecer al repetir la peticion.
#:
#: «unexpected response» y «challenge» son de las webs que sirven una pantalla
#: anti-robots en vez de la página: al volver a pedirla suele llegar la buena,
#: porque la decisión depende del momento y no de la petición en sí.
ERRORES_TRANSITORIOS = (
    "403", "forbidden", "429", "too many requests", "timed out",
    "unexpected response", "challenge",
)
INTENTOS_TRANSITORIOS = 3

#: Nivel al que se iguala el volumen, en el estándar EBU R128.
#:
#: -14 LUFS es lo que usan las plataformas de streaming, así que lo descargado
#: suena al mismo nivel que el resto de lo que escucha el teléfono.
NIVEL_SONORIDAD = "I=-14:TP=-1.5:LRA=11"

#: Coletillas de videoclip que sobran en el nombre de una canción.
#:
#: Se buscan solo dentro de paréntesis o corchetes: «Live» suelto puede ser
#: parte del título de verdad, pero «(Live)» al final nunca lo es.
#: El «(?i)» va dentro del patrón porque yt-dlp lo compila sin banderas.
RUIDO_TITULO = (
    r"(?i)\s*[\(\[][^)\]]*\b(?:official|oficial|video|videoclip|lyrics?|letra|"
    r"audio|hd|hq|4k|8k|mv|remaster(?:ed)?|visualizer|visualiser|"
    r"en\s+vivo|live)\b[^)\]]*[\)\]]"
)

#: Recorte al cuadrado centrado, del lado del menor de los dos.
#:
#: La miniatura de YouTube es 16:9, y de carátula de disco queda fatal en
#: cualquier reproductor: sale el fotograma estirado o con franjas.
RECORTE_CUADRADO = "crop='min(iw,ih)':'min(iw,ih)'"

#: Cómo se reparte «Artista - Tema» dentro del título.
PLANTILLA_ETIQUETAS = "%(artist)s - %(track)s"

#: Prefijo de búsqueda del motor, por fuente. El Archive no tiene y va aparte.
PREFIJOS_BUSQUEDA = {"youtube": "ytsearch", "soundcloud": "scsearch"}

#: Colección del Internet Archive con conciertos que los grupos dejan compartir.
#:
#: Es la única fuente gratuita con audio sin pérdida de verdad: lo demás que se
#: puede buscar sirve siempre algo ya comprimido con pérdida.
COLECCION_ARCHIVE = "etree"


def acciones_etiquetas() -> tuple:
    """Acciones de MetadataParser para dejar el título en artista y tema.

    Primero se quitan las coletillas y después se parte: al revés, el ruido se
    quedaría pegado al nombre del tema. Las constantes se importan aquí y no
    arriba por lo mismo que el motor: sin yt-dlp, el error debe ser el nuestro.
    """
    try:
        from yt_dlp.postprocessor.metadataparser import MetadataParserPP
    except ImportError as exc:
        raise DownloadError(FALTAN_DEPENDENCIAS) from exc
    acciones = MetadataParserPP.Actions
    return (
        (acciones.REPLACE, "title", RUIDO_TITULO, ""),
        (acciones.INTERPRET, "title", PLANTILLA_ETIQUETAS),
    )


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
        cookies: str | None = None,
    ):
        self._on_progress = on_progress
        #: Archivo de cookies en formato Netscape, cuando hace falta.
        #:
        #: No es para iniciar sesión: hay webs que sirven un muro anti-robots
        #: a quien no llega con las cookies que dan a cualquier visitante.
        self._cookies = cookies
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

    # -- reproduccion directa ---------------------------------------------
    def stream(self, request: DownloadRequest) -> PlaybackSource:
        """Devuelve una pista que puede sonar ya, sin bajar el archivo."""
        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
        }
        if self._registro is not None:
            opciones |= {"logger": self._registro, "verbose": True}
        try:
            # Sin procesar: la pista la elige _elegir_pista sobre la lista
            # completa, así que la selección de formato de yt-dlp sobra, y
            # cuando no logra satisfacerla aborta la extracción entera.
            with YoutubeDL(opciones) as engine:
                info = engine.extract_info(request.url, download=False, process=False)
            if not info:
                raise DownloadError("No se obtuvo nada que reproducir.")
            pista = self._elegir_pista(info, request.options.audio_only)
            cabeceras = tuple((k, str(v)) for k, v in (pista.get("http_headers") or {}).items())
            return PlaybackSource(
                url=str(pista["url"]),
                headers=cabeceras,
                title=info.get("title") or "",
            )
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo preparar la reproducción: {exc}") from exc

    @staticmethod
    def _elegir_pista(info: dict, audio_only: bool) -> dict:
        """Escoge un único flujo reproducible entre todos los formatos.

        Para video se prefiere el manifiesto HLS: YouTube ya casi nunca ofrece
        un formato con imagen y sonido juntos, y el manifiesto los combina para
        que los resuelva el propio reproductor. Si no lo hay, se busca un
        formato combinado y, como último recurso, se cae al audio: mejor oírlo
        que no obtener nada.
        """
        formatos = info.get("formats") or []
        if not audio_only:
            for formato in formatos:
                if formato.get("manifest_url"):
                    return {
                        "url": formato["manifest_url"],
                        "http_headers": formato.get("http_headers"),
                    }
            combinados = [
                f for f in formatos
                if f.get("url")
                and f.get("vcodec") not in (None, "none")
                and f.get("acodec") not in (None, "none")
            ]
            if combinados:
                return max(combinados, key=lambda f: f.get("height") or 0)

        audios = [
            f for f in formatos
            if f.get("url")
            and f.get("acodec") not in (None, "none")
            and f.get("vcodec") in (None, "none")
            and str(f.get("protocol") or "").startswith("http")
        ]
        if audios:
            return max(audios, key=lambda f: f.get("abr") or 0)
        if info.get("url"):
            return info
        raise DownloadError("Este video no ofrece una pista reproducible directa.")

    # -- busqueda ---------------------------------------------------------
    def search(self, query: SearchQuery) -> tuple[VideoInfo, ...]:
        """Busca por texto en YouTube y devuelve resultados con su URL.

        Usa extraccion plana: solo interesan titulo, autor y duracion para
        pintar la lista, y pedir la ficha completa de cada resultado seria
        lentisimo. Esta es la unica ruta del adaptador que acepta una lista,
        porque una busqueda es precisamente eso.
        """
        if query.source == "archive":
            return self._buscar_en_archive(query)

        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "quiet": True,
            "no_warnings": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
            "extract_flat": "in_playlist",
        }
        prefijo = PREFIJOS_BUSQUEDA[query.source]
        try:
            with YoutubeDL(opciones) as engine:
                info = engine.extract_info(
                    f"{prefijo}{query.limit}:{query.text}", download=False)
            entradas = (info or {}).get("entries") or []
            return tuple(self._resultado(e) for e in entradas if e)
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo buscar: {exc}") from exc

    @staticmethod
    def _buscar_en_archive(query: SearchQuery) -> tuple[VideoInfo, ...]:
        """Busca conciertos con audio sin pérdida en el Internet Archive.

        No pasa por el motor porque este no trae buscador para esa web: se le
        pregunta a su propia API y se arman las direcciones. Cada resultado es
        un concierto entero, no una canción, de ahí que la fuente figure en
        FUENTES_DE_LISTAS.
        """
        # Se busca en el título y en el intérprete, no en todo el registro: a
        # campo abierto salían conciertos de otros grupos solo porque la ficha
        # mencionaba de pasada lo que se pedía. Los caracteres que Lucene usa
        # como operadores se quitan para que el texto no cambie la consulta.
        texto = re.sub(r'["\+\-!(){}\[\]^~*?:/]', " ", query.text).strip()
        if not texto:
            raise DownloadError("Escribe algo que buscar en el Archive.")
        consulta = (
            f"collection:{COLECCION_ARCHIVE} AND format:FLAC "
            f"AND (title:({texto}) OR creator:({texto}))"
        )
        direccion = "https://archive.org/advancedsearch.php?" + urlencode(
            {
                "q": consulta,
                # doseq para que los tres campos viajen como «fl[]» repetido,
                # que es como los pide su API.
                "fl[]": ["identifier", "title", "creator"],
                "rows": query.limit,
                "output": "json",
            },
            doseq=True,
        )
        try:
            peticion = Request(direccion, headers={"User-Agent": "descargador"})
            with urlopen(peticion, timeout=30) as respuesta:
                datos = json.loads(respuesta.read().decode("utf-8"))
            documentos = datos.get("response", {}).get("docs", [])
        except (OSError, ValueError) as exc:
            raise DownloadError(f"No se pudo buscar en el Archive: {exc}") from exc

        return tuple(
            VideoInfo(
                title=str(doc.get("title") or doc["identifier"]),
                uploader=str(doc.get("creator") or ""),
                url=f"https://archive.org/details/{doc['identifier']}",
            )
            for doc in documentos
            if doc.get("identifier")
        )

    def playlist(self, url: str) -> Playlist:
        """Lee una lista de reproducción entera sin descargar nada.

        Es la misma extracción plana que la búsqueda: solo hacen falta título,
        autor y URL de cada pista. Aquí sí se acepta una lista, claro.
        """
        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "quiet": True,
            "no_warnings": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
            "extract_flat": "in_playlist",
            # Un canal entero puede traer miles; con esto la espera es razonable.
            "playlistend": 200,
        }
        try:
            with YoutubeDL(opciones) as engine:
                info = engine.extract_info(url, download=False)
            entradas = (info or {}).get("entries")
            if entradas is None:
                raise DownloadError("Ese enlace no es una lista de reproducción.")
            return Playlist(
                title=(info or {}).get("title") or "Lista importada",
                items=tuple(self._resultado(e) for e in entradas if e),
            )
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo leer la lista: {exc}") from exc

    @staticmethod
    def _resultado(datos: dict) -> VideoInfo:
        identificador = datos.get("id") or ""
        return VideoInfo(
            title=datos.get("title") or "(sin título)",
            uploader=datos.get("uploader") or datos.get("channel"),
            duration=datos.get("duration"),
            # webpage_url primero: SoundCloud pone en «url» la de su API, que no
            # sirve para volver a la pista. YouTube lo deja vacío y usa «url».
            url=(datos.get("webpage_url") or datos.get("url")
                 or f"https://www.youtube.com/watch?v={identificador}"),
            thumbnail=YtDlpDownloader._miniatura(datos),
        )

    @staticmethod
    def _miniatura(datos: dict) -> str:
        """La miniatura mas grande que ofrezca la entrada."""
        candidatas = [m for m in (datos.get("thumbnails") or []) if m.get("url")]
        if candidatas:
            mejor = max(candidatas, key=lambda m: (m.get("width") or 0) * (m.get("height") or 0))
            return str(mejor["url"])
        return str(datos.get("thumbnail") or "")

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
                "postprocessor_args": self._argumentos_postproceso(opts),
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
            if self._cookies:
                options["cookiefile"] = self._cookies

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
        # El «?» del tope es lo que evita descartar un formato solo porque no
        # diga su altura. Instagram y compañía sirven MP4 sin metadatos, y con
        # el filtro estricto se quedaban fuera los únicos que servían.
        alto = f"[height<=?{opts.quality}]" if opts.quality else ""
        general = f"bv*{alto}+ba/b{alto}" if alto else "bv*+ba/b"
        # Y sin una rama sin condiciones al final, el tope puede dejarlas todas
        # vacías y yt-dlp aborta con «Requested format is not available». Pasa
        # con el vídeo vertical: un reel de 720p mide 720x1280, y esos 1280
        # superan cualquier tope pensado para vídeo apaisado.
        respaldo = "/b" if alto else ""
        if not opts.prefer_mp4:
            return f"{general}{respaldo}"
        # H.264 primero: es el unico codec que decodifica por hardware
        # cualquier movil. Un MP4 con AV1 o VP9 se reproduce a tirones o no se
        # reproduce. Si no lo hay, se baja a cualquier MP4 y luego a lo general.
        return (f"bv*[vcodec^=avc1]{alto}+ba[ext=m4a]/"
                f"bv*[ext=mp4]{alto}+ba[ext=m4a]/"
                f"b[ext=mp4]{alto}/{general}{respaldo}")

    @staticmethod
    def _argumentos_postproceso(opts: DownloadOptions) -> dict[str, list[str]]:
        """Argumentos extra para FFmpeg, dirigidos a un postprocesador concreto.

        La clave `extractaudio+ffmpeg` apunta solo a la conversión de audio.
        Con la clave `default` el filtro llegaría también a los pasos que
        copian el flujo (metadatos, carátula), y ffmpeg aborta al mezclar un
        filtro con «-c copy». Comprobado contra el resolutor de yt-dlp.
        """
        argumentos: dict[str, list[str]] = {}
        if opts.normalize:
            argumentos["extractaudio+ffmpeg"] = ["-af", f"loudnorm={NIVEL_SONORIDAD}"]
        if opts.audio_only:
            argumentos["thumbnailsconvertor+ffmpeg"] = ["-vf", RECORTE_CUADRADO]
        return argumentos

    @staticmethod
    def _postprocesadores(opts: DownloadOptions, caratula: bool = True) -> list[dict]:
        pps: list[dict] = []
        if opts.clean_tags:
            # En `pre_process`, así que el archivo también sale con el
            # nombre limpio y no solo la etiqueta de dentro.
            pps.append({"key": "MetadataParser", "actions": acciones_etiquetas(),
                        "when": "pre_process"})
        if opts.audio_only:
            pps.append({
                "key": "FFmpegExtractAudio",
                "preferredcodec": opts.audio_format,
                "preferredquality": opts.audio_bitrate,
            })
        if opts.audio_only and caratula:
            # Convierte la miniatura antes de incrustarla, que es cuando se le
            # puede aplicar el recorte: al incrustarla ya va con «-c copy».
            # A PNG y no a JPG a propósito: si el destino coincide con el
            # origen, yt-dlp se salta la conversión y no habría recorte.
            pps.append({"key": "FFmpegThumbnailsConvertor", "format": "png"})
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


def escribir_etiquetas(origen: Path, destino: Path, *, titulo: str, artista: str) -> None:
    """Reescribe título y artista de un audio ya descargado.

    Con «-c copy -map 0» el sonido y la carátula pasan tal cual: solo cambia la
    cabecera, así que no se pierde calidad ni tarda. FFmpeg no sabe escribir
    sobre el archivo que está leyendo, de ahí que el destino tenga que ser otro
    y sea quien llama el que lo ponga en su sitio.
    """
    if not origen.is_file():
        raise DownloadError("No se encontró el archivo que se quería etiquetar.")
    ffmpeg = _preparar_ffmpeg()
    orden = [
        ffmpeg, "-y", "-i", str(origen),
        "-map", "0", "-c", "copy",
        # La versión 3 es la que entienden todos los reproductores; con la 4
        # hay teléfonos que no leen ni el título.
        "-id3v2_version", "3",
        "-metadata", f"title={titulo}",
        "-metadata", f"artist={artista}",
        str(destino),
    ]
    try:
        resultado = subprocess.run(orden, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise DownloadError(f"No se pudo ejecutar FFmpeg: {exc}") from exc
    if resultado.returncode != 0 or not destino.is_file():
        detalle = (resultado.stderr or "").strip().splitlines()
        raise DownloadError(
            "No se pudieron escribir las etiquetas: " + (detalle[-1] if detalle else "falló FFmpeg"))


def nombre_con_etiquetas(nombre: str, *, titulo: str, artista: str) -> str:
    """El nombre de archivo que corresponde a esas etiquetas.

    Conserva la extensión y el identificador entre corchetes, que es con lo que
    se reconoce la pista y se evita volver a descargarla. Sin artista no se
    inventa un guion suelto.
    """
    extension = ""
    resto = nombre
    if "." in nombre:
        resto, _, sufijo = nombre.rpartition(".")
        extension = f".{sufijo}"
    identificador = ""
    marca = re.search(r"\s*(\[[^\]]+\])\s*$", resto)
    if marca:
        identificador = f" {marca.group(1)}"

    limpio = f"{artista.strip()} - {titulo.strip()}" if artista.strip() else titulo.strip()
    # Los mismos caracteres que rechaza Android en un nombre de archivo.
    limpio = re.sub(r'[\\/:*?"<>|]', " ", limpio)
    limpio = re.sub(r"\s+", " ", limpio).strip()
    if not limpio:
        return nombre
    return f"{limpio}{identificador}{extension}"


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
