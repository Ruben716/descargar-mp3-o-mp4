import 'dart:async';

import 'package:flutter/foundation.dart';

import 'autoeq.dart';
import 'canales_oficiales.dart';
import 'ecualizador.dart';
import 'nucleo.dart';

/// Por donde sale la musica.
enum TipoSalida { altavoz, cable, bluetooth, usb }

/// El aparato por el que suena la musica ahora mismo.
@immutable
class SalidaAudio {
  const SalidaAudio(this.tipo, {this.nombre = '', this.modelo = ''});

  /// Lo que manda Kotlin: {tipo, nombre, modelo}.
  factory SalidaAudio.desdeMapa(Map<dynamic, dynamic> m) => SalidaAudio(
        TipoSalida.values.firstWhere(
          (TipoSalida t) => t.name == '${m['tipo']}',
          orElse: () => TipoSalida.altavoz,
        ),
        nombre: '${m['nombre'] ?? ''}'.trim(),
        modelo: '${m['modelo'] ?? ''}'.trim(),
      );

  static const SalidaAudio altavoz = SalidaAudio(TipoSalida.altavoz);

  final TipoSalida tipo;

  /// El nombre del aparato (el de unos audifonos Bluetooth, por ejemplo).
  final String nombre;

  /// El telefono, como «samsung SM-A546E»: para decir de quien es el altavoz.
  final String modelo;

  /// Con que se guarda su ajuste: cada audifono Bluetooth tiene el suyo, pero
  /// el cable es uno solo (Android no dice que audifonos van enchufados).
  String get clave => switch (tipo) {
        TipoSalida.altavoz => 'altavoz',
        TipoSalida.cable => 'cable',
        TipoSalida.bluetooth || TipoSalida.usb => '${tipo.name}:${nombre.toLowerCase()}',
      };

  bool get esAudifono => tipo != TipoSalida.altavoz;

  String get titulo => switch (tipo) {
        TipoSalida.altavoz => modelo.isEmpty ? 'Altavoz del telefono' : 'Altavoz del $modelo',
        TipoSalida.cable => 'Audifonos con cable',
        TipoSalida.bluetooth => nombre.isEmpty ? 'Bluetooth' : nombre,
        TipoSalida.usb => nombre.isEmpty ? 'Audifonos USB' : nombre,
      };

  @override
  bool operator ==(Object other) => other is SalidaAudio && other.clave == clave;

  @override
  int get hashCode => clave.hashCode;
}

/// Nombres que dan muchos aparatos y no dicen que modelo son.
const Set<String> _genericos = <String>{
  'bluetooth', 'headset', 'headphones', 'earphones', 'auriculares', 'audifonos', 'speaker', 'car', 'usb audio',
  'usb', 'bt', 'stereo', 'handsfree', 'hands free', 'audio',
};

/// El modelo de AutoEQ que corresponde al nombre de un aparato, o null si no
/// esta claro: se prefiere no corregir a corregir con la curva de otro.
///
/// Los nombres Bluetooth suelen ser el modelo sin la marca («Galaxy Buds2»,
/// «WH-1000XM4»), a veces con «LE-» delante o un codigo entre parentesis.
ModeloAudifonos? modeloParaAparato(List<ModeloAudifonos> todos, String aparato) {
  String limpio = aparato.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  limpio = limpio.replaceFirst(RegExp(r'^\s*LE[-_ ]', caseSensitive: false), '');
  final String clave = CanalesOficiales.normalizar(limpio).trim();
  if (clave.length < 3 || _genericos.contains(clave)) return null;
  final List<ModeloAudifonos> candidatos = AutoEq.buscar(todos, clave, limite: 12);
  final List<ModeloAudifonos> exactos = <ModeloAudifonos>[
    for (final ModeloAudifonos m in candidatos)
      if (CanalesOficiales.normalizar(m.nombre) == clave || CanalesOficiales.normalizar(m.nombre).endsWith(' $clave'))
        m,
  ];
  if (exactos.length == 1) return exactos.single;
  return candidatos.length == 1 ? candidatos.single : null;
}

/// Sigue la salida de audio y le pide al ecualizador el ajuste de cada una.
///
/// Al conectar unos audifonos Bluetooth se pone su ajuste guardado; si es la
/// primera vez y AutoEQ los conoce, su correccion. Al quitarlos vuelve el del
/// altavoz, que de fabrica recorta los graves que un altavoz pequeno no puede dar.
class SalidasDeAudio extends ChangeNotifier {
  SalidasDeAudio._();

  static final SalidasDeAudio instancia = SalidasDeAudio._();

  SalidaAudio? _actual;

  /// La salida de ahora, o null si aun no se sabe.
  SalidaAudio? get actual => _actual;

  /// Como se pregunta la salida. Las pruebas lo cambian.
  @visibleForTesting
  static Future<SalidaAudio?> Function() preguntar = Nucleo.salidaDeAudio;

  /// Pregunta la salida al abrir y escucha los cambios que avise Android.
  Future<void> empezar() async {
    Nucleo.alCambiarSalida = (Map<dynamic, dynamic> datos) => cambiar(SalidaAudio.desdeMapa(datos));
    final SalidaAudio? inicial = await preguntar();
    if (inicial != null) await cambiar(inicial);
  }

  Future<void> cambiar(SalidaAudio nueva) async {
    if (nueva == _actual) return;
    _actual = nueva;
    notifyListeners();
    await Ecualizador.instancia.cambiarSalida(nueva);
  }

  @visibleForTesting
  void reiniciar() {
    _actual = null;
    preguntar = Nucleo.salidaDeAudio;
  }
}
