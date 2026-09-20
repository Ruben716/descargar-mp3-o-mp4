import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'ecualizador.dart';
import 'tema.dart';

/// Ecualizador y refuerzo de volumen.
Future<void> abrirEcualizador(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tema.superficie,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext contexto) => const HojaEcualizador(),
  );
}

class HojaEcualizador extends StatefulWidget {
  const HojaEcualizador({super.key});

  @override
  State<HojaEcualizador> createState() => _HojaEcualizadorState();
}

class _HojaEcualizadorState extends State<HojaEcualizador> {
  final Ecualizador _ecualizador = Ecualizador.instancia;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: FutureBuilder<AndroidEqualizerParameters>(
        // Los parametros no llegan hasta que suena algo: el aparato no dice
        // cuantas bandas tiene mientras el reproductor esta parado.
        future: _ecualizador.parametros,
        builder: (
          BuildContext context,
          AsyncSnapshot<AndroidEqualizerParameters> datos,
        ) {
          if (!datos.hasData) return const _Esperando();
          return _Controles(
            parametros: datos.data!,
            ecualizador: _ecualizador,
            alCambiar: () => setState(() {}),
          );
        },
      ),
    );
  }
}

class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 180,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.graphic_eq_rounded, size: 40, color: Colors.white24),
          SizedBox(height: 14),
          Text(
            'Pon una cancion primero.',
            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'El ecualizador es del telefono, y hasta que\n'
            'no suena algo no dice con que bandas cuenta.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class _Controles extends StatelessWidget {
  const _Controles({
    required this.parametros,
    required this.ecualizador,
    required this.alCambiar,
  });

  final AndroidEqualizerParameters parametros;
  final Ecualizador ecualizador;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Ecualizador',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
                ),
              ),
              Switch(
                value: ecualizador.activo,
                onChanged: (bool encendido) async {
                  await ecualizador.activar(encendido);
                  alCambiar();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Ajuste ajuste in Ajuste.todos)
                ActionChip(
                  label: Text(ajuste.nombre),
                  backgroundColor: Tema.superficieAlta,
                  onPressed: () async {
                    await ecualizador.aplicar(ajuste);
                    alCambiar();
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 210,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final AndroidEqualizerBand banda in parametros.bands)
                  Expanded(
                    child: _Banda(
                      banda: banda,
                      minimo: parametros.minDecibels,
                      maximo: parametros.maxDecibels,
                      ecualizador: ecualizador,
                      alCambiar: alCambiar,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 32, color: Colors.white12),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Reforzar volumen',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                '+${ecualizador.refuerzo.round()} dB',
                style: TextStyle(
                  color: ecualizador.refuerzo > 0 ? Tema.acento : Colors.white38,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Slider(
            value: ecualizador.refuerzo.clamp(0, 12),
            max: 12,
            divisions: 12,
            onChanged: (double v) async {
              await ecualizador.reforzar(v);
              alCambiar();
            },
          ),
          const Text(
            'Sube el nivel de las grabaciones flojas para que no haya que '
            'tocar el volumen entre cancion y cancion.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Una banda, con su deslizador vertical y su frecuencia debajo.
class _Banda extends StatelessWidget {
  const _Banda({
    required this.banda,
    required this.minimo,
    required this.maximo,
    required this.ecualizador,
    required this.alCambiar,
  });

  final AndroidEqualizerBand banda;
  final double minimo;
  final double maximo;
  final Ecualizador ecualizador;
  final VoidCallback alCambiar;

  /// 1200 Hz se lee mejor como "1.2k".
  String get _frecuencia {
    final double hz = banda.centerFrequency;
    if (hz < 1000) return '${hz.round()}';
    final double miles = hz / 1000;
    return miles >= 10 ? '${miles.round()}k' : '${miles.toStringAsFixed(1)}k';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: banda.gainStream,
      builder: (BuildContext context, AsyncSnapshot<double> valor) {
        final double ganancia = (valor.data ?? banda.gain).clamp(minimo, maximo);
        return Column(
          children: <Widget>[
            Text(
              ganancia.round().toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: ganancia,
                  min: minimo,
                  max: maximo,
                  onChanged: (double v) async {
                    await ecualizador.ajustarBanda(banda, v);
                    alCambiar();
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _frecuencia,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        );
      },
    );
  }
}
