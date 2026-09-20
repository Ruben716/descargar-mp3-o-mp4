"""Puente entre Kotlin y el nucleo Python que comparte con la consola.

Kotlin no entiende los objetos del dominio, asi que cada funcion devuelve un
JSON. Del lado de Flutter basta con un jsonDecode.
"""
import json
import sys
from pathlib import Path

from descargador.application import InspectVideo
from descargador.domain import DownloadError
from descargador.infrastructure import YtDlpDownloader


def _respuesta(datos: dict) -> str:
    return json.dumps(datos, ensure_ascii=False)


def diagnostico() -> str:
    """Comprueba que Python y yt-dlp viajan dentro del APK."""
    datos: dict = {
        "python": sys.version.split()[0],
        "plataforma": sys.platform,
    }
    try:
        import yt_dlp

        datos["yt_dlp"] = yt_dlp.version.__version__
    except ImportError as exc:
        datos["yt_dlp"] = f"no disponible ({exc})"
    try:
        from yt_dlp.globals import supported_js_runtimes

        datos["runtimes_js"] = list(supported_js_runtimes.value.keys())
    except ImportError:
        datos["runtimes_js"] = []
    return _respuesta(datos)


def informacion(url: str) -> str:
    """Consulta un video sin descargarlo. Es la prueba de la fase 0."""
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
