# CLAUDE.md

Guía para trabajar en este repositorio. Proyecto académico, local: no se despliega ni se distribuye.
Sin inicio de sesión ni cookies (decisión explícita del autor); la única excepción es el WebView que
recoge la cookie de visitante que algunos sitios exigen para descargar, nunca para identificarse.

Hay dos productos que comparten un mismo núcleo Python:

- **Consola de escritorio** (raíz): `descargador/` + `py.py`. Toda su interfaz es de consola;
  **no le añadas GUI**.
- **App Android «Tumbao»** (`movil/`): interfaz Flutter que embebe ese mismo núcleo con Chaquopy y se
  comunica con él por un `MethodChannel`. Ahí sí hay GUI (y es aparte, no dentro del CLI).

La regla que gobierna todo: **el núcleo no sabe quién lo llama**. El CLI y la app móvil son dos
adaptadores sobre los mismos casos de uso; el caso de uso no conoce yt-dlp y las dependencias apuntan
siempre al dominio.

## Comandos

### Núcleo Python (raíz)

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

### App móvil (`movil/`)

```bash
cd movil
flutter pub get
flutter test          # pruebas de widget y de la base de datos (sin red)
flutter analyze
flutter run           # con el teléfono conectado o por depuración wifi
```

El núcleo de Python **no se copia a mano**: la tarea Gradle `sincronizarNucleo` lleva `descargador/` a
`android/app/src/main/python/` en cada compilación. Esa copia está en `.gitignore`; edita siempre el
original en `descargador/`.

Icono: se genera desde `herramientas/icono_origen.jpeg` con
`python herramientas/generar_icono.py` y luego `dart run flutter_launcher_icons`.

### Integración continua

[.github/workflows/apk.yml](.github/workflows/apk.yml) compila el APK al empujar a la rama `movil` (o a
mano): instala Python 3.14 (la versión de Chaquopy), Flutter 3.44.8 y Java 21; pasa ruff, mypy, unittest
y `flutter analyze`/`flutter test`; y publica el APK como la versión «apk-prueba». Los fallos de las
pruebas se convierten en anotaciones con [.github/anotar_pruebas.py](.github/anotar_pruebas.py). La firma
usa el secreto `DEBUG_KEYSTORE`: con otra clave, Android no deja instalar el APK encima de la app ya
instalada. En el PC de desarrollo, Smart App Control bloquea las herramientas de Flutter (no llevan
firma), así que se compila en GitHub y el PC solo descarga el APK.

## Arquitectura

### Núcleo Python compartido (`descargador/`)

Arquitectura limpia con cuatro capas en `descargador/`, una por archivo.

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
Python del sistema), [descargador/__main__.py](descargador/__main__.py) y el script `descargar` de
[pyproject.toml](pyproject.toml).

### App móvil Tumbao (`movil/`)

- **Interfaz**: Flutter, en `movil/lib/`. [main.dart](movil/lib/main.dart) es el armazón: un
  `IndexedStack` de cuatro pestañas (Inicio, Descargar, Biblioteca, Ver) que se construyen
  perezosamente (para no pedir portadas de todo al arrancar) y un mini reproductor fijo sobre la barra.
  El estado compartido son singletons `ChangeNotifier` (`EstadoReproductor`, `ControlDescarga`,
  `Listas`, `Favoritas`, `Nucleo`) sobre los que se pintan pantallas casi sin estado.
- **Puente con el núcleo**: [nucleo.dart](movil/lib/nucleo.dart) llama por el `MethodChannel`
  `com.ruben.descargador/nucleo`; todo viaja como JSON y las claves del dominio se espejan en DTOs
  (`Resultado`, `Elemento`, `Ajustes`, `Fuente`, `CalidadAudio`). En Android, `MainActivity.kt` recibe
  la llamada y ejecuta el módulo Python `puente` fuera del hilo de interfaz.
- **Python solo del móvil** (rastreado, no copiado): `movil/android/app/src/main/python/puente.py`
  (funciones del canal) y `red_android.py` (red nativa). El resto del núcleo es `descargador/`.
- **Reproducción**: `just_audio` + `just_audio_background` dentro de `EstadoReproductor`; vídeo con
  `video_player` y gestos tipo VLC en [video_pro.dart](movil/lib/video_pro.dart).
