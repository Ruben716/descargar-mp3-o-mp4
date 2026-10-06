package com.ruben.descargador_movil.pelis

import android.net.Uri
import com.ruben.descargador_movil.anime.RedAnime
import org.jsoup.Jsoup

/**
 * Fuente de peliculas y series en espanol latino: PelisPlusHD.
 *
 * Solo lee el catalogo y los servidores que la propia web publica. Los
 * servidores son embeds (embed69 y companiia) que se reproducen dentro de la
 * app cargandolos en un iframe, porque muchos no dejan abrirse como pagina
 * principal.
 */
class Pelisplus {

    private val red = RedAnime()

    companion object {
        const val BASE = "https://pelisplushd.bz"
    }

    fun buscar(texto: String): List<Peli> {
        val limpio = texto.trim()
        if (limpio.isEmpty()) return emptyList()
        return parsearTarjetas(red.cuerpo("$BASE/search?s=${Uri.encode(limpio)}", BASE))
    }

    fun peliculas(): List<Peli> = parsearTarjetas(red.cuerpo("$BASE/peliculas", BASE), "Pelicula")

    fun series(): List<Peli> = parsearTarjetas(red.cuerpo("$BASE/series", BASE), "Serie")

    private fun parsearTarjetas(html: String, tipo: String = ""): List<Peli> {
        val doc = Jsoup.parse(html, BASE)
        return doc.select("a.Posters-link").mapNotNull { enlace ->
            val titulo = enlace.selectFirst("p")?.text()?.trim().orEmpty()
            val url = enlace.attr("abs:href").ifEmpty { enlace.attr("href") }
            if (url.isEmpty() || titulo.isEmpty()) return@mapNotNull null
            val imagen = enlace.selectFirst("img")
            val portada = imagen?.attr("abs:data-src").orEmpty()
                .ifEmpty { imagen?.attr("abs:src").orEmpty() }
            val etiqueta = tipo.ifEmpty {
                when {
                    url.contains("/serie/") -> "Serie"
                    url.contains("/pelicula/") -> "Pelicula"
                    else -> ""
                }
            }
            Peli(url = url, titulo = titulo, portada = portada, tipo = etiqueta)
        }.distinctBy { it.url }
    }

    /** Los capitulos de una serie, con su temporada, en orden. */
    fun capitulos(urlSerie: String): List<CapituloPeli> {
        val doc = Jsoup.parse(red.cuerpo(urlSerie, BASE), urlSerie)
        return doc.select("a[href*='/temporada/'][href*='/capitulo/']").mapNotNull { enlace ->
            val href = enlace.attr("abs:href").ifEmpty { enlace.attr("href") }
            val partes = Regex("/temporada/(\\d+)/capitulo/(\\d+)").find(href)
                ?: return@mapNotNull null
            CapituloPeli(
                url = href,
                temporada = partes.groupValues[1],
                numero = partes.groupValues[2],
                titulo = enlace.text().trim().ifEmpty { "Capitulo ${partes.groupValues[2]}" },
            )
        }.distinctBy { it.url }.sortedWith(
            compareBy({ it.temporada.toIntOrNull() ?: 0 }, { it.numero.toIntOrNull() ?: 0 }),
        )
    }

    /** Los servidores (embeds) de una pelicula o de un capitulo. */
    fun servidores(url: String): List<ServidorPeli> {
        val html = red.cuerpo(url, BASE)
        val salida = mutableListOf<ServidorPeli>()

        // El array `video[]` con los reproductores.
        Regex("video\\[(\\d+)\\]\\s*=\\s*'([^']+)'").findAll(html).forEach { coincidencia ->
            val enlace = coincidencia.groupValues[2].trim()
            if (enlace.startsWith("http")) {
                salida.add(ServidorPeli("Servidor ${coincidencia.groupValues[1]}", enlace))
            }
        }

        // Por si la pagina trae algun iframe directo.
        Jsoup.parse(html, url).select("iframe[src]").forEach { marco ->
            val enlace = marco.attr("abs:src").ifEmpty { marco.attr("src") }
            if (enlace.startsWith("http") && !enlace.contains("youtube") && !enlace.contains("facebook")) {
                salida.add(ServidorPeli("Embed", enlace))
            }
        }
        return salida.distinctBy { it.url }
    }
}
