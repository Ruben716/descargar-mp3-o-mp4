import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Listas de reproduccion, guardadas en el propio movil.
///
/// Son una organizacion del usuario, no del catalogo: por eso viven aqui y no
/// en el nucleo, que solo sabe de descargas. Cada lista guarda los URI de
/// MediaStore de sus pistas.
class Listas extends ChangeNotifier {
  Listas._();

  static final Listas instancia = Listas._();

  static const String _clave = 'listas_v1';

  final Map<String, List<String>> _listas = <String, List<String>>{};
  bool _cargado = false;

  Map<String, List<String>> get todas => Map<String, List<String>>.unmodifiable(_listas);
  List<String> get nombres => _listas.keys.toList()..sort();

  Future<void> cargar() async {
    if (_cargado) return;
    _cargado = true;
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final String? crudo = memoria.getString(_clave);
      if (crudo != null && crudo.isNotEmpty) {
        final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
        _listas.clear();
        datos.forEach((String nombre, dynamic uris) {
          _listas[nombre] = (uris as List<dynamic>).map((dynamic u) => u.toString()).toList();
        });
      }
    } catch (_) {
      // Unos datos ilegibles no deben impedir usar la app; se empieza de cero.
    }
    notifyListeners();
  }

  Future<void> _guardar() async {
    notifyListeners();
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setString(_clave, jsonEncode(_listas));
    } catch (_) {
      // Sin persistencia la lista sigue viva en memoria hasta cerrar la app.
    }
  }

  List<String> contenido(String nombre) => List<String>.unmodifiable(_listas[nombre] ?? <String>[]);

  bool contiene(String nombre, String uri) => _listas[nombre]?.contains(uri) ?? false;

  /// Devuelve false si el nombre esta vacio o repetido.
  Future<bool> crear(String nombre) async {
    final String limpio = nombre.trim();
    if (limpio.isEmpty || _listas.containsKey(limpio)) return false;
    _listas[limpio] = <String>[];
    await _guardar();
    return true;
  }

  Future<void> borrar(String nombre) async {
    _listas.remove(nombre);
    await _guardar();
  }

  /// Anade sin quitar. alternar() no sirve al recrear una lista: si una pista
  /// apareciera dos veces, el segundo paso la borraria.
  Future<void> anadir(String nombre, String uri) async {
    final List<String> lista = _listas.putIfAbsent(nombre, () => <String>[]);
    if (lista.contains(uri)) return;
    lista.add(uri);
    await _guardar();
  }

  /// Vuelve al estado inicial. Es un objeto unico para toda la app y conviene
  /// poder empezar de cero; lo usan las pruebas.
  void reiniciar() {
    _listas.clear();
    _cargado = false;
    notifyListeners();
  }

  Future<void> alternar(String nombre, String uri) async {
    final List<String> lista = _listas.putIfAbsent(nombre, () => <String>[]);
    if (lista.contains(uri)) {
      lista.remove(uri);
    } else {
      lista.add(uri);
    }
    await _guardar();
  }

  /// Al borrar una descarga hay que sacarla de todas las listas.
  Future<void> olvidar(String uri) async {
    bool cambio = false;
    for (final List<String> lista in _listas.values) {
      if (lista.remove(uri)) cambio = true;
    }
    if (cambio) await _guardar();
  }
}
