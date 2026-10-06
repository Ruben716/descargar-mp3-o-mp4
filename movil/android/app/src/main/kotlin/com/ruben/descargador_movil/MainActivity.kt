package com.ruben.descargador_movil

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.net.Uri
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.util.Rational
import android.util.Size
import android.system.Os
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.util.zip.ZipInputStream
import kotlin.concurrent.thread
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/**
 * Puente Flutter -> Kotlin -> Python.
 *
 * Chaquopy arranca CPython dentro del proceso de la app y el canal deja que
 * Dart invoque el mismo nucleo que usa la version de consola.
 *
 * Hereda de AudioServiceActivity (que a su vez es una FlutterActivity) para
 * que Android reconozca la app como reproductor y muestre sus controles.
 */
class MainActivity : AudioServiceActivity() {

    private val canal = "com.ruben.descargador/nucleo"

    private var canalFlutter: MethodChannel? = null

    @Volatile
    private var ffmpegListo = false

    /** Enlace llegado por Compartir, a la espera de que Flutter lo recoja. */
    @Volatile
    private var urlCompartida: String? = null

    /** Atajo del icono o del widget, a la espera de que Flutter lo atienda. */
    @Volatile
    private var atajoPendiente: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recogerEnlace(intent)
        pedirPermisoNotificaciones()
        // En segundo plano: consulta a MediaStore, y el arranque no puede
        // esperarla. Cuando ya no quede nada que mudar no cuesta nada.
        thread { mudarVideosADcim() }
    }

    /**
     * Al quitar la app de recientes (o salir con atras) se le avisa a Flutter.
     *
     * El motor de Flutter sigue vivo despues, porque lo comparte el servicio de
     * audio, asi que Flutter aun puede parar la musica si estaba en pausa. Sin
     * esto, servicio y notificacion se quedaban vivos con la app «cerrada».
     */
    override fun onDestroy() {
        if (isFinishing) {
            try {
                canalFlutter?.invokeMethod("tareaCerrada", null)
            } catch (error: Throwable) {
                // Sin nadie escuchando no hay nada que parar.
            }
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        recogerEnlace(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        canalFlutter = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
        // El motor sobrevive a la actividad (lo guarda el servicio de audio):
        // mientras viva, el widget le manda sus botones por este canal.
        WidgetTumbao.canalVivo = canalFlutter
        flutterEngine.addEngineLifecycleListener(vigiaDelMotor(applicationContext))
        canalFlutter!!.setMethodCallHandler { llamada, respuesta ->
                when (llamada.method) {
                    "diagnostico" -> enHilo(respuesta) { puente ->
                        asegurarFfmpeg(puente)
                        puente.callAttr("diagnostico").toString()
                    }
                    "informacion" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        enHilo(respuesta) { puente ->
                            puente.callAttr("informacion", url).toString()
                        }
                    }
                    "descargar" -> {
                        val ajustes = Ajustes(
                            url = llamada.argument<String>("url").orEmpty(),
                            soloAudio = llamada.argument<Boolean>("soloAudio") ?: false,
                            calidad = llamada.argument<Int>("calidad") ?: 0,
                            formatoAudio = llamada.argument<String>("formatoAudio") ?: "mp3",
                            bitrate = llamada.argument<String>("bitrate") ?: "192",
                            subtitulos = llamada.argument<String>("subtitulos").orEmpty(),
                            fragmento = llamada.argument<String>("fragmento").orEmpty(),
                            sinPatrocinios = llamada.argument<Boolean>("sinPatrocinios") ?: false,
                            normalizar = llamada.argument<Boolean>("normalizar") ?: false,
                            etiquetasLimpias = llamada.argument<Boolean>("etiquetasLimpias") ?: true,
                            portadaOficial = llamada.argument<Boolean>("portadaOficial") ?: true,
                            avisar = llamada.argument<Boolean>("avisar") ?: true,
                        )
                        enHilo(respuesta) { puente -> descargar(puente, ajustes) }
                    }
                    "buscar" -> {
                        val texto = llamada.argument<String>("texto").orEmpty()
                        val limite = llamada.argument<Int>("limite") ?: 10
                        val fuente = llamada.argument<String>("fuente") ?: "youtube"
                        enHilo(respuesta) { puente ->
                            puente.callAttr("buscar", texto, limite, fuente).toString()
                        }
                    }
                    "previsualizar" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        val soloAudio = llamada.argument<Boolean>("soloAudio") ?: true
                        enHilo(respuesta) { puente ->
                            puente.callAttr("previsualizar", url, soloAudio).toString()
                        }
                    }
                    // Brillo de esta ventana, de 0 a 1. Sin valor solo se lee. Se
                    // toca la ventana y no el ajuste del sistema: al salir del
                    // video la pantalla vuelve sola a su brillo de siempre.
                    "brillo" -> {
                        val valor = llamada.argument<Double>("valor")
                        val ventana = window.attributes
                        if (valor != null) {
                            ventana.screenBrightness = valor.toFloat().coerceIn(0.01f, 1f)
                            window.attributes = ventana
                        }
                        val actual = window.attributes.screenBrightness
                        respuesta.success(if (actual < 0) -1.0 else actual.toDouble())
                    }
                    // Volumen de la musica del telefono, de 0 a 1. Sin valor solo se lee.
                    "volumen" -> {
                        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                        val maximo = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        llamada.argument<Double>("valor")?.let { v ->
                            val nivel = (v.coerceIn(0.0, 1.0) * maximo).roundToInt()
                            // Sin bandera de interfaz: la barra la pinta la app.
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, nivel, 0)
                        }
                        respuesta.success(
                            audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maximo,
                        )
                    }
                    "ventanaFlotante" -> {
                        val ancho = llamada.argument<Int>("ancho") ?: 16
                        val alto = llamada.argument<Int>("alto") ?: 9
                        respuesta.success(entrarEnVentanaFlotante(ancho, alto))
                    }
                    "importarLista" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        enHilo(respuesta) { puente ->
                            puente.callAttr("importar_lista", url).toString()
                        }
                    }
                    "avisarLote" -> {
                        val cantidad = llamada.argument<Int>("cantidad") ?: 0
                        val esAudio = llamada.argument<Boolean>("audio") ?: false
                        ServicioDescarga.avisarLote(this, cantidad, esAudio)
                        respuesta.success("{\"ok\": true}")
                    }
                    // Compartir abre el selector del sistema, asi que va en el
                    // hilo principal y no en uno aparte.
                    "compartirArchivo" -> respuesta.success(
                        compartirArchivo(
                            llamada.argument<String>("uri").orEmpty(),
                            llamada.argument<Boolean>("audio") ?: true,
                        ),
                    )
                    "abrirEnlace" -> respuesta.success(
                        abrirEnlace(llamada.argument<String>("url").orEmpty()),
                    )
                    "compartirEnlace" -> respuesta.success(
                        compartirEnlace(
                            llamada.argument<String>("url").orEmpty(),
                            llamada.argument<String>("titulo").orEmpty(),
                        ),
                    )
                    "etiquetar" -> {
                        val uri = llamada.argument<String>("uri").orEmpty()
                        val titulo = llamada.argument<String>("titulo").orEmpty()
                        val artista = llamada.argument<String>("artista").orEmpty()
                        enHilo(respuesta) { puente ->
                            etiquetar(puente, uri, titulo, artista)
                        }
                    }
                    // Ninguna de las dos pasa por Python: salen de MediaStore.
                    // Listar es ademas lo primero que pide la app al abrir, y
                    // asi ya no arrastra el arranque del motor de descargas.
                    "biblioteca" -> enHiloSuelto(respuesta) { biblioteca() }
                    "eliminar" -> {
                        val uri = llamada.argument<String>("uri").orEmpty()
                        enHiloSuelto(respuesta) { eliminar(uri) }
                    }
                    "caratula" -> {
                        val uri = llamada.argument<String>("uri").orEmpty()
                        enHiloSuelto(respuesta) { caratula(uri) }
                    }
                    "calidad" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        enHilo(respuesta) { puente -> puente.callAttr("calidad", url).toString() }
                    }
                    "precalentar" -> enHilo(respuesta) { puente ->
                        puente.callAttr("precalentar").toString()
                    }
                    // Consulta ligera: Flutter la repite mientras dura la descarga.
                    "progreso" -> enHilo(respuesta) { puente ->
                        puente.callAttr("progreso").toString()
                    }
                    // Flutter la consulta al abrir y al volver del segundo plano.
                    "atajoPendiente" -> {
                        val pendiente = atajoPendiente
                        atajoPendiente = null
                        respuesta.success(pendiente)
                    }
                    "actualizarWidget" -> {
                        WidgetTumbao.actualizar(
                            this,
                            EstadoWidget(
                                titulo = llamada.argument<String>("titulo"),
                                artista = llamada.argument<String>("artista") ?: "",
                                sonando = llamada.argument<Boolean>("sonando") ?: false,
                                caratula = llamada.argument<String>("caratula"),
                            ),
                        )
                        respuesta.success(null)
                    }
                    "urlCompartida" -> {
                        val pendiente = urlCompartida
                        urlCompartida = null
                        respuesta.success(pendiente)
                    }
                    else -> respuesta.notImplemented()
                }
            }
        // La pestania de anime usa un canal propio: no toca el de descargas.
        CanalAnime.registrar(flutterEngine)
        // Y la de peliculas y series, otro.
        CanalPelis.registrar(flutterEngine)
    }

    /** Todo lo que el usuario puede ajustar antes de descargar. */
    private data class Ajustes(
        val url: String,
        val soloAudio: Boolean,
        val calidad: Int,
        val formatoAudio: String,
        val bitrate: String,
        val subtitulos: String,
        val fragmento: String,
        val sinPatrocinios: Boolean,
        val normalizar: Boolean,
        val etiquetasLimpias: Boolean,
        val portadaOficial: Boolean,
        /** En un lote solo avisa la ultima, o saldrian cientos de avisos. */
        val avisar: Boolean,
    )

    /**
     * Descarga con el proceso protegido y deja el resultado en la biblioteca
     * del movil, para que aparezca en la galeria o el reproductor de musica.
     */
    private fun descargar(puente: PyObject, ajustes: Ajustes): String {
        asegurarFfmpeg(puente)
        ServicioDescarga.arrancar(this)
        try {
            var crudo = pedirDescarga(puente, ajustes, "", false)
            if (esMuroAntiRobots(crudo)) {
                // La web reconocio que quien pedia no era un navegador. Se
                // reintenta saliendo por la red del sistema, cuya huella TLS si
                // es la de Chrome, y con las cookies que la propia web le da a
                // un navegador de verdad.
                val dominio = dominioDe(ajustes.url)
                val cookies = if (dominio == null) {
                    null
                } else {
                    archivoDeCookies(cookiesDeNavegador(ajustes.url), dominio)
                }
                crudo = pedirDescarga(puente, ajustes, cookies?.absolutePath.orEmpty(), true)
            }

            val datos = JSONObject(crudo)
            if (!datos.optBoolean("ok")) return crudo

            val origen = datos.optJSONArray("archivos") ?: JSONArray()
            val guardados = JSONArray()
            for (i in 0 until origen.length()) {
                val archivo = File(origen.getString(i))
                guardados.put(exportarABiblioteca(archivo, ajustes.soloAudio) ?: archivo.absolutePath)
                if (ajustes.avisar) {
                    ServicioDescarga.avisarCompletada(this, archivo.name, ajustes.soloAudio)
                }
            }
            // La calidad del origen viaja tal cual: Flutter la guarda para
            // poder decir despues, sin mentir, de donde salio cada cancion.
            return JSONObject()
                .put("ok", true)
                .put("archivos", guardados)
                .put("origen", datos.opt("origen") ?: JSONObject.NULL)
                .toString()
        } finally {
            ServicioDescarga.detener(this)
        }
    }

    /**
     * Encoge la app a una ventana flotante, como hace YouTube.
     *
     * Android la recorta a la proporcion que se le pase, asi que conviene
     * darle la del video para que no salgan franjas negras.
     */
    private fun entrarEnVentanaFlotante(ancho: Int, alto: Int): Boolean {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            return false
        }
        return try {
            // Android rechaza proporciones extremas; se recortan a lo admitido.
            val proporcion = (ancho.toDouble() / alto.toDouble()).coerceIn(0.42, 2.39)
            val parametros = PictureInPictureParams.Builder()
                .setAspectRatio(Rational((proporcion * 1000).toInt(), 1000))
                .build()
            enterPictureInPictureMode(parametros)
        } catch (error: Throwable) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(enVentana: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(enVentana, config)
        // Flutter necesita saberlo para dejar solo el video en pantalla.
        canalFlutter?.invokeMethod("ventanaFlotante", enVentana)
    }

    /**
     * Manda el archivo a otra app.
     *
     * Hace falta conceder permiso de lectura sobre el URI: quien lo reciba no
     * tiene acceso a nuestra biblioteca por su cuenta.
     */
    private fun compartirArchivo(uri: String, esAudio: Boolean): String {
        if (uri.isEmpty()) return fallo("No hay nada que compartir.")
        return try {
            val envio = Intent(Intent.ACTION_SEND).apply {
                type = if (esAudio) "audio/*" else "video/*"
                putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(envio, "Compartir"))
            JSONObject().put("ok", true).toString()
        } catch (error: Throwable) {
            fallo("${error.message}")
        }
    }

    /** Comparte el enlace de algo que todavia no esta descargado. */
    /** Abre la web o la app que la atiende (la de Crunchyroll, por ejemplo). */
    private fun abrirEnlace(url: String): String {
        if (!url.startsWith("https://") && !url.startsWith("http://")) {
            return fallo("Ese enlace no se puede abrir.")
        }
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            JSONObject().put("ok", true).toString()
        } catch (error: Exception) {
            fallo("No hay ninguna app para abrir ese enlace.")
        }
    }

    private fun compartirEnlace(url: String, titulo: String): String {
        if (url.isEmpty()) return fallo("No hay enlace que compartir.")
        return try {
            val envio = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(
                    Intent.EXTRA_TEXT,
                    if (titulo.isEmpty()) url else "$titulo\n$url",
                )
            }
            startActivity(Intent.createChooser(envio, "Compartir"))
            JSONObject().put("ok", true).toString()
        } catch (error: Throwable) {
            fallo("${error.message}")
        }
    }

    private fun fallo(mensaje: String): String =
        JSONObject().put("ok", false).put("error", mensaje).toString()

    /** Lo descargado, leido de la biblioteca del telefono. */
    private fun biblioteca(): String {
        val salida = JSONArray()
        listar(
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            CARPETAS_AUDIO, true, salida,
        )
        listar(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            CARPETAS_VIDEO, false, salida,
        )
        return JSONObject().put("ok", true).put("elementos", salida).toString()
    }

    /**
     * Borra un archivo de la biblioteca.
     *
     * Funciona sin pedir permiso porque los inserto esta misma app y por tanto
     * es su duenia; borrar lo de otras aplicaciones exigiria confirmacion.
     */
    private fun eliminar(uri: String): String {
        return try {
            val borrados = contentResolver.delete(Uri.parse(uri), null, null)
            JSONObject().put("ok", borrados > 0)
                .put("error", if (borrados > 0) "" else "No se pudo borrar el archivo.")
                .toString()
        } catch (error: Throwable) {
            JSONObject().put("ok", false).put("error", "${error.message}").toString()
        }
    }

    /**
     * Devuelve la caratula del archivo en base64.
     *
     * MediaStore la genera a partir de lo incrustado en el MP3 o del primer
     * fotograma del video, asi que la biblioteca se ve sin descargar nada.
     */
    private fun caratula(uri: String): String {
        return try {
            val mapa = contentResolver.loadThumbnail(Uri.parse(uri), Size(512, 512), null)
            val memoria = ByteArrayOutputStream()
            mapa.compress(Bitmap.CompressFormat.JPEG, 82, memoria)
            mapa.recycle()
            JSONObject()
                .put("ok", true)
                .put("imagen", Base64.encodeToString(memoria.toByteArray(), Base64.NO_WRAP))
                .toString()
        } catch (error: Throwable) {
            // Sin caratula la lista sigue funcionando con un icono generico.
            JSONObject().put("ok", true).put("imagen", "").toString()
        }
    }

    private fun listar(
        coleccion: Uri,
        carpetas: List<String>,
        esAudio: Boolean,
        salida: JSONArray,
    ) {
        // Titulo y artista de las etiquetas: el nombre del archivo trae el
        // titulo de YouTube tal cual, con su codigo entre corchetes y todo.
        // «artist» se pide por su nombre porque la constante comun a audio y
        // video no existe antes de Android 11, y la app arranca en el 10.
        val columnas = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DURATION,
            MediaStore.MediaColumns.TITLE,
            MediaStore.Audio.AudioColumns.ARTIST,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        // Las carpetas van en una sola consulta y no en varias: asi el orden por
        // fecha sale mezclado de verdad y lo antiguo no se amontona al final.
        val condicion = carpetas.joinToString(" OR ") {
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
        }
        try {
            contentResolver.query(
                coleccion,
                columnas,
                condicion,
                carpetas.map { "$it/%" }.toTypedArray(),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    salida.put(
                        JSONObject()
                            .put("nombre", cursor.getString(1) ?: "")
                            .put("tamano", cursor.getLong(2))
                            .put("duracion", cursor.getLong(3) / 1000)
                            .put("audio", esAudio)
                            .put("uri", ContentUris.withAppendedId(coleccion, id).toString())
                            .put("titulo", cursor.getString(4) ?: "")
                            .put("artista", cursor.getString(5) ?: "")
                            .put("fecha", cursor.getLong(6)),
                    )
                }
            }
        } catch (error: Throwable) {
            // Una coleccion vacia o inaccesible no debe tumbar la biblioteca.
        }
    }

    /**
     * El tipo del archivo segun su extension.
     *
     * Antes todo audio se registraba como MP3 y todo video como MP4. Con un
     * FLAC, un WAV o un M4A eso es falso, y Android, al ver que la extension no
     * casa con el tipo, puede cambiarle el nombre al archivo al guardarlo.
     */
    private fun tipoDe(archivo: File, esAudio: Boolean): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(archivo.extension.lowercase())
            ?: if (esAudio) "audio/mpeg" else "video/mp4"

    /**
     * Copia el archivo a Musica/ o Peliculas/ mediante MediaStore y borra el
     * temporal. Asi lo ven el resto de apps del telefono.
     */
    private fun exportarABiblioteca(archivo: File, esAudio: Boolean): String? {
        if (!archivo.isFile) return null
        return try {
            val coleccion = if (esAudio) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val carpeta = if (esAudio) CARPETAS_AUDIO.first() else CARPETAS_VIDEO.first()
            val valores = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, archivo.name)
                put(MediaStore.MediaColumns.MIME_TYPE, tipoDe(archivo, esAudio))
                put(MediaStore.MediaColumns.RELATIVE_PATH, carpeta)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val destino = contentResolver.insert(coleccion, valores) ?: return null
            contentResolver.openOutputStream(destino)?.use { salida ->
                archivo.inputStream().use { it.copyTo(salida) }
            } ?: return null

            valores.clear()
            valores.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(destino, valores, null, null)
            archivo.delete()
            // Se devuelve el URI de MediaStore, no la ruta: es lo que la app
            // necesita para poder anadir la pista a una lista suya.
            destino.toString()
        } catch (error: Throwable) {
            // Si la biblioteca falla, el archivo sigue en la carpeta de la app.
            null
        }
    }

    /**
     * Python aqui hace red y disco, asi que nunca puede correr en el hilo
     * principal: Android lanzaria NetworkOnMainThreadException.
     */
    /**
     * Como [enHilo] pero sin pasar por Python.
     *
     * Importa el modulo «puente» cuesta lo suyo la primera vez, y hay trabajos
     * que no lo necesitan para nada: la caratula sale de MediaStore. Pedirlo
     * igualmente hacia que la primera cancion de cada sesion esperase a que
     * arrancara el motor de descargas antes de empezar a sonar.
     */
    private fun enHiloSuelto(
        respuesta: MethodChannel.Result,
        trabajo: () -> String,
    ) {
        thread {
            val salida = try {
                trabajo()
            } catch (error: Throwable) {
                """{"ok": false, "error": "Kotlin: ${error.message}"}"""
            }
            try {
                runOnUiThread { respuesta.success(salida) }
            } catch (error: Throwable) {
                // Nadie escuchando; no debe tumbar el hilo.
            }
        }
    }

    private fun enHilo(
        respuesta: MethodChannel.Result,
        trabajo: (PyObject) -> String,
    ) {
        thread {
            val salida = try {
                trabajo(Python.getInstance().getModule("puente"))
            } catch (error: Throwable) {
                """{"ok": false, "error": "Kotlin: ${error.message}"}"""
            }
            // Si la app se cerro mientras descargaba ya no hay a quien
            // responder, pero el trabajo si termino: no debe tumbar el hilo.
            try {
                runOnUiThread { respuesta.success(salida) }
            } catch (error: Throwable) {
                // Nadie escuchando; la descarga quedo guardada igualmente.
            }
        }
    }

    private fun recogerEnlace(intent: Intent?) {
        intent?.getStringExtra("atajo")?.let {
            atajoPendiente = it
            // Que no se repita al recrear la actividad (al girar, por ejemplo).
            intent.removeExtra("atajo")
        }
        if (intent?.action != Intent.ACTION_SEND) return
        val texto = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        // Lo compartido suele traer titulo y enlace juntos; se queda el enlace.
        urlCompartida = texto.split(Regex("\\s+")).firstOrNull { it.startsWith("http") } ?: texto
    }

    private fun pedirPermisoNotificaciones() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val concedido = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
        if (concedido != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    private fun carpetaTrabajo(): File =
        (getExternalFilesDir(null) ?: filesDir).resolve("descargas").apply { mkdirs() }

    /**
     * Deja FFmpeg utilizable y se lo comunica a Python. Solo la primera vez.
     */
    @Synchronized
    private fun asegurarFfmpeg(puente: PyObject) {
        if (ffmpegListo) return
        val nativos = applicationInfo.nativeLibraryDir
        val librerias = extraerLibreriasFfmpeg(nativos)

        // Android solo ejecuta binarios desde la carpeta de librerias nativas,
        // donde llegan con nombre libffmpeg.so. yt-dlp busca ficheros llamados
        // "ffmpeg" y "ffprobe", asi que se enlazan con esos nombres.
        val bin = File(filesDir, "bin").apply { mkdirs() }
        enlazar(File(nativos, "libffmpeg.so"), File(bin, "ffmpeg"))
        enlazar(File(nativos, "libffprobe.so"), File(bin, "ffprobe"))

        puente.callAttr("preparar", bin.absolutePath, librerias.absolutePath)
        ffmpegListo = true
    }

    /**
     * libffmpeg.zip.so es un ZIP con libavcodec y demas. Se descomprime una vez
     * en el almacenamiento de la app; de ahi las carga el ejecutable.
     */
    private fun extraerLibreriasFfmpeg(nativos: String): File {
        val raiz = File(filesDir, "ffmpeg")
        val destino = File(raiz, "usr/lib")
        val marca = File(raiz, ".completo")
        // La marca guarda de que instalacion salieron las librerias: al
        // actualizar la app cambia la ruta nativa y hay que volver a extraer.
        if (marca.exists() && marca.readText() == nativos) return destino

        raiz.deleteRecursively()
        raiz.mkdirs()
        ZipInputStream(FileInputStream(File(nativos, "libffmpeg.zip.so"))).use { zip ->
            var entrada = zip.nextEntry
            while (entrada != null) {
                val salida = File(raiz, entrada.name)
                if (entrada.isDirectory) {
                    salida.mkdirs()
                } else {
                    salida.parentFile?.mkdirs()
                    salida.outputStream().use { zip.copyTo(it) }
                }
                entrada = zip.nextEntry
            }
        }
        marca.writeText(nativos)
        return destino
    }

    /**
     * Reescribe titulo y artista de una pista y la renombra.
     *
     * El archivo de verdad vive en MediaStore y solo se llega a el por un
     * descriptor, asi que no se puede etiquetar en el sitio: se saca una copia,
     * Python la reetiqueta con FFmpeg y el resultado vuelve a su lugar. Al
     * final se renombra, que es lo que se ve en la biblioteca y lo que permite
     * agrupar por artista.
     */
    private fun etiquetar(puente: PyObject, uri: String, titulo: String, artista: String): String {
        if (uri.isEmpty()) return fallo("No se indico que pista etiquetar.")
        asegurarFfmpeg(puente)
        val destino = Uri.parse(uri)
        val nombre = nombreDe(destino) ?: return fallo("Esa pista ya no esta en el telefono.")
        val extension = nombre.substringAfterLast('.', "mp3")

        val entrada = File(cacheDir, "etiquetas_entra.$extension")
        val salida = File(cacheDir, "etiquetas_sale.$extension")
        return try {
            entrada.delete()
            salida.delete()
            contentResolver.openInputStream(destino).use { origen ->
                if (origen == null) return fallo("No se pudo abrir la pista.")
                entrada.outputStream().use { origen.copyTo(it) }
            }

            val crudo = puente.callAttr(
                "etiquetar",
                entrada.absolutePath,
                salida.absolutePath,
                titulo,
                artista,
                nombre,
            ).toString()
            val datos = JSONObject(crudo)
            if (!datos.optBoolean("ok")) return crudo

            // El «wt» vacia el archivo antes de escribir: sin el, un audio mas
            // corto dejaria basura del anterior pegada al final.
            contentResolver.openOutputStream(destino, "wt").use { hueco ->
                if (hueco == null) return fallo("No se pudo guardar la pista etiquetada.")
                salida.inputStream().use { it.copyTo(hueco) }
            }

            val nuevo = datos.optString("nombre", nombre)
            JSONObject().put("ok", true).put("nombre", renombrar(destino, nuevo) ?: nombre).toString()
        } catch (error: Throwable) {
            fallo("${error.message}")
        } finally {
            entrada.delete()
            salida.delete()
        }
    }

    /**
     * Cookies que la web le entrega a un navegador de verdad.
     *
     * Hay webs (TikTok) que sirven un muro anti-robots de medio kilobyte en vez
     * de la pagina, porque la peticion no viene de un navegador. yt-dlp lo
     * resolveria imitando su huella, pero eso pide curl_cffi y para Android no
     * existe. El WebView del sistema si es Chromium de verdad, asi que se le
     * deja abrir la pagina y se recoge lo que la web le dio.
     *
     * No es iniciar sesion: son las cookies que se reparten a cualquier
     * visitante. Nunca se pide usuario ni contrasenia.
     */
    private fun cookiesDeNavegador(url: String): String {
        val listo = java.util.concurrent.CountDownLatch(1)
        var recogidas = ""
        runOnUiThread {
            try {
                val vista = WebView(this)
                vista.settings.javaScriptEnabled = true
                vista.settings.domStorageEnabled = true
                val galletas = CookieManager.getInstance()
                galletas.setAcceptCookie(true)
                galletas.setAcceptThirdPartyCookies(vista, true)
                vista.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(vistaWeb: WebView?, cargada: String?) {
                        recogidas = galletas.getCookie(cargada ?: url).orEmpty()
                        galletas.flush()
                        vistaWeb?.destroy()
                        listo.countDown()
                    }
                }
                vista.loadUrl(url)
            } catch (error: Throwable) {
                listo.countDown()
            }
        }
        // Si la pagina se atasca no se espera indefinidamente: sin cookies se
        // sigue como antes y el fallo sera el de siempre, no uno peor.
        listo.await(25, java.util.concurrent.TimeUnit.SECONDS)
        return recogidas
    }

    /**
     * Deja las cookies en el formato Netscape que entiende yt-dlp.
     *
     * Es un archivo de texto con siete columnas separadas por tabuladores. El
     * dominio va con punto delante para que valga tambien en los subdominios.
     */
    private fun archivoDeCookies(cookies: String, dominio: String): File? {
        val pares = cookies.split(';')
            .mapNotNull { trozo ->
                val corte = trozo.indexOf('=')
                if (corte <= 0) null else trozo.take(corte).trim() to trozo.substring(corte + 1).trim()
            }
            .filter { it.first.isNotEmpty() }
        if (pares.isEmpty()) return null

        val caduca = (System.currentTimeMillis() / 1000) + 86_400
        val destino = File(cacheDir, "cookies_${dominio.replace('.', '_')}.txt")
        return try {
            destino.bufferedWriter().use { salida ->
                salida.write("# Netscape HTTP Cookie File\n")
                for ((nombre, valor) in pares) {
                    salida.write(".$dominio\tTRUE\t/\tTRUE\t$caduca\t$nombre\t$valor\n")
                }
            }
            destino
        } catch (error: Throwable) {
            null
        }
    }

    /** El dominio principal de una URL, para etiquetar sus cookies. */
    private fun dominioDe(url: String): String? {
        val anfitrion = try {
            Uri.parse(url).host
        } catch (error: Throwable) {
            null
        } ?: return null
        val partes = anfitrion.split('.')
        return if (partes.size >= 2) partes.takeLast(2).joinToString(".") else anfitrion
    }

    private fun pedirDescarga(
        puente: PyObject,
        ajustes: Ajustes,
        cookies: String,
        nativo: Boolean,
    ): String =
        puente.callAttr(
            "descargar",
            ajustes.url,
            carpetaTrabajo().absolutePath,
            ajustes.soloAudio,
            ajustes.calidad,
            ajustes.formatoAudio,
            ajustes.bitrate,
            ajustes.subtitulos,
            ajustes.fragmento,
            ajustes.sinPatrocinios,
            ajustes.normalizar,
            ajustes.etiquetasLimpias,
            cookies,
            nativo,
            ajustes.portadaOficial,
        ).toString()

    /** Si el fallo huele a que la web sirvio un muro en vez de la pagina. */
    private fun esMuroAntiRobots(crudo: String): Boolean {
        val datos = try {
            JSONObject(crudo)
        } catch (error: Throwable) {
            return false
        }
        if (datos.optBoolean("ok")) return false
        val error = datos.optString("error").lowercase()
        return error.contains("unexpected response") || error.contains("challenge")
    }

    private fun nombreDe(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (error: Throwable) {
            null
        }
    }

    /** Renombra en MediaStore. Devuelve el nombre que quedo, o null si no pudo. */
    private fun renombrar(uri: Uri, nombre: String): String? {
        if (nombre.isEmpty()) return null
        return try {
            val valores = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, nombre)
            }
            if (contentResolver.update(uri, valores, null, null) > 0) nombre else null
        } catch (error: Throwable) {
            // Suele ser que ya hay otra pista con ese nombre. Las etiquetas de
            // dentro ya se escribieron, asi que se deja el nombre viejo.
            null
        }
    }

    /**
     * Lleva a DCIM los videos que se guardaron en Movies.
     *
     * Los de antes seguirian sin verse en la galeria, y mudarlos es la unica
     * forma de que salgan. Solo alcanza a los que inserto esta app, que son
     * los suyos; si alguno se resiste se queda donde esta y no pasa nada,
     * porque la biblioteca sigue leyendo las carpetas viejas igualmente.
     */
    private fun mudarVideosADcim() {
        val coleccion = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val viejas = CARPETAS_VIDEO.drop(1)
        val condicion = viejas.joinToString(" OR ") {
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
        }
        try {
            contentResolver.query(
                coleccion,
                arrayOf(MediaStore.MediaColumns._ID),
                condicion,
                viejas.map { "$it/%" }.toTypedArray(),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val destino = ContentUris.withAppendedId(coleccion, cursor.getLong(0))
                    try {
                        val valores = ContentValues().apply {
                            put(MediaStore.MediaColumns.RELATIVE_PATH, CARPETAS_VIDEO.first())
                        }
                        contentResolver.update(destino, valores, null, null)
                    } catch (error: Throwable) {
                        // De otra app, abierto o con el nombre ya ocupado.
                    }
                }
            }
        } catch (error: Throwable) {
            // Sin permiso o con MediaStore ocupado: se reintenta al abrir otra vez.
        }
    }

    private fun enlazar(origen: File, enlace: File) {
        try {
            // Ojo: exists() sigue el enlace, asi que devuelve false cuando esta
            // roto (pasa en cada reinstalacion, porque cambia la ruta nativa) y
            // el enlace viejo se quedaria ahi haciendo fallar a symlink.
            enlace.delete()
            Os.symlink(origen.absolutePath, enlace.absolutePath)
        } catch (error: Throwable) {
            // Sin enlace simbolico se seguira pudiendo descargar: yt-dlp acepta
            // la ruta directa al ejecutable, solo se pierde ffprobe.
        }
    }

    private companion object {
        /**
         * Un unico vigilante para todo el proceso: la actividad se recrea y
         * configureFlutterEngine se repite con el mismo motor, y el motor
         * guarda sus vigilantes en un conjunto, asi que no se duplica.
         */
        private var vigia: FlutterEngine.EngineLifecycleListener? = null

        private fun vigiaDelMotor(contexto: Context): FlutterEngine.EngineLifecycleListener =
            vigia ?: object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}

                override fun onEngineWillDestroy() {
                    WidgetTumbao.alMorirFlutter(contexto)
                }
            }.also { vigia = it }

        /**
         * Carpetas de la biblioteca del telefono, de la actual a la mas vieja.
         *
         * Lo nuevo se guarda siempre en la primera; las demas se siguen leyendo
         * para que lo descargado antes de que la app se llamase Tumbao no
         * desaparezca de la biblioteca de un dia para otro.
         */
        val CARPETAS_AUDIO = listOf("Music/Tumbao", "Music/Descargador")

        /**
         * El video va a DCIM y no a Movies, que seria su sitio natural.
         *
         * Movies queda escondido: Google Fotos y la galeria del telefono
         * enseniaan por defecto lo que hay en DCIM y en Pictures, y lo demas lo
         * dejan enterrado en «carpetas del dispositivo». Guardado en DCIM sale
         * como un album mas, que es donde la gente lo busca. Con la musica no
         * pasa porque Music si es la carpeta que miran los reproductores.
         */
        val CARPETAS_VIDEO = listOf("DCIM/Tumbao", "Movies/Tumbao", "Movies/Descargador")
    }
}
