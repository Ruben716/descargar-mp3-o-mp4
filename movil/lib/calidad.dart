import 'dart:async';

import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'tema.dart';

/// Cuanta calidad tiene el audio de verdad.
enum NivelCalidad {
  /// Sin perdida y por encima de lo de un CD.
  hiRes,

  /// Sin perdida: el audio entero, como salio del estudio o del escenario.
  sinPerdida,

  /// Comprimido, pero de lo mejor que se encuentra gratis.
  alta,

  /// Lo normal de YouTube y compania.
  buena,

  /// Por debajo de lo normal.
  basica,
}

/// La calidad del audio en su origen, antes de convertirlo a nada.
///
/// Es lo unico que se ensenia como calidad. Pasar a FLAC un Opus de 128 kb/s
/// no le devuelve lo que se perdio al comprimirlo: solo ocupa cinco veces mas.
/// Si la app llamara «maxima calidad» a ese FLAC estaria mintiendo, asi que el
/// sello dice de donde salio el sonido, no en que caja se guardo.
class CalidadAudio {
  const CalidadAudio({
    required this.codec,
    this.kbps,
    this.hz,
    this.bits,
    this.estimada = false,
  });

  factory CalidadAudio.desdeJson(Map<String, dynamic> j) => CalidadAudio(
        codec: (j['codec'] ?? '').toString(),
        kbps: (j['kbps'] as num?)?.toDouble(),
        hz: (j['hz'] as num?)?.toInt(),
        bits: (j['bits'] as num?)?.toInt(),
      );

  /// Lo que da YouTube casi siempre, medido: Opus a unos 127 kb/s.
  ///
  /// Sirve para ordenar sus resultados sin comprobar uno por uno, que en el
  /// telefono tarda. Se dice «~» delante para no darlo por comprobado.
  static const CalidadAudio tipicaDeYoutube =
      CalidadAudio(codec: 'opus', kbps: 127, hz: 48000, estimada: true);

  /// null si no hay nada que leer: una descarga antigua no lo sabe.
  static CalidadAudio? tal(Object? j) =>
      j is Map<String, dynamic> && (j['codec'] ?? '').toString().isNotEmpty
          ? CalidadAudio.desdeJson(j)
          : null;

  final String codec;
  final double? kbps;
  final int? hz;

  /// Bits por muestra. Solo se sabe leyendo el archivo sin perdida ya bajado.
  final int? bits;

  /// Si es lo tipico de la fuente y no algo comprobado en este resultado.
  final bool estimada;

  static const Set<String> _sinPerdida = <String>{'flac', 'alac', 'wav', 'pcm', 'aiff'};

  static const Map<String, String> _nombres = <String, String>{
    'opus': 'Opus',
    'aac': 'AAC',
    'mp3': 'MP3',
    'vorbis': 'Vorbis',
    'flac': 'FLAC',
    'alac': 'ALAC',
    'wav': 'WAV',
    'pcm': 'WAV',
    'aiff': 'AIFF',
  };

  bool get sinPerdida => _sinPerdida.contains(codec);

  /// Mas que un CD: 24 bits, o mas de 48 kHz. Solo cuando se sabe.
  bool get hiRes => sinPerdida && ((bits ?? 0) > 16 || (hz ?? 0) > 48000);

  NivelCalidad get nivel {
    if (hiRes) return NivelCalidad.hiRes;
    if (sinPerdida) return NivelCalidad.sinPerdida;
    final double k = kbps ?? 0;
    // Medido: lo mejor de YouTube ronda 127-130 kb/s y lo de SoundCloud sin
    // DRM llega a 160. Los cortes estan puestos para separar esos dos.
    if (k >= 150) return NivelCalidad.alta;
    if (k >= 110) return NivelCalidad.buena;
    return NivelCalidad.basica;
  }

  String get nombreCodec => _nombres[codec] ?? codec.toUpperCase();

