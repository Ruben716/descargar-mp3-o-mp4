"""Adaptador de yt-dlp: red, archivos, unión con FFmpeg y utilidades del sistema."""
import functools
import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from .domain import (
    GUIONES,
    SPONSOR_CATEGORIES,
    AudioQuality,
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

#: La API pública de Audius. No pide clave: basta con decir quién pregunta.
AUDIUS_API = "https://api.audius.co/v1"
APP_AUDIUS = "tumbao"

#: Las direcciones de una pista de Audius: «audius.co/artista/tema».
ES_AUDIUS = re.compile(r"https?://(?:www\.)?audius\.co/[^/?#]+/[^/?#]+")

#: El buscador público de la web de Bandcamp.
BUSCADOR_BANDCAMP = "https://bandcamp.com/api/bcsearch_public_api/1/autocomplete_elastic"

#: Tamaño de cada trozo al bajar un archivo grande en varias conexiones.
TROZO_PARALELO = 4 * 1024 * 1024

#: Cuántas conexiones a la vez para un archivo en trozos. Medido: con cuatro,
#: el WAV original de Audius bajó un 58 % más rápido que con una.
CONEXIONES_PARALELAS = 4

#: Formatos que no pierden nada. Si el destino es uno de estos, se busca el
#: mejor origen, sin pérdida incluido; si no, sobra bajar un original enorme.
FORMATOS_SIN_PERDIDA = ("flac", "wav", "alac")

#: Prefijo de búsqueda del motor, por fuente. Las demás van por su propia API.
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


#: Fallos conocidos del motor y qué contarle a quien está delante.
#:
#: Lo que escupe yt-dlp está en inglés y habla de cosas que no le dicen nada a
#: quien solo quería una canción. Aquí se traduce y, cuando hay salida, se
#: sugiere: un mensaje que no dice qué hacer es medio mensaje.
EXPLICACIONES: tuple[tuple[str, str], ...] = (
    ("drm protected",
     "Esa pista está protegida por su sello y no se puede descargar. "
     "Prueba a buscar la misma canción en YouTube."),
    ("requiring login",
     "Ese contenido pide iniciar sesión, y esta aplicación no usa cuentas."),
    ("sign in to confirm",
     "La web pide iniciar sesión para comprobar que no eres un robot. "
     "Inténtalo más tarde o busca la canción en otra fuente."),
    ("private video", "Ese vídeo es privado."),
    ("video unavailable", "Ese vídeo ya no está disponible."),
    ("members-only", "Ese contenido es solo para miembros del canal."),
    ("requested format is not available",
     "No hay ningún formato descargable para ese enlace."),
    ("no space left", "No queda espacio libre en el teléfono."),
    ("unexpected response",
     "La web respondió con una pantalla de verificación en vez de la página. "
     "Suele arreglarse probando de nuevo en un rato."),
)


def codec_legible(acodec: str | None, ext: str | None = None) -> str:
    """El códec como lo diría una persona: «aac» y no «mp4a.40.2».

    Si el motor no lo sabe, se deduce de la extensión: el archivo original que
    algunos artistas dejan bajar en SoundCloud llega así, sin códec declarado.
    """
    codec = (acodec or "").lower()
    if not codec or codec == "none":
        codec = (ext or "").lower()
    if codec.startswith("mp4a") or codec == "m4a":
        return "aac"
    if codec.startswith("pcm"):
        return "pcm"
    if codec in ("aif", "aiff"):
        return "aiff"
    return codec or "desconocido"


def calidad_de(info: dict) -> AudioQuality:
    """La calidad del audio que eligió el motor, venga suelto o junto al vídeo."""
    elegidos = info.get("requested_formats") or [info]
    audio = next(
        (f for f in elegidos if (f.get("acodec") or "none") != "none"
         or f.get("ext") in ("flac", "wav", "mp3", "m4a", "opus", "ogg")),
        None,
    )
    if audio is None:
        raise DownloadError("Ese enlace no tiene audio.")
    kbps = audio.get("abr") or audio.get("tbr")
    hz = audio.get("asr")
    return AudioQuality(
        codec=codec_legible(audio.get("acodec"), audio.get("ext")),
        kbps=round(float(kbps), 1) if kbps else None,
        hz=int(hz) if hz else None,
    )


def original_sin_perdida(pista: dict) -> str | None:
    """La extensión del original de una pista de Audius, si se deja bajar y no pierde.

    El artista decide si su pista se puede descargar, y Audius entonces sirve
    el archivo que subió. Si es un MP3 no aporta nada frente al streaming;
    si es un WAV o un FLAC, es el sonido entero.
    """
    if not (pista.get("is_downloadable") and pista.get("is_original_available")):
        return None
    if pista.get("is_download_gated"):
        return None
    extension = Path(pista.get("orig_filename") or "").suffix.lower().lstrip(".")
    extension = "aiff" if extension == "aif" else extension
    return extension if extension in ("wav", "flac", "aiff") else None


def calidad_audius(pista: dict) -> AudioQuality | None:
    """Lo que da una pista de Audius, o None si no se puede escuchar sin pagar.

    Medido: su streaming es MP3 a 320 kb/s, cabecera a cabecera.
    """
    if pista.get("is_stream_gated") or pista.get("is_streamable") is False:
        return None
    original = original_sin_perdida(pista)
    return AudioQuality(original) if original else AudioQuality("mp3", 320.0)


@functools.cache
def _extractor_audius():
    """Un extractor de Audius que sabe bajar el original, no solo escucharlo.

    El que trae el motor solo pide el streaming. Este ofrece también el
    archivo que subió el artista cuando lo deja bajar, y la selección de
    formato de siempre se queda con el mejor: si es un WAV, el WAV.
    """
    try:
        from yt_dlp.extractor.common import InfoExtractor
    except ImportError as exc:
        raise DownloadError(FALTAN_DEPENDENCIAS) from exc

    class AudiusOriginalIE(InfoExtractor):
        IE_NAME = "audius:original"
        _VALID_URL = ES_AUDIUS.pattern

        def _real_extract(self, url):
            pista = self._download_json(
                f"{AUDIUS_API}/resolve", url,
                query={"url": url, "app_name": APP_AUDIUS},
                note="Consultando la pista en Audius")["data"]
            if calidad_audius(pista) is None:
                self.raise_no_formats(
                    "Esa pista de Audius es de pago o está restringida.", expected=True)
            ident = pista["id"]
            formatos = [{
                "format_id": "mp3-320",
                "url": f"{AUDIUS_API}/tracks/{ident}/stream?app_name={APP_AUDIUS}",
                "ext": "mp3",
                "acodec": "mp3",
                "abr": 320,
                "vcodec": "none",
            }]
            original = original_sin_perdida(pista)
            if original:
                formatos.append(self._formato_original(ident, original))
            autor = (pista.get("user") or {}).get("name")
            return {
                "id": ident,
                "title": pista.get("title") or ident,
                "uploader": autor,
                "artist": autor,
                "duration": pista.get("duration"),
                "thumbnail": (pista.get("artwork") or {}).get("1000x1000"),
                "webpage_url": url,
                "formats": formatos,
            }

        def _formato_original(self, ident: str, extension: str) -> dict:
            """El original, en trozos si se sabe cuánto pesa.

            Pesa mucho (un WAV de cuatro minutos, 70 MB), y bajarlo por una
            sola conexión era lo que hacía eterna la descarga en el teléfono.
            En trozos, el motor los pide a la vez y luego los junta.
            """
            direccion = f"{AUDIUS_API}/tracks/{ident}/download?app_name={APP_AUDIUS}"
            formato: dict = {
                "format_id": "original",
                "url": direccion,
                "ext": extension,
                "acodec": extension,
                "vcodec": "none",
            }
            try:
                from yt_dlp.networking import HEADRequest

                respuesta = self._request_webpage(
                    HEADRequest(direccion), ident, note="Midiendo el original", fatal=False)
                total = int((respuesta.headers.get("Content-Length") if respuesta else 0) or 0)
                final = respuesta.url if respuesta else ""
            except (ValueError, ImportError):
                total, final = 0, ""
            if total > TROZO_PARALELO and final:
                formato |= {
                    "url": final,
                    "filesize": total,
                    "protocol": "http_dash_segments",
                    "fragments": [{"url": final, "byte_range": r} for r in trozos(total)],
                }
            return formato

    return AudiusOriginalIE


def necesita_portada_oficial(url: str) -> bool:
    """Si la imagen que trae el enlace es un fotograma y no la portada.

    Solo pasa con YouTube. En Audius, Bandcamp, SoundCloud o el Archive la
    imagen ya es la del disco que subió el artista: buscar otra fuera cuesta
    tiempo y, peor, puede cambiarla por la de otra versión (a un remix, la
    del tema original).
    """
    try:
        anfitrion = (urlparse(url).hostname or "").lower()
    except ValueError:
        return False
    return anfitrion == "youtu.be" or anfitrion.endswith("youtube.com")


def trozos(total: int, tamano: int = TROZO_PARALELO) -> list[dict]:
    """Los rangos de bytes para bajar un archivo en varias conexiones.

    El final de cada rango es exclusivo, como lo espera el motor.
    """
    return [{"start": inicio, "end": min(inicio + tamano, total)}
            for inicio in range(0, total, tamano)]


def _extraer(engine, url: str, **opciones):
    """extract_info, pero con el extractor propio donde hace falta."""
    if ES_AUDIUS.match(url):
        clase = _extractor_audius()
        engine.add_info_extractor(clase())
        return engine.extract_info(url, ie_key=clase.ie_key(), **opciones)
    return engine.extract_info(url, **opciones)


def _consultar(direccion: str, fuente: str, cuerpo: bytes | None = None) -> dict:
    """Pide un JSON a la API de una fuente. Un fallo se cuenta, no se esconde."""
    cabeceras = {"User-Agent": "Mozilla/5.0 (descargador)"}
    if cuerpo is not None:
        cabeceras["Content-Type"] = "application/json"
    try:
        with urlopen(Request(direccion, data=cuerpo, headers=cabeceras), timeout=30) as respuesta:
            return json.loads(respuesta.read().decode("utf-8"))
    except (OSError, ValueError) as exc:
        raise DownloadError(f"No se pudo buscar en {fuente}: {exc}") from exc


def cabecera_sin_perdida(ruta: Path) -> tuple[int, int] | None:
    """Frecuencia y bits reales de un FLAC o un WAV, leídos de su cabecera.

    Es lo que separa un CD (16 bits, 44,1 kHz) de un Hi-Res de verdad, y no
    lo dice ninguna web al buscar: solo el archivo, una vez bajado.
    """
    try:
        with open(ruta, "rb") as archivo:
            cabeza = archivo.read(4096)
    except OSError:
        return None
    # FLAC: tras «fLaC» va siempre el bloque STREAMINFO. 20 bits de
    # frecuencia, 3 de canales y 5 de bits por muestra, en ese orden.
    if cabeza[:4] == b"fLaC" and len(cabeza) >= 42:
        info = cabeza[8:42]
        hz = (info[10] << 12) | (info[11] << 4) | (info[12] >> 4)
        bits = (((info[12] & 0x01) << 4) | (info[13] >> 4)) + 1
        return (hz, bits) if hz else None
    # WAV: se busca el trozo «fmt », que lleva la frecuencia y los bits.
    if cabeza[:4] == b"RIFF" and cabeza[8:12] == b"WAVE":
        i = 12
        while i + 8 <= len(cabeza):
            tamano = int.from_bytes(cabeza[i + 4:i + 8], "little")
            if cabeza[i:i + 4] == b"fmt " and i + 24 <= len(cabeza):
                hz = int.from_bytes(cabeza[i + 12:i + 16], "little")
                bits = int.from_bytes(cabeza[i + 22:i + 24], "little")
                return (hz, bits) if hz else None
            i += 8 + tamano + (tamano & 1)
    return None


def mensaje_claro(error: Exception) -> str:
    """Convierte un fallo del motor en algo que se entienda."""
    crudo = str(error)
    plano = crudo.lower()
    for pista, explicacion in EXPLICACIONES:
        if pista in plano:
            return explicacion
    return f"No se pudo completar la descarga: {crudo}"


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
                info = _extraer(engine, request.url, download=False)
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

    def quality(self, request: DownloadRequest) -> AudioQuality:
        """Qué audio se bajaría de verdad, sin bajarlo.

        Elige con la misma selección de formato que la descarga, así que dice
        exactamente lo que va a llegar. De paso comprueba que se pueda bajar:
        un tema con DRM o retirado falla aquí, antes de empezar, y no a mitad.
        """
        YoutubeDL, YoutubeDLError, _ = _cargar_motor()
        opciones = {
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "color": "no_color",
            "socket_timeout": 30,
            "js_runtimes": _runtimes_js(),
            "format": self._seleccion_formato(request.options),
        }
        try:
            with YoutubeDL(opciones) as engine:
                info = _extraer(engine, request.url, download=False)
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(mensaje_claro(exc)) from exc
        if not info:
            raise DownloadError("No se obtuvo información. Comprueba la URL.")
        if info.get("_type") in {"playlist", "multi_video"}:
            raise DownloadError("Pasa la URL de un video individual, no de una lista o canal.")
        return calidad_de(info)

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
                info = _extraer(engine, request.url, download=False, process=False)
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
        if query.source == "audius":
            return self._buscar_en_audius(query)
        if query.source == "bandcamp":
            return self._buscar_en_bandcamp(query)

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
    def _buscar_en_audius(query: SearchQuery) -> tuple[VideoInfo, ...]:
        """Busca en Audius, donde los artistas suben su música tal cual.

        Su API es pública y sin clave, y ya dice aquí la calidad de cada pista:
        todo lo que se puede escuchar va a 320 kb/s, y cuando el artista deja
        bajar el original suele ser un WAV sin pérdida. Lo que es de pago o
        está restringido se descarta, porque no se podría bajar.
        """
        direccion = f"{AUDIUS_API}/tracks/search?" + urlencode(
            {"query": query.text, "app_name": APP_AUDIUS, "limit": query.limit})
        resultados = []
        for pista in _consultar(direccion, "Audius").get("data") or []:
            calidad = calidad_audius(pista)
            if calidad is None or not pista.get("permalink"):
                continue
            resultados.append(VideoInfo(
                title=pista.get("title") or "(sin título)",
                uploader=(pista.get("user") or {}).get("name"),
                duration=pista.get("duration"),
                url=f"https://audius.co{pista['permalink']}",
                thumbnail=(pista.get("artwork") or {}).get("480x480") or "",
                quality=calidad,
            ))
        return tuple(resultados)

    @staticmethod
    def _buscar_en_bandcamp(query: SearchQuery) -> tuple[VideoInfo, ...]:
        """Busca canciones en Bandcamp con el buscador de su propia web.

        Allí lo normal es escuchar a 128 kb/s y pagar por el FLAC, pero hay
        artistas que lo regalan, y entonces el motor baja el original sin
        pérdida. Cuál es cuál solo se sabe comprobándolo: aquí no se promete.
        """
        cuerpo = json.dumps({
            "search_text": query.text,
            "search_filter": "t",
            "full_page": False,
            "fan_id": None,
        }).encode()
        datos = _consultar(BUSCADOR_BANDCAMP, "Bandcamp", cuerpo)
        resultados = (datos.get("auto") or {}).get("results") or []
        return tuple(
            VideoInfo(
                title=r.get("name") or "(sin título)",
                uploader=r.get("band_name"),
                url=r["item_url_path"],
                thumbnail=r.get("img") or "",
            )
            for r in resultados[:query.limit]
            if r.get("item_url_path")
        )

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
                # Lo que llega en trozos (HLS de SoundCloud, el original de
                # Audius) se pide en varias conexiones a la vez.
                "concurrent_fragment_downloads": CONEXIONES_PARALELAS,
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
                info = _extraer(engine, request.url, download=False, process=False)
                if info and info.get("_type") in {"playlist", "multi_video"}:
                    raise DownloadError("Pasa la URL de un video individual, no de una lista o canal.")
                procesado = engine.process_ie_result(info, download=True) if info else None
            existentes = tuple(dict.fromkeys(p for p in archivos if p.is_file()))
            if not existentes:
                if opts.use_archive:
                    # Ya figuraba en el registro: se omite, no es un fallo.
                    return DownloadResult(())
                raise DownloadError("No se obtuvo ningún archivo. Comprueba la URL.")
            return DownloadResult(existentes, quality=self._calidad_bajada(procesado, existentes))
        except (YoutubeDLError, OSError, RuntimeError) as exc:
            raise DownloadError(mensaje_claro(exc)) from exc

    @staticmethod
    def _calidad_bajada(info: dict | None, archivos: tuple[Path, ...] = ()) -> AudioQuality | None:
        """Lo que llegó, para poder decirlo luego. Sin ello no se pierde nada.

        Si llegó sin pérdida y se guardó así, se completa con los bits y la
        frecuencia del propio archivo: la web no los dice, el archivo sí.
        """
        if not info:
            return None
        try:
            calidad = calidad_de(info)
        except DownloadError:
            return None
        if calidad.lossless:
            for archivo in archivos:
                cabecera = cabecera_sin_perdida(archivo)
                if cabecera:
                    return replace(calidad, hz=cabecera[0], bits=cabecera[1])
        return calidad

    @staticmethod
    def _seleccion_formato(opts: DownloadOptions) -> str:
        if opts.audio_only:
            if opts.audio_format in FORMATOS_SIN_PERDIDA:
                return "ba/b"
            # Para un MP3 no hace falta bajar el WAV original de 70 MB y
            # convertirlo: si hay un origen comprimido, se usa ese. En Audius,
            # su MP3 a 320 pesa una séptima parte y se copia sin reconvertir.
            return "ba[acodec!~='^(flac|alac|wav|aiff|pcm)']/ba/b"
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


#: Quién dice ser la app al pedir. MusicBrainz exige identificarse de verdad.
AGENTE = "descargador (proyecto academico)"


def _json_remoto(direccion: str) -> dict:
    """Pide un JSON y devuelve {} si algo sale mal.

    Quedarse sin carátula no puede tumbar una descarga que ya salió bien, así
    que aquí ningún fallo sube: se responde vacío y el siguiente proveedor lo
    intenta.
    """
    try:
        peticion = Request(direccion, headers={"User-Agent": AGENTE})
        with urlopen(peticion, timeout=20) as respuesta:
            datos = json.loads(respuesta.read().decode("utf-8"))
    except (OSError, ValueError):
        return {}
    return datos if isinstance(datos, dict) else {}


def _portada_itunes(artista: str, titulo: str, lado: int) -> str | None:
    """El catálogo de Apple. El que mejor resolución da: 1200 píxeles."""
    datos = _json_remoto("https://itunes.apple.com/search?" + urlencode({
        "term": f"{artista} {titulo}".strip(),
        "entity": "song",
        "limit": 1,
    }))
    resultados = datos.get("results") or []
    if not resultados:
        return None
    # Devuelve una miniatura de 100, pero la misma imagen existe en grande
    # cambiándole la medida a la propia dirección.
    pequena = str(resultados[0].get("artworkUrl100") or "")
    return pequena.replace("100x100bb", f"{lado}x{lado}bb") if pequena else None


def _portada_deezer(artista: str, titulo: str, lado: int) -> str | None:
    """Deezer. Menos resolución que Apple, pero encuentra bastante más.

    Medido: da la cara con los remixes y las sesiones largas, que es justo
    donde el catálogo de Apple se queda en blanco.
    """
    datos = _json_remoto("https://api.deezer.com/search?" + urlencode({
        "q": f"{artista} {titulo}".strip(),
        "limit": 1,
    }))
    resultados = datos.get("data") or []
    if not resultados:
        return None
    album = resultados[0].get("album") or {}
    return str(album.get("cover_xl") or "") or None


def _portada_coverart(artista: str, titulo: str, lado: int) -> str | None:
    """MusicBrainz y su archivo de carátulas, ambos abiertos.

    Va el último de los tres porque falla más con lo comercial, pero recoge
    ediciones y rarezas que los otros dos no tienen fichadas.
    """
    if not artista.strip():
        return None
    datos = _json_remoto("https://musicbrainz.org/ws/2/release?" + urlencode({
        "query": f'artist:"{artista}" AND release:"{titulo}"',
        "fmt": "json",
        "limit": 1,
    }))
    ediciones = datos.get("releases") or []
    if not ediciones:
        return None
    identificador = str(ediciones[0].get("id") or "")
    if not identificador:
        return None
    return f"https://coverartarchive.org/release/{identificador}/front-{lado}"


#: A quién se le pregunta por la carátula y en qué orden.
#:
#: Primero el que da la imagen más grande y, según se baja, los que encuentran
#: más cosas. Se para en el primero que responda, así que en lo corriente solo
#: se consulta uno. Si ninguno la tiene, la canción se queda con el fotograma
#: del vídeo, que es como estaba antes.
PROVEEDORES_PORTADA: tuple[tuple[str, Callable[[str, str, int], str | None]], ...] = (
    ("itunes", _portada_itunes),
    ("deezer", _portada_deezer),
    ("coverart", _portada_coverart),
)


def buscar_portada(artista: str, titulo: str, *, lado: int = 1200) -> str | None:
    """Dirección de la carátula oficial, o None si no la tiene nadie."""
    if not f"{artista}{titulo}".strip():
        return None
    for _nombre, buscar in PROVEEDORES_PORTADA:
        try:
            direccion = buscar(artista, titulo, lado)
        except Exception:
            # Un proveedor que se porte raro no puede dejar sin probar a los
            # que vienen detrás.
            continue
        if direccion:
            return direccion
    return None


def descargar_portada(direccion: str, destino: Path) -> bool:
    """Trae la imagen a disco. Devuelve si lo consiguió."""
    try:
        peticion = Request(direccion, headers={"User-Agent": "descargador"})
        with urlopen(peticion, timeout=30) as respuesta:
            imagen = respuesta.read()
    except OSError:
        return False
    if not imagen:
        return False
    try:
        destino.write_bytes(imagen)
    except OSError:
        return False
    return True


def incrustar_portada(origen: Path, destino: Path, imagen: Path) -> None:
    """Pega la imagen dentro del audio, sustituyendo la que tuviera.

    «-map 0:a» coge solo el sonido del original, de modo que la carátula vieja
    se queda fuera; si no, quedarían las dos y cada reproductor enseñaría la
    que le diera la gana. El audio pasa con «-c copy», sin recomprimir.
    """
    if not origen.is_file():
        raise DownloadError("No se encontró el archivo al que poner la carátula.")
    if not imagen.is_file():
        raise DownloadError("No se encontró la imagen de la carátula.")
    ffmpeg = _preparar_ffmpeg()
    orden = [
        ffmpeg, "-y", "-i", str(origen), "-i", str(imagen),
        "-map", "0:a", "-map", "1:v", "-c", "copy",
        "-id3v2_version", "3",
        "-metadata:s:v", "title=Album cover",
        "-metadata:s:v", "comment=Cover (front)",
        "-disposition:v", "attached_pic",
        str(destino),
    ]
    try:
        resultado = subprocess.run(orden, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise DownloadError(f"No se pudo ejecutar FFmpeg: {exc}") from exc
    if resultado.returncode != 0 or not destino.is_file():
        detalle = (resultado.stderr or "").strip().splitlines()
        raise DownloadError(
            "No se pudo incrustar la carátula: " + (detalle[-1] if detalle else "falló FFmpeg"))


def partes_del_nombre(nombre: str) -> tuple[str, str]:
    """Artista y tema sacados del nombre de archivo.

    Con las etiquetas limpias los archivos salen como «Artista - Tema [id]», y
    eso basta para buscar la carátula. Sin guion no hay artista que sacar.
    """
    limpio = re.sub(r"\.[a-zA-Z0-9]{2,4}$", "", nombre)
    limpio = re.sub(r"\s*\[[^\]]+\]\s*$", "", limpio).strip()
    corte = re.search(rf"\s+[{GUIONES}]\s+", limpio)
    if not corte:
        return "", limpio
    return limpio[: corte.start()].strip(), limpio[corte.end() :].strip()


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
