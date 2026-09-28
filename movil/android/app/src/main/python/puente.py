"""Puente entre Kotlin y el nucleo Python que comparte con la consola.

Kotlin no entiende los objetos del dominio, asi que cada funcion devuelve un
JSON. Del lado de Flutter basta con un jsonDecode.
"""
import json
import shutil
import sys
from pathlib import Path

from descargador.application import (
    CheckQuality,
    DownloadVideo,
    ImportPlaylist,
    InspectVideo,
    SearchVideos,
    StreamVideo,
)
from descargador.domain import (
    AudioQuality,
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    parse_section,
)
from descargador.infrastructure import (
    YtDlpDownloader,
    buscar_portada,
    configurar_entorno,
    descargar_portada,
    escribir_etiquetas,
    incrustar_portada,
    necesita_portada_oficial,
    nombre_con_etiquetas,
    partes_del_nombre,
)

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


def _calidad_json(calidad: AudioQuality | None) -> dict | None:
    if calidad is None:
        return None
    return {
        "codec": calidad.codec,
        "kbps": calidad.kbps,
        "hz": calidad.hz,
        "bits": calidad.bits,
        "sinPerdida": calidad.lossless,
    }


def calidad(url: str) -> str:
    """Que audio llegaria de un enlace y si se puede bajar, sin bajarlo."""
    try:
        resultado = CheckQuality(YtDlpDownloader()).execute(url)
        return _respuesta({"ok": True, **(_calidad_json(resultado) or {})})
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc)})
    except Exception as exc:
        return _respuesta({"ok": False, "error": f"{type(exc).__name__}: {exc}"})


def precalentar() -> str:
    """Carga el motor en segundo plano para que la primera busqueda no espere.

    Importar yt-dlp y sus extractores es lo mas lento de la primera busqueda:
    hacerlo mientras el usuario aun esta escribiendo esconde esa espera.
    """
    try:
        from yt_dlp import YoutubeDL

        with YoutubeDL({"quiet": True, "no_warnings": True}) as motor:
            for nombre in ("Youtube", "YoutubeSearch", "SoundcloudSearch"):
                motor.get_info_extractor(nombre)
        return _respuesta({"ok": True})
    except Exception as exc:
        return _respuesta({"ok": False, "error": f"{type(exc).__name__}: {exc}"})


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
              fragmento: str = "", sin_patrocinios: bool = False,
              normalizar: bool = False, etiquetas_limpias: bool = True,
              cookies: str = "", nativo: bool = False,
              portada_oficial: bool = True) -> str:
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
            # Igualar el volumen obliga a reconvertir, asi que solo se pide
            # cuando se baja audio; en video el dominio lo rechazaria.
            normalize=bool(normalizar) and bool(solo_audio),
            clean_tags=bool(etiquetas_limpias),
            # En el movil el contenedor importa: MKV o VP9 no se reproducen.
            prefer_mp4=True,
        )
        # Las cookies y la salida por Android solo llegan cuando Kotlin ya
        # choco con un muro anti-robots; en lo normal no se tocan.
        if nativo:
            _encender_red_android()
        motor = YtDlpDownloader(_anotar, registro, cookies or None)
        resultado = DownloadVideo(motor).execute(url, Path(carpeta), opciones)
        archivos = list(resultado.files)
        # Solo donde la imagen es un fotograma: en las demas ya es la del disco.
        if solo_audio and portada_oficial and necesita_portada_oficial(url):
            _AVANCE["status"] = "portada"
            archivos = [_ponerPortadaOficial(a) for a in archivos]
        _AVANCE["status"] = "listo"
        return _respuesta({
            "ok": True,
            "archivos": [str(a) for a in archivos],
            # Lo que llego de verdad: la calidad del origen, no la del archivo.
            "origen": _calidad_json(resultado.quality),
        })
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
    finally:
        # Se apaga pase lo que pase: la siguiente descarga tiene que volver a
        # salir por el camino de siempre.
        if nativo:
            _apagar_red_android()


