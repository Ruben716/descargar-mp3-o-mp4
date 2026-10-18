"""Pruebas de video_letra.py: el video de un trozo de la cancion con su letra.

Vive junto al puente, como ritmo.py y voz.py: se carga por su ruta. Lo puro
(la lista del concat, la orden, la cadena de codificadores) se prueba sin
FFmpeg; si lo hay, ademas se hace un video de verdad y se mira lo que salio.
"""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

CARPETA = Path("movil/android/app/src/main/python")


def _cargar() -> ModuleType:
    if str(CARPETA) not in sys.path:
        sys.path.insert(0, str(CARPETA))
    spec = importlib.util.spec_from_file_location("video_letra_prueba", CARPETA / "video_letra.py")
    assert spec and spec.loader
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


video = _cargar()

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")


class ConcatTests(unittest.TestCase):
    def test_cada_png_con_su_duracion_y_el_ultimo_repetido(self) -> None:
        texto = video.texto_concat([("/c/0.png", 3200), ("/c/1.png", 11800)])
        self.assertEqual(texto.splitlines(), [
            "ffconcat version 1.0",
            "file '/c/0.png'",
            "duration 3.200",
            "file '/c/1.png'",
            "duration 11.800",
            "file '/c/1.png'",
        ])
        self.assertTrue(texto.endswith("\n"))

    def test_una_comilla_en_la_ruta_no_rompe_la_lista(self) -> None:
        texto = video.texto_concat([("/c/l'amour.png", 1000)])
        self.assertIn("file '/c/l'\\''amour.png'", texto.splitlines())

    def test_las_duraciones_suman_lo_pedido(self) -> None:
        # Sobran: se quitan los que no caben y el ultimo se recorta.
        self.assertEqual(
            video.ajustar_duraciones([("a", 4000), ("b", 9000), ("c", 5000)], 10000),
            [("a", 4000), ("b", 6000)],
        )
        # Faltan: el ultimo se estira hasta el final.
        self.assertEqual(
            video.ajustar_duraciones([("a", 4000), ("b", 1000)], 15000),
            [("a", 4000), ("b", 11000)],
        )
        # Lo que no dura nada no es un fotograma.
        self.assertEqual(video.ajustar_duraciones([("a", 0), ("b", 2000)], 2000), [("b", 2000)])
        self.assertEqual(video.ajustar_duraciones([], 2000), [])


class OrdenTests(unittest.TestCase):
    def _orden(self, codificador: tuple[str, ...] = ("-c:v", "libx264")) -> list[str]:
        return video.orden(
            "ffmpeg", "/c/lista.txt", "/c/cancion.m4a", 61250, 15000, "/c/sale.mp4", codificador,
        )

    def test_recorta_el_audio_antes_de_abrirlo(self) -> None:
        orden = self._orden()
        audio = orden.index("/c/cancion.m4a")
        self.assertEqual(
            orden[audio - 5:audio + 1], ["-ss", "61.250", "-t", "15.000", "-i", "/c/cancion.m4a"],
        )
        lista = orden.index("/c/lista.txt")
        self.assertEqual(orden[lista - 5:lista + 1], ["-f", "concat", "-safe", "0", "-i", "/c/lista.txt"])
        self.assertLess(lista, audio, "los fotogramas son la entrada 0 y el audio la 1")

    def test_salida_lista_para_compartir(self) -> None:
        orden = self._orden(("-c:v", "libx264", "-preset", "veryfast", "-crf", "23"))
        texto = " ".join(orden)
        for trozo in ("-map [v] -map [a]", "-t 15.000 -r 30", "-c:v libx264 -preset veryfast -crf 23",
                      "-pix_fmt yuv420p", "-c:a aac", "-movflags +faststart"):
            self.assertIn(trozo, texto)
        self.assertEqual(orden[-1], "/c/sale.mp4")
        self.assertIn("-y", orden, "se reintenta sobre la misma salida")

    def test_filtro_con_fundidos_onda_y_superposicion(self) -> None:
        grafo = video.filtro(15000)
        self.assertIn("afade=t=in:st=0:d=0.500", grafo)
        self.assertIn("afade=t=out:st=14.500:d=0.500", grafo)
        self.assertIn("apad", grafo, "si la cancion acaba antes, silencio y no un video cojo")
        self.assertIn("showwaves=s=640x160:mode=cline:colors=white@0.55", grafo)
        self.assertIn("aformat=channel_layouts=mono", grafo)
        self.assertIn("[0:v]scale=720:1280", grafo)
        self.assertIn("fps=30", grafo)
        self.assertIn(f"overlay=x=(W-w)/2:y={1280 - 160 - video.ONDA_MARGEN}", grafo)
        self.assertTrue(grafo.endswith("format=yuv420p[v]"))

    def test_en_un_fragmento_cortisimo_los_fundidos_no_se_pisan(self) -> None:
        grafo = video.filtro(600)
        self.assertIn("afade=t=in:st=0:d=0.300", grafo)
        self.assertIn("afade=t=out:st=0.300:d=0.300", grafo)


