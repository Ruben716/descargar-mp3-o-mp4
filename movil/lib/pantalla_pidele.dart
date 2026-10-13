import 'package:flutter/material.dart';

import 'tema.dart';

/// «Pidele a Tumbao»: escribe lo que quieres oir y la app arma la cola.
class PantallaPidele extends StatefulWidget {
  const PantallaPidele({super.key, this.frase = ''});

  /// Lo que ya viene escrito (un ejemplo tocado, un atajo).
  final String frase;

  @override
  State<PantallaPidele> createState() => _PantallaPideleState();
}

class _PantallaPideleState extends State<PantallaPidele> {
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tema.fondo,
        appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Pidele a Tumbao')),
      );
}
