"""Letras de YouTube Music por el id del video, sincronizadas cuando las hay.

Hace lo mismo que ytmusicapi (get_watch_playlist y get_lyrics con tiempos)
con la biblioteca estandar, sin cuenta ni cookies de sesion. Se pide por el
id del video de la cancion bajada, asi que no puede confundirse de tema, que
es lo que le pasa a una busqueda por nombre.

Son tres pasos: «next» dice donde esta la pestana de la letra (un browseId que
empieza por MPLY); «browse» con el cliente movil la da con tiempos cuando
YouTube los tiene (LyricFind o Musixmatch); y si no, el cliente web da la
letra plana. YouTube cambia la forma de sus respuestas sin avisar: todo se
recorre con _nav, que devuelve None en vez de lanzar.

Vive junto al puente y no en el nucleo: la consola no lo necesita.
"""
from __future__ import annotations

import gzip
import http.client
import json
import re
import time
import zlib
from collections.abc import Iterable
from typing import Any
from urllib.request import Request, urlopen

API = "https://music.youtube.com/youtubei/v1/"
ORIGEN = "https://music.youtube.com"
NAVEGADOR = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
#: El cliente movil es el unico al que YouTube le da los tiempos de cada linea.
CLIENTE_MOVIL = {"clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50", "hl": "es"}

PESTANAS = ("contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer",
            "watchNextTabbedResultsRenderer", "tabs")
CON_TIEMPOS = ("contents", "elementRenderer", "newElement", "type", "componentType", "model",
               "timedLyricsModel", "lyricsData")
SECCIONES = ("contents", "sectionListRenderer", "contents")

_ID_VIDEO = re.compile(r"[A-Za-z0-9_-]{11}")
_SIN_LETRA = {"ok": True, "lrc": "", "texto": "", "fuente": ""}


def _nav(datos: Any, *claves: str | int) -> Any:
    """datos[c1][c2]... o None si algo falta o no tiene la forma esperada."""
    for clave in claves:
        if isinstance(clave, int):
            if not isinstance(datos, list) or not -len(datos) <= clave < len(datos):
                return None
        elif not isinstance(datos, dict) or clave not in datos:
            return None
        datos = datos[clave]
    return datos


def _texto(valor: Any) -> str:
    """El texto de un campo que unas veces es una cadena y otras va en «runs».

    Se unen todos los trozos y no solo el primero, como hace ytmusicapi: si
    YouTube parte la letra en varios, no se pierde el resto.
    """
    if isinstance(valor, str):
        return valor
    trozos = _nav(valor, "runs")
    if isinstance(trozos, list):
        return "".join(t for t in (_nav(r, "text") for r in trozos) if isinstance(t, str))
    sencillo = _nav(valor, "simpleText")
    return sencillo if isinstance(sencillo, str) else ""


def _milisegundos(valor: Any) -> int | None:
    """Los milisegundos de un cueRange, que YouTube manda como texto."""
    if isinstance(valor, bool):
        return None
    if isinstance(valor, int):
        return valor if valor >= 0 else None
    if isinstance(valor, str) and valor.strip().isdecimal():
        return int(valor)
    return None


def browse_id(datos_next: Any) -> str | None:
    """La pestana de la letra en la respuesta de «next», o None si no tiene.

    Suele ser la segunda (A continuacion, Letra, Relacionado), pero se busca
    por su prefijo y no por el puesto: si YouTube cambia el orden no se pide
    otra pestana creyendo que es la letra. Sin letra la pestana sigue ahi,
    marcada «unselectable».
    """
    pestanas = _nav(datos_next, *PESTANAS)
    if not isinstance(pestanas, list):
        return None
    for pestana in pestanas:
        renderer = _nav(pestana, "tabRenderer")
        if not isinstance(renderer, dict) or "unselectable" in renderer:
            continue
        ident = _nav(renderer, "endpoint", "browseEndpoint", "browseId")
        if isinstance(ident, str) and ident.startswith("MPLY"):
            return ident
    return None


def lineas_con_tiempo(datos_browse: Any) -> list[tuple[int, str]] | None:
    """Las lineas con su inicio en milisegundos, en orden, o None si no hay.

    Una linea rota se salta en vez de tirar la letra entera; si no queda
    ninguna con texto, es que no habia letra sincronizada.
    """
    filas = _nav(datos_browse, *CON_TIEMPOS, "timedLyricsData")
    if not isinstance(filas, list):
        return None
    lineas: list[tuple[int, str]] = []
    for fila in filas:
        texto = _nav(fila, "lyricLine")
        inicio = _milisegundos(_nav(fila, "cueRange", "startTimeMilliseconds"))
        if isinstance(texto, str) and inicio is not None:
            # Un salto de linea dentro partiria la fila del LRC en dos.
            lineas.append((inicio, " ".join(texto.split())))
    lineas.sort(key=lambda linea: linea[0])
    return lineas if any(texto for _, texto in lineas) else None


def fuente_con_tiempo(datos_browse: Any) -> str:
    """De donde sale la letra sincronizada («Fuente: LyricFind», por ejemplo)."""
    return _texto(_nav(datos_browse, *CON_TIEMPOS, "sourceMessage")).strip()


