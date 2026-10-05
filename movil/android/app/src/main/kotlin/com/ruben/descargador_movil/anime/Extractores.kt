package com.ruben.descargador_movil.anime

import dev.datlag.jsunpacker.JsUnpacker
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.jsoup.Jsoup

/**
 * Resuelve la direccion reproducible de un servidor de video.
 *
 * Es la pieza que ni yt-dlp ni Chaquopy cubrian: los hostings (Streamtape,
 * Mp4upload...) esconden el enlace real detras de su reproductor. La logica
 * esta portada de los extractores de Aniyomi (Apache-2.0).
 *
 * Si un servidor no se sabe resolver se devuelve null y la app ofrece abrirlo
 * en el navegador, en vez de dejar al usuario sin nada.
 */
object Extractores {

    fun resolver(red: RedAnime, url: String): StreamResuelto? {
        val anfitrion = runCatching { java.net.URI(url).host.orEmpty().lowercase() }.getOrDefault("")
        val bajo = url.lowercase()
        return when {
            anfitrion.contains("mp4upload") -> mp4upload(red, url)

            anfitrion.contains("jkanime") && bajo.contains("/jkplayer/") -> jkplayer(red, url)

            anfitrion.contains("jkanime") && (bajo.contains("um.php") || bajo.contains("/um?")) ->
                desu(red, url)

            anfitrion.contains("jkanime") && (bajo.contains("um2.php") || bajo.contains("nozomi")) ->
                nozomi(red, url)

            anfitrion.contains("jkanime") && bajo.contains("jkmedia") -> desuka(red, url)

            else -> null
        }
    }

    /** Los enlaces internos `jkplayer` de JKanime sueltan un HLS directo. */
    private fun jkplayer(red: RedAnime, url: String): StreamResuelto? {
        val html = red.cuerpo(url, "$BASES/")
        Regex("https?://[^\"'\\s\\\\]+\\.m3u8[^\"'\\s\\\\]*").find(html)?.value?.let {
            return StreamResuelto(it, mapOf("Referer" to "$BASES/"))
        }
        Regex("https?://[^\"'\\s\\\\]+\\.mp4[^\"'\\s\\\\]*").find(html)?.value?.let {
            return StreamResuelto(it, mapOf("Referer" to "$BASES/"))
        }
        return null
    }

    /** Mp4upload publica el `player.src(...)`; a veces va empaquetado (eval). */
    private fun mp4upload(red: RedAnime, url: String): StreamResuelto? {
        val doc = Jsoup.parse(red.cuerpo(url, "https://mp4upload.com/"), url)
        val script = doc.selectFirst("script:containsData(eval):containsData(p,a,c,k,e,d)")
            ?.data()
            ?.let(JsUnpacker::unpackAndCombine)
            ?: doc.selectFirst("script:containsData(player.src)")?.data()
            ?: return null
        val video = script.substringAfter(".src(").substringBefore(")")
            .substringAfter("src:").substringAfter('"').substringBefore('"')
        if (video.length < 12 || !video.startsWith("http")) return null
        return StreamResuelto(video, mapOf("Referer" to "https://mp4upload.com/"))
    }

    /** Los reproductores propios de JKanime (`um.php`) traen `var parts = {url: '...'}`. */
    private fun desu(red: RedAnime, url: String): StreamResuelto? {
        val doc = Jsoup.parse(red.cuerpo(url, url), url)
        val script = doc.selectFirst("script:containsData(var parts = {)")?.data() ?: return null
        val video = script.substringAfter("url: '", "").substringBefore("'")
        if (video.length < 12) return null
        return StreamResuelto(video, mapOf("Referer" to url))
    }

    /** Nozomi pide un POST intermedio para canjear la clave. */
    private fun nozomi(red: RedAnime, url: String): StreamResuelto? {
        val doc = Jsoup.parse(red.cuerpo(url, url), url)
        val clave = doc.select("form input[value]").attr("value")
        if (clave.isEmpty()) return null

        val cuerpo = ("data=" + urlCodificar(clave))
            .toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val peticion = Request.Builder()
            .url("$BASES/gsplay/redirect_post.php")
            .header("User-Agent", RedAnime.AGENTE)
            .header("Referer", url)
            .post(cuerpo)
            .build()
        val destino = red.cliente.newCall(peticion).execute().use { it.request.url.toString() }
        val postKey = destino.substringAfter("player.html#", "")
        if (postKey.isEmpty()) return null

        val cuerpoDos = ("v=" + urlCodificar(postKey))
            .toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val respuesta = red.cliente.newCall(
            Request.Builder()
                .url("$BASES/gsplay/api.php")
                .header("User-Agent", RedAnime.AGENTE)
                .post(cuerpoDos)
                .build(),
        ).execute().use { it.body?.string().orEmpty() }
        val file = runCatching { JSONObject(respuesta).optString("file") }.getOrDefault("")
        if (file.length < 12) return null
        return StreamResuelto(file)
    }

    /** Los `jkmedia` devuelven un DPlayer (o el video directo, segun el caso). */
    private fun desuka(red: RedAnime, url: String): StreamResuelto? {
        val respuesta = red.respuesta(url, url)
        val tipo = respuesta.header("Content-Type").orEmpty()
        val cuerpo = respuesta.use { it.body?.string().orEmpty() }
        if (tipo.startsWith("video/")) return StreamResuelto(url, mapOf("Referer" to url))
        val doc = Jsoup.parse(cuerpo, url)
        val script = doc.selectFirst("script:containsData(new DPlayer({)")?.data() ?: return null
        val video = script.substringAfter("url: '", "").substringBefore("'")
        if (video.length < 12) return null
        return StreamResuelto(video, mapOf("Referer" to url))
    }

    private const val BASES = "https://jkanime.net"
}
