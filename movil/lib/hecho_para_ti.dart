import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dj.dart';
import 'emisora.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'ritmos.dart';

/// Cuantas veces y cuando fue la ultima (en milisegundos), de una cancion.
typedef Escucha = ({int veces, int ultima});

/// De que va un mix: decide su icono y su color en pantalla.
enum ClaseMix {
  diario,
  redescubre,
  sinEscuchar,
  repeticion,
  artista,
  moverse,
  tranqui,
  concentrarte,
  sesionDj,
}

/// Un mix armado por la app con lo que ya hay en el telefono.
@immutable
class Mix {
  const Mix({
    required this.titulo,
    required this.subtitulo,
    required this.pistas,
    required this.clase,
    this.modoDj = ModoDj.flujo,
  });

  final String titulo;
  final String subtitulo;
  final List<Elemento> pistas;
  final ClaseMix clase;

  /// Como lo ordena el DJ si se pide la mezcla.
  final ModoDj modoDj;

  /// La «Sesion DJ»: su boton principal mezcla en vez de reproducir en orden.
  bool get comoDj => clase == ClaseMix.sesionDj;
}

/// «Hecho para ti» y «Tus mixes»: mezclas que se arman solas, sin red.
///
/// Todo son funciones puras con el azar inyectado. Con la semilla del dia
/// ([semillaDelDia]) un mix no cambia en cada recarga, solo de un dia a otro,
/// que es lo que hacen los «Mix diario» de Spotify.
class HechoParaTi {
  HechoParaTi._();

  /// Por debajo no hay de donde sacar mixes que digan algo.
  static const int minimoCanciones = 8;

  /// Un mix con menos se queda en nada: no se ensenia.
  static const int minimoPorMix = 3;

  /// Los de animo piden algo mas, o «Tranqui» serian dos canciones.
  static const int minimoPorAnimo = 5;

  /// Cuantas tiene que haber analizado el DJ para hablar de animos.
  static const int minimoAnalizadas = 8;

  /// Un artista necesita al menos tantas para tener su mix.
  static const int minimoPorArtista = 3;

  /// Lo que dura un mix, como una radio de [Emisora].
  static const int largo = Emisora.largo;

  /// Lo que lleva sin sonar para que valga la pena redescubrirlo.
  static const Duration olvido = Duration(days: 30);

  /// Las muy largas (sesiones, episodios) no entran en un mix de animo.
  static const Duration largoMaximo = Duration(minutes: 12);

  /// La misma durante todo el dia y distinta al siguiente.
  static int semillaDelDia(DateTime dia) => dia.year * 10000 + dia.month * 100 + dia.day;

  static String _clave(String artista) => sinTildes(artista.trim());

  /// Los artistas de [canciones], del mas oido al menos.
  ///
  /// Sin escuchas manda cuantas canciones tiene cada uno. Lo que no dice
  /// artista no cuenta: «Sin artista» no es nadie a quien hacerle un mix.
  static List<({String artista, List<Elemento> pistas})> artistas(
    List<Elemento> canciones,
    Map<String, Escucha> escuchas, {
    int minimo = 1,
  }) {
    final Map<String, List<Elemento>> grupos = <String, List<Elemento>>{};
    final Map<String, String> nombres = <String, String>{};
    for (final Elemento e in canciones) {
      final String artista = e.artista.trim();
      if (!e.audio || artista.isEmpty) continue;
      final String clave = _clave(artista);
      grupos.putIfAbsent(clave, () => <Elemento>[]).add(e);
      nombres.putIfAbsent(clave, () => artista);
    }
    int veces(String clave) =>
        grupos[clave]!.fold(0, (int s, Elemento e) => s + (escuchas[e.uri]?.veces ?? 0));
    final List<String> claves = grupos.keys.where((String c) => grupos[c]!.length >= minimo).toList()
      ..sort((String a, String b) {
        final int porVeces = veces(b).compareTo(veces(a));
        if (porVeces != 0) return porVeces;
        final int porCuantas = grupos[b]!.length.compareTo(grupos[a]!.length);
        return porCuantas != 0 ? porCuantas : a.compareTo(b);
      });
    return <({String artista, List<Elemento> pistas})>[
      for (final String c in claves) (artista: nombres[c]!, pistas: grupos[c]!),
    ];
  }

