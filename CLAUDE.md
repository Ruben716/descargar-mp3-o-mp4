# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Proyecto académico, local. No se despliega, no se distribuye y no lleva inicio de sesión ni cookies
(decisión explícita del autor). Toda la interfaz es de consola; no añadas GUI.

## Comandos

Windows con PowerShell y entorno virtual local `.venv`.

```powershell
# Instalar (editable, con herramientas de desarrollo)
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"

# Ejecutar
python py.py                                  # menú interactivo
python py.py "URL" --calidad 1080 --subs es
python py.py --desde lista.txt --registro
python py.py "URL" --info                     # sin descargar

# Control de calidad
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe -m unittest tests.test_downloader.AdapterTests
.\.venv\Scripts\python.exe -m ruff check .    # --fix para autocorregir
.\.venv\Scripts\python.exe -m mypy

# Actualizar el motor cuando un sitio deja de funcionar
python py.py --actualizar
```

## Arquitectura

Arquitectura limpia con cuatro capas en `descargador/`, una por archivo. La regla que gobierna el
diseño: **el caso de uso no conoce yt-dlp**, y las dependencias apuntan siempre al dominio.

- [domain.py](descargador/domain.py) — `DownloadOptions` (todos los ajustes, con su validación),
  `DownloadRequest` (valida y normaliza la URL en `__post_init__`), `DownloadProgress`, `VideoInfo`,
  `MediaFormat`, `AudioQuality` (calidad real del audio en origen), `DownloadError`, los ayudantes
  `parse_timestamp`/`parse_section` y el `Protocol` `VideoDownloader` (`download`, `inspect`,
  `search`, `playlist`, `stream`, `quality`). Sin imports del proyecto.
- [application.py](descargador/application.py) — `DownloadVideo`, `InspectVideo`, `SearchVideos`,
  `StreamVideo`, `ImportPlaylist` y `CheckQuality`. Reciben el `VideoDownloader` por constructor y
  solo construyen la petición. Deliberadamente mínimos.
- [infrastructure.py](descargador/infrastructure.py) — `YtDlpDownloader`, único lugar que toca red,
  disco, yt-dlp y FFmpeg, más las utilidades de sistema (`actualizar_motor`, `abrir_carpeta`,
  `leer_portapapeles`, `incrusta_caratula`). Importa yt-dlp e imageio-ffmpeg **dentro** de
  `_cargar_motor()` para convertir un `ImportError` en `DownloadError` con instrucciones.
- [cli.py](descargador/cli.py) — argparse, menús, formato de salida y el único punto de composición.
  Hay dos caminos: **banderas** (no preguntan nada) y **modo interactivo**, que tras `choose_format()`
  abre `menu_ajustes()`, una pantalla que muestra `describir_ajustes()` y aplica las `acciones_ajustes()`
  hasta que el usuario pulsa Enter. Cada acción es un `Ajuste`: recibe `(opciones, destino)` y devuelve
  los nuevos mediante `dataclasses.replace`. **Si añades una opción, añádela también ahí**, o solo
  existirá para quien use la línea de comandos.

Puntos de entrada: [py.py](py.py) (relanza con `.venv\Scripts\python.exe` si se invoca desde el
Python del sistema), `descargador/__main__.py` y el script `descargar` de [pyproject.toml](pyproject.toml).

### Invariantes a respetar

- **Toda excepción que llegue al usuario debe ser `DownloadError`**; `cli.main` no imprime tracebacks.
  El adaptador captura `YoutubeDLError` (base común de extracción, descarga y postprocesado), no solo
  `DownloadError` de yt-dlp. Salidas: `0` éxito, `1` `DownloadError`, `130` `Ctrl-C`/EOF, `2` argparse.
- La validación vive en el dominio, no en el CLI ni en el adaptador. Las pruebas verifican que el
  adaptador **no se invoca** con una URL inválida.
- Un `DownloadResult` **vacío significa «omitido»**, no error: pasa cuando `--registro` detecta que la
  URL ya figura en `.descargadas.txt`. El CLI lo cuenta aparte y devuelve 0.
- Con varias URLs, un fallo no interrumpe el resto; el resumen final distingue correctas, con error y
  omitidas.
- El modo audio escribe en la subcarpeta `audio/` del destino.
- Ninguna prueba debe tocar la red: se usan dobles del adaptador, y la lógica probable (selección de
  formato, postprocesadores, `_single_video`, parsers) está en métodos puros.

### Trampas conocidas de yt-dlp

- **`ffmpeg_location` no basta.** Para `--seccion`, yt-dlp comprueba FFmpeg con `FFmpegFD.available()`,
  que construye el postprocesador sin `downloader` y por tanto solo mira el `PATH` (su propio código lo
  marca con un *Fixme*). Por eso `_preparar_ffmpeg` crea un alias `ffmpeg.exe` junto al binario de
  imageio-ffmpeg y añade esa carpeta al `PATH`. No lo quites o el recorte dejará de funcionar.
- **ffprobe no viene con imageio-ffmpeg.** `EmbedThumbnail` lo necesita para contenedores MKV. Por eso
  `incrusta_caratula()` decide si se incrusta la carátula, y `writethumbnail` sigue esa misma condición
  para no dejar `.webp` sueltos. En audio siempre se incrusta (mutagen o FFmpeg lo resuelven).
- **La calidad que se enseña es la del origen, no la del archivo.** `quality()` usa la misma
  `_seleccion_formato` que la descarga, así que dice exactamente qué audio llegará; convertir un
  Opus de 127 kb/s a FLAC no lo hace «sin pérdida», y la app no debe decir lo contrario. Medido sin
  cuenta: Audius, MP3 320 y el WAV/FLAC original cuando el artista deja bajarlo; SoundCloud, AAC 160
  si no lleva DRM (lo de los sellos grandes sí lo lleva); YouTube, Opus ~127 / AAC ~129; Bandcamp,
  MP3 128 salvo lo regalado (~1 de cada 10), que llega sin pérdida; el Archive, FLAC.
- **Audius necesita el extractor propio** (`_extractor_audius`, enrutado por `_extraer`): el de
  yt-dlp solo pide el streaming y nunca bajaría el original. Toda extracción de una pista suelta
  debe pasar por `_extraer`. Los bits y la frecuencia reales salen de la cabecera del archivo ya
  bajado (`cabecera_sin_perdida`): ninguna web los dice al buscar.
- Opciones que son decisiones de producto, no detalles: `noplaylist` + `match_filter` rechazan listas,
  canales y directos; `continuedl` + `overwrites: False` reanudan sin sobrescribir; el nombre incluye
  `%(id)s`; `bv*+ba/b` une sin recodificar.

## Idioma

Código, mensajes, docstrings y documentación en español. Mantén ese idioma en cualquier texto nuevo.
