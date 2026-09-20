import 'package:flutter/material.dart';

import 'formato.dart';
import 'nucleo.dart';
import 'reproductor.dart';

/// Lo descargado, leido de la biblioteca del telefono.
class PantallaBiblioteca extends StatefulWidget {
  const PantallaBiblioteca({super.key});

  @override
  State<PantallaBiblioteca> createState() => PantallaBibliotecaState();
}

class PantallaBibliotecaState extends State<PantallaBiblioteca> {
  List<Elemento> _elementos = <Elemento>[];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar() async {
    setState(() => _cargando = true);
    try {
      final List<Elemento> elementos = await Nucleo.biblioteca();
      if (!mounted) return;
      setState(() {
        _elementos = elementos;
        _error = null;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_elementos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aun no hay nada descargado.\nBaja algo desde la otra pestana.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: recargar,
      child: ListView.separated(
        itemCount: _elementos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int i) {
          final Elemento e = _elementos[i];
          return ListTile(
            leading: CircleAvatar(child: Icon(e.audio ? Icons.music_note : Icons.movie)),
            title: Text(e.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${formatoTiempo(e.duracion)}  ·  ${formatoTamano(e.tamano)}'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: e)),
            ),
          );
        },
      ),
    );
  }
}
