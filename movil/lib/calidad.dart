import 'package:flutter/material.dart';

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
  const CalidadAudio({required this.codec, this.kbps, this.hz});

  factory CalidadAudio.desdeJson(Map<String, dynamic> j) => CalidadAudio(
        codec: (j['codec'] ?? '').toString(),
        kbps: (j['kbps'] as num?)?.toDouble(),
        hz: (j['hz'] as num?)?.toInt(),
      );

  /// null si no hay nada que leer: una descarga antigua no lo sabe.
  static CalidadAudio? tal(Object? j) =>
      j is Map<String, dynamic> && (j['codec'] ?? '').toString().isNotEmpty
          ? CalidadAudio.desdeJson(j)
          : null;

  final String codec;
  final double? kbps;
  final int? hz;

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

  bool get hiRes => sinPerdida && (hz ?? 0) > 48000;

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
      final String alta = hiRes ? ' · ${(hz! / 1000).toStringAsFixed(hz! % 1000 == 0 ? 0 : 1)} kHz' : '';
      return '$nombreCodec · sin perdida$alta';
    }
    final double? k = kbps;
    return k == null ? nombreCodec : '$nombreCodec ${k.round()} kb/s';
  }

  /// Si esta es mejor que [otra]: primero lo sin perdida, luego el bitrate.
  bool mejorQue(CalidadAudio otra) {
    if (sinPerdida != otra.sinPerdida) return sinPerdida;
    if (hiRes != otra.hiRes) return hiRes;
    return (kbps ?? 0) > (otra.kbps ?? 0);
  }

  Map<String, dynamic> aJson() => <String, dynamic>{'codec': codec, 'kbps': kbps, 'hz': hz};

  @override
  bool operator ==(Object other) =>
      other is CalidadAudio && other.codec == codec && other.kbps == kbps && other.hz == hz;

  @override
  int get hashCode => Object.hash(codec, kbps, hz);
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
  return null;
}

/// El sello de calidad, pequenio, para tarjetas, filas y el reproductor.
class SelloCalidad extends StatelessWidget {
  const SelloCalidad({required this.calidad, this.grande = false, super.key});

  final CalidadAudio calidad;
  final bool grande;

  static const Color _oro = Color(0xFFFFC857);
  static const Color _verde = Color(0xFF57D9A3);

  @override
  Widget build(BuildContext context) {
    final NivelCalidad nivel = calidad.nivel;
    final (String texto, Color color) = switch (nivel) {
      NivelCalidad.hiRes => ('HI-RES · ${calidad.etiqueta}', _oro),
      NivelCalidad.sinPerdida => ('SIN PERDIDA · ${calidad.nombreCodec}', _oro),
      NivelCalidad.alta => (calidad.etiqueta, _verde),
      NivelCalidad.buena => (calidad.etiqueta, Colors.white70),
      NivelCalidad.basica => (calidad.etiqueta, Colors.white38),
    };
    final bool destaca = nivel == NivelCalidad.hiRes || nivel == NivelCalidad.sinPerdida;
    return Container(
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
