import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'tema.dart';

/// Elegir cuanto se funde una cancion con la siguiente.
Future<void> abrirFundido(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext contexto) => const HojaFundido(),
  );
}

class HojaFundido extends StatelessWidget {
  const HojaFundido({super.key});

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: ListenableBuilder(
          listenable: estado,
          builder: (BuildContext context, _) {
            final int elegido = estado.fundido.inSeconds;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Fundido entre canciones',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Al final de cada cancion el volumen baja poco a poco, y la '
                  'siguiente entra subiendo. Asi no hay cortes de golpe.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final int segundos in EstadoReproductor.segundosDeFundido)
                      ChoiceChip(
                        label: Text(segundos == 0 ? 'Apagado' : '$segundos s'),
                        selected: elegido == segundos,
                        onSelected: (_) =>
                            estado.ponerFundido(Duration(seconds: segundos)),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
