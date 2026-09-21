import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar
from unittest.mock import Mock, patch

from descargador.application import (
    DownloadVideo,
    ImportPlaylist,
    InspectVideo,
    SearchVideos,
    StreamVideo,
)
from descargador.cli import (
    _alternar_normalizar,
    acciones_ajustes,
    describir_ajustes,
    formato_tamano,
    formato_tiempo,
    leer_lista,
    main,
)
from descargador.domain import (
    FORMATOS_SIN_NORMALIZAR,
    FUENTES_DE_LISTAS,
    GUIONES,
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    DownloadRequest,
    DownloadResult,
    PlaybackSource,
    Playlist,
    SearchQuery,
    VideoInfo,
    parse_section,
    parse_timestamp,
)
from descargador.infrastructure import (
    INTENTOS_TRANSITORIOS,
    PREFIJOS_BUSQUEDA,
    YtDlpDownloader,
    buscar_portada,
    escribir_etiquetas,
    incrusta_caratula,
    incrustar_portada,
    mensaje_claro,
    nombre_con_etiquetas,
    partes_del_nombre,
)


class DownloadTests(unittest.TestCase):
    def test_rejects_invalid_urls_before_adapter(self):
        invalidas = ("", "hola", "file:///video.mp4", "ftp://example.com/a",
                     "https://", "https://a:bad/v", "https://a/a b")
        for url in invalidas:
            with self.subTest(url=url):
                adapter = Mock()
                with self.assertRaises(DownloadError):
                    DownloadVideo(adapter).execute(url, Path("out"))
                adapter.download.assert_not_called()

    def test_normalizes_url_and_passes_destination(self):
        adapter = Mock()
        adapter.download.return_value = DownloadResult((Path("out/video.mp4"),))
        result = DownloadVideo(adapter).execute("  https://example.com/v?a=1&b=2  ", Path("out"))
        esperada = DownloadRequest("https://example.com/v?a=1&b=2", Path("out"))
        adapter.download.assert_called_once_with(esperada)
        self.assertEqual(result.files, (Path("out/video.mp4"),))

    def test_cli_invalid_url_returns_failure_without_traceback(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            code = main(["incorrecta"])
        self.assertEqual(code, 1)
        self.assertIn("URL válida", output.getvalue())
        self.assertNotIn("Traceback", output.getvalue())

    def test_inspect_use_case_delegates_without_downloading(self):
        adapter = Mock()
        adapter.inspect.return_value = VideoInfo("Un video")
        info = InspectVideo(adapter).execute("https://example.com/v", Path("out"))
        self.assertEqual(info.title, "Un video")
        adapter.download.assert_not_called()


class OptionTests(unittest.TestCase):
    def test_rejects_invalid_options(self):
        casos = [{"quality": 0}, {"quality": -720}, {"audio_format": "wma"}, {"audio_bitrate": "alto"}]
        for caso in casos:
            with self.subTest(**caso), self.assertRaises(DownloadError):
                DownloadOptions(**caso)

    def test_rejects_inverted_section(self):
        with self.assertRaises(DownloadError):
            DownloadOptions(section=(120.0, 30.0))

    def test_parses_timestamps(self):
        self.assertEqual(parse_timestamp("90"), 90)
        self.assertEqual(parse_timestamp("1:30"), 90)
        self.assertEqual(parse_timestamp("01:02:03"), 3723)

    def test_parses_sections_with_open_ends(self):
        self.assertEqual(parse_section("00:30-02:15"), (30.0, 135.0))
        self.assertEqual(parse_section("-1:00"), (0.0, 60.0))
        self.assertEqual(parse_section("1:00-")[0], 60.0)

    def test_rejects_malformed_sections(self):
        for texto in ("", "0:30", "2:15-0:30", "a-b", "1:2:3:4-5"):
            with self.subTest(texto=texto), self.assertRaises(DownloadError):
                parse_section(texto)

    def test_progress_percent(self):
        self.assertAlmostEqual(DownloadProgress("downloading", downloaded=50, total=200).percent, 25.0)
        self.assertIsNone(DownloadProgress("downloading", downloaded=50).percent)


class AdapterTests(unittest.TestCase):
    """Comprueban la traducción a opciones de yt-dlp sin tocar la red."""

    def test_filter_rejects_playlists_and_live(self):
        self.assertIsNotNone(YtDlpDownloader._single_video({"_type": "playlist"}))
        self.assertIsNotNone(YtDlpDownloader._single_video({"is_live": True}))
        self.assertIsNone(YtDlpDownloader._single_video({"title": "normal"}))

    def test_thumbnail_is_skipped_when_ffprobe_is_missing(self):
        """Sin ffprobe la carátula se omite en video, pero nunca en audio."""
        sin_probe = [p["key"] for p in YtDlpDownloader._postprocesadores(DownloadOptions(), caratula=False)]
        self.assertNotIn("EmbedThumbnail", sin_probe)
        self.assertIn("FFmpegMetadata", sin_probe)
        with patch("descargador.infrastructure.shutil.which", return_value=None):
            self.assertTrue(incrusta_caratula(audio_only=True))
            self.assertFalse(incrusta_caratula(audio_only=False))

    def test_format_selection(self):
        self.assertEqual(YtDlpDownloader._seleccion_formato(DownloadOptions()), "bv*+ba/b")
        self.assertEqual(YtDlpDownloader._seleccion_formato(DownloadOptions(audio_only=True)), "ba/b")
        # El tope va con «?»: un formato que no diga su altura no se descarta.
        self.assertIn("height<=?720", YtDlpDownloader._seleccion_formato(DownloadOptions(quality=720)))

    def test_mp4_preference_asks_for_h264_first(self):
        """En el movil el contenedor y el codec deciden si el video se reproduce."""
        seleccion = YtDlpDownloader._seleccion_formato(DownloadOptions(prefer_mp4=True, quality=720))
        self.assertTrue(seleccion.startswith("bv*[vcodec^=avc1][height<=?720]"))
        # Debe conservar alternativas: si no hay H.264, algo se descarga igual.
        self.assertIn("/bv*[height<=?720]+ba/", seleccion)
        self.assertEqual(seleccion.count("height<=?720"), 5)

    def test_audio_extracted_before_embedding_thumbnail(self):
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(DownloadOptions(audio_only=True))]
        self.assertLess(claves.index("FFmpegExtractAudio"), claves.index("EmbedThumbnail"))
        self.assertIn("FFmpegMetadata", claves)

    def test_subtitles_only_embedded_for_video(self):
        video = [p["key"] for p in YtDlpDownloader._postprocesadores(DownloadOptions(subtitles=("es",)))]
        solo_audio = DownloadOptions(subtitles=("es",), audio_only=True)
        audio = [p["key"] for p in YtDlpDownloader._postprocesadores(solo_audio)]
        self.assertIn("FFmpegEmbedSubtitle", video)
        self.assertNotIn("FFmpegEmbedSubtitle", audio)

    def test_sponsorblock_needs_both_postprocessors(self):
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(DownloadOptions(skip_sponsors=True))]
        self.assertLess(claves.index("SponsorBlock"), claves.index("ModifyChapters"))

    def test_sin_normalizar_no_se_pasan_argumentos_a_ffmpeg(self):
        self.assertEqual(YtDlpDownloader._argumentos_postproceso(DownloadOptions()), {})

    def test_el_filtro_de_volumen_va_solo_a_la_conversion_de_audio(self):
        # Con la clave «default» el filtro llegaría también a los pasos que
        # copian el flujo (metadatos, carátula) y ffmpeg abortaría.
        opciones = DownloadOptions(audio_only=True, normalize=True)
        argumentos = YtDlpDownloader._argumentos_postproceso(opciones)

        conLoudnorm = [k for k, v in argumentos.items() if any("loudnorm" in a for a in v)]
        self.assertEqual(conLoudnorm, ["extractaudio+ffmpeg"])
        self.assertEqual(argumentos["extractaudio+ffmpeg"][0], "-af")

    def test_yt_dlp_entrega_el_filtro_donde_lo_esperamos(self):
        """Comprueba el acuerdo con yt-dlp, no nuestro diccionario.

        Si en una versión futura cambia cómo resuelve las claves, esto avisa
        antes de que el filtro se cuele en un paso que copia el flujo.
        """
        from yt_dlp.utils._utils import _configuration_args

        argumentos = YtDlpDownloader._argumentos_postproceso(
            DownloadOptions(audio_only=True, normalize=True))
        # Las mismas claves que arma yt_dlp al escribir el archivo de salida.
        salida = ["_o1", "_o", ""]

        def recibe(postprocesador):
            return _configuration_args(postprocesador, argumentos, "ffmpeg", salida)

        self.assertIn("loudnorm", " ".join(recibe("ExtractAudio")))
        self.assertEqual(recibe("Metadata"), [])
        self.assertEqual(recibe("EmbedThumbnail"), [])


