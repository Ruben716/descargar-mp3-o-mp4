# Descargador por consola

Descarga un video o solo su audio a partir de una URL. Todo funciona desde la
consola, sin interfaz gráfica, sin inicio de sesión y sin cookies.

Desde esta carpeta, ejecuta:

```powershell
python py.py
```

Primero aparece este menú:

```text
¿Qué quieres descargar?

  1. Video con audio
  2. Música / audio en MP3
  3. Ver información del video (sin descargar)
  0. Salir
```

Si te equivocas de opción, el programa vuelve a pedirla.

Al elegir `1` o `2` aparece la pantalla de ajustes, donde se ve cómo se va a
descargar y se puede cambiar cualquier cosa antes de empezar:

```text
Así se va a descargar:

  Calidad:      la mejor disponible
  Subtítulos:   no
  Patrocinios:  se conservan
  Fragmento:    completo
  Carpeta:      descargas
  Repetidos:    se vuelven a descargar
  Carátula:     se incrusta

  1. Calidad   2. Subtítulos   3. Patrocinios   4. Fragmento   5. Carpeta   6. Repetidos

Enter para continuar, un número para cambiarlo, 0 para salir:
```

Escribe el número del ajuste que quieras cambiar y el resumen se actualiza. Con
Enter se acepta todo tal cual y el programa pide el enlace. En audio, la lista
ofrece el códec y el bitrate en lugar de calidad, subtítulos y patrocinios.

Todo esto también está disponible como opciones de la línea de comandos, y al
usarlas no se pregunta nada. Usa comillas alrededor de la URL, sobre todo si
contiene `&`:

```powershell
python py.py "https://sitio.com/video"
python py.py "https://sitio.com/video" --audio
```

## Opciones

| Opción | Para qué sirve |
|---|---|
| `-a`, `--audio` | Descargar solo el audio (MP3 de 192 kb/s por omisión) |
| `-o`, `--destino CARPETA` | Carpeta de salida (por omisión `descargas`) |
| `-c`, `--calidad ALTO` | Limitar el alto en píxeles, por ejemplo `1080` |
| `--formato-audio CODEC` | `mp3`, `m4a`, `opus`, `flac`, `wav`, `aac`, `alac`, `vorbis`, `best` |
| `--bitrate KBPS` | Calidad del audio, por omisión `192` |
| `--subs [IDIOMAS]` | Descargar e incrustar subtítulos (por omisión `es,en`) |
| `--seccion INICIO-FIN` | Descargar solo un fragmento, por ejemplo `00:30-02:15` |
| `--sin-patrocinios` | Eliminar segmentos patrocinados con SponsorBlock |
| `--registro` | Anotar lo descargado y omitir lo repetido |
| `--desde ARCHIVO` | Descargar todas las URLs de un archivo, una por línea |
| `--pegar` | Tomar la URL del portapapeles |
| `-i`, `--info` | Mostrar los datos y formatos del video sin descargarlo |
| `--abrir` | Abrir la carpeta al terminar |
| `--sin-progreso` | Usar la salida original de yt-dlp en vez del progreso propio |
| `--actualizar` | Actualizar yt-dlp y salir |

### Ejemplos

```powershell
python py.py "URL" --calidad 1080 --subs es
python py.py "URL" --seccion 01:20-03:45
python py.py "URL" --audio --formato-audio m4a --bitrate 256
python py.py --desde lista.txt --registro
python py.py --pegar --audio --abrir
python py.py "URL" --info
```

En `lista.txt` va una URL por línea; las líneas vacías y las que empiezan por
`#` se ignoran. Al procesar varias URLs, un fallo no detiene las demás y al
final se imprime un resumen.

## Instalación en otro equipo

Python 3.10 o posterior:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
python py.py
```

El lanzador utiliza automáticamente el entorno `.venv` del proyecto. FFmpeg se
incluye mediante imageio-ffmpeg; si ya está en PATH se utiliza esa instalación.
Para soporte completo de YouTube, instala Deno o Node.js compatible con yt-dlp.
Ambos se detectan automáticamente; en el equipo de desarrollo hay Node.js.

También puedes usar `.\.venv\Scripts\descargar.exe "URL"` o
`.\.venv\Scripts\python.exe -m descargador "URL"`.

## Comportamiento

- Selecciona la mejor calidad disponible (o la que limite `--calidad`) y une
  video y audio mediante FFmpeg.
- El contenedor final puede ser MP4, MKV u otro formato de origen, según los
  códecs disponibles; no recodifica con pérdida.
- Incrusta título, autor, año y carátula en el archivo resultante.
- Muestra el progreso, reintenta fallos transitorios y conserva archivos
  parciales para reanudar al repetir la URL.
- Evita sobrescribir archivos existentes y añade el identificador del video al
  nombre.
- Está pensado para videos individuales; rechaza listas, canales y
  transmisiones en vivo.
- Devuelve código 0 si termina, 1 ante un error y 130 al cancelar. Los
  argumentos incorrectos devuelven 2.

La compatibilidad depende de los extractores de yt-dlp y del acceso que permita
cada sitio. Contenido privado, DRM o bloqueos del sitio pueden impedir una
descarga. No incluye inicio de sesión ni extracción de cookies.

Si un sitio cambia, actualiza el motor con `python py.py --actualizar`.

### Sobre FFmpeg y ffprobe

imageio-ffmpeg aporta FFmpeg pero no ffprobe. Sin ffprobe, la carátula no puede
incrustarse en contenedores MKV, así que en ese caso se omite la carátula en
lugar de perder la descarga; en audio siempre se incrusta. Si quieres la
carátula también en video, instala FFmpeg completo y déjalo en el PATH.

## Arquitectura limpia

`domain.py` define modelos, validaciones, errores y el contrato
`VideoDownloader`. `application.py` implementa los casos de uso y depende solo
del dominio. `infrastructure.py` implementa el contrato con yt-dlp y FFmpeg.
`cli.py` recibe argumentos, presenta resultados y conecta las dependencias. El
motor puede sustituirse sin modificar los casos de uso.

## Desarrollo

```powershell
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m mypy
```

Las pruebas usan dobles en lugar del adaptador real, así que no acceden a la
red ni descargan nada.

## Investigación

- [Documentación oficial y uso desde Python](https://github.com/yt-dlp/yt-dlp#embedding-yt-dlp).
- [Consulta de la comunidad sobre selección de formatos y audio](https://github.com/yt-dlp/yt-dlp/issues/4237).
- [Discusión sobre evaluación de formatos en Python](https://github.com/yt-dlp/yt-dlp/issues/9973).
- [Distribución de FFmpeg con imageio-ffmpeg](https://github.com/imageio/imageio-ffmpeg).

Se aplicaron la API de Python, selección de formatos con alternativa y unión
con FFmpeg; la lógica de descarga queda fuera de la consola.
