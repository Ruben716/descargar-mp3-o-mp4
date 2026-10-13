"""Genera el icono de Tumbao a partir del dibujo original.

Se deja como script y no como imagenes sueltas para que el icono sea
reproducible: si cambia el color de la app, se vuelve a ejecutar y ya.

    python movil/herramientas/generar_icono.py

El dibujo de partida (`icono_origen.jpeg`) es trazo blanco sobre fondo negro.
De ahi se saca la silueta: lo claro es la figura y lo oscuro se descarta. Luego
se repinta en tinta sobre el degradado azul de la marca, igual que los botones
principales, porque asi se lee mucho mejor en la parrilla de aplicaciones que
un trazo fino y blanco perdido entre iconos oscuros. Por eso tampoco se usa la
version en neon (la figura azul sobre negro): a 48 px, sobre un fondo de
pantalla oscuro, se perdia.
"""
from pathlib import Path

from PIL import Image, ImageDraw

#: Los mismos colores que tema.dart, para que el icono no vaya por libre.
ACENTO_HIELO = (69, 200, 255)  # #45C8FF, Tema.acentoHielo
AZUL_PROFUNDO = (58, 123, 255)  # #3A7BFF, Tema.azulProfundo
AZUL_NOCHE = (37, 99, 255)  # #2563FF, solo aqui y en el widget
PARADAS = (ACENTO_HIELO, AZUL_PROFUNDO, AZUL_NOCHE)
"""El degradado del icono, de arriba a la izquierda a abajo a la derecha.

Lleva una parada mas que el de los botones: el azul noche de la esquina le da
peso al icono entre los demas de la parrilla. Ahi no va texto, solo la figura,
y la tinta sigue dando mas de 4:1 incluso en esa esquina.
"""
TINTA = (4, 8, 20)  # #040814, Tema.tinta

LADO = 1024
AIRE = 1.34
"""Cuanto se abre el recorte respecto al dibujo, para que no vaya pegado al borde."""

BASE = Path(__file__).resolve().parent
ORIGEN = BASE / "icono_origen.jpeg"
SALIDA = BASE.parent / "assets"


def degradado(lado: int) -> Image.Image:
    """Degradado en diagonal, de cian hielo a azul electrico."""
    # El color solo depende de x+y, asi que la rampa se calcula una vez y luego
    # cada pixel la consulta: pintarla punto a punto tarda un mundo.
    pasos = 2 * (lado - 1)
    tramos = len(PARADAS) - 1
    rampa: list[tuple[int, ...]] = []
    for diagonal in range(pasos + 1):
        # Por tramos: se ve en que par de paradas cae la diagonal y cuanto
        # avanza dentro de el.
        t = diagonal / pasos * tramos
        i = min(int(t), tramos - 1)
        f = t - i
        rampa.append(
            tuple(
                round(inicio + (fin - inicio) * f)
                for inicio, fin in zip(PARADAS[i], PARADAS[i + 1], strict=True)
            )
        )

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
