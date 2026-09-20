import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'control_descarga.dart';
import 'estado_reproductor.dart';
import 'mini_reproductor.dart';
import 'nucleo.dart';
import 'pantalla_biblioteca.dart';
import 'pantalla_descarga.dart';
import 'pantalla_inicio.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sin esto el telefono no reconoce la app como reproductor: no hay controles
  // en la barra de estado ni en la pantalla de bloqueo.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ruben.descargador.reproduccion',
    androidNotificationChannelName: 'Reproduccion',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  Nucleo.escucharVentanaFlotante();
  EstadoReproductor.instancia.recuperarEcualizador();
  // Sin esperarla: deja la cola como estaba, parada, mientras la app abre.
  unawaited(EstadoReproductor.instancia.restaurarSesion());
  runApp(const AplicacionTumbao());
}

class AplicacionTumbao extends StatelessWidget {
  const AplicacionTumbao({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tumbao',
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
  final GlobalKey<PantallaInicioState> _inicio = GlobalKey<PantallaInicioState>();
  final GlobalKey<PantallaBibliotecaState> _biblioteca = GlobalKey<PantallaBibliotecaState>();
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    // La descarga puede empezar en cualquier pantalla, asi que refrescar lo que
    // depende de ella se engancha una sola vez aqui arriba.
    ControlDescarga.instancia.alTerminar = () {
      _biblioteca.currentState?.recargar();
      _inicio.currentState?.recargar();
    };
  }

  /// Las pestanias ya abiertas alguna vez.
  ///
  /// El IndexedStack construye a la vez todas las que le des, y cada pantalla
  /// pide las portadas de lo que ensenia: al arrancar salian las tres de
  /// golpe y se codificaban decenas de imagenes antes del primer fotograma.
  /// Las que no se han visitado esperan, y una vez abiertas se quedan para
  /// conservar su estado.
  final Set<int> _vistas = <int>{0};

  void _irA(int pestana) {
    setState(() {
      _pestana = pestana;
      _vistas.add(pestana);
    });
    if (pestana == 0) _inicio.currentState?.recargar();
    if (pestana == 2) _biblioteca.currentState?.recargar();
  }

  /// Construye la pestania solo si ya se abrio alguna vez.
  Widget _siSeHaVisto(int indice, Widget Function() construir) =>
      _vistas.contains(indice) ? construir() : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _pestana,
          children: <Widget>[
            _siSeHaVisto(
              0,
              () => PantallaInicio(
                key: _inicio,
                alIrADescargar: () => _irA(1),
                alIrABiblioteca: () => _irA(2),
              ),
            ),
            _siSeHaVisto(1, () => const PantallaDescarga()),
            _siSeHaVisto(2, () => PantallaBiblioteca(key: _biblioteca)),
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
            onDestinationSelected: _irA,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
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