class _Hecho:
    def __init__(self, codigo: int, error: str = "") -> None:
        self.returncode = codigo
        self.stderr = error
        self.stdout = ""


class CadenaDeCodificadoresTests(unittest.TestCase):
    """subprocess.run simulado: que codificador se pide y cuando se reintenta."""

    def setUp(self) -> None:
        self._carpeta = tempfile.TemporaryDirectory()
        self.carpeta = Path(self._carpeta.name)
        self.addCleanup(self._carpeta.cleanup)
        self.audio = self.carpeta / "cancion.m4a"
        self.audio.write_bytes(b"audio")
        self.pngs = []
        for i in range(2):
            png = self.carpeta / f"{i}.png"
            png.write_bytes(b"png")
            self.pngs.append(str(png))
        self.salida = self.carpeta / "sale.mp4"
        self.listas: list[str] = []

    def _crear(self, respuestas: list[_Hecho]) -> tuple[dict, list[list[str]]]:
        llamadas: list[list[str]] = []

        def correr(orden: list[str], **_: object) -> _Hecho:
            llamadas.append(orden)
            self.listas.append(Path(orden[orden.index("concat") + 4]).read_text(encoding="utf-8"))
            hecho = respuestas[len(llamadas) - 1]
            if hecho.returncode == 0:
                self.salida.write_bytes(b"\x00\x00\x00\x18ftypisom")
            else:
                # FFmpeg deja a veces un archivo a medias al fallar.
                self.salida.write_bytes(b"a medias")
            return hecho

        with patch.object(video.subprocess, "run", side_effect=correr):
            r = video.crear("ffmpeg", str(self.audio), 1000, 15000,
                            [(self.pngs[0], 4000), (self.pngs[1], 11000)], str(self.salida))
        return r, llamadas

    @staticmethod
    def _codificador(orden: list[str]) -> str:
        return orden[orden.index("-c:v") + 1]

    def test_si_no_hay_libx264_prueba_el_del_telefono(self) -> None:
        r, llamadas = self._crear([
            _Hecho(8, "[vost#0:0 @ 0x1] Unknown encoder 'libx264'\n"
                      "Error opening output files: Encoder not found"),
            _Hecho(0),
        ])
        self.assertEqual(r, {"ok": True, "ruta": str(self.salida), "codificador": "h264_mediacodec",
                             "onda": True})
        self.assertEqual([self._codificador(o) for o in llamadas], ["libx264", "h264_mediacodec"])
        self.assertIn("-b:v", llamadas[1])
        self.assertFalse(Path(f"{self.salida}.txt").exists(), "la lista del concat se borra")
        self.assertIn(f"file '{self.pngs[1]}'\nduration 11.000\nfile '{self.pngs[1]}'", self.listas[0])

    def test_y_si_tampoco_el_mpeg4_de_siempre(self) -> None:
        r, llamadas = self._crear([
            _Hecho(1, "Unknown encoder 'libx264'"),
            _Hecho(1, "Error while opening encoder for output stream #0:0"),
            _Hecho(0),
        ])
        self.assertTrue(r["ok"])
        self.assertEqual(r["codificador"], "mpeg4")
        self.assertEqual(llamadas[2][llamadas[2].index("-c:v"):llamadas[2].index("-c:v") + 4],
                         ["-c:v", "mpeg4", "-q:v", "3"])

    def test_sin_ninguno_dice_por_que(self) -> None:
        r, llamadas = self._crear([_Hecho(1, "Unknown encoder 'x'")] * 3)
        self.assertEqual(len(llamadas), 3)
        self.assertFalse(r["ok"])
        self.assertIn("Unknown encoder", r["error"])
        self.assertFalse(self.salida.exists(), "no queda un video a medias")

    def test_si_no_entiende_la_onda_lo_hace_sin_ella(self) -> None:
        r, llamadas = self._crear([
            _Hecho(1, "[AVFilterGraph @ 0x1] No such filter: 'showwaves'\n"
                      "Error initializing complex filters."),
            _Hecho(0),
        ])
        self.assertEqual(r, {"ok": True, "ruta": str(self.salida), "codificador": "libx264", "onda": False})
        self.assertIn("showwaves", llamadas[0][llamadas[0].index("-filter_complex") + 1])
        self.assertNotIn("showwaves", llamadas[1][llamadas[1].index("-filter_complex") + 1])
        self.assertEqual(self._codificador(llamadas[1]), "libx264", "el mismo codificador, sin la onda")

    def test_otro_fallo_no_se_arregla_cambiando_de_codificador(self) -> None:
        r, llamadas = self._crear([_Hecho(1, "cancion.m4a: Invalid data found when processing input")])
        self.assertEqual(len(llamadas), 1)
        self.assertFalse(r["ok"])
        self.assertIn("Invalid data", r["error"])

    def test_si_tarda_demasiado_no_lanza(self) -> None:
        with patch.object(video.subprocess, "run", side_effect=subprocess.TimeoutExpired("ffmpeg", 120)):
            r = video.crear("ffmpeg", str(self.audio), 0, 15000, [(self.pngs[0], 15000)], str(self.salida))
        self.assertEqual(r, {"ok": False, "error": "El video tardo demasiado."})

    def test_sin_fotogramas_o_sin_audio_ni_se_llama(self) -> None:
        with patch.object(video.subprocess, "run") as correr:
            sin_png = video.crear("ffmpeg", str(self.audio), 0, 15000,
                                  [(str(self.carpeta / "no.png"), 15000)], str(self.salida))
            vacio = video.crear("ffmpeg", str(self.audio), 0, 15000, [], str(self.salida))
            sin_audio = video.crear("ffmpeg", str(self.carpeta / "no.m4a"), 0, 15000,
                                    [(self.pngs[0], 15000)], str(self.salida))
            sin_duracion = video.crear("ffmpeg", str(self.audio), 0, 0,
                                       [(self.pngs[0], 15000)], str(self.salida))
        correr.assert_not_called()
        for r in (sin_png, vacio, sin_audio, sin_duracion):
            self.assertFalse(r["ok"])
            self.assertTrue(r["error"])


