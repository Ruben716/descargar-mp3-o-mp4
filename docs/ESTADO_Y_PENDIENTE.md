# Tumbao: qué está hecho, qué está a medias y qué falta

Escrito el 13 de octubre de 2026 para poder retomar el trabajo en cualquier sesión, con Claude o a mano.
La rama de trabajo es `claude/music-listening-features-srfqv4`; la que compila el APK es `movil`.

---

## 1. Ya está hecho y en el APK (rama `movil`)

El APK de prueba se publica solo en
<https://github.com/Ruben716/descargar-mp3-o-mp4/releases/tag/apk-prueba> cada vez que algo entra en `movil`.

### Calidad de sonido
- **Formato «Original» de fábrica**: el Opus o AAC de YouTube y SoundCloud se guarda tal cual, sin volver a
  comprimirlo a MP3. La hoja de descarga avisa si lo elegido reconvierte.
- **Jamendo** (FLAC con licencia libre). Usa el secreto `JAMENDO_CLIENT_ID`, ya puesto en GitHub. Su descarga va
  por la dirección oficial, porque la de yt-dlp daba 404 (comprobado contra la red real).
- **Internet Archive** busca en conciertos (etree), netlabels y discos de 78 rpm (Great 78 Project), todo en FLAC.
- **hearthis.at** (sesiones de DJ) y **podcasts** (directorio de Apple + RSS). Cada episodio se baja desde su
  programa para conservar el título.

### Funciones
- **Una pista por capítulo**: un álbum o mix entero sale canción a canción, con título, artista, álbum y número
  de cada una (`--capitulos` en la consola).
- Discos de cada artista en el orden de sus pistas.
- Los audios de más de 20 minutos siguen donde se dejaron.
- Repetir un tramo A-B.
- Radio a partir de una canción, sin red.
- Guardar una lista como `.m3u`.
- Poner una canción como tono de llamada.
- **Radio en vivo** de todo el mundo (Radio Browser): Perú, por géneros, en FLAC (Radio Paradise) y favoritas.
- **Letra traducida al castellano** con la IA del propio teléfono (ML Kit), sin cuenta y sin internet después de
  la primera vez.

### Herramientas
- Flujo **«Prueba de red»** (`.github/workflows/prueba-red.yml` + `.github/prueba_red.py`): prueba las fuentes
  contra internet de verdad en GitHub Actions. Se lanza al cambiar `prueba_red.py` en una rama `claude/**`, o a
  mano desde la pestaña Actions.

---

## 2. Recién integrado (rediseño azul y proveedores nuevos)

Lo construyeron dos agentes en paralelo, lo revisó un tercero que buscaba fallos, y luego se juntó, se corrigió
lo que encontró el revisor y se probó contra internet real con la **Prueba de red**.

### 2.1 Rediseño azul y negro
- Paleta nueva fijada en `movil/lib/tema.dart`: fondo `#05070D`, superficie `#0C1322`, acento azul eléctrico
  `#4D94FF`, cian hielo `#45C8FF`, tinta `#040814`, oro `#FFC857` para los sellos de sin pérdida. Nada sale violeta,
  y una prueba lo comprueba.
- Contrastes WCAG comprobados por otra prueba: el texto tenue pasa de 3,5:1 a 4,7:1 o más.
- **Logo nuevo**: degradado azul #45C8FF → #3A7BFF → #2563FF con la figura en tinta. Se regenera con
  `python movil/herramientas/generar_icono.py` y `dart run flutter_launcher_icons`.
- Resplandor azul en las cabeceras, cifras tabulares, barra de navegación con filete, y atajos, widget y pantalla de
  arranque de Android en azul. En Android 12 o superior ya no sale el fogonazo blanco (`values-v31`).
- Arreglos del revisor:
  - botón grande del reproductor con dos tonos de la carátula;
  - corazón de «Me gusta» que se distingue del sin marcar;
  - pista de los deslizadores al 3:1;
  - fichas que siguen el tinte de la carátula.

### 2.2 Proveedores nuevos (probados contra la red)
- **Wikimedia Commons** (`commons`): audio con licencia libre, bajando el original. Con «Beethoven» bajó un OGG; el
  FLAC sale cuando el original lo es.
