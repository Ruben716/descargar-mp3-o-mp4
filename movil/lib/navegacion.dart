import 'package:flutter/foundation.dart';

/// Pedir desde cualquier pantalla que se cambie de pestania.
///
/// Las pestanias las lleva el armazon de main.dart, que escucha esto. Asi
/// Descargar puede llevar a la Biblioteca sin conocer el armazon.
class Navegacion {
  Navegacion._();

  static const int inicio = 0;
  static const int descargar = 1;
  static const int biblioteca = 2;

  static final ValueNotifier<int?> pestanaPedida = ValueNotifier<int?>(null);

  static void irA(int pestana) {
    // Se pasa por null para que pedir dos veces la misma pestania avise igual.
    pestanaPedida.value = null;
    pestanaPedida.value = pestana;
  }
}
