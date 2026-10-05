import 'dart:async';

import 'package:flutter/foundation.dart';

import 'anime.dart';
import 'nucleo.dart';

/// Un canal de YouTube que sube anime con permiso de quien tiene los derechos.
@immutable
class CanalOficial {
  const CanalOficial({required this.nombre, required this.handle, required this.idioma});

  final String nombre;

  /// El @ del canal en YouTube.
  final String handle;
  final String idioma;

  String buscarUrl(String consulta) =>
      'https://www.youtube.com/$handle/search?query=${Uri.encodeQueryComponent(consulta)}';

  String get listasUrl => 'https://www.youtube.com/$handle/playlists';
}

/// Lo que se puede ver gratis de un anime en los canales oficiales.
@immutable
class OfertaGratis {
  const OfertaGratis({this.series = const <Resultado>[], this.episodios = const <Resultado>[]});

  /// Listas de reproduccion: una temporada o una serie entera.
  final List<Resultado> series;

  /// Episodios sueltos, ya de duracion completa.
  final List<Resultado> episodios;

  bool get vacia => series.isEmpty && episodios.isEmpty;
}

/// Anime gratis y legal: solo de canales oficiales, nunca de resubidas.
///
/// Buscar en todo YouTube no sirve: lo primero que sale son copias subidas
/// por cualquiera. Por eso se busca *dentro* de cada canal de la lista, que
/// son de los propios estudios o de quien tiene la licencia en la region.
/// Muse Asia y Ani-One no estan: desde America sus videos no se pueden ver.
class CanalesOficiales {
  CanalesOficiales._();

  static const List<CanalOficial> canales = <CanalOficial>[
    CanalOficial(nombre: 'TMS Anime Latino', handle: '@TMSAnimeLatino', idioma: 'Latino y subtitulado'),
    CanalOficial(nombre: 'Gundam Channel', handle: '@GundamInfo', idioma: 'Subtitulado'),
    CanalOficial(nombre: 'Crunchyroll en Español', handle: '@CrunchyrollenEspanol', idioma: 'Latino'),
    CanalOficial(nombre: 'Toei Animation', handle: '@ToeiAnimationOfficial', idioma: 'Varios'),
  ];

  /// Los canales con series completas, para ensenar algo que ver sin buscar.
  static const List<CanalOficial> conSeries = <CanalOficial>[
    CanalOficial(nombre: 'TMS Anime Latino', handle: '@TMSAnimeLatino', idioma: 'Latino y subtitulado'),
    CanalOficial(nombre: 'Gundam Channel', handle: '@GundamInfo', idioma: 'Subtitulado'),
  ];

  /// Lo que dura como poco un episodio de verdad. Menos es un clip o un avance.
  static const double minimoEpisodio = 15 * 60;

  static bool esLista(Resultado r) => r.url.contains('playlist?list=');

  static bool esEpisodio(Resultado r) => !esLista(r) && r.duracion >= minimoEpisodio;

