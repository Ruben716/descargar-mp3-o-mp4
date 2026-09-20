import contextlib
import io
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
    acciones_ajustes,
    describir_ajustes,
    formato_tamano,
    formato_tiempo,
    leer_lista,
    main,
)
from descargador.domain import (
    DownloadError,
    DownloadOptions,
    DownloadProgress,
    DownloadRequest,
    DownloadResult,
    PlaybackSource,
    SearchQuery,
    VideoInfo,
    parse_section,
    parse_timestamp,
)
from descargador.infrastructure import YtDlpDownloader, incrusta_caratula


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
        self.assertIn("height<=720", YtDlpDownloader._seleccion_formato(DownloadOptions(quality=720)))

    def test_mp4_preference_asks_for_h264_first(self):
        """En el movil el contenedor y el codec deciden si el video se reproduce."""
        seleccion = YtDlpDownloader._seleccion_formato(DownloadOptions(prefer_mp4=True, quality=720))
        self.assertTrue(seleccion.startswith("bv*[vcodec^=avc1][height<=720]"))
        # Debe conservar alternativas: si no hay H.264, algo se descarga igual.
        self.assertIn("/bv*+ba/b" if "/bv*+ba/b" in seleccion else "/b", seleccion)
        self.assertEqual(seleccion.count("height<=720"), 5)

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
        adaptador.playlist.return_value = (VideoInfo("Una", url="https://y/1"),)
        pistas = ImportPlaylist(adaptador).execute("  https://y/lista  ")
        adaptador.playlist.assert_called_once_with("https://y/lista")
        self.assertEqual(len(pistas), 1)
        adaptador.download.assert_not_called()


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
