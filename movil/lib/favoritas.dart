import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'nucleo.dart';

/// Las canciones marcadas con el corazon, compartidas por toda la app.
///
/// Se guardan en el catalogo; aqui se tienen en memoria para que el corazon
/// se pinte al instante en cualquier fila y cambie a la vez en todas.
class Favoritas extends ChangeNotifier {
  Favoritas._();

  static final Favoritas instancia = Favoritas._();

  final Set<String> _uris = <String>{};
  bool _cargada = false;

  bool contiene(String uri) => _uris.contains(uri);

  Future<void> cargar() async {
    if (_cargada) return;
    _cargada = true;
    try {
      _uris.addAll(await Catalogo.instancia.favoritas());
      notifyListeners();
    } catch (_) {
      // Sin catalogo se empieza sin favoritas; marcar seguira funcionando.
    }
  }

  /// Marca o desmarca. Devuelve como queda.
  Future<bool> alternar(String uri) async {
    final bool ahora = !_uris.contains(uri);
    // Primero en pantalla y luego en disco: el corazon responde sin esperar.
    ahora ? _uris.add(uri) : _uris.remove(uri);
    notifyListeners();
    try {
      await Catalogo.instancia.marcarFavorita(uri, favorita: ahora);
    } catch (_) {
      // Si no se pudo guardar, al menos dura hasta cerrar la app.
    }
    return ahora;
  }

  /// Al borrar una descarga deja de ser favorita.
  void olvidar(String uri) {
    if (_uris.remove(uri)) notifyListeners();
  }

  @visibleForTesting
  void reiniciar() {
    _uris.clear();
    _cargada = false;
    notifyListeners();
  }
}

/// Listas que se hacen solas a partir de lo que se escucha y se marca.
enum ListaAuto {
  meGusta('Me gusta', Icons.favorite_rounded, Color(0xFFFF6B81)),
  recientes('Escuchadas hace poco', Icons.history_rounded, Color(0xFF57D9A3)),
  masEscuchadas('Lo mas escuchado', Icons.trending_up_rounded, Color(0xFFFFC857)),
  nuncaEscuchadas('Sin escuchar todavia', Icons.new_releases_outlined, Color(0xFF7FB3FF)),
  sinPerdida('Sin perdida', Icons.graphic_eq_rounded, Color(0xFFFFC857));

  const ListaAuto(this.titulo, this.icono, this.color);

  final String titulo;
  final IconData icono;
  final Color color;

  /// Lo que hay en ella ahora mismo, de entre las canciones de [biblioteca].
  Future<List<Elemento>> pistas(List<Elemento> biblioteca) async {
    final List<Elemento> canciones = biblioteca.where((Elemento e) => e.audio).toList();
    final Map<String, Elemento> porUri = <String, Elemento>{
      for (final Elemento e in canciones) e.uri: e,
    };
    List<Elemento> enOrden(Iterable<String> uris) =>
        <Elemento>[for (final String u in uris) ?porUri[u]];
    final Catalogo catalogo = Catalogo.instancia;
    return switch (this) {
      ListaAuto.meGusta => enOrden(await catalogo.favoritas()),
      ListaAuto.recientes => enOrden(await catalogo.recientes()),
      ListaAuto.masEscuchadas => enOrden(
          (await catalogo.masEscuchadas(limite: 50)).map((({String uri, int veces}) m) => m.uri),
        ),
      ListaAuto.nuncaEscuchadas => () async {
          final Set<String> oidas = await catalogo.escuchadas();
          return canciones.where((Elemento e) => !oidas.contains(e.uri)).toList();
        }(),
      ListaAuto.sinPerdida => enOrden(await catalogo.sinPerdida()),
    };
  }
}