  /// El titulo corto con el que se busca: sin subtitulo ni temporada.
  ///
  /// «Lupin III: Part 4» se sube como «Lupin III Parte 4»; buscando «Lupin
  /// III» salen todas sus partes, y el filtro ya descarta lo que no es.
  static String corto(String titulo) {
    final String sinSubtitulo = titulo.split(RegExp(r'[:：]')).first;
    return sinSubtitulo
        .replaceAll(RegExp(r'\b(season|part|temporada)\s*\d+\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Hasta dos busquedas distintas por anime: con el nombre en ingles y en romaji.
  static List<String> consultas(Anime anime) {
    final List<String> todas = <String>[];
    for (final String nombre in <String>[?anime.ingles, anime.romaji]) {
      final String c = corto(nombre);
      if (c.length >= 2 && !todas.any((String t) => normalizar(t) == normalizar(c))) todas.add(c);
    }
    return todas.take(2).toList();
  }

  /// Minusculas, sin tildes ni signos: para comparar titulos escritos distinto.
  static String normalizar(String texto) {
    const String con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const String sin = 'aaaaaeeeeiiiiooooouuuunc';
    final StringBuffer salida = StringBuffer();
    for (final int codigo in texto.toLowerCase().runes) {
      final String letra = String.fromCharCode(codigo);
      final int donde = con.indexOf(letra);
      salida.write(donde >= 0 ? sin[donde] : letra);
    }
    return salida
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Si un video del canal es de este anime y no de otro que sale al buscar.
  static bool esDe(String tituloVideo, Anime anime) {
    final String video = ' ${normalizar(tituloVideo)} ';
    for (final String nombre in anime.nombres) {
      final String clave = normalizar(corto(nombre));
      if (clave.length < 3) continue;
      if (video.contains(' $clave ')) return true;
      // Junto: AniList dice «Megalo Box» y el canal lo sube como «MEGALOBOX».
      final String junta = clave.replaceAll(' ', '');
      if (junta.length >= 6 && video.replaceAll(' ', '').contains(junta)) return true;
      // Por palabras: «Gundam SEED» en «Mobile Suit Gundam SEED HD Remaster».
      final List<String> palabras =
          clave.split(' ').where((String p) => p.length >= 3).toList();
      if (palabras.length >= 2 && palabras.every((String p) => video.contains(' $p '))) {
        return true;
      }
    }
    return false;
  }

  /// Busca el anime en todos los canales a la vez.
  ///
  /// Un canal que falla (sin red, cambio de YouTube) no tumba a los demas.
  static Future<OfertaGratis> buscar(Anime anime) async {
    final List<Future<List<Resultado>>> pedidos = <Future<List<Resultado>>>[
      for (final CanalOficial canal in canales)
        for (final String consulta in consultas(anime)) _deCanal(canal, consulta),
    ];
    final List<List<Resultado>> todos = await Future.wait(pedidos);

    final Set<String> vistos = <String>{};
    final List<Resultado> series = <Resultado>[];
    final List<Resultado> episodios = <Resultado>[];
    for (final Resultado r in todos.expand((List<Resultado> l) => l)) {
      if (!vistos.add(r.url) || !esDe(r.titulo, anime)) continue;
      if (esLista(r)) {
        series.add(r);
      } else if (esEpisodio(r)) {
        episodios.add(r);
      }
    }
    return OfertaGratis(series: series, episodios: episodios);
  }

  static Future<List<Resultado>> _deCanal(CanalOficial canal, String consulta) async {
    try {
      final ListaTraida lista = await Nucleo.importarLista(canal.buscarUrl(consulta));
      return <Resultado>[for (final Resultado r in lista.pistas) _delCanal(r, canal)];
    } catch (_) {
      return const <Resultado>[];
    }
  }

  /// Las series completas de los canales que las tienen, para curiosear.
  static Future<List<Resultado>> seriesCompletas() async {
    final List<List<Resultado>> todas = await Future.wait(<Future<List<Resultado>>>[
      for (final CanalOficial canal in conSeries)
        Nucleo.importarLista(canal.listasUrl)
            .then((ListaTraida l) => <Resultado>[
                  for (final Resultado r in l.pistas)
                    if (esLista(r)) _delCanal(r, canal),
                ])
            .catchError((Object _) => const <Resultado>[]),
    ]);
    // Intercaladas, para que no salga un canal entero antes que el otro.
    final List<Resultado> mezcla = <Resultado>[];
    final int largo = todas.fold<int>(0, (int m, List<Resultado> l) => l.length > m ? l.length : m);
    for (int i = 0; i < largo; i++) {
      for (final List<Resultado> l in todas) {
        if (i < l.length) mezcla.add(l[i]);
      }
    }
    return mezcla;
  }

  /// Los episodios de una lista oficial, sin borrados ni clips sueltos.
  ///
  /// Si la lista solo tiene clips (pasa: hay listas de avances) se devuelven
  /// tal cual, para no ensenar una lista vacia sin explicacion.
  static Future<({List<Resultado> episodios, bool soloClips})> episodiosDe(Resultado lista) async {
    final ListaTraida traida = await Nucleo.importarLista(lista.url);
    final List<Resultado> validos = traida.pistas
        .where((Resultado r) => r.titulo != '(sin título)' && r.titulo.isNotEmpty)
        .map((Resultado r) => r.autor.isEmpty ? _conAutor(r, lista.autor) : r)
        .toList();
    final List<Resultado> completos = validos.where(esEpisodio).toList();
    if (completos.isNotEmpty) return (episodios: completos, soloClips: false);
    return (episodios: validos, soloClips: true);
  }

  static Resultado _delCanal(Resultado r, CanalOficial canal) => _conAutor(r, canal.nombre);

  static Resultado _conAutor(Resultado r, String autor) => Resultado(
        titulo: r.titulo,
        autor: autor,
        duracion: r.duracion,
        url: r.url,
        miniatura: r.miniatura,
      );
}
