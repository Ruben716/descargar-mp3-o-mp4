import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'entrada.dart';
import 'estado_reproductor.dart';
import 'listas.dart';
import 'navegacion.dart';
import 'nucleo.dart';
import 'pantalla_lista.dart';
import 'pantalla_radio.dart';
import 'radio_mundial.dart';
import 'secciones_inicio.dart';
import 'suscripciones.dart';
import 'tema.dart';

/// A donde lleva una ficha de Explorar.
///
/// Una de tres: la radio con un atajo ya elegido, Descargar con una fuente (y
/// un texto, si lo hay), o una hoja con varias de esas para elegir.
@immutable
class DestinoExplorar {
  const DestinoExplorar(
    this.titulo,
    this.icono,
    this.color, {
    this.radio,
    this.fuente,
    this.texto = '',
    this.subtitulo = '',
    this.opciones = const <DestinoExplorar>[],
  });

  final String titulo;
  final IconData icono;
  final Color color;

  /// El atajo de la radio con que se abre (el nombre de un FiltroRadio).
  final String? radio;

  /// La fuente con que se busca en Descargar.
  final Fuente? fuente;

  /// Lo que se busca alli. Vacio: solo se elige la fuente.
  final String texto;

  /// Una linea de que esperar, en las hojas y en los estantes.
  final String subtitulo;

  /// Si no lleva a un sitio sino a elegir entre varios.
  final List<DestinoExplorar> opciones;
}

/// Las vias de verdad para tener algo sin perdida, sin cuenta.
const List<DestinoExplorar> rutasSinPerdida = <DestinoExplorar>[
  DestinoExplorar('Radios en FLAC', Icons.radio_rounded, Tema.oro,
      radio: 'Sin perdida', subtitulo: 'En directo y sin perdida, como Radio Paradise'),
  DestinoExplorar('Audius', Icons.graphic_eq_rounded, Tema.acento,
      fuente: Fuente.audius, subtitulo: 'A 320 y a veces el original sin perdida'),
  DestinoExplorar('Jamendo', Icons.library_music_rounded, Tema.acentoHielo,
      fuente: Fuente.jamendo, subtitulo: 'Musica libre en FLAC, si el artista la deja bajar'),
  DestinoExplorar('Archive', Icons.account_balance_rounded, Tema.azulProfundo,
      fuente: Fuente.archive, subtitulo: 'Conciertos y musica libre en FLAC, a veces de 24 bits'),
  DestinoExplorar('Commons', Icons.public_rounded, Tema.acento,
      fuente: Fuente.commons, subtitulo: 'Clasica y dominio publico, el archivo original'),
  DestinoExplorar('Bandcamp', Icons.storefront_rounded, Tema.acentoHielo,
      fuente: Fuente.bandcamp, subtitulo: 'Independientes; algunos regalan el FLAC'),
];

/// Musica que el artista deja bajar y compartir.
const List<DestinoExplorar> rutasMusicaLibre = <DestinoExplorar>[
  DestinoExplorar('Jamendo', Icons.library_music_rounded, Tema.acentoHielo,
      fuente: Fuente.jamendo, subtitulo: 'Musica libre en FLAC, si el artista la deja bajar'),
  DestinoExplorar('ccMixter', Icons.multitrack_audio_rounded, Tema.acento,
      fuente: Fuente.ccmixter, subtitulo: 'Remixes, a cappellas e instrumentales libres'),
  DestinoExplorar('Commons', Icons.public_rounded, Tema.azulProfundo,
      fuente: Fuente.commons, subtitulo: 'Clasica y dominio publico, el archivo original'),
  DestinoExplorar('Netlabels', Icons.album_rounded, Tema.acentoHielo,
      fuente: Fuente.archive, texto: 'netlabel', subtitulo: 'Sellos que publican gratis, en el Archive'),
];

/// La categoria «Sin perdida»: una hoja con sus vias. Tambien la abren
/// Inicio y el estado vacio de Descargar.
const DestinoExplorar categoriaSinPerdida = DestinoExplorar(
  'Sin perdida',
  Icons.graphic_eq_rounded,
  Tema.oro,
  subtitulo: 'Donde conseguirlo entero, sin cuenta',
  opciones: rutasSinPerdida,
);

