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
      home: const PantallaPrueba(),
    );
  }
}

class PantallaPrueba extends StatefulWidget {
  const PantallaPrueba({super.key});

  @override
  State<PantallaPrueba> createState() => _PantallaPruebaState();
}

class _PantallaPruebaState extends State<PantallaPrueba> {
  final TextEditingController _url = TextEditingController(
    text: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
  );
  String _salida = 'Sin resultados todavia.';
  bool _ocupado = false;

  Future<void> _llamar(String metodo, [Map<String, dynamic>? argumentos]) async {
    setState(() {
      _ocupado = true;
      _salida = 'Ejecutando Python dentro del movil...';
    });
    String texto;
    try {
      final String crudo = await _nucleo.invokeMethod(metodo, argumentos) ?? '{}';
      texto = const JsonEncoder.withIndent('  ').convert(jsonDecode(crudo));
    } on PlatformException catch (error) {
      texto = 'Error del canal: ${error.message}';
    } catch (error) {
      texto = 'Error: $error';
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _salida = texto;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Descargador - fase 0')),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _ocupado ? null : () => _llamar('diagnostico'),
                    child: const Text('Diagnostico'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _ocupado
                        ? null
                        : () => _llamar('informacion', <String, dynamic>{'url': _url.text}),
                    child: const Text('Consultar video'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_ocupado) const LinearProgressIndicator(),
            const SizedBox(height: 8),
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
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
