import 'dart:convert';
import 'dart:io';

import 'catalogo.dart';
import 'formato.dart';

/// Una linea de la letra con el instante en que se canta.
class LineaLetra {
  const LineaLetra(this.desde, this.texto);

  final Duration desde;
  final String texto;
}

/// La letra de una pista, sincronizada si se pudo.
class Letra {
  const Letra({required this.lineas, required this.texto});

  /// Letra vacia: se busco y no habia.
  const Letra.ninguna() : lineas = const <LineaLetra>[], texto = '';

  /// Las lineas con su marca de tiempo. Vacio si solo hay letra sin sincronizar.
  final List<LineaLetra> lineas;

  /// La letra de corrido, para cuando no hay sincronizacion.
  final String texto;

  bool get vacia => lineas.isEmpty && texto.trim().isEmpty;
  bool get sincronizada => lineas.isNotEmpty;

  /// Que linea toca en [instante], o -1 si aun no empezo.
  ///
  /// Busca hacia atras porque la primera linea suele entrar bastante despues
  /// del segundo cero, y hasta entonces no hay ninguna que resaltar.
  int lineaEn(Duration instante) {
    int encontrada = -1;
    for (int i = 0; i < lineas.length; i++) {
      if (lineas[i].desde > instante) break;
      encontrada = i;
    }
    return encontrada;
  }
}

/// Busca letras en lrclib.
///
/// Es abierta y no pide clave ni cuenta, que es la condicion de siempre del
/// proyecto. Lo que se encuentra se guarda en el catalogo, asi que a partir de
/// la segunda vez la letra sale sin internet.
class Letras {
  const Letras._();

  static const String _servidor = 'lrclib.net';

  /// La cortesia que pide lrclib: identificarse para que puedan distinguir
  /// el trafico y avisar si algo va mal.
  static const String _agente = 'Tumbao (proyecto academico)';

  /// Quita del nombre de archivo el ruido que no ayuda a encontrar la cancion.
  ///
  /// Los titulos de YouTube vienen llenos de "(Official Video)", "[4K]" o
  /// "| Video Oficial", y con eso dentro la busqueda no encuentra nada.
  static String consultaDe(String nombre) {
    String texto = nombreLimpio(nombre);
    texto = texto.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    texto = texto.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    texto = texto.split('|').first;
    texto = texto.replaceAll(
      RegExp(
        r'\b(official|oficial|video|videoclip|lyric[s]?|letra|audio|hd|4k|'
        r'mv|m/v|remaster(ed)?|en\s+vivo|live)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    texto = texto.replaceAll(RegExp(r'[_\-]+'), ' ');
    return texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Convierte un LRC en lineas con su instante.
  ///
  /// Una misma linea puede llevar varias marcas cuando el estribillo se repite,
  /// y las lineas de cabecera (`[ar:...]`) no son tiempos y se descartan.
  static List<LineaLetra> analizarLrc(String lrc) {
    final RegExp marca = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final List<LineaLetra> lineas = <LineaLetra>[];

    for (final String fila in const LineSplitter().convert(lrc)) {
      final List<RegExpMatch> marcas = marca.allMatches(fila).toList();
      if (marcas.isEmpty) continue;
      final String texto = fila.substring(marcas.last.end).trim();
      for (final RegExpMatch m in marcas) {
        final String centesimas = (m.group(3) ?? '0').padRight(3, '0');
        lineas.add(LineaLetra(
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: int.parse(centesimas),
          ),
          texto,
        ));
      }
    }
    lineas.sort((LineaLetra a, LineaLetra b) => a.desde.compareTo(b.desde));
    return lineas;
  }

  /// De entre lo que devuelve el servidor, la que mejor encaja.
  ///
  /// Manda la duracion: un mismo tema tiene version de album, remix y directo,
  /// y la que dura lo que dura nuestro archivo es casi siempre la buena. Entre
  /// dos igual de cerca, gana la que viene sincronizada.
  static Map<String, dynamic>? mejorCandidata(
    List<dynamic> candidatas,
    num duracion,
  ) {
    Map<String, dynamic>? mejor;
    num mejorPena = double.infinity;

    for (final dynamic cruda in candidatas) {
      if (cruda is! Map<String, dynamic>) continue;
      final bool sincronizada = (cruda['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      final bool hayLetra =
          sincronizada || ((cruda['plainLyrics'] as String?)?.isNotEmpty ?? false);
      if (!hayLetra) continue;

      final num suya = (cruda['duration'] as num?) ?? 0;
      // Sin duracion nuestra no se puede comparar: entonces solo pesa el tener
      // sincronizacion, y se queda la primera que la traiga.
      final num distancia = duracion <= 0 || suya <= 0 ? 0 : (suya - duracion).abs();
      final num pena = distancia + (sincronizada ? 0 : 1000);
      if (pena < mejorPena) {
        mejorPena = pena;
        mejor = cruda;
      }
    }
    return mejor;
  }

  /// La letra de una pista: primero de lo guardado, si no de la red.
  ///
  /// Nunca lanza: quedarse sin letra no puede tumbar el reproductor, y sin
  /// internet lo normal es que falle.
  static Future<Letra> de({
    required String uri,
    required String nombre,
    required num duracion,
  }) async {
    final ({String lrc, String texto})? guardada = await Catalogo.instancia.letraDe(uri);
    if (guardada != null) {
      return Letra(lineas: analizarLrc(guardada.lrc), texto: guardada.texto);
    }

    final Letra traida = await _pedir(consultaDe(nombre), duracion);
    await Catalogo.instancia.guardarLetra(
      uri,
      lrc: traida.lineas.isEmpty ? '' : _aLrc(traida.lineas),
      texto: traida.texto,
    );
    return traida;
  }

  static Future<Letra> _pedir(String consulta, num duracion) async {
    if (consulta.isEmpty) return const Letra.ninguna();
    final HttpClient cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest peticion = await cliente.getUrl(
        Uri.https(_servidor, '/api/search', <String, String>{'q': consulta}),
      );
      peticion.headers.set(HttpHeaders.userAgentHeader, _agente);
      final HttpClientResponse respuesta = await peticion.close();
      if (respuesta.statusCode != 200) return const Letra.ninguna();

      final String cuerpo = await respuesta.transform(utf8.decoder).join();
      final dynamic datos = jsonDecode(cuerpo);
      if (datos is! List<dynamic>) return const Letra.ninguna();

      final Map<String, dynamic>? elegida = mejorCandidata(datos, duracion);
      if (elegida == null) return const Letra.ninguna();

      final String lrc = elegida['syncedLyrics'] as String? ?? '';
      return Letra(
        lineas: analizarLrc(lrc),
        texto: elegida['plainLyrics'] as String? ?? '',
      );
    } catch (_) {
      // Sin red, con el servidor caido o con una respuesta rara: sin letra.
      return const Letra.ninguna();
    } finally {
      cliente.close(force: true);
    }
  }

  /// Vuelve a dejar las lineas en LRC para guardarlas tal cual llegaron.
  static String _aLrc(List<LineaLetra> lineas) => lineas
      .map((LineaLetra l) {
        final String minutos = l.desde.inMinutes.toString().padLeft(2, '0');
        final String segundos = (l.desde.inSeconds % 60).toString().padLeft(2, '0');
        final String centesimas =
            (l.desde.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');
        return '[$minutos:$segundos.$centesimas]${l.texto}';
      })
      .join('\n');
}
