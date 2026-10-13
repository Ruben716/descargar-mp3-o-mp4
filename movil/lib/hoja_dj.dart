import 'dart:async';

import 'package:flutter/material.dart';

import 'dialogos.dart';
import 'dj.dart';
import 'estado_reproductor.dart';
import 'nucleo.dart';
import 'ritmos.dart';
import 'tema.dart';

/// El DJ automatico: cuanto lleva analizado, el corte al compas y una mezcla
/// de toda la biblioteca.
Future<void> abrirDj(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext contexto) => const HojaDj(),
  );
}

class HojaDj extends StatefulWidget {
  const HojaDj({super.key});

  @override
  State<HojaDj> createState() => _HojaDjState();
}

class _HojaDjState extends State<HojaDj> {
  List<Elemento>? _canciones;
  ModoDj _modo = ModoDj.flujo;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
  }

  Future<void> _cargar() async {
    try {
      final List<Elemento> todo = await Nucleo.biblioteca();
      if (mounted) setState(() => _canciones = <Elemento>[for (final Elemento e in todo) if (e.audio) e]);
    } catch (_) {
      if (mounted) setState(() => _canciones = const <Elemento>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final Ritmos ritmos = Ritmos.instancia;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[estado, ritmos]),
          builder: (BuildContext context, _) {
            final List<Elemento> canciones = _canciones ?? const <Elemento>[];
            final List<String> uris = <String>[for (final Elemento e in canciones) e.uri];
            final int faltan = ritmos.faltanDe(uris);
            final int hechas = uris.length - faltan;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('DJ automatico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Tumbao escucha cada cancion una vez (en el telefono, sin internet) para saber su '
                  'tempo y su energia. Con eso ordena la cola para que fluya y corta en el pulso.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (_canciones != null) ...<Widget>[
                  Text(
                    '$hechas de ${uris.length} canciones analizadas',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: uris.isEmpty ? 0 : hechas / uris.length,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (faltan > 0)
                    TextButton.icon(
                      onPressed: ritmos.trabajando
                          ? null
                          : () {
                              final int puestas = ritmos.analizarTodas(uris);
                              avisar(
                                context,
                                puestas == 0
                                    ? 'Todavia se esta preparando: prueba en un momento.'
                                    : 'Analizando $puestas canciones en segundo plano.',
                              );
                            },
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: Text(
                        ritmos.trabajando
                            ? 'Analizando, quedan ${ritmos.pendientes}...'
                            : 'Analizar la biblioteca ($faltan sin analizar)',
                      ),
                    ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: estado.alCompas,
                  onChanged: estado.ponerAlCompas,
                  title: const Text('Fundido al compas'),
                  subtitle: Text(
                    estado.fundido == Duration.zero
                        ? 'Corta en el pulso. Pon tambien un fundido para que la bajada vaya por compases.'
                        : 'Corta en el ultimo pulso y la siguiente entra con su primer golpe.',
                    style: const TextStyle(color: Tema.textoTenue, height: 1.3),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('MEZCLA DE TODA TU MUSICA', style: TextStyle(color: Tema.textoTenue, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final ModoDj modo in ModoDj.values)
                      ChoiceChip(
                        label: Text(modo.titulo),
                        selected: _modo == modo,
                        onSelected: (_) => setState(() => _modo = modo),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_modo.pista, style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canciones.length < 3
                        ? null
                        : () {
                            unawaited(estado.reproducirDj(canciones, modo: _modo));
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.queue_music_rounded),
                    label: const Text('Poner la mezcla'),
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
