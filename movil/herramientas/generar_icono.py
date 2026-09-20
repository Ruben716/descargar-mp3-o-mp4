"""Genera el icono de Tumbao a partir del dibujo original.

Se deja como script y no como imagenes sueltas para que el icono sea
reproducible: si cambia el color de la app, se vuelve a ejecutar y ya.

    python movil/herramientas/generar_icono.py

El dibujo de partida (`icono_origen.jpeg`) es trazo blanco sobre fondo negro.
De ahi se saca la silueta: lo claro es la figura y lo oscuro se descarta. Luego
se repinta en tinta sobre el degradado de la marca, igual que los botones
principales, porque asi se lee mucho mejor en la parrilla de aplicaciones que
un trazo fino y blanco perdido entre iconos oscuros.
"""
from pathlib import Path

from PIL import Image, ImageDraw

#: Los mismos colores que tema.dart, para que el icono no vaya por libre.
ACENTO = (182, 156, 255)
ACENTO_CALIDO = (255, 143, 177)
TINTA = (14, 12, 24)

LADO = 1024
AIRE = 1.34
"""Cuanto se abre el recorte respecto al dibujo, para que no vaya pegado al borde."""

BASE = Path(__file__).resolve().parent
ORIGEN = BASE / "icono_origen.jpeg"
SALIDA = BASE.parent / "assets"


def degradado(lado: int) -> Image.Image:
    """Degradado en diagonal, de violeta a rosa."""
    # El color solo depende de x+y, asi que la rampa se calcula una vez y luego
    # cada pixel la consulta: pintarla punto a punto tarda un mundo.
    pasos = 2 * (lado - 1)
    rampa = [
        tuple(
            round(inicio + (fin - inicio) * diagonal / pasos)
            for inicio, fin in zip(ACENTO, ACENTO_CALIDO, strict=True)
        )
        for diagonal in range(pasos + 1)
    ]

    base = Image.new("RGB", (lado, lado))
    base.putdata([rampa[x + y] for y in range(lado) for x in range(lado)])
    return base


def silueta(lado: int) -> Image.Image:
    """Recorta el dibujo del original y lo devuelve en transparente.

    El original viene con mucho fondo negro arriba y abajo, asi que el encuadre
    no se fija a mano: se busca donde hay luz y se cuadra alrededor de eso.
    """
    imagen = Image.open(ORIGEN).convert("L")

    # Umbral bajo: basta con distinguir el trazo del negro del fondo.
    caja = imagen.point(lambda v: 255 if v > 45 else 0).getbbox()
    if caja is None:
        raise RuntimeError(f"{ORIGEN.name} esta en negro, no hay dibujo que recortar")

    izquierda, arriba, derecha, abajo = caja
    medida = round(max(derecha - izquierda, abajo - arriba) * AIRE)
    centro_x, centro_y = (izquierda + derecha) // 2, (arriba + abajo) // 2
    recorte = imagen.crop(
        (
            centro_x - medida // 2,
            centro_y - medida // 2,
            centro_x + medida // 2,
            centro_y + medida // 2,
        )
    ).resize((lado, lado), Image.Resampling.LANCZOS)

    # El brillo pasa a ser opacidad: el trazo queda solido y el fondo desaparece.
    # El x1.25 compensa el borde gris del JPEG, que si no deja el trazo lavado.
    figura = Image.new("RGBA", (lado, lado), (*TINTA, 0))
    figura.putalpha(recorte.point(lambda v: min(255, round(v * 1.25))))
    return figura


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
    fondo = degradado(LADO)

    # Icono clasico: degradado con esquinas y la figura encima.
    clasico = esquinas(fondo.copy(), radio=round(LADO * 0.22))
    clasico.alpha_composite(silueta(LADO))
    clasico.save(SALIDA / "icono.png")

    # Adaptativo: Android recorta hasta un 33%, asi que el fondo va a sangre y
    # la figura, mas pequenia y centrada, para que no le corte la cabeza.
    fondo.save(SALIDA / "icono_fondo.png")

    primer_plano = Image.new("RGBA", (LADO, LADO), (0, 0, 0, 0))
    reducida = silueta(round(LADO * 0.62))
    margen = (LADO - reducida.width) // 2
    primer_plano.alpha_composite(reducida, (margen, margen))
    primer_plano.save(SALIDA / "icono_primer_plano.png")

    print(f"iconos generados en {SALIDA}")


if __name__ == "__main__":
    main()
