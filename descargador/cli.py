"""Interfaz de consola y composición de dependencias."""
import argparse
import sys
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path

from .application import DownloadVideo, InspectVideo
from .domain import (
    AUDIO_FORMATS,
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    VideoInfo,
    parse_section,
)
from .infrastructure import (
    YtDlpDownloader,
    abrir_carpeta,
    actualizar_motor,
    incrusta_caratula,
    leer_portapapeles,
)


# -- formato de salida -----------------------------------------------------
def formato_tamano(octetos: int | None) -> str:
    if not octetos:
        return "--"
    valor = float(octetos)
    for unidad in ("B", "KB", "MB", "GB"):
        if valor < 1024 or unidad == "GB":
            return f"{valor:.1f} {unidad}"
        valor /= 1024
    return f"{valor:.1f} GB"


def formato_tiempo(segundos: float | None) -> str:
    if segundos is None:
        return "--:--"
    total = int(segundos)
    horas, resto = divmod(total, 3600)
    minutos, segs = divmod(resto, 60)
    return f"{horas}:{minutos:02d}:{segs:02d}" if horas else f"{minutos:02d}:{segs:02d}"


def mostrar_progreso(avance: DownloadProgress) -> None:
    """Imprime el avance en una sola línea que se reescribe."""
    if avance.status == "downloading":
        porcentaje = f"{avance.percent:5.1f}%" if avance.percent is not None else "   ?  "
        velocidad = f"{formato_tamano(int(avance.speed))}/s" if avance.speed else "--"
        linea = (f"  {porcentaje}  de {formato_tamano(avance.total)}"
                 f"  a {velocidad}  falta {formato_tiempo(avance.eta)}")
        print(f"\r{linea:<70}", end="", flush=True)
    elif avance.status == "finished":
        print(f"\r  {'Descargado. Procesando con FFmpeg...':<70}")
    elif avance.status == "error":
        print()


def mostrar_info(info: VideoInfo) -> None:
    print(f"\n  Título:    {info.title}")
    if info.uploader:
        print(f"  Autor:     {info.uploader}")
    if info.duration:
        print(f"  Duración:  {formato_tiempo(info.duration)}")
    if not info.formats:
        return
    print(f"\n  {'ID':<10}{'EXT':<6}{'RESOLUCIÓN':<14}{'TAMAÑO':<12}NOTA")
    print(f"  {'-' * 62}")
    for formato in info.formats:
        print(f"  {formato.format_id:<10}{formato.ext:<6}{formato.resolution:<14}"
              f"{formato_tamano(formato.filesize):<12}{formato.note}")
    print(f"\n  {len(info.formats)} formatos disponibles. Usa --calidad para limitar el alto.")


# -- entrada del usuario ---------------------------------------------------
def choose_format() -> str | None:
    print("\n¿Qué quieres descargar?\n")
    print("  1. Video con audio")
    print("  2. Música / audio en MP3")
    print("  3. Ver información del video (sin descargar)")
    print("  0. Salir\n")
    opciones = {"1": "video", "2": "audio", "3": "info"}
    while True:
        eleccion = input("Selecciona una opción (1, 2, 3 o 0): ").strip()
        if eleccion == "0":
            return None
        if eleccion in opciones:
            return opciones[eleccion]
        print("Opción inválida. Escribe 1, 2, 3 o 0.")


#: Una acción del menú recibe los ajustes actuales y devuelve los nuevos.
Ajuste = Callable[[DownloadOptions, Path], tuple[DownloadOptions, Path]]


def describir_ajustes(opciones: DownloadOptions, destino: Path, audio: bool) -> list[str]:
    """Resume en texto cómo se va a descargar."""
    lineas = []
    if audio:
        lineas.append(f"  Formato:      {opciones.audio_format} a {opciones.audio_bitrate} kb/s")
    else:
        calidad = f"hasta {opciones.quality}p" if opciones.quality else "la mejor disponible"
        subtitulos = ",".join(opciones.subtitles) if opciones.subtitles else "no"
        lineas.append(f"  Calidad:      {calidad}")
        lineas.append(f"  Subtítulos:   {subtitulos}")
        lineas.append(f"  Patrocinios:  {'se eliminan' if opciones.skip_sponsors else 'se conservan'}")
    if opciones.section:
        inicio, fin = opciones.section
        remate = formato_tiempo(fin) if fin != float("inf") else "el final"
        lineas.append(f"  Fragmento:    de {formato_tiempo(inicio)} a {remate}")
    else:
        lineas.append("  Fragmento:    completo")
    lineas.append(f"  Carpeta:      {destino}")
    lineas.append(f"  Repetidos:    {'se omiten' if opciones.use_archive else 'se vuelven a descargar'}")
    lineas.append(f"  Carátula:     {'se incrusta' if incrusta_caratula(audio) else 'no (falta ffprobe)'}")
    return lineas


