"""Puente entre Kotlin y el nucleo Python que comparte con la consola.

Kotlin no entiende los objetos del dominio, asi que cada funcion devuelve un
JSON. Del lado de Flutter basta con un jsonDecode.
"""
import json
import shutil
import sys
from pathlib import Path

from descargador.application import (
    DownloadVideo,
    InspectVideo,
    SearchVideos,
    StreamVideo,
)
from descargador.domain import (
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    parse_section,
)
from descargador.infrastructure import YtDlpDownloader, configurar_entorno

#: Ultimo avance publicado por el motor. Kotlin lo consulta mientras descarga.
_AVANCE: dict = {"status": "inactivo"}


def _respuesta(datos: dict) -> str:
    return json.dumps(datos, ensure_ascii=False)


def _anotar(avance: DownloadProgress) -> None:
    _AVANCE.update({
        "status": avance.status,
        "archivo": avance.filename,
        "descargado": avance.downloaded,
        "total": avance.total or 0,
        "porcentaje": round(avance.percent, 1) if avance.percent is not None else -1,
        "velocidad": int(avance.speed) if avance.speed else 0,
        "restante": avance.eta or 0,
    })


def progreso() -> str:
    """Estado actual de la descarga; Kotlin la consulta cada poco."""
    return _respuesta(_AVANCE)


def preparar(binarios: str, librerias: str) -> str:
    """Registra los binarios de FFmpeg que Kotlin extrajo del APK."""
    configurar_entorno(binarios, librerias)
    return _respuesta({
        "ffmpeg": shutil.which("ffmpeg") or "",
        "ffprobe": shutil.which("ffprobe") or "",
    })


def diagnostico() -> str:
    """Comprueba que Python y yt-dlp viajan dentro del APK."""
    datos: dict = {
        "python": sys.version.split()[0],
        "plataforma": sys.platform,
        "ffmpeg": shutil.which("ffmpeg") or "no encontrado",
        "ffprobe": shutil.which("ffprobe") or "no encontrado",
    }
    try:
        import yt_dlp

        datos["yt_dlp"] = yt_dlp.version.__version__
    except ImportError as exc:
        datos["yt_dlp"] = f"no disponible ({exc})"
    return _respuesta(datos)


def informacion(url: str) -> str:
    """Consulta un video sin descargarlo."""
    try:
        info = InspectVideo(YtDlpDownloader()).execute(url, Path("."))
        return _respuesta({
            "ok": True,
            "titulo": info.title,
            "autor": info.uploader or "",
            "duracion": info.duration or 0,
            "formatos": len(info.formats),
        })
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc)})
    except Exception as exc:
        # Frontera con Kotlin: una excepcion sin capturar cruzaria a Java y
        # tumbaria la app. Aqui se convierte en un error que Flutter puede pintar.
        return _respuesta({"ok": False, "error": f"{type(exc).__name__}: {exc}"})


class _Registro:
    """Recoge el log del motor para poder explicar un fallo sin consola."""

    def __init__(self, limite: int = 60):
        self.lineas: list[str] = []
        self._limite = limite

    def _anotar(self, mensaje: str) -> None:
        self.lineas.append(str(mensaje))
        del self.lineas[: max(0, len(self.lineas) - self._limite)]

    def debug(self, mensaje):
        self._anotar(mensaje)

    def info(self, mensaje):
        self._anotar(mensaje)

    def warning(self, mensaje):
        self._anotar(f"AVISO {mensaje}")

    def error(self, mensaje):
        self._anotar(f"ERROR {mensaje}")


def descargar(url: str, carpeta: str, solo_audio: bool, calidad: int,
              formato_audio: str, bitrate: str = "192", subtitulos: str = "",
              fragmento: str = "", sin_patrocinios: bool = False) -> str:
    """Descarga de verdad. Devuelve las rutas obtenidas."""
    _AVANCE.clear()
    _AVANCE["status"] = "preparando"
    registro = _Registro()
    try:
        opciones = DownloadOptions(
            audio_only=bool(solo_audio),
            quality=int(calidad) or None,
            audio_format=formato_audio or "mp3",
            audio_bitrate=bitrate or "192",
            subtitles=tuple(i.strip() for i in subtitulos.split(",") if i.strip()),
            section=parse_section(fragmento) if fragmento.strip() else None,
            skip_sponsors=bool(sin_patrocinios),
            # En el movil el contenedor importa: MKV o VP9 no se reproducen.
            prefer_mp4=True,
        )
        motor = YtDlpDownloader(_anotar, registro)
        resultado = DownloadVideo(motor).execute(url, Path(carpeta), opciones)
        _AVANCE["status"] = "listo"
        return _respuesta({"ok": True, "archivos": [str(r) for r in resultado.files]})
    except DownloadError as exc:
        _AVANCE["status"] = "error"
        return _respuesta({"ok": False, "error": str(exc), "registro": registro.lineas})
    except Exception as exc:
        _AVANCE["status"] = "error"
        return _respuesta({
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "registro": registro.lineas,
        })


def buscar(texto: str, limite: int) -> str:
    """Busca por nombre. En un movil es mas comodo que pegar una URL."""
    try:
        resultados = SearchVideos(YtDlpDownloader()).execute(texto, int(limite))
        return _respuesta({
            "ok": True,
            "resultados": [
                {
                    "titulo": r.title,
                    "autor": r.uploader or "",
                    "duracion": r.duration or 0,
                    "url": r.url,
                    "miniatura": r.thumbnail,
                }
                for r in resultados
            ],
        })
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc)})
    except Exception as exc:
        return _respuesta({"ok": False, "error": f"{type(exc).__name__}: {exc}"})


def previsualizar(url: str, solo_audio: bool) -> str:
    """Pista reproducible al vuelo, para oir antes de decidir si se descarga."""
    registro = _Registro()
    try:
        motor = YtDlpDownloader(registro=registro)
        pista = StreamVideo(motor).execute(url, audio_only=bool(solo_audio))
        return _respuesta({
            "ok": True,
            "url": pista.url,
            "titulo": pista.title,
            "cabeceras": dict(pista.headers),
        })
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc), "registro": registro.lineas})
    except Exception as exc:
        return _respuesta({
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "registro": registro.lineas,
        })
