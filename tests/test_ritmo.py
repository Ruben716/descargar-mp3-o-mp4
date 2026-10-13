"""Pruebas del analisis de pulso y energia que usa el DJ automatico del movil.

ritmo.py vive junto al puente y no en el nucleo, asi que se carga por su ruta,
como red_android.py. El audio se fabrica aqui mismo: ni red ni archivos.
"""

import importlib.util
import json
import math
import random
import shutil
import subprocess
import tempfile
import time
import unittest
from array import array
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

CARPETA = Path("movil/android/app/src/main/python")


def _cargar(nombre: str, archivo: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(nombre, CARPETA / archivo)
    assert spec and spec.loader
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


ritmo = _cargar("ritmo_prueba", "ritmo.py")


def pcm_sintetico(bpm: float, segundos: float, silencio: float = 0.0, semilla: int = 1) -> bytes:
    """Tres bandas intercaladas a 12 kHz, como las saca FFmpeg: bombo en cada
    pulso (graves), caja en 2 y 4 (medios) y charles a contratiempo (agudos)."""
    azar = random.Random(semilla)
    tasa = ritmo.TASA
    pulso = round(60 * tasa / bpm)
    compas: list[int] = []
    for p in range(4):
        for i in range(pulso):
            t = i / tasa
            bombo = 20000 * math.exp(-25 * t) * math.sin(2 * math.pi * 60 * t)
            caja = 9000 * math.exp(-30 * t) * (2 * azar.random() - 1) if p in (1, 3) else 0.0
            tc = t - pulso / tasa / 2
            charles = 4000 * math.exp(-80 * tc) * (2 * azar.random() - 1) if tc >= 0 else 0.0
            compas += (int(bombo), int(caja), int(charles))
    muestras = array("h", [0] * (3 * round(silencio * tasa)))
    muestras += array("h", compas) * int(segundos * bpm / 240)
    return muestras.tobytes()


def analizar_pcm(pcm: bytes) -> dict[str, Any]:
    e = ritmo.Energias()
    # Trozos de tamano raro: el acumulador tiene que coser bien los bordes.
    for i in range(0, len(pcm), 7777):
        e.anadir(pcm[i:i + 7777])
    datos: dict[str, Any] = ritmo.rasgos(e.filas)
    return datos


RESUMEN_EBUR128 = (
    "Input #0, mp3, from 'x.mp3':\n  Metadata:\n    genre           : Reggaeton\n"
    "    date            : 2022-05-06\n  Stream #0:0: Audio: mp3\nStream mapping:\n"
    "[Parsed_ebur128_0 @ 0x0] Summary:\n\n  Integrated loudness:\n"
    "    I:          -8.4 LUFS\n    Threshold: -18.6 LUFS\n\n  Loudness range:\n"
    "    LRA:         5.2 LU\n"
)


class RitmoTests(unittest.TestCase):
    def test_tempo_de_un_patron_conocido(self) -> None:
        for bpm in (128, 96, 90, 150):
            with self.subTest(bpm=bpm):
                datos = analizar_pcm(pcm_sintetico(bpm, 60))
                self.assertAlmostEqual(datos["bpm"], bpm, delta=bpm * 0.02)

    def test_silencio_no_tiene_pulso(self) -> None:
        datos = analizar_pcm(bytes(3 * 2 * ritmo.TASA * 20))
        self.assertIsNone(datos["bpm"])
        self.assertIsNone(datos["pulsoInicioMs"])

    def test_ruido_no_inventa_un_pulso(self) -> None:
        azar = random.Random(3)
        ruido = array("h", (int(3000 * (2 * azar.random() - 1)) for _ in range(3 * ritmo.TASA * 30)))
        datos = analizar_pcm(ruido.tobytes())
        self.assertTrue(datos["bpm"] is None or datos["confianza"] < 0.1)

    def test_el_silencio_del_principio_no_cuenta(self) -> None:
        datos = analizar_pcm(pcm_sintetico(120, 40, silencio=3.0))
        self.assertAlmostEqual(datos["inicioMs"], 3000, delta=20)
        # El primer golpe cae justo al acabar el silencio, en la rejilla de 500 ms.
        self.assertAlmostEqual(datos["pulsoInicioMs"], 3000, delta=20)

    def test_el_ultimo_pulso_cae_en_la_rejilla(self) -> None:
        datos = analizar_pcm(pcm_sintetico(120, 60))
        resto = datos["pulsoFinMs"] % 500
        self.assertLessEqual(min(resto, 500 - resto), 20)

    def test_doble_y_mitad_cuentan_como_el_mismo_tempo(self) -> None:
        self.assertGreater(ritmo.peso_previo(120), ritmo.peso_previo(240))
        self.assertGreater(ritmo.peso_previo(120), ritmo.peso_previo(60))

    def test_lee_lufs_lra_y_etiquetas_de_la_salida_de_ffmpeg(self) -> None:
        lufs, lra, etiquetas = ritmo.leer_resumen(RESUMEN_EBUR128)
        self.assertEqual((lufs, lra), (-8.4, 5.2))
        self.assertEqual(etiquetas["genre"], "Reggaeton")
        self.assertEqual(etiquetas["date"], "2022-05-06")

    def test_en_opus_las_etiquetas_van_en_la_pista(self) -> None:
        """En Opus y OGG FFmpeg las sangra seis espacios, dentro del Stream."""
        salida = ("Input #0, ogg, from 'x.opus':\n  Stream #0:0: Audio: opus\n    Metadata:\n"
                  "      GENRE           : Salsa\n      DATE            : 1978\nStream mapping:\n")
        _, _, etiquetas = ritmo.leer_resumen(salida)
        self.assertEqual(etiquetas["genre"], "Salsa")
        self.assertEqual(etiquetas["date"], "1978")

    def test_un_resumen_a_cero_no_es_una_medida(self) -> None:
        lufs, _, _ = ritmo.leer_resumen("Summary:\n    I:          0.0 LUFS\n")
        self.assertIsNone(lufs)

    def test_mas_golpes_y_mas_fuerte_es_mas_energia(self) -> None:
        tranquila = ritmo.energia_cruda(-20, 1.0, 70, 0.02, 12)
        potente = ritmo.energia_cruda(-7, 5.0, 128, 0.12, 4)
        self.assertLess(tranquila, 0.25)
        self.assertGreater(potente, 0.8)

    def test_sin_datos_no_revienta(self) -> None:
        datos = ritmo.rasgos([[], [], []])
        self.assertIsNone(datos["bpm"])
        self.assertEqual(datos["golpes"], 0)

    def test_cuatro_minutos_se_analizan_rapido(self) -> None:
        pcm = pcm_sintetico(128, 240)
        inicio = time.perf_counter()
        analizar_pcm(pcm)
        # En un PC va en menos de un segundo; el margen es para maquinas lentas.
        self.assertLess(time.perf_counter() - inicio, 5)


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


@unittest.skipUnless(FFMPEG, "Hace falta FFmpeg (o imageio-ffmpeg)")
class RitmoConFfmpegTests(unittest.TestCase):
    """De punta a punta con audio fabricado por FFmpeg (lavfi): sin red."""

    def _fabricar(self, carpeta: Path, bpm: float, segundos: int = 40) -> Path:
        p = 60 / bpm
        expr = (f"0.9*sin(2*PI*55*t)*exp(-20*mod(t,{p}))"
                f"+0.3*(2*random(0)-1)*exp(-70*mod(t+{p / 2},{p}))")
        destino = carpeta / f"prueba_{bpm}.flac"
        subprocess.run([str(FFMPEG), "-y", "-v", "error", "-f", "lavfi",
                        "-i", f"aevalsrc='{expr}':s=44100:d={segundos}", "-ac", "2", str(destino)],
                       check=True)
        return destino

    def test_tempo_y_sonoridad_de_un_flac_fabricado(self) -> None:
        with tempfile.TemporaryDirectory() as carpeta:
            ruta = self._fabricar(Path(carpeta), 124)
            datos = ritmo.analizar(str(ruta), ffmpeg=str(FFMPEG))
        self.assertAlmostEqual(datos["bpm"], 124, delta=2.5)
        self.assertIsNotNone(datos["lufs"])
        self.assertGreaterEqual(datos["energia"], 0)
        self.assertEqual(datos["version"], ritmo.VERSION)

    def test_un_tono_fijo_no_tiene_pulso(self) -> None:
        with tempfile.TemporaryDirectory() as carpeta:
            ruta = Path(carpeta) / "tono.flac"
            subprocess.run([str(FFMPEG), "-y", "-v", "error", "-f", "lavfi", "-i",
                            "sine=f=440:d=30", str(ruta)], check=True)
            datos = ritmo.analizar(str(ruta), ffmpeg=str(FFMPEG))
        self.assertTrue(datos["bpm"] is None or datos["confianza"] < 0.1 or datos["golpes"] < 0.5)

    def test_un_archivo_que_no_es_audio_lanza(self) -> None:
        with tempfile.TemporaryDirectory() as carpeta:
            ruta = Path(carpeta) / "nada.mp3"
            ruta.write_bytes(b"esto no es audio")
            with self.assertRaises(RuntimeError):
                ritmo.analizar(str(ruta), ffmpeg=str(FFMPEG))


class _ProcesoFalso:
    """Lo minimo de Popen: da el PCM por stdout y el resumen en el stderr recibido."""

    pcm = b""
    codigo = 0

    def __init__(self, orden: list[str], stdout: Any = None, stderr: Any = None) -> None:
        import io

        self.pid = 0
        self.stdout = io.BytesIO(self.pcm)
        stderr.write(RESUMEN_EBUR128.encode())

    def __enter__(self) -> "_ProcesoFalso":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def wait(self, timeout: float | None = None) -> int:
        return self.codigo

    def kill(self) -> None:
        return None


class PuenteAnalisisTests(unittest.TestCase):
    """analizar_audio del puente: nunca deja escapar una excepcion."""

    puente: ModuleType

    @classmethod
    def setUpClass(cls) -> None:
        cls.puente = _cargar("puente_analisis_prueba", "puente.py")

    def _llamar(self, codigo: int = 0, ffmpeg: str | None = "/bin/ffmpeg") -> dict[str, Any]:
        falso = type("Proceso", (_ProcesoFalso,), {"pcm": pcm_sintetico(124, 40), "codigo": codigo})
        with patch.dict("sys.modules", {"ritmo": ritmo}), \
                patch.object(ritmo.subprocess, "Popen", falso), \
                patch.object(self.puente.shutil, "which", return_value=ffmpeg):
            datos: dict[str, Any] = json.loads(self.puente.analizar_audio("/tmp/copia.mp3"))
        return datos

    def test_devuelve_pulso_y_sonoridad(self) -> None:
        datos = self._llamar()
        self.assertTrue(datos["ok"])
        self.assertAlmostEqual(datos["bpm"], 124, delta=2.5)
        self.assertIsNotNone(datos["pulsoFinMs"])
        self.assertEqual(datos["lufs"], -8.4)
        self.assertEqual(datos["genero"], "Reggaeton")
        self.assertEqual(datos["anio"], 2022)

    def test_si_ffmpeg_falla_lo_dice_sin_lanzar(self) -> None:
        datos = self._llamar(codigo=1)
        self.assertFalse(datos["ok"])
        self.assertIn("codigo 1", datos["error"])

    def test_sin_ffmpeg_lo_dice_sin_lanzar(self) -> None:
        datos = self._llamar(ffmpeg=None)
        self.assertFalse(datos["ok"])
        self.assertIn("FFmpeg", datos["error"])

    def test_si_tarda_demasiado_lo_dice_sin_lanzar(self) -> None:
        with patch.object(ritmo, "analizar", side_effect=subprocess.TimeoutExpired("ffmpeg", 240)):
            datos = self._llamar()
        self.assertFalse(datos["ok"])
        self.assertIn("tardo", datos["error"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
