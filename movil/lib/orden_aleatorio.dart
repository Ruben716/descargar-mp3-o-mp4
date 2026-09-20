import 'dart:math';

import 'package:just_audio/just_audio.dart';

/// El orden en que suena la cola cuando el aleatorio esta puesto.
///
/// Es igual que el de fabrica salvo en una cosa: el de fabrica reparte las
/// altas en un sitio al azar de la cola, asi que "reproducir a continuacion"
/// no reproducia a continuacion, dejaba la pista caer donde quisiera. Aqui el
/// llamante puede decir en que posicion de la escucha tienen que caer.
class OrdenAleatorio extends ShuffleOrder {
  OrdenAleatorio({Random? azar}) : _azar = azar ?? Random();

  final Random _azar;

  /// Posiciones de la cola original, en el orden en que van a sonar.
  @override
  final List<int> indices = <int>[];

  /// Donde cae lo siguiente que se anada, contado en orden de escucha.
  ///
  /// Con `null` se reparte al azar, que es lo que se quiere al encolar sin
  /// mas. El llamante lo pone justo antes de anadir y lo vuelve a dejar en
  /// `null`, porque solo vale para esa insercion.
  int? proximaInsercion;

  @override
  void shuffle({int? initialIndex}) {
    assert(initialIndex == null || indices.contains(initialIndex));
    if (indices.length <= 1) return;
    indices.shuffle(_azar);
    if (initialIndex == null) return;

    // Lo que ya esta sonando pasa a la cabeza, o el barajado cortaria la
    // cancion actual para empezar otra.
    final int donde = indices.indexOf(initialIndex);
    indices[donde] = indices[0];
    indices[0] = initialIndex;
  }

  @override
  void insert(int index, int count) {
    // Lo que estaba detras del punto de insercion se corre en la cola original.
    for (int i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }

    final int? destino = proximaInsercion;
    for (int i = 0; i < count; i++) {
      indices.insert(
        destino == null
            ? _azar.nextInt(indices.length + 1)
            : (destino + i).clamp(0, indices.length),
        index + i,
      );
    }
  }

  @override
  void removeRange(int start, int end) {
    final Set<int> fuera = <int>{for (int i = start; i < end; i++) i};
    indices.removeWhere(fuera.contains);
    for (int i = 0; i < indices.length; i++) {
      if (indices[i] >= end) indices[i] -= end - start;
    }
  }

  @override
  void clear() => indices.clear();
}
