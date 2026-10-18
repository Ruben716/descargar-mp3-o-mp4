import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'descubre.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'hecho_para_ti.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'pidele.dart';
import 'ritmos.dart';

/// De donde saca canciones una mezcla inteligente.
enum TipoMezcla {
  /// De los artistas que mas oyes, como Descubre.
  paraTi,

  /// De un genero: tus canciones de ese genero o, si aun no tienes, de sus
  /// artistas mas conocidos.
  genero,

  /// La radio de un artista: el y los que suenan parecido.
  artista,
}

/// Una mezcla que se baja sola y se renueva cada cierto tiempo.
@immutable
class MezclaInteligente {
  const MezclaInteligente({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.clave = '',
    this.cuantas = 20,
    this.dias = 7,
    this.activa = true,
    this.renovada = 0,
    this.vueltas = 0,
  });

  factory MezclaInteligente.desdeJson(Map<String, dynamic> j) => MezclaInteligente(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        tipo: TipoMezcla.values.firstWhere((TipoMezcla t) => t.name == j['tipo'], orElse: () => TipoMezcla.paraTi),
        clave: '${j['clave'] ?? ''}',
        cuantas: (j['cuantas'] as num?)?.toInt() ?? 20,
        dias: (j['dias'] as num?)?.toInt() ?? 7,
        activa: j['activa'] != false,
        renovada: (j['renovada'] as num?)?.toInt() ?? 0,
        vueltas: (j['vueltas'] as num?)?.toInt() ?? 0,
      );

  /// Estable aunque cambie el nombre: con el se apunta lo que bajo.
  final String id;

  /// El que ve el usuario, y el de la lista donde quedan sus canciones.
  final String nombre;
  final TipoMezcla tipo;

  /// El genero (su nombre en [generos]) o el artista, segun [tipo].
  final String clave;
  final int cuantas;

  /// Cada cuantos dias se renueva.
  final int dias;
  final bool activa;

  /// Cuando se renovo por ultima vez, en ms; 0 si nunca.
  final int renovada;

  /// Cuantas veces se ha renovado: con eso cambian las semillas de una vez a otra.
  final int vueltas;

  MezclaInteligente copiar({
    String? nombre,
    int? cuantas,
    int? dias,
    bool? activa,
    int? renovada,
    int? vueltas,
  }) =>
      MezclaInteligente(
        id: id,
        nombre: nombre ?? this.nombre,
        tipo: tipo,
        clave: clave,
        cuantas: cuantas ?? this.cuantas,
        dias: dias ?? this.dias,
        activa: activa ?? this.activa,
        renovada: renovada ?? this.renovada,
        vueltas: vueltas ?? this.vueltas,
      );

  Map<String, Object> aJson() => <String, Object>{
        'id': id,
        'nombre': nombre,
        'tipo': tipo.name,
        'clave': clave,
        'cuantas': cuantas,
        'dias': dias,
        'activa': activa,
        'renovada': renovada,
        'vueltas': vueltas,
      };

  /// Si ya toca cambiar sus canciones por otras.
  bool tocaRenovar(DateTime ahora) =>
      renovada == 0 || ahora.millisecondsSinceEpoch - renovada >= Duration(days: dias).inMilliseconds;

  /// De donde salen sus canciones, para decirlo en pantalla.
  String get origen => switch (tipo) {
        TipoMezcla.paraTi => 'De tus artistas mas escuchados',
        TipoMezcla.genero => 'Genero: ${clave.isEmpty ? '' : clave[0].toUpperCase() + clave.substring(1)}',
        TipoMezcla.artista => 'Artista: $clave',
      };
}

/// Una cancion que la app bajo sola: de que mezcla y de que tanda (la
/// [MezclaInteligente.renovada] de cuando se bajo).
@immutable
class BajadaInteligente {
  const BajadaInteligente({required this.url, required this.uri, required this.mezcla, required this.tanda});

  factory BajadaInteligente.desdeJson(Map<String, dynamic> j) => BajadaInteligente(
        url: '${j['url']}',
        uri: '${j['uri']}',
        mezcla: '${j['mezcla'] ?? DescargasInteligentes.idParaTi}',
        tanda: (j['tanda'] as num?)?.toInt() ?? 0,
      );

  final String url;
  final String uri;
  final String mezcla;
  final int tanda;

  Map<String, Object> aJson() => <String, Object>{'url': url, 'uri': uri, 'mezcla': mezcla, 'tanda': tanda};
}

