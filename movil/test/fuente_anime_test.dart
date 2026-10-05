import 'package:descargador_movil/fuente_anime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de la fuente de anime: el canal de Kotlin se simula, asi que no se
/// toca la red. Comprueba el contrato (metodo, claves y conversion a modelos).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel canal = FuenteAnime.canal;

  void responder(Future<String> Function(MethodCall) manejar) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (MethodCall llamada) => manejar(llamada));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  test('buscar pide el texto y devuelve los animes del canal', () async {
    responder((MethodCall llamada) async {
      expect(llamada.method, 'buscar');
      expect(llamada.arguments, <String, dynamic>{'texto': 'naruto'});
      return '{"ok": true, "animes": ['
          '{"url": "https://jkanime.net/naruto/", "titulo": "Naruto", '
          '"portada": "https://x/p.jpg", "tipo": "Serie", "estado": "Concluido"}]}';
    });

    final List<AnimeFuente> lista = await FuenteAnime.buscar('naruto');

    expect(lista, hasLength(1));
    expect(lista.first.titulo, 'Naruto');
    expect(lista.first.url, 'https://jkanime.net/naruto/');
    expect(lista.first.tipo, 'Serie');
  });

  test('buscar con texto vacio no llama al canal', () async {
    responder((MethodCall llamada) async {
      fail('no deberia llamarse al canal');
    });
    expect(await FuenteAnime.buscar('   '), isEmpty);
  });

  test('un error del canal se convierte en ErrorFuente', () async {
    responder((MethodCall llamada) async => '{"ok": false, "error": "Sin conexion"}');
    await expectLater(FuenteAnime.populares(), throwsA(isA<ErrorFuente>()));
  });

  test('resolver trae la url y sus cabeceras', () async {
    responder((MethodCall llamada) async {
      expect(llamada.method, 'resolver');
      return '{"ok": true, "url": "https://cdn/x.mp4", '
          '"cabeceras": {"Referer": "https://streamtape.com/"}}';
    });

    final StreamResuelto resuelto = await FuenteAnime.resolver('https://streamtape.com/e/abc');

    expect(resuelto.url, 'https://cdn/x.mp4');
    expect(resuelto.cabeceras['Referer'], 'https://streamtape.com/');
  });

  test('episodios y servidores se convierten a sus modelos', () async {
    responder((MethodCall llamada) async => switch (llamada.method) {
          'episodios' => '{"ok": true, "episodios": ['
              '{"numero": "1", "url": "https://jkanime.net/x/1/"}]}',
          'servidores' => '{"ok": true, "servidores": ['
              '{"nombre": "Streamtape", "idioma": "Japones subtitulado", '
              '"url": "https://streamtape.com/e/x"}]}',
          _ => '{"ok": false, "error": "inesperado"}',
        });

    final List<EpisodioFuente> episodios = await FuenteAnime.episodios('https://jkanime.net/x/');
    expect(episodios.single.numero, '1');
    expect(episodios.single.url, 'https://jkanime.net/x/1/');

    final List<ServidorFuente> servidores = await FuenteAnime.servidores('https://jkanime.net/x/1/');
    expect(servidores.single.nombre, 'Streamtape');
    expect(servidores.single.idioma, 'Japones subtitulado');
  });
}