/// Las categorias de arriba, en el orden en que se ensenian.
const List<DestinoExplorar> categoriasExplorar = <DestinoExplorar>[
  DestinoExplorar('Radio en vivo', Icons.radio_rounded, Tema.acento, radio: 'Populares'),
  DestinoExplorar('Podcasts', Icons.podcasts_rounded, Tema.azulProfundo, fuente: Fuente.podcasts),
  categoriaSinPerdida,
  DestinoExplorar('Musica libre', Icons.volunteer_activism_rounded, Tema.acentoHielo,
      subtitulo: 'Lo que el artista deja bajar y compartir', opciones: rutasMusicaLibre),
  DestinoExplorar('Sesiones de DJ', Icons.headphones_rounded, Tema.acentoHielo,
      fuente: Fuente.hearthis, texto: 'dj set'),
  DestinoExplorar('Conciertos', Icons.stadium_rounded, Tema.azulProfundo, fuente: Fuente.archive, texto: 'live'),
  DestinoExplorar('YouTube Music', Icons.music_video_rounded, Tema.acento, fuente: Fuente.ytmusic),
];

/// Los generos: emisoras en vivo de cada uno.
const List<DestinoExplorar> generosExplorar = <DestinoExplorar>[
  DestinoExplorar('Salsa', Icons.nightlife_rounded, Tema.acento, radio: 'Salsa'),
  DestinoExplorar('Reggaeton', Icons.speaker_rounded, Tema.azulProfundo, radio: 'Reggaeton'),
  DestinoExplorar('Rock', Icons.electric_bolt_rounded, Tema.acentoHielo, radio: 'Rock'),
  DestinoExplorar('Lofi', Icons.coffee_rounded, Tema.azulProfundo, radio: 'Lofi'),
  DestinoExplorar('Jazz', Icons.piano_rounded, Tema.acento, radio: 'Jazz'),
  DestinoExplorar('Clasica', Icons.queue_music_rounded, Tema.acentoHielo, radio: 'Clasica'),
];

/// Va a donde dice [destino].
///
/// Para buscar en Descargar se cierra todo lo que haya encima (Explorar, una
/// hoja...) y se pide la busqueda: el armazon cambia de pestania y Descargar
/// la atiende como lo compartido.
Future<void> irADestino(BuildContext context, DestinoExplorar destino) async {
  if (destino.opciones.isNotEmpty) {
    final DestinoExplorar? elegido = await elegirDestino(context, destino);
    if (elegido != null && context.mounted) await irADestino(context, elegido);
    return;
  }
  final String? radio = destino.radio;
  if (radio != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PantallaRadio(inicial: PantallaRadio.filtroDe(radio))),
    );
    return;
  }
  final Fuente? fuente = destino.fuente;
  if (fuente == null) return;
  Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  Navegacion.buscarEn(fuente, texto: destino.texto);
}

/// Hoja para elegir entre las [opciones] de una categoria.
Future<DestinoExplorar?> elegirDestino(BuildContext context, DestinoExplorar categoria) =>
    showModalBottomSheet<DestinoExplorar>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext contexto) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(categoria.titulo, style: Theme.of(contexto).textTheme.titleLarge),
              ),
              if (categoria.subtitulo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(categoria.subtitulo, style: const TextStyle(color: Tema.textoTenue)),
                ),
              for (final DestinoExplorar o in categoria.opciones)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(o.icono, color: o.color),
                  title: Text(o.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(o.subtitulo, style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                  onTap: () => Navigator.of(contexto).pop(o),
                ),
            ],
          ),
        ),
      ),
    );

/// Explorar: lo que no esta en el telefono y se puede oir o encontrar.
///
/// Se abre encima de Inicio o de Descargar, como la radio o los ajustes. Al
/// abrirse no pide nada a internet: cada ficha abre la radio con su atajo o
/// lleva a Descargar con la fuente elegida, y solo entonces se busca.
class PantallaExplorar extends StatefulWidget {
  const PantallaExplorar({super.key});

  @override
  State<PantallaExplorar> createState() => _PantallaExplorarState();
}

class _PantallaExplorarState extends State<PantallaExplorar> {
  final RadiosFavoritas _radios = RadiosFavoritas.instancia;
  final Suscripciones _suscripciones = Suscripciones.instancia;

  @override
  void initState() {
    super.initState();
    // De la memoria del telefono, no de la red.
    unawaited(_radios.cargar());
    unawaited(_suscripciones.cargar());
  }

