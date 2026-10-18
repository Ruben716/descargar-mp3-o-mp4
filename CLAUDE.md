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
  bajado (`cabecera_sin_perdida`): casi ninguna web los dice al buscar. La excepción es el
  Archive, que llama «24bit Flac» a ese formato: `calidad_archive` lo lee del campo `format`.
- **Commons necesita el extractor propio** (`_extractor_commons`): el `WikimediaIE` de yt-dlp no le
  pone `vcodec` al formato `source` (el original), solo a las copias Ogg que hace Commons, y con
  `ba` se elegía la copia con pérdida en vez del FLAC. `formatos_commons` deja solo el original,
  marcado como audio; las copias son recompresiones del mismo archivo. La búsqueda va con
  `AGENTE_COMMONS`, porque fingir un navegador da 403, y descarta pronunciaciones (Lingua Libre),
  lo de menos de 30 s, los MIDI y las licencias que no son CC0, dominio público, CC BY o BY-SA.
  Un Ogg se anuncia como «ogg»: puede llevar Vorbis, Opus o FLAC dentro y no se adivina.
- **El Archive no llama «audio» a etree**: sus conciertos son `mediatype:etree`, así que la consulta
  pide `mediatype:(audio OR etree)` o se pierde la colección entera. Lo de fuera de las tres
  colecciones entra por `licenseurl:*creativecommons*`/`*publicdomain*`: comodines sin «/», que con
  barra su buscador falla. «24bit Flac» se busca con `format:24bit*`, sin comillas en la consulta.
- **ccMixter repite el cuerpo en la cabecera `X-JSON`**, y pasa de los 64 KB que admite
  `http.client`: lanza `LineTooLong`, que hereda de `HTTPException` y no de `OSError`. Por eso
  `_pedir` captura `HTTPException` en todas las fuentes, se piden 10 como mucho
  (`LIMITE_CCMIXTER`; por encima de 25 responde vacío) y, si aun así no cabe, la mitad. Su JSON
  trae ceros a la izquierda y caracteres de control (`json_ccmixter`), corta el hotlink sin
  `Referer: https://ccmixter.org/` (va en el formato, y llega también a la escucha previa) y
  rechaza una búsqueda que acaba en comilla. yt-dlp no tiene extractor: `_extractor_ccmixter`
  ofrece solo la mezcla, porque los FLAC de una subida suelen ser muestras o la voz sola.
- **YouTube Music busca con el extractor del motor** (`youtube:music:search_url`, sección `#songs`),
  pero ese solo saca título y enlace. `_extractor_ytmusic` lo subclasea y redefine
  `_music_reponsive_list_entry` (con la errata de yt-dlp) para añadir artista, álbum, duración y
  la carátula a 544 px. Si yt-dlp renombra el método, se pierde eso sin romper la búsqueda.
- **Sin procesar, los formatos no traen `protocol`** (lo rellena yt-dlp al procesar), y la escucha
  previa extrae sin procesar: `_elegir_pista` mira entonces la dirección. Sin eso, la escucha de
  cualquier extractor propio acababa en «no ofrece una pista reproducible».
- **Jamendo pide una clave de la app** (no del usuario): `clave_jamendo()` la lee de
  `JAMENDO_CLIENT_ID` o de `descargador/clave_jamendo.txt`, que git ignora y que GitHub Actions
  escribe desde el secreto del mismo nombre antes de compilar el APK. Solo se ofrecen las pistas
  con `audiodownload_allowed`: de las demás su servidor no da el FLAC. El original de SoundCloud
  no se contempla: su servidor responde 401 sin sesión.
- **Un episodio de podcast se baja desde su programa.** Suelto, el motor solo ve un MP3 y lo llama
  por el nombre del archivo. `playlist()` da enlaces `programa#tumbao-episodio=<episodio>`
  (`enlace_de_episodio`) y `_extraer` los resuelve dentro del RSS, con el título y la fecha de
  allí y un identificador corto (`ep-…`). Los podcasts cuentan en `FUENTES_DE_LISTAS`.
- **Las fuentes nuevas se comprueban contra internet antes de darlas por buenas**, con
  `.github/prueba_red.py` (flujo «Prueba de red»): las pruebas normales no salen a la red, y así se
  vio que el FLAC de Jamendo daba 404 por la dirección que usaba el motor. Cada fuente va en su
  bloque (`seccion`): una caída no tapa a las demás, y el proceso acaba con error si falló alguna.
