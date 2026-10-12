import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una emisora de radio en directo, tal como la describe Radio Browser.
class EstacionRadio {
  const EstacionRadio({
    required this.id,
    required this.nombre,
    required this.url,
    this.codec = '',
    this.kbps = 0,
    this.pais = '',
    this.logo = '',
    this.etiquetas = '',
  });

  factory EstacionRadio.desdeJson(Map<String, dynamic> j) => EstacionRadio(
        id: j['stationuuid']?.toString() ?? j['id']?.toString() ?? '',
        nombre: (j['name']?.toString() ?? j['nombre']?.toString() ?? '').trim(),
        url: j['url_resolved']?.toString() ?? j['url']?.toString() ?? '',
        codec: (j['codec']?.toString() ?? '').toUpperCase(),
        kbps: (j['bitrate'] as num?)?.toInt() ?? (j['kbps'] as num?)?.toInt() ?? 0,
        pais: j['country']?.toString() ?? j['pais']?.toString() ?? '',
        logo: j['favicon']?.toString() ?? j['logo']?.toString() ?? '',
        etiquetas: j['tags']?.toString() ?? j['etiquetas']?.toString() ?? '',
      );

  final String id;
  final String nombre;
  final String url;
  final String codec;
  final int kbps;
  final String pais;
  final String logo;
  final String etiquetas;

  Map<String, dynamic> aJson() => <String, dynamic>{
        'id': id,
        'nombre': nombre,
        'url': url,
        'codec': codec,
        'kbps': kbps,
        'pais': pais,
        'logo': logo,
        'etiquetas': etiquetas,
      };

  /// FLAC por la radio: lo que ni Spotify ofrece en directo.
  bool get sinPerdida => codec == 'FLAC';

  /// Lo que se ensenia de su calidad. Muchas no dicen sus kb/s (vienen a 0).
  String get sello {
    if (sinPerdida) return 'FLAC · sin perdida';
    final String codigo = codec.isEmpty ? 'Audio' : codec;
    return kbps > 0 ? '$codigo $kbps kb/s' : codigo;
  }

  /// Cuanto vale para ordenar por calidad: el FLAC arriba, luego los kb/s.
  int get puntos => sinPerdida ? 100000 : kbps;
}

/// Radios en directo de todo el mundo, con el directorio libre Radio Browser.
///
/// Sin clave ni cuenta. Medido: decenas de miles de emisoras, las peruanas
/// (RPP, La Mega, Oxigeno...) y algunas en FLAC, como Radio Paradise.
class RadioMundial {
  RadioMundial._();

  static const String _servidor = 'https://de1.api.radio-browser.info';

  /// Como se piden los datos. Las pruebas lo cambian: no tocan la red.
  @visibleForTesting
  static Future<String> Function(Uri direccion) transporte = _porHttp;

  /// Busca emisoras. Todo es opcional: sin nada salen las mas votadas.
  static Future<List<EstacionRadio>> buscar({
    String nombre = '',
    String paisCodigo = '',
    String etiqueta = '',
    bool soloSinPerdida = false,
    int limite = 40,
  }) async {
    final Uri direccion = Uri.parse('$_servidor/json/stations/search').replace(
      queryParameters: <String, String>{
        if (nombre.trim().isNotEmpty) 'name': nombre.trim(),
        if (paisCodigo.isNotEmpty) 'countrycode': paisCodigo,
        if (etiqueta.isNotEmpty) 'tag': etiqueta,
        if (soloSinPerdida) 'codec': 'FLAC',
        'limit': '$limite',
        'order': 'votes',
        'reverse': 'true',
        // Las que el directorio ya sabe caidas no se ofrecen.
        'hidebroken': 'true',
      },
    );
    return desdeRespuesta(await transporte(direccion));
  }

  /// Traduce la respuesta: sin direccion no hay emisora, y la misma emisora
  /// dada de alta dos veces sale una sola.
  @visibleForTesting
  static List<EstacionRadio> desdeRespuesta(String texto) {
    final List<dynamic> crudas = jsonDecode(texto) as List<dynamic>;
    final Set<String> vistas = <String>{};
    return <EstacionRadio>[
      for (final dynamic c in crudas)
        if (EstacionRadio.desdeJson(c as Map<String, dynamic>) case final EstacionRadio e
            when e.url.startsWith('http') && e.nombre.isNotEmpty && vistas.add(e.url))
          e,
    ];
  }

  static Future<String> _porHttp(Uri direccion) async {
    final HttpClient cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest peticion = await cliente.getUrl(direccion);
      peticion.headers.set(HttpHeaders.userAgentHeader, 'Tumbao/2 (proyecto academico)');
      final HttpClientResponse respuesta = await peticion.close().timeout(const Duration(seconds: 20));
      final String texto = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode >= 400) throw ErrorRadio('El directorio de radios respondio ${respuesta.statusCode}.');
      return texto;
    } on SocketException {
      throw const ErrorRadio('Sin conexion a internet.');
    } finally {
      cliente.close();
    }
  }
}

class ErrorRadio implements Exception {
  const ErrorRadio(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Las emisoras guardadas con el corazon, para tenerlas a un toque.
class RadiosFavoritas extends ChangeNotifier {
  RadiosFavoritas._();

  static final RadiosFavoritas instancia = RadiosFavoritas._();

  static const String clave = 'radios_favoritas_v1';

  final List<EstacionRadio> _todas = <EstacionRadio>[];
  bool _cargadas = false;

  List<EstacionRadio> get todas => List<EstacionRadio>.unmodifiable(_todas);

  bool contiene(EstacionRadio e) => _todas.any((EstacionRadio f) => f.url == e.url);

  Future<void> cargar() async {
    if (_cargadas) return;
    _cargadas = true;
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final List<dynamic> crudas = jsonDecode(memoria.getString(clave) ?? '[]') as List<dynamic>;
      _todas
        ..clear()
        ..addAll(crudas.map((dynamic c) => EstacionRadio.desdeJson(c as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      // Sin favoritas guardadas se empieza de cero; marcar sigue funcionando.
    }
  }

  Future<void> alternar(EstacionRadio e) async {
    contiene(e) ? _todas.removeWhere((EstacionRadio f) => f.url == e.url) : _todas.insert(0, e);
    notifyListeners();
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setString(clave, jsonEncode(_todas.map((EstacionRadio f) => f.aJson()).toList()));
    } catch (_) {
      // Si no se pudo guardar, al menos dura hasta cerrar la app.
    }
  }

  @visibleForTesting
  void reiniciar() {
    _todas.clear();
    _cargadas = false;
  }
}
