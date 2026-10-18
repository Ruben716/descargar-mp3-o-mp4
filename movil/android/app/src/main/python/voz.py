"""Donde entra la voz en una cancion, para cuadrar la letra sola.

No es reconocimiento de voz: no entiende palabras. Mira cuando arranca algo en
la banda de la voz (de 250 a 3500 Hz) que suena en el centro de la mezcla, que
es donde casi siempre va el cantante, y busca cuanto hay que correr la letra
para que cada verso caiga justo donde empieza a cantar. Los versos llegan a
destiempo e irregulares, asi que el ajuste bueno destaca sobre los demas; si no
destaca, no se toca nada.

Como ritmo.py: FFmpeg decodifica y filtra, y Python solo suma cuadrados.
"""
from __future__ import annotations

import math
import subprocess
from array import array
from collections import deque
from collections.abc import Sequence
from typing import Any

import ritmo

TASA = 8000
SALTO = 80                # 10 ms por trama
CPS = TASA // SALTO
MAX_SEGUNDOS = 600
RANGO_MS = 8000           # se prueba a correr la letra hasta 8 s a cada lado
RANGO_MAXIMO_MS = 60000   # con una letra de otra version (ver letras.dart), hasta 1 min
PASO_MS = 20
ANTES = 15                # el verso puede marcarse hasta 150 ms antes o despues
DESPUES = 15              # de que cante: la ventana es simetrica para no torcer el ajuste
CONFIANZA_MINIMA = 3.5    # cuanto tiene que destacar el mejor ajuste (desviaciones)
AJUSTE_MINIMO_MS = 250    # por debajo no merece la pena tocar nada
VERSOS_MINIMOS = 6
SEPARACION_MS = 400       # otro ajuste «distinto» esta al menos a esta distancia
VENTAJA_MINIMA = 1.25     # cuanto tiene que ganarle a ese otro


def orden_ffmpeg(ffmpeg: str, ruta: str, segundos: int = MAX_SEGUNDOS) -> list[str]:
    """Centro y lados de la mezcla en la banda de la voz, en dos canales."""
    filtro = (
        f"[0:a:0]aformat=channel_layouts=stereo,aresample={TASA},asplit=2[a][b];"
        "[a]pan=mono|c0=0.5*c0+0.5*c1,highpass=f=250,lowpass=f=3500[m];"
        "[b]pan=mono|c0=0.5*c0-0.5*c1,highpass=f=250,lowpass=f=3500[s];"
        "[m][s]amerge=inputs=2[o]"
    )
    return [ffmpeg, "-hide_banner", "-nostats", "-loglevel", "error", "-i", ruta, "-t", str(segundos),
            "-filter_complex", filtro, "-map", "[o]", "-f", "s16le", "-acodec", "pcm_s16le", "-"]


def energias(crudo: bytes) -> tuple[list[float], list[float]]:
    """Energia por trama del centro y de los lados, en dB."""
    muestras = array("h")
    muestras.frombytes(crudo[: len(crudo) - len(crudo) % 4])
    centro, lados = muestras[0::2], muestras[1::2]
    tramas = len(centro) // SALTO
    db_centro: list[float] = []
    db_lados: list[float] = []
    for i in range(tramas):
        a, b = i * SALTO, (i + 1) * SALTO
        m, s = centro[a:b], lados[a:b]
        db_centro.append(10 * math.log10(ritmo._sumprod(m, m) / SALTO + 1.0))
        db_lados.append(10 * math.log10(ritmo._sumprod(s, s) / SALTO + 1.0))
    return db_centro, db_lados


def _media(serie: Sequence[float], desde: int, hasta: int) -> float:
    trozo = serie[max(0, desde):max(0, hasta)]
    return sum(trozo) / len(trozo) if trozo else 0.0


