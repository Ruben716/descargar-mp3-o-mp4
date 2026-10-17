import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'animaciones.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Marco comun de las portadas: esquinas redondeadas y relleno de reserva.
class _Marco extends StatelessWidget {
  const _Marco({required this.hijo, required this.lado, required this.radio, required this.reserva});

  final Widget? hijo;
  final double lado;
  final double radio;

  /// Lo que se pinta si no hay imagen.
  final Widget reserva;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(width: lado, height: lado, child: hijo ?? reserva),
    );
  }
}

/// Los dos tonos del degradado de una portada que no existe, sacados de [clave].
///
/// La misma clave da siempre los mismos colores, en esta y en cualquier otra
/// ejecucion: por eso el hash es uno propio (FNV-1a) y no `hashCode`, que Dart
/// no promete estable. El tono cae entre el teal y el violeta, pasando por el
/// cian y el azul de la marca, y nunca en rojos ni verdes chillones; el
/// segundo es mas oscuro y algo girado, para que el degradado tenga fondo.
(Color, Color) colorDeArtista(String clave) {
  int h = 0x811c9dc5;
  for (final int c in clave.trim().toLowerCase().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  // Del teal (170) al violeta (265).
  final double tono = 170 + (h % 96);
  final double saturacion = 0.45 + ((h >> 8) % 20) / 100;
  final double luz = 0.36 + ((h >> 16) % 10) / 100;
  final double giro = ((h >> 24) % 2 == 0 ? 1 : -1) * (18 + (h >> 12) % 14).toDouble();
  final Color claro = HSLColor.fromAHSL(1, tono, saturacion, luz).toColor();
  final Color oscuro =
      HSLColor.fromAHSL(1, (tono + giro).clamp(160.0, 275.0), saturacion * 0.9, luz * 0.55).toColor();
  return (claro, oscuro);
}

/// Una o dos iniciales de [nombre]: «Bad Bunny» da «BB» y «Shakira», «S».
///
/// Se salta lo que no es letra ni cifra («¡», «(»...) y las coletillas de
/// colaboracion («feat.», «ft.»), que no dicen nada de quien es.
String iniciales(String nombre) {
  final List<String> palabras = nombre
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((String p) => p.isNotEmpty && !const <String>{'feat', 'ft'}.contains(p.toLowerCase()))
      .take(2)
      .toList();
  return palabras.map((String p) => String.fromCharCode(p.runes.first).toUpperCase()).join();
}

/// La portada de lo que no trae: un degradado propio del artista con sus
/// iniciales, para que cada cancion sin caratula se distinga de las demas.
class _SinCaratula extends StatelessWidget {
  const _SinCaratula({required this.clave, required this.lado, required this.icono});

  final String clave;
  final double lado;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final (Color claro, Color oscuro) = colorDeArtista(clave);
    final String letras = iniciales(clave);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[claro, oscuro],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Align(
            alignment: letras.isEmpty ? Alignment.center : const Alignment(0.8, 0.8),
            child: Icon(
              icono,
              color: Colors.white.withValues(alpha: letras.isEmpty ? 0.3 : 0.12),
              size: lado * (letras.isEmpty ? 0.45 : 0.3),
            ),
          ),
          if (letras.isNotEmpty)
            Center(
              child: ExcludeSemantics(
                child: Text(
                  letras,
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                    fontSize: lado * (letras.length > 1 ? 0.34 : 0.4),
                    height: 1,
                    letterSpacing: lado * 0.01,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Portada de un archivo ya descargado, sacada de MediaStore.
class PortadaLocal extends StatelessWidget {
  const PortadaLocal({
    required this.elemento,
    this.lado = 56,
    this.radio = 16,
    super.key,
  });

  final Elemento elemento;
  final double lado;
  final double radio;

  Widget _marco(BuildContext context, Uint8List? datos) => _Marco(
    lado: lado,
    radio: radio,
    reserva: _SinCaratula(
      clave: elemento.artista.isNotEmpty ? elemento.artista : elemento.tema,
      lado: lado,
      icono: elemento.audio ? Icons.music_note : Icons.movie_creation,
    ),
    hijo: datos == null
        ? null
        : Image.memory(
            datos,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Descodificada al tamano al que se pinta. Las portadas guardadas
            // miden 512 px, y en una lista se ensenian a 50: descodificarlas
            // enteras gastaba memoria y daba tirones al desplazar. En la
            // portada grande no se toca, que ahi se ve cada pixel.
            cacheWidth: lado < 200 ? (lado * MediaQuery.devicePixelRatioOf(context)).round() : null,
            frameBuilder: _fundido,
          ),
  );

  @override
  Widget build(BuildContext context) {
    // Si ya se conoce, se pinta directamente. Pasar por un FutureBuilder aqui
    // volveria a lanzar la peticion en cada reconstruccion, que es justo lo
    // que dejaba la app pillada al arrancar.
    if (Nucleo.caratulaConocida(elemento.uri)) {
      return _marco(context, Nucleo.caratulaGuardada(elemento.uri));
    }
    return FutureBuilder<Uint8List?>(
      future: Nucleo.caratula(elemento.uri),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> imagen) =>
          _marco(context, imagen.data),
    );
  }
}

/// Miniatura de un resultado de busqueda, que viene de la red.
class PortadaRemota extends StatelessWidget {
  const PortadaRemota({required this.url, this.ancho = 128, this.alto = 74, super.key});

  final String url;
  final double ancho;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: ancho,
        height: alto,
        child: url.isEmpty
            ? const ColoredBox(
                color: Tema.superficieAlta,
                child: Icon(Icons.image_not_supported, color: Colors.white24),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: (ancho * MediaQuery.devicePixelRatioOf(context)).round(),
                frameBuilder: _fundido,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Tema.superficieAlta,
                  child: Icon(Icons.broken_image, color: Colors.white24),
                ),
                loadingBuilder: (BuildContext context, Widget hijo, ImageChunkEvent? avance) {
                  if (avance == null) return hijo;
                  return const ColoredBox(color: Tema.superficieAlta);
                },
              ),
      ),
    );
  }
}

/// Las imagenes que tardan en llegar aparecen con un fundido, no de golpe.
/// Las que ya estaban (se pintan en el mismo fotograma) salen tal cual.
Widget _fundido(BuildContext context, Widget hijo, int? fotograma, bool alInstante) {
  if (alInstante) return hijo;
  return AnimatedOpacity(
    opacity: fotograma == null ? 0 : 1,
    duration: Movimiento.de(context, Movimiento.medio),
    curve: Curves.easeOut,
    child: hijo,
  );
}
