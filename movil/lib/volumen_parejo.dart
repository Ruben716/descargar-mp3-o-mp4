import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'nucleo.dart';

/// Que todas las canciones suenen igual de fuerte, vengan de donde vengan.
///
/// Una bajada de YouTube y otra de Bandcamp pueden estar a varios decibelios
/// de distancia, y no deberia tocarse el volumen entre cancion y cancion. Se
/// mide cada una (en LUFS, la medida que usan Spotify o YouTube) y al sonar se
/// lleva al mismo nivel: las fuertes se bajan con el volumen del reproductor y
/// las flojas se suben con el refuerzo del ecualizador.
class VolumenParejo extends ChangeNotifier {
  VolumenParejo._();

  static final VolumenParejo instancia = VolumenParejo._();

  /// El nivel al que se lleva todo: el de Spotify y YouTube.
  static const double objetivo = -14;

  static const String claveActivo = 'volumen_parejo';
  static const String claveSilencios = 'saltar_silencios';

  bool _activo = true;
  bool get activo => _activo;

  bool _saltarSilencios = false;
  bool get saltarSilencios => _saltarSilencios;

  /// Hasta que no se carga no se mide nada: asi las pruebas que no lo usan no
  /// se llenan de mediciones que nadie pidio.
  bool _listo = false;

  final Map<String, double> _lufs = <String, double>{};

  /// Lo que se ha medido ya.
  int get medidas => _lufs.length;

  double? lufsDe(String uri) => _lufs[uri];

  /// Lo que hay que hacer con una cancion de [lufs] para llevarla al objetivo.
  ///
  /// Bajar se hace con el volumen del reproductor (factor de 0 a 1); subir no
  /// cabe ahi, asi que va al refuerzo del ecualizador en decibelios. Con
  /// limites, para no destrozar nada si una medida sale rara.
  static ({double factor, double extraDb}) correccion(double lufs) {
    final double diferencia = (objetivo - lufs).clamp(-15.0, 9.0);
    if (diferencia < 0) return (factor: pow(10, diferencia / 20).toDouble(), extraDb: 0);
    return (factor: 1, extraDb: diferencia);
  }

  /// Lo que toca para [uri]: neutro si esta apagado o aun no se ha medido.
  ({double factor, double extraDb}) para(String? uri) {
    final double? lufs = uri == null ? null : _lufs[uri];
    if (!_activo || lufs == null) return (factor: 1, extraDb: 0);
    return correccion(lufs);
  }

  Future<void> cargar() async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      _activo = memoria.getBool(claveActivo) ?? true;
      _saltarSilencios = memoria.getBool(claveSilencios) ?? false;
      _lufs.addAll(await Catalogo.instancia.volumenes());
    } catch (_) {
      // Sin datos se empieza de cero: se ira midiendo.
    }
    _listo = true;
    notifyListeners();
  }

  Future<void> ponerActivo(bool activo) async {
    _activo = activo;
    notifyListeners();
    await _guardar(claveActivo, activo);
  }

  /// Lo aplica el reproductor, que escucha los cambios.
  Future<void> ponerSaltarSilencios(bool saltar) async {
    _saltarSilencios = saltar;
    notifyListeners();
    await _guardar(claveSilencios, saltar);
  }

  Future<void> _guardar(String clave, bool valor) async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setBool(clave, valor);
    } catch (_) {
      // Dura hasta cerrar la app.
    }
  }

  // --- Medicion ------------------------------------------------------------

  final List<String> _cola = <String>[];
  final Set<String> _intentadas = <String>{};
  bool _midiendo = false;

  /// Cuantas faltan en la cola ahora mismo.
  int get pendientes => _cola.length + (_midiendo ? 1 : 0);

  /// Pide medir una cancion si aun no se sabe cuanto suena. Se mide en segundo
  /// plano, de una en una: es FFmpeg leyendo la cancion entera.
  void pedirSiFalta(String uri) {
    if (!_listo || !_activo || uri.isEmpty) return;
    if (_lufs.containsKey(uri) || _intentadas.contains(uri) || _cola.contains(uri)) return;
    _cola.add(uri);
    unawaited(_trabajar());
  }

  /// Mide toda la biblioteca que falte. Devuelve cuantas se pusieron en cola.
  int medirTodas(Iterable<String> uris) {
    if (!_listo) return 0;
    int puestas = 0;
    for (final String uri in uris) {
      if (_lufs.containsKey(uri) || _cola.contains(uri)) continue;
      _intentadas.remove(uri);
      _cola.add(uri);
      puestas++;
    }
    notifyListeners();
    unawaited(_trabajar());
    return puestas;
  }

  Future<void> _trabajar() async {
    if (_midiendo) return;
    _midiendo = true;
    try {
      while (_cola.isNotEmpty) {
        final String uri = _cola.removeAt(0);
        _intentadas.add(uri);
        final double? lufs = await medir(uri);
        if (lufs != null) {
          _lufs[uri] = lufs;
          try {
            await Catalogo.instancia.anotarVolumen(uri, lufs);
          } catch (_) {
            // Se queda en memoria; se volvera a medir otro dia.
          }
        }
        notifyListeners();
      }
    } finally {
      _midiendo = false;
      notifyListeners();
    }
  }

  /// Como se mide una cancion. Las pruebas lo cambian.
  @visibleForTesting
  static Future<double?> Function(String uri) medir = Nucleo.medirVolumen;

  @visibleForTesting
  void reiniciar() {
    _lufs.clear();
    _cola.clear();
    _intentadas.clear();
    _activo = true;
    _saltarSilencios = false;
    _listo = false;
    medir = Nucleo.medirVolumen;
  }

  @visibleForTesting
  void marcarListo() => _listo = true;
}
