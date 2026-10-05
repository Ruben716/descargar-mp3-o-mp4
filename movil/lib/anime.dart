import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Un anime tal como lo describe AniList: solo informacion, ningun video.
@immutable
class Anime {
  const Anime({
    required this.id,
    required this.romaji,
    this.ingles,
    this.nativo,
    this.sinonimos = const <String>[],
    this.portada = '',
    this.banner = '',
    this.color,
    this.sinopsis = '',
    this.generos = const <String>[],
    this.episodios,
    this.nota,
    this.anio,
    this.formato = '',
    this.estado = '',
    this.trailerYoutube,
    this.enlaces = const <EnlaceLegal>[],
  });

  factory Anime.desdeJson(Map<String, dynamic> j) {
    final Map<String, dynamic> titulos = (j['title'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> portada =
        (j['coverImage'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic>? trailer = j['trailer'] as Map<String, dynamic>?;
    return Anime(
      id: (j['id'] as num?)?.toInt() ?? 0,
      romaji: titulos['romaji']?.toString() ?? '',
      ingles: _texto(titulos['english']),
      nativo: _texto(titulos['native']),
      sinonimos: <String>[
        for (final dynamic s in (j['synonyms'] as List<dynamic>?) ?? <dynamic>[])
          if (s != null && '$s'.trim().isNotEmpty) '$s'.trim(),
      ],
      portada: portada['extraLarge']?.toString() ?? portada['large']?.toString() ?? '',
      banner: j['bannerImage']?.toString() ?? '',
      color: _color(portada['color']?.toString()),
      sinopsis: AniList.limpiarSinopsis(j['description']?.toString() ?? ''),
      generos: <String>[
        for (final dynamic g in (j['genres'] as List<dynamic>?) ?? <dynamic>[]) '$g',
      ],
      episodios: (j['episodes'] as num?)?.toInt(),
      nota: (j['averageScore'] as num?)?.toInt(),
      anio: (j['seasonYear'] as num?)?.toInt(),
      formato: j['format']?.toString() ?? '',
      estado: j['status']?.toString() ?? '',
      // Solo el de YouTube: es el que la app ya sabe reproducir.
      trailerYoutube: trailer != null && trailer['site'] == 'youtube' ? _texto(trailer['id']) : null,
      enlaces: <EnlaceLegal>[
        for (final dynamic e in (j['externalLinks'] as List<dynamic>?) ?? <dynamic>[])
          if (e is Map<String, dynamic> && e['type'] == 'STREAMING' && e['url'] != null)
            EnlaceLegal(sitio: e['site']?.toString() ?? 'Web', url: e['url'].toString()),
      ],
    );
  }

  final int id;
  final String romaji;
  final String? ingles;
  final String? nativo;
  final List<String> sinonimos;
  final String portada;
  final String banner;
  final int? color;
  final String sinopsis;
  final List<String> generos;
  final int? episodios;

  /// De 0 a 100, la media de los usuarios de AniList.
  final int? nota;
  final int? anio;
  final String formato;
  final String estado;

  /// El id del video en YouTube, si el trailer esta ahi.
  final String? trailerYoutube;

  /// Donde se puede ver legalmente (Crunchyroll, Netflix...).
  final List<EnlaceLegal> enlaces;

  /// El nombre que se ensenia: el ingles suele ser el que se reconoce aqui.
  String get titulo => (ingles?.isNotEmpty ?? false) ? ingles! : romaji;

  /// Todos los nombres por los que se le conoce, para reconocerlo en YouTube.
  List<String> get nombres => <String>[
        ?ingles,
        romaji,
        ...sinonimos.where((String s) => _latino.hasMatch(s)),
      ];

  /// Lo que es serie, pelicula, OVA... en castellano.
  String get formatoLegible => switch (formato) {
        'TV' => 'Serie',
        'TV_SHORT' => 'Serie corta',
        'MOVIE' => 'Pelicula',
        'OVA' || 'ONA' || 'SPECIAL' => 'Especial',
        _ => formato,
      };

  String get estadoLegible => switch (estado) {
        'RELEASING' => 'En emision',
        'FINISHED' => 'Terminado',
        'NOT_YET_RELEASED' => 'Proximamente',
        'CANCELLED' => 'Cancelado',
        'HIATUS' => 'En pausa',
        _ => '',
      };

  static final RegExp _latino = RegExp(r'^[\x00-ɏ\s]+$');

  static String? _texto(dynamic valor) {
    final String texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static int? _color(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    final int? valor = int.tryParse(hex.substring(1), radix: 16);
    return valor == null ? null : 0xFF000000 | valor;
  }
}

@immutable
class EnlaceLegal {
  const EnlaceLegal({required this.sitio, required this.url});

  final String sitio;
  final String url;
}

/// El catalogo de anime de AniList: gratuito, sin clave y legal.
///
/// Solo da informacion (titulos, caratulas, sinopsis, donde verlo). Los videos
/// salen de los canales oficiales de YouTube, nunca de aqui.
class AniList {
  AniList._();

  static const String _direccion = 'https://graphql.anilist.co';

  /// Como se manda la consulta. Las pruebas lo cambian para no tocar la red.
  @visibleForTesting
  static Future<String> Function(String cuerpo) transporte = _porHttp;

  static const String _consulta = r'''
query ($q: String, $temporada: MediaSeason, $anio: Int, $orden: [MediaSort]) {
  Page(page: 1, perPage: 30) {
    media(type: ANIME, isAdult: false, search: $q, season: $temporada,
          seasonYear: $anio, sort: $orden) {
      id
      title { romaji english native }
      synonyms
      coverImage { extraLarge large color }
      bannerImage
      description(asHtml: false)
      genres
      episodes
      averageScore
      seasonYear
      format
      status
      trailer { id site }
      externalLinks { site url type }
    }
  }
}''';

  static final Map<String, List<Anime>> _recordados = <String, List<Anime>>{};

  /// Lo que se emite esta temporada, lo mas popular primero.
  static Future<List<Anime>> temporada([DateTime? cuando]) {
    final ({String temporada, int anio}) ahora = temporadaDe(cuando ?? DateTime.now());
    return _pedir(<String, dynamic>{
      'temporada': ahora.temporada,
      'anio': ahora.anio,
      'orden': <String>['POPULARITY_DESC'],
    });
  }

  /// Los mas populares de siempre.
  static Future<List<Anime>> populares() =>
      _pedir(<String, dynamic>{'orden': <String>['POPULARITY_DESC']});

  static Future<List<Anime>> buscar(String texto) {
    final String limpio = texto.trim();
    if (limpio.isEmpty) return Future<List<Anime>>.value(const <Anime>[]);
    return _pedir(<String, dynamic>{'q': limpio, 'orden': <String>['SEARCH_MATCH']});
  }

  static Future<List<Anime>> _pedir(Map<String, dynamic> variables) async {
    final String cuerpo = jsonEncode(<String, dynamic>{'query': _consulta, 'variables': variables});
    final List<Anime>? antes = _recordados[cuerpo];
    if (antes != null) return antes;
    final List<Anime> lista = desdeRespuesta(await transporte(cuerpo));
    _recordados[cuerpo] = lista;
    return lista;
  }

  @visibleForTesting
  static void olvidar() => _recordados.clear();

  /// Convierte la respuesta de AniList en la lista de animes.
  static List<Anime> desdeRespuesta(String crudo) {
    final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
    final List<dynamic>? errores = datos['errors'] as List<dynamic>?;
    if (errores != null && errores.isNotEmpty) {
      final dynamic primero = errores.first;
      throw ErrorCatalogo(primero is Map ? '${primero['message']}' : '$primero');
    }
    final List<dynamic> medios =
        ((datos['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?)?['media']
                as List<dynamic>? ??
            <dynamic>[];
    return <Anime>[
      for (final dynamic m in medios)
        if (m is Map<String, dynamic>) Anime.desdeJson(m),
    ];
  }

  /// La temporada de AniList para una fecha: invierno es enero a marzo.
  static ({String temporada, int anio}) temporadaDe(DateTime fecha) {
    const List<String> temporadas = <String>['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    return (temporada: temporadas[(fecha.month - 1) ~/ 3], anio: fecha.year);
  }

  /// La sinopsis llega con etiquetas sueltas y notas de la fuente: se dejan
  /// solo los parrafos.
  static String limpiarSinopsis(String crudo) {
    String texto = crudo
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&mdash;', '—');
    // «(Source: Crunchyroll)» y parecidos al final no aportan nada.
    texto = texto.replaceAll(RegExp(r'\(Source:[^)]*\)', caseSensitive: false), '');
    texto = texto.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return texto.trim();
  }

  static Future<String> _porHttp(String cuerpo) async {
    final HttpClient cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest peticion = await cliente.postUrl(Uri.parse(_direccion));
      peticion.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json');
      peticion.add(utf8.encode(cuerpo));
      final HttpClientResponse respuesta =
          await peticion.close().timeout(const Duration(seconds: 20));
      final String texto = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode == 429) {
        throw const ErrorCatalogo('AniList pide esperar un momento. Prueba en un minuto.');
      }
      if (respuesta.statusCode >= 500) {
        throw const ErrorCatalogo('AniList no responde ahora mismo.');
      }
      return texto;
    } on SocketException {
      throw const ErrorCatalogo('Sin conexion a internet.');
    } finally {
      cliente.close();
    }
  }
}

class ErrorCatalogo implements Exception {
  const ErrorCatalogo(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}
