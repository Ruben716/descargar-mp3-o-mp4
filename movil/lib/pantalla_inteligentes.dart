import 'dart:async';

import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'descargas_inteligentes.dart';
import 'dialogos.dart';
import 'formato.dart';
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

  /// Lo que pesa cada archivo de la biblioteca, para decir cuanto ocupan.
  Map<String, int> _pesos = const <String, int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_d.cargar());
    unawaited(_leerPesos());
  }

  Future<void> _leerPesos() async {
    try {
      final Map<String, int> pesos = <String, int>{for (final Elemento e in await Nucleo.biblioteca()) e.uri: e.tamano};
      if (mounted) setState(() => _pesos = pesos);
    } catch (_) {
      // Sin biblioteca no se dice cuanto ocupan; lo demas sigue igual.
    }
  }

  Future<void> _viaje() async {
    final ({int horas, MezclaInteligente plantilla})? pedido =
        await showModalBottomSheet<({int horas, MezclaInteligente plantilla})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const HojaViaje(),
    );
    if (pedido == null || !mounted) return;
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    final ({String lista, int canciones}) r = await _d.modoViaje(horas: pedido.horas, plantilla: pedido.plantilla);
    if (!mounted) return;
    unawaited(_leerPesos());
    avisos.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(r.canciones == 0 ? _d.aviso : 'Listo: «${r.lista}» con ${r.canciones} canciones para el viaje.'),
    ));
  }

  Widget _ajustes() {
    final int ocupado = _d.ocupado(_pesos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 4), child: Text('AJUSTES', style: Tema.antetitulo)),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          value: _d.soloCargando,
          onChanged: (bool v) => unawaited(_d.ponerAjustes(soloCargando: v)),
          secondary: const Icon(Icons.battery_charging_full_rounded),
          title: const Text('Solo cargando'),
          subtitle: const Text('Bajan cuando el telefono esta enchufado y con wifi'),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          value: _d.mejorCalidad,
          onChanged: (bool v) => unawaited(_d.ponerAjustes(mejorCalidad: v)),
          secondary: const Icon(Icons.high_quality_rounded),
          title: const Text('Buscar mejor calidad'),
          subtitle: const Text('Despues de bajar, busca la misma sin perdida en otras fuentes libres y la cambia. Tarda mas'),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: const Icon(Icons.sd_storage_rounded),
          title: const Text('Limite de espacio'),
          subtitle: Text('Ahora ocupan ${formatoTamano(ocupado)}'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int mb in DescargasInteligentes.opcionesLimiteMb)
                ChoiceChip(
                  label: Text(DescargasInteligentes.textoLimite(mb)),
                  selected: _d.limiteMb == mb,
                  onSelected: (_) => unawaited(_d.ponerAjustes(limiteMb: mb)),
                ),
            ],
          ),
        ),
      ],
    );
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.flight_takeoff_rounded),
                    title: const Text('Modo viaje'),
                    subtitle: const Text('Baja de una vez unas horas de musica para ir sin senal'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _d.trabajando ? null : _viaje,
                  ),
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
              _ajustes(),
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
        TipoMezcla.animo => Icons.bolt_rounded,
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
              const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Text('POR ANIMO', style: Tema.antetitulo)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Animo a in animos)
                    ActionChip(label: Text(a.titulo), onPressed: () => _elegir(TipoMezcla.animo, clave: a.clave)),
                ],
              ),
              const Padding(padding: EdgeInsets.only(top: 16, bottom: 8), child: Text('POR GENERO', style: Tema.antetitulo)),
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

/// Pedir el modo viaje: cuantas horas y de que.
class HojaViaje extends StatefulWidget {
  const HojaViaje({super.key});

  @override
  State<HojaViaje> createState() => _HojaViajeState();
}

class _HojaViajeState extends State<HojaViaje> {
  int _horas = 2;
  MezclaInteligente _de = DescargasInteligentes.instancia.nueva(TipoMezcla.paraTi);
  bool? _conWifi;

  @override
  void initState() {
    super.initState();
    unawaited(Nucleo.redSinLimite().then((bool w) {
      if (mounted) setState(() => _conWifi = w);
    }));
  }

  void _elegir(TipoMezcla tipo, [String clave = '']) =>
      setState(() => _de = DescargasInteligentes.instancia.nueva(tipo, clave: clave));

  bool _es(TipoMezcla tipo, [String clave = '']) => _de.tipo == tipo && _de.clave == clave;

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
              Text('Modo viaje', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Se baja todo de una vez a una lista nueva que es tuya: no se renueva ni se borra.',
                style: TextStyle(color: Tema.textoSecundario, fontSize: 13),
              ),
              const Padding(padding: EdgeInsets.only(top: 16, bottom: 8), child: Text('CUANTO', style: Tema.antetitulo)),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final int h in DescargasInteligentes.opcionesHorasViaje)
                    ChoiceChip(
                      label: Text('$h ${h == 1 ? 'hora' : 'horas'}'),
                      selected: _horas == h,
                      onSelected: (_) => setState(() => _horas = h),
                    ),
                ],
              ),
              const Padding(padding: EdgeInsets.only(top: 16, bottom: 8), child: Text('DE QUE', style: Tema.antetitulo)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('Para ti'),
                    selected: _es(TipoMezcla.paraTi),
                    onSelected: (_) => _elegir(TipoMezcla.paraTi),
                  ),
                  for (final Animo a in animos)
                    ChoiceChip(
                      label: Text(a.titulo),
                      selected: _es(TipoMezcla.animo, a.clave),
                      onSelected: (_) => _elegir(TipoMezcla.animo, a.clave),
                    ),
                  for (final Genero g in generosDistintos)
                    ChoiceChip(
                      label: Text(g.titulo),
                      selected: _es(TipoMezcla.genero, g.nombre),
                      onSelected: (_) => _elegir(TipoMezcla.genero, g.nombre),
                    ),
                ],
              ),
              if (_conWifi == false)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'No estas con wifi: se usaran tus datos moviles.',
                    style: TextStyle(color: Tema.peligro, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop((horas: _horas, plantilla: _de)),
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Bajar $_horas ${_horas == 1 ? 'hora' : 'horas'} de musica'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