def _cambiar_calidad(opciones: DownloadOptions, destino: Path):
    texto = input("  Alto máximo en píxeles (1080, 720, 480) o Enter para la mejor: ").strip()
    if not texto:
        return replace(opciones, quality=None), destino
    if texto.isdigit() and int(texto) > 0:
        return replace(opciones, quality=int(texto)), destino
    print("  Valor inválido; se mantiene el ajuste actual.")
    return opciones, destino


def _cambiar_subtitulos(opciones: DownloadOptions, destino: Path):
    texto = input("  Idiomas separados por comas (es,en) o Enter para no descargarlos: ").strip()
    idiomas = tuple(i.strip() for i in texto.split(",") if i.strip())
    return replace(opciones, subtitles=idiomas), destino


def _cambiar_fragmento(opciones: DownloadOptions, destino: Path):
    texto = input("  Fragmento INICIO-FIN (por ejemplo 00:30-02:15) o Enter para el video entero: ").strip()
    if not texto:
        return replace(opciones, section=None), destino
    try:
        return replace(opciones, section=parse_section(texto)), destino
    except DownloadError as exc:
        print(f"  {exc}")
        return opciones, destino


def _cambiar_formato_audio(opciones: DownloadOptions, destino: Path):
    texto = input(f"  Códec ({'/'.join(AUDIO_FORMATS)}) o Enter para mantener: ").strip().lower()
    if not texto:
        return opciones, destino
    if texto in AUDIO_FORMATS:
        return replace(opciones, audio_format=texto), destino
    print("  Códec no admitido; se mantiene el ajuste actual.")
    return opciones, destino


def _cambiar_bitrate(opciones: DownloadOptions, destino: Path):
    texto = input("  Calidad del audio en kb/s (128, 192, 320) o Enter para mantener: ").strip()
    if not texto:
        return opciones, destino
    if texto.isdigit():
        return replace(opciones, audio_bitrate=texto), destino
    print("  Valor inválido; se mantiene el ajuste actual.")
    return opciones, destino


def _cambiar_carpeta(opciones: DownloadOptions, destino: Path):
    texto = input(f"  Carpeta de destino o Enter para {destino}: ").strip().strip('"')
    return opciones, Path(texto) if texto else destino


def _alternar_patrocinios(opciones: DownloadOptions, destino: Path):
    return replace(opciones, skip_sponsors=not opciones.skip_sponsors), destino


def _alternar_registro(opciones: DownloadOptions, destino: Path):
    return replace(opciones, use_archive=not opciones.use_archive), destino


def acciones_ajustes(audio: bool) -> list[tuple[str, Ajuste]]:
    """Menú de ajustes disponible según se descargue audio o video."""
    comunes: list[tuple[str, Ajuste]]
    if audio:
        comunes = [("Formato", _cambiar_formato_audio), ("Calidad", _cambiar_bitrate)]
    else:
        comunes = [("Calidad", _cambiar_calidad), ("Subtítulos", _cambiar_subtitulos),
                   ("Patrocinios", _alternar_patrocinios)]
    return [*comunes, ("Fragmento", _cambiar_fragmento), ("Carpeta", _cambiar_carpeta),
            ("Repetidos", _alternar_registro)]


def menu_ajustes(opciones: DownloadOptions, destino: Path,
                 audio: bool) -> tuple[DownloadOptions, Path] | None:
    """Deja revisar y cambiar los ajustes antes de pedir el enlace."""
    acciones = acciones_ajustes(audio)
    while True:
        print("\nAsí se va a descargar:\n")
        for linea in describir_ajustes(opciones, destino, audio):
            print(linea)
        print("\n  " + "   ".join(f"{n}. {nombre}" for n, (nombre, _) in enumerate(acciones, start=1)))
        eleccion = input("\nEnter para continuar, un número para cambiarlo, 0 para salir: ").strip()
        if not eleccion:
            return opciones, destino
        if eleccion == "0":
            return None
        if eleccion.isdigit() and 1 <= int(eleccion) <= len(acciones):
            opciones, destino = acciones[int(eleccion) - 1][1](opciones, destino)
        else:
            print("Opción inválida.")


def leer_lista(ruta: Path) -> list[str]:
    """Lee un archivo con una URL por línea; ignora vacías y comentarios."""
    try:
        contenido = ruta.read_text(encoding="utf-8")
    except OSError as exc:
        raise DownloadError(f"No se pudo leer la lista de URLs: {exc}") from exc
    lineas = [linea.strip() for linea in contenido.splitlines()]
    urls = [linea for linea in lineas if linea and not linea.startswith("#")]
    if not urls:
        raise DownloadError(f"La lista {ruta} no contiene ninguna URL.")
    return urls