class FragmentoTests(unittest.TestCase):
    """Acotar un trozo es de lo más fácil de escribir mal."""

    def test_un_punto_en_vez_de_dos_puntos_no_pasa_en_silencio(self):
        # Regresión: «0.30-2.15» se leía como 0,3 y 2,15 segundos, así que
        # recortaba un trozo de dos segundos sin avisar. Parecía que la
        # función no servía, y en realidad hacía lo que se le pedía.
        for texto in ("0.30-2.15", "1,30-2,15"):
            with self.subTest(texto=texto), self.assertRaises(DownloadError) as caso:
                parse_section(texto)
            self.assertIn("dos puntos", str(caso.exception))

    def test_el_guion_largo_del_teclado_tambien_vale(self):
        # Muchos teclados de móvil cambian solos el guion normal por uno largo.
        for guion in GUIONES:
            with self.subTest(guion=guion):
                self.assertEqual(parse_section(f"00:30{guion}02:15"), (30.0, 135.0))

    def test_los_extremos_se_pueden_dejar_sueltos(self):
        self.assertEqual(parse_section("1:30-")[0], 90.0)
        self.assertEqual(parse_section("-2:00"), (0.0, 120.0))

    def test_sigue_valiendo_lo_de_siempre(self):
        self.assertEqual(parse_section("00:30-02:15"), (30.0, 135.0))
        self.assertEqual(parse_section("30-60"), (30.0, 60.0))
        self.assertEqual(parse_section("00:30 - 02:15"), (30.0, 135.0))


class MensajesTests(unittest.TestCase):
    """Lo que escupe el motor está en inglés y no dice qué hacer."""

    def test_una_pista_protegida_se_explica_y_se_ofrece_salida(self):
        # Pasa con las subidas oficiales de los sellos en SoundCloud.
        mensaje = mensaje_claro(Exception("ERROR: [soundcloud] 19166: This video is DRM protected"))
        self.assertIn("protegida", mensaje)
        self.assertIn("YouTube", mensaje)
        self.assertNotIn("DRM protected", mensaje)

    def test_los_fallos_conocidos_se_cuentan_en_castellano(self):
        casos = {
            "ERROR: [youtube] abc: Video unavailable": "disponible",
            "ERROR: [youtube] abc: Private video": "privado",
            "ERROR: Requested format is not available": "formato",
            "OSError: No space left on device": "espacio",
        }
        for crudo, esperado in casos.items():
            with self.subTest(crudo=crudo):
                self.assertIn(esperado, mensaje_claro(Exception(crudo)))

    def test_un_fallo_desconocido_se_cuenta_tal_cual(self):
        # Inventarse una explicación para algo que no se conoce sería peor:
        # el texto original al menos deja rastro para diagnosticarlo.
        mensaje = mensaje_claro(Exception("algo que nunca habiamos visto"))
        self.assertIn("algo que nunca habiamos visto", mensaje)

    def test_una_pista_protegida_no_se_reintenta(self):
        # Repetirlo tres veces no va a quitarle el candado.
        motor = YtDlpDownloader()
        fallo = Mock(side_effect=DownloadError("Esa pista está protegida por su sello"))
        with patch.object(YtDlpDownloader, "_intentar", fallo), self.assertRaises(DownloadError):
            motor.download(DownloadRequest("https://example.com/v", Path("out")))
        self.assertEqual(fallo.call_count, 1)


