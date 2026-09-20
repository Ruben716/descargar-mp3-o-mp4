import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un ajuste con nombre del ecualizador.
///
/// La curva se da en funcion de la posicion de la banda, de 0 (la mas grave) a
/// 1 (la mas aguda), y no como una lista de valores fijos: cada telefono
/// reparte sus bandas como quiere, y hay desde cinco hasta diez. Asi el ajuste
/// vale igual en todos.
class Ajuste {
  const Ajuste(this.nombre, this._curva);

  final String nombre;
  final double Function(double posicion) _curva;

  /// Ganancia en decibelios para esa banda, con [techo] como maximo del aparato.
  double ganancia(double posicion, double techo) => _curva(posicion) * techo;

  static const Ajuste plano = Ajuste('Plano', _plano);
  static const Ajuste graves = Ajuste('Graves', _graves);
  static const Ajuste voz = Ajuste('Voz', _voz);
  static const Ajuste agudos = Ajuste('Agudos', _agudos);
  static const Ajuste fiesta = Ajuste('Fiesta', _fiesta);

  static const List<Ajuste> todos = <Ajuste>[plano, graves, voz, agudos, fiesta];

  static double _plano(double _) => 0;

  /// Sube abajo y cae rapido: el bombo y el bajo.
  static double _graves(double p) => 0.75 * (1 - p) * (1 - p);

  /// Campana en el centro, donde vive la voz.
  static double _voz(double p) {
    final double centrado = 2 * p - 1;
    return 0.6 * (1 - centrado * centrado);
  }

  static double _agudos(double p) => 0.7 * p * p;

  /// La uve de toda la vida: graves y brillo, y el centro hundido.
  static double _fiesta(double p) {
    final double centrado = 2 * p - 1;
    return 0.65 * centrado * centrado - 0.2;
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

  /// Cuanto se refuerza el volumen, en decibelios.
  double get refuerzo => realce.targetGain;

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
  Future<AndroidEqualizerParameters> get parametros async =>
      _cache ??= await motor.parameters;

  Future<void> activar(bool encendido) async {
    await motor.setEnabled(encendido);
    await _guardar();
  }

  Future<void> reforzar(double decibelios) async {
    await realce.setTargetGain(decibelios);
    // El refuerzo se apaga solo cuando se deja a cero, para no gastar efecto.
    await realce.setEnabled(decibelios > 0);
    await _guardar();
  }

  /// Aplica un ajuste con nombre a todas las bandas.
  Future<void> aplicar(Ajuste ajuste) async {
    final AndroidEqualizerParameters p = await parametros;
    final int cuantas = p.bands.length;
    for (int i = 0; i < cuantas; i++) {
      final double posicion = cuantas <= 1 ? 0.5 : i / (cuantas - 1);
      final double pedida = ajuste.ganancia(posicion, p.maxDecibels);
      await p.bands[i].setGain(pedida.clamp(p.minDecibels, p.maxDecibels));
    }
    if (!motor.enabled) await motor.setEnabled(true);
    await _guardar();
  }

  Future<void> ajustarBanda(AndroidEqualizerBand banda, double ganancia) async {
    await banda.setGain(ganancia);
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
        'refuerzo': realce.targetGain,
        // Sin bandas todavia no se inventa nada: se guarda lo que si se sabe.
        if (p != null)
          'bandas': p.bands.map((AndroidEqualizerBand b) => b.gain).toList(),
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
      final AndroidEqualizerParameters p = await parametros;
      final List<dynamic> bandas = (datos['bandas'] as List<dynamic>?) ?? <dynamic>[];
      // Si el aparato cambio de numero de bandas, se aplica lo que encaje y el
      // resto se queda como esta: mejor eso que descartar todo el ajuste.
      for (int i = 0; i < p.bands.length && i < bandas.length; i++) {
        final double valor = (bandas[i] as num).toDouble();
        await p.bands[i].setGain(valor.clamp(p.minDecibels, p.maxDecibels));
      }
      final double refuerzoGuardado = ((datos['refuerzo'] as num?) ?? 0).toDouble();
      await realce.setTargetGain(refuerzoGuardado);
      await realce.setEnabled(refuerzoGuardado > 0);
      await motor.setEnabled(datos['activo'] == true);
    } catch (_) {
      // Un ajuste guardado que ya no se entiende no debe impedir escuchar.
    }
  }

  /// Solo para las pruebas: olvida lo puesto en esta sesion.
  @visibleForTesting
  Future<void> reiniciar() async {
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.remove(_clave);
  }
}
