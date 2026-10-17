"""Prueba de punta a punta contra internet de lo que las pruebas normales no tocan.

Cada fuente va en su propio bloque: si una falla se dice con su traza y se
sigue con las demás, y al final el proceso acaba con error para que el flujo
salga en rojo. Así una fuente caída no esconde lo que pasa con las otras.
"""
import sys
import traceback
from collections.abc import Callable
from pathlib import Path

from descargador.application import CheckQuality, StreamVideo
from descargador.domain import DownloadError, DownloadOptions, DownloadRequest, SearchQuery, VideoInfo
from descargador.infrastructure import YtDlpDownloader

motor = YtDlpDownloader()
fallos: list[str] = []


def bajar(url: str, carpeta: str, formato: str = "best") -> list[bytes]:
    """Mira la calidad como lo hace la app, baja la pista y dice qué llegó."""
    print("   calidad en origen:", CheckQuality(motor).execute(url))
    opciones = DownloadOptions(audio_only=True, audio_format=formato)
    res = motor.download(DownloadRequest(url, Path(carpeta), opciones))
    cabezas = []
    for f in res.files:
        cabeza = f.read_bytes()[:4]
        cabezas.append(cabeza)
        print("   BAJADO:", f.name, f.stat().st_size // 1024, "KB, empieza por", cabeza,
              "| llegó:", res.quality)
    if not res.files:
        raise AssertionError("no se bajó ningún archivo")
    return cabezas


def escuchar(url: str) -> None:
    """La escucha previa: una dirección que el reproductor pueda abrir ya."""
    pista = StreamVideo(motor).execute(url)
    print("   ESCUCHA:", pista.url[:120], "| cabeceras:", dict(pista.headers))


def listar(resultados: tuple[VideoInfo, ...]) -> None:
    for r in resultados:
        print("  ", r.uploader, "-", r.title, "|", r.duration, "s |", r.quality, "|", r.url)


def la_mas_corta(resultados) -> VideoInfo:
    con_duracion = [r for r in resultados if r.duration]
    return min(con_duracion or list(resultados), key=lambda r: r.duration or 10**9)


def seccion(nombre: str, prueba: Callable[[], None]) -> None:
    print(f"\n===== {nombre}")
    try:
        prueba()
    except Exception:
        traceback.print_exc()
        fallos.append(nombre)


def podcasts() -> None:
    programas = motor.search(SearchQuery("historia", limit=5, source="podcasts"))
    for p in programas:
        print("  ", p.uploader, "-", p.title, "|", p.url)
    lista = motor.playlist(programas[0].url)
    print("episodios de", lista.title, ":", len(lista.items))
    corto = min(lista.items, key=lambda e: e.duration or 10**9)
    print("el mas corto:", corto.title, corto.duration, "s |", corto.url[:160])
    bajar(corto.url, "podcast")


def hearthis() -> None:
    pistas = motor.search(SearchQuery("chill", limit=10, source="hearthis"))
    for p in pistas:
        print("  ", p.uploader, "-", p.title, p.duration, "|", p.url)
    corta = min((p for p in pistas if p.duration), key=lambda p: p.duration or 0)
    print("la mas corta:", corta.title, corta.duration)
    bajar(corta.url, "hearthis")


def commons() -> None:
    """Que salga el original (FLAC o WAV) y no la copia Ogg de Commons."""
    pistas = motor.search(SearchQuery("beethoven sonata", limit=10, source="commons"))
    listar(pistas)
    if not pistas:
        raise AssertionError("Commons no devolvió nada")
    sin_perdida = [p for p in pistas if p.quality and p.quality.lossless]
    print("sin pérdida:", len(sin_perdida), "de", len(pistas))
    corta = la_mas_corta(sin_perdida or pistas)
    print("la elegida:", corta.title, corta.duration, "s |", corta.quality)
    escuchar(corta.url)
    original = bool(corta.quality and corta.quality.lossless)
    cabezas = bajar(corta.url, "commons", "flac" if original else "best")
    if original and not any(c in (b"fLaC", b"RIFF") for c in cabezas):
        raise AssertionError(f"llegó una copia y no el original: {cabezas}")