- **Persistencia**: catálogo en SQLite (`catalogo.db`, esquema v7) por
  [catalogo.dart](movil/lib/catalogo.dart); listas, sesión, ecualizador, ajustes y posiciones de vídeo
  en `shared_preferences`; lo descargado se publica en MediaStore: audio en `Music/Tumbao`, vídeo en
  `DCIM/Tumbao` (se leen también las carpetas antiguas `Music/Descargador` y `Movies/...`).
- **Kotlin de apoyo**: `ServicioDescarga.kt` (servicio en primer plano que mantiene vivo el proceso
  mientras se descarga), `RedNativa.kt` (TLS con huella de Chrome para muros anti-bot),
  `WidgetTumbao.kt` (widget de la pantalla de inicio).

### Invariantes del núcleo

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

### Trampas de la app móvil (Android / Chaquopy)

- **Chaquopy** se aplica **después** del plugin de Android. Python queda fijado a **3.14** y solo se
  empaqueta `arm64-v8a` (no hay Python 3.14 para `armeabi-v7a`); `finalizeDsl` vuelve a forzar esa ABI
  porque Flutter añade las tres tarde. `minSdk 29` es deliberado: permite escribir en MediaStore sin
  permisos de almacenamiento.
- **No actives el R8 «optimize» en release**: rompe la reflexión de `audio_service`, la app deja de
  verse como reproductor y desaparecen los controles de notificación y pantalla de bloqueo. Solo
  `proguard-rules.pro`.
- **`libffmpeg.zip.so` es un ZIP, no un ELF**: necesita `useLegacyPackaging` y no debe quitarse con el
  *stripping*; el ejecutable de FFmpeg solo corre desde la carpeta nativa extraída.
  `MainActivity.asegurarFfmpeg` lo extrae y enlaza `ffmpeg`/`ffprobe`. Un enlace roto hay que borrarlo
  antes de `Os.symlink` porque `exists()` lo sigue.
- **El ecualizador de Android se engancha al construir el `AudioPlayer`** (no se puede añadir después)
  y a veces pide las bandas antes de que exista la sesión de audio (`NullPointerException`). Un
  reintento simple no basta porque la activación rota queda cacheada: hay que parar el motor y recargar
  (`cargarConReintentos`).
- **MediaStore**: el MIME se deduce de la extensión (registrar todo como `audio/mpeg` renombra
  FLAC/WAV/M4A); el vídeo va a `DCIM` y no a `Movies` porque las galerías ocultan `Movies`; y como solo
  se expone un descriptor, para reetiquetar hay que copiar fuera, reescribir con Python/FFmpeg y volver
  a entrar con `"wt"` (truncar) antes de renombrar.
- **Anti-bot**: TikTok sirve un reto a TLS no-navegador; para reintentar se usa `RedNativa` (huella
  Conscrypt de Chrome) o un WebView que recoge la cookie de visitante. Nunca inicio de sesión.
- `kotlin.incremental=false` porque la caché incremental de Kotlin falla con la ruta de Windows que
  lleva espacios.
- Ninguna prueba toca la red: [movil/test/widget_test.dart](movil/test/widget_test.dart) usa
  `sqflite_common_ffi` en memoria y [movil/test/motor_falso.dart](movil/test/motor_falso.dart)
  implementa un motor de audio falso (`JustAudioPlatform`); AniList y la traducción se inyectan.

### Trampas del núcleo móvil (Dart)

- `Ajustes.aMapa()` fuerza `calidad: 0` en audio, descarta `normalizar`/`portadaOficial` fuera de audio
  y anula `normalizar` si el formato está en `formatosSinNormalizar` (`best, opus, m4a, aac`): si no,
  el núcleo rechaza la descarga **entera** (el filtro loudnorm choca con `-c copy`).
- El fundido **no es un crossfade real** (hay un solo reproductor): solo baja el final y el principio.
- Las carátulas ya preparadas se guardan en el directorio de soporte de la app, no en el temporal,
  porque el limpiador del sistema las borraría y habría que recomprimir cientos antes de sonar nada.
- `minimoParaContar = 20 s`: una canción saltada no cuenta como escuchada.
- Ojo: el comentario sobre `enum Fuente` en `nucleo.dart` dice que Bandcamp queda fuera, pero Bandcamp
  sí existe y se busca; trátalo como comentario obsoleto.

## Idioma

Código, mensajes, docstrings y documentación en español. Mantén ese idioma en cualquier texto nuevo.