/// Descargas inteligentes: mezclas que, con wifi, se bajan solas y se
/// renuevan cada cierto tiempo, como en YouTube Music.
///
/// Cada mezcla sale de la radio de YouTube Music de unas semillas (tus
/// artistas mas oidos, un genero o un artista) y deja sus canciones en su
/// propia lista. Al renovarse, lo que bajo sola y no has tocado (ni
/// escuchado, ni marcado Me gusta, ni metido en otra lista) se borra para
/// dejar sitio a lo nuevo; lo que si tocaste pasa a ser tuyo y no se borra
/// nunca. «Guardar como lista» hace tuyo todo lo que tiene en ese momento.
class DescargasInteligentes extends ChangeNotifier {
  DescargasInteligentes._();

  static final DescargasInteligentes instancia = DescargasInteligentes._();

  static const String claveMezclas = 'inteligentes_mezclas';
  static const String claveBajadas = 'inteligentes_bajadas';

  // Las de la primera version, que tenia una sola mezcla.
  static const String claveActivas = 'inteligentes_activas';
  static const String claveCuantas = 'inteligentes_cuantas';

  static const String idParaTi = 'para-ti';

  /// La lista de la mezcla «Para ti» de fabrica: la misma que tenia antes.
  static const String lista = 'Descargas inteligentes';

  static const List<int> opcionesCantidad = <int>[10, 20, 30, 50, 100];
  static const List<int> opcionesDias = <int>[1, 3, 7, 14, 30];

  /// Cuantas semillas se piden por mezcla. Mas semillas, mas variada y mas
  /// pegada al genero, porque lo primero de cada radio es lo mas parecido.
  static const int semillas = 4;

  static String textoDias(int dias) => switch (dias) {
        1 => 'Cada dia',
        7 => 'Cada semana',
        14 => 'Cada 2 semanas',
        30 => 'Cada mes',
        _ => 'Cada $dias dias',
      };

  bool _cargada = false;
  List<MezclaInteligente> _mezclas = <MezclaInteligente>[];
  List<BajadaInteligente> _bajadas = <BajadaInteligente>[];
  bool _trabajando = false;
  String _aviso = '';

  List<MezclaInteligente> get mezclas => List<MezclaInteligente>.unmodifiable(_mezclas);

  /// Las que bajo sola y aun no son tuyas.
  List<BajadaInteligente> get bajadas => List<BajadaInteligente>.unmodifiable(_bajadas);
  bool get trabajando => _trabajando;
  String get aviso => _aviso;
  bool get activas => _mezclas.any((MezclaInteligente m) => m.activa);

  List<BajadaInteligente> deMezcla(String id) =>
      <BajadaInteligente>[for (final BajadaInteligente b in _bajadas) if (b.mezcla == id) b];

  /// Que canciones de [pistas] bajar: por su orden, sin lo que ya esta en el
  /// telefono ([tengo], por video) ni lo que ya se bajo solo ([yaBajadas]).
  static List<Resultado> queBajar(
    List<Resultado> pistas, {
    required Set<String> tengo,
    required Set<String> yaBajadas,
    required int faltan,
  }) {
    if (faltan <= 0) return const <Resultado>[];
    return <Resultado>[
      for (final Resultado r in pistas)
        if (!yaBajadas.contains(r.url) && !tengo.contains(Catalogo.identificador(r.url))) r,
    ].take(faltan).toList();
  }

  /// Que hacer con lo bajado antes de [desde]: lo que no has tocado se borra;
  /// lo que si, se queda y deja de ser de la app.
  static ({List<BajadaInteligente> borrar, List<BajadaInteligente> tuyas}) repasar(
    List<BajadaInteligente> bajadas, {
    required int desde,
    required Set<String> escuchadas,
    required Set<String> favoritas,
    required Set<String> enOtrasListas,
  }) {
    final List<BajadaInteligente> borrar = <BajadaInteligente>[];
    final List<BajadaInteligente> tuyas = <BajadaInteligente>[];
    for (final BajadaInteligente b in bajadas) {
      final bool tocada =
          escuchadas.contains(b.uri) || favoritas.contains(b.uri) || enOtrasListas.contains(b.uri);
      if (tocada) {
        tuyas.add(b);
      } else if (b.tanda < desde) {
        borrar.add(b);
      }
    }
    return (borrar: borrar, tuyas: tuyas);
  }

