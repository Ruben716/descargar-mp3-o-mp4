import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'listas.dart';
import 'nucleo.dart';

/// Una lista o canal que se sigue: lo nuevo que le agreguen se baja solo.
@immutable
class Suscripcion {
  const Suscripcion({
    required this.url,
    required this.titulo,
    required this.audio,
    required this.conocidas,
    this.revisada = 0,
  });

  factory Suscripcion.desdeJson(Map<String, dynamic> j) => Suscripcion(
        url: j['url']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? 'Lista',
        audio: j['audio'] != false,
        conocidas: <String>{for (final dynamic u in (j['conocidas'] as List<dynamic>?) ?? <dynamic>[]) '$u'},
        revisada: (j['revisada'] as num?)?.toInt() ?? 0,
      );

  final String url;

  /// El nombre de la lista; tambien el de la lista de Tumbao donde va cayendo.
  final String titulo;

  /// Si se baja como musica o como video.
  final bool audio;

  /// Los enlaces que ya se tienen (o que se decidio no bajar).
  final Set<String> conocidas;

  /// Cuando se miro por ultima vez, en milisegundos.
  final int revisada;

  Suscripcion copiar({Set<String>? conocidas, int? revisada}) => Suscripcion(
        url: url,
        titulo: titulo,
        audio: audio,
        conocidas: conocidas ?? this.conocidas,
        revisada: revisada ?? this.revisada,
      );

  Map<String, dynamic> aJson() => <String, dynamic>{
        'url': url,
        'titulo': titulo,
        'audio': audio,
        'conocidas': conocidas.toList(),
        'revisada': revisada,
      };
}

/// Las listas que se siguen, como las suscripciones de Stacher o TubeSync.
///
/// Se miran al abrir la app (como mucho cada [cadaCuanto]) y, si hay algo
/// nuevo, se baja en la cola de siempre y se anade a la lista de Tumbao con
/// el mismo nombre. Por defecto solo con wifi, para no gastar datos.
class Suscripciones extends ChangeNotifier {
  Suscripciones._();

  static final Suscripciones instancia = Suscripciones._();

  static const String clave = 'suscripciones_v1';
  static const String claveSoloWifi = 'suscripciones_solo_wifi';
  static const Duration cadaCuanto = Duration(hours: 6);

  final List<Suscripcion> _todas = <Suscripcion>[];
  List<Suscripcion> get todas => List<Suscripcion>.unmodifiable(_todas);

  bool _soloWifi = true;
  bool get soloWifi => _soloWifi;

  bool _revisando = false;
  bool get revisando => _revisando;

  /// Lo que paso la ultima vez, para ensenarlo.
  String _ultimoAviso = '';
  String get ultimoAviso => _ultimoAviso;

  bool _cargadas = false;

