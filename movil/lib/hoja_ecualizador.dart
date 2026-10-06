import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'autoeq.dart';
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
                ChoiceChip(
                  label: Text(ajuste.nombre),
                  selected: ecualizador.ajuste == ajuste,
                  showCheckmark: false,
                  onSelected: (_) async {
                    await ecualizador.aplicar(ajuste);
                    alCambiar();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _TusAudifonos(ecualizador: ecualizador, alCambiar: alCambiar),
          const SizedBox(height: 14),
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


/// La correccion para los audifonos del usuario (AutoEQ).
class _TusAudifonos extends StatelessWidget {
  const _TusAudifonos({required this.ecualizador, required this.alCambiar});

  final Ecualizador ecualizador;
  final VoidCallback alCambiar;

  Future<void> _elegir(BuildContext context) async {
    final ModeloAudifonos? modelo = await showModalBottomSheet<ModeloAudifonos>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const HojaAudifonos(),
    );
    if (modelo == null || !context.mounted) return;
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    try {
      final Correccion correccion = await AutoEq.correccion(modelo);
      await ecualizador.corregir(correccion);
      alCambiar();
      avisos.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Sonido corregido para ${modelo.nombre}'),
      ));
    } catch (error) {
      avisos.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Correccion? puesta = ecualizador.correccion;
    return DecoratedBox(
      decoration: BoxDecoration(color: Tema.superficieAlta, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(Icons.headphones_rounded, color: puesta == null ? Colors.white54 : Tema.acento),
        title: Text(
          puesta == null ? 'Corregir para tus audifonos' : puesta.nombre,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          puesta == null
              ? 'AutoEQ: mas de 8800 modelos medidos. Elige el tuyo y suena como deberia.'
              : 'Correccion AutoEQ puesta. El ajuste elegido se suma encima.',
          style: const TextStyle(fontSize: 11.5, height: 1.35),
        ),
        trailing: puesta == null
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(
                tooltip: 'Quitar correccion',
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  await ecualizador.corregir(null);
                  alCambiar();
                },
              ),
        onTap: () => _elegir(context),
      ),
    );
  }
}

/// Buscar el modelo de audifonos en el catalogo de AutoEQ.
class HojaAudifonos extends StatefulWidget {
  const HojaAudifonos({super.key});

  @override
  State<HojaAudifonos> createState() => _HojaAudifonosState();
}

class _HojaAudifonosState extends State<HojaAudifonos> {
  late final Future<List<ModeloAudifonos>> _indice = AutoEq.indice();
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Tus audifonos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Escribe la marca y el modelo: «galaxy buds», «airpods», «jbl tune»...',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (String v) => setState(() => _texto = v),
              decoration: const InputDecoration(
                hintText: 'Buscar modelo',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<ModeloAudifonos>>(
                future: _indice,
                builder: (BuildContext context, AsyncSnapshot<List<ModeloAudifonos>> estado) {
                  if (estado.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (estado.hasError) {
                    return Center(
                      child: Text('${estado.error}', style: const TextStyle(color: Colors.white54)),
                    );
                  }
                  final List<ModeloAudifonos> hallados = AutoEq.buscar(estado.data!, _texto);
                  if (_texto.trim().isEmpty) {
                    return Center(
                      child: Text(
                        '${estado.data!.length} mediciones disponibles',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    );
                  }
                  if (hallados.isEmpty) {
                    return const Center(
                      child: Text('No esta ese modelo.', style: TextStyle(color: Colors.white54)),
                    );
                  }
                  return ListView.builder(
                    itemCount: hallados.length,
                    itemBuilder: (BuildContext context, int i) => ListTile(
                      leading: const Icon(Icons.headphones_outlined),
                      title: Text(hallados[i].nombre),
                      subtitle: Text('Medido por ${hallados[i].fuente}', style: const TextStyle(fontSize: 11.5)),
                      onTap: () => Navigator.of(context).pop(hallados[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
