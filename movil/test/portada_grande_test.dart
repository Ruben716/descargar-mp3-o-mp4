import 'dart:convert';
import 'dart:io';

import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/portada_grande.dart';
import 'package:descargador_movil/portadas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

Elemento _cancion(String uri, {String nombre = 'Grupo - Tema [abc].opus', bool audio = true}) =>
    Elemento(nombre: nombre, uri: uri, duracion: 200, tamano: 1, audio: audio);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> llamadas = <MethodCall>[];
  bool wifi = true;
  late Directory raiz;

  /// Lo que contesta Kotlin a «caratulaGrande». Por defecto la deja en su sitio.
  late String Function(MethodCall llamada) responderGrande;

  /// Cuantas peticiones de portada grande hay a la vez, y el maximo visto.
  int aLaVez = 0;
  int maximoALaVez = 0;

  String guardarGrande(MethodCall llamada) {
    final String clave = '${(llamada.arguments as Map<dynamic, dynamic>)['clave']}';
    final File archivo = File('${raiz.path}/portadas/$clave.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    return jsonEncode(<String, Object>{'ok': true, 'ruta': archivo.path});
  }

  setUp(() {
    llamadas.clear();
    wifi = true;
    aLaVez = 0;
    maximoALaVez = 0;
    raiz = Directory.systemTemp.createTempSync('portadas_prueba');
    responderGrande = guardarGrande;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PortadasGrandes.reiniciar();
    Nucleo.olvidarCaratulas();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      switch (llamada.method) {
        case 'redSinLimite':
          return wifi;
        case 'caratula':
          return '{"ok":true,"imagen":""}';
        case 'caratulaGrande':
          aLaVez++;
          if (aLaVez > maximoALaVez) maximoALaVez = aLaVez;
          await Future<void>.delayed(Duration.zero);
          aLaVez--;
          return responderGrande(llamada);
        case 'biblioteca':
          return jsonEncode(<String, Object>{
            'ok': true,
            'elementos': <Map<String, Object>>[
              for (final String n in <String>['1', '2', '3'])
                <String, Object>{
                  'nombre': 'Grupo $n - Tema $n [id$n].opus',
                  'uri': 'content://audio/$n',
                  'duracion': 200,
                  'tamano': 1,
                  'audio': true,
                },
              <String, Object>{
                'nombre': 'Un video [v].mp4',
                'uri': 'content://video/9',
                'duracion': 200,
                'tamano': 1,
                'audio': false,
              },
            ],
          });
      }
      return '{"ok":true}';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, null);
    PortadasGrandes.carpeta = () async => throw const FileSystemException('sin path_provider');
    try {
      raiz.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Activa la portada grande: le da una carpeta, que en las pruebas no hay.
  void conCarpeta() => PortadasGrandes.carpeta = () async => raiz;

  Iterable<MethodCall> grandes() => llamadas.where((MethodCall l) => l.method == 'caratulaGrande');

  bool hayGrande() => find
      .byWidgetPredicate((Widget w) =>
          w is Image && w.image is ResizeImage && (w.image as ResizeImage).imageProvider is FileImage)
      .evaluate()
      .isNotEmpty;

  Future<void> pintar(WidgetTester tester, Elemento elemento) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: PortadaGrande(elemento: elemento, lado: 300))));
    // La busqueda encadena varias esperas (carpeta, recuerdo, wifi, canal).
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  group('la clave de la portada', () {
    test('es estable, sin barras y distinta para cada cancion', () {
      // FNV-1a de nada es su base: si cambia el hash, las guardadas se pierden.
      expect(Nucleo.clavePortada(''), '811c9dc5811c9dc5');
      expect(Nucleo.clavePortada('content://audio/1'), Nucleo.clavePortada('content://audio/1'));
      expect(Nucleo.clavePortada('content://audio/1'), isNot(Nucleo.clavePortada('content://audio/2')));
      expect(Nucleo.clavePortada('content://media/external/audio/media/1234'), matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('la portada grande', () {
    testWidgets('sin carpeta (en las pruebas) se queda en la pequena y no pide nada', (WidgetTester tester) async {
      PortadasGrandes.carpeta = () async => throw const FileSystemException('sin path_provider');
      await pintar(tester, _cancion('content://audio/1'));
      expect(find.byType(PortadaLocal), findsOneWidget);
      expect(hayGrande(), isFalse);
      expect(llamadas.where((MethodCall l) => l.method != 'caratula'), isEmpty);
    });

    testWidgets('si ya esta en disco se usa sin tocar la red', (WidgetTester tester) async {
      conCarpeta();
      final String uri = 'content://audio/1';
      File('${raiz.path}/portadas/${Nucleo.clavePortada(uri)}.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
      await pintar(tester, _cancion(uri));
      expect(hayGrande(), isTrue);
      expect(find.byType(PortadaLocal), findsOneWidget, reason: 'la pequena sigue debajo');
      expect(llamadas.where((MethodCall l) => l.method == 'redSinLimite' || l.method == 'caratulaGrande'), isEmpty);
    });

    testWidgets('sin wifi no se pide', (WidgetTester tester) async {
      conCarpeta();
      wifi = false;
      await pintar(tester, _cancion('content://audio/1'));
      expect(grandes(), isEmpty);
      expect(hayGrande(), isFalse);
    });

    testWidgets('con wifi se pide con su clave y se funde encima', (WidgetTester tester) async {
      conCarpeta();
      const String uri = 'content://audio/1';
      await pintar(tester, _cancion(uri));
      expect(grandes(), hasLength(1));
      final Map<dynamic, dynamic> argumentos = grandes().single.arguments as Map<dynamic, dynamic>;
      expect(argumentos['clave'], Nucleo.clavePortada(uri));
      expect(argumentos['artista'], 'Grupo');
      expect(argumentos['titulo'], 'Tema');
      expect(hayGrande(), isTrue);
      final Image grande = tester.widget<Image>(find.byWidgetPredicate((Widget w) => w is Image && w.image is ResizeImage));
      expect((grande.image as ResizeImage).width, (300 * tester.view.devicePixelRatio).round(),
          reason: 'descodificada al ancho de la pantalla, no a 1400');
      expect(tester.getSize(find.byType(PortadaGrande)), const Size(300, 300), reason: 'sin saltos de tamano');
    });

    testWidgets('sin artista no se busca: daria con otra que se llame igual', (WidgetTester tester) async {
      conCarpeta();
      await pintar(tester, _cancion('content://audio/1', nombre: 'Un tema suelto [x].opus'));
      expect(grandes(), isEmpty);
    });

    testWidgets('lo que no tiene portada oficial se recuerda y no se repite', (WidgetTester tester) async {
      conCarpeta();
      responderGrande = (MethodCall _) => '{"ok":false,"sinPortada":true,"error":"No tiene portada oficial."}';
      await pintar(tester, _cancion('content://audio/1'));
      expect(grandes(), hasLength(1));
      expect(hayGrande(), isFalse);

      // Aunque se olvide lo que hay en memoria, queda guardado.
      PortadasGrandes.reiniciar();
      await tester.pumpWidget(const SizedBox());
      await pintar(tester, _cancion('content://audio/1'));
      expect(grandes(), hasLength(1));
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('portadas_sin_oficial'), hasLength(1));
    });

    testWidgets('un fallo cualquiera no se recuerda: se vuelve a intentar', (WidgetTester tester) async {
      conCarpeta();
      responderGrande = (MethodCall _) => '{"ok":false,"error":"Kotlin: algo"}';
      await pintar(tester, _cancion('content://audio/1'));
      PortadasGrandes.reiniciar();
      await tester.pumpWidget(const SizedBox());
      await pintar(tester, _cancion('content://audio/1'));
      expect(grandes(), hasLength(2));
    });

    testWidgets('al cambiar de cancion la grande de la anterior no se queda encima', (WidgetTester tester) async {
      conCarpeta();
      await pintar(tester, _cancion('content://audio/1'));
      expect(hayGrande(), isTrue);
      wifi = false;
      await pintar(tester, _cancion('content://audio/2', nombre: 'Otro - Distinto [y].opus'));
      expect(hayGrande(), isFalse);
    });
  });

  group('toda la biblioteca', () {
    test('se baja de una en una, solo audio, y salta lo que ya esta', () async {
      conCarpeta();
      File('${raiz.path}/portadas/${Nucleo.clavePortada('content://audio/2')}.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1]);
      final List<({int hechas, int total})?> avances = <({int hechas, int total})?>[];
      void apuntar() => avances.add(PortadasGrandes.avance.value);
      PortadasGrandes.avance.addListener(apuntar);
      final int hechas = await PortadasGrandes.bajarTodas();
      PortadasGrandes.avance.removeListener(apuntar);

      expect(hechas, 3);
      expect(grandes().map((MethodCall l) => (l.arguments as Map<dynamic, dynamic>)['titulo']),
          <String>['Tema 1', 'Tema 3']);
      expect(maximoALaVez, 1, reason: 'de una en una');
      expect(avances.whereType<({int hechas, int total})>().map((({int hechas, int total}) a) => a.total).toSet(),
          containsAll(<int>[3]));
      expect(PortadasGrandes.avance.value, isNull, reason: 'al acabar ya no esta en marcha');
    });

    test('sin wifi se para y no pide nada', () async {
      conCarpeta();
      wifi = false;
      expect(await PortadasGrandes.bajarTodas(), 0);
      expect(grandes(), isEmpty);
    });
  });
}
