import 'dart:async';

import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'descargas_inteligentes.dart';
import 'dialogos.dart';
import 'hecho_para_ti.dart';
import 'hoja_listas.dart';
import 'nucleo.dart';
import 'pidele.dart';
import 'tema.dart';

/// Las mezclas que se bajan solas: cuales hay, cuantas canciones, cada cuanto
/// se renuevan y como se llaman. Se anaden por genero o por artista.
class PantallaInteligentes extends StatefulWidget {
  const PantallaInteligentes({super.key});

  @override
  State<PantallaInteligentes> createState() => _PantallaInteligentesState();
}

class _PantallaInteligentesState extends State<PantallaInteligentes> {
  final DescargasInteligentes _d = DescargasInteligentes.instancia;

  @override
  void initState() {
    super.initState();
    unawaited(_d.cargar());
  }

  Future<void> _editar(MezclaInteligente m) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HojaMezcla(mezcla: m),
    );
  }

  Future<void> _nueva() async {
    final MezclaInteligente? m = await showModalBottomSheet<MezclaInteligente>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const HojaNuevaMezcla(),
    );
    if (m == null || !mounted) return;
    await _d.anadir(m);
    if (mounted) await _editar(m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Descargas inteligentes'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _d,
            builder: (BuildContext context, _) => IconButton(
              tooltip: 'Renovar ahora',
              onPressed: _d.trabajando || !_d.activas ? null : () => unawaited(_d.revisar(forzar: true)),
              icon: _d.trabajando
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nueva,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva mezcla'),
      ),
      body: ListenableBuilder(
        listenable: _d,
        builder: (BuildContext context, _) {
          final DateTime ahora = DateTime.now();
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  _d.aviso.isNotEmpty
                      ? _d.aviso
                      : 'Con wifi, cada mezcla se baja sola y se renueva cuando le toca. '
                          'Lo que no escuches se cambia por lo nuevo; lo que escuches, marques '
                          'o metas en una lista se queda.',
                  style: const TextStyle(color: Tema.textoSecundario, fontSize: 13, height: 1.4),
                ),
              ),
              for (final MezclaInteligente m in _d.mezclas)
                _FilaMezcla(
                  mezcla: m,
                  bajadas: _d.deMezcla(m.id).length,
                  proxima: m.activa ? proximaRenovacion(m, ahora) : null,
                  alTocar: () => _editar(m),
                  alEncender: (bool v) => unawaited(_d.cambiar(m.copiar(activa: v))),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaMezcla extends StatelessWidget {
  const _FilaMezcla({
    required this.mezcla,
    required this.bajadas,
    required this.proxima,
    required this.alTocar,
    required this.alEncender,
  });

  final MezclaInteligente mezcla;
  final int bajadas;
  final String? proxima;
  final VoidCallback alTocar;
  final ValueChanged<bool> alEncender;

  IconData get _icono => switch (mezcla.tipo) {
        TipoMezcla.paraTi => Icons.auto_awesome_rounded,
        TipoMezcla.genero => Icons.album_rounded,
        TipoMezcla.artista => Icons.person_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: alTocar,
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      leading: CircleAvatar(
        backgroundColor: Tema.superficieAlta,
        foregroundColor: mezcla.activa ? Tema.acento : Tema.textoTenue,
        child: Icon(_icono),
      ),
      title: Text(mezcla.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        <String>[
          mezcla.origen,
          resumenDeMezcla(mezcla),
          if (bajadas > 0) '$bajadas en el telefono',
          ?proxima,
        ].join('  ·  '),
        maxLines: 3,
        style: const TextStyle(color: Tema.textoSecundario, fontSize: 12.5, height: 1.35),
      ),
      trailing: Switch(value: mezcla.activa, onChanged: alEncender),
    );
  }
}

/// Lo que se puede cambiar de una mezcla.
class HojaMezcla extends StatefulWidget {
  const HojaMezcla({required this.mezcla, super.key});

  final MezclaInteligente mezcla;

  @override
  State<HojaMezcla> createState() => _HojaMezclaState();
}

class _HojaMezclaState extends State<HojaMezcla> {
  final DescargasInteligentes _d = DescargasInteligentes.instancia;
  late final TextEditingController _nombre = TextEditingController(text: widget.mezcla.nombre);
  late MezclaInteligente _m = widget.mezcla;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _poner(MezclaInteligente nueva) async {
    setState(() => _m = nueva);
    await _d.cambiar(nueva);
  }

  Future<void> _renombrar() async {
    final String nombre = _nombre.text.trim();
    if (nombre.isEmpty || nombre == _m.nombre) return;
    await _poner(_m.copiar(nombre: nombre));
  }

  Future<void> _guardarComoLista() async {
    final String? nombre = await pedirNombreDeLista(context, inicial: _m.nombre.replaceFirst(DescargasInteligentes.lista, 'Mis descubrimientos'));
    if (nombre == null || !mounted) return;
    final int cuantas = await _d.guardarComoLista(_m.id, nombre);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(cuantas < 0
          ? 'Ya hay una lista con ese nombre.'
          : 'Guardada «${nombre.trim()}» con $cuantas ${cuantas == 1 ? 'cancion' : 'canciones'}: ya no cambian.'),
    ));
  }

  Future<void> _quitar() async {
    final bool si = await confirmar(
      context,
      titulo: 'Quitar «${_m.nombre}»',
      mensaje: 'Ya no se bajara. Lo que bajo y no has escuchado, marcado ni metido en una lista se borra '
          'del telefono; lo demas se queda.',
      accion: 'Quitar',
    );
    if (!si || !mounted) return;
    await _d.quitar(_m.id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(texto, style: Tema.antetitulo),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.edit_rounded)),
              onSubmitted: (_) => _renombrar(),
              onEditingComplete: _renombrar,
              onTapOutside: (_) => _renombrar(),
            ),
            const SizedBox(height: 6),
            Text(_m.origen, style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
            _titulo('CUANTAS CANCIONES'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int n in DescargasInteligentes.opcionesCantidad)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _m.cuantas == n,
                    onSelected: (_) => _poner(_m.copiar(cuantas: n)),
                  ),
              ],
            ),
            _titulo('SE RENUEVA'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int d in DescargasInteligentes.opcionesDias)
                  ChoiceChip(
                    label: Text(DescargasInteligentes.textoDias(d)),
                    selected: _m.dias == d,
                    onSelected: (_) => _poner(_m.copiar(dias: d)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _d.deMezcla(_m.id).isEmpty ? null : _guardarComoLista,
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Guardar como lista'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Copia lo que tiene ahora a una lista tuya: esas canciones ya no se borran al renovarse.',
              style: TextStyle(color: Tema.textoTenue, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _quitar,
              style: TextButton.styleFrom(foregroundColor: Tema.peligro),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Quitar mezcla'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elegir de donde sale una mezcla nueva: para ti, un genero o un artista.
class HojaNuevaMezcla extends StatefulWidget {
  const HojaNuevaMezcla({super.key});

  @override
  State<HojaNuevaMezcla> createState() => _HojaNuevaMezclaState();
}

class _HojaNuevaMezclaState extends State<HojaNuevaMezcla> {
  List<String> _artistas = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_cargarArtistas());
  }

  /// Los artistas de la biblioteca, del mas oido al menos.
  Future<void> _cargarArtistas() async {
    try {
      final List<Elemento> canciones = (await Nucleo.biblioteca()).where((Elemento e) => e.audio).toList();
      final Map<String, Escucha> escuchas = await Catalogo.instancia.escuchasConFecha();
      final List<String> nombres = <String>[
        for (final ({String artista, List<Elemento> pistas}) a in HechoParaTi.artistas(canciones, escuchas).take(24))
          a.artista,
      ];
      if (mounted) setState(() => _artistas = nombres);
    } catch (_) {
      // Sin biblioteca no hay artistas que ofrecer; quedan los generos.
    }
  }

  void _elegir(TipoMezcla tipo, {String clave = ''}) =>
      Navigator.of(context).pop(DescargasInteligentes.instancia.nueva(tipo, clave: clave));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Nueva mezcla', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Para ti'),
                subtitle: const Text('De tus artistas mas escuchados'),
                onTap: () => _elegir(TipoMezcla.paraTi),
              ),
              const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Text('POR GENERO', style: Tema.antetitulo)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Genero g in generosDistintos)
                    ActionChip(label: Text(g.titulo), onPressed: () => _elegir(TipoMezcla.genero, clave: g.nombre)),
                ],
              ),
              if (_artistas.isNotEmpty) ...<Widget>[
                const Padding(padding: EdgeInsets.only(top: 16, bottom: 8), child: Text('POR ARTISTA', style: Tema.antetitulo)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String a in _artistas)
                      ActionChip(label: Text(a), onPressed: () => _elegir(TipoMezcla.artista, clave: a)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