  Future<void> cargar() async {
    if (_cargadas) return;
    _cargadas = true;
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      _soloWifi = memoria.getBool(claveSoloWifi) ?? true;
      final String? crudo = memoria.getString(clave);
      _todas
        ..clear()
        ..addAll(<Suscripcion>[
          for (final dynamic j in (crudo == null ? <dynamic>[] : jsonDecode(crudo) as List<dynamic>))
            if (j is Map<String, dynamic>) Suscripcion.desdeJson(j),
        ]);
    } catch (_) {
      // Unos datos ilegibles no impiden usar la app: se empieza sin ninguna.
    }
    notifyListeners();
  }

  Future<void> _guardar() async {
    notifyListeners();
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setString(clave, jsonEncode(<Map<String, dynamic>>[for (final Suscripcion s in _todas) s.aJson()]));
    } catch (_) {
      // Sigue en memoria hasta cerrar la app.
    }
  }

  Future<void> ponerSoloWifi(bool solo) async {
    _soloWifi = solo;
    notifyListeners();
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.setBool(claveSoloWifi, solo);
  }

  /// Empieza a seguir una lista. Falla con [ErrorNucleo] si el enlace no es
  /// una lista o un canal.
  ///
  /// Con [bajarLoQueHay] se baja tambien lo que ya tiene; si no, solo lo que
  /// le agreguen de aqui en adelante.
  Future<Suscripcion> seguir(String url, {required bool audio, required bool bajarLoQueHay}) async {
    await cargar();
    final String limpio = url.trim();
    if (_todas.any((Suscripcion s) => s.url == limpio)) {
      throw const ErrorNucleo('Ya sigues esa lista.');
    }
    final ListaTraida lista = await Nucleo.importarLista(limpio);
    final Suscripcion nueva = Suscripcion(
      url: limpio,
      titulo: lista.titulo,
      audio: audio,
      conocidas: bajarLoQueHay ? <String>{} : <String>{for (final Resultado r in lista.pistas) r.url},
      revisada: bajarLoQueHay ? 0 : DateTime.now().millisecondsSinceEpoch,
    );
    _todas.add(nueva);
    await _guardar();
    if (bajarLoQueHay) unawaited(revisar(forzar: true));
    return nueva;
  }

  Future<void> dejar(String url) async {
    _todas.removeWhere((Suscripcion s) => s.url == url);
    await _guardar();
  }

  /// Si hace falta mirar ya: lo llama la app al abrirse y al volver.
  Future<void> revisarSiToca() async {
    await cargar();
    final int ahora = DateTime.now().millisecondsSinceEpoch;
    if (_todas.every((Suscripcion s) => ahora - s.revisada < cadaCuanto.inMilliseconds)) return;
    await revisar();
  }

  /// Mira todas las listas y baja lo nuevo. Devuelve cuantas canciones se
  /// pusieron a bajar.
  Future<int> revisar({bool forzar = false}) async {
    await cargar();
    if (_revisando || _todas.isEmpty) return 0;
    if (_soloWifi && !forzar && !await Nucleo.redSinLimite()) {
      _ultimoAviso = 'Esperando wifi para mirar tus listas.';
      notifyListeners();
      return 0;
    }
    final ControlDescarga control = ControlDescarga.instancia;
    // Con una descarga en marcha no se mete nada en medio: se mira otro rato.
    if (control.activa) return 0;
    _revisando = true;
    notifyListeners();
    int bajadas = 0;
    try {
      for (int i = 0; i < _todas.length; i++) {
        final Suscripcion s = _todas[i];
        final int ahora = DateTime.now().millisecondsSinceEpoch;
        if (!forzar && ahora - s.revisada < cadaCuanto.inMilliseconds) continue;
        final ListaTraida lista;
        try {
          lista = await Nucleo.importarLista(s.url);
        } catch (_) {
          continue;
        }
        final Set<String> conocidas = <String>{...s.conocidas};
        final List<String> nuevas = <String>[];
        for (final Resultado r in lista.pistas) {
          if (conocidas.contains(r.url)) continue;
          // Lo que ya esta en el telefono no se baja otra vez: solo entra en la lista.
          final String? ya = await Catalogo.instancia.buscar(r.url, audio: s.audio);
          if (ya != null) {
            conocidas.add(r.url);
            await _alaLista(s.titulo, ya);
          } else {
            nuevas.add(r.url);
          }
        }
        if (nuevas.isNotEmpty) {
          await control.iniciarVarios(nuevas, con: control.ajustes.copiar(soloAudio: s.audio));
          for (final String url in nuevas) {
            final String? uri = await Catalogo.instancia.buscar(url, audio: s.audio);
            if (uri != null) {
              await _alaLista(s.titulo, uri);
              conocidas.add(url);
              bajadas++;
            } else if (Catalogo.identificador(url) == null) {
              // De fuentes que el catalogo no sabe seguir no se puede saber si
              // salio bien: se da por vista para no bajarla en cada revision.
              conocidas.add(url);
            }
          }
        }
        _todas[i] = s.copiar(conocidas: conocidas, revisada: DateTime.now().millisecondsSinceEpoch);
        await _guardar();
      }
      _ultimoAviso = bajadas == 0
          ? 'Tus listas estan al dia.'
          : 'Se bajaron $bajadas ${bajadas == 1 ? 'cancion nueva' : 'canciones nuevas'} de tus listas.';
    } finally {
      _revisando = false;
      notifyListeners();
    }
    return bajadas;
  }

  Future<void> _alaLista(String nombre, String uri) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (!listas.nombres.contains(nombre)) await listas.crear(nombre);
    if (!listas.contiene(nombre, uri)) await listas.anadir(nombre, uri);
  }

  @visibleForTesting
  void reiniciar() {
    _todas.clear();
    _cargadas = false;
    _revisando = false;
    _soloWifi = true;
    _ultimoAviso = '';
  }
}
