import 'package:descargador_movil/descargas_inteligentes.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

Resultado _r(String video) => Resultado(
      titulo: 'Tema $video',
      autor: 'Artista',
      duracion: 200,
      url: 'https://www.youtube.com/watch?v=$video',
    );

BajadaInteligente _b(String uri, int semana) =>
    BajadaInteligente(url: 'https://www.youtube.com/watch?v=$uri', uri: uri, semana: semana);

void main() {
  test('se bajan las primeras que faltan, sin lo que ya tienes ni lo ya bajado', () {
    final List<Resultado> pistas = <Resultado>[_r('a'), _r('b'), _r('c'), _r('d'), _r('e')];
    final List<Resultado> elegidas = DescargasInteligentes.queBajar(
      pistas,
      tengo: <String>{'a'},
      yaBajadas: <String>{'https://www.youtube.com/watch?v=b'},
      faltan: 2,
    );
    expect(elegidas.map((Resultado r) => r.url), <String>[
      'https://www.youtube.com/watch?v=c',
      'https://www.youtube.com/watch?v=d',
    ]);
    expect(DescargasInteligentes.queBajar(pistas, tengo: const <String>{}, yaBajadas: const <String>{}, faltan: 0),
        isEmpty);
  });

  test('al renovar solo se borra lo de antes que no tocaste; lo tocado pasa a ser tuyo', () {
    final ({List<BajadaInteligente> borrar, List<BajadaInteligente> tuyas}) r = DescargasInteligentes.repasar(
      <BajadaInteligente>[
        _b('sin-tocar', 9),
        _b('escuchada', 9),
        _b('me-gusta', 9),
        _b('en-lista', 9),
        _b('de-esta-semana', 10),
      ],
      semana: 10,
      escuchadas: <String>{'escuchada'},
      favoritas: <String>{'me-gusta'},
      enOtrasListas: <String>{'en-lista'},
    );
    expect(r.borrar.map((BajadaInteligente b) => b.uri), <String>['sin-tocar']);
    expect(r.tuyas.map((BajadaInteligente b) => b.uri), <String>['escuchada', 'me-gusta', 'en-lista']);
  });
}
