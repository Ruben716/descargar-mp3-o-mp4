import 'dart:async';

import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'tema.dart';

/// Temporizador de apagado: para la musica sola al cabo de un rato.
Future<void> abrirTemporizador(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext contexto) => const HojaSuenio(),
  );
}

class HojaSuenio extends StatefulWidget {
  const HojaSuenio({super.key});

  @override
  State<HojaSuenio> createState() => _HojaSuenioState();
}

class _HojaSuenioState extends State<HojaSuenio> {
  static const List<int> _minutos = <int>[15, 30, 45, 60];

  final EstadoReproductor _estado = EstadoReproductor.instancia;
  Timer? _cuenta;

  @override
  void initState() {
    super.initState();
    // La cuenta atras no la avisa nadie: el estado solo guarda a que hora
    // toca parar, asi que es la pantalla la que se refresca cada segundo.
    _cuenta = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cuenta?.cancel();
    super.dispose();
  }

  String _reloj(Duration queda) {
    final int minutos = queda.inMinutes;
    final int segundos = queda.inSeconds % 60;
    return '$minutos:${segundos.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Duration? queda = _estado.restanteSuenio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Temporizador',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            queda == null
                ? 'La musica sigue hasta que la pares.'
                : 'Se apaga en ${_reloj(queda)}.',
            style: TextStyle(
              color: queda == null ? Colors.white54 : Tema.acento,
              fontSize: 13,
              fontWeight: queda == null ? FontWeight.normal : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final int m in _minutos)
                ActionChip(
                  label: Text('$m min'),
                  backgroundColor: Tema.superficieAlta,
                  onPressed: () {
                    _estado.dormirEn(Duration(minutes: m));
                    setState(() {});
                  },
                ),
              ActionChip(
                label: const Text('Al acabar esta'),
                backgroundColor: Tema.superficieAlta,
                onPressed: () {
                  _estado.dormirAlAcabarPista();
                  setState(() {});
                },
              ),
            ],
          ),
          if (queda != null) ...<Widget>[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _estado.cancelarSuenio();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Quitar el temporizador'),
            ),
          ],
        ],
      ),
    );
  }
}
