import 'package:descargador_movil/animaciones.dart';
import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/paleta.dart';
import 'package:descargador_movil/panel_letras.dart';
import 'package:descargador_movil/tarjeta_letra.dart';
import 'package:descargador_movil/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'motor_falso.dart';

/// La tarjeta para compartir una frase de la letra, su hoja y el envio.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const Elemento _cancion = Elemento(
  nombre: 'Rubén Blades - Pedro Navaja, version extendida con un titulo larguisimo [x1].mp3',
  uri: 'content://audio/pedro',
  duracion: 400,
  tamano: 1,
  audio: true,
);

const List<String> _versos = <String>[
  'Por la esquina del viejo barrio lo vi pasar',
  '',
  'Con el tumbao que tienen los guapos al caminar',
  'Las manos siempre en los bolsillos de su gaban',
  'Pa que no sepan en cual de ellas lleva el punal',
];

/// La firma con la que empieza todo PNG.
const List<int> _firmaPng = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Widget _app(Widget hijo) => MaterialApp(
      theme: Tema.construir(),
      home: Scaffold(body: hijo),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final List<MethodCall> llamadas = <MethodCall>[];

  setUp(() async {
    JustAudioPlatform.instance = MotorFalso();
    Movimiento.bucles = false;
    llamadas.clear();
    Nucleo.olvidarCaratulas();
    Paleta.vaciar();
    await Catalogo.instancia.usarEnMemoria();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      return switch (llamada.method) {
        'caratula' => '{"ok":true,"imagen":""}',
        _ => '{"ok":true}',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, null);
  });

  test('el verso siguiente es el siguiente que dice algo, y como mucho tres', () {
    expect(versosDesde(_versos, 0, 1), <String>[_versos[0]]);
    expect(versosDesde(_versos, 0, 2), <String>[_versos[0], _versos[2]], reason: 'la pausa no cuenta');
    expect(versosDesde(_versos, 3, 3), <String>[_versos[3], _versos[4]], reason: 'no hay mas');
    expect(versosDesde(_versos, 9, 1), isEmpty);
  });

  test('cada fondo deja leer su texto', () {
    for (final FondoTarjeta fondo in FondoTarjeta.values) {
      final TintaTarjeta t = TarjetaLetra.tintaDe(fondo, null);
      for (final Color c in t.degradado) {
        expect(contraste(t.texto, c), greaterThan(4.5), reason: fondo.titulo);
      }
    }
  });

  testWidgets('la tarjeta cabe en los dos formatos aunque la frase sea larga', (WidgetTester tester) async {
    final List<String> largos = <String>[
      for (int i = 0; i < 3; i++) 'Una frase larguisima que no se acaba nunca y sigue y sigue ' * 3,
    ];
    for (final FormatoTarjeta formato in FormatoTarjeta.values) {
      for (final FondoTarjeta fondo in FondoTarjeta.values) {
        await tester.pumpWidget(_app(Center(
          child: FittedBox(
            child: TarjetaLetra(elemento: _cancion, versos: largos, formato: formato, fondo: fondo),
          ),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${formato.titulo}, ${fondo.titulo}');
        final Size medida = tester.getSize(find.byType(TarjetaLetra));
        expect(medida.width, TarjetaLetra.ancho);
        expect(medida.width / medida.height, closeTo(formato.proporcion, 1e-6));
        expect(find.text('Tumbao'), findsOneWidget);
        expect(find.text('Pedro Navaja, version extendida con un titulo larguisimo'), findsOneWidget);
      }
    }
  });

  testWidgets('mantener pulsado un verso abre la hoja; tocarlo no', (WidgetTester tester) async {
    const String lrc = '[00:01.00] Por la esquina del viejo barrio lo vi pasar\n'
        '[00:05.00] Con el tumbao que tienen los guapos al caminar\n'
        '[00:09.00] Las manos siempre en los bolsillos de su gaban';
    await tester.runAsync(() => Catalogo.instancia.guardarLetra(_cancion.uri, lrc: lrc, texto: ''));
    await tester.pumpWidget(_app(const PanelLetras(elemento: _cancion)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Con el tumbao que tienen los guapos al caminar'));
    await tester.pumpAndSettle();
    expect(find.byType(HojaCompartirLetra), findsNothing, reason: 'el toque corto salta, no comparte');

    await tester.longPress(find.text('Con el tumbao que tienen los guapos al caminar'));
    await tester.pumpAndSettle();
    expect(find.byType(HojaCompartirLetra), findsOneWidget);
    expect(find.text('Compartir la letra'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TarjetaLetra),
        matching: find.text('Con el tumbao que tienen los guapos al caminar'),
      ),
      findsOneWidget,
    );

    // El verso siguiente se anade y se quita.
    await tester.tap(find.text('Verso siguiente'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TarjetaLetra),
        matching: find.text('Las manos siempre en los bolsillos de su gaban'),
      ),
      findsOneWidget,
    );
    expect(find.text('Verso siguiente'), findsNothing, reason: 'era el ultimo');
    await tester.tap(find.text('Quitar verso'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar verso'), findsNothing);
  });

  testWidgets('en la letra sin sincronizar tambien se comparte', (WidgetTester tester) async {
    await tester.runAsync(() => Catalogo.instancia.guardarLetra(
          _cancion.uri,
          lrc: '',
          texto: 'Por la esquina del viejo barrio\n\nlo vi pasar',
        ));
    await tester.pumpWidget(_app(const PanelLetras(elemento: _cancion)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('lo vi pasar'));
    await tester.pumpAndSettle();
    expect(find.byType(HojaCompartirLetra), findsOneWidget);
  });

  testWidgets('«Compartir» manda un PNG de 1080 px al canal', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Builder(
      builder: (BuildContext context) => TextButton(
        onPressed: () => abrirCompartirLetra(context, elemento: _cancion, versos: _versos, indice: 0),
        child: const Text('abrir'),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cuadrada'));
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir'));
    // Sacar la imagen lo hace el motor de verdad: necesita tiempo real.
    for (int i = 0; i < 40 && !llamadas.any((MethodCall c) => c.method == 'compartirImagen'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final MethodCall envio = llamadas.singleWhere((MethodCall c) => c.method == 'compartirImagen');
    final Map<dynamic, dynamic> argumentos = envio.arguments as Map<dynamic, dynamic>;
    final Uint8List png = argumentos['png'] as Uint8List;
    expect(png.take(8).toList(), _firmaPng);
    // El ancho va en la cabecera IHDR, en los bytes 16 a 19.
    expect(ByteData.sublistView(png).getUint32(16), 1080);
    expect(ByteData.sublistView(png).getUint32(20), 1080, reason: 'cuadrada');
    expect(argumentos['nombre'], endsWith('.png'));
    expect(find.byType(HojaCompartirLetra), findsNothing, reason: 'compartida, la hoja se cierra');
  });
}