class PortadaOficialTests(unittest.TestCase):
    """La carátula del disco en vez del fotograma del vídeo."""

    class _RespuestaFalsa:
        def __init__(self, cuerpo):
            self._cuerpo = cuerpo

        def read(self):
            return self._cuerpo

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    def test_se_pide_la_grande_y_no_la_miniatura(self):
        # El catálogo devuelve una de 100 píxeles; la misma existe en 1200 sin
        # más que cambiarle la medida a la dirección.
        cuerpo = b'{"results": [{"artworkUrl100": "https://x/a/100x100bb.jpg"}]}'
        with patch("descargador.infrastructure.urlopen",
                   return_value=self._RespuestaFalsa(cuerpo)):
            direccion = buscar_portada("Un Grupo", "Un Tema")
        self.assertEqual(direccion, "https://x/a/1200x1200bb.jpg")

    def test_sin_resultados_no_se_inventa_una_portada(self):
        with patch("descargador.infrastructure.urlopen",
                   return_value=self._RespuestaFalsa(b'{"results": []}')):
            self.assertIsNone(buscar_portada("Nadie", "Nada"))

    def test_sin_artista_ni_titulo_ni_se_pregunta(self):
        with patch("descargador.infrastructure.urlopen") as red:
            self.assertIsNone(buscar_portada("", "   "))
        red.assert_not_called()

    def test_un_fallo_de_red_deja_la_descarga_en_pie(self):
        # La canción ya se bajó bien: quedarse sin la portada buena no puede
        # convertirse en un error.
        with patch("descargador.infrastructure.urlopen", side_effect=OSError("sin red")):
            self.assertIsNone(buscar_portada("Un Grupo", "Un Tema"))

    def test_la_portada_vieja_se_queda_fuera(self):
        """Comprueba la orden de FFmpeg, no a FFmpeg."""
        with tempfile.TemporaryDirectory() as carpeta:
            audio = Path(carpeta) / "tema.mp3"
            audio.write_bytes(b"audio")
            imagen = Path(carpeta) / "arte.jpg"
            imagen.write_bytes(b"imagen")
            destino = Path(carpeta) / "sale.mp3"

            def fingir(orden, **_):
                destino.write_bytes(b"audio")
                return subprocess.CompletedProcess(orden, 0, "", "")

            with (
                patch("descargador.infrastructure._preparar_ffmpeg", return_value="ffmpeg"),
                patch("descargador.infrastructure.subprocess.run", side_effect=fingir) as corrio,
            ):
                incrustar_portada(audio, destino, imagen)

            orden = corrio.call_args.args[0]
            # Del original se coge solo el sonido: así la carátula anterior no
            # sobrevive y no quedan dos dentro del mismo archivo.
            self.assertIn("0:a", orden)
            self.assertIn("1:v", orden)
            self.assertIn("attached_pic", orden)
            self.assertEqual(orden[orden.index("-c") + 1], "copy")

    def test_sin_imagen_se_dice_claro(self):
        with tempfile.TemporaryDirectory() as carpeta:
            audio = Path(carpeta) / "tema.mp3"
            audio.write_bytes(b"audio")
            with self.assertRaises(DownloadError):
                incrustar_portada(audio, Path(carpeta) / "sale.mp3", Path("no-existe.jpg"))

    def test_el_artista_y_el_tema_salen_del_nombre_del_archivo(self):
        self.assertEqual(
            partes_del_nombre("Soda Stereo - De Musica Ligera [T_Fk].mp3"),
            ("Soda Stereo", "De Musica Ligera"))
        # Sin guion no hay artista, pero el tema sigue sirviendo para buscar.
        self.assertEqual(partes_del_nombre("Un tema suelto [x].mp3"), ("", "Un tema suelto"))
        # El guion que parte es el primero: el tema puede llevar los suyos.
        self.assertEqual(
            partes_del_nombre("Artista - Tema - con guion [id].mp3"),
            ("Artista", "Tema - con guion"))


class FuentesTests(unittest.TestCase):
    """De dónde se busca. El adaptador no toca la red en estas pruebas."""

    def test_por_defecto_se_busca_en_youtube(self):
        self.assertEqual(SearchQuery("algo").source, "youtube")

    def test_se_rechaza_una_fuente_que_no_existe(self):
        for fuente in ("tidal", "spotify", "", "YouTube"):
            with self.subTest(fuente=fuente), self.assertRaises(DownloadError):
                SearchQuery("algo", source=fuente)

    def test_cada_fuente_usa_el_prefijo_que_le_toca(self):
        # Sin esto, buscar en SoundCloud acabaría preguntándole a YouTube.
        self.assertEqual(PREFIJOS_BUSQUEDA["youtube"], "ytsearch")
        self.assertEqual(PREFIJOS_BUSQUEDA["soundcloud"], "scsearch")
        # El Archive no tiene buscador en el motor y va por su propia API.
        self.assertNotIn("archive", PREFIJOS_BUSQUEDA)

    def test_el_caso_de_uso_traslada_la_fuente_sin_interpretarla(self):
        adaptador = Mock()
        adaptador.search.return_value = ()
        SearchVideos(adaptador).execute("algo", 5, "soundcloud")
        adaptador.search.assert_called_once_with(SearchQuery("algo", 5, "soundcloud"))

    def test_el_archive_es_el_unico_que_devuelve_grabaciones_enteras(self):
        # Quien lo use tiene que tratar cada resultado como una lista.
        self.assertEqual(FUENTES_DE_LISTAS, ("archive",))

    def test_la_direccion_de_soundcloud_es_la_de_la_pista_y_no_la_de_su_api(self):
        # Regresión: SoundCloud pone en «url» una dirección de su API que no
        # sirve para volver a la pista; la buena viene en «webpage_url».
        info = YtDlpDownloader._resultado({
            "id": "214693515",
            "title": "Una pista",
            "url": "https://api.soundcloud.com/tracks/soundcloud%3Atracks%3A214693515",
            "webpage_url": "https://soundcloud.com/grupo/una-pista",
        })
        self.assertEqual(info.url, "https://soundcloud.com/grupo/una-pista")

    def test_youtube_sigue_usando_su_direccion_de_siempre(self):
        # Ahí «webpage_url» llega vacío, así que no puede ganarle a «url».
        info = YtDlpDownloader._resultado({
            "id": "abc123",
            "title": "Un video",
            "url": "https://www.youtube.com/watch?v=abc123",
            "webpage_url": None,
        })
        self.assertEqual(info.url, "https://www.youtube.com/watch?v=abc123")

    def test_la_consulta_al_archive_se_ciñe_al_titulo_y_al_interprete(self):
        """Comprueba la consulta, no la red: se intercepta la llamada."""
        pedido = {}

        class RespuestaFalsa:
            def read(self):
                return b'{"response": {"docs": []}}'

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        def espiar(peticion, timeout=None):
            pedido["url"] = peticion.full_url
            return RespuestaFalsa()

        with patch("descargador.infrastructure.urlopen", side_effect=espiar):
            YtDlpDownloader._buscar_en_archive(SearchQuery("grateful dead", source="archive"))

        # A campo abierto salían conciertos de otros grupos.
        self.assertIn("title%3A", pedido["url"])
        self.assertIn("creator%3A", pedido["url"])
        self.assertIn("format%3AFLAC", pedido["url"])

    def test_lo_que_lucene_usa_como_operador_no_cambia_la_consulta(self):
        pedido = {}

        class RespuestaFalsa:
            def read(self):
                return b'{"response": {"docs": []}}'

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        def espiar(peticion, timeout=None):
            pedido["url"] = peticion.full_url
            return RespuestaFalsa()

        with patch("descargador.infrastructure.urlopen", side_effect=espiar):
            YtDlpDownloader._buscar_en_archive(
                SearchQuery('AC/DC "live" -1977', source="archive"))

        # Ni comillas, ni barras, ni signos que Lucene entienda como ordenes.
        self.assertNotIn("%22", pedido["url"])
        self.assertNotIn("%2F", pedido["url"])


