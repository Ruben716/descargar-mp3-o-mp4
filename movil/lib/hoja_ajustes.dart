import 'package:flutter/material.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Opciones avanzadas: las mismas que ofrece la version de consola, porque
/// salen del mismo DownloadOptions del dominio.
class HojaAjustes extends StatefulWidget {
  const HojaAjustes({required this.inicial, super.key});

  final Ajustes inicial;

  @override
  State<HojaAjustes> createState() => _HojaAjustesState();
}

class _HojaAjustesState extends State<HojaAjustes> {
  late Ajustes _a = widget.inicial;
  late final TextEditingController _subs = TextEditingController(text: _a.subtitulos);
  late final TextEditingController _fragmento = TextEditingController(text: _a.fragmento);

  static const Map<String, int> _calidades = <String, int>{
    'La mejor': 0,
    '1080p': 1080,
    '720p': 720,
    '480p': 480,
    '360p': 360,
  };

  @override
  void dispose() {
    _subs.dispose();
    _fragmento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Opciones', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              _a.soloAudio ? 'Descarga de musica' : 'Descarga de video',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            if (_a.soloAudio) ..._opcionesAudio() else ..._opcionesVideo(),
            const SizedBox(height: 14),
            _Etiqueta('Fragmento'),
            const SizedBox(height: 8),
            TextField(
              controller: _fragmento,
              decoration: const InputDecoration(hintText: '00:30-02:15, o vacio para entero'),
            ),
            const SizedBox(height: 24),
            BotonDegradado(
              texto: 'Aplicar',
              icono: Icons.check_rounded,
              alPulsar: () => Navigator.of(context).pop(
                _a.copiar(subtitulos: _subs.text.trim(), fragmento: _fragmento.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _opcionesAudio() => <Widget>[
        _Etiqueta('Formato'),
        const SizedBox(height: 8),
        _Fichas<String>(
          valores: const <String>['mp3', 'm4a', 'opus', 'flac', 'wav'],
          elegido: _a.formatoAudio,
          etiqueta: (String v) => v.toUpperCase(),
          alElegir: (String v) => setState(() => _a = _a.copiar(formatoAudio: v)),
        ),
        const SizedBox(height: 16),
        _Etiqueta('Calidad del audio'),
        const SizedBox(height: 8),
        _Fichas<String>(
          valores: const <String>['128', '192', '256', '320'],
          elegido: _a.bitrate,
          etiqueta: (String v) => '$v kb/s',
          alElegir: (String v) => setState(() => _a = _a.copiar(bitrate: v)),
        ),
        const SizedBox(height: 8),
        _igualarVolumen(),
      ];

  /// Igualar el volumen obliga a reconvertir, y hay formatos que se copian
  /// tal cual. En vez de dejar que falle la descarga, se dice aqui.
  Widget _igualarVolumen() {
    final bool admitido = !formatosSinNormalizar.contains(_a.formatoAudio);
    return SwitchListTile(
      value: _a.normalizar && admitido,
      onChanged: admitido
          ? (bool v) => setState(() => _a = _a.copiar(normalizar: v))
          : null,
      title: const Text('Igualar el volumen'),
      subtitle: Text(
        admitido
            ? 'Para que una cancion no reviente despues de otra'
            : 'Con ${_a.formatoAudio.toUpperCase()} no se puede: elige MP3, FLAC o WAV',
      ),
      contentPadding: EdgeInsets.zero,
      activeThumbColor: Tema.acento,
    );
  }

  List<Widget> _opcionesVideo() => <Widget>[
        _Etiqueta('Calidad maxima'),
        const SizedBox(height: 8),
        _Fichas<int>(
          valores: _calidades.values.toList(),
          elegido: _a.calidad,
          etiqueta: (int v) => _calidades.entries.firstWhere((e) => e.value == v).key,
          alElegir: (int v) => setState(() => _a = _a.copiar(calidad: v)),
        ),
        const SizedBox(height: 16),
        _Etiqueta('Subtitulos'),
        const SizedBox(height: 8),
        TextField(
          controller: _subs,
          decoration: const InputDecoration(hintText: 'es,en  ·  vacio para no descargarlos'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _a.sinPatrocinios,
          onChanged: (bool v) => setState(() => _a = _a.copiar(sinPatrocinios: v)),
          title: const Text('Quitar patrocinios'),
          subtitle: const Text('Recorta los segmentos marcados en SponsorBlock'),
          contentPadding: EdgeInsets.zero,
          activeThumbColor: Tema.acento,
        ),
      ];
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Colors.white54,
        ),
      );
}

/// Fila de fichas seleccionables; mas comoda que un desplegable en el movil.
class _Fichas<T> extends StatelessWidget {
  const _Fichas({
    required this.valores,
    required this.elegido,
    required this.etiqueta,
    required this.alElegir,
  });

  final List<T> valores;
  final T elegido;
  final String Function(T) etiqueta;
  final void Function(T) alElegir;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final T v in valores)
          ChoiceChip(
            label: Text(etiqueta(v)),
            selected: v == elegido,
            onSelected: (_) => alElegir(v),
            selectedColor: Tema.acento.withValues(alpha: 0.28),
            backgroundColor: Tema.superficieAlta,
          ),
      ],
    );
  }
}