  /// De la mas oida a la menos; el azar solo deshace los empates.
  ///
  /// Se sortea antes una clave por cancion: `sort` no es estable, y barajar y
  /// ordenar despues no garantizaria nada.
  static List<Elemento> _porEscuchas(List<Elemento> pistas, Map<String, Escucha> escuchas, Random azar) {
    final Map<String, double> sorteo = <String, double>{for (final Elemento e in pistas) e.uri: azar.nextDouble()};
    return List<Elemento>.of(pistas)
      ..sort((Elemento a, Elemento b) {
        final int porVeces = (escuchas[b.uri]?.veces ?? 0).compareTo(escuchas[a.uri]?.veces ?? 0);
        return porVeces != 0 ? porVeces : sorteo[a.uri]!.compareTo(sorteo[b.uri]!);
      });
  }

  /// Intercala dos listas: [cada] de la primera por una de la segunda.
  static List<Elemento> _intercalar(List<Elemento> propias, List<Elemento> otras, {int cada = 1}) {
    final List<Elemento> salida = <Elemento>[];
    int i = 0;
    int j = 0;
    while (i < propias.length || j < otras.length) {
      for (int k = 0; k < cada && i < propias.length; k++) {
        salida.add(propias[i++]);
      }
      if (j < otras.length) salida.add(otras[j++]);
    }
    return salida;
  }

  static Map<String, int> _veces(Map<String, Escucha> escuchas) => <String, int>{
        for (final MapEntry<String, Escucha> e in escuchas.entries) e.key: e.value.veces,
      };

  /// «A, B y C» o «A, B y mas».
  static String _nombres(List<String> nombres) {
    if (nombres.isEmpty) return 'Un poco de todo lo tuyo';
    if (nombres.length == 1) return '${nombres.first} y mas';
    return '${nombres.take(nombres.length - 1).join(', ')} y ${nombres.last}';
  }

  /// Mix diario 1 a [cuantos]: cada uno con sus artistas y relleno parecido.
  ///
  /// Los artistas se reparten como en un sorteo de mesas: el mas oido al 1,
  /// el segundo al 2, el tercero al 3, el cuarto otra vez al 1... Asi los
  /// tres son distintos. Lo que falta se rellena con la radio de [Emisora]
  /// a partir de la mas oida del artista principal.
  static List<Mix> mixesDiarios(
    List<Elemento> canciones, {
    required Map<String, Escucha> escuchas,
    required Random azar,
    Set<String> favoritas = const <String>{},
    int cuantos = 3,
  }) {
    final List<Elemento> audios = canciones.where((Elemento e) => e.audio).toList();
    if (audios.isEmpty) return <Mix>[];
    final List<({String artista, List<Elemento> pistas})> todos = artistas(audios, escuchas);
    final Map<String, int> veces = _veces(escuchas);
    final List<Mix> mixes = <Mix>[];
    for (int i = 0; i < cuantos; i++) {
      final List<({String artista, List<Elemento> pistas})> suyos = <({String artista, List<Elemento> pistas})>[
        for (int j = i; j < todos.length && j < i + 3 * cuantos; j += cuantos) todos[j],
      ];
      // Sin artistas que repartir, un solo mix con un poco de todo.
      if (suyos.isEmpty && i > 0) break;
      final List<Elemento> propias = suyos.isEmpty
          ? <Elemento>[audios[azar.nextInt(audios.length)]]
          : <Elemento>[
              for (final ({String artista, List<Elemento> pistas}) a in suyos) ..._porEscuchas(a.pistas, escuchas, azar),
            ];
      final Elemento semilla = propias.first;
      final List<Elemento> delMix = <Elemento>[
        semilla,
        ...(propias.skip(1).toList()..shuffle(azar)),
      ].take(largo ~/ 2).toList();
      final Set<String> dentro = <String>{for (final Elemento e in delMix) e.uri};
      final List<Elemento> relleno = <Elemento>[
        for (final Elemento e in Emisora.mezcla(semilla, audios, favoritas: favoritas, escuchas: veces, azar: azar))
          if (dentro.add(e.uri)) e,
      ].take(largo - delMix.length).toList();
      mixes.add(Mix(
        titulo: 'Mix diario ${i + 1}',
        subtitulo: _nombres(<String>[for (final ({String artista, List<Elemento> pistas}) a in suyos) a.artista]),
        pistas: _intercalar(delMix, relleno),
        clase: ClaseMix.diario,
      ));
    }
    return mixes;
  }

