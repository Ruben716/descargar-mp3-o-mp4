import 'package:descargador_movil/main.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Respuestas del canal nativo. Las pruebas no arrancan Python ni tocan la red.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const String _busqueda = '{"ok":true,"resultados":['
    '{"titulo":"Cancion uno","autor":"Autor","duracion":254,"url":"https://y/1","miniatura":""},'
    '{"titulo":"Cancion dos","autor":"Otro","duracion":100,"url":"https://y/2","miniatura":""}]}';

void main() {
  final List<MethodCall> llamadas = <MethodCall>[];

  setUp(() {
    llamadas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      return switch (llamada.method) {
        'urlCompartida' => null,
        'biblioteca' => '{"ok":true,"elementos":[]}',
        'buscar' => _busqueda,
        'caratula' => '{"ok":true,"imagen":""}',
        'descargar' => '{"ok":true,"archivos":["Music/Descargador/x.mp3"]}',
        _ => '{"ok":true}',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, null);
  });

  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionDescargador());
    await tester.pumpAndSettle();
  }

  testWidgets('arranca en el buscador, con video y musica a elegir', (WidgetTester tester) async {
    await abrir(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Musica'), findsOneWidget);
    // El titulo, el boton y la pestania comparten la palabra.
    expect(find.text('Descargar'), findsWidgets);
  });

  testWidgets('una busqueda pinta los resultados', (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(find.text('Cancion dos'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isTrue);
  });

  testWidgets('elegir un resultado cambia el boton de descarga', (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    expect(find.text('Descargar seleccion'), findsOneWidget);
  });

  testWidgets('el panel de opciones se abre y ofrece lo del nucleo',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Opciones'), findsOneWidget);
    expect(find.text('SUBTITULOS'), findsOneWidget);
    expect(find.text('Quitar patrocinios'), findsOneWidget);
  });

  testWidgets('la biblioteca vacia lo dice en vez de quedarse en blanco',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aqui no hay nada todavia'), findsOneWidget);
  });

  test('los ajustes viajan al nucleo con los nombres que espera Kotlin', () {
    final Map<String, dynamic> mapa = const Ajustes(
      url: 'https://y/1',
      soloAudio: true,
      calidad: 720,
      bitrate: '320',
      subtitulos: 'es',
      fragmento: '00:10-00:20',
      sinPatrocinios: true,
    ).aMapa();

    expect(mapa['soloAudio'], isTrue);
    // En audio la altura no aplica: se manda 0 para que el nucleo la ignore.
    expect(mapa['calidad'], 0);
    expect(mapa['bitrate'], '320');
    expect(mapa['fragmento'], '00:10-00:20');
    expect(mapa['sinPatrocinios'], isTrue);
  });
}
