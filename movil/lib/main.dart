import 'package:flutter/material.dart';

import 'pantalla_biblioteca.dart';
import 'pantalla_descarga.dart';

void main() => runApp(const AplicacionDescargador());

class AplicacionDescargador extends StatelessWidget {
  const AplicacionDescargador({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Descargador',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  final GlobalKey<PantallaBibliotecaState> _biblioteca = GlobalKey<PantallaBibliotecaState>();
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_pestana == 0 ? 'Descargar' : 'Biblioteca')),
      body: IndexedStack(
        index: _pestana,
        children: <Widget>[
          // Al terminar una descarga la biblioteca se refresca sola.
          PantallaDescarga(alDescargar: () => _biblioteca.currentState?.recargar()),
          PantallaBiblioteca(key: _biblioteca),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (int i) {
          setState(() => _pestana = i);
          if (i == 1) _biblioteca.currentState?.recargar();
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.download), label: 'Descargar'),
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Biblioteca'),
        ],
      ),
    );
  }
}