class RedAndroidTests(unittest.TestCase):
    """El manejador que saca las peticiones por la red del sistema.

    Vive en el puente del móvil, no en el núcleo: es lo único del proyecto que
    depende de Android. Se carga por su ruta y no por sys.path para no colar
    sin querer la copia del núcleo que Gradle sincroniza al lado.
    """

    modulo: ClassVar = None

    @classmethod
    def setUpClass(cls):
        import importlib.util

        ruta = Path("movil/android/app/src/main/python/red_android.py")
        spec = importlib.util.spec_from_file_location("red_android_prueba", ruta)
        assert spec and spec.loader
        cls.modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.modulo)

    def tearDown(self):
        self.modulo.desactivar()

    def _peticion(self, url="https://ejemplo.com/v"):
        from yt_dlp.networking import Request

        return Request(url)

    def _manejador(self):
        # yt-dlp le pasa su propio registro al construirlo; aquí basta uno mudo.
        return self.modulo.RedAndroidRH(logger=Mock())

    def test_apagado_se_aparta_para_que_siga_el_de_siempre(self):
        from yt_dlp.networking.exceptions import UnsupportedRequest

        manejador = self._manejador()
        with self.assertRaises(UnsupportedRequest):
            manejador.validate(self._peticion())

    def test_encendido_devuelve_lo_que_dio_la_red_del_sistema(self):
        recibido = {}

        def backend(url, metodo, cabeceras, datos):
            recibido.update(url=url, metodo=metodo)
            return 200, url, {"Content-Type": "text/html"}, b"<html>hola</html>"

        self.modulo.activar(backend)
        respuesta = self._manejador().send(self._peticion())

        self.assertEqual(recibido["url"], "https://ejemplo.com/v")
        self.assertEqual(recibido["metodo"], "GET")
        self.assertEqual(respuesta.status, 200)
        self.assertEqual(respuesta.read(), b"<html>hola</html>")

    def test_un_error_del_servidor_se_cuenta_como_error(self):
        from yt_dlp.networking.exceptions import HTTPError

        def backend(url, metodo, cabeceras, datos):
            return 404, url, {}, b"no esta"

        self.modulo.activar(backend)
        with self.assertRaises(HTTPError) as caso:
            self._manejador().send(self._peticion())
        self.assertEqual(caso.exception.status, 404)

    def test_si_la_red_del_sistema_falla_se_traduce_a_error_de_transporte(self):
        from yt_dlp.networking.exceptions import TransportError

        def backend(url, metodo, cabeceras, datos):
            raise OSError("sin red")

        self.modulo.activar(backend)
        with self.assertRaises(TransportError):
            self._manejador().send(self._peticion())

    def test_encender_y_apagar_deja_el_estado_donde_estaba(self):
        self.assertFalse(self.modulo.activo())
        self.modulo.activar(lambda *_: (200, "", {}, b""))
        self.assertTrue(self.modulo.activo())
        self.modulo.desactivar()
        self.assertFalse(self.modulo.activo())


class EditarEtiquetasTests(unittest.TestCase):
    def test_el_nombre_recoge_artista_y_titulo_sin_perder_el_identificador(self):
        # El identificador entre corchetes es con lo que se reconoce la pista
        # para no volver a descargarla: renombrar no puede llevárselo.
        self.assertEqual(
            nombre_con_etiquetas(
                "Soda Stereo - De Musica Ligera (Official) [T_Fk].mp3",
                titulo="De Música Ligera", artista="Soda Stereo"),
            "Soda Stereo - De Música Ligera [T_Fk].mp3")

    def test_sin_artista_no_queda_un_guion_suelto(self):
        self.assertEqual(
            nombre_con_etiquetas("Video by alguien [Dc9a].mp4", titulo="Un título", artista=""),
            "Un título [Dc9a].mp4")

    def test_los_caracteres_que_android_no_admite_se_cambian(self):
        self.assertEqual(
            nombre_con_etiquetas("Algo [id].mp3", titulo="Con / barras : raras", artista="AC/DC"),
            "AC DC - Con barras raras [id].mp3")

    def test_unas_etiquetas_vacias_dejan_el_nombre_como_estaba(self):
        self.assertEqual(
            nombre_con_etiquetas("Lo que sea [id].mp3", titulo="   ", artista="  "),
            "Lo que sea [id].mp3")

    def test_se_reescribe_la_cabecera_sin_tocar_el_sonido(self):
        """Comprueba la orden que se le da a FFmpeg, no a FFmpeg."""
        with tempfile.TemporaryDirectory() as carpeta:
            origen = Path(carpeta) / "entra.mp3"
            origen.write_bytes(b"audio")
            destino = Path(carpeta) / "sale.mp3"

            def fingir(orden, **_):
                destino.write_bytes(b"audio")
                return subprocess.CompletedProcess(orden, 0, "", "")

            with (
                patch("descargador.infrastructure._preparar_ffmpeg", return_value="ffmpeg"),
                patch("descargador.infrastructure.subprocess.run", side_effect=fingir) as corrio,
            ):
                escribir_etiquetas(origen, destino, titulo="Tema", artista="Artista")

            orden = corrio.call_args.args[0]
            # «-c copy» es lo que evita recomprimir, y «-map 0» conserva la
            # carátula, que en un MP3 viaja como un flujo de vídeo.
            self.assertIn("-c", orden)
            self.assertEqual(orden[orden.index("-c") + 1], "copy")
            self.assertIn("-map", orden)
            self.assertIn("title=Tema", orden)
            self.assertIn("artist=Artista", orden)

    def test_si_ffmpeg_falla_se_avisa_y_no_se_deja_a_medias(self):
        with tempfile.TemporaryDirectory() as carpeta:
            origen = Path(carpeta) / "entra.mp3"
            origen.write_bytes(b"audio")
            fallo = subprocess.CompletedProcess([], 1, "", "Invalid data found")

            with (
                patch("descargador.infrastructure._preparar_ffmpeg", return_value="ffmpeg"),
                patch("descargador.infrastructure.subprocess.run", return_value=fallo),
                self.assertRaises(DownloadError) as caso,
            ):
                escribir_etiquetas(origen, Path(carpeta) / "sale.mp3",
                                   titulo="T", artista="A")

            self.assertIn("Invalid data found", str(caso.exception))

    def test_un_archivo_que_no_esta_se_dice_claro(self):
        with self.assertRaises(DownloadError):
            escribir_etiquetas(Path("no-existe.mp3"), Path("sale.mp3"), titulo="T", artista="A")


