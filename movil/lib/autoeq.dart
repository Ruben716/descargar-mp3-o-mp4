import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'canales_oficiales.dart';
import 'ecualizador.dart';

/// Unos audifonos medidos por AutoEQ.
@immutable
class ModeloAudifonos {
  const ModeloAudifonos({required this.nombre, required this.ruta, required this.fuente});

  final String nombre;

  /// La carpeta dentro de results/, tal como la escribe el indice (codificada).
  final String ruta;

  /// Quien lo midio (oratory1990, Rtings...). Hay modelos medidos por varios.
  final String fuente;

  /// La curva de correccion, en el repositorio publico de AutoEQ.
  Uri get urlCorreccion {
    final String carpeta = ruta.split('/').last;
    return Uri.parse('${AutoEq.base}/results/$ruta/$carpeta%20GraphicEQ.txt');
  }
}

/// El catalogo de AutoEQ: mas de 8800 audifonos medidos, con licencia MIT.
///
/// No se mete entero en la app: el indice (unos 850 KB) se baja la primera vez
/// que se busca y se guarda un mes; de cada modelo solo se baja su curva al
/// elegirlo.
class AutoEq {
  AutoEq._();

  static const String base = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master';

  /// Como se baja un texto. Las pruebas lo cambian para no tocar la red.
  @visibleForTesting
  static Future<String> Function(Uri direccion) bajar = _porHttp;

  /// Donde se guarda el indice. Las pruebas la cambian.
  @visibleForTesting
  static Future<Directory> Function() carpeta = getApplicationSupportDirectory;

  static List<ModeloAudifonos>? _indice;

  /// Las mediciones de quien mas se fia la comunidad van primero.
  static const List<String> _preferidas = <String>['oratory1990', 'crinacle', 'Rtings', 'Innerfidelity'];

  static final RegExp _linea = RegExp(r'^- \[(.+?)\]\(\./(.+?)\) by (.+)$');

  /// Lee el INDEX.md de AutoEQ: una linea por medicion.
  static List<ModeloAudifonos> leerIndice(String texto) {
    final List<ModeloAudifonos> todos = <ModeloAudifonos>[];
    for (final String linea in const LineSplitter().convert(texto)) {
      final RegExpMatch? m = _linea.firstMatch(linea.trim());
      if (m == null) continue;
      todos.add(ModeloAudifonos(nombre: m.group(1)!, ruta: m.group(2)!, fuente: m.group(3)!.trim()));
    }
    return todos;
  }

  static Future<List<ModeloAudifonos>> indice() async {
    final List<ModeloAudifonos>? hecho = _indice;
    if (hecho != null) return hecho;
    File? guardado;
    try {
      guardado = File('${(await carpeta()).path}/autoeq_indice.md');
      if (guardado.existsSync() &&
          DateTime.now().difference(guardado.lastModifiedSync()) < const Duration(days: 30)) {
        return _indice = leerIndice(await guardado.readAsString());
      }
    } catch (_) {
      guardado = null;
    }
    final String texto = await bajar(Uri.parse('$base/results/INDEX.md'));
    final List<ModeloAudifonos> todos = leerIndice(texto);
    if (todos.isEmpty) throw const ErrorAutoEq('El catalogo de AutoEQ no se entiende.');
    try {
      await guardado?.writeAsString(texto);
    } catch (_) {
      // Sin cache se vuelve a bajar la proxima vez; nada mas.
    }
    return _indice = todos;
  }

  /// Los modelos cuyo nombre lleva todas las palabras buscadas.
  ///
  /// Cada modelo sale una vez, con la medicion de la fuente mas fiable.
  static List<ModeloAudifonos> buscar(List<ModeloAudifonos> todos, String texto, {int limite = 40}) {
    final List<String> palabras =
        CanalesOficiales.normalizar(texto).split(' ').where((String p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return const <ModeloAudifonos>[];
    final Map<String, ModeloAudifonos> mejores = <String, ModeloAudifonos>{};
    for (final ModeloAudifonos m in todos) {
      final String nombre = CanalesOficiales.normalizar(m.nombre);
      if (!palabras.every(nombre.contains)) continue;
      final ModeloAudifonos? antes = mejores[m.nombre];
      if (antes == null || _rango(m.fuente) < _rango(antes.fuente)) mejores[m.nombre] = m;
    }
    final List<ModeloAudifonos> lista = mejores.values.toList()
      ..sort((ModeloAudifonos a, ModeloAudifonos b) => a.nombre.length.compareTo(b.nombre.length));
    return lista.take(limite).toList();
  }

  static int _rango(String fuente) {
    for (int i = 0; i < _preferidas.length; i++) {
      if (fuente.startsWith(_preferidas[i])) return i;
    }
    return _preferidas.length;
  }

  /// Baja y lee la correccion de un modelo.
  static Future<Correccion> correccion(ModeloAudifonos modelo) async {
    final String texto = await bajar(modelo.urlCorreccion);
    try {
      return Correccion.desdeGraphicEq(modelo.nombre, texto);
    } on FormatException {
      throw const ErrorAutoEq('Ese modelo no tiene una correccion que se pueda usar.');
    }
  }

  @visibleForTesting
  static void olvidar() => _indice = null;

  static Future<String> _porHttp(Uri direccion) async {
    final HttpClient cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest peticion = await cliente.getUrl(direccion);
      final HttpClientResponse respuesta = await peticion.close().timeout(const Duration(seconds: 30));
      final String texto = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode == 404) {
        throw const ErrorAutoEq('Ese modelo no esta en AutoEQ.');
      }
      if (respuesta.statusCode >= 400) {
        throw ErrorAutoEq('AutoEQ no responde ahora (${respuesta.statusCode}).');
      }
      return texto;
    } on SocketException {
      throw const ErrorAutoEq('Sin conexion a internet.');
    } finally {
      cliente.close();
    }
  }
}

class ErrorAutoEq implements Exception {
  const ErrorAutoEq(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}