@unittest.skipUnless(FFMPEG, "Hace falta FFmpeg")
class VideoDeVerdadTests(unittest.TestCase):
    """Con el FFmpeg del sistema: un video que se puede abrir."""

    def test_sale_un_mp4_con_video_y_audio_de_lo_pedido(self) -> None:
        assert FFMPEG
        with tempfile.TemporaryDirectory() as carpeta:
            base = Path(carpeta)
            pngs = []
            for i, color in enumerate(("0x334488", "0x884433")):
                png = base / f"{i}.png"
                subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "lavfi",
                                "-i", f"color=c={color}:s=72x128", "-frames:v", "1", str(png)], check=True)
                pngs.append(str(png))
            tono = base / "tono.wav"
            subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "lavfi",
                            "-i", "sine=f=330:d=3", "-ac", "2", str(tono)], check=True)
            salida = base / "letra.mp4"

            r = video.crear(FFMPEG, str(tono), 500, 2000, [(pngs[0], 800), (pngs[1], 1200)], str(salida))

            self.assertTrue(r["ok"], r)
            self.assertEqual(r["ruta"], str(salida))
            # Con libx264 en el FFmpeg del sistema no hace falta bajar de la cadena.
            encoders = subprocess.run([FFMPEG, "-hide_banner", "-encoders"], capture_output=True, text=True)
            esperado = "libx264" if " libx264 " in encoders.stdout else r["codificador"]
            self.assertEqual(r["codificador"], esperado)
            datos = salida.read_bytes()
            self.assertEqual(datos[4:8], b"ftyp")
            if not FFPROBE:
                return
            sondeo = subprocess.run(
                [FFPROBE, "-v", "error", "-show_entries",
                 "stream=codec_type,codec_name,width,height,pix_fmt:format=duration",
                 "-of", "json", str(salida)],
                capture_output=True, text=True, check=True,
            )
            info = json.loads(sondeo.stdout)
            tipos = {s["codec_type"]: s for s in info["streams"]}
            self.assertEqual(set(tipos), {"video", "audio"})
            self.assertEqual((tipos["video"]["width"], tipos["video"]["height"]), (720, 1280))
            self.assertEqual(tipos["video"]["pix_fmt"], "yuv420p")
            self.assertEqual(tipos["audio"]["codec_name"], "aac")
            self.assertAlmostEqual(float(info["format"]["duration"]), 2.0, delta=0.1)


