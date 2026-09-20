import 'package:flutter/material.dart';

import 'mini_reproductor.dart';
import 'pantalla_biblioteca.dart';
import 'pantalla_descarga.dart';
import 'tema.dart';

void main() => runApp(const AplicacionDescargador());

class AplicacionDescargador extends StatelessWidget {
  const AplicacionDescargador({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Descargador',
      debugShowCheckedModeBanner: false,
      theme: Tema.construir(),
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
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _pestana,
          children: <Widget>[
            // Al terminar una descarga la biblioteca se refresca sola.
            PantallaDescarga(alDescargar: () => _biblioteca.currentState?.recargar()),
            PantallaBiblioteca(key: _biblioteca),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Lo que suena acompania siempre, se mire la pestania que se mire.
          const MiniReproductor(),
          NavigationBar(
            selectedIndex: _pestana,
            onDestinationSelected: (int i) {
              setState(() => _pestana = i);
              if (i == 1) _biblioteca.currentState?.recargar();
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download_rounded),
                label: 'Descargar',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Biblioteca',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
