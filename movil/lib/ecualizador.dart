import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'autoeq.dart';
import 'navegacion.dart';
import 'nucleo.dart';
import 'salida_audio.dart';

/// Ganancia en una frecuencia cualquiera a partir de unos puntos conocidos.
///
/// Se interpola en escala logaritmica, que es como oye el oido: de 100 a 200 Hz
/// hay el mismo salto que de 1000 a 2000. Fuera de los puntos vale el extremo.
double interpolarEnFrecuencia(List<double> frecuencias, List<double> ganancias, double hz) {
  if (frecuencias.isEmpty) return 0;
  if (hz <= frecuencias.first) return ganancias.first;
  if (hz >= frecuencias.last) return ganancias.last;
  for (int i = 1; i < frecuencias.length; i++) {
    if (hz <= frecuencias[i]) {
      final double a = log(frecuencias[i - 1]);
      final double b = log(frecuencias[i]);
      final double t = (log(hz) - a) / (b - a);
      return ganancias[i - 1] + (ganancias[i] - ganancias[i - 1]) * t;
    }
  }
  return ganancias.last;
}

/// Un ajuste con nombre del ecualizador.
///
/// Se da en decibelios sobre diez frecuencias de referencia, las de cualquier
/// ecualizador grafico. Cada telefono tiene sus propias bandas (cinco, diez...)
/// y en otras frecuencias: a cada una le toca lo que dice la curva en su
/// frecuencia central, asi que el ajuste suena igual en todos.
class Ajuste {
  const Ajuste(this.nombre, this.ganancias);

  final String nombre;

  /// dB en [frecuencias], de la mas grave a la mas aguda.
  final List<double> ganancias;

