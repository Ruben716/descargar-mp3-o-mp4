import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'nucleo.dart';
import 'ritmos.dart';
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
          listenable: Listenable.merge(<Listenable>[estado, Ritmos.instancia]),
          builder: (BuildContext context, _) {
            final int elegido = estado.fundido.inSeconds;
            final List<String> cola = <String>[for (final Elemento e in estado.cola) e.uri];
            final int faltan = Ritmos.instancia.faltanDe(cola);
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
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: estado.alCompas,
                  onChanged: estado.ponerAlCompas,
                  title: const Text('Al compas (modo DJ)'),
                  subtitle: const Text(
                    'Corta en el ultimo pulso y la siguiente entra con su primer '
                    'golpe. Necesita canciones analizadas.',
                    style: TextStyle(color: Tema.textoTenue, height: 1.3),
                  ),
                ),
                if (estado.alCompas && faltan > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: Ritmos.instancia.trabajando
                          ? null
                          : () => Ritmos.instancia.analizarTodas(cola, urgente: true),
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: Text(
                        Ritmos.instancia.trabajando
                            ? 'Analizando, quedan ${Ritmos.instancia.pendientes}'
                            : 'Analizar la cola ($faltan sin analizar)',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
