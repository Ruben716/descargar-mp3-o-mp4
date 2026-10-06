import 'dart:async';

import 'package:flutter/material.dart';

import 'copia_seguridad.dart';
import 'dialogos.dart';
import 'hoja_ecualizador.dart';
import 'hoja_fundido.dart';
import 'nucleo.dart';
import 'suscripciones.dart';
import 'tema.dart';
import 'volumen_parejo.dart';

/// Todo lo que se configura una vez y se olvida: sonido, listas que se
/// siguen, copia de seguridad y la version de la app.
class PantallaAjustes extends StatefulWidget {
  const PantallaAjustes({super.key});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  final VolumenParejo _volumen = VolumenParejo.instancia;
  final Suscripciones _suscripciones = Suscripciones.instancia;

  late Future<DateTime?> _ultimaCopia = CopiaSeguridad.ultima();
  late Future<bool> _copiaAuto = CopiaSeguridad.automatica();
  late final Future<String> _version = Nucleo.versionApp();
  bool _copiando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_suscripciones.cargar());
  }

  Future<void> _hacerCopia() async {
    setState(() => _copiando = true);
    try {
      final String ruta = await CopiaSeguridad.guardar();
      if (mounted) avisar(context, 'Copia guardada en $ruta');
    } catch (error) {
      if (mounted) avisar(context, 'No se pudo hacer la copia: $error');
    } finally {
      if (mounted) {
        setState(() {
          _copiando = false;
          _ultimaCopia = CopiaSeguridad.ultima();
        });
      }
    }
  }

  Future<void> _restaurar() async {
    final String? texto;
    try {
      texto = await Nucleo.abrirCopia();
    } catch (error) {
      if (mounted) avisar(context, '$error');
      return;
    }
    if (texto == null || !mounted) return;
    setState(() => _copiando = true);
    try {
      final ResultadoRestauracion r = await CopiaSeguridad.restaurar(texto);
      if (!mounted) return;
      await _contarRestauracion(texto, r);
    } on FormatException catch (error) {
      if (mounted) avisar(context, error.message);
    } catch (error) {
      if (mounted) avisar(context, 'No se pudo restaurar: $error');
    } finally {
      if (mounted) setState(() => _copiando = false);
    }
  }

  Future<void> _contarRestauracion(String texto, ResultadoRestauracion r) async {
    final int recuperables = r.recuperables.length;
    final int sinEnlace = r.faltantes.length - recuperables;
    final bool bajar = await showDialog<bool>(
          context: context,
          builder: (BuildContext contexto) => AlertDialog(
            backgroundColor: Tema.superficieAlta,
            icon: const Icon(Icons.restore_rounded, color: Tema.acento, size: 32),
            title: const Text('Copia restaurada', textAlign: TextAlign.center),
            content: Text(
              <String>[
                '${r.encontradas} canciones encontradas en este telefono.',
                '${r.listas} listas recuperadas, con tus Me gusta, lo escuchado y tus ajustes.',
                if (recuperables > 0) 'Faltan $recuperables que se pueden volver a bajar.',
                if (sinEnlace > 0) '$sinEnlace no se pueden recuperar: no se sabe de donde se bajaron.',
              ].join('\n\n'),
              style: const TextStyle(height: 1.4),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(contexto).pop(false),
                child: Text(recuperables > 0 ? 'Ahora no' : 'Listo'),
              ),
              if (recuperables > 0)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Tema.acento, foregroundColor: Colors.black),
                  onPressed: () => Navigator.of(contexto).pop(true),
                  child: Text('Bajar $recuperables'),
                ),
            ],
          ),
        ) ??
        false;
    if (!bajar || !mounted) return;
    avisar(context, 'Bajando lo que faltaba. Puedes seguir usando la app.');
    await CopiaSeguridad.bajarFaltantes(texto, r.faltantes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const _Titulo('SONIDO'),
          ListenableBuilder(
            listenable: _volumen,
            builder: (BuildContext context, _) => Column(
              children: <Widget>[
                SwitchListTile(
                  value: _volumen.activo,
                  onChanged: _volumen.ponerActivo,
                  secondary: const Icon(Icons.equalizer_rounded),
                  title: const Text('Volumen parejo'),
                  subtitle: Text(
                    'Todas las canciones suenan igual de fuerte, vengan de donde vengan. '
                    '${_volumen.medidas} medidas'
                    '${_volumen.pendientes > 0 ? ' · midiendo ${_volumen.pendientes}...' : ''}',
                  ),
                ),
                if (_volumen.activo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _volumen.pendientes > 0
                            ? null
                            : () async {
                                final List<Elemento> todo = await Nucleo.biblioteca();
                                final int puestas = _volumen.medirTodas(<String>[
                                  for (final Elemento e in todo)
                                    if (e.audio) e.uri,
                                ]);
                                if (context.mounted) {
                                  avisar(
                                    context,
                                    puestas == 0
                                        ? 'Ya esta todo medido.'
                                        : 'Midiendo $puestas canciones en segundo plano.',
                                  );
                                }
                              },
                        icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                        label: const Text('Medir toda la biblioteca'),
                      ),
                    ),
                  ),
                SwitchListTile(
                  value: _volumen.saltarSilencios,
                  onChanged: _volumen.ponerSaltarSilencios,
                  secondary: const Icon(Icons.fast_forward_rounded),
                  title: const Text('Saltar silencios'),
                  subtitle: const Text('Quita los silencios largos del principio, el final y las pausas.'),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Ecualizador'),
            subtitle: const Text('15 ajustes y correccion para tus audifonos (AutoEQ).'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => abrirEcualizador(context),
          ),
          ListTile(
            leading: const Icon(Icons.blur_linear_rounded),
            title: const Text('Fundido entre canciones'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => abrirFundido(context),
          ),
          const _Titulo('LISTAS QUE SIGUES'),
          ListenableBuilder(listenable: _suscripciones, builder: (BuildContext context, _) => _listasQueSigues()),
          const _Titulo('COPIA DE SEGURIDAD'),
          _copiaDeSeguridad(),
          const _Titulo('ACERCA DE'),
          FutureBuilder<String>(
            future: _version,
            builder: (BuildContext context, AsyncSnapshot<String> v) => ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text('Tumbao ${v.data ?? ''}'.trim()),
              subtitle: const Text(
                'Proyecto academico. Musica y video para tenerlos en el telefono y '
                'escucharlos sin conexion.\n'
                'Correcciones de audifonos: AutoEQ (licencia MIT). Letras: LRCLIB.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listasQueSigues() {
    final List<Suscripcion> todas = _suscripciones.todas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Sigue una lista o un canal y lo que le agreguen se baja solo al abrir la app, '
            'y entra en la lista de Tumbao con el mismo nombre.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
          ),
        ),
        for (final Suscripcion s in todas)
          ListTile(
            leading: Icon(s.audio ? Icons.queue_music_rounded : Icons.video_library_rounded, color: Tema.acento),
            title: Text(s.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${s.audio ? 'Musica' : 'Video'} · ${s.conocidas.length} vistas'),
            trailing: IconButton(
              tooltip: 'Dejar de seguir',
              icon: const Icon(Icons.close_rounded),
              onPressed: () async {
                final bool si = await confirmar(
                  context,
                  titulo: 'Dejar de seguir',
                  mensaje: 'Ya no se bajara lo nuevo de «${s.titulo}». Lo que ya tienes se queda.',
                  accion: 'Dejar de seguir',
                );
                if (si) await _suscripciones.dejar(s.url);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => seguirLista(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Seguir una lista'),
              ),
              if (todas.isNotEmpty)
                TextButton.icon(
                  onPressed: _suscripciones.revisando ? null : () => _suscripciones.revisar(forzar: true),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(_suscripciones.revisando ? 'Mirando...' : 'Mirar ahora'),
                ),
            ],
          ),
        ),
        if (_suscripciones.ultimoAviso.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(_suscripciones.ultimoAviso, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        SwitchListTile(
          value: _suscripciones.soloWifi,
          onChanged: _suscripciones.ponerSoloWifi,
          title: const Text('Solo con wifi'),
          subtitle: const Text('Para no gastar tus datos moviles.'),
        ),
      ],
    );
  }

  Widget _copiaDeSeguridad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FutureBuilder<DateTime?>(
          future: _ultimaCopia,
          builder: (BuildContext context, AsyncSnapshot<DateTime?> f) => ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(f.data == null ? 'Aun no hay ninguna copia' : 'Ultima copia: ${_fecha(f.data!)}'),
            subtitle: const Text(
              'Guarda tus listas, Me gusta, lo escuchado, letras, ajustes y las listas que '
              'sigues en Descargas/Tumbao. Sobrevive aunque borres la app; para otro '
              'telefono, pasa ese archivo (por Drive, WhatsApp o cable).',
              style: TextStyle(height: 1.4),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Tema.acento, foregroundColor: Colors.black),
                onPressed: _copiando ? null : _hacerCopia,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text('Hacer copia ahora'),
              ),
              OutlinedButton.icon(
                onPressed: _copiando ? null : _restaurar,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restaurar'),
              ),
            ],
          ),
        ),
        FutureBuilder<bool>(
          future: _copiaAuto,
          builder: (BuildContext context, AsyncSnapshot<bool> a) => SwitchListTile(
            value: a.data ?? true,
            onChanged: (bool v) async {
              await CopiaSeguridad.ponerAutomatica(v);
              if (mounted) setState(() => _copiaAuto = CopiaSeguridad.automatica());
            },
            title: const Text('Copia automatica cada semana'),
          ),
        ),
      ],
    );
  }

  static String _fecha(DateTime d) {
    const List<String> meses = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final String hora = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${meses[d.month - 1]} ${d.year}, $hora';
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white54),
        ),
      );
}

