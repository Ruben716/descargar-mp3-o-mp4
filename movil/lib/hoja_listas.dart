import 'package:flutter/material.dart';

import 'dialogos.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Abre la hoja para meter una o varias canciones en una lista.
Future<void> elegirListaPara(BuildContext context, List<Elemento> elementos) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => HojaAnadirALista(elementos: elementos),
    );

/// Las listas, para meter en ellas lo elegido.
///
/// Con una sola cancion cada lista es una casilla: se marca o se desmarca.
/// Con varias, tocar una lista las mete todas de golpe, que era lo que
/// faltaba: antes habia que hacerlo cancion por cancion.
class HojaAnadirALista extends StatefulWidget {
  const HojaAnadirALista({required this.elementos, super.key});

  final List<Elemento> elementos;

  @override
  State<HojaAnadirALista> createState() => _HojaAnadirAListaState();
}

class _HojaAnadirAListaState extends State<HojaAnadirALista> {
  final Listas _listas = Listas.instancia;

  bool get _varias => widget.elementos.length > 1;

  List<String> get _uris => <String>[for (final Elemento e in widget.elementos) e.uri];

  Future<void> _meterEn(String nombre) async {
    final int nuevas = await _listas.anadirVarias(nombre, _uris);
    if (!mounted) return;
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    avisos.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(nuevas == 0
            ? 'Ya estaban todas en «$nombre»'
            : '$nuevas ${nuevas == 1 ? 'anadida' : 'anadidas'} a «$nombre»'),
      ),
    );
  }

  Future<void> _nueva() async {
    final String? nombre = await pedirNombreDeLista(context);
    if (nombre == null || !mounted) return;
    if (!await _listas.crear(nombre)) {
      if (mounted) avisar(context, 'Ya hay una lista con ese nombre.');
      return;
    }
    await _meterEn(nombre);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> nombres = _listas.nombres;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Anadir a lista', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              _varias
                  ? '${widget.elementos.length} canciones'
                  : widget.elementos.first.etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Tema.superficieAlta,
                child: Icon(Icons.add_rounded, color: Tema.acento),
              ),
              title: const Text('Nueva lista'),
              onTap: _nueva,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final String nombre in nombres)
                    if (_varias)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(nombre),
                        subtitle: Text(_cuantas(_listas.contenido(nombre).length)),
                        trailing: const Icon(Icons.playlist_add_rounded, color: Tema.acento),
                        onTap: () => _meterEn(nombre),
                      )
                    else
                      CheckboxListTile(
                        value: _listas.contiene(nombre, widget.elementos.first.uri),
                        onChanged: (_) async {
                          await _listas.alternar(nombre, widget.elementos.first.uri);
                          if (mounted) setState(() {});
                        },
                        title: Text(nombre),
                        activeColor: Tema.acento,
                        contentPadding: EdgeInsets.zero,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pide el nombre de una lista nueva. null si se cancela.
Future<String?> pedirNombreDeLista(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const DialogoNuevaLista());

/// Dialogo para crear una lista.
///
/// Es un widget propio a proposito: el controlador del campo tiene que vivir y
/// morir con el. Crearlo fuera y liberarlo tras el await lo destruia mientras
/// el dialogo seguia cerrandose, y Flutter aborta por ello.
class DialogoNuevaLista extends StatefulWidget {
  const DialogoNuevaLista({super.key});

  @override
  State<DialogoNuevaLista> createState() => _DialogoNuevaListaState();
}

class _DialogoNuevaListaState extends State<DialogoNuevaLista> {
  final TextEditingController _nombre = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool valido = _nombre.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: Tema.superficieAlta,
      title: const Text('Nueva lista'),
      content: TextField(
        controller: _nombre,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nombre'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (String v) {
          if (v.trim().isNotEmpty) Navigator.of(context).pop(v.trim());
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valido ? () => Navigator.of(context).pop(_nombre.text.trim()) : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

String _cuantas(int n) => n == 1 ? '1 cancion' : '$n canciones';
