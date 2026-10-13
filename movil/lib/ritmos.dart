import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'nucleo.dart';
import 'volumen_parejo.dart';

/// Lo que el analisis sabe de una cancion: su pulso y su energia.
///
/// Sale de una pasada de FFmpeg en el telefono (ritmo.py) y se guarda en la
/// tabla `ritmos` del catalogo. Con eso el DJ ordena la cola, el fundido corta
/// en el pulso y «Pidele a Tumbao» entiende «algo tranquilo».
@immutable
class Rasgos {
  const Rasgos({
    this.bpm,
    this.confianza = 0,
    this.energia = 0.5,
    this.golpes = 0,
    this.brillo = 0,
    this.graves = 0,
    this.lra,
    this.lufs,
    this.inicioMs = 0,
    this.finMs = 0,
    this.pulsoInicioMs,
    this.pulsoFinMs,
    this.camelot,
    this.genero = '',
    this.anio,
    this.version = Rasgos.versionActual,
  });

  /// La del algoritmo de ritmo.py. Lo analizado con otra se repite.
  static const int versionActual = 1;

  /// Por debajo, el tempo es una adivinanza: mejor no usarlo.
  static const double confianzaMinima = 0.1;

  /// null si no hay pulso que valga (orquesta, ruido, una voz sola).
  final double? bpm;
  final double confianza;

  /// De 0 a 1, en bruto. Para comparar se usa el percentil dentro de la
  /// biblioteca ([Ritmos.percentil]), que se calibra solo.
  final double energia;
  final double golpes;
  final double brillo;
  final double graves;
  final double? lra;
  final double? lufs;
  final int inicioMs;
  final int finMs;
  final int? pulsoInicioMs;
  final int? pulsoFinMs;
  final String? camelot;
  final String genero;
  final int? anio;
  final int version;

  bool get conPulso => bpm != null && confianza >= confianzaMinima;

  double? get periodoMs => conPulso ? 60000 / bpm! : null;

  /// El tempo para enseniar, con «~» porque puede ser el doble o la mitad.
  String? get textoBpm => conPulso ? '~${bpm!.round()} BPM' : null;

  static double? _real(Object? v) => v is num ? v.toDouble() : null;
  static int? _entero(Object? v) => v is num ? v.round() : null;

  /// Lo que devuelve analizar_audio del puente.
  factory Rasgos.desdeJson(Map<String, dynamic> j) => Rasgos(
        bpm: _real(j['bpm']),
        confianza: _real(j['confianza']) ?? 0,
        energia: _real(j['energia']) ?? 0.5,
        golpes: _real(j['golpes']) ?? 0,
        brillo: _real(j['brillo']) ?? 0,
        graves: _real(j['graves']) ?? 0,
        lra: _real(j['lra']),
        lufs: _real(j['lufs']),
        inicioMs: _entero(j['inicioMs']) ?? 0,
        finMs: _entero(j['finMs']) ?? 0,
        pulsoInicioMs: _entero(j['pulsoInicioMs']),
        pulsoFinMs: _entero(j['pulsoFinMs']),
        camelot: j['camelot'] as String?,
        genero: '${j['genero'] ?? ''}'.trim(),
        anio: _entero(j['anio']),
        version: _entero(j['version']) ?? versionActual,
      );

  /// Una fila de la tabla `ritmos` (sin uri ni fecha, que pone el catalogo).
  Map<String, Object?> aFila() => <String, Object?>{
        'version': version,
        'bpm': bpm,
        'confianza': confianza,
        'energia': energia,
        'golpes': golpes,
        'brillo': brillo,
        'graves': graves,
        'lra': lra,
        'inicio_ms': inicioMs,
        'fin_ms': finMs,
        'pulso_inicio_ms': pulsoInicioMs,
        'pulso_fin_ms': pulsoFinMs,
        'camelot': camelot,
        'genero': genero,
        'anio': anio,
      };

