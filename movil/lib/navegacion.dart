import 'package:flutter/material.dart';

/// Pedir desde cualquier pantalla que se cambie de pestania.
///
/// Las pestanias las lleva el armazon de main.dart, que escucha esto. Asi
/// Descargar puede llevar a la Biblioteca sin conocer el armazon.
class Navegacion {
  Navegacion._();

  static const int inicio = 0;
  static const int descargar = 1;
  static const int biblioteca = 2;
  static const int ver = 3;

  static final ValueNotifier<int?> pestanaPedida = ValueNotifier<int?>(null);

  /// Para avisar sin tener un `context` a mano (los atajos del icono).
  static final GlobalKey<ScaffoldMessengerState> mensajes = GlobalKey<ScaffoldMessengerState>();

  static void avisar(String texto) {
    mensajes.currentState?.showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(texto)),
    );
  }

  static void irA(int pestana) {
    // Se pasa por null para que pedir dos veces la misma pestania avise igual.
    pestanaPedida.value = null;
    pestanaPedida.value = pestana;
  }
}
