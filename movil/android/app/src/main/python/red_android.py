"""Manejador de red que sale por el propio Android en vez de por Python.

Hay webs (TikTok) que miran la huella del saludo TLS y rechazan a quien no
parece un navegador. El Python del telefono trae su propio OpenSSL y esa huella
no cuela; la biblioteca que yt-dlp usa para disimularla (curl_cffi) no existe
para Android. Pero el sistema si tiene una pila de red con huella de navegador,
la misma que usa Chrome, y desde Python se puede llamar.

No se usa siempre: solo cuando una descarga ya choco con ese muro. Asi lo que
hoy funciona (YouTube, Instagram) sigue yendo por el camino de siempre.
"""
from __future__ import annotations

import io
from collections.abc import Callable

from yt_dlp.networking import Response
from yt_dlp.networking.common import RequestHandler, register_preference, register_rh
from yt_dlp.networking.exceptions import HTTPError, TransportError, UnsupportedRequest

#: Firma del backend: (url, metodo, cabeceras, cuerpo) -> (estado, url, cabeceras, cuerpo).
#:
#: Se inyecta en vez de llamar a Java directamente para poder probar todo esto
#: en el escritorio, donde no hay Android que valga.
Backend = Callable[[str, str, dict, bytes | None], tuple[int, str, dict, bytes]]

_backend: Backend | None = None


def activar(backend: Backend) -> None:
    """Enciende la salida por Android. Sin esto el manejador se aparta."""
    global _backend
    _backend = backend


def desactivar() -> None:
    global _backend
    _backend = None


def activo() -> bool:
    return _backend is not None


class RedAndroidRH(RequestHandler):
    """Pide por la red del sistema y devuelve lo que yt-dlp espera."""

    _SUPPORTED_URL_SCHEMES = ("http", "https")
    RH_NAME = "android"

    def _validate(self, request):
        if _backend is None:
            # Apartarse asi es lo que deja que yt-dlp siga con el de siempre.
            raise UnsupportedRequest("la salida por Android esta apagada")
        super()._validate(request)

    def _check_extensions(self, extensions):
        super()._check_extensions(extensions)
        # Las cookies y el tiempo de espera los lleva el sistema, no nosotros.
        extensions.pop("cookiejar", None)
        extensions.pop("timeout", None)
        extensions.pop("legacy_ssl", None)
        extensions.pop("impersonate", None)

    def _send(self, request):
        assert _backend is not None
        try:
            estado, url, cabeceras, cuerpo = _backend(
                request.url,
                request.method,
                dict(request.headers),
                request.data,
            )
        except Exception as exc:
            raise TransportError(cause=exc) from exc

        respuesta = Response(
            fp=io.BytesIO(cuerpo),
            url=url,
            headers=cabeceras,
            status=estado,
        )
        # Igual que el manejador de serie: un 4xx o 5xx se cuenta como error,
        # no como una respuesta buena con un numero raro.
        if 200 <= estado < 300:
            return respuesta
        raise HTTPError(respuesta)


register_rh(RedAndroidRH)


@register_preference(RedAndroidRH)
def _preferir_android(rh, request):
    """Cuando esta encendido, manda este; si no, ni se mira."""
    return 1000 if activo() else -1000