  factory Rasgos.deFila(Map<String, Object?> f) => Rasgos(
        bpm: _real(f['bpm']),
        confianza: _real(f['confianza']) ?? 0,
        energia: _real(f['energia']) ?? 0.5,
        golpes: _real(f['golpes']) ?? 0,
        brillo: _real(f['brillo']) ?? 0,
        graves: _real(f['graves']) ?? 0,
        lra: _real(f['lra']),
        inicioMs: _entero(f['inicio_ms']) ?? 0,
        finMs: _entero(f['fin_ms']) ?? 0,
        pulsoInicioMs: _entero(f['pulso_inicio_ms']),
        pulsoFinMs: _entero(f['pulso_fin_ms']),
        camelot: f['camelot'] as String?,
        genero: '${f['genero'] ?? ''}',
        anio: _entero(f['anio']),
        version: _entero(f['version']) ?? 0,
      );
}

/// El analisis de la biblioteca, en segundo plano y de una en una.
///
/// Calcado de [VolumenParejo]: se carga lo guardado, y lo que falta va a una
/// cola. Tiene prioridad lo que va a sonar en una mezcla DJ, luego lo recien
/// bajado y luego el resto. Espera mientras se descarga, porque el analisis y
/// yt-dlp comparten el mismo Python.
class Ritmos extends ChangeNotifier {
  Ritmos._();

  static final Ritmos instancia = Ritmos._();

  bool _listo = false;
  bool get listo => _listo;

  final Map<String, Rasgos> _rasgos = <String, Rasgos>{};

  /// Cuantas hay analizadas.
  int get analizadas => _rasgos.length;

  Rasgos? rasgosDe(String uri) => _rasgos[uri];

  /// Todo lo analizado, para quien tiene que mirar muchas a la vez.
  Map<String, Rasgos> get todos => Map<String, Rasgos>.unmodifiable(_rasgos);

  List<double>? _energiasOrdenadas;

  /// Donde cae la energia de [uri] dentro de la biblioteca: 0 es la mas
  /// tranquila y 1 la mas movida. null si no se ha analizado.
  double? percentil(String uri) {
    final Rasgos? r = _rasgos[uri];
    if (r == null) return null;
    final List<double> orden = _energiasOrdenadas ??= (<double>[
      for (final Rasgos x in _rasgos.values) x.energia,
    ]..sort());
    if (orden.length < 2) return 0.5;
    // Primera posicion con esa energia: los empates quedan en el mismo sitio.
    int bajo = 0;
    int alto = orden.length;
    while (bajo < alto) {
      final int medio = (bajo + alto) >> 1;
      if (orden[medio] < r.energia) {
        bajo = medio + 1;
      } else {
        alto = medio;
      }
    }
    return bajo / (orden.length - 1);
  }

  Future<void> cargar() async {
    try {
      for (final Map<String, Object?> fila in await Catalogo.instancia.ritmos()) {
        final Rasgos r = Rasgos.deFila(fila);
        // Lo de otra version del algoritmo no se carga: se vuelve a analizar.
        if (r.version == Rasgos.versionActual) _rasgos['${fila['uri']}'] = r;
      }
    } catch (_) {
      // Sin datos se empieza de cero.
    }
    _energiasOrdenadas = null;
    _listo = true;
    notifyListeners();
  }

  // --- La cola ------------------------------------------------------------

  /// Primero lo que va a sonar en una mezcla, despues lo demas.
  final List<String> _urgentes = <String>[];
  final List<String> _cola = <String>[];
  final Set<String> _intentadas = <String>{};
  bool _trabajando = false;
  String? _ahora;

  /// Cuantas faltan, contando la que se esta analizando.
  int get pendientes => _urgentes.length + _cola.length + (_ahora == null ? 0 : 1);

  bool get trabajando => _trabajando;

  bool _encolada(String uri) => uri == _ahora || _urgentes.contains(uri) || _cola.contains(uri);