  /// Las semillas de [m] en esta vuelta.
  ///
  /// Para ti: los artistas que mas oyes, como Descubre. Genero: tus canciones
  /// de ese genero, de las mas oidas, y si hay pocas, artistas conocidos del
  /// genero. Artista: sus canciones, o el artista a secas si no tienes.
  static List<Semilla> semillasDe(
    MezclaInteligente m,
    List<Elemento> canciones,
    Map<String, Escucha> escuchas,
    Map<String, String> videos, {
    Map<String, Rasgos> rasgos = const <String, Rasgos>{},
  }) {
    // hashCode no vale de semilla: cambia de una ejecucion a otra.
    final int deLaMezcla = m.id.codeUnits.fold(0, (int a, int c) => (a * 31 + c) & 0x3fffffff);
    final Random azar = Random(m.vueltas * 7919 + deLaMezcla);
    int veces(Elemento e) => escuchas[e.uri]?.veces ?? 0;
    List<Elemento> masOidas(Iterable<Elemento> pistas) => pistas.toList()
      ..sort((Elemento a, Elemento b) {
        final int porVeces = veces(b).compareTo(veces(a));
        return porVeces != 0 ? porVeces : a.uri.compareTo(b.uri);
      });
    Semilla deCancion(Elemento e) => (artista: e.artista, tema: e.tema, video: videos[e.uri]);
    // Entre las doce mas oidas se sortean las de esta vuelta: asi cada
    // renovacion trae otra cosa sin irse a lo que no te gusta.
    List<Semilla> sortear(List<Elemento> candidatas) {
      final List<Elemento> mejores = candidatas.take(12).toList()..shuffle(azar);
      return <Semilla>[for (final Elemento e in mejores.take(semillas)) deCancion(e)];
    }

    switch (m.tipo) {
      case TipoMezcla.paraTi:
        return Descubre.elegirSemillas(canciones, escuchas, videos, semana: m.vueltas, cuantas: semillas);
      case TipoMezcla.genero:
        final Genero? g = generosDistintos.where((Genero x) => x.nombre == m.clave).firstOrNull;
        if (g == null) return const <Semilla>[];
        final List<Semilla> propias = sortear(masOidas(
          canciones.where((Elemento e) => e.audio && cancionDelGenero(e, g, rasgos: rasgos[e.uri])),
        ));
        if (propias.length >= semillas) return propias;
        final List<String> conocidos = List<String>.of(artistasSemilla[g.nombre] ?? const <String>[])..shuffle(azar);
        return <Semilla>[
          ...propias,
          for (final String a in conocidos.take(semillas - propias.length)) (artista: a, tema: '', video: null),
        ];
      case TipoMezcla.artista:
        final String buscado = normalizarFrase(m.clave).trim();
        final List<Semilla> suyas = sortear(masOidas(canciones.where(
          (Elemento e) => e.audio && normalizarFrase(e.artista).trim() == buscado,
        )));
        return suyas.isNotEmpty ? suyas : <Semilla>[(artista: m.clave, tema: '', video: null)];
    }
  }

  /// Una mezcla nueva para un genero o un artista, con un nombre que no se
  /// repite.
  MezclaInteligente nueva(TipoMezcla tipo, {String clave = ''}) {
    final String base = switch (tipo) {
      TipoMezcla.paraTi => 'Para ti',
      TipoMezcla.genero => 'Mezcla de $clave',
      TipoMezcla.artista => 'Radio de $clave',
    };
    final String idBase = '${tipo.name}:${normalizarFrase(clave).trim()}';
    String id = idBase;
    String nombre = base;
    for (int n = 2; _mezclas.any((MezclaInteligente m) => m.id == id || m.nombre == nombre); n++) {
      id = '$idBase#$n';
      nombre = '$base $n';
    }
    return MezclaInteligente(id: id, nombre: nombre, tipo: tipo, clave: clave);
  }

