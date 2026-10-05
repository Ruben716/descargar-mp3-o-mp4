import 'dart:async';

import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'formato.dart';
import 'navegacion.dart';
import 'nucleo.dart';

/// Lo que llega desde fuera de la app: los atajos del icono y los botones del
/// widget de la pantalla de inicio.
class Atajos {
  Atajos._();

  /// Atiende un atajo del icono.
  ///
  /// Lo que se pone a sonar se ve en el mini reproductor, que esta en todas
  /// las pestanias; se lleva a la Biblioteca para tener la musica a mano.
  static Future<void> atender(String atajo) async {
    final EstadoReproductor reproductor = EstadoReproductor.instancia;
    switch (atajo) {
      case 'descargar':
        Navegacion.irA(Navegacion.descargar);
      case 'continuar':
        Navegacion.irA(Navegacion.biblioteca);
        // Sin nada que retomar (la primera vez), lo mas parecido es todo.
        if (!await reproductor.continuar()) await _todoAleatorio(reproductor);
      case 'aleatorio':
        Navegacion.irA(Navegacion.biblioteca);
        await _todoAleatorio(reproductor);
      case 'me_gusta':
        Navegacion.irA(Navegacion.biblioteca);
        final List<Elemento> gustan = await ListaAuto.meGusta.pistas(await Nucleo.biblioteca());
        if (gustan.isEmpty) {
          Navegacion.avisar('Aun no tienes canciones en Me gusta. Marca alguna con el corazon.');
        } else {
          unawaited(reproductor.reproducirEnOrden(gustan));
        }
    }
  }

  static Future<void> _todoAleatorio(EstadoReproductor reproductor) async {
    final List<Elemento> canciones =
        (await Nucleo.biblioteca()).where((Elemento e) => e.audio).toList();
    if (canciones.isEmpty) {
      Navegacion.avisar('Todavia no tienes canciones. Descarga alguna y vuelve.');
      return;
    }
    // Sin esperar a que suene: play() no termina hasta que la musica para.
    unawaited(reproductor.reproducirAleatorio(canciones));
  }

  /// Un boton del widget.
  static Future<void> pulsarWidget(String accion) async {
    final EstadoReproductor reproductor = EstadoReproductor.instancia;
    switch (accion) {
      case 'anterior':
        await reproductor.anterior();
      case 'alternar':
        // Sin esperar: al reanudar, play() no vuelve hasta la pausa.
        unawaited(reproductor.alternar());
      case 'siguiente':
        await reproductor.siguiente();
    }
  }
}

/// Lo que el widget tiene que ensenar, sacado del reproductor.
@immutable
class ContenidoWidget {
  const ContenidoWidget({this.titulo, this.artista = '', this.sonando = false, this.uri});

  factory ContenidoWidget.de(EstadoReproductor estado) {
    final Pista? pista = estado.actual;
    if (pista == null) return const ContenidoWidget();
    final Elemento? elemento = pista.elemento;
    if (elemento == null) {
      return ContenidoWidget(titulo: nombreLimpio(pista.titulo), sonando: estado.sonando);
    }
    final ({String artista, String tema}) partes = elemento.partes;
    return ContenidoWidget(
      titulo: partes.tema,
      artista: partes.artista,
      sonando: estado.sonando,
      uri: elemento.uri,
    );
  }

  /// Sin titulo, no hay nada puesto.
  final String? titulo;
  final String artista;
  final bool sonando;

  /// La cancion, para sacar su caratula. Nula si no es de la biblioteca.
  final String? uri;

  @override
  bool operator ==(Object other) =>
      other is ContenidoWidget &&
      other.titulo == titulo &&
      other.artista == artista &&
      other.sonando == sonando &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(titulo, artista, sonando, uri);
}

/// Mantiene el widget de la pantalla de inicio al dia con lo que suena.
///
/// El reproductor avisa por muchas cosas (cargando, posicion del buffer...);
/// al widget solo se le manda algo cuando cambia lo que ensenia.
class SincroWidget {
  SincroWidget._();

  static ContenidoWidget? _enviado;

  /// Empieza a seguir al reproductor. Devuelve como dejar de seguirlo.
  static VoidCallback empezar([EstadoReproductor? estado]) {
    final EstadoReproductor reproductor = estado ?? EstadoReproductor.instancia;
    void alCambiar() => unawaited(_enviar(reproductor));
    reproductor.addListener(alCambiar);
    alCambiar();
    return () => reproductor.removeListener(alCambiar);
  }

  static Future<void> _enviar(EstadoReproductor reproductor) async {
    final ContenidoWidget ahora = ContenidoWidget.de(reproductor);
    if (ahora == _enviado) return;
    _enviado = ahora;
    String? caratula;
    final String? uri = ahora.uri;
    if (uri != null) {
      try {
        caratula = (await Nucleo.caratulaArchivo(uri))?.toFilePath();
      } catch (_) {
        // Sin caratula el widget pone el icono de la app.
      }
      // Mientras se buscaba la caratula ya cambio otra vez: manda el nuevo.
      if (_enviado != ahora) return;
    }
    await Nucleo.actualizarWidget(
      titulo: ahora.titulo,
      artista: ahora.artista,
      sonando: ahora.sonando,
      caratula: caratula,
    );
  }

  @visibleForTesting
  static void reiniciar() => _enviado = null;
}