/// Pregunta como seguir una lista y la sigue. Sin [url] la pide.
Future<void> seguirLista(BuildContext context, {String? url}) async {
  final TextEditingController enlace = TextEditingController(text: url ?? '');
  bool audio = true;
  bool loQueHay = false;
  final bool? seguir = await showDialog<bool>(
    context: context,
    builder: (BuildContext contexto) => StatefulBuilder(
      builder: (BuildContext contexto, StateSetter refrescar) => AlertDialog(
        backgroundColor: Tema.superficieAlta,
        title: const Text('Seguir una lista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (url == null)
              TextField(
                controller: enlace,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Enlace de la lista o del canal'),
              ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Musica'), icon: Icon(Icons.music_note_rounded)),
                ButtonSegment<bool>(value: false, label: Text('Video'), icon: Icon(Icons.movie_outlined)),
              ],
              selected: <bool>{audio},
              onSelectionChanged: (Set<bool> s) => refrescar(() => audio = s.first),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: loQueHay,
              onChanged: (bool? v) => refrescar(() => loQueHay = v ?? false),
              title: const Text('Bajar tambien lo que ya tiene'),
              subtitle: const Text('Si no, solo lo que agreguen desde hoy.'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Tema.acento, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Seguir'),
          ),
        ],
      ),
    ),
  );
  final String elegido = enlace.text.trim();
  enlace.dispose();
  if (seguir != true || elegido.isEmpty || !context.mounted) return;
  try {
    final Suscripcion s =
        await Suscripciones.instancia.seguir(elegido, audio: audio, bajarLoQueHay: loQueHay);
    if (context.mounted) {
      avisar(
        context,
        loQueHay ? 'Siguiendo «${s.titulo}». Bajando lo que tiene...' : 'Siguiendo «${s.titulo}».',
      );
    }
  } on ErrorNucleo catch (error) {
    if (context.mounted) avisar(context, error.mensaje);
  } catch (error) {
    if (context.mounted) avisar(context, '$error');
  }
}
