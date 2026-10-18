"""El video de un trozo de la cancion con su letra, para estados e historias.

Flutter pinta un fotograma por verso (PNG de 720x1280, ver video_letra.dart) y
aqui FFmpeg los une con el audio de ese trozo: los fotogramas, cada uno el
tiempo que dura su verso, con el demuxer concat; el audio recortado y con un
fundido a cada lado; y encima, abajo, la onda del audio moviendose a la par.

No se sabe seguro que trae el FFmpeg del telefono (es la compilacion de Termux
de youtubedl-android, y antigua), asi que el codificador de video va en cadena:
libx264, el de MediaCodec del telefono y, si no hay otro, mpeg4, que viene
siempre. Nunca lanza: devuelve un diccionario con «ok».
"""
from __future__ import annotations

import contextlib
import subprocess
import time
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any, NamedTuple

ANCHO = 720
ALTO = 1280
FPS = 30
FUNDIDO_MS = 500

# La onda va en la franja de abajo que el fotograma deja libre (en Dart,
# FotogramaVideo.franjaOnda: 120 puntos, 240 px). Blanca y semitransparente,
# para que se lea sin tapar el fondo.
ONDA_ANCHO = 640
ONDA_ALTO = 160
ONDA_MARGEN = 56          # px entre la onda y el borde de abajo
ONDA_COLOR = "white@0.55"
# Sin el paso bajo, a 30 fotogramas por segundo la onda es un borron de
# dientes; con el se ve la forma de la musica. Algo mas baja que el audio,
# para que lo mas fuerte no llegue al borde y salga con la punta plana.
ONDA_PASO_BAJO_HZ = 1000
ONDA_VOLUMEN = 0.8

#: Lo que tarda el vinilo en dar una vuelta: 33 1/3 revoluciones por minuto.
VUELTA_VINILO_S = 1.8
#: Cuanto se acerca la portada por segundo: en 15 s, un 12 %; apenas se nota
#: que se mueve, pero el video deja de parecer una foto.
ZOOM_POR_S = 0.008

LIMITE_S = 120


class Movil(NamedTuple):
    """Lo que FFmpeg mueve encima de los fotogramas, en su sitio (px).

    El fotograma ya lo trae pintado quieto en ese mismo sitio: si el FFmpeg del
    telefono no sabe moverlo, el video sale igual, solo que sin movimiento.
    """

    png: str
    tipo: str  # «girar» (el vinilo) o «zoom» (la portada)
    x: int
    y: int
    ancho: int
    alto: int


class Diseno(NamedTuple):
    """El lienzo del video y donde van la onda y lo que se mueve, en px."""

    ancho: int = ANCHO
    alto: int = ALTO
    onda: tuple[int, int, int, int] | None = (
        (ANCHO - ONDA_ANCHO) // 2, ALTO - ONDA_ALTO - ONDA_MARGEN, ONDA_ANCHO, ONDA_ALTO,
    )
    movil: Movil | None = None


def _par(valor: Any) -> int:
    """yuv420p pide medidas pares."""
    return max(2, int(valor) // 2 * 2)


def diseno_de(datos: Mapping[str, Any] | None) -> Diseno:
    """El [Diseno] que manda Flutter: {"ancho", "alto", "onda": [x, y, w, h],
    "movil": {"png", "tipo", "x", "y", "ancho", "alto"}}. Sin datos, el de
    siempre: 720x1280 con la onda abajo."""
    if not datos:
        return Diseno()
    onda = datos.get("onda")
    movil = datos.get("movil")
    return Diseno(
        ancho=_par(datos.get("ancho", ANCHO)),
        alto=_par(datos.get("alto", ALTO)),
        onda=tuple(_par(v) for v in onda) if onda else None,  # type: ignore[arg-type]
        movil=Movil(
            png=str(movil["png"]),
            tipo="girar" if movil.get("tipo") == "girar" else "zoom",
            x=int(movil["x"]),
            y=int(movil["y"]),
            ancho=_par(movil["ancho"]),
            alto=_par(movil["alto"]),
        ) if movil else None,
    )

#: Del mejor al que siempre esta. El nombre y como se le pide la calidad.
CODIFICADORES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("libx264", ("-c:v", "libx264", "-preset", "veryfast", "-crf", "23")),
    # El del telefono no entiende de calidad constante: se le da un caudal.
    ("h264_mediacodec", ("-c:v", "h264_mediacodec", "-b:v", "4M")),
    ("mpeg4", ("-c:v", "mpeg4", "-q:v", "3")),
)

#: Lo que dice FFmpeg cuando no tiene el codificador o no lo puede abrir.
#: Cualquier otro fallo (el audio no se lee, falta un PNG) no se arregla con
#: otro codificador, y no se reintenta.
FALLOS_DE_CODIFICADOR = (
    "Unknown encoder",
    "Encoder not found",
    "Error selecting an encoder",
    "Error while opening encoder",
    "Error initializing output stream",
    "Could not open encoder",
)