  /// Un programa que se sigue: su lista, si ya cayo algo; si no, a buscarlo.
  Future<void> _abrirPrograma(Suscripcion s) async {
    if (Listas.instancia.contenido(s.titulo).isNotEmpty) {
      List<Elemento> biblioteca = <Elemento>[];
      try {
        biblioteca = await Nucleo.biblioteca();
      } catch (_) {
        // Sin biblioteca se abre igual: dira que esta vacia.
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PantallaLista(nombre: s.titulo, biblioteca: biblioteca)),
      );
      return;
    }
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    // Una lista de YouTube se abre tal cual; un podcast se busca por su nombre.
    if (Entrada.de(s.url).tipo == TipoEntrada.lista) {
      Nucleo.enlaceCompartido.value = s.url;
    } else {
      Navegacion.buscarEn(Fuente.podcasts, texto: s.titulo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Explorar')),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_radios, _suscripciones, EstadoReproductor.instancia]),
        builder: (BuildContext context, _) {
          final List<EstacionRadio> emisoras = _radios.todas;
          final List<Suscripcion> programas = _suscripciones.todas;
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: <Widget>[
              const PastillaPidele(),
              const TituloEstante(texto: 'Categorias'),
              _Rejilla(destinos: categoriasExplorar),
              const SizedBox(height: 26),
              const TituloEstante(texto: 'Generos en vivo'),
              _Rejilla(destinos: generosExplorar, alto: 72),
              const SizedBox(height: 26),
              if (emisoras.isNotEmpty)
                Estante(
                  titulo: 'Tus emisoras',
                  alto: TarjetaEmisora.alto,
                  cuantos: emisoras.length,
                  alVerTodo: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PantallaRadio(inicial: PantallaRadio.filtroDe('Favoritas')),
                    ),
                  ),
                  construir: (BuildContext context, int i) => TarjetaEmisora(emisora: emisoras[i]),
                ),
              if (programas.isNotEmpty)
                Estante(
                  titulo: 'Tus programas',
                  cuantos: programas.length,
                  construir: (BuildContext context, int i) => TarjetaEstante(
                    portada: const CuadroIcono(icono: Icons.podcasts_rounded, lado: 130),
                    titulo: programas[i].titulo,
                    subtitulo: 'Lo nuevo se baja solo',
                    alPulsar: () => _abrirPrograma(programas[i]),
                  ),
                ),
              Estante(
                titulo: 'Musica libre',
                alto: 164,
                cuantos: rutasMusicaLibre.length,
                construir: (BuildContext context, int i) => _TarjetaRuta(destino: rutasMusicaLibre[i]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Rejilla de categorias de colores, de dos en dos.
class _Rejilla extends StatelessWidget {
  const _Rejilla({required this.destinos, this.alto = 92});

  final List<DestinoExplorar> destinos;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < destinos.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                children: <Widget>[
                  Expanded(child: _FichaCategoria(destino: destinos[i], alto: alto)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < destinos.length
                        ? _FichaCategoria(destino: destinos[i + 1], alto: alto)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Una categoria: su color arriba a la izquierda y su icono ladeado abajo.
class _FichaCategoria extends StatelessWidget {
  const _FichaCategoria({required this.destino, required this.alto});

  final DestinoExplorar destino;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tema.superficieAlta,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => irADestino(context, destino),
        child: Ink(
          height: alto,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[destino.color.withValues(alpha: 0.38), Tema.superficieAlta],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -6,
                bottom: -8,
                child: Transform.rotate(
                  angle: pi / 9,
                  child: Icon(destino.icono, size: alto * 0.62, color: destino.color.withValues(alpha: 0.9)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 40, 10),
                child: Text(
                  destino.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Tema.texto),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una via del estante «Musica libre»: su icono, su nombre y que esperar.
class _TarjetaRuta extends StatelessWidget {
  const _TarjetaRuta({required this.destino});

  final DestinoExplorar destino;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TarjetaEstante(
        ancho: 136,
        portada: Container(
          width: 136,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[destino.color.withValues(alpha: 0.45), Tema.superficieAlta],
            ),
          ),
          child: Icon(destino.icono, size: 44, color: destino.color),
        ),
        titulo: destino.titulo,
        subtitulo: destino.subtitulo,
        alPulsar: () => irADestino(context, destino),
      ),
    );
  }
}
