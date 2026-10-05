package com.ruben.descargador_movil.anime

import android.net.Uri
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup

/**
 * Fuente de anime en espanol: JKanime.
 *
 * Solo lee lo que la web ya sirve (catalogo, episodios y la lista de
 * servidores embebida en la pagina). La resolucion del video de cada servidor
 * la hace [Extractores].
 *
 * Las rutas y selectores salen del extensor mantenido de Aniyomi/Kohi-den,
 * que es de donde conviene copiarlos cuando JKanime cambie de HTML.
 */
class Jkanime {

    private val red = RedAnime()

    companion object {
        const val BASE = "https://jkanime.net"
    }

    /**
     * Busca por nombre. La web usa `/buscar/<texto>` y, si redirige, el
     * formulario clasico `/buscar?q=`.
     */
    fun buscar(texto: String): List<AnimeFuente> {
        val limpio = texto.trim()
        if (limpio.isEmpty()) return emptyList()
        val porRuta = "$BASE/buscar/${Uri.encode(limpio)}"
        val lista = parsearResultados(red.cuerpo(porRuta, BASE), porRuta)
        if (lista.isNotEmpty()) return lista
        val porConsulta = "$BASE/buscar?q=${Uri.encode(limpio)}"
        return parsearResultados(red.cuerpo(porConsulta, BASE), porConsulta)
    }

    private fun parsearResultados(html: String, base: String): List<AnimeFuente> {
        val doc = Jsoup.parse(html, base)
        return doc.select("div.anime__item").mapNotNull { item ->
            val enlace = item.selectFirst("h5 a") ?: item.selectFirst("a") ?: return@mapNotNull null
            val titulo = enlace.text().trim()
            val href = enlace.attr("abs:href").ifEmpty { enlace.attr("href") }
            if (titulo.isEmpty() || href.isEmpty()) return@mapNotNull null
            val portada = item.selectFirst(".set-bg")?.attr("abs:data-setbg").orEmpty()
            val tipo = item.selectFirst("li.anime")?.text()?.trim().orEmpty()
            val estado = item.select("ul li").firstOrNull { !it.hasClass("anime") }
                ?.text()?.trim().orEmpty()
            AnimeFuente(url = href, titulo = titulo, portada = portada, tipo = tipo, estado = estado)
        }.distinctBy { it.url }
    }

    /** Lo mas popular, del directorio. Viene en un `var animes = {...}`. */
    fun populares(): List<AnimeFuente> {
        val html = red.cuerpo("$BASE/directorio?filtro=popularidad&p=1", BASE)
        return parsearJsonAnimes(html)
    }

    /** Lo que se esta emitiendo ahora mismo. */
    fun emision(): List<AnimeFuente> {
        val html = red.cuerpo("$BASE/directorio?estado=emision&p=1", BASE)
        return parsearJsonAnimes(html)
    }

