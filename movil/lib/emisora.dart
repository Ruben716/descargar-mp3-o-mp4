import 'dart:math';

import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'nucleo.dart';

/// Radio a partir de una cancion, con lo que ya hay en el telefono.
///
/// Sin red y sin que nadie mire lo que escuchas: se arma con lo descargado.
/// Primero suena la elegida; detras, lo del mismo artista, lo marcado con el
/// corazon y lo que mas se escucha, con algo de azar para que cada radio sea
/// distinta y no salga siempre el mismo orden.
class Emisora {
  Emisora._();

  /// Cuantas canciones lleva una radio. Una hora y pico de musica.
  static const int largo = 30;

  /// La cola de la radio de [semilla], ella la primera.
  static List<Elemento> mezcla(
    Elemento semilla,
    List<Elemento> biblioteca, {
    Set<String> favoritas = const <String>{},
    Map<String, int> escuchas = const <String, int>{},
    Random? azar,
  }) {
    final Random suerte = azar ?? Random();
    final String artista = _clave(semilla.partes.artista);
    final int masOida = escuchas.values.fold(1, max);
    final List<({Elemento e, double puntos})> candidatas = <({Elemento e, double puntos})>[
      for (final Elemento e in biblioteca)
        if (e.audio && e.uri != semilla.uri)
          (
            e: e,
            puntos: (artista.isNotEmpty && _clave(e.partes.artista) == artista ? 3 : 0) +
                (favoritas.contains(e.uri) ? 2 : 0) +
                2 * (escuchas[e.uri] ?? 0) / masOida +
                // El azar pesa como el corazon: mueve el orden, no lo decide.
                suerte.nextDouble() * 2,
          ),
    ]..sort((a, b) => b.puntos.compareTo(a.puntos));
    return <Elemento>[
      semilla,
      ...candidatas.take(largo - 1).map((({Elemento e, double puntos}) c) => c.e),
    ];
  }

  /// Pone a sonar la radio de [semilla].
  static Future<void> poner(Elemento semilla, List<Elemento> biblioteca) async {
    Map<String, int> escuchas = const <String, int>{};
    try {
      escuchas = <String, int>{
        for (final ({String uri, int veces}) f in await Catalogo.instancia.masEscuchadas(limite: 500))
          f.uri: f.veces,
      };
    } catch (_) {
      // Sin escuchas la radio sale igual, solo que con menos criterio.
    }
    await Favoritas.instancia.cargar();
    final Set<String> favoritas = <String>{
      for (final Elemento e in biblioteca)
        if (Favoritas.instancia.contiene(e.uri)) e.uri,
    };
    await EstadoReproductor.instancia.reproducirLista(
      mezcla(semilla, biblioteca, favoritas: favoritas, escuchas: escuchas),
      0,
    );
  }

  static String _clave(String artista) => artista.trim().toLowerCase();
}
