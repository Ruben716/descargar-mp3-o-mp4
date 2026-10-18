import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canales_oficiales.dart';
import 'catalogo.dart';
import 'formato.dart';
import 'hecho_para_ti.dart';
import 'nucleo.dart';

/// Una cancion de la que pedir la radio: de quien es y, si se bajo de
/// YouTube, su video. Sin video hay que buscarla antes.
typedef Semilla = ({String artista, String tema, String? video});

/// «Descubre»: cada semana, canciones que no tienes parecidas a lo que mas oyes.
///
/// Sale de la radio de YouTube Music de una cancion de cada uno de tus
/// artistas mas escuchados: la lista «RDAMVM» del video, que el motor lee sin
/// cuenta como cualquier otra. Se quita lo que ya esta en la biblioteca y se
/// turnan las radios, para que no salgan diez seguidas del mismo artista.
///
/// Se guarda en el telefono: Inicio la ensenia sin esperar a la red, y solo se
/// vuelve a armar cuando pasa una semana.
class Descubre extends ChangeNotifier {
  Descubre._();

  static final Descubre instancia = Descubre._();

  static const String clave = 'descubre_v1';
  static const Duration cadaCuanto = Duration(days: 7);

  /// De cuantos artistas se piden radios. Cada una es una consulta.
  static const int cuantasSemillas = 4;
  static const int largo = 30;

  /// Lo que no es una cancion: intros de segundos o mezclas de una hora.
  static const double minimo = 60;
  static const double maximo = 12 * 60;

  List<Resultado> _pistas = const <Resultado>[];
  List<String> _artistas = const <String>[];
  DateTime? _hecha;
  bool _cargada = false;
  bool _armando = false;

  /// La lista de la semana; vacia si aun no se armo.
  List<Resultado> get pistas => _pistas;

  /// De quienes salio, para decirlo en pantalla.
  List<String> get artistas => _artistas;

  DateTime? get hecha => _hecha;
  bool get armando => _armando;

  /// La radio de YouTube Music de un video: la que sale al pulsar «Iniciar radio».
  static String radioDe(String video) => 'https://www.youtube.com/watch?v=$video&list=RDAMVM$video';

  /// La misma toda la semana y distinta la siguiente.
  static int semanaDe(DateTime dia) =>
      DateTime.utc(dia.year, dia.month, dia.day).millisecondsSinceEpoch ~/ const Duration(days: 7).inMilliseconds;

  /// «artista tema» sin tildes ni signos: para saber si ya la tienes aunque
  /// llegara de otra fuente o con otro titulo («(Official Video)», «- Topic»).
  static String claveDe(String artista, String tema) => CanalesOficiales.normalizar('$artista $tema').trim();

  static ({String artista, String tema}) partesDe(Resultado r) =>
      nombreVisible(r.titulo, titulo: r.titulo, artista: r.autor);

  /// La miniatura, o la de YouTube por su video si la lista no la trajo.
  static String portadaDe(Resultado r) {
    if (r.miniatura.isNotEmpty) return r.miniatura;
    final String? video = Catalogo.identificador(r.url);
    return video == null ? '' : 'https://i.ytimg.com/vi/$video/hqdefault.jpg';
  }

  /// «A, B y C».
  static String unir(List<String> nombres) => nombres.length <= 1
      ? nombres.join()
      : '${nombres.take(nombres.length - 1).join(', ')} y ${nombres.last}';

  /// De que canciones pedir radio esta semana.
  ///
  /// Los dos artistas que mas oyes van siempre; los demas se sortean entre los
  /// ocho siguientes, para que cada semana traiga algo distinto. De cada uno,
  /// una de sus tres canciones mas oidas, tambien sorteada.
  ///
  /// [videos] es el video de YouTube de cada cancion, por su URI.
  static List<Semilla> elegirSemillas(
    List<Elemento> canciones,
    Map<String, Escucha> escuchas,
    Map<String, String> videos, {
    required int semana,
    int cuantas = cuantasSemillas,
  }) {
    final List<({String artista, List<Elemento> pistas})> todos = HechoParaTi.artistas(canciones, escuchas);
    final Random azar = Random(semana);
    final List<({String artista, List<Elemento> pistas})> resto = todos.skip(2).take(8).toList()..shuffle(azar);
    final List<({String artista, List<Elemento> pistas})> elegidos = <({String artista, List<Elemento> pistas})>[
      ...todos.take(2),
      ...resto,
    ].take(cuantas).toList();
    return <Semilla>[
      for (final ({String artista, List<Elemento> pistas}) a in elegidos) _semillaDe(a.artista, a.pistas, escuchas, videos, azar),
    ];
  }

  static Semilla _semillaDe(
    String artista,
    List<Elemento> pistas,
    Map<String, Escucha> escuchas,
    Map<String, String> videos,
    Random azar,
  ) {
    int veces(Elemento e) => escuchas[e.uri]?.veces ?? 0;
    final List<Elemento> masOidas = List<Elemento>.of(pistas)
      ..sort((Elemento a, Elemento b) {
        final int porVeces = veces(b).compareTo(veces(a));
        return porVeces != 0 ? porVeces : a.uri.compareTo(b.uri);
      });
    final List<Elemento> tres = masOidas.take(3).toList();
    final Elemento e = tres[azar.nextInt(tres.length)];
    return (artista: artista, tema: e.tema, video: videos[e.uri]);
  }

