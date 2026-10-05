import 'package:flutter/material.dart';

import 'animaciones.dart';

import 'estado_reproductor.dart';
import 'gestos.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Barra fija con lo que esta sonando de la biblioteca.
///
/// Las vistas previas no aparecen aqui: viven en su propia pantalla y se paran
/// al salir de ella, que es lo que se espera de una previsualizacion.
class MiniReproductor extends StatelessWidget {
  const MiniReproductor({super.key});

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final Pista? actual = estado.actual;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: Movimiento.de(context, Movimiento.medio),
            transitionBuilder: (Widget hijo, Animation<double> a) => SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: hijo),
            ),
            child: actual?.elemento == null
                ? const SizedBox(width: double.infinity, key: ValueKey<String>('nada'))
                : _Barra(key: const ValueKey<String>('barra'), pista: actual!, estado: estado),
          ),
        );
      },
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.pista, required this.estado, super.key});

  final Pista pista;
  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: Tema.superficieAlta,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: pista.elemento!)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    // Portada y titulo se deslizan para cambiar de cancion; los
                    // botones se quedan quietos.
                    Expanded(
                      child: DeslizarParaCambiar(
                        alSiguiente: estado.haySiguiente ? estado.siguiente : null,
                        alAnterior: estado.hayAnterior ? estado.irALaAnterior : null,
                        child: Row(
                          children: <Widget>[
                            PortadaLocal(elemento: pista.elemento!, lado: 44, radio: 12),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                pista.elemento?.etiqueta ?? pista.titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Iconos justos y sin relleno: caben cuatro controles sin
                    // comerse el titulo.
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: estado.hayAnterior ? estado.anterior : null,
                      icon: const Icon(Icons.skip_previous_rounded, size: 22),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: estado.alternar,
                      icon: AnimatedSwitcher(
                        duration: Movimiento.de(context, Movimiento.corto),
                        transitionBuilder: (Widget hijo, Animation<double> a) =>
                            RotationTransition(
                              turns: Tween<double>(begin: 0.75, end: 1).animate(a),
                              child: ScaleTransition(scale: a, child: hijo),
                            ),
                        child: Icon(
                          estado.sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(estado.sonando),
                          size: 28,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: estado.haySiguiente ? estado.siguiente : null,
                      icon: const Icon(Icons.skip_next_rounded, size: 22),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: estado.cerrar,
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              StreamBuilder<Duration>(
                stream: estado.motor.positionStream,
                builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
                  final Duration total = estado.motor.duration ?? Duration.zero;
                  final double avance = total.inMilliseconds == 0
                      ? 0
                      : (instante.data ?? Duration.zero).inMilliseconds / total.inMilliseconds;
                  return LinearProgressIndicator(
                    value: avance.clamp(0, 1),
                    minHeight: 2.5,
                    backgroundColor: Colors.white12,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
