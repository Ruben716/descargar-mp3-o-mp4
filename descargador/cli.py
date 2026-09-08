"""Interfaz y composición de dependencias."""
import argparse
from pathlib import Path
import sys

from .application import DownloadVideo
from .domain import DownloadError
from .infrastructure import YtDlpDownloader


def choose_format() -> bool | None:
    print("\n¿Qué quieres descargar?\n")
    print("  1. Video con audio")
    print("  2. Música / audio en MP3")
    print("  0. Salir\n")
    while True:
        choice = input("Selecciona una opción (1, 2 o 0): ").strip()
        if choice == "0":
            return None
        if choice in {"1", "2"}:
            return choice == "2"
        print("Opción inválida. Escribe 1, 2 o 0.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Descarga video o solo audio pegando su URL.")
    parser.add_argument("url", nargs="?", help="URL del video (entre comillas)")
    parser.add_argument("-a", "--audio", action="store_true", help="Descargar solo audio en MP3 (192 kb/s)")
    parser.add_argument("-o", "--destino", type=Path, default=Path("descargas"), help="Carpeta de salida (predeterminado: descargas)")
    args = parser.parse_args(argv)
    try:
        audio_only = args.audio
        if args.url is None and not args.audio:
            audio_only = choose_format()
            if audio_only is None:
                print("Hasta luego.")
                return 0
        url = args.url if args.url is not None else input("Ingresa el link: ").strip()
        result = DownloadVideo(YtDlpDownloader()).execute(url, args.destino, audio_only=audio_only)
        kind = "Audio" if audio_only else "Video"
        for path in result.files:
            print(f"\nListo. {kind} guardado en: {path}")
        return 0
    except DownloadError as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelado. Puedes repetir la URL para reanudar la descarga.", file=sys.stderr)
        return 130