  /// Lo que gustaba (favorito o muy oido) y lleva mas de un mes sin sonar.
  static List<Elemento> redescubre(
    List<Elemento> canciones, {
    required Map<String, Escucha> escuchas,
    required DateTime ahora,
    Set<String> favoritas = const <String>{},
    int minimoVeces = 3,
  }) {
    final int limite = ahora.subtract(olvido).millisecondsSinceEpoch;
    final List<Elemento> olvidadas = <Elemento>[
      for (final Elemento e in canciones)
        if (escuchas[e.uri] case final Escucha x
            when e.audio &&
                x.ultima > 0 &&
                x.ultima < limite &&
                (favoritas.contains(e.uri) || x.veces >= minimoVeces))
          e,
    ];
    int puntos(Elemento e) => escuchas[e.uri]!.veces + (favoritas.contains(e.uri) ? 1000 : 0);
    olvidadas.sort((Elemento a, Elemento b) {
      final int porPuntos = puntos(b).compareTo(puntos(a));
      return porPuntos != 0 ? porPuntos : escuchas[a.uri]!.ultima.compareTo(escuchas[b.uri]!.ultima);
    });
    return olvidadas.take(largo).toList();
  }

  /// Lo bajado que aun no ha sonado nunca, de lo ultimo a lo primero.
  static List<Elemento> sinEscuchar(List<Elemento> canciones, Map<String, Escucha> escuchas) => <Elemento>[
        for (final Elemento e in canciones)
          if (e.audio && !escuchas.containsKey(e.uri)) e,
      ].take(largo).toList();

  /// Lo que se esta oyendo en bucle este mes, de lo que mas a lo que menos.
  static List<Elemento> tuRepeticion(
    List<Elemento> canciones, {
    required Map<String, Escucha> escuchas,
    required DateTime ahora,
    int minimoVeces = 2,
  }) {
    final int desde = ahora.subtract(olvido).millisecondsSinceEpoch;
    final List<Elemento> enBucle = <Elemento>[
      for (final Elemento e in canciones)
        if (escuchas[e.uri] case final Escucha x when e.audio && x.ultima >= desde && x.veces >= minimoVeces) e,
    ]..sort((Elemento a, Elemento b) {
        final int porVeces = escuchas[b.uri]!.veces.compareTo(escuchas[a.uri]!.veces);
        return porVeces != 0 ? porVeces : escuchas[b.uri]!.ultima.compareTo(escuchas[a.uri]!.ultima);
      });
    return enBucle.take(largo).toList();
  }

  /// Todo «Hecho para ti»: los Mix diario, Redescubre, Sin escuchar todavia y
  /// Tu repeticion. Vacio con menos de [minimoCanciones] canciones, y sin los
  /// mixes que se quedan en menos de [minimoPorMix].
  static List<Mix> armar(
    List<Elemento> biblioteca, {
    required Map<String, Escucha> escuchas,
    required DateTime ahora,
    Set<String> favoritas = const <String>{},
    Random? azar,
  }) {
    final List<Elemento> canciones = biblioteca.where((Elemento e) => e.audio).toList();
    if (canciones.length < minimoCanciones) return <Mix>[];
    final Random suerte = azar ?? Random(semillaDelDia(ahora));
    final List<Mix> mixes = <Mix>[
      ...mixesDiarios(canciones, escuchas: escuchas, favoritas: favoritas, azar: suerte),
      Mix(
        titulo: 'Redescubre',
        subtitulo: 'Lo que te gustaba y hace tiempo no suena',
        pistas: redescubre(canciones, escuchas: escuchas, favoritas: favoritas, ahora: ahora),
        clase: ClaseMix.redescubre,
      ),
      Mix(
        titulo: 'Sin escuchar todavia',
        subtitulo: 'Lo que bajaste y aun no has oido',
        pistas: sinEscuchar(canciones, escuchas),
        clase: ClaseMix.sinEscuchar,
      ),
      Mix(
        titulo: 'Tu repeticion',
        subtitulo: 'Lo que mas suena este mes',
        pistas: tuRepeticion(canciones, escuchas: escuchas, ahora: ahora),
        clase: ClaseMix.repeticion,
      ),
    ];
    return mixes.where((Mix m) => m.pistas.length >= minimoPorMix).toList();
  }