class FormatoVerticalTests(unittest.TestCase):
    """El selector tiene que servir también para vídeo vertical y sin metadatos.

    Se le pregunta al selector de yt-dlp, no a nuestra cadena de texto: lo que
    importa es qué formato acaba eligiendo. No toca la red; los formatos son
    los que devuelve un reel, copiados a mano.
    """

    #: Ni un solo H.264, el vídeo separado en VP9 y más alto que ancho, y MP4
    #: sueltos que no dicen ni su resolución ni su códec.
    FORMATOS: ClassVar[list[dict]] = [
        {"format_id": "dash-a", "ext": "m4a", "vcodec": "none",
         "acodec": "mp4a.40.5", "abr": 72},
        {"format_id": "1", "ext": "mp4", "url": "https://x/1"},
        {"format_id": "3", "ext": "mp4", "url": "https://x/3"},
        {"format_id": "dash-v720", "ext": "mp4", "vcodec": "vp09.00.31.08",
         "acodec": "none", "width": 720, "height": 1280, "vbr": 1489},
        {"format_id": "dash-v1080", "ext": "mp4", "vcodec": "vp09.00.40.08",
         "acodec": "none", "width": 1080, "height": 1920, "vbr": 2677},
    ]

    @classmethod
    def _elegidos(cls, selector: str) -> list[str]:
        from yt_dlp import YoutubeDL

        with YoutubeDL({"quiet": True, "no_warnings": True, "simulate": True}) as motor:
            elegir = motor.build_format_selector(selector)
            return [
                f["format_id"]
                for f in elegir({"formats": cls.FORMATOS, "incomplete_formats": False})
            ]

    def test_un_video_vertical_sin_metadatos_si_se_puede_descargar(self):
        # Regresión: con el tope estricto no quedaba ninguna rama viable y
        # yt-dlp abortaba con «Requested format is not available».
        opciones = DownloadOptions(quality=1080, prefer_mp4=True)
        self.assertTrue(self._elegidos(YtDlpDownloader._seleccion_formato(opciones)))

    def test_el_tope_estricto_era_el_que_no_dejaba_nada(self):
        # Demuestra la causa: el mismo selector sin el «?» y sin respaldo no
        # encuentra nada entre estos formatos.
        estricto = ("bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]/"
                    "bv*[ext=mp4][height<=1080]+ba[ext=m4a]/"
                    "b[ext=mp4][height<=1080]/bv*[height<=1080]+ba/b[height<=1080]")
        self.assertEqual(self._elegidos(estricto), [])

    def test_el_tope_no_descarta_lo_que_no_dice_su_altura(self):
        selector = YtDlpDownloader._seleccion_formato(
            DownloadOptions(quality=1080, prefer_mp4=True))
        self.assertIn("height<=?1080", selector)
        self.assertNotIn("height<=1080", selector)

    def test_con_tope_siempre_queda_una_rama_sin_condiciones(self):
        for opciones in (DownloadOptions(quality=720),
                         DownloadOptions(quality=720, prefer_mp4=True)):
            with self.subTest(mp4=opciones.prefer_mp4):
                self.assertTrue(
                    YtDlpDownloader._seleccion_formato(opciones).endswith("/b"))

    def test_sin_tope_la_seleccion_no_cambia(self):
        # Sin altura que limitar no hacía falta respaldo: la cadena ya acababa
        # en «b» y no se le añade uno de más.
        self.assertEqual(YtDlpDownloader._seleccion_formato(DownloadOptions()), "bv*+ba/b")

    def test_el_audio_se_elige_igual_que_siempre(self):
        self.assertEqual(
            YtDlpDownloader._seleccion_formato(DownloadOptions(audio_only=True)), "ba/b")


class EtiquetasTests(unittest.TestCase):
    """Cómo queda el título al limpiarlo.

    Se ejecutan las acciones de verdad contra el postprocesador de yt-dlp, no
    solo el diccionario: lo que importa es el resultado sobre un título real.
    """

    @staticmethod
    def _limpiar(titulo: str) -> dict:
        from yt_dlp import YoutubeDL
        from yt_dlp.postprocessor.metadataparser import MetadataParserPP

        from descargador.infrastructure import acciones_etiquetas

        info = {"title": titulo}
        with YoutubeDL({"quiet": True, "no_warnings": True}) as motor:
            MetadataParserPP(motor, acciones_etiquetas()).run(info)
        return info

    def test_separa_artista_y_tema_quitando_las_coletillas(self):
        casos = {
            "Bad Bunny - Titi Me Pregunto (Video Oficial)": ("Bad Bunny", "Titi Me Pregunto"),
            "Soda Stereo - De Musica Ligera (Official Video) [4K]": (
                "Soda Stereo", "De Musica Ligera"),
            "Grupo 5 - Motor y Motivo (Video Lyric Oficial)": ("Grupo 5", "Motor y Motivo"),
            "Shakira - Hips Dont Lie [Official Music Video] (HD)": ("Shakira", "Hips Dont Lie"),
        }
        for titulo, (artista, tema) in casos.items():
            with self.subTest(titulo=titulo):
                info = self._limpiar(titulo)
                self.assertEqual(info.get("artist"), artista)
                self.assertEqual(info.get("track"), tema)

    def test_la_coletilla_se_quita_sin_importar_las_mayusculas(self):
        # El patrón lleva «(?i)» dentro porque yt-dlp lo compila sin banderas;
        # sin eso, «(Video Oficial)» no casaba con la alternativa en minúsculas.
        for variante in ("(VIDEO OFICIAL)", "(Video Oficial)", "(video oficial)"):
            with self.subTest(variante=variante):
                info = self._limpiar(f"Artista - Tema {variante}")
                self.assertEqual(info.get("track"), "Tema")

    def test_una_palabra_suelta_no_se_confunde_con_una_coletilla(self):
        # Solo se mira dentro de paréntesis o corchetes: «Live» en mitad de un
        # título es parte del nombre, no una etiqueta del videoclip.
        info = self._limpiar("Coldplay - Live in Buenos Aires")
        self.assertEqual(info.get("track"), "Live in Buenos Aires")

    def test_un_titulo_sin_guion_se_deja_como_esta(self):
        info = self._limpiar("Un tema sin artista")
        self.assertIsNone(info.get("artist"))
        self.assertEqual(info["title"], "Un tema sin artista")

    def test_sin_la_opcion_no_se_toca_el_titulo(self):
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(DownloadOptions())]
        self.assertNotIn("MetadataParser", claves)

    def test_limpiar_corre_antes_de_descargar_para_que_el_archivo_salga_igual(self):
        pps = YtDlpDownloader._postprocesadores(DownloadOptions(clean_tags=True))
        parser = next(p for p in pps if p["key"] == "MetadataParser")
        self.assertEqual(parser["when"], "pre_process")

    def test_el_menu_ofrece_limpiar_las_etiquetas(self):
        for audio in (True, False):
            with self.subTest(audio=audio):
                nombres = [nombre for nombre, _ in acciones_ajustes(audio=audio)]
                self.assertIn("Etiquetas", nombres)


