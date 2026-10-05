import 'package:flutter/material.dart';

import 'tema.dart';

/// Pregunta antes de hacer algo que borra. Devuelve true si se confirma.
///
/// El boton que borra va en rojo y a la derecha, y el de cancelar es el que
/// queda a mano: equivocarse tiene que costar un toque mas, no uno menos.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext contexto) => AlertDialog(
        backgroundColor: Tema.superficieAlta,
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B81), size: 32),
        title: Text(titulo, textAlign: TextAlign.center),
        content: Text(mensaje, style: const TextStyle(height: 1.4)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B81)),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: Text(accion),
          ),
        ],
      ),
    ) ??
    false;

/// Avisa de lo que se acaba de hacer y deja deshacerlo unos segundos.
void avisarConDeshacer(BuildContext context, String texto, Future<void> Function() deshacer) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Deshacer', onPressed: deshacer),
      ),
    );
}

/// Un aviso corto, sin nada que hacer con el.
void avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating));
}
