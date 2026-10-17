import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                    if (pistas.length >= 3) ...<Widget>[
                      IconButton.filledTonal(
                        tooltip: 'Mezcla DJ',
                        onPressed: () => EstadoReproductor.instancia.reproducirDj(pistas),
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                      const SizedBox(width: 8),
                    ],
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

/// El boton del corazon. Al marcarlo da un saltito y suelta unas chispas.
///
/// Solo al marcar: quitar un Me gusta no es para celebrarlo, asi que solo
/// cambia el icono con un fundido.
class BotonMeGusta extends StatefulWidget {
  const BotonMeGusta({required this.uri, this.color, super.key});

  final String uri;
  final Color? color;

  @override
  State<BotonMeGusta> createState() => _BotonMeGustaState();
}

class _BotonMeGustaState extends State<BotonMeGusta> with SingleTickerProviderStateMixin {
  /// Empieza acabada (en 1): asi, en reposo, el corazon esta a su tamano y
  /// no hay chispas que pintar.
  late final AnimationController _estallido =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500), value: 1);

  /// 0,7 → 1,2 → 1 en los primeros 420 ms; el resto lo ocupan las chispas.
  late final Animation<double> _escala = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 0.7, end: 1.2).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1.2, end: 1).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(CurvedAnimation(parent: _estallido, curve: const Interval(0, 0.84)));

  @override
  void dispose() {
    _estallido.dispose();
    super.dispose();
  }

  void _alternar(bool marcada) {
    Favoritas.instancia.alternar(widget.uri);
    if (marcada) return;
    HapticFeedback.lightImpact();
    if (!Movimiento.reducido(context)) _estallido.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final Favoritas favoritas = Favoritas.instancia;
    return ListenableBuilder(
      listenable: favoritas,
      builder: (BuildContext context, _) {
        final bool marcada = favoritas.contiene(widget.uri);
        return IconButton(
          tooltip: marcada ? 'Quitar de Me gusta' : 'Me gusta',
          onPressed: () => _alternar(marcada),
          // Lo que se mueve va aparte: el estallido no repinta la fila entera.
          icon: RepaintBoundary(
            child: CustomPaint(
              painter: _Chispas(_estallido, Tema.meGusta),
              child: ScaleTransition(
                scale: _escala,
                child: AnimatedSwitcher(
                  duration: Movimiento.de(context, Movimiento.corto),
                  child: Icon(
                    marcada ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey<bool>(marcada),
                    color: marcada ? Tema.meGusta : widget.color,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ocho chispas en corro que se alejan del corazon y se apagan.
class _Chispas extends CustomPainter {
  _Chispas(this.avance, this.color) : super(repaint: avance);

  final Animation<double> avance;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = avance.value;
    if (t <= 0 || t >= 1) return;
    final double sale = Curves.easeOutCubic.transform(t);
    final Offset centro = size.center(Offset.zero);
    final Paint pincel = Paint();
    for (int i = 0; i < 8; i++) {
      // Desfasadas medio paso: ni en cruz ni en aspa, que se ve mas natural.
      final double angulo = (i + 0.5) * pi / 4;
      final double distancia = 8 + 14 * sale;
      final double radio = (i.isEven ? 2.2 : 1.6) * (1 - 0.6 * t);
      pincel.color = color.withValues(alpha: (1 - t) * (i.isEven ? 0.9 : 0.6));
      canvas.drawCircle(centro + Offset(cos(angulo), sin(angulo)) * distancia, radio, pincel);
    }
  }

  @override
  bool shouldRepaint(_Chispas antes) => antes.avance != avance || antes.color != color;
}