class CaratulaCuadradaTests(unittest.TestCase):
    def test_en_audio_se_recorta_la_miniatura_antes_de_incrustarla(self):
        # La de YouTube es 16:9 y como carátula de disco queda fatal.
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(
            DownloadOptions(audio_only=True), caratula=True)]
        self.assertLess(claves.index("FFmpegThumbnailsConvertor"), claves.index("EmbedThumbnail"))

        argumentos = YtDlpDownloader._argumentos_postproceso(DownloadOptions(audio_only=True))
        self.assertIn("crop", argumentos["thumbnailsconvertor+ffmpeg"][1])

    def test_en_video_la_miniatura_se_deja_como_viene(self):
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(
            DownloadOptions(), caratula=True)]
        self.assertNotIn("FFmpegThumbnailsConvertor", claves)
        self.assertNotIn("thumbnailsconvertor+ffmpeg",
                         YtDlpDownloader._argumentos_postproceso(DownloadOptions()))

    def test_sin_caratula_no_se_convierte_nada(self):
        claves = [p["key"] for p in YtDlpDownloader._postprocesadores(
            DownloadOptions(audio_only=True), caratula=False)]
        self.assertNotIn("FFmpegThumbnailsConvertor", claves)


class NormalizarTests(unittest.TestCase):
    def test_normalizar_exige_audio(self):
        with self.assertRaises(DownloadError):
            DownloadOptions(normalize=True)

    def test_normalizar_rechaza_los_formatos_que_podrian_copiarse(self):
        for formato in FORMATOS_SIN_NORMALIZAR:
            with self.subTest(formato=formato), self.assertRaises(DownloadError):
                DownloadOptions(audio_only=True, normalize=True, audio_format=formato)

    def test_normalizar_acepta_los_que_siempre_reconvierten(self):
        for formato in ("mp3", "flac", "wav", "vorbis", "alac"):
            with self.subTest(formato=formato):
                opciones = DownloadOptions(audio_only=True, normalize=True, audio_format=formato)
                self.assertTrue(opciones.normalize)

    def test_el_menu_de_audio_ofrece_igualar_el_volumen(self):
        # Si no está en el menú, la opción solo existiría para quien use
        # la línea de comandos.
        nombres = [nombre for nombre, _ in acciones_ajustes(audio=True)]
        self.assertIn("Volumen", nombres)

    def test_el_menu_no_deja_activarlo_con_un_formato_que_no_lo_admite(self):
        opciones = DownloadOptions(audio_only=True, audio_format="opus")
        with contextlib.redirect_stdout(io.StringIO()) as salida:
            resultado, _ = _alternar_normalizar(opciones, Path("."))
        self.assertFalse(resultado.normalize)
        self.assertIn("opus", salida.getvalue())

    def test_el_menu_lo_activa_y_lo_desactiva(self):
        opciones = DownloadOptions(audio_only=True, audio_format="mp3")
        activado, _ = _alternar_normalizar(opciones, Path("."))
        self.assertTrue(activado.normalize)
        apagado, _ = _alternar_normalizar(activado, Path("."))
        self.assertFalse(apagado.normalize)


class SearchTests(unittest.TestCase):
    def test_rejects_empty_or_oversized_searches(self):
        for caso in ({"text": ""}, {"text": "   "}, {"text": "algo", "limit": 0},
                     {"text": "algo", "limit": 26}):
            with self.subTest(**caso), self.assertRaises(DownloadError):
                SearchQuery(**caso)

    def test_trims_the_text(self):
        self.assertEqual(SearchQuery("  algo que buscar  ").text, "algo que buscar")

    def test_use_case_delegates_and_does_not_download(self):
        adaptador = Mock()
        adaptador.search.return_value = (VideoInfo("Uno", url="https://y/1"),)
        resultados = SearchVideos(adaptador).execute("algo", 5)
        adaptador.search.assert_called_once_with(SearchQuery("algo", 5))
        adaptador.download.assert_not_called()
        self.assertEqual(resultados[0].url, "https://y/1")

    def test_result_always_carries_a_usable_url(self):
        """Sin URL directa se compone desde el id, o no se podria descargar."""
        conteniendo = YtDlpDownloader._resultado({"id": "abc123", "title": "Uno"})
        self.assertEqual(conteniendo.url, "https://www.youtube.com/watch?v=abc123")
        directa = YtDlpDownloader._resultado({"id": "x", "url": "https://y/ver"})
        self.assertEqual(directa.url, "https://y/ver")


