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

## 2. A medias: hecho por los agentes pero todavía SIN juntar

Dos agentes trabajaron en copias aisladas del código. Su trabajo está guardado como parches en
`docs/pendiente/`, porque esas copias viven en el contenedor y se pierden si se cierra la sesión.

| Parche | Qué trae | Estado |
|---|---|---|
| `docs/pendiente/diseno_commits.patch` | Rediseño azul y negro (7 commits) | Listo para aplicar y revisar |
| `docs/pendiente/proveedores_commits.patch` | Fuentes nuevas de alta calidad (7 commits) | Listo para aplicar y revisar |

### Cómo aplicarlos

```bash
git checkout claude/music-listening-features-srfqv4
git pull
git am docs/pendiente/proveedores_commits.patch   # primero el núcleo
git am docs/pendiente/diseno_commits.patch        # luego la app
# Si «git am» choca en un archivo: arreglar el conflicto, «git add» y «git am --continue».
```

Después hay que pasar todas las comprobaciones (sección 6) y, para las fuentes nuevas, la **Prueba de red**.

### 2.1 Rediseño azul y negro (`diseno_commits.patch`)
Commits, del primero al último:
1. Tema azul y negro con el esquema de color fijado, para que nada salga violeta.
2. Los colores sueltos pasan a los tokens del tema.
3. El texto pequeño de apoyo se lee con el gris tenue (contraste WCAG AA).
4. Cifras tabulares en el contador y en el sello de calidad.
5. Resplandor azul detrás de la cabecera de Inicio y Biblioteca.
6. Atajos, widget y arranque de Android en azul y negro.
7. El icono pasa al degradado azul de la marca (#45C8FF → #3A7BFF → #2563FF, figura en tinta #040814).

La paleta completa, con su hex y su uso, está en `docs/investigacion/diseno.json`. Principales tokens:
fondo `#05070D`, superficie `#0C1322`, superficieAlta `#152036`, acento `#4D94FF`, acentoHielo `#45C8FF`,
tinta `#040814`, oro `#FFC857` (sellos de sin pérdida), peligro `#FF5D5D` y exito `#57D9A3`.

**Revisar al aplicarlo.** El crítico encontró esto antes de que se construyera; ver
`docs/investigacion/critica_diseno.json`:
- **No** cambiar `_BotonGrande` de `reproductor.dart` a `[secondary, primary]`: con portadas azules sale casi gris.
  Mantener `[primary, tertiary]`.
- Arranque de Android 12 o superior: faltan `values-v31/styles.xml` y `values-night-v31/styles.xml`
  (`android:windowSplashScreenBackground` = `#05070D`). Sin ellos sigue saliendo un fogonazo blanco al abrir.
- `generar_icono.py`: nada de varias sentencias en una línea con `;`, porque ruff da E702 y rompe el CI.
- Los colores que usa `ListaAuto` tienen que ser `static const` en `Tema` (`meGusta`, `exito`, `oro`…).
- El botón «Eliminar» del diálogo de borrado de `pantalla_biblioteca.dart` debe ir en `Tema.peligro`.
- Los `ChoiceChip` que fijan `selectedColor` a mano (biblioteca, hoja_ajustes, descarga) hay que cambiarlos ahí.

### 2.2 Proveedores nuevos (`proveedores_commits.patch`)
1. Los fallos de `http.client` también salen como `DownloadError` (antes una cabecera enorme rompía la app).
2. Escuchar antes de bajar acepta formatos sin protocolo declarado.
3. **Wikimedia Commons** (`commons`): FLAC y WAV con licencia libre, bajando el original y no la copia Ogg.
4. **Internet Archive** busca todo lo de licencia libre y dice si es FLAC de 24 bits.
5. **ccMixter** (`ccmixter`), con un extractor propio.
6. **YouTube Music** (`ytmusic`): solo canciones, con título, artista y carátula oficiales.
7. Las tres fuentes nuevas aparecen en el buscador de la app.

**Antes de darlas por buenas**, lanzar la **Prueba de red** en GitHub Actions. El agente añadió las comprobaciones
a `.github/prueba_red.py`. Trampas ya conocidas (en `docs/investigacion/proveedores.json`, campo `notas`):
- **Commons** da 403 si se finge ser un navegador: hay que usar un User-Agent propio.
- **ccMixter**: su cabecera X-JSON pasa de 64 KB (`http.client.LineTooLong`). Su JSON trae ceros a la izquierda
  (`strict=False`) y hay que mandar `Referer: https://ccmixter.org/`.

---

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
El agente de investigación del DJ no llegó a entregar su informe. El plan, para retomarlo:
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

> Lee docs/ESTADO_Y_PENDIENTE.md. Aplica los parches de docs/pendiente con las correcciones de la sección 2.1, pasa
> todas las comprobaciones, lanza la Prueba de red para las fuentes nuevas y, si todo sale bien, abre el pull request
> hacia movil. Después sigue con la sección 3 en este orden: portadas, Inicio + Explorar y DJ + Pídele.

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