- **La radio en vivo va por HTTP plano**: casi todas las emisoras emiten así, y
  `network_security_config.xml` lo permite. Solo afecta a lo que reproduce la app.
- **El DJ analiza en el teléfono, no en el núcleo.** `ritmo.py` vive junto a `puente.py`
  (`analizar_audio`) y la consola no lo usa; sus pruebas están en `tests/test_ritmo.py` y lo cargan por su ruta.
  Una sola pasada de FFmpeg da tempo, pulsos, energía y LUFS (el volumen parejo los aprovecha), con stderr a un
  archivo temporal: `ebur128` escribe cada 100 ms y una tubería se llenaría. Lo analizado va a la tabla `ritmos`
  (catálogo v9) con la `version` del algoritmo; subir `VERSION` vuelve a analizarlo todo. La energía se compara
  siempre por percentil de la biblioteca (`Ritmos.percentil`), nunca en bruto.
- **El fundido al compás recorta con `ClippingAudioSource`**: la posición y la duración del motor pasan a ser las
  del tramo, así que solo se usa el corte en las fuentes que se cargaron recortadas (`_recortadas`). «Saltar
  silencios» se apaga en ese modo: quita trozos y descuadra los pulsos.
- **El ecualizador va por salida** (`salida_audio.dart`): Kotlin avisa con `salidaCambio` al conectar o quitar
  un aparato (`AudioDeviceCallback`) y cada salida (altavoz, cable, cada Bluetooth por su nombre) guarda su
  ajuste en `ecualizador_salidas`. No hay mediciones públicas de altavoces de teléfono: `Ajuste.altavoz` es
  una curva general, no la de cada modelo. Unos audífonos nuevos se corrigen solos con AutoEQ solo si el
  nombre casa sin dudas (`modeloParaAparato`) y con wifi.
- **En «Todas» primero la canción y después la calidad** (`busqueda.dart`, `_ordenados`). El primer resultado
  de YouTube Music (o, si no hay, de YouTube) es el `Objetivo`: YouTube entiende trozos de letra y faltas, las
  demás fuentes solo palabras. Arriba va el objetivo en todas las fuentes, por calidad; lo que solo lleva las
  palabras va después por la relevancia de cada fuente, no por calidad. Si lo escrito no era el título, se
  vuelve a preguntar a `MejorCalidad.fuentes` por «artista título» del objetivo.
- **Las animaciones sin fin pasan por `Movimiento.continuas(context)`** (el latido, el fondo vivo, la barra
  ondulada, el brillo del sello, Pídele que se escribe, el desenfoque de la letra). Es false con «Quitar
  animaciones» del sistema y en las pruebas (`Movimiento.bucles = false` en el `setUp`): `pumpAndSettle` no
  acaba nunca con una animación en bucle. El latido del reproductor es un solo reloj (`ConLatido`) que solo
  corre sonando una canción con pulso; lo demás escucha sus `ValueNotifier` sin reconstruir la pantalla.
- **«Pídele a Tumbao» son reglas, no IA** (`pidele.dart`): sin red y probado con funciones puras. Relajar una
  petición nunca deja sin filtros lo pedido: si solo se pidió un género o un ritmo que no hay, sale vacío y se
  ofrece buscar en internet, en vez de devolver la biblioteca entera.
- **«Descubre» es la radio de YouTube Music, no una recomendación propia** (`descubre.dart`): la lista
  `RDAMVM<video>` de una canción de cada artista más oído, leída con `importarLista` como cualquier otra. Las
  semillas salen de la tabla `descargas` (`Catalogo.videos`, por video); lo que no se bajó de YouTube se busca
  antes en `ytmusic`. Se guarda en `SharedPreferences` y Inicio solo lee eso: la red va en las tareas de fondo
  de `main.dart`, una vez por semana. Si no llega nada, se queda la lista de antes.
