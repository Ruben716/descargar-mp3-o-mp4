import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'animaciones.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Marco comun de las portadas: esquinas redondeadas y relleno de reserva.
class _Marco extends StatelessWidget {
  const _Marco({required this.hijo, required this.lado, required this.radio, required this.icono});

  final Widget? hijo;
  final double lado;
  final double radio;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(
        width: lado,
        height: lado,
        child: hijo ??
            DecoratedBox(
              decoration: const BoxDecoration(gradient: Tema.degradado),
              child: Icon(icono, color: Colors.black38, size: lado * 0.45),
            ),
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
    icono: elemento.audio ? Icons.music_note : Icons.movie_creation,
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
