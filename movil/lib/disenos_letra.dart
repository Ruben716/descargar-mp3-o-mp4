import 'dart:math';

import 'package:flutter/material.dart';

import 'nucleo.dart';
import 'portadas.dart';
import 'tarjeta_letra.dart';
import 'video_letra.dart';

/// Como se viste la frase, en la tarjeta y en el video.
///
/// En el video, el vinilo gira y la portada se acerca despacio: lo mueve
/// FFmpeg (ver video_letra.py) encima del fotograma, que ya lo trae quieto en
/// el mismo sitio. Si el FFmpeg del telefono no sabe moverlo, sale quieto.
enum EstiloLetra {
  letra('Letra', Icons.notes_rounded),
  vinilo('Vinilo', Icons.album_rounded),
  portada('Portada', Icons.photo_outlined);

  const EstiloLetra(this.titulo, this.icono);

  final String titulo;
  final IconData icono;

  /// A cuantas veces el tamano del fotograma se saca lo que se mueve: la
  /// portada al doble, para que al acercarse no se vean los pixeles.
  int get escalaMovil => this == EstiloLetra.portada ? 2 : 1;

  /// Como lo mueve FFmpeg.
  String get movimiento => this == EstiloLetra.vinilo ? 'girar' : 'zoom';
}

/// Donde va cada cosa, en puntos: el texto (cabecera, frase y marca), la onda
/// del video y lo que se mueve (null en el estilo de siempre).
typedef DisenoLetra = ({Rect texto, Rect onda, Rect? movil});

/// El sitio de cada cosa en un lienzo de 360 de ancho con la forma de
/// [formato]. En la tarjeta no hay onda y el texto baja hasta el borde.
DisenoLetra disenoLetra(FormatoTarjeta formato, EstiloLetra estilo, {bool video = true}) {
  final bool alta = formato == FormatoTarjeta.historia;
  final double alto = TarjetaLetra.ancho / formato.proporcion;
  final Rect onda = alta ? const Rect.fromLTWH(20, 532, 320, 80) : const Rect.fromLTWH(30, 298, 300, 44);
  final ({Rect texto, Rect? movil}) sitio = switch ((estilo, alta)) {
    (EstiloLetra.letra, true) => (texto: const Rect.fromLTRB(30, 44, 330, 520), movil: null),
    (EstiloLetra.letra, false) => (texto: const Rect.fromLTRB(24, 24, 336, 286), movil: null),
    (EstiloLetra.vinilo, true) => (
      texto: const Rect.fromLTRB(30, 316, 330, 520),
      movil: const Rect.fromLTWH(62, 56, 236, 236),
    ),
    (EstiloLetra.vinilo, false) => (
      texto: const Rect.fromLTRB(192, 24, 336, 286),
      movil: const Rect.fromLTWH(18, 77, 158, 158),
    ),
    (EstiloLetra.portada, true) => (
      texto: const Rect.fromLTRB(30, 346, 330, 520),
      movil: const Rect.fromLTWH(0, 0, 360, 326),
    ),
    (EstiloLetra.portada, false) => (
      texto: const Rect.fromLTRB(190, 24, 336, 286),
      movil: const Rect.fromLTWH(0, 0, 172, 360),
    ),
  };
  // En la cuadrada con portada la onda va bajo el texto, no sobre la foto.
  final Rect ondaFinal = !alta && estilo == EstiloLetra.portada ? const Rect.fromLTWH(190, 298, 146, 44) : onda;
  if (video) return (texto: sitio.texto, onda: ondaFinal, movil: sitio.movil);
  final Rect t = sitio.texto;
  return (texto: Rect.fromLTRB(t.left, t.top, t.right, alto - (alta ? 34 : 22)), onda: ondaFinal, movil: sitio.movil);
}

