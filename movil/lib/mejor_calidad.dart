import 'dart:async';

import 'package:flutter/foundation.dart';

import 'calidad.dart';
import 'canales_oficiales.dart';
import 'catalogo.dart';
import 'control_descarga.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'listas.dart';
import 'nucleo.dart';

/// Otra version de la misma cancion, con mejor sonido.
@immutable
class Alternativa {
  const Alternativa({required this.resultado, required this.calidad, required this.fuente});

  final Resultado resultado;
  final CalidadAudio calidad;
  final Fuente fuente;
}

/// Buscar la misma cancion en mejor calidad en las fuentes que ya maneja la
/// app (Bandcamp, Audius, Archive, SoundCloud) y cambiarla sin perder nada.
///
/// La calidad que se compara es la del origen, la real: nunca se presenta como
/// mejor algo que solo es mas grande.
class MejorCalidad {
  MejorCalidad._();

  static const List<Fuente> fuentes = <Fuente>[Fuente.bandcamp, Fuente.audius, Fuente.archive, Fuente.soundcloud];

  /// Cuanto vale una calidad, para ordenar. Sin perdida va siempre por encima;
  /// entre las comprimidas, Opus y AAC rinden mas por kb/s que el MP3.
  static double puntos(CalidadAudio c) {
    if (c.sinPerdida) return 1000 + (c.bits ?? 16) * 10 + (c.hz ?? 44100) / 1000;
    const Map<String, double> eficiencia = <String, double>{'opus': 1.4, 'vorbis': 1.2, 'aac': 1.15, 'mp3': 1};
    return (c.kbps ?? 128) * (eficiencia[c.codec] ?? 1);
  }

  /// Si [nueva] suena de verdad mejor que [actual]: con un margen, para no
  /// ofrecer cambiar un Opus 127 por un AAC 160 que suena igual.
  static bool esMejor(CalidadAudio nueva, CalidadAudio actual) => puntos(nueva) > puntos(actual) * 1.2;

  /// Si un resultado es la misma cancion: lleva el nombre del tema y dura lo
  /// mismo (unos segundos arriba o abajo).
  static bool esLaMisma(Resultado r, Elemento e) {
    final ({String artista, String tema}) partes = e.partes;
    final String tema = CanalesOficiales.normalizar(partes.tema);
    if (tema.length < 2 || !CanalesOficiales.normalizar(r.titulo).contains(tema)) return false;
    if (e.duracion > 0 && r.duracion > 0 && (e.duracion - r.duracion).abs() > 8) return false;
    return true;
  }

  /// Las versiones mejores que la actual, de la mejor a la peor.
  static Future<List<Alternativa>> buscar(Elemento e, CalidadAudio actual) async {
    final ({String artista, String tema}) partes = e.partes;
    final String consulta = '${partes.artista} ${partes.tema}'.trim();
    final List<List<Alternativa>> porFuente = await Future.wait(<Future<List<Alternativa>>>[
      for (final Fuente f in fuentes) _enFuente(f, consulta, e, actual),
    ]);
    final List<Alternativa> todas = porFuente.expand((List<Alternativa> l) => l).toList()
      ..sort((Alternativa a, Alternativa b) => puntos(b.calidad).compareTo(puntos(a.calidad)));
    return todas;
  }

  static Future<List<Alternativa>> _enFuente(Fuente f, String consulta, Elemento e, CalidadAudio actual) async {
    final List<Resultado> hallados;
    try {
      hallados = await Nucleo.buscar(consulta, limite: 6, fuente: f.clave);
    } catch (_) {
      return const <Alternativa>[];
    }
    final List<Alternativa> buenas = <Alternativa>[];
    // Mirar la calidad cuesta una consulta por pista: solo las tres primeras.
    for (final Resultado r in hallados.where((Resultado r) => esLaMisma(r, e)).take(3)) {
      CalidadAudio? calidad = r.calidad;
      if (calidad == null) {
        try {
          calidad = await Nucleo.calidad(r.url);
        } catch (_) {
          continue;
        }
      }
      if (esMejor(calidad, actual)) buenas.add(Alternativa(resultado: r.deFuente(f), calidad: calidad, fuente: f));
    }
    return buenas;
  }

  /// Baja [alternativa] y la pone en lugar de [vieja] en listas, Me gusta,
  /// escuchas y letra. Devuelve el URI nuevo, o null si no se pudo bajar.
  ///
  /// La vieja no se borra aqui: lo decide el usuario despues.
  static Future<String?> cambiar(Elemento vieja, Alternativa alternativa) async {
    final ControlDescarga control = ControlDescarga.instancia;
    // Sin perdida se guarda en FLAC; lo comprimido se deja como viene, porque
    // pasarlo a MP3 le quitaria justo lo que se ha ido a buscar.
    final String formato = alternativa.calidad.sinPerdida ? 'flac' : 'best';
    await control.iniciarVarios(
      <String>[alternativa.resultado.url],
      con: control.ajustes.copiar(soloAudio: true, formatoAudio: formato),
    );
    if (control.fallo || control.ultimas.isEmpty) return null;
    final String nueva = control.ultimas.first;
    await heredar(vieja.uri, nueva);
    return nueva;
  }

  /// Todo lo que colgaba de la cancion vieja pasa a la nueva.
  static Future<void> heredar(String vieja, String nueva) async {
    await Catalogo.instancia.heredar(vieja, nueva);
    await Listas.instancia.cargar();
    await Listas.instancia.sustituir(vieja, nueva);
    await Favoritas.instancia.recargar();
  }

  /// Borra la version anterior una vez cambiada.
  static Future<void> borrarAnterior(String uri) async {
    await EstadoReproductor.instancia.olvidarSiEs(uri);
    await Nucleo.eliminar(uri);
    await Catalogo.instancia.olvidar(uri);
    await Listas.instancia.olvidar(uri);
    Favoritas.instancia.olvidar(uri);
  }
}
