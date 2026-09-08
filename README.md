# Descargador por consola

Desde esta carpeta, ejecuta:

```powershell
python py.py
```

Primero aparece este menú:

```text
¿Qué quieres descargar?

  1. Video con audio
  2. Música / audio en MP3
  0. Salir
```

Selecciona `1` o `2` y después pega el enlace en `Ingresa el link:`.
Si te equivocas de opción, el programa vuelve a pedirla.
También puedes descargar video directamente con `python py.py "URL"`.
Para descargar **solo audio en MP3**:

```powershell
python py.py "https://sitio.com/video" --audio
```

También puedes usar `python py.py --audio` y pegar el enlace después.
El audio se convierte a MP3 de 192 kb/s y se guarda en `descargas/audio`.
Con `--destino`, se guarda en la subcarpeta `audio` del destino elegido,
para que la extracción no afecte a videos descargados previamente.
Si el sitio no ofrece una pista de audio separada, se descarga el video
temporalmente y se conserva solo el MP3. Al pasar una URL como argumento sin `--audio`, descarga video con audio.

Los archivos se guardan en `descargas` dentro del directorio desde el que ejecutas el comando.
Usa comillas alrededor de la URL, especialmente si contiene `&`.

```powershell
python py.py "https://sitio.com/video" --destino "D:\Mis videos"
```

## Instalación en otro equipo

Python 3.10 o posterior:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
python py.py
```

El lanzador utiliza automáticamente el entorno `.venv` del proyecto. FFmpeg se incluye mediante imageio-ffmpeg; si ya está en PATH se utiliza esa instalación. Para soporte completo de YouTube, instala Deno o Node.js compatible con yt-dlp. Ambos se detectan automáticamente; en el equipo de desarrollo hay Node.js.

También puedes usar `.\.venv\Scripts\descargar.exe "URL"` o `.\.venv\Scripts\python.exe -m descargador "URL"`.

## Comportamiento

- Selecciona la mejor calidad disponible y une video y audio mediante FFmpeg.
- El contenedor final puede ser MP4, MKV u otro formato de origen, según los códecs disponibles; no recodifica con pérdida.
- Muestra el progreso, reintenta fallos transitorios y conserva archivos parciales para reanudar al repetir la URL.
- Evita sobrescribir archivos existentes y añade el identificador del video al nombre.
- Está pensado para videos individuales; rechaza listas, canales y transmisiones en vivo.
- Devuelve código 0 si termina, 1 ante un error y 130 al cancelar. Los argumentos incorrectos devuelven 2.

La compatibilidad depende de los extractores de yt-dlp y del acceso que permita cada sitio. Contenido privado, DRM o bloqueos del sitio pueden impedir una descarga. No incluye inicio de sesión ni extracción de cookies.

Si un sitio cambia, actualiza el motor:

```powershell
.\.venv\Scripts\python.exe -m pip install --upgrade "yt-dlp[default]"
```

## Arquitectura limpia

`domain.py` define modelos, errores y el contrato `VideoDownloader`. `application.py` implementa el caso de uso y depende solo del dominio. `infrastructure.py` implementa el contrato con yt-dlp y FFmpeg. `cli.py` recibe argumentos, presenta resultados y conecta las dependencias. El motor puede sustituirse sin modificar el caso de uso.

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

## Investigación

- [Documentación oficial y uso desde Python](https://github.com/yt-dlp/yt-dlp#embedding-yt-dlp).
- [Consulta de la comunidad sobre selección de formatos y audio](https://github.com/yt-dlp/yt-dlp/issues/4237).
- [Discusión sobre evaluación de formatos en Python](https://github.com/yt-dlp/yt-dlp/issues/9973).
- [Distribución de FFmpeg con imageio-ffmpeg](https://github.com/imageio/imageio-ffmpeg).

Se aplicaron la API de Python, selección de formatos con alternativa y unión con FFmpeg; la lógica de descarga queda fuera de la consola.
