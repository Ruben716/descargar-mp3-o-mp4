import 'package:flutter/material.dart';

import 'animaciones.dart';

import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Una opcion del menu de la pista, para que cada pantalla ponga las suyas.
class AccionPista {
  const AccionPista({
    required this.icono,
    required this.texto,
    required this.alElegir,
    this.destacada = false,
  });

  final IconData icono;
  final String texto;
  final VoidCallback alElegir;
  final bool destacada;
}

/// Fila de una pista descargada.
///
/// La comparten la biblioteca y las listas: antes estaba metida dentro de la
/// biblioteca y no habia forma de reutilizarla.
class FilaPista extends StatelessWidget {
  const FilaPista({
    required this.elemento,
    required this.enCola,
    this.acciones = const <AccionPista>[],
    this.seleccionada,
    this.alSeleccionar,
    this.alPulsarLargo,
    super.key,
  });

  /// null fuera del modo seleccion; dentro, si esta marcada.
  final bool? seleccionada;

  /// Marcar o desmarcar, en el modo seleccion. Sustituye al toque normal.
  final VoidCallback? alSeleccionar;

  /// Mantener pulsada: entra en el modo seleccion con esta ya marcada.
  final VoidCallback? alPulsarLargo;

  final Elemento elemento;

  /// Al tocar una pista, las que se ven detras quedan en cola.
  final List<Elemento> enCola;

  final List<AccionPista> acciones;

  /// Lo que ocupa una fila con la letra de siempre: la portada (50), su
  /// relleno (16) y la separacion con la siguiente (8). La lista con indice
  /// lo necesita para saber donde empieza cada letra sin pintarla.
  static const double alto = 74;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final ({String artista, String tema}) partes = elemento.partes;
    return ListenableBuilder(
      // Tambien las favoritas: el corazon de la fila cambia al marcarla.
      listenable: Listenable.merge(<Listenable>[estado, Favoritas.instancia]),
      builder: (BuildContext context, _) {
        final bool activo = estado.esActual(elemento.uri);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Material(
            color: seleccionada ?? false
                ? Tema.acento.withValues(alpha: 0.22)
                : activo
                    ? Tema.acento.withValues(alpha: 0.14)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: seleccionada != null ? alSeleccionar : () => _abrir(context, estado),
              onLongPress: alPulsarLargo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  children: <Widget>[
                    Hero(
                      tag: elemento.uri,
                      child: PortadaLocal(elemento: elemento, lado: 50, radio: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            partes.tema,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: activo ? Tema.acento : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: <Widget>[
                              if (Favoritas.instancia.contiene(elemento.uri))
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.favorite_rounded, size: 12, color: Color(0xFFFF6B81)),
                                ),
                              Expanded(
                                child: Text(
                                  partes.artista.isEmpty
                                      ? formatoTiempo(elemento.duracion)
                                      : '${partes.artista}  ·  ${formatoTiempo(elemento.duracion)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (activo)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: BarrasSonando(sonando: estado.sonando),
                      ),
                    if (seleccionada case final bool marcada)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          transitionBuilder: (Widget hijo, Animation<double> a) =>
                              ScaleTransition(scale: a, child: hijo),
                          child: Icon(
                            marcada ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            key: ValueKey<bool>(marcada),
                            color: marcada ? Tema.acento : Colors.white38,
                          ),
                        ),
                      )
                    else
                      _Menu(elemento: elemento, acciones: acciones),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _abrir(BuildContext context, EstadoReproductor estado) {
    if (elemento.audio) {
      // Solo se encolan las canciones: un video a mitad cortaria la musica.
      final List<Elemento> canciones =
          enCola.where((Elemento e) => e.audio).toList();
      estado.reproducirLista(canciones, canciones.indexOf(elemento));
    }
    Navigator.of(context).push(
      // Una cancion ya la puso a sonar la lista; un video lo arranca el reproductor.
      MaterialPageRoute<void>(
        builder: (_) => Reproductor(elemento: elemento, arrancar: !elemento.audio),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.elemento, required this.acciones});

  final Elemento elemento;
  final List<AccionPista> acciones;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final List<AccionPista> todas = <AccionPista>[
      // Encolar solo se ofrece para musica: meter un video en la cola de audio
      // cortaria la escucha en seco.
      if (elemento.audio) ...<AccionPista>[
        AccionPista(
          icono: Icons.playlist_play_rounded,
          texto: 'Reproducir a continuacion',
          alElegir: () => estado.reproducirAContinuacion(elemento),
        ),
        AccionPista(
          icono: Icons.queue_music_rounded,
          texto: 'Anadir a la cola',
          alElegir: () => estado.anadirAlFinal(elemento),
        ),
      ],
      AccionPista(
        icono: Icons.share_rounded,
        texto: 'Compartir',
        alElegir: () => Nucleo.compartirArchivo(elemento.uri, audio: elemento.audio),
      ),
      ...acciones,
    ];
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
      color: Tema.superficieAlta,
      onSelected: (int i) => todas[i].alElegir(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        for (final (int i, AccionPista accion) in todas.indexed)
          PopupMenuItem<int>(
            value: i,
            child: ListTile(
              leading: Icon(
                accion.icono,
                color: accion.destacada ? Tema.acentoCalido : null,
              ),
              title: Text(accion.texto),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
