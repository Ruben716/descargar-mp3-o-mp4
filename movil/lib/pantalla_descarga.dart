import 'dart:async';

import 'package:flutter/material.dart';

import 'formato.dart';
import 'nucleo.dart';

/// Pantalla principal: buscar o pegar una URL, ajustar y descargar.
class PantallaDescarga extends StatefulWidget {
  const PantallaDescarga({required this.alDescargar, super.key});

  /// Avisa para que la biblioteca se refresque sin tener que recargarla a mano.
  final VoidCallback alDescargar;

  @override
  State<PantallaDescarga> createState() => PantallaDescargaState();
}

class PantallaDescargaState extends State<PantallaDescarga> with WidgetsBindingObserver {
  final TextEditingController _entrada = TextEditingController();

  bool _buscando = true;
  Ajustes _ajustes = const Ajustes(url: '');
  List<Resultado> _resultados = <Resultado>[];
  Resultado? _elegido;

  bool _ocupado = false;
  String _estado = '';
  double? _porcentaje;
  String _mensaje = '';
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recogerCompartido();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recogerCompartido();
  }

  /// Un enlace compartido desde YouTube llega con la app ya abierta.
  Future<void> _recogerCompartido() async {
    final String? enlace = await Nucleo.urlCompartida();
    if (enlace == null || enlace.isEmpty || !mounted) return;
    setState(() {
      _buscando = false;
      _entrada.text = enlace;
      _elegido = null;
      _resultados = <Resultado>[];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace recibido desde otra app')),
    );
  }

  Future<void> _buscar() async {
    final String texto = _entrada.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _ocupado = true;
      _mensaje = '';
      _resultados = <Resultado>[];
    });
    try {
      final List<Resultado> encontrados = await Nucleo.buscar(texto);
      if (!mounted) return;
      setState(() {
        _resultados = encontrados;
        _mensaje = encontrados.isEmpty ? 'Sin resultados.' : '';
      });
    } catch (error) {
      if (mounted) setState(() => _mensaje = 'Error: $error');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _descargar() async {
    final String url = _elegido?.url ?? _entrada.text.trim();
    if (url.isEmpty) {
      setState(() => _mensaje = 'Elige un resultado o pega una URL.');
      return;
    }
    setState(() {
      _ocupado = true;
      _porcentaje = null;
      _estado = 'Preparando...';
      _mensaje = '';
    });
    _vigilar();

    try {
      final List<String> archivos = await Nucleo.descargar(_ajustes.copiar(url: url));
      if (!mounted) return;
      setState(() => _mensaje = 'Guardado en:\n${archivos.join('\n')}');
      widget.alDescargar();
    } on ErrorNucleo catch (error) {
      if (!mounted) return;
      final String detalle = error.registro.isEmpty
          ? ''
          : '\n\n--- registro del motor ---\n${error.registro.join('\n')}';
      setState(() => _mensaje = 'Error: ${error.mensaje}$detalle');
    } catch (error) {
      if (mounted) setState(() => _mensaje = 'Error: $error');
    } finally {
      _reloj?.cancel();
      if (mounted) {
        setState(() {
          _ocupado = false;
          _estado = '';
          _porcentaje = null;
        });
      }
    }
  }

  /// Python publica el avance y aqui se consulta mientras dure la descarga.
  void _vigilar() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (Timer reloj) async {
      if (!_ocupado) {
        reloj.cancel();
        return;
      }
      try {
        final Avance avance = await Nucleo.progreso();
        if (!mounted) return;
        setState(() {
          _porcentaje = avance.porcentaje >= 0 ? avance.porcentaje / 100 : null;
          _estado = switch (avance.estado) {
            'downloading' =>
              '${avance.porcentaje.toStringAsFixed(1)}%  ${formatoTamano(avance.velocidad)}/s',
            'finished' => 'Uniendo con FFmpeg...',
            _ => 'Trabajando...',
          };
        });
      } catch (_) {
        // Una consulta perdida no debe romper la descarga en curso.
      }
    });
  }

  Future<void> _abrirAjustes() async {
    final Ajustes? nuevos = await showModalBottomSheet<Ajustes>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaAjustes(inicial: _ajustes),
    );
    if (nuevos != null) setState(() => _ajustes = nuevos);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('Buscar'), icon: Icon(Icons.search)),
              ButtonSegment<bool>(value: false, label: Text('URL'), icon: Icon(Icons.link)),
            ],
            selected: <bool>{_buscando},
            onSelectionChanged: _ocupado
                ? null
                : (Set<bool> e) => setState(() {
                      _buscando = e.first;
                      _elegido = null;
                      _resultados = <Resultado>[];
                    }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _entrada,
            textInputAction: _buscando ? TextInputAction.search : TextInputAction.done,
            onSubmitted: _ocupado ? null : (_) => _buscando ? _buscar() : _descargar(),
            decoration: InputDecoration(
              labelText: _buscando ? 'Que quieres buscar' : 'URL del video',
              border: const OutlineInputBorder(),
              suffixIcon: _buscando
                  ? IconButton(onPressed: _ocupado ? null : _buscar, icon: const Icon(Icons.search))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: false, label: Text('MP4')),
                    ButtonSegment<bool>(value: true, label: Text('MP3')),
                  ],
                  selected: <bool>{_ajustes.soloAudio},
                  onSelectionChanged: _ocupado
                      ? null
                      : (Set<bool> e) =>
                          setState(() => _ajustes = _ajustes.copiar(soloAudio: e.first)),
                ),
              ),
              IconButton(
                onPressed: _ocupado ? null : _abrirAjustes,
                icon: const Icon(Icons.tune),
                tooltip: 'Mas opciones',
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _ocupado ? null : _descargar,
            icon: const Icon(Icons.download),
            label: Text(_elegido == null ? 'Descargar' : 'Descargar lo elegido'),
          ),
          if (_ocupado) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _porcentaje),
            const SizedBox(height: 6),
            Text(_estado, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_mensaje.isNotEmpty) {
      return SingleChildScrollView(
        child: SelectableText(_mensaje, style: const TextStyle(fontSize: 12)),
      );
    }
    if (_resultados.isEmpty) {
      return Center(
        child: Text(
          _buscando
              ? 'Escribe el nombre de una cancion o video.'
              : 'Pega una URL, o compartela desde YouTube.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.separated(
      itemCount: _resultados.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final Resultado r = _resultados[i];
        final bool marcado = identical(r, _elegido);
        return ListTile(
          selected: marcado,
          leading: Icon(marcado ? Icons.check_circle : Icons.play_circle_outline),
          title: Text(r.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${r.autor}  ·  ${formatoTiempo(r.duracion)}'),
          onTap: () => setState(() => _elegido = marcado ? null : r),
        );
      },
    );
  }
}

