import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Trae las pistas de una lista de reproduccion ajena, sin descargarlas.
  static Future<ListaTraida> importarLista(String url) async {
    final Map<String, dynamic> datos =
        await _pedir('importarLista', <String, dynamic>{'url': url});
    return ListaTraida(
      titulo: datos['titulo']?.toString() ?? 'Lista importada',
      pistas: ((datos['resultados'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic r) => Resultado.desdeJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<List<String>> descargar(Ajustes ajustes, {bool avisar = true}) async {
    final Map<String, dynamic> datos = await _pedir('descargar', <String, dynamic>{
      ...ajustes.aMapa(),
      'avisar': avisar,
    });
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

  /// Pista reproducible al vuelo, para oir antes de decidir si se descarga.
  static Future<Previsualizacion> previsualizar(String url, {bool soloAudio = true}) async {
    final Map<String, dynamic> datos = await _pedir(
      'previsualizar',
      <String, dynamic>{'url': url, 'soloAudio': soloAudio},
    );
    return Previsualizacion.desdeJson(datos);
  }

  /// Borra una descarga de la biblioteca del telefono.
  static Future<void> eliminar(String uri) =>
      _pedir('eliminar', <String, dynamic>{'uri': uri});

  /// Cierto mientras la app va encogida en una ventana flotante.
  static final ValueNotifier<bool> enVentanaFlotante = ValueNotifier<bool>(false);

  /// Encoge la app a una ventana flotante con la proporcion del video.
  static Future<bool> pedirVentanaFlotante({required int ancho, required int alto}) async =>
      await _canal.invokeMethod<bool>(
        'ventanaFlotante',
        <String, dynamic>{'ancho': ancho, 'alto': alto},
      ) ??
      false;

  /// Android avisa por el mismo canal al entrar o salir de la ventana.
  static void escucharVentanaFlotante() {
    _canal.setMethodCallHandler((MethodCall llamada) async {
      if (llamada.method == 'ventanaFlotante') {
        enVentanaFlotante.value = llamada.arguments == true;
      }
      return null;
    });
  }

  static Future<String?> urlCompartida() => _canal.invokeMethod<String>('urlCompartida');

  static final Map<String, Uint8List?> _caratulas = <String, Uint8List?>{};

  /// Caratula del archivo, ya decodificada. Se recuerda porque cruzar el
  /// canal y decodificar base64 por cada pintado seria un derroche.
  /// La caratula guardada como archivo: la notificacion del sistema necesita
  /// una direccion, no unos bytes.
  static Future<Uri?> caratulaArchivo(String uri) async {
    final Uint8List? imagen = await caratula(uri);
    if (imagen == null) return null;
    try {
      final Directory cache = await getTemporaryDirectory();
      final String nombre = uri.hashCode.toRadixString(16);
      final File destino = File('${cache.path}/caratula_$nombre.jpg');
      if (!destino.existsSync()) await destino.writeAsBytes(imagen);
      return destino.uri;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> caratula(String uri) async {
    if (_caratulas.containsKey(uri)) return _caratulas[uri];
    try {
      final Map<String, dynamic> datos =
          await _pedir('caratula', <String, dynamic>{'uri': uri});
      final String crudo = datos['imagen']?.toString() ?? '';
      final Uint8List? imagen = crudo.isEmpty ? null : base64Decode(crudo);
      _caratulas[uri] = imagen;
      return imagen;
    } catch (_) {
      _caratulas[uri] = null;
      return null;
    }
  }
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
  const Resultado({
    required this.titulo,
    required this.autor,
    required this.duracion,
    required this.url,
    this.miniatura = '',
  });

  factory Resultado.desdeJson(Map<String, dynamic> j) => Resultado(
        titulo: j['titulo']?.toString() ?? '',
        autor: j['autor']?.toString() ?? '',
        duracion: (j['duracion'] as num?)?.toDouble() ?? 0,
        url: j['url']?.toString() ?? '',
        miniatura: j['miniatura']?.toString() ?? '',
      );

  final String titulo;
  final String autor;
  final double duracion;
  final String url;
  final String miniatura;
}

/// Una lista ajena tal y como llega: con su nombre, para poder recrearla.
class ListaTraida {
  const ListaTraida({required this.titulo, required this.pistas});

  final String titulo;
  final List<Resultado> pistas;
}

class Previsualizacion {
  const Previsualizacion({required this.url, required this.titulo, required this.cabeceras});

  factory Previsualizacion.desdeJson(Map<String, dynamic> j) => Previsualizacion(
        url: j['url']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        cabeceras: ((j['cabeceras'] as Map<String, dynamic>?) ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
      );

  final String url;
  final String titulo;

  /// YouTube exige el mismo User-Agent con el que se pidio el enlace.
  final Map<String, String> cabeceras;
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