  /// Como se dice en pantalla: «AAC 160 kb/s», «FLAC · sin perdida».
  String get etiqueta {
    if (sinPerdida) {
      final String detalle = <String>[
        if (bits != null) '$bits bits',
        if (hz != null) '${(hz! / 1000).toStringAsFixed(hz! % 1000 == 0 ? 0 : 1)} kHz',
      ].join(' · ');
      return detalle.isEmpty ? '$nombreCodec · sin perdida' : '$nombreCodec · $detalle';
    }
    final double? k = kbps;
    if (k == null) return nombreCodec;
    return '$nombreCodec ${estimada ? '~' : ''}${k.round()} kb/s';
  }

  /// Cuanto rinde cada codec frente a MP3 al mismo bitrate, a grandes rasgos.
  ///
  /// Es la equivalencia que suele salir en las pruebas de escucha: un Opus a
  /// 128 suena como un MP3 a unos 190. Sin ella, un MP3 a 128 de Bandcamp
  /// quedaria por encima del Opus a 127 de YouTube, y suena peor.
  static const Map<String, double> _rinde = <String, double>{
    'opus': 1.5,
    'vorbis': 1.25,
    'aac': 1.2,
    'mp3': 1.0,
  };

  /// Una cifra para ordenar de mejor a peor: sin perdida siempre por encima.
  double get puntos {
    if (sinPerdida) return 10000 + (bits ?? 16) * 10 + (hz ?? 44100) / 1000;
    return (kbps ?? 0) * (_rinde[codec] ?? 1.0);
  }

  /// Si esta es mejor que [otra]: primero lo sin perdida, luego el bitrate.
  bool mejorQue(CalidadAudio otra) => puntos > otra.puntos;

  Map<String, dynamic> aJson() =>
      <String, dynamic>{'codec': codec, 'kbps': kbps, 'hz': hz, 'bits': bits};

  @override
  bool operator ==(Object other) =>
      other is CalidadAudio &&
      other.codec == codec &&
      other.kbps == kbps &&
      other.hz == hz &&
      other.bits == bits &&
      other.estimada == estimada;

  @override
  int get hashCode => Object.hash(codec, kbps, hz, bits, estimada);
}

/// El consejo al elegir formato, segun lo que hay en el origen.
///
/// Devuelve null si lo elegido ya tiene sentido.
String? consejoDeFormato(CalidadAudio origen, String formato) {
  final bool formatoSinPerdida = const <String>['flac', 'wav'].contains(formato);
  if (origen.sinPerdida && !formatoSinPerdida) {
    return 'El origen es sin perdida. Elige FLAC para conservarlo entero.';
  }
  if (!origen.sinPerdida && formatoSinPerdida) {
    return 'El origen es ${origen.etiqueta}: en ${formato.toUpperCase()} ocupara '
        'mucho mas y sonara igual. No se puede recuperar lo que ya se perdio.';
  }
  if (!origen.sinPerdida && reconvierte(origen, formato)) {
    return 'El origen es ${origen.etiqueta}: pasarlo a ${formato.toUpperCase()} lo '
        'vuelve a comprimir y pierde algo mas. Original lo guarda tal cual.';
  }
  return null;
}

/// Codec que sale de cada formato con perdida que se puede elegir.
const Map<String, String> _codecDelFormato = <String, String>{
  'mp3': 'mp3',
  'm4a': 'aac',
  'aac': 'aac',
  'opus': 'opus',
  'vorbis': 'vorbis',
};

/// Si guardar un origen comprimido en [formato] obliga a comprimirlo otra vez.
///
/// «best» nunca reconvierte, y tampoco cuando el destino es el mismo codec
/// (un AAC en M4A se copia). Cada vuelta por un codec con perdida tira algo
/// que ya no vuelve.
bool reconvierte(CalidadAudio origen, String formato) {
  final String? destino = _codecDelFormato[formato];
  return destino != null && destino != origen.codec;
}

/// El sello de calidad, pequenio, para tarjetas, filas y el reproductor.
class SelloCalidad extends StatelessWidget {
  const SelloCalidad({required this.calidad, this.grande = false, this.brillo = false, super.key});

  final CalidadAudio calidad;
  final bool grande;

  /// Un reflejo que cruza el sello de vez en cuando, solo si es sin perdida.
  ///
  /// Para un sello suelto (el del reproductor): en una lista serian cientos
  /// de animaciones a la vez para nada.
  final bool brillo;

