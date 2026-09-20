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
  const Letra({
    required this.lineas,
    required this.texto,
    this.desfase = Duration.zero,
  });

  /// Letra vacia: se busco y no habia.
  const Letra.ninguna()
      : lineas = const <LineaLetra>[],
        texto = '',
        desfase = Duration.zero;

  /// Las lineas con su marca de tiempo. Vacio si solo hay letra sin sincronizar.
  final List<LineaLetra> lineas;

  /// La letra de corrido, para cuando no hay sincronizacion.
  final String texto;

  /// Cuanto se retrasa la letra respecto al archivo.
  ///
  /// Las marcas del servidor son del disco, y el video de YouTube casi nunca
  /// empieza en el mismo punto: suele llevar una entradilla. Positivo retrasa
  /// la letra, negativo la adelanta.
  final Duration desfase;

  Letra conDesfase(Duration nuevo) =>
      Letra(lineas: lineas, texto: texto, desfase: nuevo);

  bool get vacia => lineas.isEmpty && texto.trim().isEmpty;
  bool get sincronizada => lineas.isNotEmpty;

  /// Que linea toca en [instante], o -1 si aun no empezo.
  ///
  /// Busca hacia atras porque la primera linea suele entrar bastante despues
  /// del segundo cero, y hasta entonces no hay ninguna que resaltar.
  int lineaEn(Duration instante) {
    final Duration ajustado = instante - desfase;
    int encontrada = -1;
    for (int i = 0; i < lineas.length; i++) {
      if (lineas[i].desde > ajustado) break;
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
  /// Con [conservarGuion] se respeta el guion que separa artista y tema, que
  /// es lo que necesita [partesDe]; sin el, todo queda en una sola frase.
  static String consultaDe(String nombre, {bool conservarGuion = false}) {
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
    texto = texto.replaceAll(RegExp(conservarGuion ? '_+' : r'[_\-]+'), ' ');
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

  /// Parte «Artista - Tema» en sus dos mitades.
  ///
  /// Se corta por el primer guion y no por el ultimo: hay temas que llevan
  /// guion dentro, pero el artista casi nunca.
  static ({String artista, String tema}) partesDe(String nombre) =>
      partirNombre(consultaDe(nombre, conservarGuion: true));

  /// Cuantos de los terminos de [referencia] estan en [candidato], de 0 a 1.
  static double parecido(String candidato, String referencia) {
    final List<String> buscados = _terminos(referencia);
    if (buscados.isEmpty) return 0;
    final Set<String> tiene = _terminos(candidato).toSet();
    return buscados.where(tiene.contains).length / buscados.length;
  }

  static List<String> _terminos(String texto) => sinTildes(texto)
      .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList();

  /// Cuanto se tiene que parecer el nombre para dar la letra por buena.
  ///
  /// El buscador del servidor es generoso: pidiendo un tema de un grupo
  /// devuelve medio catalogo del grupo. Sin este filtro se colaba la letra de
  /// otra cancion solo porque duraba parecido.
  static const double parecidoMinimo = 0.75;

  /// De entre lo que devuelve el servidor, la que mejor encaja.
  ///
  /// Primero manda el nombre: una letra equivocada es peor que ninguna, asi
  /// que lo que no se parece se descarta aunque no quede nada. Entre las que
  /// si son el tema, gana la que dura lo que nuestro archivo, porque un mismo
  /// tema tiene version de album, remix y directo; y a igualdad, la
  /// sincronizada.
  static Map<String, dynamic>? mejorCandidata(
    List<dynamic> candidatas,
    num duracion, {
    String tema = '',
  }) {
    Map<String, dynamic>? mejor;
    num mejorPena = double.infinity;

    for (final dynamic cruda in candidatas) {
      if (cruda is! Map<String, dynamic>) continue;
      final bool sincronizada = (cruda['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      final bool hayLetra =
          sincronizada || ((cruda['plainLyrics'] as String?)?.isNotEmpty ?? false);
      if (!hayLetra) continue;

      if (tema.isNotEmpty) {
        final String suyo = cruda['trackName']?.toString() ?? '';
        if (parecido(suyo, tema) < parecidoMinimo) continue;
      }

      final num suya = (cruda['duration'] as num?) ?? 0;
      // Sin duracion con la que comparar no se descarta, pero tampoco puede
      // ganarle a una que si encaja: antes puntuaba cero y salia elegida
      // siempre, que era justo al reves de lo que se busca.
      final num distancia =
          duracion <= 0 || suya <= 0 ? _penaSinDuracion : (suya - duracion).abs();
      final num pena = distancia + (sincronizada ? 0 : 1000);
      if (pena < mejorPena) {
        mejorPena = pena;
        mejor = cruda;
      }
    }
    return mejor;
  }

  /// Lo que penaliza no poder comparar duraciones, en segundos equivalentes.
  static const int _penaSinDuracion = 30;

  /// La letra de una pista: primero de lo guardado, si no de la red.
  ///
  /// Nunca lanza: quedarse sin letra no puede tumbar el reproductor, y sin
  /// internet lo normal es que falle.
  static Future<Letra> de({
    required String uri,
    required String nombre,
    required num duracion,
  }) async {
    final ({String lrc, String texto, int desfase})? guardada =
        await Catalogo.instancia.letraDe(uri);
    if (guardada != null) {
      return Letra(
        lineas: analizarLrc(guardada.lrc),
        texto: guardada.texto,
        desfase: Duration(milliseconds: guardada.desfase),
      );
    }

    final Letra traida = await _pedir(nombre, duracion);
    await Catalogo.instancia.guardarLetra(
      uri,
      lrc: traida.lineas.isEmpty ? '' : _aLrc(traida.lineas),
      texto: traida.texto,
    );
    return traida;
  }

  /// Pide la letra al servidor: primero por nombre exacto, luego buscando.
  static Future<Letra> _pedir(String nombre, num duracion) async {
    final ({String artista, String tema}) partes = partesDe(nombre);
    final HttpClient cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      // La consulta exacta es la buena cuando el archivo trae «Artista - Tema»:
      // el servidor casa por nombre y no puede devolver otra cancion.
      if (partes.artista.isNotEmpty && partes.tema.isNotEmpty) {
        final Letra exacta = await _porNombre(cliente, partes, duracion);
        if (!exacta.vacia) return exacta;
      }
      return await _buscando(cliente, consultaDe(nombre), partes.tema, duracion);
    } catch (_) {
      // Sin red, con el servidor caido o con una respuesta rara: sin letra.
      return const Letra.ninguna();
    } finally {
      cliente.close(force: true);
    }
  }

  static Future<Letra> _porNombre(
    HttpClient cliente,
    ({String artista, String tema}) partes,
    num duracion,
  ) async {
    final Map<String, String> consulta = <String, String>{
      'artist_name': partes.artista,
      'track_name': partes.tema,
      // La duracion la usa el servidor para distinguir entre versiones, y la
      // aplica con holgura: si no cuadra ninguna responde que no hay.
      if (duracion > 0) 'duration': duracion.round().toString(),
    };
    final dynamic datos = await _json(cliente, '/api/get', consulta);
    if (datos is! Map<String, dynamic>) return const Letra.ninguna();
    return _desde(datos);
  }

  static Future<Letra> _buscando(
    HttpClient cliente,
    String consulta,
    String tema,
    num duracion,
  ) async {
    if (consulta.isEmpty) return const Letra.ninguna();
    final dynamic datos =
        await _json(cliente, '/api/search', <String, String>{'q': consulta});
    if (datos is! List<dynamic>) return const Letra.ninguna();

    final Map<String, dynamic>? elegida =
        mejorCandidata(datos, duracion, tema: tema);
    return elegida == null ? const Letra.ninguna() : _desde(elegida);
  }

  static Letra _desde(Map<String, dynamic> datos) => Letra(
    lineas: analizarLrc(datos['syncedLyrics'] as String? ?? ''),
    texto: datos['plainLyrics'] as String? ?? '',
  );

  static Future<dynamic> _json(
    HttpClient cliente,
    String ruta,
    Map<String, String> consulta,
  ) async {
    final HttpClientRequest peticion =
        await cliente.getUrl(Uri.https(_servidor, ruta, consulta));
    peticion.headers.set(HttpHeaders.userAgentHeader, _agente);
    final HttpClientResponse respuesta = await peticion.close();
    if (respuesta.statusCode != 200) {
      // Se vacia el cuerpo o la conexion se queda a medias en el reaprovecho.
      await respuesta.drain<void>();
      return null;
    }
    return jsonDecode(await respuesta.transform(utf8.decoder).join());
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
