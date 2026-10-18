"""Pruebas de voz.py: cuadrar la letra con donde entra la voz.

voz.py vive junto al puente, como ritmo.py, y lo importa: se carga por su
ruta con esa carpeta en el camino de importacion.
"""
import importlib.util
import math
import random
import shutil
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from types import ModuleType

CARPETA = Path("movil/android/app/src/main/python")


def _cargar() -> ModuleType:
    if str(CARPETA) not in sys.path:
        sys.path.insert(0, str(CARPETA))
    spec = importlib.util.spec_from_file_location("voz_prueba", CARPETA / "voz.py")
    assert spec and spec.loader
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


voz = _cargar()


def _ffmpeg() -> str | None:
    encontrado = shutil.which("ffmpeg")
    if encontrado:
        return encontrado
    try:
        import imageio_ffmpeg

        return str(imageio_ffmpeg.get_ffmpeg_exe())
    except Exception:
        return None


FFMPEG = _ffmpeg()


def _frases(semilla: int, segundos: float) -> list[tuple[float, float]]:
    """Frases de voz a destiempo e irregulares, como los versos de verdad."""
    azar = random.Random(semilla)
    frases: list[tuple[float, float]] = []
    t = 4.3
    while t < segundos - 4:
        dura = azar.uniform(1.4, 3.0)
        frases.append((t, dura))
        t += dura + azar.uniform(0.4, 2.4)
    return frases


def _cancion(ruta: Path, frases: list[tuple[float, float]], segundos: float, con_voz: bool) -> None:
    """Base estereo (fondos abiertos y golpes en el centro cada medio segundo)
    y, si se pide, una voz en el centro que canta en [frases]."""
    tasa = 8000
    azar = random.Random(3)
    n = int(tasa * segundos)
    izq = [0.03 * azar.uniform(-1, 1) + 0.12 * math.sin(2 * math.pi * 196 * i / tasa) for i in range(n)]
    der = [0.03 * azar.uniform(-1, 1) + 0.12 * math.sin(2 * math.pi * 247 * i / tasa + 1) for i in range(n)]
    for k in range(int(segundos / 0.5)):
        a = int(k * 0.5 * tasa)
        for j in range(min(int(0.12 * tasa), n - a)):
            golpe = math.exp(-j / (0.03 * tasa)) * (0.5 * math.sin(2 * math.pi * 60 * j / tasa)
                                                     + (0.25 * azar.uniform(-1, 1) if k % 2 else 0))
            izq[a + j] += golpe
            der[a + j] += golpe
    if con_voz:
        for t0, dura in frases:
            a, b = int(t0 * tasa), min(n, int((t0 + dura) * tasa))
            for i in range(a, b):
                s = (i - a) / tasa
                envolvente = min(1.0, s / 0.04) * min(1.0, (dura - s) / 0.15)
                f = 220 * (1 + 0.01 * math.sin(2 * math.pi * 5.5 * s))
                v = sum((0.35 / h) * math.sin(2 * math.pi * f * h * s) for h in range(1, 7))
                izq[i] += envolvente * v * 0.6
                der[i] += envolvente * v * 0.6
    pico = max(max(map(abs, izq)), max(map(abs, der)))
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(tasa)
        w.writeframes(b"".join(struct.pack("<hh", int(32000 * a / pico), int(32000 * b / pico))
                               for a, b in zip(izq, der, strict=True)))