/// Opciones avanzadas: las mismas que ofrece la version de consola.
class _HojaAjustes extends StatefulWidget {
  const _HojaAjustes({required this.inicial});

  final Ajustes inicial;

  @override
  State<_HojaAjustes> createState() => _HojaAjustesState();
}

class _HojaAjustesState extends State<_HojaAjustes> {
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
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Opciones', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_a.soloAudio) ...<Widget>[
              DropdownButtonFormField<String>(
                initialValue: _a.formatoAudio,
                decoration: const InputDecoration(labelText: 'Formato', border: OutlineInputBorder()),
                items: const <String>['mp3', 'm4a', 'opus', 'flac', 'wav']
                    .map((String f) => DropdownMenuItem<String>(value: f, child: Text(f)))
                    .toList(),
                onChanged: (String? v) => setState(() => _a = _a.copiar(formatoAudio: v)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _a.bitrate,
                decoration: const InputDecoration(labelText: 'Calidad', border: OutlineInputBorder()),
                items: const <String>['128', '192', '256', '320']
                    .map((String b) => DropdownMenuItem<String>(value: b, child: Text('$b kb/s')))
                    .toList(),
                onChanged: (String? v) => setState(() => _a = _a.copiar(bitrate: v)),
              ),
            ] else ...<Widget>[
              DropdownButtonFormField<int>(
                initialValue: _a.calidad,
                decoration:
                    const InputDecoration(labelText: 'Calidad maxima', border: OutlineInputBorder()),
                items: _calidades.entries
                    .map((MapEntry<String, int> e) =>
                        DropdownMenuItem<int>(value: e.value, child: Text(e.key)))
                    .toList(),
                onChanged: (int? v) => setState(() => _a = _a.copiar(calidad: v)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subs,
                decoration: const InputDecoration(
                  labelText: 'Subtitulos (es,en) o vacio',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _a.sinPatrocinios,
                onChanged: (bool v) => setState(() => _a = _a.copiar(sinPatrocinios: v)),
                title: const Text('Quitar patrocinios'),
                subtitle: const Text('Elimina los segmentos con SponsorBlock'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _fragmento,
              decoration: const InputDecoration(
                labelText: 'Fragmento 00:30-02:15 o vacio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _a.copiar(subtitulos: _subs.text.trim(), fragmento: _fragmento.text.trim()),
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}
