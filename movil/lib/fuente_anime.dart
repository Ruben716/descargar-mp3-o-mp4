import 'dart:convert';

import 'package:flutter/services.dart';

/// Un anime tal como lo lista una fuente externa (por ahora JKanime).
class AnimeFuente {
  const AnimeFuente({
    required this.url,
    required this.titulo,
    this.portada = '',
    this.tipo = '',
    this.estado = '',
  });

  factory AnimeFuente.desdeJson(Map<String, dynamic> j) => AnimeFuente(
        url: j['url']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        portada: j['portada']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
        estado: j['estado']?.toString() ?? '',
      );

  final String url;
  final String titulo;
  final String portada;
  final String tipo;
  final String estado;
}

/// Un episodio de la ficha, con su numero y la direccion para verlo.
class EpisodioFuente {
  const EpisodioFuente({required this.numero, required this.url});

  factory EpisodioFuente.desdeJson(Map<String, dynamic> j) => EpisodioFuente(
        numero: j['numero']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
      );

  final String numero;
  final String url;
}

/// Un servidor de video del episodio, ya decodificado desde el base64.
class ServidorFuente {
  const ServidorFuente({required this.nombre, required this.idioma, required this.url});

  factory ServidorFuente.desdeJson(Map<String, dynamic> j) => ServidorFuente(
        nombre: j['nombre']?.toString() ?? '',
        idioma: j['idioma']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
      );

  final String nombre;
  final String idioma;
  final String url;
}

/// La direccion reproducible y las cabeceras que exige el servidor.
class StreamResuelto {
  const StreamResuelto({required this.url, this.cabeceras = const <String, String>{}});

  final String url;
  final Map<String, String> cabeceras;
}

class ErrorFuente implements Exception {
  const ErrorFuente(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Acceso a la fuente de anime externa por su MethodChannel propio.
///
/// Va aparte del canal del nucleo para no rozar la musica ni las descargas.
class FuenteAnime {
  FuenteAnime._();

  static const MethodChannel canal = MethodChannel('com.ruben.descargador/anime');

  static Future<Map<String, dynamic>> _pedir(String metodo, [Map<String, dynamic>? args]) async {
    final String crudo = await canal.invokeMethod<String>(metodo, args) ?? '{}';
    final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
    if (datos['ok'] != true) {
      throw ErrorFuente(datos['error']?.toString() ?? 'No se pudo consultar la fuente.');
    }
    return datos;
  }

  static Future<List<AnimeFuente>> buscar(String texto) async {
    if (texto.trim().isEmpty) return const <AnimeFuente>[];
    final Map<String, dynamic> datos =
        await _pedir('buscar', <String, dynamic>{'texto': texto.trim()});
    return _lista(datos, 'animes', AnimeFuente.desdeJson);
  }

  static Future<List<AnimeFuente>> populares() async {
    final Map<String, dynamic> datos = await _pedir('populares');
    return _lista(datos, 'animes', AnimeFuente.desdeJson);
  }

  static Future<List<AnimeFuente>> emision() async {
    final Map<String, dynamic> datos = await _pedir('emision');
    return _lista(datos, 'animes', AnimeFuente.desdeJson);
  }

  static Future<List<EpisodioFuente>> episodios(String url) async {
    final Map<String, dynamic> datos = await _pedir('episodios', <String, dynamic>{'url': url});
    return _lista(datos, 'episodios', EpisodioFuente.desdeJson);
  }

  static Future<List<ServidorFuente>> servidores(String url) async {
    final Map<String, dynamic> datos = await _pedir('servidores', <String, dynamic>{'url': url});
    return _lista(datos, 'servidores', ServidorFuente.desdeJson);
  }

  static Future<StreamResuelto> resolver(String url) async {
    final Map<String, dynamic> datos = await _pedir('resolver', <String, dynamic>{'url': url});
    final Map<String, dynamic> cabeceras =
        (datos['cabeceras'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return StreamResuelto(
      url: datos['url']?.toString() ?? '',
      cabeceras: cabeceras.map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
    );
  }

  static List<T> _lista<T>(
    Map<String, dynamic> datos,
    String clave,
    T Function(Map<String, dynamic>) desde,
  ) {
    final List<dynamic> crudos = (datos[clave] as List<dynamic>?) ?? <dynamic>[];
    return <T>[
      for (final dynamic elemento in crudos)
        if (elemento is Map<String, dynamic>) desde(elemento),
    ];
  }
}