- **Internet Archive ampliado**: todo lo de licencia libre, y **dice al buscar si es FLAC de 24 bits** (lo detectó
  en The Open Goldberg Variations y en un concierto de Grateful Dead).
- **ccMixter** (`ccmixter`): MP3 a 320 kb/s con a cappellas e instrumentales. Se salvan su cabecera gigante, su JSON
  roto y su protección de enlaces.
- **YouTube Music** (`ytmusic`): solo canciones, con título, artista y carátula oficiales. Desde los servidores de
  GitHub YouTube pide verificación; desde un teléfono no debería.
- Arreglos encontrados al probar contra la red:
  - **cada pista de un álbum del Archive apuntaba al álbum entero** y no se podía bajar suelta (venía de antes);
  - los fallos de `http.client` se escapaban sin `DownloadError`.
- Arreglos del revisor:
  - «Buscar mejor calidad» ya no ofrece un disco entero como la misma canción;
  - los MIDI de Commons siguen sonando;
  - un error de la API de Commons se dice en vez de «no hay nada»;
  - los errores de YouTube Music llegan en castellano;
  - a igual calidad gana YouTube Music frente al videoclip.

## 3. Pendiente: investigado, falta construir

### 3.1 Portadas en máxima resolución
Datos medidos en `docs/investigacion/portadas.json`. Lo que hay que cambiar en
`descargador/infrastructure.py`:
- `_portada_itunes`: pedir `{N}x{N}bb` hasta **3000** (por encima Apple agranda y no gana nitidez).
- `_portada_deezer`: cambiar `/1000x1000-` por `/1900x1900-` (con 2000 o más da 403).
- `_portada_coverart`: probar `front` (original) o `front-1200`, y si da 404, el `release-group`.
- YouTube Music (`lh3.googleusercontent.com`): cambiar lo que va tras `=` por `=s0` (original) o `=w{N}-h{N}`.
- Bandcamp: `_0` es el original (suele pasar de 1400 px); `_10` = 1200 px.
- **Para incrustar** en el audio: limitar a **1400-1600 px** en JPEG (unos 300-600 KB). La grande, para la pantalla
  del reproductor. Un PNG de 1400 px pesa 2-3,5 MB, así que conviene recomprimir a JPEG.

### 3.2 Nuevas secciones y mejor distribución
Plan completo en `docs/investigacion/secciones.json`. Lo esencial:

**Inicio, de arriba abajo:**
1. Cabecera igual que hoy, más un icono «Explorar».
2. Barra **«Pídele a Tumbao»**, con un ejemplo que cambia con la hora.
3. **Accesos rápidos** en rejilla de 2×3: Me gusta, Lo más escuchado, Sin pérdida, la última lista, Tu radio y el
   Mix del artista más oído.
4. Continuar escuchando (igual).
5. **Hecho para ti**: Mix diario 1 a 3 (semilla = fecha del día), Redescubre (favoritas que no suenan desde hace
   30 días), Sin escuchar todavía.
6. **Recién descargado**, con el sello de calidad.
7. **Tus mixes**: «Mix de <artista>» y, cuando el DJ haya analizado la biblioteca, Para moverse / Tranqui /
   Para concentrarte.
8. **Radio favorita** + tarjeta Radio en vivo.
9. Lo que más oyes, **Sin pérdida**, **Episodios a medias** y Tus listas.
10. Tarjeta final «Explora radio, podcasts y música libre».

**Pantalla Explorar** (`pantalla_explorar.dart`), que se abre con `Navigator.push` y **no** como pestaña, para no
romper pruebas: categorías de colores para Radio, Podcasts, Sin pérdida, Música libre (Jamendo, Commons, ccMixter),
Sesiones de DJ, Conciertos (Archive), YouTube Music y géneros.

**Cuidado con las pruebas** (`movil/test/widget_test.dart`): 57 abren la app entera. Las etiquetas «Inicio»,
«Descargar» y «Biblioteca» y los índices 0, 1 y 2 **no se pueden cambiar**: el ayudante `abrir()` busca
`find.text('Descargar').last`. Y en la pantalla Descargar no puede aparecer un texto exacto «Biblioteca».