def entradas_de_voz(db_centro: list[float], db_lados: list[float]) -> list[float]:
    """Cuanto arranca algo en el centro en cada trama (0 si nada).

    Lo que suena igual de fuerte en los lados (la guitarra abierta, la reverb)
    cuenta menos. Si la mezcla es mono no hay lados que mirar y vale el centro.
    """
    if not db_centro:
        return []
    orden_c, orden_l = sorted(db_centro), sorted(db_lados)
    mono = orden_l[len(orden_l) // 2] < orden_c[len(orden_c) // 2] - 30
    voz = [c if mono else c + 0.5 * max(0.0, min(c - s, 20.0))
           for c, s in zip(db_centro, db_lados, strict=True)]
    # La subida de los 50 ms que vienen sobre los 100 ms de antes: un verso
    # que empieza es voz que aparece, no voz que sigue. La primera trama no
    # tiene antes, y el arranque del archivo no es una entrada de voz.
    return [max(0.0, _media(voz, i, i + 5) - _media(voz, i - 10, i)) if i else 0.0 for i in range(len(voz))]


def _maximos(serie: list[float], antes: int, despues: int) -> list[float]:
    """Para cada trama, el maximo de la serie de [i-antes, i+despues]."""
    salida = [0.0] * len(serie)
    cola: deque[int] = deque()
    n = len(serie)
    j = 0
    for i in range(n):
        while j < n and j <= i + despues:
            while cola and serie[cola[-1]] <= serie[j]:
                cola.pop()
            cola.append(j)
            j += 1
        while cola[0] < i - antes:
            cola.popleft()
        salida[i] = serie[cola[0]]
    return salida


def alinear(entradas: list[float], inicios_ms: Sequence[int], rango_ms: int = RANGO_MS) -> dict[str, Any]:
    """Cuanto correr la letra para que los versos caigan en entradas de voz.

    Devuelve el desfase en milisegundos (positivo retrasa la letra, como el de
    la app) y cuanto destaca sobre los demas ajustes probados, de los que van
    de -[rango_ms] a +[rango_ms].
    """
    if len(inicios_ms) < VERSOS_MINIMOS or not entradas:
        return {"desfase": 0, "confianza": 0.0, "ventaja": 0.0}
    picos = _maximos(entradas, ANTES, DESPUES)
    ultimo = len(picos) - 1

    def puntuacion(desfase: int) -> float:
        total = 0.0
        for t in inicios_ms:
            i = (t + desfase) // (1000 // CPS)
            if 0 <= i <= ultimo:
                total += picos[i]
        return total / len(inicios_ms)

    rango = max(PASO_MS, min(int(rango_ms), RANGO_MAXIMO_MS))
    pruebas = [(d, puntuacion(d)) for d in range(-rango, rango + 1, PASO_MS)]
    valores = [p for _, p in pruebas]
    media = sum(valores) / len(valores)
    desviacion = math.sqrt(sum((v - media) ** 2 for v in valores) / len(valores))
    cima = max(range(len(pruebas)), key=lambda k: valores[k])
    nota = valores[cima]
    # Con la ventana, el mejor ajuste no es un punto sino una meseta: los
    # versos caen en su entrada de voz en todo un tramo de ajustes. Se toma el
    # centro de la meseta; quedarse con un borde torcia el ajuste 200 ms.
    izquierda = derecha = cima
    while izquierda > 0 and valores[izquierda - 1] >= nota * 0.97:
        izquierda -= 1
    while derecha < len(valores) - 1 and valores[derecha + 1] >= nota * 0.97:
        derecha += 1
    mejor = pruebas[(izquierda + derecha) // 2][0]
    confianza = (nota - media) / desviacion if desviacion > 0 else 0.0
    # Con golpes regulares muchos ajustes puntuan casi igual (uno por pulso):
    # el bueno tiene que ganarle con claridad al mejor de los que estan lejos.
    lejos = [v for (d, v) in pruebas if abs(d - mejor) >= SEPARACION_MS]
    ventaja = nota / max(lejos) if lejos and max(lejos) > 0 else 0.0
    return {"desfase": mejor, "confianza": round(confianza, 2), "ventaja": round(ventaja, 2)}


def sincronizar(
    ruta: str, inicios_ms: Sequence[int], ffmpeg: str, limite: float = 120, rango_ms: int = RANGO_MS,
) -> dict[str, Any]:
    """Analiza el archivo y dice cuanto correr la letra; 0 si no esta claro.

    «seguro» dice si el ajuste destaca, aunque sea quedarse como esta: con una
    letra de otra version, eso confirma que sus tiempos valen. «aplicar» pide
    ademas que merezca la pena moverla.
    """
    proceso = subprocess.run(orden_ffmpeg(ffmpeg, ruta), capture_output=True, timeout=limite, check=False)
    if proceso.returncode != 0:
        raise RuntimeError(proceso.stderr.decode("utf-8", "replace").strip()[-300:] or "FFmpeg fallo")
    centro, lados = energias(proceso.stdout)
    resultado = alinear(entradas_de_voz(centro, lados), inicios_ms, rango_ms)
    seguro = resultado["confianza"] >= CONFIANZA_MINIMA and resultado.get("ventaja", 0) >= VENTAJA_MINIMA
    aplicar = seguro and abs(resultado["desfase"]) >= AJUSTE_MINIMO_MS
    return {**resultado, "seguro": seguro, "aplicar": aplicar}