  Future<void> cargar() async {
    if (_cargada) return;
    _cargada = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? mezclas = prefs.getString(claveMezclas);
      final String? bajadas = prefs.getString(claveBajadas);
      if (mezclas != null) {
        _mezclas = <MezclaInteligente>[
          for (final dynamic j in jsonDecode(mezclas) as List<dynamic>)
            MezclaInteligente.desdeJson(j as Map<String, dynamic>),
        ];
      } else if (prefs.getBool(claveActivas) != null) {
        // De la primera version: una sola mezcla, la de Descubre. Lo que ya
        // bajo cuenta como de esta tanda, para no borrarlo al pasar.
        final int ahora = DateTime.now().millisecondsSinceEpoch;
        _mezclas = <MezclaInteligente>[
          MezclaInteligente(
            id: idParaTi,
            nombre: lista,
            tipo: TipoMezcla.paraTi,
            cuantas: prefs.getInt(claveCuantas) ?? 20,
            activa: prefs.getBool(claveActivas) ?? false,
            renovada: ahora,
          ),
        ];
        if (bajadas != null) {
          _bajadas = <BajadaInteligente>[
            for (final dynamic j in jsonDecode(bajadas) as List<dynamic>)
              BajadaInteligente(
                url: '${(j as Map<String, dynamic>)['url']}',
                uri: '${j['uri']}',
                mezcla: idParaTi,
                tanda: ahora,
              ),
          ];
        }
        await _guardar();
        notifyListeners();
        return;
      }
      if (bajadas != null) {
        _bajadas = <BajadaInteligente>[
          for (final dynamic j in jsonDecode(bajadas) as List<dynamic>)
            BajadaInteligente.desdeJson(j as Map<String, dynamic>),
        ];
      }
    } catch (_) {
      // Sin lo guardado se empieza de cero: no se borra nada que no se conozca.
    }
    if (_mezclas.isEmpty) {
      _mezclas = <MezclaInteligente>[
        const MezclaInteligente(id: idParaTi, nombre: lista, tipo: TipoMezcla.paraTi, activa: false),
      ];
    }
    notifyListeners();
  }

  Future<void> _guardar() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(claveMezclas, jsonEncode(<Map<String, Object>>[for (final MezclaInteligente m in _mezclas) m.aJson()]));
    await prefs.setString(claveBajadas, jsonEncode(<Map<String, Object>>[for (final BajadaInteligente b in _bajadas) b.aJson()]));
  }

  MezclaInteligente? mezcla(String id) => _mezclas.where((MezclaInteligente m) => m.id == id).firstOrNull;

  /// Cambia una mezcla. Si cambia de nombre, su lista tambien.
  Future<void> cambiar(MezclaInteligente nueva) async {
    await cargar();
    final int i = _mezclas.indexWhere((MezclaInteligente m) => m.id == nueva.id);
    if (i < 0) return;
    final MezclaInteligente vieja = _mezclas[i];
    final String nombre = nueva.nombre.trim();
    if (nombre.isEmpty) return;
    _mezclas[i] = nueva.copiar(nombre: nombre);
    if (nombre != vieja.nombre) await _renombrarLista(vieja.nombre, nombre);
    _aviso = '';
    notifyListeners();
    await _guardar();
    final bool masOEncendida = nueva.activa &&
        (!vieja.activa || nueva.cuantas > vieja.cuantas || nueva.dias < vieja.dias);
    if (masOEncendida) unawaited(revisar());
  }

  Future<void> anadir(MezclaInteligente m) async {
    await cargar();
    _mezclas.add(m);
    notifyListeners();
    await _guardar();
    if (m.activa) unawaited(revisar());
  }

  /// Quita la mezcla. Lo que bajo y no has tocado se borra del telefono; lo
  /// tocado se queda como tuyo.
  Future<void> quitar(String id) async {
    await cargar();
    final MezclaInteligente? m = mezcla(id);
    if (m == null) return;
    await _soltar(m, desde: 1 << 62);
    _mezclas.removeWhere((MezclaInteligente x) => x.id == id);
    _bajadas.removeWhere((BajadaInteligente b) => b.mezcla == id);
    notifyListeners();
    await _guardar();
  }

  /// Hace tuyo todo lo que tiene ahora la mezcla, en una lista nueva que ya
  /// no cambia. Devuelve cuantas canciones quedaron en ella.
  Future<int> guardarComoLista(String id, String nombre) async {
    await cargar();
    final String limpio = nombre.trim();
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (limpio.isEmpty || listas.nombres.contains(limpio)) return -1;
    final List<String> uris = <String>[for (final BajadaInteligente b in deMezcla(id)) b.uri];
    await listas.crear(limpio);
    await listas.anadirVarias(limpio, uris);
    _bajadas.removeWhere((BajadaInteligente b) => b.mezcla == id);
    notifyListeners();
    await _guardar();
    return uris.length;
  }

  Future<void> _renombrarLista(String vieja, String nueva) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (!listas.nombres.contains(vieja) || listas.nombres.contains(nueva)) return;
    final List<String> uris = await listas.borrar(vieja);
    await listas.restaurar(nueva, uris);
  }

  /// Desde las tareas de fondo: solo si hay alguna encendida.
  Future<void> revisarSiToca() async {
    await cargar();
    if (activas) await revisar();
  }

  /// Renueva las mezclas a las que les toca y baja lo que falte de cada una.
  /// Con [forzar] se renuevan todas las encendidas aunque no les toque.
  /// Devuelve cuantas canciones se bajaron.
  Future<int> revisar({bool forzar = false}) async {
    await cargar();
    final ControlDescarga control = ControlDescarga.instancia;
    if (!activas || _trabajando || control.activa) return 0;
    if (!await Nucleo.redSinLimite()) {
      _aviso = 'Esperando wifi para bajarlas.';
      notifyListeners();
      return 0;
    }
    _trabajando = true;
    notifyListeners();
    int total = 0;
    try {
      final List<Elemento> canciones =
          (await Nucleo.biblioteca()).where((Elemento e) => e.audio).toList();
      final Map<String, Escucha> escuchas = await Catalogo.instancia.escuchasConFecha();
      await Ritmos.instancia.cargar();
      final Map<String, Rasgos> rasgos = Ritmos.instancia.todos;
      for (final MezclaInteligente original in List<MezclaInteligente>.of(_mezclas)) {
        if (!original.activa || control.activa) continue;
        total += await _revisarMezcla(original, canciones, escuchas, rasgos, forzar: forzar);
      }
      _aviso = total == 0
          ? 'Tus descargas inteligentes estan al dia.'
          : 'Se bajaron $total ${total == 1 ? 'cancion nueva' : 'canciones nuevas'}.';
      await _guardar();
    } catch (_) {
      _aviso = 'No se pudieron bajar ahora; se intentara al volver a abrir la app.';
    } finally {
      _trabajando = false;
      notifyListeners();
    }
    return total;
  }

  Future<int> _revisarMezcla(
    MezclaInteligente m,
    List<Elemento> canciones,
    Map<String, Escucha> escuchas,
    Map<String, Rasgos> rasgos, {
    required bool forzar,
  }) async {
    final ControlDescarga control = ControlDescarga.instancia;
    final DateTime ahora = DateTime.now();
    final bool renovar = forzar || m.tocaRenovar(ahora);
    final int deEstaTanda =
        _bajadas.where((BajadaInteligente b) => b.mezcla == m.id && b.tanda == m.renovada).length;
    if (!renovar && deEstaTanda >= m.cuantas) return 0;

    final Map<String, String> bajados = await Catalogo.instancia.videos();
    final MezclaInteligente conVuelta = renovar ? m.copiar(vueltas: m.vueltas + 1) : m;
    final List<Semilla> semillasDeAhora = semillasDe(
      conVuelta,
      canciones,
      escuchas,
      <String, String>{for (final MapEntry<String, String> v in bajados.entries) v.value: v.key},
      rasgos: rasgos,
    );
    if (semillasDeAhora.isEmpty) return 0;
    final List<List<Resultado>> radios = await Future.wait(<Future<List<Resultado>>>[
      for (final Semilla s in semillasDeAhora) Descubre.radioDeSemilla(s),
    ]);
    final List<Resultado> candidatas = Descubre.armar(
      radios,
      tengo: bajados.keys.toSet(),
      conocidas: <String>{for (final Elemento e in canciones) Descubre.claveDe(e.artista, e.tema)},
      cuantas: m.cuantas * 2,
    );
    // Sin red no se renueva: mejor lo de antes que quedarse sin nada.
    if (candidatas.isEmpty) return 0;

    MezclaInteligente actual = m;
    if (renovar) {
      final int tanda = ahora.millisecondsSinceEpoch;
      await _soltar(m, desde: tanda);
      actual = conVuelta.copiar(renovada: tanda);
      _cambiarEnLista(actual);
    }
    final List<Resultado> nuevas = queBajar(
      candidatas,
      tengo: (await Catalogo.instancia.videos()).keys.toSet(),
      yaBajadas: <String>{for (final BajadaInteligente b in _bajadas) b.url},
      faltan: actual.cuantas -
          _bajadas.where((BajadaInteligente b) => b.mezcla == actual.id && b.tanda == actual.renovada).length,
    );
    if (nuevas.isEmpty) return 0;
    final List<String> urls = <String>[for (final Resultado r in nuevas) r.url];
    await control.iniciarVarios(urls, con: control.ajustes.copiar(soloAudio: true));
    int bajadas = 0;
    for (final String url in urls) {
      final String? uri = await Catalogo.instancia.buscar(url, audio: true);
      if (uri == null) continue;
      _bajadas.add(BajadaInteligente(url: url, uri: uri, mezcla: actual.id, tanda: actual.renovada));
      await _alaLista(actual.nombre, uri);
      bajadas++;
    }
    notifyListeners();
    return bajadas;
  }

  void _cambiarEnLista(MezclaInteligente m) {
    final int i = _mezclas.indexWhere((MezclaInteligente x) => x.id == m.id);
    if (i >= 0) _mezclas[i] = m;
  }

  /// Borra lo de [m] anterior a [desde] que no tocaste y suelta lo que si.
  Future<void> _soltar(MezclaInteligente m, {required int desde}) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    final ({List<BajadaInteligente> borrar, List<BajadaInteligente> tuyas}) repaso = repasar(
      deMezcla(m.id),
      desde: desde,
      escuchadas: await Catalogo.instancia.escuchadas(),
      favoritas: (await Catalogo.instancia.favoritas()).toSet(),
      enOtrasListas: <String>{
        for (final MapEntry<String, List<String>> l in listas.todas.entries)
          if (l.key != m.nombre) ...l.value,
      },
    );
    final Set<String> fuera = <String>{for (final BajadaInteligente b in repaso.tuyas) b.uri};
    for (final BajadaInteligente b in repaso.borrar) {
      try {
        await EstadoReproductor.instancia.olvidarSiEs(b.uri);
        await Nucleo.eliminar(b.uri);
        await Catalogo.instancia.olvidar(b.uri);
        await listas.olvidar(b.uri);
        Favoritas.instancia.olvidar(b.uri);
        fuera.add(b.uri);
      } catch (_) {
        // Si no se pudo borrar se intenta la proxima vez.
      }
    }
    _bajadas.removeWhere((BajadaInteligente b) => b.mezcla == m.id && fuera.contains(b.uri));
  }

  Future<void> _alaLista(String nombre, String uri) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (!listas.nombres.contains(nombre)) await listas.crear(nombre);
    if (!listas.contiene(nombre, uri)) await listas.anadir(nombre, uri);
  }

  @visibleForTesting
  void reiniciar() {
    _cargada = false;
    _mezclas = <MezclaInteligente>[];
    _bajadas = <BajadaInteligente>[];
    _trabajando = false;
    _aviso = '';
  }
}