### 3.3 DJ automático y «Pídele a Tumbao» (sin coste)
Investigado y con un **prototipo que funciona**: `docs/pendiente/dj_prototipo/` (`ritmo2.py.txt`, con sus pruebas en
`test_ritmo.py.txt`; llevan `.txt` para que ruff no los revise hasta integrarlos), y el diseño completo en `docs/investigacion/dj.json` (con su crítica en `critica_dj.json`).
Medido en un PC: unos 3 s por canción de 4 minutos. En un móvil se estiman 4-6 s en gama media y 12-20 s en gama
baja, así que conviene analizar en segundo plano y por lotes. El plan:
- **BPM y energía de cada canción en el propio teléfono, sin numpy**: FFmpeg decodifica a mono y a pocos hercios;
  Python calcula la energía cada 10 ms, el flujo de ataques y la autocorrelación entre 60 y 200 BPM, corrigiendo
  el doble o la mitad. Se guarda en el catálogo SQLite (subir a la versión 9) y se calcula en segundo plano.
- **Orden DJ**: ordenar la cola para que el tempo y la energía fluyan, con la opción de subir la energía.
- **Fundido al compás**: alinear el fundido que ya existe (`_aplicarFundido` en `estado_reproductor.dart`) con el pulso.
- **Pídele a Tumbao offline**: frases en castellano convertidas en filtros sobre la biblioteca («algo tranquilo para
  dormir», «reggaetón para entrenar», «lo que más escucho de X», «canciones largas», «sin pérdida»).
- Pruebas sin red, con audio sintético generado con `ffmpeg -f lavfi`.

### 3.4 Otras ideas que quedaron fuera
- **Android Auto**: exige pasar de `just_audio_background` a `audio_service`, con un árbol navegable. Mucho trabajo
  y no se puede probar sin coche o sin el simulador de Android Auto.
- **«Pídele a Tumbao» con un modelo de lenguaje de verdad** (Claude): entendería cualquier frase, pero necesita una
  clave de la API de Anthropic y cuesta dinero por uso. Decisión del autor.

---

## 4. Proveedores investigados y descartados (para no repetir el trabajo)

Detalle y fuentes en `docs/investigacion/proveedores.json`:
- **Requieren cuenta o pago**: Funkwhale (casi todos los servidores), Musopen, Freesound (el original), Mirlo (pide
  un email), Monstercat, Audiomack (más de 128 kb/s), YouTube Audio Library y Tidal, Qobuz y Deezer sin pérdida.
- **Cerrados o rotos en 2026**: Nina Protocol (cerró en julio de 2026), API de Free Music Archive (404) y Library of
  Congress (desafío de Cloudflare).
- **Peor calidad que lo que ya hay**: Mixcloud (AAC 64), NTS (sale de SoundCloud o Mixcloud), Vimeo e IMSLP.
- **El original de SoundCloud**: su servidor solo lo da con sesión iniciada (401).
- **Quizás, más adelante**: Europeana (clave gratis), Incompetech (MP3 320), Newgrounds, OpenGameArt y mejoras de
  Bandcamp (lo regalado en FLAC).

---

## 5. Cómo retomarlo con Claude

Abrir una sesión de Claude Code sobre este repositorio y pedirle, por ejemplo:

> Lee docs/ESTADO_Y_PENDIENTE.md y sigue con la sección 3 en este orden: portadas en alta resolución, Inicio nuevo
> con Explorar, y DJ automático con Pídele a Tumbao (parte del prototipo de docs/pendiente/dj_prototipo). Pasa todas
> las comprobaciones de la sección 6 antes de abrir el pull request hacia movil.

Las investigaciones completas (con enlaces, medidas y trampas) están en `docs/investigacion/*.json`.

---

## 6. Comprobaciones antes de juntar nada

```bash
python3 -m ruff check .
python3 -m mypy
python3 -m unittest discover -s tests
cd movil && flutter analyze && flutter test
```

- **Fuentes nuevas**: cambiar `.github/prueba_red.py` en una rama `claude/**` y mirar el resultado del flujo
  «Prueba de red» en Actions.
- **APK**: entra solo al fusionar en `movil` (flujo «APK»). También se puede lanzar a mano desde Actions sobre otra rama.
- **Secretos de GitHub** que usa el flujo: `DEBUG_KEYSTORE` (firma, para instalar encima de la app de siempre) y
  `JAMENDO_CLIENT_ID`.