  /// Junta las radios en una sola lista: se van turnando, sin repetir y sin
  /// lo que ya tienes.
  ///
  /// [tengo] son los videos ya bajados; [conocidas], las [claveDe] de la
  /// biblioteca, para lo que llego de otra fuente o desde otro video.
  static List<Resultado> armar(
    List<List<Resultado>> radios, {
    required Set<String> tengo,
    required Set<String> conocidas,
    int cuantas = largo,
  }) {
    bool vale(Resultado r) {
      if (r.duracion > 0 && (r.duracion < minimo || r.duracion > maximo)) return false;
      final String? video = Catalogo.identificador(r.url);
      if (video != null && tengo.contains(video)) return false;
      final ({String artista, String tema}) p = partesDe(r);
      return !conocidas.contains(claveDe(p.artista, p.tema));
    }

    final List<List<Resultado>> buenas = <List<Resultado>>[
      for (final List<Resultado> radio in radios) radio.where(vale).toList(),
    ];
    final List<Resultado> salida = <Resultado>[];
    final Set<String> vistas = <String>{};
    for (int vuelta = 0; salida.length < cuantas; vuelta++) {
      bool quedaban = false;
      for (final List<Resultado> radio in buenas) {
        if (vuelta >= radio.length) continue;
        quedaban = true;
        final Resultado r = radio[vuelta];
        final ({String artista, String tema}) p = partesDe(r);
        // La misma cancion sale en varias radios, y a veces desde dos videos
        // (el del sello y el «Topic»): cuenta una vez.
        final String video = Catalogo.identificador(r.url) ?? r.url;
        if (!vistas.add(video) | !vistas.add(claveDe(p.artista, p.tema))) continue;
        salida.add(r);
        if (salida.length == cuantas) break;
      }
      if (!quedaban) break;
    }
    return salida;
  }

  /// Lee la lista guardada. No sale a la red.
  Future<void> cargar() async {
    if (_cargada) return;
    _cargada = true;
    try {
      final String? guardada = (await SharedPreferences.getInstance()).getString(clave);
      if (guardada == null) return;
      final Map<String, dynamic> datos = jsonDecode(guardada) as Map<String, dynamic>;
      _hecha = DateTime.fromMillisecondsSinceEpoch(datos['hecha'] as int);
      _artistas = <String>[for (final dynamic a in datos['artistas'] as List<dynamic>) '$a'];
      _pistas = <Resultado>[
        for (final dynamic p in datos['pistas'] as List<dynamic>) Resultado.desdeJson(p as Map<String, dynamic>),
      ];
      notifyListeners();
    } catch (_) {
      // Una lista guardada que no se entiende se rehace a la proxima.
    }
  }

  Future<void> _guardar() async {
    await (await SharedPreferences.getInstance()).setString(
      clave,
      jsonEncode(<String, Object>{
        'hecha': _hecha!.millisecondsSinceEpoch,
        'artistas': _artistas,
        'pistas': <Map<String, Object>>[
          for (final Resultado r in _pistas)
            <String, Object>{
              'titulo': r.titulo,
              'autor': r.autor,
              'duracion': r.duracion,
              'url': r.url,
              'miniatura': r.miniatura,
            },
        ],
      }),
    );
  }

  /// La vuelve a armar si ya paso una semana o si nunca se armo.
  Future<void> rehacerSiToca() async {
    await cargar();
    final DateTime? hecha = _hecha;
    if (hecha != null && DateTime.now().difference(hecha) < cadaCuanto) return;
    await rehacer();
  }

  /// Pide las radios y arma la lista. Si no llega nada (sin red, por
  /// ejemplo), se queda la de antes.
  Future<void> rehacer() async {
    if (_armando) return;
    _armando = true;
    notifyListeners();
    try {
      final List<Elemento> canciones =
          (await Nucleo.biblioteca()).where((Elemento e) => e.audio).toList();
      final Map<String, Escucha> escuchas = await Catalogo.instancia.escuchasConFecha();
      final Map<String, String> bajados = await Catalogo.instancia.videos();
      final DateTime ahora = DateTime.now();
      final List<Semilla> semillas = elegirSemillas(
        canciones,
        escuchas,
        <String, String>{for (final MapEntry<String, String> v in bajados.entries) v.value: v.key},
        semana: semanaDe(ahora),
      );
      if (semillas.isEmpty) return;
      final List<List<Resultado>> radios = await Future.wait(<Future<List<Resultado>>>[
        for (final Semilla s in semillas) radioDeSemilla(s),
      ]);
      final List<Resultado> lista = armar(
        radios,
        tengo: bajados.keys.toSet(),
        conocidas: <String>{for (final Elemento e in canciones) claveDe(e.artista, e.tema)},
      );
      if (lista.isEmpty) return;
      _pistas = lista;
      _artistas = <String>[for (final Semilla s in semillas) s.artista];
      _hecha = ahora;
      await _guardar();
    } catch (_) {
      // Sin biblioteca o sin catalogo no hay nada que descubrir todavia.
    } finally {
      _armando = false;
      notifyListeners();
    }
  }

  /// La radio de una semilla; si no se bajo de YouTube, se busca antes en
  /// YouTube Music. Vacia si no se pudo.
  static Future<List<Resultado>> radioDeSemilla(Semilla s) async {
    try {
      String? video = s.video;
      if (video == null) {
        final List<Resultado> hallados =
            await Nucleo.buscar('${s.artista} ${s.tema}', limite: 1, fuente: Fuente.ytmusic.clave);
        video = hallados.isEmpty ? null : Catalogo.identificador(hallados.first.url);
      }
      if (video == null) return const <Resultado>[];
      return (await Nucleo.importarLista(radioDe(video))).pistas;
    } catch (_) {
      return const <Resultado>[];
    }
  }

  @visibleForTesting
  void reiniciar() {
    _pistas = const <Resultado>[];
    _artistas = const <String>[];
    _hecha = null;
    _cargada = false;
    _armando = false;
  }
}
