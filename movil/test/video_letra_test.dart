import 'dart:convert';
import 'dart:io';

import 'package:descargador_movil/animaciones.dart';
import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/disenos_letra.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/paleta.dart';
import 'package:descargador_movil/panel_letras.dart';
import 'package:descargador_movil/tarjeta_letra.dart';
import 'package:descargador_movil/tema.dart';
import 'package:descargador_movil/video_letra.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'motor_falso.dart';

/// El video de un trozo de la cancion con su letra: el plan, la hoja y el envio.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const Elemento _cancion = Elemento(
  nombre: 'Ruben Blades - Pedro Navaja.mp3',
  uri: 'content://audio/pedro',
  duracion: 400,
  tamano: 1,
  audio: true,
);

const List<String> _versos = <String>[
  'Por la esquina del viejo barrio lo vi pasar',
  'Con el tumbao que tienen los guapos al caminar',
  '',
  'Las manos siempre en los bolsillos de su gaban',
  'Pa que no sepan en cual de ellas lleva el punal',
  'Usa un sombrero de ala ancha de medio lao',
];

const List<Duration> _instantes = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 5),
  Duration(seconds: 9),
  Duration(seconds: 12),
  Duration(seconds: 20),
  Duration(seconds: 40),
];

Widget _app(Widget hijo) => MaterialApp(
      theme: Tema.construir(),
      home: Scaffold(body: hijo),
    );