def buscar(texto: str, limite: int, fuente: str = "youtube") -> str:
    """Busca por nombre. En un movil es mas comodo que pegar una URL."""
    try:
        resultados = SearchVideos(YtDlpDownloader()).execute(texto, int(limite), fuente)
        return _respuesta({
            "ok": True,
            "resultados": [
                {
                    "titulo": r.title,
                    "autor": r.uploader or "",
                    "duracion": r.duration or 0,
                    "url": r.url,
                    "miniatura": r.thumbnail,
                    # Solo cuando la fuente ya la dice al buscar (Audius).
                    "calidad": _calidad_json(r.quality),
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


def importar_lista(url: str) -> str:
    """Trae las pistas de una lista de reproduccion ajena."""
    try:
        lista = ImportPlaylist(YtDlpDownloader()).execute(url)
        return _respuesta({
            "ok": True,
            "titulo": lista.title,
            "resultados": [
                {
                    "titulo": p.title,
                    "autor": p.uploader or "",
                    "duracion": p.duration or 0,
                    "url": p.url,
                    "miniatura": p.thumbnail,
                }
                for p in lista.items
            ],
        })
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc)})
    except Exception as exc:
        return _respuesta({"ok": False, "error": f"{type(exc).__name__}: {exc}"})


def etiquetar(origen: str, destino: str, titulo: str, artista: str, nombre: str) -> str:
    """Reescribe titulo y artista de un audio ya descargado.

    Trabaja sobre copias porque el archivo de verdad vive en MediaStore y solo
    se llega a el por un descriptor: Kotlin trae una copia, esto la reetiqueta
    y Kotlin devuelve el resultado a su sitio. Ademas calcula el nombre que le
    corresponde, que es lo que se ve en la biblioteca.
    """
    try:
        escribir_etiquetas(Path(origen), Path(destino), titulo=titulo, artista=artista)
        return _respuesta({
            "ok": True,
            "nombre": nombre_con_etiquetas(nombre, titulo=titulo, artista=artista),
        })
    except DownloadError as exc:
        return _respuesta({"ok": False, "error": str(exc)})


def _backend_android(url: str, metodo: str, cabeceras: dict, datos):
    """Manda la peticion por la red del sistema y traduce la respuesta."""
    # jclass y no «from com... import»: es la forma que documenta Chaquopy y
    # da un error entendible si la clase no viaja en el APK.
    from java import jclass  # type: ignore[import-not-found]

    red = jclass("com.ruben.descargador_movil.RedNativa")
    respuesta = red.pedir(url, metodo, json.dumps(cabeceras), datos)
    return (
        respuesta.estado,
        respuesta.url,
        json.loads(respuesta.cabeceras),
        bytes(respuesta.cuerpo),
    )


def _encender_red_android() -> None:
    """Hace que yt-dlp salga por Android en esta descarga.

    Se importa aqui y no arriba porque el modulo arrastra yt_dlp, y cargarlo al
    abrir la app retrasaria el arranque sin que casi nunca haga falta.
    """
    try:
        import red_android

        red_android.activar(_backend_android)
    except Exception:
        # Sin esto se sigue por el camino de siempre: peor el fallo de antes
        # que quedarse sin descargar nada.
        pass


def _apagar_red_android() -> None:
    try:
        import red_android

        red_android.desactivar()
    except Exception:
        pass


def _ponerPortadaOficial(archivo: Path) -> Path:
    """Cambia el fotograma de YouTube por la caratula oficial del tema.

    Si algo falla se devuelve el archivo tal cual: la descarga ya salio bien y
    quedarse sin la portada buena no es motivo para perderla.
    """
    try:
        artista, titulo = partes_del_nombre(archivo.name)
        direccion = buscar_portada(artista, titulo)
        if not direccion:
            return archivo

        imagen = archivo.with_name(f"{archivo.stem}.portada.jpg")
        if not descargar_portada(direccion, imagen):
            return archivo

        conPortada = archivo.with_name(f"{archivo.stem}.conportada{archivo.suffix}")
        try:
            incrustar_portada(archivo, conPortada, imagen)
            # Se ocupa el sitio del original para que arriba no cambie nada.
            archivo.unlink()
            conPortada.rename(archivo)
        finally:
            imagen.unlink(missing_ok=True)
            conPortada.unlink(missing_ok=True)
        return archivo
    except Exception:
        return archivo