  /// Pide analizar una cancion si aun no se sabe su ritmo.
  void pedirSiFalta(String uri) {
    if (!_listo || uri.isEmpty) return;
    if (_rasgos.containsKey(uri) || _intentadas.contains(uri) || _encolada(uri)) return;
    _cola.add(uri);
    unawaited(_trabajar());
  }

  /// Pone en cola todas las que falten. Con [urgente] se adelantan a lo que
  /// ya hubiera (las de una mezcla DJ que esta a punto de sonar).
  int analizarTodas(Iterable<String> uris, {bool urgente = false}) {
    if (!_listo) return 0;
    int puestas = 0;
    for (final String uri in uris) {
      if (uri.isEmpty || _rasgos.containsKey(uri) || uri == _ahora) continue;
      if (urgente) {
        if (_urgentes.contains(uri)) continue;
        _cola.remove(uri);
        _urgentes.add(uri);
      } else {
        if (_encolada(uri)) continue;
        _cola.add(uri);
      }
      _intentadas.remove(uri);
      puestas++;
    }
    notifyListeners();
    unawaited(_trabajar());
    return puestas;
  }

  /// Cuantas de [uris] faltan por analizar.
  int faltanDe(Iterable<String> uris) => uris.where((String u) => !_rasgos.containsKey(u)).length;

  Future<void> _esperarDescargas() async {
    final ControlDescarga control = ControlDescarga.instancia;
    if (!control.activa) return;
    final Completer<void> listo = Completer<void>();
    void mirar() {
      if (!control.activa && !listo.isCompleted) listo.complete();
    }

    control.addListener(mirar);
    try {
      await listo.future;
    } finally {
      control.removeListener(mirar);
    }
  }

  Future<void> _trabajar() async {
    if (_trabajando) return;
    _trabajando = true;
    try {
      while (_urgentes.isNotEmpty || _cola.isNotEmpty) {
        await _esperarDescargas();
        if (_urgentes.isEmpty && _cola.isEmpty) break;
        final String uri = _urgentes.isNotEmpty ? _urgentes.removeAt(0) : _cola.removeAt(0);
        _ahora = uri;
        _intentadas.add(uri);
        notifyListeners();
        Rasgos? r;
        try {
          r = await analizar(uri);
        } catch (_) {
          r = null;
        }
        _ahora = null;
        if (r != null) {
          _rasgos[uri] = r;
          _energiasOrdenadas = null;
          // Una pasada da tambien cuanto suena: el volumen parejo lo aprovecha.
          final double? lufs = r.lufs;
          if (lufs != null) VolumenParejo.instancia.anotarMedida(uri, lufs);
          try {
            await Catalogo.instancia.anotarRitmo(uri, r.aFila());
          } catch (_) {
            // Se queda en memoria; se repetira otro dia.
          }
        }
        notifyListeners();
      }
    } finally {
      _trabajando = false;
      _ahora = null;
      notifyListeners();
    }
  }

  /// Como se analiza una cancion. Las pruebas lo cambian.
  @visibleForTesting
  static Future<Rasgos?> Function(String uri) analizar = _deVerdad;

  static Future<Rasgos?> _deVerdad(String uri) async {
    final Map<String, dynamic>? datos = await Nucleo.analizarAudio(uri);
    return datos == null ? null : Rasgos.desdeJson(datos);
  }

  @visibleForTesting
  void reiniciar() {
    _rasgos.clear();
    _urgentes.clear();
    _cola.clear();
    _intentadas.clear();
    _energiasOrdenadas = null;
    _listo = false;
    _ahora = null;
    analizar = _deVerdad;
  }

  /// Solo para las pruebas: rasgos puestos a mano, sin analizar nada.
  @visibleForTesting
  void ponerParaPruebas(Map<String, Rasgos> rasgos) {
    _rasgos
      ..clear()
      ..addAll(rasgos);
    _energiasOrdenadas = null;
    _listo = true;
    notifyListeners();
  }
}