def letra_simple(datos_browse: Any) -> tuple[str, str] | None:
    """La letra plana y su fuente, o None si la respuesta no la trae."""
    secciones = _nav(datos_browse, *SECCIONES)
    if not isinstance(secciones, list):
        return None
    for seccion in secciones:
        estante = _nav(seccion, "musicDescriptionShelfRenderer")
        if not isinstance(estante, dict):
            continue
        texto = _texto(estante.get("description")).replace("\r\n", "\n").strip()
        if texto:
            return texto, _texto(estante.get("footer")).strip()
    return None


def a_lrc(lineas: Iterable[tuple[int, str]]) -> str:
    """Las lineas en formato LRC, «[mm:ss.cc]texto», como _aLrc de letras.dart."""
    return "\n".join(
        f"[{ms // 60000:02d}:{ms // 1000 % 60:02d}.{ms % 1000 // 10:02d}]{texto}"
        for ms, texto in lineas
    )


class _SinRespuesta(Exception):
    """YouTube no contesto, o lo que contesto no era JSON."""


def _cliente_web() -> dict[str, str]:
    # La version lleva la fecha de hoy, como la de la web: una vieja se rechaza.
    version = time.strftime("1.%Y%m%d.01.00", time.gmtime())
    return {"clientName": "WEB_REMIX", "clientVersion": version, "hl": "es"}


def _pedir(metodo: str, cliente: dict[str, str], cuerpo: dict[str, Any],
           timeout: float, visitante: str = "") -> Any:
    """Un POST a la API interna de YouTube Music, ya leido como JSON."""
    cabeceras = {
        "Content-Type": "application/json",
        "Accept-Encoding": "gzip",
        "Origin": ORIGEN,
        "Referer": ORIGEN + "/",
        "User-Agent": NAVEGADOR,
        # Sin ella, desde Europa llega la pantalla de consentimiento.
        "Cookie": "SOCS=CAI",
    }
    if visitante:
        # El visitante que dio «next»: las siguientes van como la misma visita.
        cabeceras["X-Goog-Visitor-Id"] = visitante
    datos = {"context": {"client": cliente, "user": {}}, **cuerpo}
    peticion = Request(f"{API}{metodo}?prettyPrint=false", data=json.dumps(datos).encode("utf-8"),
                       headers=cabeceras, method="POST")
    try:
        with urlopen(peticion, timeout=timeout) as respuesta:
            crudo = respuesta.read()
        if crudo[:2] == b"\x1f\x8b":
            crudo = gzip.decompress(crudo)
        return json.loads(crudo.decode("utf-8"))
    # HTTPException no hereda de OSError (una respuesta cortada lanza
    # IncompleteRead) y un gzip a medias da EOFError o zlib.error.
    except (OSError, http.client.HTTPException, EOFError, zlib.error, ValueError) as exc:
        raise _SinRespuesta(f"{type(exc).__name__}: {exc}") from exc


def letra(video_id: str, timeout: float = 10) -> dict[str, Any]:
    """La letra de un video de YouTube Music. Nunca lanza.

    Devuelve {"ok": True, "lrc", "texto", "fuente"}: lrc va vacio si YouTube
    no tiene los tiempos, y los tres vacios si el tema no tiene letra; con
    «completa» en False si es la plana porque el cliente de los tiempos no
    respondio. Si no se pudo preguntar, {"ok": False, "error"}, que no es lo
    mismo que no tener.
    """
    if not isinstance(video_id, str) or not _ID_VIDEO.fullmatch(video_id):
        return {"ok": False, "error": "Id de video no valido."}
    try:
        siguiente = _pedir("next", _cliente_web(), {
            "videoId": video_id,
            "isAudioOnly": True,
            "enablePersistentPlaylistPanel": True,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        }, timeout)
        pestana = browse_id(siguiente)
        if pestana is None:
            return dict(_SIN_LETRA)
        visitante = _texto(_nav(siguiente, "responseContext", "visitorData"))
        # Primero el cliente movil, que es el que da los tiempos. Si falla
        # (YouTube puede retirar esa version) aun queda la letra plana.
        fallo: _SinRespuesta | None = None
        movil: Any = None
        try:
            movil = _pedir("browse", CLIENTE_MOVIL, {"browseId": pestana}, timeout, visitante)
        except _SinRespuesta as exc:
            fallo = exc
        lineas = lineas_con_tiempo(movil)
        if lineas:
            return {
                "ok": True,
                "lrc": a_lrc(lineas),
                "texto": "\n".join(texto for _, texto in lineas),
                "fuente": fuente_con_tiempo(movil),
            }
        # A veces el cliente movil ya trae la plana; si no, se pide a la web.
        simple = letra_simple(movil)
        if simple is None:
            web = _pedir("browse", _cliente_web(), {"browseId": pestana}, timeout, visitante)
            simple = letra_simple(web)
        if simple is None:
            if fallo is not None:
                # Sin respuesta del cliente movil no se puede decir que no la tenga.
                raise fallo
            return dict(_SIN_LETRA)
        texto, fuente = simple
        respuesta = {"ok": True, "lrc": "", "texto": texto, "fuente": fuente}
        if fallo is not None:
            # La plana vale para ahora, pero los tiempos quiza si los tenga:
            # que la app no la guarde como si fuera todo lo que hay.
            respuesta["completa"] = False
        return respuesta
    except _SinRespuesta as exc:
        return {"ok": False, "error": f"YouTube Music no respondio: {exc}"}
    except Exception as exc:
        # Lo pide el puente: una excepcion sin capturar cruzaria hasta Kotlin.
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