class PuenteVideoLetraTests(unittest.TestCase):
    """video_letra del puente: traduce el JSON y nunca deja escapar nada."""

    def setUp(self) -> None:
        spec = importlib.util.spec_from_file_location("puente_video_prueba", CARPETA / "puente.py")
        assert spec and spec.loader
        self.puente = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.puente)

    def test_sin_ffmpeg_o_con_json_roto_responde_sin_lanzar(self) -> None:
        with patch.object(self.puente.shutil, "which", return_value=None):
            sin_ffmpeg = json.loads(self.puente.video_letra("/c/a.m4a", 0, 15000, "[]", "/c/s.mp4"))
        self.assertFalse(sin_ffmpeg["ok"])
        with patch.object(self.puente.shutil, "which", return_value="/bin/ffmpeg"):
            datos = json.loads(self.puente.video_letra("/c/a.m4a", 0, 15000, "esto no es json", "/c/s.mp4"))
        self.assertFalse(datos["ok"])
        self.assertIn("JSONDecodeError", datos["error"])

    def test_pasa_los_fotogramas_como_pares(self) -> None:
        respuesta = {"ok": True, "ruta": "/c/s.mp4", "codificador": "libx264"}
        fotogramas = json.dumps([{"png": "/c/0.png", "ms": 4000}, {"png": "/c/1.png", "ms": 11000}])
        with patch.object(self.puente.shutil, "which", return_value="/bin/ffmpeg"), \
                patch.object(video, "crear", return_value=respuesta) as crear, \
                patch.dict("sys.modules", {"video_letra": video}):
            datos = json.loads(self.puente.video_letra("/c/a.m4a", 61250, 15000, fotogramas, "/c/s.mp4"))
        self.assertEqual(datos, respuesta)
        crear.assert_called_once_with(
            "/bin/ffmpeg", "/c/a.m4a", 61250, 15000, [("/c/0.png", 4000), ("/c/1.png", 11000)], "/c/s.mp4",
        )


if __name__ == "__main__":
    unittest.main()