def archive() -> None:
    """Lo de licencia libre entra, etree sigue entrando y se ven los 24 bits."""
    discos = motor.search(SearchQuery("goldberg variations", limit=10, source="archive"))
    listar(discos)
    conciertos = motor.search(SearchQuery("grateful dead", limit=5, source="archive"))
    print("conciertos de etree:")
    listar(conciertos)
    if not discos or not conciertos:
        raise AssertionError("el Archive no devolvió nada en alguna de las dos")
    hires = [d for d in (*discos, *conciertos) if d.quality and d.quality.bits == 24]
    print("dicen 24 bits al buscar:", len(hires))
    elegido = hires[0] if hires else discos[0]
    lista = motor.playlist(elegido.url)
    print("pistas de", lista.title, ":", len(lista.items))
    corta = la_mas_corta(lista.items)
    print("la mas corta:", corta.title, corta.duration, "s |", corta.url)
    # Regresión medida aquí: la pista apuntaba a la página del álbum entero, y
    # bajarla pedía el concierto completo, que se rechaza por ser una lista.
    bajar(corta.url, "archive", "flac")


def ccmixter() -> None:
    """Con todas sus manías: cabecera enorme, JSON roto y Referer."""
    pistas = motor.search(SearchQuery("piano", limit=10, source="ccmixter"))
    listar(pistas)
    if not pistas:
        raise AssertionError("ccMixter no devolvió nada")
    # 25 pedidas: se piden 10 para que la cabecera X-JSON quepa.
    muchas = motor.search(SearchQuery("remix", limit=25, source="ccmixter"))
    print("pidiendo 25 llegaron", len(muchas), "sin que reventara la cabecera")
    corta = la_mas_corta(pistas)
    print("la mas corta:", corta.title, corta.duration, "s |", corta.quality)
    escuchar(corta.url)
    bajar(corta.url, "ccmixter")


def ytmusic() -> None:
    """Canciones con artista y carátula oficiales."""
    canciones = motor.search(SearchQuery("bad bunny", limit=5, source="ytmusic"))
    for c in canciones:
        print("  ", c.uploader, "-", c.title, "|", c.duration, "s |", c.url, "|", c.thumbnail)
    if not canciones:
        raise AssertionError("YouTube Music no devolvió nada")
    if not all(c.uploader and c.thumbnail for c in canciones):
        raise AssertionError("faltan artistas o carátulas: el motor pudo cambiar la fila")
    corta = la_mas_corta(canciones)
    try:
        bajar(corta.url, "ytmusic")
    except DownloadError as exc:
        # Desde los servidores de GitHub YouTube pide a veces demostrar que no
        # se es un robot. Eso no dice nada de la búsqueda, que es lo nuevo.
        if "robot" not in str(exc):
            raise
        print("   AVISO: YouTube pidió verificación desde este servidor:", exc)


def radio() -> None:
    """«Descubre»: la radio de YouTube Music de una canción, leída como lista."""
    semilla = motor.search(SearchQuery("marc anthony vivir mi vida", limit=1, source="ytmusic"))
    if not semilla:
        raise AssertionError("YouTube Music no devolvió la canción semilla")
    video = semilla[0].url.split("v=")[1].split("&")[0]
    lista = motor.playlist(f"https://www.youtube.com/watch?v={video}&list=RDAMVM{video}")
    print("  ", lista.title, "|", len(lista.items), "pistas")
    listar(lista.items[:10])
    if len(lista.items) < 10:
        raise AssertionError("la radio trajo muy pocas canciones")
    if not all(p.title and "v=" in p.url for p in lista.items):
        raise AssertionError("hay pistas sin título o sin video")
    if len({p.uploader for p in lista.items}) < 4:
        raise AssertionError("la radio no trae artistas distintos")
    print("   con miniatura:", sum(1 for p in lista.items if p.thumbnail), "de", len(lista.items))
    print("   con duración:", sum(1 for p in lista.items if p.duration), "de", len(lista.items))


seccion("PODCASTS (con id corto)", podcasts)
seccion("HEARTHIS", hearthis)
seccion("WIKIMEDIA COMMONS", commons)
seccion("ARCHIVE (ampliado)", archive)
seccion("CCMIXTER", ccmixter)
seccion("YOUTUBE MUSIC", ytmusic)
seccion("RADIO DE YOUTUBE MUSIC (Descubre)", radio)

if fallos:
    print("\nFALLARON:", ", ".join(fallos))
    sys.exit(1)
print("\nTodo bien.")