  static const List<double> frecuencias = <double>[31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  double gananciaEn(double hz) => interpolarEnFrecuencia(frecuencias, ganancias, hz);

  static const Ajuste plano = Ajuste('Plano', <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  static const Ajuste graves = Ajuste('Graves', <double>[6, 5, 4, 2, 0, 0, 0, 0, 0, 0]);
  static const Ajuste gravesExtremos = Ajuste('Graves a tope', <double>[9, 8, 6, 3, 0, -1, -1, 0, 0, 0]);
  static const Ajuste voz = Ajuste('Voz', <double>[-2, -2, -1, 1, 3, 4, 4, 3, 1, 0]);
  static const Ajuste agudos = Ajuste('Agudos', <double>[0, 0, 0, 0, 0, 1, 2, 4, 5, 6]);
  static const Ajuste fiesta = Ajuste('Fiesta', <double>[5, 4, 2, 0, -2, -2, 0, 2, 4, 5]);
  static const Ajuste reggaeton = Ajuste('Reggaeton', <double>[7, 6, 4, 1, -1, 0, 1, 2, 2, 2]);
  static const Ajuste electronica = Ajuste('Electronica', <double>[6, 5, 2, 0, -1, 1, 0, 2, 4, 5]);
  static const Ajuste rock = Ajuste('Rock', <double>[5, 4, 2, -1, -2, -1, 1, 3, 4, 4]);
  static const Ajuste pop = Ajuste('Pop', <double>[-1, 0, 2, 3, 4, 3, 1, 0, -1, -1]);
  static const Ajuste hipHop = Ajuste('Hip-hop', <double>[6, 5, 3, 1, -1, -1, 1, 1, 2, 2]);
  static const Ajuste acustico = Ajuste('Acustico', <double>[2, 2, 1, 1, 2, 2, 3, 3, 2, 1]);
  static const Ajuste clasica = Ajuste('Clasica', <double>[3, 2, 1, 0, -1, -1, 0, 2, 3, 4]);
  static const Ajuste jazz = Ajuste('Jazz', <double>[3, 2, 1, 2, -1, -1, 0, 1, 2, 3]);
  static const Ajuste noche = Ajuste('Noche (suave)', <double>[-2, -1, 0, 1, 1, 0, -2, -3, -4, -5]);

  /// Para el altavoz del propio telefono, que es pequeno y no da graves.
  ///
  /// No hay mediciones publicas de altavoces de telefono como las de AutoEQ
  /// para audifonos, asi que es una curva general, no la de cada modelo: quita
  /// lo que esta por debajo de unos 100 Hz (el altavoz no lo da y subirlo solo
  /// gasta potencia y distorsiona), sube los medios bajos donde si suena el
  /// cuerpo de la musica, suaviza el chillido de 2-4 kHz y aclara un poco arriba.
  static const Ajuste altavoz =
      Ajuste('Altavoz del telefono', <double>[-8, -6, -2, 2, 3, 0, -1, -2, 1, 2]);

  static const List<Ajuste> todos = <Ajuste>[
    plano,
    graves,
    gravesExtremos,
    voz,
    agudos,
    fiesta,
    reggaeton,
    electronica,
    rock,
    pop,
    hipHop,
    acustico,
    clasica,
    jazz,
    noche,
    altavoz,
  ];

  static Ajuste? porNombre(String? nombre) {
    for (final Ajuste a in todos) {
      if (a.nombre == nombre) return a;
    }
    return null;
  }
}

/// La correccion de unos audifonos concretos (AutoEQ).
///
/// AutoEQ mide como suena cada modelo y calcula cuanto subir o bajar cada
/// frecuencia para que suene neutro. Llega como una curva fina (unos 120
/// puntos); el ecualizador del telefono tiene pocas bandas, asi que a cada una
/// le toca la media de la curva dentro de su tramo: la correccion es
/// aproximada, pero va en la direccion buena.
class Correccion {
  const Correccion({required this.nombre, required this.frecuencias, required this.ganancias});

  /// Lee el formato «GraphicEQ: 20 -0.2; 21 -0.2; ...» de AutoEQ.
  factory Correccion.desdeGraphicEq(String nombre, String texto) {
    final int inicio = texto.indexOf(':');
    final String datos = inicio >= 0 ? texto.substring(inicio + 1) : texto;
    final List<double> f = <double>[];
    final List<double> g = <double>[];
    for (final String par in datos.split(';')) {
      final List<String> trozos = par.trim().split(RegExp(r'\s+'));
      if (trozos.length < 2) continue;
      final double? hz = double.tryParse(trozos[0]);
      final double? db = double.tryParse(trozos[1]);
      if (hz == null || db == null || hz <= 0) continue;
      f.add(hz);
      g.add(db);
    }
    if (f.length < 4) throw const FormatException('No es una curva de AutoEQ');
    return Correccion(nombre: nombre, frecuencias: f, ganancias: g);
  }

  factory Correccion.desdeJson(Map<String, dynamic> j) => Correccion(
        nombre: j['nombre']?.toString() ?? '',
        frecuencias: <double>[for (final dynamic v in j['f'] as List<dynamic>) (v as num).toDouble()],
        ganancias: <double>[for (final dynamic v in j['g'] as List<dynamic>) (v as num).toDouble()],
      );

  final String nombre;
  final List<double> frecuencias;
  final List<double> ganancias;

  Map<String, dynamic> aJson() => <String, dynamic>{'nombre': nombre, 'f': frecuencias, 'g': ganancias};

  /// La media de la curva entre dos frecuencias (el tramo de una banda).
  double mediaEntre(double desde, double hasta) {
    final double a = max(1, min(desde, hasta));
    final double b = max(a * 1.01, max(desde, hasta));
    // Doce muestras repartidas en escala logaritmica dentro del tramo.
    const int muestras = 12;
    double suma = 0;
    for (int i = 0; i < muestras; i++) {
      final double hz = exp(log(a) + (log(b) - log(a)) * (i + 0.5) / muestras);
      suma += interpolarEnFrecuencia(frecuencias, ganancias, hz);
    }
    return suma / muestras;
  }

  /// La ganancia de cada banda, centrada: AutoEQ ya trae restado un margen
  /// para no saturar, y aplicado tal cual solo bajaria el volumen de todo.
  List<double> paraBandas(List<({double desde, double hasta})> tramos) {
    final List<double> crudas = <double>[for (final t in tramos) mediaEntre(t.desde, t.hasta)];
    if (crudas.isEmpty) return crudas;
    final double media = crudas.reduce((double a, double b) => a + b) / crudas.length;
    return <double>[for (final double c in crudas) c - media];
  }
}

/// El ecualizador de Android y el refuerzo de volumen.
///
/// Los dos los trae just_audio, asi que no hace falta nada en Kotlin: se
/// enchufan a la tuberia del reproductor al construirlo.
class Ecualizador {
  Ecualizador._();

  static final Ecualizador instancia = Ecualizador._();

  static const String _clave = 'ecualizador';

  /// El ajuste de cada salida (altavoz, cable, cada audifono Bluetooth).
  static const String _claveSalidas = 'ecualizador_salidas';

  final AndroidEqualizer motor = AndroidEqualizer();
  final AndroidLoudnessEnhancer realce = AndroidLoudnessEnhancer();

  /// La tuberia que se le pasa al AudioPlayer. Se monta una sola vez.
  late final AudioPipeline tuberia = AudioPipeline(
    androidAudioEffects: <AndroidAudioEffect>[motor, realce],
  );

  bool get activo => motor.enabled;

  double _refuerzo = 0;
  double _extra = 0;

  /// Cuanto refuerza el usuario el volumen, en decibelios.
  double get refuerzo => _refuerzo;

  Ajuste? _ajuste;
  Correccion? _correccion;

  /// El ajuste elegido, o null si se movieron las bandas a mano.
  Ajuste? get ajuste => _ajuste;

  /// La correccion de audifonos puesta, si hay.
  Correccion? get correccion => _correccion;

  /// Los parametros, una vez el aparato los ha dicho.
  ///
  /// Se guardan aparte porque `motor.parameters` no se resuelve hasta que el
  /// reproductor tiene una pista cargada: esperarlo antes seria colgarse, y
  /// hay sitios (como guardar los ajustes) donde solo interesa si ya estan.
  AndroidEqualizerParameters? _cache;

  /// Cuantas bandas tiene el aparato, o `null` si aun no lo ha dicho.
  AndroidEqualizerParameters? get parametrosSiListos => _cache;

  /// Espera a que el aparato diga sus bandas. La pantalla lo hace con un
  /// FutureBuilder; el resto del codigo no deberia llamarlo a ciegas.
  Future<AndroidEqualizerParameters> get parametros async => _cache ??= await motor.parameters;

  Future<void> activar(bool encendido) async {
    await motor.setEnabled(encendido);
    await _guardar();
  }

  Future<void> reforzar(double decibelios) async {
    _refuerzo = decibelios;
    await _ponerRealce();
    await _guardar();
  }

  /// Lo que suma el volumen parejo a las canciones flojas. No se guarda: va
  /// cambiando con cada cancion.
  Future<void> fijarExtra(double decibelios) async {
    if ((decibelios - _extra).abs() < 0.05) return;
    _extra = decibelios;
    await _ponerRealce();
  }

  Future<void> _ponerRealce() async {
    final double total = _refuerzo + _extra;
    await realce.setTargetGain(total);
    // Se apaga solo cuando no suma nada, para no gastar efecto.
    await realce.setEnabled(total > 0);
  }

  /// Aplica un ajuste con nombre, sobre la correccion de audifonos si la hay.
  Future<void> aplicar(Ajuste ajuste) async {
    _ajuste = ajuste;
    await _ponerBandas();
  }

  /// Pone o quita la correccion de unos audifonos. El ajuste elegido se
  /// conserva y se suma encima.
  Future<void> corregir(Correccion? correccion) async {
    _correccion = correccion;
    await _ponerBandas();
  }

  /// Lo que deberia llevar cada banda con el ajuste y la correccion puestos.
  static List<double> ganancias(
    AndroidEqualizerParameters p, {
    Ajuste? ajuste,
    Correccion? correccion,
  }) {
    final List<AndroidEqualizerBand> bandas = p.bands;
    final List<double> correcciones = correccion == null
        ? List<double>.filled(bandas.length, 0)
        : correccion.paraBandas(<({double desde, double hasta})>[
            for (final AndroidEqualizerBand b in bandas) (desde: b.lowerFrequency, hasta: b.upperFrequency),
          ]);
    return <double>[
      for (int i = 0; i < bandas.length; i++)
        (correcciones[i] + (ajuste?.gananciaEn(bandas[i].centerFrequency) ?? 0))
            .clamp(p.minDecibels, p.maxDecibels),
    ];
  }

  Future<void> _ponerBandas() async {
    final AndroidEqualizerParameters p = await parametros;
    final List<double> g = ganancias(p, ajuste: _ajuste, correccion: _correccion);
    for (int i = 0; i < p.bands.length; i++) {
      await p.bands[i].setGain(g[i]);
    }
    if (!motor.enabled) await motor.setEnabled(true);
    await _guardar();
  }

  Future<void> ajustarBanda(AndroidEqualizerBand banda, double ganancia) async {
    await banda.setGain(ganancia);
    // Movida a mano ya no es ningun ajuste con nombre.
    _ajuste = null;
    if (!motor.enabled) await motor.setEnabled(true);
    await _guardar();
  }

  /// Lo puesto ahora, tal como se guarda.
  Map<String, dynamic> _estado() {
    final AndroidEqualizerParameters? p = _cache;
    return <String, dynamic>{
      'activo': motor.enabled,
      'refuerzo': _refuerzo,
      'ajuste': _ajuste?.nombre,
      'correccion': _correccion?.aJson(),
      'salida': _salida,
      // Sin bandas todavia no se inventa nada: se guarda lo que si se sabe.
      if (p != null) 'bandas': p.bands.map((AndroidEqualizerBand b) => b.gain).toList(),
    };
  }

  /// Vuelca lo puesto a disco para recuperarlo al abrir la app, y lo apunta
  /// como el ajuste de la salida por la que suena.
  Future<void> _guardar() async {
    final Map<String, dynamic> estado = _estado();
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.setString(_clave, jsonEncode(estado));
    final String? salida = _salida;
    if (salida != null) {
      _perfiles[salida] = estado;
      await memoria.setString(_claveSalidas, jsonEncode(_perfiles));
    }
  }

  // --- Un ajuste por salida ---------------------------------------------------

  final Map<String, Map<String, dynamic>> _perfiles = <String, Map<String, dynamic>>{};
  bool _perfilesCargados = false;
  String? _salida;
  SalidaAudio? _aparato;

  /// Por donde suena ahora, si ya se sabe.
  SalidaAudio? get aparato => _aparato;

  /// Las salidas que ya tienen su ajuste guardado.
  Set<String> get salidasConAjuste => _perfiles.keys.toSet();

  Future<void> _cargarPerfiles() async {
    if (_perfilesCargados) return;
    _perfilesCargados = true;
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final Object? datos = jsonDecode(memoria.getString(_claveSalidas) ?? '{}');
      if (datos is Map<String, dynamic>) {
        for (final MapEntry<String, dynamic> e in datos.entries) {
          if (e.value is Map<String, dynamic>) _perfiles[e.key] = e.value as Map<String, dynamic>;
        }
      }
    } catch (_) {
      // Sin ajustes por salida se empieza de cero: no impide escuchar.
    }
  }

  /// Lo que se pone la primera vez que se suena por [salida]: en el altavoz,
  /// el ajuste para altavoces pequenos; en unos audifonos, plano (y despues su
  /// correccion de AutoEQ si se encuentra).
  static Map<String, dynamic> deFabrica(SalidaAudio salida) => <String, dynamic>{
        'activo': true,
        'refuerzo': 0,
        'ajuste': salida.esAudifono ? Ajuste.plano.nombre : Ajuste.altavoz.nombre,
        'correccion': null,
        'salida': salida.clave,
      };

  /// Cambia al ajuste de la salida nueva. La primera vez que se sabe por donde
  /// suena, lo que ya estaba puesto se queda para esa salida: nadie pierde el
  /// ajuste que tenia.
  Future<void> cambiarSalida(SalidaAudio nueva) async {
    await _cargarPerfiles();
    if (nueva.clave == _salida) return;
    final bool primera = _salida == null;
    _salida = nueva.clave;
    _aparato = nueva;
    final Map<String, dynamic>? guardado = _perfiles[nueva.clave];
    if (guardado != null) {
      await _aplicarEstado(guardado, nueva.clave);
      return;
    }
    if (primera) {
      if (_cache != null) await _guardar();
      return;
    }
    await _aplicarEstado(deFabrica(nueva), nueva.clave);
    if (nueva.esAudifono && nueva.nombre.isNotEmpty) unawaited(_corregirConAutoEq(nueva));
  }

  /// Unos audifonos que se conectan por primera vez: si AutoEQ los conoce sin
  /// dudas, se corrigen solos. Solo con wifi, que el indice pesa casi un mega.
  Future<void> _corregirConAutoEq(SalidaAudio aparato) async {
    try {
      if (!await Nucleo.redSinLimite()) return;
      final ModeloAudifonos? modelo = modeloParaAparato(await AutoEq.indice(), aparato.nombre);
      if (modelo == null || _salida != aparato.clave || _correccion != null) return;
      final Correccion correccion = await AutoEq.correccion(modelo);
      if (_salida != aparato.clave) return;
      await corregir(correccion);
      Navegacion.avisar('Sonido corregido para ${modelo.nombre} (AutoEQ)');
    } catch (_) {
      // Sin red o sin ese modelo se queda plano; se puede elegir a mano.
    }
  }

  /// Pone un estado guardado. Espera a que el aparato diga sus bandas, y si
  /// mientras tanto cambio otra vez la salida, ya no lo pone.
  Future<void> _aplicarEstado(Map<String, dynamic> datos, String? salida) async {
    _ajuste = Ajuste.porNombre(datos['ajuste']?.toString());
    final dynamic c = datos['correccion'];
    _correccion = c is Map<String, dynamic> ? Correccion.desdeJson(c) : null;
    _refuerzo = ((datos['refuerzo'] as num?) ?? 0).toDouble();
    final AndroidEqualizerParameters p = await parametros;
    if (salida != null && _salida != salida) return;
    final List<dynamic>? bandas = datos['bandas'] as List<dynamic>?;
    if (bandas == null) {
      // Sin bandas guardadas (un ajuste de fabrica) salen del ajuste y la correccion.
      final List<double> g = ganancias(p, ajuste: _ajuste, correccion: _correccion);
      for (int i = 0; i < p.bands.length; i++) {
        await p.bands[i].setGain(g[i]);
      }
    } else {
      // Si el aparato cambio de numero de bandas, se aplica lo que encaje y el
      // resto se queda como esta: mejor eso que descartar todo el ajuste.
      for (int i = 0; i < p.bands.length && i < bandas.length; i++) {
        final double valor = (bandas[i] as num).toDouble();
        await p.bands[i].setGain(valor.clamp(p.minDecibels, p.maxDecibels));
      }
    }
    await _ponerRealce();
    await motor.setEnabled(datos['activo'] == true);
    await _guardar();
  }

  /// Recupera lo guardado. Se llama cuando el reproductor ya tiene una pista,
  /// que es cuando el aparato responde con sus bandas.
  ///
  /// Si ya se sabe por donde suena, va el ajuste de esa salida; lo ultimo que
  /// se uso solo si era de esa misma salida (o de antes de haber una por salida).
  Future<void> recuperar() async {
    await _cargarPerfiles();
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    final String? crudo = memoria.getString(_clave);
    try {
      final String? salida = _salida;
      Map<String, dynamic>? datos = salida == null ? null : _perfiles[salida];
      if (datos == null && crudo != null) {
        final Map<String, dynamic> ultimo = jsonDecode(crudo) as Map<String, dynamic>;
        final Object? deQuien = ultimo['salida'];
        final SalidaAudio? aparato = _aparato;
        datos = deQuien == null || deQuien == salida || aparato == null ? ultimo : deFabrica(aparato);
      }
      if (datos == null) return;
      // Lo de antes no traia bandas cuando no se habian llegado a mover.
      if (crudo != null && datos['bandas'] == null && datos['ajuste'] == null && datos['correccion'] == null) {
        datos = <String, dynamic>{...datos, 'bandas': <dynamic>[]};
      }
      await _aplicarEstado(datos, salida);
    } catch (_) {
      // Un ajuste guardado que ya no se entiende no debe impedir escuchar.
    }
  }

  /// Solo para las pruebas: olvida lo puesto en esta sesion.
  @visibleForTesting
  Future<void> reiniciar() async {
    _ajuste = null;
    _correccion = null;
    _refuerzo = 0;
    _extra = 0;
    _perfiles.clear();
    _perfilesCargados = false;
    _salida = null;
    _aparato = null;
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.remove(_clave);
    await memoria.remove(_claveSalidas);
  }
}
