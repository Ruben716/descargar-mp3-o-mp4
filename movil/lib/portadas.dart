import 'dart:typed_data';

import 'package:flutter/material.dart';

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

  Widget _marco(Uint8List? datos) => _Marco(
    lado: lado,
    radio: radio,
    icono: elemento.audio ? Icons.music_note : Icons.movie_creation,
    hijo: datos == null
        ? null
        : Image.memory(datos, fit: BoxFit.cover, gaplessPlayback: true),
  );

  @override
  Widget build(BuildContext context) {
    // Si ya se conoce, se pinta directamente. Pasar por un FutureBuilder aqui
    // volveria a lanzar la peticion en cada reconstruccion, que es justo lo
    // que dejaba la app pillada al arrancar.
    if (Nucleo.caratulaConocida(elemento.uri)) {
      return _marco(Nucleo.caratulaGuardada(elemento.uri));
    }
    return FutureBuilder<Uint8List?>(
      future: Nucleo.caratula(elemento.uri),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> imagen) =>
          _marco(imagen.data),
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