  /// El mix de un artista: sus canciones, de la mas oida a la menos, con
  /// algo de lo demas de [biblioteca] intercalado (una de cada tres).
  static Mix mixDeArtista(
    String artista,
    List<Elemento> suyas,
    List<Elemento> biblioteca, {
    Map<String, Escucha> escuchas = const <String, Escucha>{},
    Set<String> favoritas = const <String>{},
    Random? azar,
  }) {
    final Random suerte = azar ?? Random();
    final List<Elemento> propias = _porEscuchas(suyas.where((Elemento e) => e.audio).toList(), escuchas, suerte);
    final Set<String> dentro = <String>{for (final Elemento e in propias) e.uri};
    final List<Elemento> otras = propias.isEmpty
        ? <Elemento>[]
        : <Elemento>[
            for (final Elemento e in Emisora.mezcla(
              propias.first,
              biblioteca,
              favoritas: favoritas,
              escuchas: _veces(escuchas),
              azar: suerte,
            ))
              if (dentro.add(e.uri)) e,
          ].take(max(0, min(propias.length ~/ 2, largo - propias.length))).toList();
    return Mix(
      titulo: 'Mix de $artista',
      subtitulo: propias.length == 1 ? '1 cancion suya y algo mas' : '${propias.length} canciones suyas y algo mas',
      pistas: _intercalar(propias, otras, cada: 2),
      clase: ClaseMix.artista,
    );
  }

  /// Un «Mix de ...» por cada artista con [minimo] canciones o mas,
  /// hasta [maximo], del mas oido al menos.
  static List<Mix> mixesDeArtista(
    List<Elemento> biblioteca, {
    required Map<String, Escucha> escuchas,
    Set<String> favoritas = const <String>{},
    Random? azar,
    int minimo = minimoPorArtista,
    int maximo = 6,
  }) {
    final List<Elemento> canciones = biblioteca.where((Elemento e) => e.audio).toList();
    final Random suerte = azar ?? Random();
    return <Mix>[
      for (final ({String artista, List<Elemento> pistas}) a
          in artistas(canciones, escuchas, minimo: minimo).take(maximo))
        mixDeArtista(a.artista, a.pistas, canciones, escuchas: escuchas, favoritas: favoritas, azar: suerte),
    ];
  }

  /// Si una cancion es «para moverse»: de lo mas energico de la biblioteca
  /// o con pulso rapido.
  static bool _movida(double percentil, Rasgos? r) =>
      percentil >= 0.65 || (r != null && r.conPulso && r.bpm! >= 118);

  /// Para moverse, Tranqui, Para concentrarte y Sesion DJ.
  ///
  /// Solo con lo que el DJ ya analizo: [percentil] dice donde cae la energia
  /// de cada cancion dentro de la biblioteca (0 la mas tranquila, 1 la mas
  /// movida) y null si aun no se sabe. Los que se quedan en menos de
  /// [minimoPorAnimo] no salen.
  static List<Mix> mixesPorAnimo(
    List<Elemento> biblioteca, {
    required double? Function(String uri) percentil,
    required Rasgos? Function(String uri) rasgos,
    Random? azar,
  }) {
    final Random suerte = azar ?? Random();
    final List<({Elemento e, double p})> medidas = <({Elemento e, double p})>[
      for (final Elemento e in biblioteca)
        if (percentil(e.uri) case final double p when e.audio && e.duracion <= largoMaximo.inSeconds) (e: e, p: p),
    ];
    List<Elemento> donde(bool Function(({Elemento e, double p}) m) cumple) =>
        (<Elemento>[for (final ({Elemento e, double p}) m in medidas) if (cumple(m)) m.e]..shuffle(suerte))
            .take(largo)
            .toList();
    final List<Mix> mixes = <Mix>[
      Mix(
        titulo: 'Para moverse',
        subtitulo: 'Lo mas movido de lo tuyo',
        pistas: donde((({Elemento e, double p}) m) => _movida(m.p, rasgos(m.e.uri))),
        clase: ClaseMix.moverse,
        modoDj: ModoDj.subir,
      ),
      Mix(
        titulo: 'Tranqui',
        subtitulo: 'Lo mas suave, para bajar el ritmo',
        pistas: donde((({Elemento e, double p}) m) => m.p <= 0.35),
        clase: ClaseMix.tranqui,
        modoDj: ModoDj.bajar,
      ),
      Mix(
        titulo: 'Para concentrarte',
        subtitulo: 'Energia media, sin sobresaltos',
        pistas: donde((({Elemento e, double p}) m) => m.p >= 0.3 && m.p <= 0.6),
        clase: ClaseMix.concentrarte,
      ),
      Mix(
        titulo: 'Sesion DJ',
        subtitulo: 'Todo lo analizado, mezclado al compas',
        // Entera y sin barajar: el orden lo pone el DJ al reproducirla.
        pistas: <Elemento>[for (final ({Elemento e, double p}) m in medidas) m.e],
        clase: ClaseMix.sesionDj,
        modoDj: ModoDj.arco,
      ),
    ];
    return mixes.where((Mix m) => m.pistas.length >= minimoPorAnimo).toList();
  }
}
