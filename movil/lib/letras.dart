import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'formato.dart';
import 'nucleo.dart';

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
    this.otraVersion = Duration.zero,
  });

  /// Letra vacia: se busco y no habia.
  const Letra.ninguna()
      : lineas = const <LineaLetra>[],
        texto = '',
        desfase = Duration.zero,
        otraVersion = Duration.zero;

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

  /// Cuanto dura de mas la version de la que son los tiempos (de menos si es
  /// negativo); cero si es la misma que el archivo. Con otra version los
  /// tiempos no se dan por buenos hasta cuadrarlos con la voz ([porCuadrar]).
  final Duration otraVersion;

  Letra conDesfase(Duration nuevo) =>
      Letra(lineas: lineas, texto: texto, desfase: nuevo, otraVersion: otraVersion);

  /// Ya cuadrada con la voz: sus tiempos valen, corridos [desfase].
  Letra cuadrada(Duration desfase) => Letra(lineas: lineas, texto: texto, desfase: desfase);

  bool get vacia => lineas.isEmpty && texto.trim().isEmpty;
  bool get sincronizada => lineas.isNotEmpty && otraVersion == Duration.zero;

  /// Trae tiempos, pero de otra version: hasta cuadrarlos se ensenia de corrido.
  bool get porCuadrar => lineas.isNotEmpty && otraVersion != Duration.zero;

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

/// Una letra que llega de una fuente, antes de guardarla.
typedef LetraTraida = ({String lrc, String texto, String fuente});

/// Busca letras en YouTube Music y en lrclib.
///
/// Ninguna pide clave ni cuenta, que es la condicion de siempre del proyecto.
/// YouTube Music va primero cuando la cancion se bajo de YouTube: se le pide
/// por el video exacto, asi que no puede dar la de otra cancion. lrclib queda
/// de respaldo, buscando por artista y titulo. Lo que se encuentra se guarda en
/// el catalogo, asi que a partir de la segunda vez la letra sale sin internet.
class Letras {
  const Letras._();

  /// Como se le pide la letra a YouTube Music por el id del video (en el
  /// telefono, letras_ytm.py). Las pruebas lo cambian.
  @visibleForTesting
  static Future<LetraTraida?> Function(String video) youtube = Nucleo.letraYoutube;

  /// Como se le pregunta a lrclib: ruta y consulta, y devuelve el JSON. Las
  /// pruebas lo cambian.
  @visibleForTesting
  static Future<dynamic> Function(String ruta, Map<String, String> consulta) lrclib = _jsonLrclib;

  /// Con la busqueda de antes se colaban letras de otra cancion, y quedaban
  /// guardadas para siempre. La primera vez con esta version se olvidan las
  /// guardadas que no se ajustaron a mano, para buscarlas otra vez.
  static const String claveRevision = 'letras_revisadas_v2';

  /// La segunda revision: las que se guardaron de corrido por ser de otra
  /// version se vuelven a buscar, ahora con sus tiempos para cuadrarlos.
  static const String claveRevisionDeCorrido = 'letras_revisadas_v3';

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
    String artista = '',
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
      // El mismo titulo de otro artista es otra cancion. Solo se mira si se
      // sabe el artista de los dos lados.
      final String suArtista = cruda['artistName']?.toString() ?? '';
      if (artista.isNotEmpty && suArtista.isNotEmpty && parecido(suArtista, artista) < artistaMinimo) continue;

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

  /// Cuanto se tiene que parecer el artista, cuando se sabe.
  static const double artistaMinimo = 0.5;

  /// Cuanto puede diferir la duracion, en segundos, para ser la misma version.
  /// Mas alla es otra (un directo, un remix, un videoclip con escenas): las
  /// palabras valen, pero sus tiempos no le van a nuestro archivo.
  static const int margenDuracion = 20;

  /// Si [candidata] es otra version que [duracion] (ver [margenDuracion]).
  static bool otraVersion(Map<String, dynamic> candidata, num duracion) =>
      diferencia((candidata['duration'] as num?) ?? 0, duracion) != Duration.zero;

  /// Cuanto dura de mas la version de [suya] segundos que el archivo de
  /// [duracion]; cero si se sabe poco o caben en [margenDuracion].
  static Duration diferencia(num suya, num duracion) {
    if (duracion <= 0 || suya <= 0 || (suya - duracion).abs() <= margenDuracion) return Duration.zero;
    return Duration(milliseconds: ((suya - duracion) * 1000).round());
  }

