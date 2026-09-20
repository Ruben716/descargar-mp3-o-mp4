import 'package:descargador_movil/main.dart';
import 'package:descargador_movil/control_descarga.dart';
import 'package:descargador_movil/estado_reproductor.dart';
import 'package:descargador_movil/listas.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Respuestas del canal nativo. Las pruebas no arrancan Python ni tocan la red.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const String _busqueda = '{"ok":true,"resultados":['
    '{"titulo":"Cancion uno","autor":"Autor","duracion":254,"url":"https://y/1","miniatura":""},'
    '{"titulo":"Cancion dos","autor":"Otro","duracion":100,"url":"https://y/2","miniatura":""}]}';

void main() {
  // El almacenamiento del telefono tampoco existe en las pruebas.
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> llamadas = <MethodCall>[];

  setUp(() {
    llamadas.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // El reproductor y la descarga son unicos para toda la app: sin esto
    // una prueba heredaria lo que dejo la anterior.
    EstadoReproductor.instancia.reiniciar();
    ControlDescarga.instancia.reiniciar();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      return switch (llamada.method) {
        'urlCompartida' => null,
        'biblioteca' => '{"ok":true,"elementos":[]}',
        'buscar' => _busqueda,
        'importarLista' => _busqueda,
        'caratula' => '{"ok":true,"imagen":""}',
        'previsualizar' =>
          '{"ok":true,"url":"https://cdn/p","titulo":"Cancion uno","cabeceras":{}}',
        'eliminar' => '{"ok":true}',
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

  testWidgets('pegar un enlace de lista en el buscador ofrece traerla entera',
      (WidgetTester tester) async {
    // Regresion: antes habia que cambiar a modo URL primero, y pegarlo en el
    // buscador acababa en "Sin resultados".
    await abrir(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    expect(find.text('Traer la lista'), findsOneWidget);

    await tester.tap(find.text('Traer la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Cancion uno'), findsOneWidget);
  });

  testWidgets('buscar con un enlace pegado no busca, lo resuelve',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/playlist?list=PLabc',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'importarLista'), isTrue);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isFalse);
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

  testWidgets('escuchar un resultado abre su vista previa',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Un boton de escucha por resultado.
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded).first);
    // pumpAndSettle no sirve aqui: mientras prepara la pista hay un indicador
    // circular girando y nunca quedaria en reposo. Se bombea a mano lo
    // suficiente para que la navegacion asincrona termine.
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // La vista previa se ve: titulo, autor y aviso de que no esta bajado.
    expect(find.text('VISTA PREVIA'), findsOneWidget);
    expect(find.text('Todavia no esta en tu telefono'), findsOneWidget);
    expect(find.textContaining('Descargar'), findsWidgets);
  });

  testWidgets('cancelar el dialogo de nueva lista no rompe nada',
      (WidgetTester tester) async {
    // Regresion: el controlador del campo se liberaba antes de que el dialogo
    // terminara de cerrarse y Flutter abortaba con _dependents.isEmpty.
    await abrir(tester);
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva lista'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nueva lista'), findsNothing);
  });

  testWidgets('no se puede crear una lista sin nombre', (WidgetTester tester) async {
    await abrir(tester);
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();

    final Finder crear = find.widgetWithText(FilledButton, 'Crear');
    expect(tester.widget<FilledButton>(crear).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Para correr');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);
  });

  test('una lista recuerda sus pistas y las olvida al borrar la descarga',
      () async {
    final Listas listas = Listas.instancia;
    await listas.crear('Prueba');
    await listas.alternar('Prueba', 'content://audio/1');
    expect(listas.contiene('Prueba', 'content://audio/1'), isTrue);

    // Un nombre repetido no crea una segunda lista.
    expect(await listas.crear('Prueba'), isFalse);

    // Al eliminar el archivo debe desaparecer de todas las listas.
    await listas.olvidar('content://audio/1');
    expect(listas.contiene('Prueba', 'content://audio/1'), isFalse);
    await listas.borrar('Prueba');
    expect(listas.nombres, isNot(contains('Prueba')));
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
