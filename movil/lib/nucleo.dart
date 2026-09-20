import 'dart:convert';

import 'package:flutter/services.dart';

/// Acceso al nucleo Python, el mismo que usa la version de consola.
///
/// Todo viaja como JSON por el canal de plataforma: Dart no entiende los
/// objetos del dominio y Kotlin solo hace de intermediario.
class Nucleo {
  const Nucleo._();

  static const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

  static Future<Map<String, dynamic>> _pedir(
    String metodo, [
    Map<String, dynamic>? argumentos,
  ]) async {
    final String crudo = await _canal.invokeMethod(metodo, argumentos) ?? '{}';
    final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
    if (datos.containsKey('ok') && datos['ok'] != true) {
      throw ErrorNucleo(
        datos['error']?.toString() ?? 'Error desconocido',
        ((datos['registro'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic l) => l.toString())
            .toList(),
      );
    }
    return datos;
  }

  static Future<Map<String, dynamic>> diagnostico() => _pedir('diagnostico');

  static Future<List<Resultado>> buscar(String texto, {int limite = 12}) async {
    final Map<String, dynamic> datos =
        await _pedir('buscar', <String, dynamic>{'texto': texto, 'limite': limite});
    return ((datos['resultados'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic r) => Resultado.desdeJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<List<String>> descargar(Ajustes ajustes) async {
    final Map<String, dynamic> datos = await _pedir('descargar', ajustes.aMapa());
    return ((datos['archivos'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic a) => a.toString())
        .toList();
  }

  static Future<Avance> progreso() async => Avance.desdeJson(await _pedir('progreso'));

  static Future<List<Elemento>> biblioteca() async {
    final Map<String, dynamic> datos = await _pedir('biblioteca');
    return ((datos['elementos'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => Elemento.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String?> urlCompartida() => _canal.invokeMethod<String>('urlCompartida');
}

/// Error del nucleo, con el registro del motor cuando lo hay.
class ErrorNucleo implements Exception {
  const ErrorNucleo(this.mensaje, [this.registro = const <String>[]]);

  final String mensaje;
  final List<String> registro;

  @override
  String toString() => mensaje;
}

class Resultado {
  const Resultado({required this.titulo, required this.autor, required this.duracion, required this.url});

  factory Resultado.desdeJson(Map<String, dynamic> j) => Resultado(
        titulo: j['titulo']?.toString() ?? '',
        autor: j['autor']?.toString() ?? '',
        duracion: (j['duracion'] as num?)?.toDouble() ?? 0,
        url: j['url']?.toString() ?? '',
      );

  final String titulo;
  final String autor;
  final double duracion;
  final String url;
}

class Elemento {
  const Elemento({
    required this.nombre,
    required this.uri,
    required this.duracion,
    required this.tamano,
    required this.audio,
  });

  factory Elemento.desdeJson(Map<String, dynamic> j) => Elemento(
        nombre: j['nombre']?.toString() ?? '',
        uri: j['uri']?.toString() ?? '',
        duracion: (j['duracion'] as num?)?.toDouble() ?? 0,
        tamano: (j['tamano'] as num?)?.toInt() ?? 0,
        audio: j['audio'] == true,
      );

  final String nombre;
  final String uri;
  final double duracion;
  final int tamano;
  final bool audio;
}

class Avance {
  const Avance({required this.estado, required this.porcentaje, required this.velocidad});

  factory Avance.desdeJson(Map<String, dynamic> j) => Avance(
        estado: j['status']?.toString() ?? '',
        porcentaje: (j['porcentaje'] as num?)?.toDouble() ?? -1,
        velocidad: (j['velocidad'] as num?)?.toInt() ?? 0,
      );

  final String estado;
  final double porcentaje;
  final int velocidad;
}

/// Lo que el usuario puede ajustar. Refleja DownloadOptions del dominio.
class Ajustes {
  const Ajustes({
    required this.url,
    this.soloAudio = false,
    this.calidad = 720,
    this.formatoAudio = 'mp3',
    this.bitrate = '192',
    this.subtitulos = '',
    this.fragmento = '',
    this.sinPatrocinios = false,
  });

  final String url;
  final bool soloAudio;
  final int calidad;
  final String formatoAudio;
  final String bitrate;
  final String subtitulos;
  final String fragmento;
  final bool sinPatrocinios;

  Ajustes copiar({
    String? url,
    bool? soloAudio,
    int? calidad,
    String? formatoAudio,
    String? bitrate,
    String? subtitulos,
    String? fragmento,
    bool? sinPatrocinios,
  }) =>
      Ajustes(
        url: url ?? this.url,
        soloAudio: soloAudio ?? this.soloAudio,
        calidad: calidad ?? this.calidad,
        formatoAudio: formatoAudio ?? this.formatoAudio,
        bitrate: bitrate ?? this.bitrate,
        subtitulos: subtitulos ?? this.subtitulos,
        fragmento: fragmento ?? this.fragmento,
        sinPatrocinios: sinPatrocinios ?? this.sinPatrocinios,
      );

  Map<String, dynamic> aMapa() => <String, dynamic>{
        'url': url,
        'soloAudio': soloAudio,
        // En audio la altura no aplica; el nucleo la ignoraria igualmente.
        'calidad': soloAudio ? 0 : calidad,
        'formatoAudio': formatoAudio,
        'bitrate': bitrate,
        'subtitulos': subtitulos,
        'fragmento': fragmento,
        'sinPatrocinios': sinPatrocinios,
      };
}
