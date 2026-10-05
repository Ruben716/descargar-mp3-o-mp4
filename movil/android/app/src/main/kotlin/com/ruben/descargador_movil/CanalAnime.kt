package com.ruben.descargador_movil

import android.os.Handler
import android.os.Looper
import com.ruben.descargador_movil.anime.Extractores
import com.ruben.descargador_movil.anime.Jkanime
import com.ruben.descargador_movil.anime.RedAnime
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Canal propio para la pestania de anime.
 *
 * Va en un MethodChannel aparte del de descargas a proposito: asi no se toca
 * el manejador que ya funciona para musica y video. Todo el trabajo de red
 * ocurre fuera del hilo de interfaz y siempre devuelve una cadena JSON, igual
 * que el puente de Python.
 */
object CanalAnime {

    private const val CANAL = "com.ruben.descargador/anime"

    fun registrar(engine: FlutterEngine) {
        val principal = Handler(Looper.getMainLooper())
        val jkanime = Jkanime()
        val red = RedAnime()

        MethodChannel(engine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { llamada, respuesta ->
                Thread {
                    val salida = try {
                        atender(llamada, jkanime, red)
                    } catch (error: Throwable) {
                        fracaso("Kotlin: ${error.message}")
                    }
                    principal.post { runCatching { respuesta.success(salida) } }
                }.start()
            }
    }

    private fun atender(llamada: MethodCall, jkanime: Jkanime, red: RedAnime): String =
        when (llamada.method) {
            "buscar" ->
                lista("animes", jkanime.buscar(llamada.argument<String>("texto").orEmpty()))
            "populares" -> lista("animes", jkanime.populares())
            "emision" -> lista("animes", jkanime.emision())
            "episodios" ->
                lista("episodios", jkanime.episodios(llamada.argument<String>("url").orEmpty()))
            "servidores" ->
                lista("servidores", jkanime.servidores(llamada.argument<String>("url").orEmpty()))
            "resolver" -> resolver(red, llamada.argument<String>("url").orEmpty())
            else -> fracaso("Metodo desconocido: ${llamada.method}")
        }

    private fun resolver(red: RedAnime, url: String): String {
        if (url.isEmpty()) return fracaso("Falta la direccion del servidor.")
        val resuelto = Extractores.resolver(red, url)
            ?: return fracaso(
                "Este servidor no se puede abrir dentro de la app. " +
                    "Usa «Abrir en el navegador».",
            )
        val cabeceras = JSONObject()
        resuelto.cabeceras.forEach { (clave, valor) -> cabeceras.put(clave, valor) }
        return JSONObject()
            .put("ok", true)
            .put("url", resuelto.url)
            .put("cabeceras", cabeceras)
            .toString()
    }

    private fun <T> lista(clave: String, datos: List<T>, aJson: (T) -> JSONObject): String {
        val arreglo = JSONArray()
        for (dato in datos) arreglo.put(aJson(dato))
        return JSONObject().put("ok", true).put(clave, arreglo).toString()
    }

    private fun fracaso(mensaje: String): String =
        JSONObject().put("ok", false).put("error", mensaje.ifBlank { "Error desconocido." }).toString()
}