  @override
  Widget build(BuildContext context) {
    final NivelCalidad nivel = calidad.nivel;
    final (String texto, Color color) = switch (nivel) {
      NivelCalidad.hiRes => ('HI-RES · ${calidad.etiqueta}', Tema.oro),
      NivelCalidad.sinPerdida => ('SIN PERDIDA · ${calidad.etiqueta.split(' · ').first}', Tema.oro),
      NivelCalidad.alta => (calidad.etiqueta, Tema.exito),
      NivelCalidad.buena => (calidad.etiqueta, Colors.white70),
      NivelCalidad.basica => (calidad.etiqueta, Tema.textoTenue),
    };
    final bool destaca = nivel == NivelCalidad.hiRes || nivel == NivelCalidad.sinPerdida;
    final Widget sello = Container(
      padding: EdgeInsets.symmetric(horizontal: grande ? 10 : 7, vertical: grande ? 4 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: destaca ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: destaca ? 0.7 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (destaca) ...<Widget>[
            Icon(Icons.graphic_eq_rounded, size: grande ? 14 : 11, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible: en una tarjeta estrecha se recorta con «...» en vez de
          // salirse y pintar la franja amarilla.
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: grande ? 11 : 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: destaca ? 0.6 : 0.2,
                // «24 bit · 96 kHz» con cifras del mismo ancho: los sellos de
                // una lista quedan alineados y tienen el aire tecnico que toca.
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (!brillo || !destaca || !Movimiento.continuas(context)) return sello;
    return _Reflejo(radio: 6, child: sello);
  }
}

/// Un brillo diagonal que cruza al hijo cada pocos segundos, como la luz
/// sobre una chapa dorada.
///
/// Cruza en menos de un segundo y luego descansa sin pedir fotogramas: el
/// controlador se para y un temporizador lo vuelve a lanzar.
class _Reflejo extends StatefulWidget {
  const _Reflejo({required this.radio, required this.child});

  final double radio;
  final Widget child;

  @override
  State<_Reflejo> createState() => _ReflejoState();
}

class _ReflejoState extends State<_Reflejo> with SingleTickerProviderStateMixin {
  static const Duration _cruce = Duration(milliseconds: 900);
  static const Duration _descanso = Duration(milliseconds: 2600);

  late final AnimationController _paso = AnimationController(vsync: this, duration: _cruce)
    ..addStatusListener(_alAcabar);
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    // El primero tarda un poco: que no brille justo al abrir, sino despues.
    _espera = Timer(const Duration(milliseconds: 1200), _cruzar);
  }

  void _cruzar() {
    if (mounted) _paso.forward(from: 0);
  }

  void _alAcabar(AnimationStatus estado) {
    if (estado == AnimationStatus.completed) _espera = Timer(_descanso, _cruzar);
  }

  @override
  void dispose() {
    _espera?.cancel();
    _paso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          foregroundPainter: _PintorReflejo(_paso, widget.radio),
          child: widget.child,
        ),
      );
}

class _PintorReflejo extends CustomPainter {
  _PintorReflejo(this.paso, this.radio) : super(repaint: paso);

  final Animation<double> paso;
  final double radio;

  static const Color _luz = Color(0x59FFF3D6);
  static const Color _nada = Color(0x00FFF3D6);

  @override
  void paint(Canvas canvas, Size size) {
    final double t = paso.value;
    if (t <= 0 || t >= 1) return;
    final double avance = Curves.easeInOutCubic.transform(t);
    // La franja va de fuera a fuera, inclinada: entra por la izquierda y sale
    // por la derecha sin asomarse quieta en ningun borde.
    final double banda = size.height * 1.4;
    final double x = -banda + avance * (size.width + 2 * banda);
    final Rect zona = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(zona, Radius.circular(radio)));
    canvas.drawRect(
      zona,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_nada, _luz, _nada],
        ).createShader(Rect.fromPoints(Offset(x - banda / 2, 0), Offset(x + banda / 2, size.height))),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorReflejo antes) => antes.paso != paso || antes.radio != radio;
}