#: Lo que dice FFmpeg cuando no entiende algun filtro u opcion del grafo. El
#: de Android es otra compilacion y puede no traer la onda tal cual: entonces
#: se repite sin ella, que un video sin onda es mejor que ninguno.
FALLOS_DE_FILTRO = (
    "No such filter",
    "Option not found",
    "Error applying option",
    "Error initializing filter",
    "Error initializing complex filters",
    "Error reinitializing filters",
)


def ajustar_duraciones(fotogramas: Sequence[tuple[str, int]], duracion_ms: int) -> list[tuple[str, int]]:
    """Los fotogramas que caben en [duracion_ms], el ultimo hasta el final.

    Flutter ya los manda sumando lo justo, pero si no fuera asi el video se
    quedaria corto o se cortaria a medio verso: los que no caben se quitan y el
    ultimo se estira o se recorta hasta completar.
    """
    salida: list[tuple[str, int]] = []
    llevado = 0
    for ruta, ms in fotogramas:
        if ms <= 0:
            continue
        if llevado >= duracion_ms:
            break
        salida.append((ruta, min(ms, duracion_ms - llevado)))
        llevado += salida[-1][1]
    if salida and llevado < duracion_ms:
        ruta, ms = salida[-1]
        salida[-1] = (ruta, ms + duracion_ms - llevado)
    return salida


def _entre_comillas(ruta: str) -> str:
    """La ruta como la quiere el concat: entre comillas simples, y cada
    comilla de dentro cerrada, escapada y vuelta a abrir."""
    return "'" + ruta.replace("'", "'\\''") + "'"


def texto_concat(fotogramas: Sequence[tuple[str, int]]) -> str:
    """La lista del demuxer concat: cada PNG con lo que dura.

    El ultimo va repetido al final, sin duracion: es como el concat sabe hasta
    cuando dura el anterior. Sin eso, el ultimo verso salia solo un instante.
    """
    lineas = ["ffconcat version 1.0"]
    for ruta, ms in fotogramas:
        lineas.append(f"file {_entre_comillas(ruta)}")
        lineas.append(f"duration {ms / 1000:.3f}")
    if fotogramas:
        lineas.append(f"file {_entre_comillas(fotogramas[-1][0])}")
    return "\n".join(lineas) + "\n"


def _mover(movil: Movil) -> str:
    """El trozo del grafo que mueve [movil] (entrada 2) y lo deja en [m].

    El vinilo gira en el sentido de las agujas, con las esquinas
    transparentes. La portada llega al doble de su tamano y se va acercando
    desde el centro: con el doble de pixeles, el redondeo de zoompan no tiembla.
    """
    if movil.tipo == "girar":
        return f"[2:v]format=rgba,rotate=a=2*PI*t/{VUELTA_VINILO_S}:c=black@0[m]"
    return (
        f"[2:v]zoompan=z=1+{ZOOM_POR_S}*on/{FPS}:x=iw/2-(iw/zoom/2):y=ih/2-(ih/zoom/2)"
        f":d=1:s={movil.ancho}x{movil.alto}:fps={FPS},format=rgba[m]"
    )


def filtro(duracion_ms: int, extras: bool = True, diseno: Diseno | None = None) -> str:
    """El grafo de FFmpeg: fundidos, lo que se mueve y la onda encima de los
    fotogramas.

    El audio se rellena con silencio (apad) por si la cancion acaba antes de
    lo pedido: el corte lo da «-t», y asi video y audio duran siempre igual.
    Sin [extras], solo los fotogramas: ni onda ni movimiento.
    """
    d = diseno or Diseno()
    segundos = duracion_ms / 1000
    fundido = min(FUNDIDO_MS / 1000, segundos / 2)
    audio = (
        f"[1:a]apad,afade=t=in:st=0:d={fundido:.3f},"
        f"afade=t=out:st={segundos - fundido:.3f}:d={fundido:.3f}"
    )
    fondo = f"[0:v]scale={d.ancho}:{d.alto},setsar=1,fps={FPS}"
    if not extras or (d.onda is None and d.movil is None):
        return f"{audio}[a];{fondo},format=yuv420p[v]"
    partes = [f"{fondo}[f0]"]
    capa = "f0"
    if d.movil is not None:
        partes.append(_mover(d.movil))
        partes.append(f"[{capa}][m]overlay=x={d.movil.x}:y={d.movil.y}:format=auto[f1]")
        capa = "f1"
    if d.onda is None:
        return f"{audio}[a];" + ";".join(partes) + f";[{capa}]format=yuv420p[v]"
    x, y, ancho, alto = d.onda
    partes.append(
        f"[w]aformat=channel_layouts=mono,lowpass=f={ONDA_PASO_BAJO_HZ},volume={ONDA_VOLUMEN},"
        f"showwaves=s={ancho}x{alto}:mode=cline:colors={ONDA_COLOR}"
        f":rate={FPS}:scale=sqrt:draw=full[onda]"
    )
    partes.append(f"[{capa}][onda]overlay=x={x}:y={y}:format=auto,format=yuv420p[v]")
    return f"{audio},asplit=2[a][w];" + ";".join(partes)


