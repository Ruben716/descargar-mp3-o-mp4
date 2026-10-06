import 'dart:convert';

import 'package:flutter/services.dart';

/// Una pelicula o serie del catalogo externo (PelisPlusHD).
class Peli {
  const Peli({
    required this.url,
    required this.titulo,
    this.portada = '',
    this.tipo = '',
  });

  factory Peli.desdeJson(Map<String, dynamic> j) => Peli(
        url: j['url']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        portada: j['portada']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
      );

  final String url;
  final String titulo;
  final String portada;
  final String tipo;
}

/// Un capitulo de una serie.
class CapituloPeli {
  const CapituloPeli({
    required this.url,
    required this.temporada,
    required this.numero,
    required this.titulo,
  });

  factory CapituloPeli.desdeJson(Map<String, dynamic> j) => CapituloPeli(
        url: j['url']?.toString() ?? '',
        temporada: j['temporada']?.toString() ?? '1',
        numero: j['numero']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
      );

  final String url;
  final String temporada;
  final String numero;
  final String titulo;
}

/// Un servidor (embed) de una pelicula o capitulo.
class ServidorPeli {
  const ServidorPeli({required this.nombre, required this.url});

  factory ServidorPeli.desdeJson(Map<String, dynamic> j) => ServidorPeli(
        nombre: j['nombre']?.toString() ?? 'Servidor',
        url: j['url']?.toString() ?? '',
      );

  final String nombre;
  final String url;
}

class ErrorPelis implements Exception {
  const ErrorPelis(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Acceso al catalogo de PelisPlusHD por su MethodChannel propio.
class FuentePelis {
  FuentePelis._();

  static const MethodChannel canal = MethodChannel('com.ruben.descargador/pelis');

  static Future<Map<String, dynamic>> _pedir(String metodo, [Map<String, dynamic>? args]) async {
    final String crudo = await canal.invokeMethod<String>(metodo, args) ?? '{}';
    final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
    if (datos['ok'] != true) {
      throw ErrorPelis(datos['error']?.toString() ?? 'No se pudo consultar el catalogo.');
    }
    return datos;
  }

  static Future<List<Peli>> buscar(String texto) async {
    if (texto.trim().isEmpty) return const <Peli>[];
    final Map<String, dynamic> datos =
        await _pedir('buscar', <String, dynamic>{'texto': texto.trim()});
    return _lista(datos, 'resultados', Peli.desdeJson);
  }

  static Future<List<Peli>> peliculas({int pagina = 1}) async {
    final Map<String, dynamic> datos =
        await _pedir('peliculas', <String, dynamic>{'pagina': pagina});
    return _lista(datos, 'resultados', Peli.desdeJson);
  }

  static Future<List<Peli>> series({int pagina = 1}) async {
    final Map<String, dynamic> datos = await _pedir('series', <String, dynamic>{'pagina': pagina});
    return _lista(datos, 'resultados', Peli.desdeJson);
  }

  static Future<List<CapituloPeli>> capitulos(String url) async {
    final Map<String, dynamic> datos = await _pedir('capitulos', <String, dynamic>{'url': url});
    return _lista(datos, 'capitulos', CapituloPeli.desdeJson);
  }

  static Future<List<ServidorPeli>> servidores(String url) async {
    final Map<String, dynamic> datos = await _pedir('servidores', <String, dynamic>{'url': url});
    return _lista(datos, 'servidores', ServidorPeli.desdeJson);
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