class PlaylistTests(unittest.TestCase):
    """Traer listas de otras apps sin tener que anadirlas a mano."""

    def test_rejects_an_empty_link_before_the_adapter(self):
        adaptador = Mock()
        for enlace in ("", "   "):
            with self.subTest(enlace=enlace), self.assertRaises(DownloadError):
                ImportPlaylist(adaptador).execute(enlace)
        adaptador.playlist.assert_not_called()

    def test_delegates_the_trimmed_link(self):
        adaptador = Mock()
        adaptador.playlist.return_value = Playlist(
            "Mis temas", (VideoInfo("Una", url="https://y/1"),))
        lista = ImportPlaylist(adaptador).execute("  https://y/lista  ")
        adaptador.playlist.assert_called_once_with("https://y/lista")
        self.assertEqual(lista.title, "Mis temas")
        self.assertEqual(len(lista.items), 1)
        adaptador.download.assert_not_called()

    def test_a_playlist_without_name_is_still_usable(self):
        """Sin nombre no se podria recrear la lista en la app."""
        self.assertEqual(Playlist("Mis temas").items, ())


class StreamTests(unittest.TestCase):
    """Escuchar antes de descargar, para comprobar que es lo que se busca."""

    #: Un video actual de YouTube: pistas sueltas y un manifiesto HLS que las une.
    FORMATOS: ClassVar[dict] = {
        "formats": [
            {"format_id": "233", "url": "https://cdn/a.m3u8", "vcodec": "none",
             "acodec": None, "protocol": "m3u8_native", "manifest_url": "https://cdn/maestro.m3u8"},
            {"format_id": "140", "url": "https://cdn/audio", "vcodec": "none",
             "acodec": "mp4a", "protocol": "https", "abr": 128},
            {"format_id": "251", "url": "https://cdn/mejor", "vcodec": "none",
             "acodec": "opus", "protocol": "https", "abr": 160},
            {"format_id": "137", "url": "https://cdn/video", "vcodec": "avc1",
             "acodec": "none", "protocol": "https"},
        ],
    }

    def test_video_prefers_the_hls_manifest(self):
        """YouTube ya casi nunca da imagen y sonido juntos; el manifiesto si."""
        pista = YtDlpDownloader._elegir_pista(self.FORMATOS, audio_only=False)
        self.assertEqual(pista["url"], "https://cdn/maestro.m3u8")

    def test_audio_takes_the_best_bitrate_over_http(self):
        pista = YtDlpDownloader._elegir_pista(self.FORMATOS, audio_only=True)
        self.assertEqual(pista["url"], "https://cdn/mejor")

    def test_video_falls_back_to_a_combined_format(self):
        combinado = {"formats": [
            {"url": "https://cdn/360", "vcodec": "avc1", "acodec": "mp4a", "height": 360},
            {"url": "https://cdn/720", "vcodec": "avc1", "acodec": "mp4a", "height": 720},
        ]}
        pista = YtDlpDownloader._elegir_pista(combinado, audio_only=False)
        self.assertEqual(pista["url"], "https://cdn/720")

    def test_without_anything_playable_it_says_so(self):
        with self.assertRaises(DownloadError):
            YtDlpDownloader._elegir_pista({"formats": []}, audio_only=False)

    def test_use_case_asks_for_audio_by_default(self):
        adaptador = Mock()
        adaptador.stream.return_value = PlaybackSource("https://cdn/pista", title="Una")
        pista = StreamVideo(adaptador).execute("https://example.com/v")
        self.assertTrue(adaptador.stream.call_args.args[0].options.audio_only)
        self.assertEqual(pista.title, "Una")
        adaptador.download.assert_not_called()

    def test_use_case_validates_the_url_before_the_adapter(self):
        adaptador = Mock()
        with self.assertRaises(DownloadError):
            StreamVideo(adaptador).execute("no-es-una-url")
        adaptador.stream.assert_not_called()

    def test_headers_travel_as_pairs_so_the_source_is_comparable(self):
        una = PlaybackSource("https://cdn/p", (("User-Agent", "x"),))
        otra = PlaybackSource("https://cdn/p", (("User-Agent", "x"),))
        self.assertEqual(una, otra)


class RetryTests(unittest.TestCase):
    """yt-dlp no reintenta un 403, y YouTube los devuelve de forma esporadica."""

    def _peticion(self):
        return DownloadRequest("https://example.com/v", Path("out"))

    def test_retries_a_transient_failure_and_succeeds(self):
        motor = YtDlpDownloader()
        esperado = DownloadResult((Path("v.mp4"),))
        intentos = [DownloadError("HTTP Error 403: Forbidden"), esperado]

        def fingir(_peticion):
            siguiente = intentos.pop(0)
            if isinstance(siguiente, Exception):
                raise siguiente
            return siguiente

        with patch.object(YtDlpDownloader, "_intentar", side_effect=fingir):
            self.assertEqual(motor.download(self._peticion()), esperado)
        self.assertEqual(intentos, [])

    def test_reintenta_la_pantalla_anti_robots(self):
        """TikTok sirve un desafio en vez de la pagina y yt-dlp se planta.

        Comprobado: el mismo video baja bien desde otra red, asi que la
        respuesta depende del momento y repetir tiene sentido.
        """
        motor = YtDlpDownloader()
        esperado = DownloadResult((Path("v.mp4"),))
        intentos = [
            DownloadError("ERROR: [TikTok] 768: Unexpected response from webpage request"),
            esperado,
        ]

        def fingir(_peticion):
            siguiente = intentos.pop(0)
            if isinstance(siguiente, Exception):
                raise siguiente
            return siguiente

        with patch.object(YtDlpDownloader, "_intentar", side_effect=fingir):
            self.assertEqual(motor.download(self._peticion()), esperado)
        self.assertEqual(intentos, [])

    def test_no_se_reintenta_para_siempre(self):
        # Si la web insiste en el desafio, se acaba avisando en vez de dar
        # vueltas: tres intentos y fuera.
        motor = YtDlpDownloader()
        fallo = Mock(side_effect=DownloadError("Unexpected response from webpage request"))
        with patch.object(YtDlpDownloader, "_intentar", fallo), self.assertRaises(DownloadError):
            motor.download(self._peticion())
        self.assertEqual(fallo.call_count, INTENTOS_TRANSITORIOS)

    def test_does_not_retry_a_real_error(self):
        motor = YtDlpDownloader()
        fallo = Mock(side_effect=DownloadError("Pasa la URL de un video individual."))
        with patch.object(YtDlpDownloader, "_intentar", fallo), self.assertRaises(DownloadError):
            motor.download(self._peticion())
        self.assertEqual(fallo.call_count, 1)

    def test_gives_up_after_the_last_attempt(self):
        motor = YtDlpDownloader()
        fallo = Mock(side_effect=DownloadError("HTTP Error 429: Too Many Requests"))
        with patch.object(YtDlpDownloader, "_intentar", fallo), self.assertRaises(DownloadError):
            motor.download(self._peticion())
        self.assertEqual(fallo.call_count, 3)