def orden(
    ffmpeg: str,
    lista: str,
    audio: str,
    inicio_ms: int,
    duracion_ms: int,
    salida: str,
    codificador: Sequence[str],
    extras: bool = True,
    diseno: Diseno | None = None,
) -> list[str]:
    """La orden entera de FFmpeg para un codificador de [CODIFICADORES].

    El recorte va antes de «-i» del audio: asi FFmpeg salta directo al trozo
    sin decodificar lo de antes, que en una cancion larga es casi todo. Lo que
    se mueve, si hay, es la entrada 2: su PNG repetido lo que dura el video.
    """
    d = diseno or Diseno()
    segundos = f"{duracion_ms / 1000:.3f}"
    movil = (
        ["-loop", "1", "-framerate", str(FPS), "-t", segundos, "-i", d.movil.png]
        if extras and d.movil is not None else []
    )
    return [
        ffmpeg, "-hide_banner", "-nostats", "-loglevel", "error", "-y",
        "-f", "concat", "-safe", "0", "-i", lista,
        "-ss", f"{max(0, inicio_ms) / 1000:.3f}", "-t", segundos, "-i", audio,
        *movil,
        "-filter_complex", filtro(duracion_ms, extras, d),
        "-map", "[v]", "-map", "[a]",
        "-t", segundos, "-r", str(FPS),
        *codificador,
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2",
        "-movflags", "+faststart",
        salida,
    ]


def falla_un_filtro(mensaje: str) -> bool:
    """Si FFmpeg no entendio el grafo de filtros."""
    return any(marca in mensaje for marca in FALLOS_DE_FILTRO)


def falla_el_codificador(mensaje: str) -> bool:
    """Si FFmpeg se quejo del codificador, y no de otra cosa."""
    return any(marca in mensaje for marca in FALLOS_DE_CODIFICADOR)


def _ultimas_lineas(texto: str, cuantas: int = 3) -> str:
    lineas = [linea.strip() for linea in texto.splitlines() if linea.strip()]
    return " | ".join(lineas[-cuantas:])


def crear(
    ffmpeg: str,
    audio: str,
    inicio_ms: int,
    duracion_ms: int,
    fotogramas: Sequence[tuple[str, int]],
    salida: str,
    limite_s: float = LIMITE_S,
    diseno: Diseno | None = None,
) -> dict[str, Any]:
    """Hace el MP4 en [salida]. Nunca lanza.

    [fotogramas] son pares (ruta del PNG, milisegundos que se ve). Devuelve
    {"ok": True, "ruta", "codificador", "onda"} o {"ok": False, "error"};
    «onda» dice si salieron la onda y el movimiento.
    """
    d = diseno or Diseno()
    lista = Path(f"{salida}.txt")
    try:
        if duracion_ms <= 0:
            return {"ok": False, "error": "El fragmento no dura nada."}
        cuadro = ajustar_duraciones(fotogramas, duracion_ms)
        if not cuadro:
            return {"ok": False, "error": "No hay fotogramas."}
        faltan = [ruta for ruta, _ in cuadro if not Path(ruta).is_file()]
        if faltan:
            return {"ok": False, "error": f"Falta el fotograma {faltan[0]}."}
        if not Path(audio).is_file():
            return {"ok": False, "error": "No se encuentra el audio."}
        if d.movil is not None and not Path(d.movil.png).is_file():
            # El fotograma ya lo trae quieto: sin el PNG, simplemente no se mueve.
            d = Diseno(ancho=d.ancho, alto=d.alto, onda=d.onda)
        lista.write_text(texto_concat(cuadro), encoding="utf-8")

        hasta = time.monotonic() + limite_s
        error = "No hay ningun codificador de video."
        extras = True
        i = 0
        while i < len(CODIFICADORES):
            nombre, opciones = CODIFICADORES[i]
            restante = hasta - time.monotonic()
            if restante <= 0:
                return {"ok": False, "error": "El video tardo demasiado."}
            hecho = subprocess.run(
                orden(ffmpeg, str(lista), audio, inicio_ms, duracion_ms, salida, opciones, extras, d),
                capture_output=True, text=True, timeout=restante, check=False,
            )
            hay_video = Path(salida).is_file() and Path(salida).stat().st_size > 0
            if hecho.returncode == 0 and hay_video:
                return {"ok": True, "ruta": salida, "codificador": nombre, "onda": extras}
            mensaje = hecho.stderr or ""
            error = _ultimas_lineas(mensaje) or f"FFmpeg acabo con el codigo {hecho.returncode}."
            # Lo que quedase a medias no puede pasar por un video bueno.
            _borrar(Path(salida))
            if falla_el_codificador(mensaje):
                i += 1
            elif extras and falla_un_filtro(mensaje):
                extras = False
            else:
                break
        return {"ok": False, "error": error}
    except subprocess.TimeoutExpired:
        _borrar(Path(salida))
        return {"ok": False, "error": "El video tardo demasiado."}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
    finally:
        _borrar(lista)


def _borrar(ruta: Path) -> None:
    """Borra si esta; si no se puede, se queda en la cache, que Android vacia."""
    with contextlib.suppress(OSError):
        ruta.unlink(missing_ok=True)