- **Las descargas inteligentes solo borran lo que bajaron ellas** (`descargas_inteligentes.dart`): varias
  `MezclaInteligente` (para ti, por género o por artista), cada una con su cantidad, sus días y su lista con su
  nombre. Salen de la radio de YouTube Music de sus semillas (`semillasDe`, que cambian con `vueltas`) y cada
  canción se apunta con la `tanda` (la `renovada` de su mezcla). Al renovar, lo de tandas anteriores que nadie
  escuchó, marcó Me gusta ni metió en otra lista se borra; lo tocado, o lo de «Guardar como lista», pasa a ser
  del usuario y se suelta. Sin red no se renueva: se arma antes de borrar. En `main.dart` van detrás de las
  listas que sigues y de Descubre, una tras otra: comparten `ControlDescarga`. Lo que se salta antes de 30 s
  (`EstadoReproductor.esSalto`) suma al artista: va al final y con 3 saltos no se baja más. El límite de espacio
  cuenta lo que ocupan las suyas (`cabenAun`, con `pesoTipico` si no se sabe), y el modo viaje no apunta tanda:
  su lista es del usuario desde el principio.
- **La portada grande va aparte de la miniatura** (`portada_grande.dart`): se baja una vez, con wifi, a la
  carpeta privada con `Nucleo.clavePortada` (FNV-1a, no `hashCode`, que cambia entre ejecuciones). Ojo con
  `whenComplete(() => mapa.remove(clave))`: devolver el futuro quitado hace que se espere a sí mismo.
- **Letras: primero YouTube Music por el video, luego lrclib** (`letras.dart`). Lo bajado de YouTube se pide por
  su id (`Catalogo.videoDe`) a `letras_ytm.py`, que no puede dar otra canción; la sincronizada solo la da el
  cliente `ANDROID_MUSIC` (si deja de salir, mirar `prueba_red.py`). lrclib busca por artista y título de las
  etiquetas (`Elemento.partes`), no por el nombre del archivo, y descarta otro artista; si la duración difiere
  más de `margenDuracion` es otra versión y se da de corrido, sin sus tiempos. La posición de la letra suma
  `inicioDelTramo`: con el fundido al compás el motor cuenta desde el corte.
- **«Ajustar con la voz» no es reconocimiento de voz** (`voz.py`, junto al puente): mira dónde arranca algo en
  la banda de la voz en el centro de la mezcla y prueba a correr la letra ±8 s. Solo aplica si el mejor ajuste
  destaca (`CONFIANZA_MINIMA`) y le gana con claridad al mejor de los lejanos (`VENTAJA_MINIMA`): con golpes
  regulares muchos ajustes puntúan casi igual, y sin esa ventaja salían falsos de 4 s en temas sin voz.
- **El video de la letra lo pinta Flutter y lo une FFmpeg** (`video_letra.dart`, `video_letra.py`): un PNG de
  720x1280 por verso (`FotogramaVideo`, 360x640 puntos a `pixelRatio` 2) desde `desde + desfase`, y en la lista
  del concat el último va repetido o dura un instante. La onda la pinta FFmpeg en la franja que el fotograma deja
  libre (`zonaOnda` = `ONDA_*` / 2: si se toca uno, el otro). El codificador va en cadena (libx264,
  h264_mediacodec, mpeg4) porque no se sabe qué trae el FFmpeg del teléfono: si el fallo es del codificador se
  prueba el siguiente, y si es del grafo (`FALLOS_DE_FILTRO`) se repite sin la onda. Se guarda en `Pictures/Tumbao`, con las tarjetas: `Movies/Tumbao` es carpeta de la biblioteca
  y `mudarVideosADcim` se lo llevaría a DCIM.
- **Tema «Ónix»: el acento es blanco.** El color lo ponen las portadas; en `tema.dart` todo es gris neutro y
  el dorado (`Tema.oro`) es solo para el sello de calidad. Por eso lo que suena no se marca con color sino con
  un icono (`graphic_eq`), y encima del acento va siempre `Tema.tinta`: un `Switch` con `activeThumbColor:
  Tema.acento` quedaría blanco sobre blanco.
- **Lo comprimido no se reconvierte.** El formato de fábrica de la app es `best` («Original»): el
  Opus o AAC llega tal cual. Pasarlo a MP3 lo comprimiría por segunda vez.
- Opciones que son decisiones de producto, no detalles: `noplaylist` + `match_filter` rechazan listas,
  canales y directos; `continuedl` + `overwrites: False` reanudan sin sobrescribir; el nombre incluye
  `%(id)s`; `bv*+ba/b` une sin recodificar.

## Idioma

Código, mensajes, docstrings y documentación en español. Mantén ese idioma en cualquier texto nuevo.