class CliTests(unittest.TestCase):
    def _adaptador(self, patched):
        adaptador = patched.return_value
        adaptador.download.return_value = DownloadResult((Path("descargas/v.mp4"),))
        adaptador.inspect.return_value = VideoInfo("Un video", "Autor", 90.0)
        return adaptador

    def test_quality_and_audio_flags_reach_the_adapter(self):
        with patch("descargador.cli.YtDlpDownloader") as patched:
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(["https://example.com/v", "-c", "720", "--subs", "es"]), 0)
        opciones = adaptador.download.call_args.args[0].options
        self.assertEqual(opciones.quality, 720)
        self.assertEqual(opciones.subtitles, ("es",))
        self.assertFalse(opciones.audio_only)

    def test_already_archived_is_skipped_not_failed(self):
        salida = io.StringIO()
        with patch("descargador.cli.YtDlpDownloader") as patched:
            adaptador = self._adaptador(patched)
            adaptador.download.return_value = DownloadResult(())
            with contextlib.redirect_stdout(salida):
                codigo = main(["https://example.com/v", "--registro"])
        self.assertEqual(codigo, 0)
        self.assertIn("Omitido", salida.getvalue())

    def test_info_inspects_without_downloading(self):
        salida = io.StringIO()
        with patch("descargador.cli.YtDlpDownloader") as patched:
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(salida):
                self.assertEqual(main(["https://example.com/v", "--info"]), 0)
        adaptador.download.assert_not_called()
        adaptador.inspect.assert_called_once()
        self.assertIn("Un video", salida.getvalue())

    def test_batch_continues_after_a_failure_and_reports(self):
        with tempfile.TemporaryDirectory() as carpeta:
            lista = Path(carpeta) / "urls.txt"
            lista.write_text("# comentario\nhttps://example.com/a\n\nincorrecta\n"
                             "https://example.com/b\n", encoding="utf-8")
            salida, errores = io.StringIO(), io.StringIO()
            with patch("descargador.cli.YtDlpDownloader") as patched:
                adaptador = self._adaptador(patched)
                with contextlib.redirect_stdout(salida), contextlib.redirect_stderr(errores):
                    codigo = main(["--desde", str(lista)])
        self.assertEqual(codigo, 1)
        self.assertEqual(adaptador.download.call_count, 2)
        self.assertIn("2 correctas, 1 con error", salida.getvalue())

    def test_clipboard_supplies_the_url(self):
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("descargador.cli.leer_portapapeles", return_value="https://example.com/v") as pegar:
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(["--pegar"]), 0)
        pegar.assert_called_once()
        self.assertEqual(adaptador.download.call_args.args[0].url, "https://example.com/v")

    def test_update_exits_without_touching_the_adapter(self):
        with patch("descargador.cli.actualizar_motor", return_value=0) as actualizar, \
             patch("descargador.cli.YtDlpDownloader") as patched:
            self.assertEqual(main(["--actualizar"]), 0)
        actualizar.assert_called_once()
        patched.assert_not_called()

    def test_reads_url_list_skipping_comments(self):
        with tempfile.TemporaryDirectory() as carpeta:
            lista = Path(carpeta) / "urls.txt"
            lista.write_text("# nota\n\nhttps://a.com/1\n  https://a.com/2  \n", encoding="utf-8")
            self.assertEqual(leer_lista(lista), ["https://a.com/1", "https://a.com/2"])
            vacia = Path(carpeta) / "vacia.txt"
            vacia.write_text("# solo comentarios\n", encoding="utf-8")
            with self.assertRaises(DownloadError):
                leer_lista(vacia)

    def test_interactive_menu_applies_video_settings(self):
        """1 video, 1 calidad 720, 2 subtítulos es, Enter para continuar."""
        respuestas = ["1", "1", "720", "2", "es", "", "https://example.com/v"]
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("builtins.input", side_effect=respuestas):
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([]), 0)
        opciones = adaptador.download.call_args.args[0].options
        self.assertEqual(opciones.quality, 720)
        self.assertEqual(opciones.subtitles, ("es",))

    def test_interactive_menu_applies_audio_settings(self):
        """2 audio, 1 códec m4a, 2 bitrate 320, Enter para continuar."""
        respuestas = ["2", "1", "m4a", "2", "320", "", "https://example.com/v"]
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("builtins.input", side_effect=respuestas):
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([]), 0)
        opciones = adaptador.download.call_args.args[0].options
        self.assertTrue(opciones.audio_only)
        self.assertEqual(opciones.audio_format, "m4a")
        self.assertEqual(opciones.audio_bitrate, "320")

    def test_settings_menu_keeps_value_when_input_is_invalid(self):
        respuestas = ["1", "1", "altísima", "", "https://example.com/v"]
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("builtins.input", side_effect=respuestas):
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([]), 0)
        self.assertIsNone(adaptador.download.call_args.args[0].options.quality)

    def test_settings_menu_can_cancel(self):
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("builtins.input", side_effect=["1", "0"]):
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([]), 0)
        adaptador.download.assert_not_called()

    def test_flags_skip_the_interactive_menu(self):
        with patch("descargador.cli.YtDlpDownloader") as patched, \
             patch("builtins.input", side_effect=AssertionError("no debe preguntar")):
            adaptador = self._adaptador(patched)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(["https://example.com/v", "-c", "480"]), 0)
        self.assertEqual(adaptador.download.call_args.args[0].options.quality, 480)

    def test_settings_menu_offers_the_right_options(self):
        video = [nombre for nombre, _ in acciones_ajustes(audio=False)]
        audio = [nombre for nombre, _ in acciones_ajustes(audio=True)]
        self.assertIn("Subtítulos", video)
        self.assertNotIn("Subtítulos", audio)
        self.assertIn("Formato", audio)
        resumen = " ".join(describir_ajustes(DownloadOptions(quality=720), Path("descargas"), audio=False))
        self.assertIn("hasta 720p", resumen)

    def test_human_readable_helpers(self):
        self.assertEqual(formato_tamano(None), "--")
        self.assertEqual(formato_tamano(1536), "1.5 KB")
        self.assertEqual(formato_tiempo(90), "01:30")
        self.assertEqual(formato_tiempo(3723), "1:02:03")


if __name__ == "__main__":
    unittest.main()
