import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Vuelca lo puesto a disco para recuperarlo al abrir la app.
  Future<void> _guardar() async {
    final AndroidEqualizerParameters? p = _cache;
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.setString(
      _clave,
      jsonEncode(<String, dynamic>{
        'activo': motor.enabled,
        'refuerzo': _refuerzo,
        'ajuste': _ajuste?.nombre,
        'correccion': _correccion?.aJson(),
        // Sin bandas todavia no se inventa nada: se guarda lo que si se sabe.
        if (p != null) 'bandas': p.bands.map((AndroidEqualizerBand b) => b.gain).toList(),
      }),
    );
  }

  /// Recupera lo guardado. Se llama cuando el reproductor ya tiene una pista,
  /// que es cuando el aparato responde con sus bandas.
  Future<void> recuperar() async {
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    final String? crudo = memoria.getString(_clave);
    if (crudo == null) return;
    try {
      final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
      _ajuste = Ajuste.porNombre(datos['ajuste']?.toString());
      final dynamic c = datos['correccion'];
      _correccion = c is Map<String, dynamic> ? Correccion.desdeJson(c) : null;
      final AndroidEqualizerParameters p = await parametros;
      final List<dynamic> bandas = (datos['bandas'] as List<dynamic>?) ?? <dynamic>[];
      // Si el aparato cambio de numero de bandas, se aplica lo que encaje y el
      // resto se queda como esta: mejor eso que descartar todo el ajuste.
      for (int i = 0; i < p.bands.length && i < bandas.length; i++) {
        final double valor = (bandas[i] as num).toDouble();
        await p.bands[i].setGain(valor.clamp(p.minDecibels, p.maxDecibels));
      }
      _refuerzo = ((datos['refuerzo'] as num?) ?? 0).toDouble();
      await _ponerRealce();
      await motor.setEnabled(datos['activo'] == true);
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
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.remove(_clave);
  }
}
