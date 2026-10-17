import 'dart:async';

import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'descubre.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'pantalla_previa.dart';
import 'portadas.dart';
import 'tema.dart';

/// La lista de «Descubre»: se escucha cada una en vista previa y se baja lo
/// que guste.
///
/// Las descargas van en cola: se pueden pedir varias seguidas aunque la de
/// antes no haya acabado, y cada fila dice como va la suya.
class PantallaDescubre extends StatefulWidget {
  const PantallaDescubre({super.key});

  @override
  State<PantallaDescubre> createState() => _PantallaDescubreState();
}

class _PantallaDescubreState extends State<PantallaDescubre> {
  final Descubre _descubre = Descubre.instancia;
  final ControlDescarga _control = ControlDescarga.instancia;

  /// Los videos que ya estan en la biblioteca.
  Set<String> _tengo = <String>{};

  /// Pedidas y aun sin empezar.
  final List<String> _cola = <String>[];

  /// Las del lote que se esta bajando.
  final Set<String> _bajando = <String>{};

  @override
  void initState() {
    super.initState();
    _descubre.addListener(_refrescar);
    _control.addListener(_alCambiarDescarga);
    unawaited(_descubre.cargar());
    unawaited(_leerTengo());
  }

  @override
  void dispose() {
    _descubre.removeListener(_refrescar);
    _control.removeListener(_alCambiarDescarga);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  Future<void> _leerTengo() async {
    final Set<String> tengo = (await Catalogo.instancia.videos()).keys.toSet();
    if (mounted) setState(() => _tengo = tengo);
  }

  /// Si otra descarga ocupaba el motor, la cola arranca al quedar libre.
  void _alCambiarDescarga() {
    if (!_control.activa && _bajando.isEmpty) unawaited(_siguiente());
  }

  bool _laTengo(Resultado r) => _tengo.contains(Catalogo.identificador(r.url));

  void _pedir(Iterable<Resultado> que) {
    setState(() {
      for (final Resultado r in que) {
        if (!_laTengo(r) && !_cola.contains(r.url) && !_bajando.contains(r.url)) _cola.add(r.url);
      }
    });
    unawaited(_siguiente());
  }

  Future<void> _siguiente() async {
    if (_control.activa || _cola.isEmpty || !mounted) return;
    final List<String> lote = List<String>.of(_cola);
    setState(() {
      _cola.clear();
      _bajando.addAll(lote);
    });
    await _control.iniciarVarios(lote, con: _control.ajustes.copiar(soloAudio: true));
    _bajando.clear();
    await _leerTengo();
    await _siguiente();
  }

  void _oir(Resultado r) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PantallaPrevia(resultado: r)),
      );

  @override
  Widget build(BuildContext context) {
    final List<Resultado> pistas = _descubre.pistas;
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            tooltip: 'Renovar ahora',
            onPressed: _descubre.armando ? null : () => unawaited(_descubre.rehacer()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: pistas.isEmpty
          ? _vacia(context)
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: pistas.length + 1,
              itemBuilder: (BuildContext context, int i) => i == 0 ? _cabecera(context, pistas) : _fila(pistas[i - 1]),
            ),
    );
  }

  Widget _cabecera(BuildContext context, List<Resultado> pistas) {
    final List<String> artistas = _descubre.artistas;
    final DateTime? hecha = _descubre.hecha;
    final List<Resultado> faltan = pistas.where((Resultado r) => !_laTengo(r)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Descubre', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26)),
          const SizedBox(height: 6),
          Text(
            artistas.isEmpty
                ? 'Canciones que no tienes, parecidas a lo que mas oyes.'
                : 'Canciones que no tienes, parecidas a lo que oyes de ${Descubre.unir(artistas)}.',
            style: const TextStyle(color: Tema.textoSecundario, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              '${pistas.length} canciones',
              if (hecha != null) 'se renueva cada semana',
            ].join('  ·  '),
            style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: faltan.isEmpty ? null : () => _pedir(faltan),
            icon: const Icon(Icons.arrow_downward_rounded, size: 20),
            label: const Text('Bajar todas'),
          ),
        ],
      ),
    );
  }

  Widget _fila(Resultado r) {
    final ({String artista, String tema}) p = Descubre.partesDe(r);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      leading: PortadaRemota(url: Descubre.portadaDe(r), ancho: 52, alto: 52),
      title: Text(p.tema, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        <String>[if (p.artista.isNotEmpty) p.artista, if (r.duracion > 0) formatoTiempo(r.duracion)].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Tema.textoSecundario),
      ),
      onTap: () => _oir(r),
      trailing: _estado(r),
    );
  }

  Widget _estado(Resultado r) {
    if (_laTengo(r)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.check_circle_rounded, color: Tema.exito, semanticLabel: 'Ya la tienes'),
      );
    }
    if (_bajando.contains(r.url)) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_cola.contains(r.url)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.schedule_rounded, color: Tema.textoTenue, semanticLabel: 'En cola'),
      );
    }
    return IconButton(
      tooltip: 'Bajar',
      onPressed: () => _pedir(<Resultado>[r]),
      icon: const Icon(Icons.arrow_downward_rounded),
    );
  }

  Widget _vacia(BuildContext context) {
    final bool armando = _descubre.armando;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_awesome_rounded, size: 40, color: Tema.acento),
            const SizedBox(height: 14),
            Text(
              armando ? 'Buscando canciones para ti...' : 'Aun no hay nada que descubrir',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              armando
                  ? 'Con la radio de tus artistas mas escuchados.'
                  : 'Sale de los artistas que mas oyes: con unas cuantas canciones en la biblioteca ya hay de donde tirar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tema.textoSecundario, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (armando)
              const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
            else
              FilledButton.icon(
                onPressed: () => unawaited(_descubre.rehacer()),
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('Buscar ahora'),
              ),
          ],
        ),
      ),
    );
  }
}
