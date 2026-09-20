import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AplicacionDescargador());

/// Canal hacia Kotlin, que a su vez llama al nucleo Python del repositorio.
const MethodChannel _nucleo = MethodChannel('com.ruben.descargador/nucleo');

class AplicacionDescargador extends StatelessWidget {
  const AplicacionDescargador({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Descargador',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const PantallaDescarga(),
    );
  }
}

class PantallaDescarga extends StatefulWidget {
  const PantallaDescarga({super.key});

  @override
  State<PantallaDescarga> createState() => _PantallaDescargaState();
}

class _PantallaDescargaState extends State<PantallaDescarga> with WidgetsBindingObserver {
  final TextEditingController _url = TextEditingController(
    text: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
  );

  bool _soloAudio = false;
  int _calidad = 720;
  bool _ocupado = false;
  String _salida = 'Pega una URL y pulsa Descargar.';
  String _estado = '';
  double? _porcentaje;
  Timer? _reloj;

  static const Map<String, int> _calidades = <String, int>{
    'La mejor': 0,
    '1080p': 1080,
    '720p': 720,
    '480p': 480,
    '360p': 360,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recogerCompartido();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al compartir desde YouTube la app vuelve al frente con el enlace nuevo.
    if (estado == AppLifecycleState.resumed) _recogerCompartido();
  }

  Future<void> _recogerCompartido() async {
    final String? enlace = await _nucleo.invokeMethod<String>('urlCompartida');
    if (enlace == null || enlace.isEmpty || !mounted) return;
    setState(() => _url.text = enlace);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace recibido desde otra app')),
    );
  }

  Future<String> _invocar(String metodo, [Map<String, dynamic>? argumentos]) async {
    final String crudo = await _nucleo.invokeMethod(metodo, argumentos) ?? '{}';
    return crudo;
  }

  Future<void> _consultar(String metodo, [Map<String, dynamic>? argumentos]) async {
    setState(() {
      _ocupado = true;
      _salida = 'Ejecutando Python dentro del movil...';
    });
    String texto;
    try {
      final String crudo = await _invocar(metodo, argumentos);
      texto = const JsonEncoder.withIndent('  ').convert(jsonDecode(crudo));
    } catch (error) {
      texto = 'Error: $error';
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _salida = texto;
    });
  }

  Future<void> _descargar() async {
    setState(() {
      _ocupado = true;
      _porcentaje = null;
      _estado = 'Preparando FFmpeg...';
      _salida = '';
    });
    _vigilarProgreso();

    String texto;
    try {
      final Map<String, dynamic> datos = jsonDecode(await _invocar('descargar', <String, dynamic>{
        'url': _url.text,
        'soloAudio': _soloAudio,
        'calidad': _soloAudio ? 0 : _calidad,
        'formatoAudio': 'mp3',
      }));
      if (datos['ok'] == true) {
        final List<dynamic> archivos = datos['archivos'] as List<dynamic>;
        texto = 'Listo:\n\n${archivos.join('\n\n')}';
      } else {
        texto = 'Error: ${datos['error']}';
        // El registro del motor solo aparece cuando algo ha fallado; es lo
        // unico que explica por que, porque aqui no hay consola.
        final List<dynamic> registro = (datos['registro'] as List<dynamic>?) ?? <dynamic>[];
        if (registro.isNotEmpty) {
          texto += '\n\n--- registro del motor ---\n${registro.join('\n')}';
        }
      }
    } catch (error) {
      texto = 'Error: $error';
    }

    _reloj?.cancel();
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _estado = '';
      _porcentaje = null;
      _salida = texto;
    });
  }

  /// Python guarda el ultimo avance y aqui se consulta mientras dure.
  void _vigilarProgreso() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (Timer reloj) async {
      if (!_ocupado) {
        reloj.cancel();
        return;
      }
      try {
        final Map<String, dynamic> avance = jsonDecode(await _invocar('progreso'));
        if (!mounted) return;
        final double pct = (avance['porcentaje'] as num?)?.toDouble() ?? -1;
        final int velocidad = (avance['velocidad'] as num?)?.toInt() ?? 0;
        setState(() {
          _porcentaje = pct >= 0 ? pct / 100 : null;
          _estado = switch (avance['status']) {
            'downloading' => '${pct.toStringAsFixed(1)}%  ${_tamano(velocidad)}/s',
            'finished' => 'Uniendo con FFmpeg...',
            'preparando' => 'Preparando...',
            _ => 'Trabajando...',
          };
        });
      } catch (_) {
        // Una consulta perdida no es motivo para romper la descarga.
      }
    });
  }

  static String _tamano(int octetos) {
    if (octetos <= 0) return '--';
    const List<String> unidades = <String>['B', 'KB', 'MB', 'GB'];
    double valor = octetos.toDouble();
    int i = 0;
    while (valor >= 1024 && i < unidades.length - 1) {
      valor /= 1024;
      i++;
    }
    return '${valor.toStringAsFixed(1)} ${unidades[i]}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Descargador')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL del video',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Video MP4'), icon: Icon(Icons.movie)),
                ButtonSegment<bool>(value: true, label: Text('Audio MP3'), icon: Icon(Icons.music_note)),
              ],
              selected: <bool>{_soloAudio},
              onSelectionChanged: _ocupado
                  ? null
                  : (Set<bool> eleccion) => setState(() => _soloAudio = eleccion.first),
            ),
            if (!_soloAudio) ...<Widget>[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _calidad,
                decoration: const InputDecoration(
                  labelText: 'Calidad maxima',
                  border: OutlineInputBorder(),
                ),
                items: _calidades.entries
                    .map((MapEntry<String, int> e) =>
                        DropdownMenuItem<int>(value: e.value, child: Text(e.key)))
                    .toList(),
                onChanged: _ocupado ? null : (int? v) => setState(() => _calidad = v ?? 0),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _ocupado ? null : _descargar,
              icon: const Icon(Icons.download),
              label: const Text('Descargar'),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: _ocupado ? null : () => _consultar('diagnostico'),
                    child: const Text('Diagnostico'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _ocupado
                        ? null
                        : () => _consultar('informacion', <String, dynamic>{'url': _url.text}),
                    child: const Text('Ver info'),
                  ),
                ),
              ],
            ),
            if (_ocupado) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _porcentaje),
              const SizedBox(height: 6),
              Text(_estado, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _salida,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