/// La entrada a las descargas inteligentes, con lo que hay ahora. Va en
/// Descubre y en Ajustes; abre [abrir].
class AjusteDescargasInteligentes extends StatelessWidget {
  const AjusteDescargasInteligentes({
    required this.abrir,
    this.margen = const EdgeInsets.symmetric(horizontal: 16),
    super.key,
  });

  final VoidCallback abrir;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    final DescargasInteligentes d = DescargasInteligentes.instancia;
    unawaited(d.cargar());
    return ListenableBuilder(
      listenable: d,
      builder: (BuildContext context, _) {
        final int encendidas = d.mezclas.where((MezclaInteligente m) => m.activa).length;
        return ListTile(
          contentPadding: margen,
          leading: const Icon(Icons.download_for_offline_rounded),
          title: const Text('Descargas inteligentes'),
          subtitle: Text(
            d.trabajando
                ? 'Bajando tus mezclas...'
                : encendidas == 0
                    ? 'Mezclas que se bajan solas con wifi y se renuevan cuando quieras'
                    : '$encendidas ${encendidas == 1 ? 'mezcla encendida' : 'mezclas encendidas'}'
                        ' · ${d.bajadas.length} canciones',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: abrir,
        );
      },
    );
  }
}

/// Lo que dura una mezcla, en palabras: «20 canciones · Cada semana».
String resumenDeMezcla(MezclaInteligente m) =>
    '${m.cuantas} canciones · ${DescargasInteligentes.textoDias(m.dias)}';

/// Cuanto falta para que se renueve, o null si nunca se ha bajado.
String? proximaRenovacion(MezclaInteligente m, DateTime ahora) {
  if (m.renovada == 0) return null;
  final Duration falta =
      Duration(milliseconds: m.renovada) + Duration(days: m.dias) - Duration(milliseconds: ahora.millisecondsSinceEpoch);
  if (falta <= Duration.zero) return 'Se renueva al abrir la app con wifi';
  if (falta.inHours < 24) return 'Se renueva en ${max(1, falta.inHours)} h';
  return 'Se renueva en ${falta.inDays} ${falta.inDays == 1 ? 'dia' : 'dias'}';
}