/// El ancho y el alto de un PNG, de su cabecera IHDR.
(int, int) _medidaPng(List<int> png) {
  final ByteData datos = ByteData.sublistView(Uint8List.fromList(png));
  return (datos.getUint32(16), datos.getUint32(20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('planificarVideo', () {
    test('desde el verso pulsado, con el desfase sumado, hasta los 15 s', () {
      final PlanVideo plan = planificarVideo(
        versos: _versos,
        instantes: _instantes,
        indice: 1,
        duracion: DuracionVideo.corta.tiempo,
        desfase: const Duration(milliseconds: 500),
      )!;
      expect(plan.inicio, const Duration(milliseconds: 5500), reason: 'desde + desfase');
      expect(plan.duracion, const Duration(seconds: 15));
      expect(plan.tramos.map((TramoVideo t) => t.verso), <String>[_versos[1], _versos[3]],
          reason: 'la pausa no es fotograma y el de los 20 s ya no entra');
      // El verso 1 sigue durante la pausa, hasta que entra el 3 (12,5 s).
      expect(plan.tramos.map((TramoVideo t) => t.duracion.inMilliseconds), <int>[7000, 8000]);
      expect(plan.tramos.first.anterior, isEmpty, reason: 'lo de antes no suena en el video');
      expect(plan.tramos.first.siguiente, _versos[3]);
      expect(plan.tramos.last.anterior, _versos[1]);
      expect(plan.tramos.last.siguiente, isEmpty, reason: 'lo que viene ya no suena');
    });

    test('a 30 s entran mas versos y los tramos suman lo que dura', () {
      final PlanVideo plan = planificarVideo(
        versos: _versos,
        instantes: _instantes,
        indice: 1,
        duracion: DuracionVideo.larga.tiempo,
        desfase: const Duration(milliseconds: 500),
      )!;
      expect(plan.tramos.map((TramoVideo t) => t.verso), <String>[_versos[1], _versos[3], _versos[4]]);
      expect(plan.tramos.map((TramoVideo t) => t.duracion.inMilliseconds), <int>[7000, 8000, 15000]);
      expect(plan.tramos[1].siguiente, _versos[4]);
    });

    test('no pasa del final de la cancion', () {
      final PlanVideo plan = planificarVideo(
        versos: _versos,
        instantes: _instantes,
        indice: 1,
        duracion: DuracionVideo.larga.tiempo,
        desfase: const Duration(milliseconds: 500),
        total: const Duration(seconds: 25),
      )!;
      expect(plan.duracion, const Duration(milliseconds: 19500));
      expect(plan.tramos.last.duracion, const Duration(milliseconds: 4500));
      final int suma = plan.tramos.fold(0, (int s, TramoVideo t) => s + t.duracion.inMilliseconds);
      expect(suma, plan.duracion.inMilliseconds);
    });

    test('con un desfase que adelanta, no empieza antes del cero', () {
      final PlanVideo plan = planificarVideo(
        versos: _versos,
        instantes: _instantes,
        indice: 0,
        duracion: DuracionVideo.corta.tiempo,
        desfase: const Duration(seconds: -2),
      )!;
      expect(plan.inicio, Duration.zero);
      // El verso 1 entra a los 3 s del archivo (5 - 2): ahi acaba el primero.
      expect(plan.tramos.first.duracion, const Duration(seconds: 3));
    });

    test('sin marcas, en una pausa o al final de la cancion no hay video', () {
      PlanVideo? de({List<Duration> instantes = _instantes, int indice = 1, Duration total = Duration.zero}) =>
          planificarVideo(
            versos: _versos,
            instantes: instantes,
            indice: indice,
            duracion: DuracionVideo.corta.tiempo,
            total: total,
          );
      expect(de(instantes: _instantes.take(3).toList()), isNull, reason: 'marcas que no cuadran');
      expect(de(indice: 2), isNull, reason: 'la pausa no se comparte');
      expect(de(indice: 9), isNull);
      expect(de(indice: 5, total: const Duration(seconds: 41)), isNull, reason: 'queda un segundo');
    });

    test('una pausa es lo que no dice nada', () {
      for (final String v in <String>['', '   ', '♪', '♪ ♪ ♪', '...', '—', '(♫)']) {
        expect(esPausa(v), isTrue, reason: '«$v»');
      }
      for (final String v in <String>['la', 'Oh', '1, 2, 3', '¡Ay!']) {
        expect(esPausa(v), isFalse, reason: '«$v»');
      }
    });
  });

  group('disenos', () {
    test('cada cosa cabe en su lienzo y nada pisa a lo que se mueve', () {
      for (final FormatoTarjeta f in FormatoTarjeta.values) {
        final Rect lienzo = Rect.fromLTWH(0, 0, 360, 360 / f.proporcion);
        for (final EstiloLetra e in EstiloLetra.values) {
          for (final bool video in <bool>[true, false]) {
            final DisenoLetra d = disenoLetra(f, e, video: video);
            final String que = '$f $e video: $video';
            final Rect? movil = d.movil;
            expect(lienzo.intersect(d.texto), d.texto, reason: que);
            expect(movil == null, e == EstiloLetra.letra, reason: que);
            if (movil != null) {
              expect(lienzo.intersect(movil), movil, reason: que);
              expect(movil.overlaps(d.texto), isFalse, reason: que);
            }
            if (!video) continue;
            expect(lienzo.intersect(d.onda), d.onda, reason: que);
            expect(d.onda.overlaps(d.texto), isFalse, reason: '$que: la onda va donde no hay texto');
            if (movil != null) expect(d.onda.overlaps(movil), isFalse, reason: que);
          }
        }
      }
    });

    test('lo que recibe FFmpeg va en px y sin PNG no se mueve nada', () {
      final Map<String, Object> historia = disenoParaFfmpeg(FormatoTarjeta.historia, EstiloLetra.letra);
      expect(historia, <String, Object>{'ancho': 720, 'alto': 1280, 'onda': <int>[40, 1064, 640, 160]},
          reason: 'el de siempre: lo mismo que pinta video_letra.py sin diseno');
      final Map<String, Object> vinilo =
          disenoParaFfmpeg(FormatoTarjeta.cuadrada, EstiloLetra.vinilo, movil: '/c/movil.png');
      expect(vinilo['alto'], 720);
      expect(vinilo['movil'], <String, Object>{
        'png': '/c/movil.png', 'tipo': 'girar', 'x': 36, 'y': 154, 'ancho': 316, 'alto': 316,
      });
      expect((disenoParaFfmpeg(FormatoTarjeta.historia, EstiloLetra.portada, movil: '/c/m.png')['movil']!
              as Map<String, Object>)['tipo'], 'zoom');
      expect(disenoParaFfmpeg(FormatoTarjeta.cuadrada, EstiloLetra.vinilo).containsKey('movil'), isFalse);
    });
  });

  group('la hoja', () {
    final List<MethodCall> llamadas = <MethodCall>[];
    late Directory temporal;

    /// Lo que se comprobo de cada fotograma mientras existia: ancho y alto.
    final List<(int, int)> medidas = <(int, int)>[];
    String respuestaVideo = '{"ok":true,"ruta":"Pictures/Tumbao/x.mp4"}';

    setUp(() async {
      JustAudioPlatform.instance = MotorFalso();
      Movimiento.bucles = false;
      llamadas.clear();
      medidas.clear();
      respuestaVideo = '{"ok":true,"ruta":"Pictures/Tumbao/x.mp4"}';
      Nucleo.olvidarCaratulas();
      Paleta.vaciar();
      await Catalogo.instancia.usarEnMemoria();
      temporal = Directory.systemTemp.createTempSync('video_letra_prueba');
      VideoLetra.carpeta = () async => temporal;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
        llamadas.add(llamada);
        if (llamada.method == 'videoLetra') {
          // Los PNG se miran ahora: al volver, la hoja los borra.
          final Map<dynamic, dynamic> argumentos = llamada.arguments as Map<dynamic, dynamic>;
          for (final dynamic f in jsonDecode(argumentos['fotogramas'] as String) as List<dynamic>) {
            medidas.add(_medidaPng(File((f as Map<String, dynamic>)['png'] as String).readAsBytesSync()));
          }
          final String diseno = argumentos['diseno'] as String;
          final dynamic movil = diseno.isEmpty ? null : (jsonDecode(diseno) as Map<String, dynamic>)['movil'];
          if (movil != null) {
            medidas.add(_medidaPng(File((movil as Map<String, dynamic>)['png'] as String).readAsBytesSync()));
          }
          return respuestaVideo;
        }
        return switch (llamada.method) {
          'caratula' => '{"ok":true,"imagen":""}',
          'sincronizarLetra' => '{"ok":true,"desfase":0,"aplicar":false}',
          _ => '{"ok":true}',
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_canal, null);
      if (temporal.existsSync()) temporal.deleteSync(recursive: true);
    });

    /// La letra sincronizada, con un desfase guardado, en el panel; y la hoja
    /// abierta sobre [verso].
    Future<void> abrirSobre(WidgetTester tester, String verso) async {
      const String lrc = '[00:01.00] Por la esquina del viejo barrio lo vi pasar\n'
          '[00:05.00] Con el tumbao que tienen los guapos al caminar\n'
          '[00:09.00]\n'
          '[00:12.00] Las manos siempre en los bolsillos de su gaban\n'
          '[00:20.00] Pa que no sepan en cual de ellas lleva el punal';
      await tester.runAsync(() async {
        await Catalogo.instancia.guardarLetra(_cancion.uri, lrc: lrc, texto: '');
        await Catalogo.instancia.guardarDesfase(_cancion.uri, 1500);
      });
      await tester.pumpWidget(_app(const PanelLetras(elemento: _cancion)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await tester.longPress(find.text(verso));
      await tester.pumpAndSettle();
      expect(find.byType(HojaCompartirLetra), findsOneWidget);
    }

    /// Espera de verdad (pintar y guardar los PNG no es de mentira) hasta que
    /// llega la llamada al canal.
    Future<void> esperarVideo(WidgetTester tester) async {
      for (int i = 0; i < 200 && !llamadas.any((MethodCall c) => c.method == 'videoLetra'); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      // Lo que queda (cerrar la hoja, borrar la carpeta) tambien es de verdad.
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('«Crear video» manda al canal el trozo y un PNG de 720x1280 por verso',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await abrirSobre(tester, 'Con el tumbao que tienen los guapos al caminar');

      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      expect(find.byType(FotogramaVideo), findsOneWidget);
      expect(find.byType(TarjetaLetra), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FotogramaVideo),
          matching: find.text('Con el tumbao que tienen los guapos al caminar'),
        ),
        findsOneWidget,
        reason: 'la vista previa es el primer fotograma',
      );
      expect(find.text('2 versos en 15 s, con el audio de ese trozo.'), findsOneWidget);

      await tester.tap(find.text('30 s'));
      await tester.pumpAndSettle();
      expect(find.text('3 versos en 30 s, con el audio de ese trozo.'), findsOneWidget);

      await tester.tap(find.text('Crear video'));
      await esperarVideo(tester);

      final MethodCall envio = llamadas.singleWhere((MethodCall c) => c.method == 'videoLetra');
      final Map<dynamic, dynamic> argumentos = envio.arguments as Map<dynamic, dynamic>;
      expect(argumentos['uri'], _cancion.uri);
      expect(argumentos['inicioMs'], 6500, reason: 'el verso a los 5 s mas 1,5 s de desfase');
      expect(argumentos['duracionMs'], 30000);
      final List<dynamic> fotogramas = jsonDecode(argumentos['fotogramas'] as String) as List<dynamic>;
      expect(fotogramas, hasLength(3));
      expect(
        fotogramas.map((dynamic f) => (f as Map<String, dynamic>)['ms']),
        <int>[7000, 8000, 15000],
      );
      expect(medidas, List<(int, int)>.filled(3, (720, 1280)));
      expect(temporal.listSync(), isEmpty, reason: 'los fotogramas no se quedan');
      expect(find.byType(HojaCompartirLetra), findsNothing, reason: 'compartido, la hoja se cierra');
    });

    testWidgets('cuadrado y con el vinilo: el disco va aparte para que FFmpeg lo gire',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await abrirSobre(tester, 'Con el tumbao que tienen los guapos al caminar');

      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vinilo'));
      await tester.tap(find.text('Cuadrada'));
      await tester.pumpAndSettle();
      expect(find.byType(Disco), findsOneWidget);
      await tester.tap(find.text('Crear video'));
      await esperarVideo(tester);

      final MethodCall envio = llamadas.singleWhere((MethodCall c) => c.method == 'videoLetra');
      final Map<String, dynamic> diseno =
          jsonDecode((envio.arguments as Map<dynamic, dynamic>)['diseno'] as String) as Map<String, dynamic>;
      expect(diseno['alto'], 720);
      expect((diseno['movil'] as Map<String, dynamic>)['tipo'], 'girar');
      expect(medidas, <(int, int)>[(720, 720), (720, 720), (316, 316)],
          reason: 'dos fotogramas cuadrados y el disco a su tamano en el video');
      expect(temporal.listSync(), isEmpty);
    });

    testWidgets('la tarjeta tambien sale con la portada', (WidgetTester tester) async {
      await abrirSobre(tester, 'Con el tumbao que tienen los guapos al caminar');
      await tester.tap(find.text('Portada'));
      await tester.pumpAndSettle();
      expect(find.byType(PortadaGrande), findsOneWidget);
      expect(find.descendant(of: find.byType(TarjetaLetra), matching: find.text('Pedro Navaja')), findsOneWidget);
    });

    testWidgets('si el video falla, se cierra la hoja y se avisa', (WidgetTester tester) async {
      respuestaVideo = '{"ok":false,"error":"Unknown encoder"}';
      await abrirSobre(tester, 'Las manos siempre en los bolsillos de su gaban');
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear video'));
      await esperarVideo(tester);

      final MethodCall envio = llamadas.singleWhere((MethodCall c) => c.method == 'videoLetra');
      expect((envio.arguments as Map<dynamic, dynamic>)['inicioMs'], 13500);
      expect(find.byType(HojaCompartirLetra), findsNothing);
      expect(find.text('No se pudo crear el video.'), findsOneWidget);
    });

    testWidgets('sin letra sincronizada no hay video', (WidgetTester tester) async {
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
      expect(find.text('Video'), findsNothing);
      expect(find.byType(SegmentedButton<ModoCompartir>), findsNothing);
      expect(find.text('Compartir'), findsOneWidget);
    });
  });
}
