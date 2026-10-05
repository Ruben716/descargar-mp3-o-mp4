package com.ruben.descargador_movil.anime

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.util.concurrent.TimeUnit

/**
 * Cliente HTTP de la fuente de anime.
 *
 * Guarda las cookies en memoria porque JKanime mete el token CSRF en una
 * cookie de sesion: sin conservarla, el POST que devuelve los episodios
 * respondia 419. Se hace con la huella de un navegador movil porque algunas
 * de estas webs rechazan a quien no lo parece.
 */
class RedAnime {

    private val galletas = object : CookieJar {
        private val guardadas = HashMap<String, List<Cookie>>()

        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            if (cookies.isNotEmpty()) guardadas[url.host] = cookies
        }

        override fun loadForRequest(url: HttpUrl): List<Cookie> = guardadas[url.host].orEmpty()
    }

    val cliente: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(galletas)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    fun peticion(url: String, referer: String? = null): Request {
        val constructor = Request.Builder()
            .url(url)
            .header("User-Agent", AGENTE)
            .header("Accept-Language", "es-ES,es;q=0.9,en;q=0.8")
            .header("Accept", "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8")
        if (referer != null) constructor.header("Referer", referer)
        return constructor.build()
    }

    fun respuesta(url: String, referer: String? = null): Response =
        cliente.newCall(peticion(url, referer)).execute()

    fun cuerpo(url: String, referer: String? = null): String =
        respuesta(url, referer).use { it.body?.string().orEmpty() }

    /** POST de formulario con cabeceras y cookies; devuelve el cuerpo. */
    fun cuerpoPost(
        url: String,
        campos: Map<String, String>,
        referer: String? = null,
        cabeceras: Map<String, String> = emptyMap(),
    ): String {
        val datos = campos.entries.joinToString("&") { (clave, valor) ->
            "${urlCodificar(clave)}=${urlCodificar(valor)}"
        }
        val cuerpo: RequestBody = datos.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val constructor = Request.Builder()
            .url(url)
            .header("User-Agent", AGENTE)
            .header("Accept-Language", "es-ES,es;q=0.9")
            .header("X-Requested-With", "XMLHttpRequest")
            .post(cuerpo)
        if (referer != null) constructor.header("Referer", referer)
        cabeceras.forEach { (clave, valor) -> constructor.header(clave, valor) }
        return cliente.newCall(constructor.build()).execute().use { it.body?.string().orEmpty() }
    }

    companion object {
        const val AGENTE =
            "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    }
}

/** Codifica como formulario (los espacios salen como %20, no como +). */
fun urlCodificar(texto: String): String =
    java.net.URLEncoder.encode(texto, "UTF-8").replace("+", "%20")