    private fun parsearJsonAnimes(html: String): List<AnimeFuente> {
        val coincidencia = Regex(
            """var animes\s*=\s*(\{.*\});""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(html) ?: return emptyList()
        val datos = runCatching { JSONObject(coincidencia.groupValues[1]).optJSONArray("data") }
            .getOrNull() ?: return emptyList()
        val salida = mutableListOf<AnimeFuente>()
        for (i in 0 until datos.length()) {
            val o = datos.optJSONObject(i) ?: continue
            val titulo = o.optString("title").trim()
            val url = absoluta(o.optString("url"))
            if (titulo.isEmpty() || url.isEmpty()) continue
            salida.add(
                AnimeFuente(
                    url = url,
                    titulo = titulo,
                    portada = absoluta(o.optString("image")),
                    tipo = o.optString("type"),
                ),
            )
        }
        return salida
    }

    private fun absoluta(url: String): String = when {
        url.isEmpty() -> ""
        url.startsWith("http") -> url
        else -> BASE + "/" + url.trimStart('/')
    }

    /**
     * Episodios de una ficha. Van por AJAX y con token: hace falta el id del
     * anime y el CSRF de la propia pagina, ademas de la cookie de sesion.
     */
    fun episodios(urlAnime: String): List<EpisodioFuente> {
        val html = red.cuerpo(urlAnime, BASE)
        val doc = Jsoup.parse(html, urlAnime)
        val id = doc.selectFirst("[data-anime]")?.attr("data-anime").orEmpty()
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content").orEmpty()
        if (id.isEmpty() || token.isEmpty()) return emptyList()

        val raiz = urlAnime.trimEnd('/')
        val salida = mutableListOf<EpisodioFuente>()
        var pagina = 1
        var ultima = 1
        // La respuesta trae `last_page` (snake_case): con el se recorren todas.
        do {
            val cuerpo = red.cuerpoPost(
                "$BASE/ajax/episodes/$id/$pagina",
                mapOf("_token" to token),
                urlAnime,
            )
            val json = runCatching { JSONObject(cuerpo) }.getOrNull() ?: break
            ultima = json.optInt("last_page", pagina)
            val datos = json.optJSONArray("data") ?: break
            for (i in 0 until datos.length()) {
                val o = datos.optJSONObject(i) ?: continue
                val numero = o.opt("number")?.toString() ?: continue
                if (numero.isEmpty() || numero == "null") continue
                salida.add(EpisodioFuente(numero = numero, url = "$raiz/$numero/"))
            }
            pagina++
            if (pagina <= ultima) runCatching { Thread.sleep(200) }
        } while (pagina <= ultima && pagina <= 200)
        return salida.distinctBy { it.numero }
    }

    /**
     * Servidores de un episodio, ya decodificados.
     *
     * La pagina los trae en `var servers = [...]`, con la direccion real en
     * base64 dentro de `remote`.
     */
    fun servidores(urlEpisodio: String): List<ServidorFuente> {
        val html = red.cuerpo(urlEpisodio, BASE)
        val salida = mutableListOf<ServidorFuente>()

        // 1) Reproductores internos de JKanime (`jkplayer/um`, `umv`...). Son
        // los que entregan un HLS directo, asi que van primero.
        val idiomaInterno = idiomaDeLaPagina(html)
        Regex("src=\"(https://jkanime\\.net/jkplayer/[^\"]+)\"")
            .findAll(html)
            .map { it.groupValues[1] }
            .filter { it.contains("e=") && !it.contains("'+") && !it.contains("val.remote") }
            .distinct()
            .forEach { salida.add(ServidorFuente(nombre = "JKanime", idioma = idiomaInterno, url = it)) }

        // 2) Servidores externos (respaldo). Los de solo descarga se saltan:
        // abrirlos llevaria a una pagina de descarga, no a un reproductor.
        val coincidencia = Regex("""var servers\s*=\s*(\[.*\]);""").find(html)
        val arreglo = coincidencia?.let { runCatching { JSONArray(it.groupValues[1]) }.getOrNull() }
        if (arreglo != null) {
            for (i in 0 until arreglo.length()) {
                val o = arreglo.optJSONObject(i) ?: continue
                val nombre = o.optString("server")
                val bajo = nombre.lowercase()
                if (bajo.contains("mediafire") || bajo.contains("mega") || bajo.contains("1fichier")) {
                    continue
                }
                val remoto = o.optString("remote")
                if (remoto.isEmpty()) continue
                val url = runCatching {
                    String(Base64.decode(remoto, Base64.DEFAULT), Charsets.UTF_8)
                }.getOrNull()?.trim().orEmpty()
                if (url.isEmpty() || !url.startsWith("http")) continue
                salida.add(
                    ServidorFuente(
                        nombre = nombre.ifEmpty { "Servidor" },
                        idioma = idioma(o.optInt("lang", 1)),
                        url = url,
                    ),
                )
            }
        }
        return salida.distinctBy { it.url }
    }

    /** El idioma que anuncia la propia pagina (Japones sub., latino...). */
    private fun idiomaDeLaPagina(html: String): String {
        val bloque = Regex(
            "<select[^>]*id=\"deflang\"[^>]*>(.*?)</select>",
            RegexOption.DOT_MATCHES_ALL,
        ).find(html)?.groupValues?.get(1) ?: return "Subtitulado"
        val opcion = Regex("<option[^>]*>([^<]+)</option>").find(bloque)
            ?.groupValues?.get(1)?.trim().orEmpty()
        return opcion.ifEmpty { "Subtitulado" }
    }

    private fun idioma(codigo: Int): String = when (codigo) {
        1 -> "Japones subtitulado"
        3 -> "Latino"
        4 -> "Chino"
        else -> "Idioma sin indicar"
    }
}
