"""Pruebas de las letras de YouTube Music que pide el movil.

letras_ytm.py vive junto al puente y no en el nucleo, asi que se carga por su
ruta, como ritmo.py. Las respuestas de YouTube se escriben aqui a mano con la
forma que tienen, y urlopen se sustituye: ninguna prueba sale a la red.
"""

import gzip
import importlib.util
import json
import sys
import unittest
from email.message import Message
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError

CARPETA = Path("movil/android/app/src/main/python")


def _cargar(nombre: str, archivo: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(nombre, CARPETA / archivo)
    assert spec and spec.loader
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


letras = _cargar("letras_ytm_prueba", "letras_ytm.py")

VIDEO = "dQw4w9WgXcQ"
LETRA = "MPLYt_abc123"


def pestana(titulo: str, browse: str | None = None, sin_letra: bool = False) -> dict[str, Any]:
    renderer: dict[str, Any] = {"title": titulo}
    if browse:
        renderer["endpoint"] = {"browseEndpoint": {"browseId": browse}}
    if sin_letra:
        renderer["unselectable"] = True
    return {"tabRenderer": renderer}


def respuesta_next(*pestanas: Any) -> dict[str, Any]:
    return {
        "responseContext": {"visitorData": "Cgt2aXNpdGFudGU%3D"},
        "contents": {"singleColumnMusicWatchNextResultsRenderer": {"tabbedRenderer": {
            "watchNextTabbedResultsRenderer": {"tabs": list(pestanas)},
        }}},
    }


CON_LETRA = respuesta_next(
    pestana("A continuacion"), pestana("Letra", LETRA), pestana("Relacionado", "MPTRt_xyz"),
)
SIN_LETRA = respuesta_next(
    pestana("A continuacion"), pestana("Letra", sin_letra=True), pestana("Relacionado", "MPTRt_xyz"),
)


def fila(texto: str, inicio: Any, fin: Any = "0") -> dict[str, Any]:
    return {"lyricLine": texto, "cueRange": {
        "startTimeMilliseconds": inicio, "endTimeMilliseconds": fin, "metadata": {"id": "1"},
    }}


def respuesta_con_tiempos(filas: Any, fuente: Any = "Fuente: LyricFind") -> dict[str, Any]:
    return {"contents": {"elementRenderer": {"newElement": {"type": {"componentType": {"model": {
        "timedLyricsModel": {"lyricsData": {"timedLyricsData": filas, "sourceMessage": fuente}},
    }}}}}}}


def respuesta_plana(texto: str, fuente: str | None = "Fuente: Musixmatch") -> dict[str, Any]:
    estante: dict[str, Any] = {"description": {"runs": [{"text": texto}]}}
    if fuente is not None:
        estante["footer"] = {"runs": [{"text": fuente}]}
    return {"contents": {"sectionListRenderer": {"contents": [
        {"musicDescriptionShelfRenderer": estante},
    ]}}}


TIEMPOS = respuesta_con_tiempos([
    fila("Voy a reir, voy a bailar", "1234", "4000"),
    fila("Vivir mi vida, la la la la", "4000"),
    fila("", "8100"),
])

FORMAS_ROTAS: list[Any] = [
    None, "", 3, [], {}, {"contents": None}, {"contents": []}, {"contents": {"x": 1}},
    {"contents": {"sectionListRenderer": {"contents": "no"}}},
    {"contents": {"sectionListRenderer": {"contents": [None, 7]}}},
    respuesta_next(), respuesta_next("no es una pestana", {"tabRenderer": "tampoco"}),
    respuesta_con_tiempos("no es lista"),
    respuesta_con_tiempos([None, 5, {"lyricLine": 3}]),
]


class _Respuesta:
    """Lo minimo de lo que devuelve urlopen: un contexto con read()."""

    def __init__(self, datos: Any, comprimir: bool = False) -> None:
        crudo = datos if isinstance(datos, bytes) else json.dumps(datos).encode("utf-8")
        self._crudo = gzip.compress(crudo) if comprimir else crudo

    def __enter__(self) -> "_Respuesta":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def read(self) -> bytes:
        return self._crudo


def _cuerpo(llamada: Any) -> dict[str, Any]:
    datos: dict[str, Any] = json.loads(llamada.args[0].data.decode("utf-8"))
    return datos


class NavegacionTests(unittest.TestCase):
    def test_browse_id_de_la_pestana_de_letra(self) -> None:
        self.assertEqual(letras.browse_id(CON_LETRA), LETRA)

    def test_pestana_unselectable_es_que_no_hay_letra(self) -> None:
        self.assertIsNone(letras.browse_id(SIN_LETRA))

    def test_no_toma_otra_pestana_por_la_letra(self) -> None:
        """Si la pestana de la letra no esta, Relacionado no la sustituye."""
        self.assertIsNone(letras.browse_id(respuesta_next(pestana("A continuacion"),
                                                          pestana("Relacionado", "MPTRt_xyz"))))

    def test_lineas_ordenadas_y_en_milisegundos(self) -> None:
        datos = respuesta_con_tiempos([
            fila("segunda", "61005"), fila("primera", "1234"), fila("tercera", 3_600_000),
        ])
        self.assertEqual(letras.lineas_con_tiempo(datos),
                         [(1234, "primera"), (61005, "segunda"), (3_600_000, "tercera")])

    def test_salta_las_lineas_rotas_sin_perder_las_buenas(self) -> None:
        datos = respuesta_con_tiempos([
            fila("buena", "500"), fila("sin tiempo", None), fila("tiempo raro", "1.5"),
            fila("negativa", -3), {"lyricLine": "sin cue"}, None,
            fila("con\nsalto  dentro", "900"),
        ])
        self.assertEqual(letras.lineas_con_tiempo(datos), [(500, "buena"), (900, "con salto dentro")])

    def test_sin_texto_en_ninguna_linea_no_hay_letra(self) -> None:
        self.assertIsNone(letras.lineas_con_tiempo(respuesta_con_tiempos([fila("", "0"), fila(" ", "9")])))

    def test_fuente_de_la_sincronizada(self) -> None:
        self.assertEqual(letras.fuente_con_tiempo(TIEMPOS), "Fuente: LyricFind")
        con_runs = respuesta_con_tiempos([], {"runs": [{"text": "Fuente: "}, {"text": "Musixmatch"}]})
        self.assertEqual(letras.fuente_con_tiempo(con_runs), "Fuente: Musixmatch")
        self.assertEqual(letras.fuente_con_tiempo({}), "")

    def test_lrc_con_centesimas(self) -> None:
        lrc = letras.a_lrc([(0, "a"), (1234, "b"), (61_005, "c"), (5_999_990, "d"), (8100, "")])
        self.assertEqual(lrc, "[00:00.00]a\n[00:01.23]b\n[01:01.00]c\n[99:59.99]d\n[00:08.10]")
        self.assertEqual(letras.a_lrc([]), "")

    def test_letra_plana_y_su_fuente(self) -> None:
        texto = "Voy a reir\r\nVoy a bailar\n\nVivir mi vida\n"
        self.assertEqual(letras.letra_simple(respuesta_plana(texto)),
                         ("Voy a reir\nVoy a bailar\n\nVivir mi vida", "Fuente: Musixmatch"))

    def test_letra_plana_sin_pie_ni_fuente(self) -> None:
        self.assertEqual(letras.letra_simple(respuesta_plana("hola", None)), ("hola", ""))

    def test_letra_plana_en_varios_trozos(self) -> None:
        datos = respuesta_plana("")
        estante = datos["contents"]["sectionListRenderer"]["contents"][0]["musicDescriptionShelfRenderer"]
        estante["description"] = {"runs": [{"text": "primera\n"}, {"text": "segunda"}]}
        self.assertEqual(letras.letra_simple(datos), ("primera\nsegunda", "Fuente: Musixmatch"))

    def test_letra_plana_vacia_no_es_letra(self) -> None:
        self.assertIsNone(letras.letra_simple(respuesta_plana("  \n ")))

    def test_formas_rotas_dan_none_sin_lanzar(self) -> None:
        for datos in FORMAS_ROTAS:
            with self.subTest(datos=datos):
                self.assertIsNone(letras.browse_id(datos))
                self.assertIsNone(letras.lineas_con_tiempo(datos))
                self.assertIsNone(letras.letra_simple(datos))
                self.assertIsInstance(letras.fuente_con_tiempo(datos), str)


class LetraTests(unittest.TestCase):
    def _pedir(self, *respuestas: Any) -> tuple[dict[str, Any], MagicMock]:
        with patch.object(letras, "urlopen", side_effect=list(respuestas)) as falso:
            resultado: dict[str, Any] = letras.letra(VIDEO, timeout=3)
        return resultado, falso

    def test_con_tiempos(self) -> None:
        resultado, falso = self._pedir(_Respuesta(CON_LETRA), _Respuesta(TIEMPOS))
        self.assertEqual(resultado, {
            "ok": True,
            "lrc": "[00:01.23]Voy a reir, voy a bailar\n[00:04.00]Vivir mi vida, la la la la\n[00:08.10]",
            "texto": "Voy a reir, voy a bailar\nVivir mi vida, la la la la\n",
            "fuente": "Fuente: LyricFind",
        })
        self.assertEqual(falso.call_count, 2)
        siguiente, movil = falso.call_args_list
        peticion = siguiente.args[0]
        self.assertEqual(peticion.full_url, "https://music.youtube.com/youtubei/v1/next?prettyPrint=false")
        self.assertEqual(peticion.get_method(), "POST")
        self.assertEqual(peticion.get_header("Cookie"), "SOCS=CAI")
        self.assertEqual(peticion.get_header("Origin"), "https://music.youtube.com")
        self.assertEqual(peticion.get_header("Content-type"), "application/json")
        self.assertEqual(siguiente.kwargs["timeout"], 3)
        cuerpo = _cuerpo(siguiente)
        self.assertEqual(cuerpo["videoId"], VIDEO)
        self.assertTrue(cuerpo["isAudioOnly"])
        self.assertEqual(cuerpo["context"]["client"]["clientName"], "WEB_REMIX")
        self.assertRegex(cuerpo["context"]["client"]["clientVersion"], r"^1\.20\d{6}\.01\.00$")
        self.assertIn("/browse?", movil.args[0].full_url)
        self.assertEqual(_cuerpo(movil)["browseId"], LETRA)
        self.assertEqual(_cuerpo(movil)["context"]["client"]["clientName"], "ANDROID_MUSIC")
        # La misma visita que abrio «next».
        self.assertEqual(movil.args[0].get_header("X-goog-visitor-id"), "Cgt2aXNpdGFudGU%3D")

    def test_sin_tiempos_cae_a_la_letra_plana(self) -> None:
        resultado, falso = self._pedir(
            _Respuesta(CON_LETRA), _Respuesta({"contents": {}}), _Respuesta(respuesta_plana("hola\nadios")),
        )
        self.assertEqual(resultado, {"ok": True, "lrc": "", "texto": "hola\nadios",
                                     "fuente": "Fuente: Musixmatch"})
        self.assertEqual(falso.call_count, 3)
        web = _cuerpo(falso.call_args_list[2])
        self.assertEqual(web["context"]["client"]["clientName"], "WEB_REMIX")
        self.assertEqual(web["browseId"], LETRA)

    def test_si_el_movil_ya_trae_la_plana_no_pregunta_a_la_web(self) -> None:
        resultado, falso = self._pedir(_Respuesta(CON_LETRA), _Respuesta(respuesta_plana("hola")))
        self.assertEqual(resultado["texto"], "hola")
        self.assertEqual(falso.call_count, 2)

    def test_sin_pestana_de_letra(self) -> None:
        resultado, falso = self._pedir(_Respuesta(SIN_LETRA))
        self.assertEqual(resultado, {"ok": True, "lrc": "", "texto": "", "fuente": ""})
        self.assertEqual(falso.call_count, 1)

    def test_con_pestana_pero_sin_letra_en_ningun_cliente(self) -> None:
        resultado, _ = self._pedir(_Respuesta(CON_LETRA), _Respuesta({}), _Respuesta({}))
        self.assertEqual(resultado, {"ok": True, "lrc": "", "texto": "", "fuente": ""})

    def test_error_de_red(self) -> None:
        resultado, falso = self._pedir(URLError("sin conexion"))
        self.assertFalse(resultado["ok"])
        self.assertIn("sin conexion", resultado["error"])
        self.assertEqual(falso.call_count, 1)

    def test_respuesta_que_no_es_json(self) -> None:
        resultado, _ = self._pedir(_Respuesta(b"<html>consentimiento</html>"))
        self.assertFalse(resultado["ok"])

    def test_respuesta_comprimida(self) -> None:
        resultado, _ = self._pedir(_Respuesta(CON_LETRA, comprimir=True), _Respuesta(TIEMPOS, comprimir=True))
        self.assertTrue(resultado["lrc"].startswith("[00:01.23]"))

    def test_si_falla_el_movil_aun_queda_la_plana(self) -> None:
        error = HTTPError("https://music.youtube.com", 400, "Bad Request", Message(), None)
        resultado, _ = self._pedir(_Respuesta(CON_LETRA), error, _Respuesta(respuesta_plana("hola")))
        self.assertEqual(resultado, {"ok": True, "lrc": "", "texto": "hola", "fuente": "Fuente: Musixmatch"})

    def test_si_falla_el_movil_y_la_web_no_trae_nada_no_se_da_por_vacia(self) -> None:
        """Sin respuesta del cliente movil no se sabe si la cancion tiene letra."""
        error = HTTPError("https://music.youtube.com", 400, "Bad Request", Message(), None)
        resultado, _ = self._pedir(_Respuesta(CON_LETRA), error, _Respuesta({}))
        self.assertFalse(resultado["ok"])
        self.assertIn("400", resultado["error"])

    def test_id_no_valido_no_sale_a_la_red(self) -> None:
        for video in ("", "corto", "dQw4w9WgXcQQ", "dQw4w9 gXcQ", "https://youtu.be/dQw4w9WgXcQ", None):
            with self.subTest(video=video), patch.object(letras, "urlopen") as falso:
                resultado = letras.letra(video)
                self.assertFalse(resultado["ok"])
                falso.assert_not_called()

    def test_nunca_lanza(self) -> None:
        with patch.object(letras, "urlopen", side_effect=RuntimeError("inesperado")):
            resultado = letras.letra(VIDEO)
        self.assertEqual(resultado, {"ok": False, "error": "RuntimeError: inesperado"})


class PuenteTests(unittest.TestCase):
    """El puente devuelve JSON pase lo que pase: cruza a Kotlin."""

    puente: ModuleType

    @classmethod
    def setUpClass(cls) -> None:
        cls.puente = _cargar("puente_letras", "puente.py")

    def test_devuelve_la_letra_en_json(self) -> None:
        falso = SimpleNamespace(letra=lambda video: {"ok": True, "lrc": "", "texto": video, "fuente": ""})
        with patch.dict(sys.modules, {"letras_ytm": falso}):
            datos = json.loads(self.puente.letra_youtube(VIDEO))
        self.assertEqual(datos, {"ok": True, "lrc": "", "texto": VIDEO, "fuente": ""})

    def test_sin_el_modulo_responde_con_el_error(self) -> None:
        with patch.dict(sys.modules, {"letras_ytm": None}):
            datos = json.loads(self.puente.letra_youtube(VIDEO))
        self.assertFalse(datos["ok"])


if __name__ == "__main__":
    unittest.main()
