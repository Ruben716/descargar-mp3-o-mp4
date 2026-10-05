import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Una lista que se hace sola (Me gusta, Lo mas escuchado...).
///
/// Va aparte de la pantalla de listas normales a proposito: esas se editan a
/// mano y estas no, asi que comparten poco mas que la forma.
class PantallaListaAuto extends StatefulWidget {
  const PantallaListaAuto({required this.lista, required this.biblioteca, super.key});

  final ListaAuto lista;
  final List<Elemento> biblioteca;

  @override
  State<PantallaListaAuto> createState() => _PantallaListaAutoState();
}

class _PantallaListaAutoState extends State<PantallaListaAuto> {
  late Future<List<Elemento>> _pistas = widget.lista.pistas(widget.biblioteca);

  @override
  void initState() {
    super.initState();
    // En «Me gusta», quitar un corazon la quita de la lista al momento.
    if (widget.lista == ListaAuto.meGusta) Favoritas.instancia.addListener(_recargar);
  }

  @override
  void dispose() {
    Favoritas.instancia.removeListener(_recargar);
    super.dispose();
  }

  void _recargar() {
    if (mounted) setState(() => _pistas = widget.lista.pistas(widget.biblioteca));
  }

  @override
  Widget build(BuildContext context) {
    final ListaAuto lista = widget.lista;
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: <Widget>[
            Icon(lista.icono, color: lista.color),
            const SizedBox(width: 10),
            Flexible(child: Text(lista.titulo, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: FutureBuilder<List<Elemento>>(
        future: _pistas,
        builder: (BuildContext context, AsyncSnapshot<List<Elemento>> datos) {
          if (!datos.hasData) return const Center(child: CircularProgressIndicator());
          final List<Elemento> pistas = datos.data!;
          if (pistas.isEmpty) return _vacia(lista);
          final int segundos = pistas.fold(0, (int s, Elemento e) => s + e.duracion.round());
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${pistas.length == 1 ? '1 cancion' : '${pistas.length} canciones'}  ·  ${formatoTiempo(segundos)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Aleatorio',
                      onPressed: () => EstadoReproductor.instancia.reproducirAleatorio(pistas),
                      icon: const Icon(Icons.shuffle_rounded),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => EstadoReproductor.instancia.reproducirEnOrden(pistas),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Reproducir'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: pistas.length,
                  itemBuilder: (BuildContext context, int i) => AparecerEscalonado(
                    indice: i,
                    child: FilaPista(elemento: pistas[i], enCola: pistas),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vacia(ListaAuto lista) {
    final String texto = switch (lista) {
      ListaAuto.meGusta => 'Toca el corazon en el reproductor\ny la cancion aparecera aqui.',
      ListaAuto.recientes => 'Aqui saldra lo que vayas escuchando.',
      ListaAuto.masEscuchadas => 'Cuando escuches un poco, aqui saldra\nlo que mas te gusta.',
      ListaAuto.nuncaEscuchadas => 'Ya has escuchado todas tus canciones.',
      ListaAuto.sinPerdida =>
        'Aun no tienes nada sin perdida.\nBusca en Audius o Bandcamp y bajalo en FLAC.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(lista.icono, size: 52, color: lista.color.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// El boton del corazon. Late al marcarlo.
class BotonMeGusta extends StatelessWidget {
  const BotonMeGusta({required this.uri, this.color, super.key});

  final String uri;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Favoritas favoritas = Favoritas.instancia;
    return ListenableBuilder(
      listenable: favoritas,
      builder: (BuildContext context, _) {
        final bool marcada = favoritas.contiene(uri);
        return IconButton(
          tooltip: marcada ? 'Quitar de Me gusta' : 'Me gusta',
          onPressed: () => favoritas.alternar(uri),
          icon: AnimatedSwitcher(
            duration: Movimiento.de(context, Movimiento.medio),
            transitionBuilder: (Widget hijo, Animation<double> a) => ScaleTransition(
              scale: TweenSequence<double>(<TweenSequenceItem<double>>[
                TweenSequenceItem<double>(tween: Tween<double>(begin: 0.4, end: 1.25), weight: 60),
                TweenSequenceItem<double>(tween: Tween<double>(begin: 1.25, end: 1), weight: 40),
              ]).animate(a),
              child: hijo,
            ),
            child: Icon(
              marcada ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey<bool>(marcada),
              color: marcada ? const Color(0xFFFF6B81) : color,
            ),
          ),
        );
      },
    );
  }
}