/// Lo que necesita video_letra.py: el lienzo, la onda y lo que se mueve, en
/// px del video (ver `diseno_de`). Sin [movil] (el PNG de lo que se mueve) no
/// se mueve nada: el fotograma ya lo trae quieto.
Map<String, Object> disenoParaFfmpeg(FormatoTarjeta formato, EstiloLetra estilo, {String? movil}) {
  const double px = FotogramaVideo.escala;
  final DisenoLetra d = disenoLetra(formato, estilo);
  List<int> enPx(Rect r) => <int>[
    for (final double v in <double>[r.left, r.top, r.width, r.height]) (v * px).round(),
  ];
  final Rect? sitio = d.movil;
  return <String, Object>{
    'ancho': FotogramaVideo.anchoExportado.round(),
    'alto': (TarjetaLetra.ancho / formato.proporcion * px).round(),
    'onda': enPx(d.onda),
    if (movil != null && sitio != null)
      'movil': <String, Object>{
        'png': movil,
        'tipo': estilo.movimiento,
        'x': enPx(sitio)[0],
        'y': enPx(sitio)[1],
        'ancho': enPx(sitio)[2],
        'alto': enPx(sitio)[3],
      },
  };
}

/// Lo que se mueve, pintado quieto: el vinilo o la portada.
class MovilLetra extends StatelessWidget {
  const MovilLetra({required this.estilo, required this.elemento, this.portada, super.key});

  final EstiloLetra estilo;
  final Elemento elemento;
  final ImageProvider? portada;

  @override
  Widget build(BuildContext context) => estilo == EstiloLetra.vinilo
      ? Disco(elemento: elemento, portada: portada)
      : PortadaGrande(elemento: elemento, portada: portada);
}

/// La caratula llenando su sitio, recortada si no es cuadrado.
class PortadaGrande extends StatelessWidget {
  const PortadaGrande({required this.elemento, this.portada, super.key});

  final Elemento elemento;
  final ImageProvider? portada;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? imagen = portada;
    final Widget reserva = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: PortadaLocal(elemento: elemento, lado: 360, radio: 0),
    );
    if (imagen == null) return SizedBox.expand(child: reserva);
    return Image(
      image: imagen,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => reserva,
    );
  }
}

/// Un vinilo con la caratula de etiqueta.
///
/// Los surcos son circulos: al girar no se ven moverse. Lo que dice que gira
/// es la etiqueta y un brillo en cuña, que en un disco de verdad se quedaria
/// quieto pero en el video, sin el, el disco parece parado.
class Disco extends StatelessWidget {
  const Disco({required this.elemento, this.portada, super.key});

  final Elemento elemento;
  final ImageProvider? portada;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints limites) {
          final double lado = limites.maxWidth;
          final double etiqueta = lado * 0.4;
          final ImageProvider? imagen = portada;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const Positioned.fill(child: CustomPaint(painter: _PintorVinilo())),
              ClipOval(
                child: SizedBox.square(
                  dimension: etiqueta,
                  child: imagen == null
                      ? FittedBox(
                          child: PortadaLocal(elemento: elemento, lado: etiqueta, radio: 0),
                        )
                      : Image(
                          image: imagen,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => PortadaLocal(elemento: elemento, lado: etiqueta, radio: 0),
                        ),
                ),
              ),
              // El agujero del centro.
              Container(
                width: lado * 0.035,
                height: lado * 0.035,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0B0B0C)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PintorVinilo extends CustomPainter {
  const _PintorVinilo();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centro = size.center(Offset.zero);
    final double radio = size.shortestSide / 2;
    canvas.drawCircle(centro, radio, Paint()..color = const Color(0xFF111113));
    // Los surcos: finos, cada uno algo distinto, como la luz en el vinilo.
    final Paint surco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.5, radio * 0.006);
    for (double r = radio * 0.24; r < radio * 0.97; r += radio * 0.022) {
      final double luz = 0.03 + 0.035 * (sin(r * 0.7).abs());
      canvas.drawCircle(centro, r, surco..color = Colors.white.withValues(alpha: luz));
    }
    // Dos cuñas de brillo enfrentadas.
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: <Color>[
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const <double>[0.05, 0.12, 0.2, 0.55, 0.62, 0.7, 1],
        ).createShader(Rect.fromCircle(center: centro, radius: radio)),
    );
    // El borde, un pelo mas claro, para que se separe de un fondo oscuro.
    canvas.drawCircle(
      centro,
      radio - surco.strokeWidth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radio * 0.012
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_PintorVinilo anterior) => false;
}