class AlinearTests(unittest.TestCase):
    """Con entradas de voz ya calculadas: sin FFmpeg."""

    INICIOS = (4300, 7100, 10250, 13900, 16800, 19650, 21700, 26100, 28600, 33600)

    @staticmethod
    def _entradas(desfase_real: int, golpes: bool = True, voz_presente: bool = True) -> list[float]:
        serie = [0.0] * 4500
        if golpes:
            # Un golpe cada medio segundo, mas flojo que la voz: lo que confunde.
            for i in range(0, len(serie), 50):
                serie[i] = 3.0
        if voz_presente:
            for t in AlinearTests.INICIOS:
                serie[(t + desfase_real) // 10] = 8.0
        return serie

    def test_encuentra_cuanto_correr_la_letra(self):
        for real in (1500, -2300, 600):
            r = voz.alinear(self._entradas(real), self.INICIOS)
            self.assertAlmostEqual(r["desfase"], real, delta=40, msg=f"desfase real {real}")
            self.assertGreaterEqual(r["ventaja"], voz.VENTAJA_MINIMA)

    def test_una_version_con_entradilla_se_encuentra_buscando_mas_lejos(self):
        # Un videoclip con 21 s de entrada: con el rango de siempre no se ve.
        serie = self._entradas(0, voz_presente=False) + [0.0] * 2500
        for t in self.INICIOS:
            serie[(t + 21000) // 10] = 8.0
        cerca = voz.alinear(serie, self.INICIOS)
        self.assertNotAlmostEqual(cerca["desfase"], 21000, delta=1000)
        lejos = voz.alinear(serie, self.INICIOS, rango_ms=29000)
        self.assertAlmostEqual(lejos["desfase"], 21000, delta=40)
        self.assertGreaterEqual(lejos["ventaja"], voz.VENTAJA_MINIMA)
        self.assertGreaterEqual(lejos["confianza"], voz.CONFIANZA_MINIMA)

    def test_si_solo_hay_golpes_regulares_no_hay_ajuste_claro(self):
        r = voz.alinear(self._entradas(0, voz_presente=False), self.INICIOS)
        self.assertLess(r["ventaja"], voz.VENTAJA_MINIMA)

    def test_con_pocos_versos_no_se_intenta(self):
        r = voz.alinear(self._entradas(1500), self.INICIOS[:3])
        self.assertEqual(r, {"desfase": 0, "confianza": 0.0, "ventaja": 0.0})

    def test_maximos_en_ventana(self):
        self.assertEqual(voz._maximos([0, 5, 0, 0, 0, 0, 2, 0], 1, 2), [5, 5, 5, 0, 2, 2, 2, 2])

    def test_en_mono_vale_el_centro(self):
        # Sin lados (mono), la voz es el centro sin mas; una subida es una entrada.
        centro = [10.0] * 30 + [40.0] * 30
        entradas = voz.entradas_de_voz(centro, [0.0] * 60)
        self.assertEqual(max(range(60), key=lambda i: entradas[i]), 30, "la subida esta en la trama 30")
        self.assertEqual(entradas[:15], [0.0] * 15)


@unittest.skipUnless(FFMPEG, "Hace falta FFmpeg (o imageio-ffmpeg)")
class SincronizarConFfmpegTests(unittest.TestCase):
    SEGUNDOS = 40.0

    def test_con_voz_cuadra_la_letra_y_sin_voz_no_toca_nada(self):
        frases = _frases(7, self.SEGUNDOS)
        with tempfile.TemporaryDirectory() as carpeta:
            cancion = Path(carpeta) / "cancion.wav"
            _cancion(cancion, frases, self.SEGUNDOS, con_voz=True)
            # La letra marca cada verso 1,5 s antes de que entre la voz.
            inicios = [int(t * 1000) - 1500 for t, _ in frases]
            r = voz.sincronizar(str(cancion), inicios, str(FFMPEG))
            self.assertAlmostEqual(r["desfase"], 1500, delta=60)
            self.assertTrue(r["aplicar"])

            # Ya a la par: se ve, pero no hay nada que corregir.
            r = voz.sincronizar(str(cancion), [int(t * 1000) for t, _ in frases], str(FFMPEG))
            self.assertLess(abs(r["desfase"]), voz.AJUSTE_MINIMO_MS)
            self.assertFalse(r["aplicar"])
            self.assertTrue(r["seguro"], "a la par y con voz: sus tiempos valen")

            base = Path(carpeta) / "base.wav"
            _cancion(base, frases, self.SEGUNDOS, con_voz=False)
            r = voz.sincronizar(str(base), inicios, str(FFMPEG))
            self.assertFalse(r["aplicar"], "sin voz no hay de donde sacar el ajuste")
            self.assertFalse(r["seguro"])


class PuenteSincronizarTests(unittest.TestCase):
    """sincronizar_letra del puente: nunca deja escapar una excepcion."""

    def setUp(self) -> None:
        spec = importlib.util.spec_from_file_location("puente_voz_prueba", CARPETA / "puente.py")
        assert spec and spec.loader
        self.puente = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.puente)

    def test_lo_que_falla_se_responde_sin_lanzar(self) -> None:
        import json
        from unittest.mock import patch

        with patch.object(self.puente.shutil, "which", return_value=None):
            self.assertFalse(json.loads(self.puente.sincronizar_letra("/tmp/x.mp3", "[1000]"))["ok"])
        with patch.object(self.puente.shutil, "which", return_value="/bin/ffmpeg"):
            datos = json.loads(self.puente.sincronizar_letra("/tmp/x.mp3", "esto no es json"))
        self.assertFalse(datos["ok"])
        self.assertIn("JSONDecodeError", datos["error"])

    def test_devuelve_el_ajuste(self) -> None:
        import json
        from unittest.mock import patch

        respuesta = {"desfase": 1500, "confianza": 5.0, "ventaja": 1.9, "seguro": True, "aplicar": True}
        with patch.object(self.puente.shutil, "which", return_value="/bin/ffmpeg"), \
                patch.object(voz, "sincronizar", return_value=respuesta) as sincronizar, \
                patch.dict("sys.modules", {"voz": voz}):
            datos = json.loads(self.puente.sincronizar_letra("/tmp/x.mp3", "[1000, 2500]"))
        self.assertEqual(datos, {"ok": True, **respuesta})
        sincronizar.assert_called_once_with("/tmp/x.mp3", [1000, 2500], ffmpeg="/bin/ffmpeg")

    def test_con_rango_busca_mas_lejos(self) -> None:
        import json
        from unittest.mock import patch

        with patch.object(self.puente.shutil, "which", return_value="/bin/ffmpeg"), \
                patch.object(voz, "sincronizar", return_value={"desfase": 0}) as sincronizar, \
                patch.dict("sys.modules", {"voz": voz}):
            self.puente.sincronizar_letra("/tmp/x.mp3", json.dumps({"inicios": [1000, 2500], "rango": 28000}))
        sincronizar.assert_called_once_with("/tmp/x.mp3", [1000, 2500], ffmpeg="/bin/ffmpeg", rango_ms=28000)


if __name__ == "__main__":
    unittest.main()
