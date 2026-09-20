import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Barra fija con lo que esta sonando, sea de la biblioteca o una vista previa.
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
          child: actual == null
              ? const SizedBox(width: double.infinity)
              : _Barra(pista: actual, estado: estado),
        );
      },
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.pista, required this.estado});

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
          // Una vista previa no tiene pantalla propia: todavia no es un archivo.
          onTap: pista.elemento == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Reproductor(elemento: pista.elemento!),
                    ),
                  ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    if (pista.elemento != null)
                      PortadaLocal(elemento: pista.elemento!, lado: 44, radio: 12)
                    else
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: Tema.degradado,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.graphic_eq_rounded, color: Colors.black54),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            pista.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          if (pista.esPrevia)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text(
                                'VISTA PREVIA · NO DESCARGADO',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w800,
                                  color: Tema.acentoCalido,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (estado.preparando)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    else
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
                    value: estado.preparando ? null : avance.clamp(0, 1),
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
