"""Adaptador de yt-dlp: red, archivos y unión con FFmpeg."""
from pathlib import Path
import shutil

from .domain import DownloadError, DownloadRequest, DownloadResult


class YtDlpDownloader:
    def download(self, request: DownloadRequest) -> DownloadResult:
        try:
            from yt_dlp import YoutubeDL
            from yt_dlp.utils import DownloadError as EngineError
            from imageio_ffmpeg import get_ffmpeg_exe
        except ImportError as exc:
            raise DownloadError('Faltan dependencias. Ejecuta: python -m pip install -e .') from exc

        files: list[Path] = []

        def finished(filename):
            if filename:
                files.append(Path(filename).resolve())

        try:
            destination = request.destination.expanduser().resolve()
            if request.audio_only:
                destination = destination / "audio"
            destination.mkdir(parents=True, exist_ok=True)
            ffmpeg = shutil.which("ffmpeg") or get_ffmpeg_exe()
            options = {
                "paths": {"home": str(destination)},
                "outtmpl": {"default": "%(title).120B [%(id)s].%(ext)s"},
                "windowsfilenames": True,
                "format": "ba/b" if request.audio_only else "bv*+ba/b",
                "ffmpeg_location": ffmpeg,
                "merge_output_format": "mp4/mkv",
                "noplaylist": True,
                "match_filter": self._single_video,
                "continuedl": True,
                "overwrites": False,
                "retries": 5,
                "fragment_retries": 5,
                "skip_unavailable_fragments": False,
                "socket_timeout": 30,
                "color": "no_color",
                "post_hooks": [finished],
                "js_runtimes": {name: {} for name in ("deno", "node") if shutil.which(name)},
            }
            if request.audio_only:
                options["postprocessors"] = [{
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "192",
                }]
            with YoutubeDL(options) as engine:
                info = engine.extract_info(request.url, download=False, process=False)
                if info and info.get("_type") in {"playlist", "multi_video"}:
                    raise DownloadError("Pasa la URL de un video individual, no de una lista o canal.")
                if info:
                    engine.process_ie_result(info, download=True)
            existing = tuple(dict.fromkeys(p for p in files if p.is_file()))
            if not existing:
                raise DownloadError("No se obtuvo ningún archivo. Comprueba la URL.")
            return DownloadResult(existing)
        except (EngineError, OSError, RuntimeError) as exc:
            raise DownloadError(f"No se pudo completar la descarga: {exc}") from exc

    @staticmethod
    def _single_video(info, *, incomplete=False):
        if info.get("_type") in {"playlist", "multi_video"}:
            return "Pasa la URL de un video individual, no de una lista o canal."
        if info.get("is_live"):
            return "El video está en directo. Usa la URL cuando la transmisión termine."
        return None
