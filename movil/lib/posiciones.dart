import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Donde se dejo cada video o cada audio largo, para retomarlo.
///
/// Solo se guarda si se oyo algo (mas de 10 segundos) y no se termino (le
/// quedaban mas de 15): lo acabado vuelve a empezar desde el principio.
/// Videos y audios van en claves distintas para que no se quiten el sitio.
class Posiciones {
  const Posiciones._(this._clave);

  static const Posiciones video = Posiciones._('posiciones_video_v1');
  static const Posiciones audio = Posiciones._('posiciones_audio_v1');

  /// Claves que guardan algo, para la copia de seguridad.
  static const List<String> claves = <String>['posiciones_video_v1', 'posiciones_audio_v1'];

  final String _clave;
  static const int _maximo = 60;

  Future<Duration?> de(String uri) async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final Map<String, dynamic> todas =
          jsonDecode(memoria.getString(_clave) ?? '{}') as Map<String, dynamic>;
      final int? ms = (todas[uri] as num?)?.toInt();
      return ms == null ? null : Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar(String uri, Duration posicion, Duration total) async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final Map<String, dynamic> todas =
          jsonDecode(memoria.getString(_clave) ?? '{}') as Map<String, dynamic>;
      todas.remove(uri);
      if (merece(posicion, total)) todas[uri] = posicion.inMilliseconds;
      // Las mas antiguas se olvidan: no hace falta recordar cien.
      while (todas.length > _maximo) {
        todas.remove(todas.keys.first);
      }
      await memoria.setString(_clave, jsonEncode(todas));
    } catch (_) {
      // Sin poder guardar, la proxima vez empieza desde el principio.
    }
  }

  @visibleForTesting
  static bool merece(Duration posicion, Duration total) =>
      posicion.inSeconds > 10 && (total - posicion).inSeconds > 15;
}
