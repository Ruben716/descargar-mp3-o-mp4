import 'package:flutter/material.dart';

import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Corrige a mano el artista y el titulo de una pista.
///
/// Hace falta porque el nombre sale de como titulase quien subio el video, y
/// eso a veces no hay limpieza que lo arregle. Devuelve `true` si algo cambio,
/// para que quien llama recargue la biblioteca.
Future<bool> editarEtiquetas(BuildContext context, Elemento elemento) async {
  final bool? cambiado = await showDialog<bool>(
    context: context,
    builder: (BuildContext contexto) => _DialogoEtiquetas(elemento: elemento),
  );
  return cambiado ?? false;
}

class _DialogoEtiquetas extends StatefulWidget {
  const _DialogoEtiquetas({required this.elemento});

  final Elemento elemento;

  @override
  State<_DialogoEtiquetas> createState() => _DialogoEtiquetasState();
}

/// El controlador de cada campo vive y muere con el dialogo, como en el de
/// crear listas: crearlo fuera y liberarlo tras el await lo destruia mientras
/// el dialogo seguia cerrandose, y Flutter aborta por ello.
class _DialogoEtiquetasState extends State<_DialogoEtiquetas> {
  late final ({String artista, String tema}) _partes =
      partirNombre(nombreLimpio(widget.elemento.nombre));
  late final TextEditingController _artista = TextEditingController(text: _partes.artista);
  late final TextEditingController _titulo = TextEditingController(text: _partes.tema);

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _artista.dispose();
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await Nucleo.etiquetar(
        widget.elemento.uri,
        titulo: _titulo.text.trim(),
        artista: _artista.text.trim(),
      );
      // La portada no cambia, pero el archivo si: mejor volver a pedirla que
      // arriesgarse a ensenar la de antes.
      Nucleo.olvidarCaratula(widget.elemento.uri);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool valido = _titulo.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: Tema.superficieAlta,
      title: const Text('Editar etiquetas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _artista,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Artista',
              hintText: 'Dejalo vacio si no lo tiene',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titulo,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Titulo'),
          ),
          const SizedBox(height: 10),
          Text(
            'Se reescribe la etiqueta del archivo y se renombra, asi que '
            'tambien cambia en el resto del telefono.',
            style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Tema.acentoCalido, fontSize: 11),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valido && !_guardando ? _guardar : null,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