  /// Hasta donde se busca el ajuste de una letra de otra version: lo que
  /// difieren, mas el margen de siempre.
  static Duration rangoDeCuadre(Letra letra) => letra.otraVersion.abs() + const Duration(seconds: 8);

  /// La etiqueta LRC con la duracion de la version de los tiempos. Se guarda
  /// con la letra para saber, al leerla, que hay que cuadrarla.
  static final RegExp _largo = RegExp(r'^\[length:\s*(\d+):(\d{2})(?:\.(\d+))?\]', multiLine: true);

  static num? largoDe(String lrc) {
    final RegExpMatch? m = _largo.firstMatch(lrc);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  /// La letra de una pista: primero de lo guardado, si no de la red.
  ///
  /// [artista] y [tema] son los de la cancion (los de sus etiquetas si las
  /// tiene); si faltan, se sacan del nombre del archivo. Con [deNuevo] se
  /// olvida lo guardado y se busca otra vez.
  ///
  /// Nunca lanza: quedarse sin letra no puede tumbar el reproductor, y sin
  /// internet lo normal es que falle.
  static Future<Letra> de({
    required String uri,
    required String nombre,
    required num duracion,
    String artista = '',
    String tema = '',
    bool deNuevo = false,
  }) async {
    if (deNuevo) await Catalogo.instancia.olvidarLetra(uri);
    final ({String lrc, String texto, int desfase})? guardada =
        await Catalogo.instancia.letraDe(uri);
    if (guardada != null) {
      final List<LineaLetra> lineas = analizarLrc(guardada.lrc);
      return Letra(
        lineas: lineas,
        texto: guardada.texto.trim().isNotEmpty ? guardada.texto : lineas.map((LineaLetra l) => l.texto).join('\n'),
        desfase: Duration(milliseconds: guardada.desfase),
        otraVersion: diferencia(largoDe(guardada.lrc) ?? 0, duracion),
      );
    }

    final ({String artista, String tema}) delNombre = partesDe(nombre);
    final ({String artista, String tema}) partes = (
      artista: artista.trim().isNotEmpty ? artista.trim() : delNombre.artista,
      tema: tema.trim().isNotEmpty ? tema.trim() : delNombre.tema,
    );
    final Letra traida = await _pedir(
      partes,
      consultaDe(nombre),
      duracion,
      video: await Catalogo.instancia.videoDe(uri),
    );
    await Catalogo.instancia.guardarLetra(
      uri,
      lrc: traida.lineas.isEmpty
          ? ''
          : traida.porCuadrar
              ? '${_etiquetaLargo(duracion, traida.otraVersion)}\n${_aLrc(traida.lineas)}'
              : _aLrc(traida.lineas),
      texto: traida.texto,
    );
    return traida;
  }

  /// Da por buenos los tiempos de una letra de otra version, corridos
  /// [desfase]: lo ha confirmado la voz. Se guarda ya sin la etiqueta.
  static Future<Letra> cuadrar(String uri, Letra letra, Duration desfase) async {
    final Letra hecha = letra.cuadrada(desfase);
    await Catalogo.instancia.guardarLetra(uri, lrc: _aLrc(letra.lineas), texto: letra.texto);
    await Catalogo.instancia.guardarDesfase(uri, desfase.inMilliseconds);
    return hecha;
  }

  static String _etiquetaLargo(num duracion, Duration otraVersion) {
    final int segundos = (duracion + otraVersion.inMilliseconds / 1000).round();
    return '[length:${(segundos ~/ 60).toString().padLeft(2, '0')}:${(segundos % 60).toString().padLeft(2, '0')}]';
  }

  /// Una sola vez por instalacion, al arrancar (ver [claveRevision]).
  static Future<void> revisarGuardadas() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(claveRevision) ?? false)) {
        // Esta ya se lleva tambien las de corrido.
        await Catalogo.instancia.olvidarLetrasSinAjustar();
      } else if (!(prefs.getBool(claveRevisionDeCorrido) ?? false)) {
        await Catalogo.instancia.olvidarLetrasDeCorrido();
      } else {
        return;
      }
      await prefs.setBool(claveRevision, true);
      await prefs.setBool(claveRevisionDeCorrido, true);
    } catch (_) {
      // Si no se puede, se intenta la proxima vez que se abra la app.
    }
  }

  @visibleForTesting
  static void reiniciar() {
    youtube = (String _) async => null;
    lrclib = _jsonLrclib;
  }

  /// Pregunta a las fuentes por orden y se queda con la mejor respuesta.
  ///
  /// Una letra sincronizada de una fuente fiable gana a todo; si solo hay
  /// letra de corrido, se sigue buscando una sincronizada antes de darla.
  static Future<Letra> _pedir(
    ({String artista, String tema}) partes,
    String consulta,
    num duracion, {
    String? video,
  }) async {
    Letra? deCorrido;
    if (video != null) {
      final Letra deYoutube = await _deYoutube(video);
      if (deYoutube.sincronizada) return deYoutube;
      if (!deYoutube.vacia) deCorrido = deYoutube;
    }
    final Letra deLrclib = await _deLrclib(partes, consulta, duracion);
    // La de otra version tambien gana a la de corrido: trae tiempos, y la voz
    // puede cuadrarlos.
    if (deLrclib.sincronizada || deLrclib.porCuadrar) return deLrclib;
    return deCorrido ?? deLrclib;
  }

  static Future<Letra> _deYoutube(String video) async {
    try {
      final LetraTraida? traida = await youtube(video);
      if (traida == null) return const Letra.ninguna();
      return Letra(lineas: analizarLrc(traida.lrc), texto: traida.texto);
    } catch (_) {
      return const Letra.ninguna();
    }
  }

  /// lrclib: primero por nombre exacto, luego buscando.
  static Future<Letra> _deLrclib(
    ({String artista, String tema}) partes,
    String consulta,
    num duracion,
  ) async {
    try {
      // La consulta exacta es la buena cuando se sabe el artista: el servidor
      // casa por nombre y duracion y no puede devolver otra cancion.
      if (partes.artista.isNotEmpty && partes.tema.isNotEmpty) {
        final Letra exacta = await _porNombre(partes, duracion);
        if (!exacta.vacia) return exacta;
      }
      final String texto =
          partes.artista.isNotEmpty && partes.tema.isNotEmpty ? '${partes.artista} ${partes.tema}' : consulta;
      return await _buscando(texto, partes, duracion);
    } catch (_) {
      // Sin red, con el servidor caido o con una respuesta rara: sin letra.
      return const Letra.ninguna();
    }
  }

  static Future<Letra> _porNombre(({String artista, String tema}) partes, num duracion) async {
    final Map<String, String> consulta = <String, String>{
      'artist_name': partes.artista,
      'track_name': partes.tema,
      // La duracion la usa el servidor para distinguir entre versiones, y la
      // aplica con holgura: si no cuadra ninguna responde que no hay.
      if (duracion > 0) 'duration': duracion.round().toString(),
    };
    final dynamic datos = await lrclib('/api/get', consulta);
    if (datos is! Map<String, dynamic>) return const Letra.ninguna();
    return _desde(datos);
  }

  static Future<Letra> _buscando(String consulta, ({String artista, String tema}) partes, num duracion) async {
    if (consulta.isEmpty) return const Letra.ninguna();
    final dynamic datos = await lrclib('/api/search', <String, String>{'q': consulta});
    if (datos is! List<dynamic>) return const Letra.ninguna();

    final Map<String, dynamic>? elegida =
        mejorCandidata(datos, duracion, tema: partes.tema, artista: partes.artista);
    if (elegida == null) return const Letra.ninguna();
    final Letra letra = _desde(elegida);
    final Duration otra = diferencia((elegida['duration'] as num?) ?? 0, duracion);
    return otra == Duration.zero ? letra : _deOtraVersion(letra, otra);
  }

  /// Una letra cuyos tiempos son de otra version: irian a destiempo, asi que
  /// se ensenia de corrido hasta que la voz diga cuanto correrlos.
  static Letra _deOtraVersion(Letra letra, Duration otra) => Letra(
        lineas: letra.lineas,
        texto: letra.texto.trim().isNotEmpty
            ? letra.texto
            : letra.lineas.map((LineaLetra l) => l.texto).join('\n'),
        otraVersion: letra.lineas.isEmpty ? Duration.zero : otra,
      );

  static Letra _desde(Map<String, dynamic> datos) => Letra(
    lineas: analizarLrc(datos['syncedLyrics'] as String? ?? ''),
    texto: datos['plainLyrics'] as String? ?? '',
  );

  static Future<dynamic> _jsonLrclib(String ruta, Map<String, String> consulta) async {
    final HttpClient cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest peticion = await cliente.getUrl(Uri.https(_servidor, ruta, consulta));
      peticion.headers.set(HttpHeaders.userAgentHeader, _agente);
      final HttpClientResponse respuesta = await peticion.close();
      if (respuesta.statusCode != 200) {
        // Se vacia el cuerpo o la conexion se queda a medias en el reaprovecho.
        await respuesta.drain<void>();
        return null;
      }
      return jsonDecode(await respuesta.transform(utf8.decoder).join());
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
