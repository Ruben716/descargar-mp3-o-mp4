"""Genera el icono de Tumbao a partir de la imagen original.

Se deja como script y no como imagenes sueltas para que el icono sea
reproducible: si cambia la imagen, se vuelve a ejecutar y ya.

    python movil/herramientas/generar_icono.py
    cd movil && dart run flutter_launcher_icons

La imagen de partida (`icono_origen.jpg`) son unos audifonos con un atardecer
dentro, sobre negro puro. Va tal cual, a color: encaja con el tema Onix (negro
y blanco, el color lo pone la portada). El encuadre no se fija a mano: se busca
donde hay luz y se centra la figura.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

NEGRO = (0, 0, 0)
"""El fondo de la imagen original. El del icono tiene que ser el mismo, o se
notaria el borde del recorte."""

LADO = 1024

AIRE_CLASICO = 1.2
"""Cuanto mas grande que la figura es el icono clasico, para que no vaya pegada al borde."""

ZONA_SEGURA = 0.62
"""Lo que puede ocupar la figura (su circulo) en el icono adaptativo.

Android dibuja la capa a 108 dp y la recorta con la mascara del fabricante
(circulo, gota, cuadrado...); lo que cae dentro de 66 dp se ve siempre. Se
mide el circulo que envuelve la figura, no su caja: las orejas de los
audifonos llegan a las esquinas de la caja y un circulo se las comeria."""

BASE = Path(__file__).resolve().parent
ORIGEN = BASE / "icono_origen.jpg"
SALIDA = BASE.parent / "assets"


def figura() -> tuple[Image.Image, float, float, float, float]:
    """La imagen, el centro de la figura, su alto y el radio que la envuelve."""
    imagen = Image.open(ORIGEN).convert("RGB")
    gris = imagen.convert("L")
    # Umbral bajo: basta con distinguir la figura del negro del fondo.
    luz = gris.point(lambda v: 255 if v > 20 else 0)
    caja = luz.getbbox()
    if caja is None:
        raise RuntimeError(f"{ORIGEN.name} esta en negro, no hay figura que recortar")
    izquierda, arriba, derecha, abajo = caja
    cx, cy = (izquierda + derecha) / 2, (arriba + abajo) / 2
    puntos = luz.load()
    if puntos is None:
        raise RuntimeError(f"no se pudo leer {ORIGEN.name}")
    radio = max(
        math.hypot(x - cx, y - cy)
        for y in range(arriba, abajo, 2)
        for x in range(izquierda, derecha, 2)
        if puntos[x, y]
    )
    return imagen, cx, cy, float(abajo - arriba), radio


def recorte(imagen: Image.Image, cx: float, cy: float, medida: float) -> Image.Image:
    """Un cuadrado de [medida] centrado en la figura, a [LADO] px.

    Si se sale de la imagen, lo de fuera es negro, igual que el fondo.
    """
    lado = round(medida)
    lienzo = Image.new("RGB", (lado, lado), NEGRO)
    lienzo.paste(imagen, (round(lado / 2 - cx), round(lado / 2 - cy)))
    return lienzo.resize((LADO, LADO), Image.Resampling.LANCZOS)


def esquinas(imagen: Image.Image, radio: int) -> Image.Image:
    """Recorta con esquinas redondeadas."""
    mascara = Image.new("L", imagen.size, 0)
    ancho, alto = imagen.size
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, ancho - 1, alto - 1], radius=radio, fill=255)
    recortada = imagen.convert("RGBA")
    recortada.putalpha(mascara)
    return recortada


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    imagen, cx, cy, alto, radio = figura()

    # Icono clasico: la figura con algo de aire y las esquinas redondeadas.
    clasico = recorte(imagen, cx, cy, alto * AIRE_CLASICO)
    esquinas(clasico, radio=round(LADO * 0.22)).save(SALIDA / "icono.png")

    # Adaptativo: el fondo, negro liso a sangre; delante, la figura entera
    # dentro de la zona segura. Como su fondo tambien es negro, no se nota
    # donde acaba una capa y empieza la otra aunque el sistema las mueva.
    Image.new("RGB", (LADO, LADO), NEGRO).save(SALIDA / "icono_fondo.png")
    recorte(imagen, cx, cy, 2 * radio / ZONA_SEGURA).save(SALIDA / "icono_primer_plano.png")

    print(f"iconos generados en {SALIDA}")


if __name__ == "__main__":
    main()
