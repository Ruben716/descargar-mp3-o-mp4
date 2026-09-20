import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Barra fija con lo que esta sonando. Aparece sola y se puede tocar para
/// abrir el reproductor completo.
class MiniReproductor extends StatelessWidget {
  const MiniReproductor({super.key});

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final Elemento? actual = estado.actual;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: actual == null
              ? const SizedBox(width: double.infinity)
              : _Barra(elemento: actual, estado: estado),
        );
      },
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.elemento, required this.estado});

  final Elemento elemento;
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
            MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: elemento)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    PortadaLocal(elemento: elemento, lado: 44, radio: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        elemento.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: estado.alternar,
                      icon: Icon(
                        estado.sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 30,
                      ),
                    ),
                    IconButton(
                      onPressed: estado.cerrar,
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white54),
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