def construir_opciones(args) -> DownloadOptions:
    subtitulos = ()
    if args.subs:
        subtitulos = tuple(i.strip() for i in args.subs.split(",") if i.strip())
    return DownloadOptions(
        audio_only=args.audio,
        quality=args.calidad,
        audio_format=args.formato_audio,
        audio_bitrate=str(args.bitrate),
        subtitles=subtitulos,
        section=parse_section(args.seccion) if args.seccion else None,
        skip_sponsors=args.sin_patrocinios,
        use_archive=args.registro,
    )


def crear_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Descarga video o solo audio pegando su URL.")
    parser.add_argument("url", nargs="?", help="URL del video (entre comillas)")
    parser.add_argument("-a", "--audio", action="store_true", help="Descargar solo audio")
    parser.add_argument("-o", "--destino", type=Path, default=Path("descargas"),
                        help="Carpeta de salida (predeterminado: descargas)")
    parser.add_argument("-c", "--calidad", type=int, metavar="ALTO",
                        help="Alto máximo en píxeles, por ejemplo 1080")
    parser.add_argument("--formato-audio", choices=AUDIO_FORMATS, default="mp3",
                        help="Códec de audio (predeterminado: mp3)")
    parser.add_argument("--bitrate", type=int, default=192,
                        help="Calidad del audio en kb/s (predeterminado: 192)")
    parser.add_argument("--subs", nargs="?", const="es,en", metavar="IDIOMAS",
                        help="Descargar e incrustar subtítulos (predeterminado: es,en)")
    parser.add_argument("--seccion", metavar="INICIO-FIN",
                        help="Descargar solo un fragmento, por ejemplo 00:30-02:15")
    parser.add_argument("--sin-patrocinios", action="store_true",
                        help="Eliminar segmentos patrocinados con SponsorBlock")
    parser.add_argument("--registro", action="store_true",
                        help="Anotar lo descargado y saltar lo repetido")
    parser.add_argument("--desde", type=Path, metavar="ARCHIVO",
                        help="Descargar todas las URLs de un archivo, una por línea")
    parser.add_argument("--pegar", action="store_true", help="Tomar la URL del portapapeles")
    parser.add_argument("-i", "--info", action="store_true",
                        help="Mostrar los datos del video sin descargarlo")
    parser.add_argument("--abrir", action="store_true", help="Abrir la carpeta al terminar")
    parser.add_argument("--sin-progreso", action="store_true",
                        help="Usar la salida original de yt-dlp en lugar del progreso propio")
    parser.add_argument("--actualizar", action="store_true", help="Actualizar yt-dlp y salir")
    return parser


def reunir_urls(args) -> list[str]:
    if args.desde:
        return leer_lista(args.desde)
    if args.pegar:
        return [leer_portapapeles()]
    if args.url is not None:
        return [args.url]
    return [input("Ingresa el link: ").strip()]


def main(argv=None) -> int:
    args = crear_parser().parse_args(argv)
    try:
        if args.actualizar:
            return actualizar_motor()

        sin_fuente = args.url is None and args.desde is None and not args.pegar
        interactivo = sin_fuente and not args.audio and not args.info
        if interactivo:
            eleccion = choose_format()
            if eleccion is None:
                print("Hasta luego.")
                return 0
            args.audio = eleccion == "audio"
            args.info = eleccion == "info"

        opciones = construir_opciones(args)
        destino = args.destino
        if interactivo and not args.info:
            ajustado = menu_ajustes(opciones, destino, args.audio)
            if ajustado is None:
                print("Hasta luego.")
                return 0
            opciones, destino = ajustado

        urls = reunir_urls(args)
        adaptador = YtDlpDownloader(None if args.sin_progreso or args.info else mostrar_progreso)
        descargar, consultar = DownloadVideo(adaptador), InspectVideo(adaptador)
        tipo = "Audio" if args.audio else "Video"
        fallos = omitidas = 0

        for indice, url in enumerate(urls, start=1):
            if len(urls) > 1:
                print(f"\n[{indice}/{len(urls)}] {url}")
            try:
                if args.info:
                    mostrar_info(consultar.execute(url, destino, opciones))
                else:
                    resultado = descargar.execute(url, destino, opciones)
                    if not resultado.files:
                        omitidas += 1
                        print("\nOmitido: ya figura en el registro de descargas.")
                    for ruta in resultado.files:
                        print(f"\nListo. {tipo} guardado en: {ruta}")
            except DownloadError as exc:
                fallos += 1
                print(f"\nError: {exc}", file=sys.stderr)

        if len(urls) > 1:
            resumen = f"\nResumen: {len(urls) - fallos - omitidas} correctas, {fallos} con error"
            print(f"{resumen}, {omitidas} omitidas." if omitidas else f"{resumen}.")
        if args.abrir and not args.info and fallos < len(urls):
            abrir_carpeta((destino / "audio" if args.audio else destino).expanduser())
        return 1 if fallos else 0
    except DownloadError as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelado. Puedes repetir la URL para reanudar la descarga.", file=sys.stderr)
        return 130
