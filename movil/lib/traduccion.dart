import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Pasa al castellano lo que AniList solo tiene en ingles.
///
/// Traduce el propio telefono con el traductor de Google (ML Kit): gratis,
/// sin cuenta y sin mandar el texto a ningun sitio. La primera vez baja los
/// paquetes de idioma (unos 30 MB) y despues funciona incluso sin internet.
class Traduccion {
  Traduccion._();

  /// Como se traduce. Las pruebas lo cambian: en ellas no hay ML Kit.
  @visibleForTesting
  static Future<String> Function(String ingles) motor = _conMlKit;

  static final Map<String, String> _hechas = <String, String>{};
  static Future<void>? _preparando;

  /// El texto en castellano, o null si no se pudo (sin red la primera vez,
  /// sin espacio...). Quien llama ensenia entonces el original.
  static Future<String?> alEspanol(String ingles) async {
    final String texto = ingles.trim();
    if (texto.isEmpty) return null;
    final String? hecha = _hechas[texto];
    if (hecha != null) return hecha;
    try {
      final String traducida = (await motor(texto)).trim();
      if (traducida.isEmpty) return null;
      _hechas[texto] = traducida;
      return traducida;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void olvidar() {
    _hechas.clear();
    _preparando = null;
  }

  static OnDeviceTranslator? _traductor;

  static Future<String> _conMlKit(String texto) async {
    // Una sola descarga aunque se abran varias fichas a la vez.
    await (_preparando ??= _prepararModelos().catchError((Object error) {
      _preparando = null;
      throw error;
    }));
    final OnDeviceTranslator traductor = _traductor ??= OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.spanish,
    );
    // Por parrafos: el traductor del telefono rinde mejor con trozos cortos.
    final List<String> parrafos = texto.split('\n');
    final List<String> salida = <String>[];
    for (final String parrafo in parrafos) {
      salida.add(parrafo.trim().isEmpty ? '' : await traductor.translateText(parrafo));
    }
    return salida.join('\n');
  }

  static Future<void> _prepararModelos() async {
    final OnDeviceTranslatorModelManager modelos = OnDeviceTranslatorModelManager();
    for (final TranslateLanguage idioma in <TranslateLanguage>[
      TranslateLanguage.english,
      TranslateLanguage.spanish,
    ]) {
      if (!await modelos.isModelDownloaded(idioma.bcpCode)) {
        // Tambien con datos moviles: son 30 MB una sola vez, y esperar al
        // wifi dejaria la sinopsis en ingles sin explicar por que.
        final bool listo = await modelos.downloadModel(idioma.bcpCode, isWifiRequired: false);
        if (!listo) throw StateError('No se pudo bajar el idioma ${idioma.bcpCode}');
      }
    }
  }

  /// Los generos de AniList son una lista cerrada: van con su traduccion fija.
  static String genero(String ingles) => _generos[ingles] ?? ingles;

  static const Map<String, String> _generos = <String, String>{
    'Action': 'Accion',
    'Adventure': 'Aventura',
    'Comedy': 'Comedia',
    'Drama': 'Drama',
    'Ecchi': 'Ecchi',
    'Fantasy': 'Fantasia',
    'Hentai': 'Hentai',
    'Horror': 'Terror',
    'Mahou Shoujo': 'Chicas magicas',
    'Mecha': 'Mecha',
    'Music': 'Musica',
    'Mystery': 'Misterio',
    'Psychological': 'Psicologico',
    'Romance': 'Romance',
    'Sci-Fi': 'Ciencia ficcion',
    'Slice of Life': 'Vida cotidiana',
    'Sports': 'Deportes',
    'Supernatural': 'Sobrenatural',
    'Thriller': 'Suspense',
  };
}
