import 'package:descargador_movil/descargas_inteligentes.dart';
import 'package:descargador_movil/estado_reproductor.dart';
import 'package:descargador_movil/ritmos.dart';
import 'package:descargador_movil/hecho_para_ti.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

Resultado _r(String video) => Resultado(
      titulo: 'Tema $video',
      autor: 'Artista',
      duracion: 200,
      url: 'https://www.youtube.com/watch?v=$video',
    );

BajadaInteligente _b(String uri, int tanda) =>
    BajadaInteligente(url: 'https://www.youtube.com/watch?v=$uri', uri: uri, mezcla: 'm', tanda: tanda);

Elemento _cancion(String artista, String tema, {String? uri}) => Elemento(
      nombre: '$artista - $tema.opus',
      uri: uri ?? 'content://$artista/$tema',
      duracion: 200,
      tamano: 1,
      audio: true,
    );

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
        _b('de-esta-tanda', 10),
      ],
      desde: 10,
      escuchadas: <String>{'escuchada'},
      favoritas: <String>{'me-gusta'},
      enOtrasListas: <String>{'en-lista'},
    );
    expect(r.borrar.map((BajadaInteligente b) => b.uri), <String>['sin-tocar']);
    expect(r.tuyas.map((BajadaInteligente b) => b.uri), <String>['escuchada', 'me-gusta', 'en-lista']);
  });

  test('cada mezcla se renueva cuando le toca, segun sus dias', () {
    final DateTime ahora = DateTime(2026, 10, 18, 12);
    const MezclaInteligente nunca = MezclaInteligente(id: 'a', nombre: 'A', tipo: TipoMezcla.paraTi);
    expect(nunca.tocaRenovar(ahora), isTrue, reason: 'sin bajar nunca, ya');
    final MezclaInteligente ayer = nunca.copiar(renovada: ahora.subtract(const Duration(hours: 25)).millisecondsSinceEpoch);
    expect(ayer.copiar(dias: 1).tocaRenovar(ahora), isTrue);
    expect(ayer.copiar(dias: 3).tocaRenovar(ahora), isFalse);
    expect(DescargasInteligentes.textoDias(1), 'Cada dia');
    expect(DescargasInteligentes.textoDias(3), 'Cada 3 dias');
    expect(DescargasInteligentes.textoDias(14), 'Cada 2 semanas');
  });

  group('semillas', () {
    final List<Elemento> canciones = <Elemento>[
      _cancion('Celia Cruz', 'Quimbara'),
      _cancion('Celia Cruz', 'La Vida Es Un Carnaval'),
      _cancion('Bad Bunny', 'Titi Me Pregunto'),
      _cancion('Grupo 5', 'Motor y Motivo'),
    ];
    const Map<String, Escucha> escuchas = <String, Escucha>{};

    test('por genero: tus canciones de ese genero y, si faltan, artistas conocidos', () {
      const MezclaInteligente salsa =
          MezclaInteligente(id: 'genero:salsa', nombre: 'Mezcla de salsa', tipo: TipoMezcla.genero, clave: 'salsa');
      final List<({String artista, String tema, String? video})> s = DescargasInteligentes.semillasDe(
        salsa,
        canciones,
        escuchas,
        <String, String>{'content://Celia Cruz/Quimbara': 'q1'},
      );
      expect(s, hasLength(DescargasInteligentes.semillas));
      expect(s.take(2).map((({String artista, String tema, String? video}) x) => x.artista).toSet(), <String>{'Celia Cruz'},
          reason: 'primero lo tuyo de salsa; nada de Bad Bunny ni de Grupo 5');
      expect(s.where((({String artista, String tema, String? video}) x) => x.tema == 'Quimbara').single.video, 'q1');
      expect(s.skip(2).every((({String artista, String tema, String? video}) x) => x.tema.isEmpty && x.video == null), isTrue,
          reason: 'el resto, artistas conocidos de salsa que se buscaran');
    });

    test('por artista: sus canciones, o el artista a secas si no tienes', () {
      const MezclaInteligente bad =
          MezclaInteligente(id: 'artista:bad bunny', nombre: 'Radio de Bad Bunny', tipo: TipoMezcla.artista, clave: 'Bad Bunny');
      expect(DescargasInteligentes.semillasDe(bad, canciones, escuchas, const <String, String>{}).single.tema,
          'Titi Me Pregunto');
      const MezclaInteligente otro =
          MezclaInteligente(id: 'artista:x', nombre: 'Radio de Romeo Santos', tipo: TipoMezcla.artista, clave: 'Romeo Santos');
      expect(DescargasInteligentes.semillasDe(otro, canciones, escuchas, const <String, String>{}).single,
          (artista: 'Romeo Santos', tema: '', video: null));
    });

    test('cada vuelta trae otras semillas, y la misma vuelta las mismas', () {
      final List<Elemento> muchas = <Elemento>[for (int i = 0; i < 12; i++) _cancion('Celia Cruz', 'Tema $i')];
      const MezclaInteligente salsa =
          MezclaInteligente(id: 'genero:salsa', nombre: 'Mezcla de salsa', tipo: TipoMezcla.genero, clave: 'salsa');
      List<String> temas(int vuelta) => <String>[
            for (final ({String artista, String tema, String? video}) s in DescargasInteligentes.semillasDe(
                salsa.copiar(vueltas: vuelta), muchas, escuchas, const <String, String>{}))
              s.tema,
          ];
      expect(temas(1), temas(1));
      expect(<String>{for (int v = 1; v <= 6; v++) temas(v).join()}.length, greaterThan(1));
    });
  });

  test('una mezcla nueva no repite nombre ni id', () {
    final DescargasInteligentes d = DescargasInteligentes.instancia..reiniciar();
    final MezclaInteligente a = d.nueva(TipoMezcla.genero, clave: 'salsa');
    expect((a.id, a.nombre), ('genero:salsa', 'Mezcla de salsa'));
    expect(a.cuantas, 20);
    expect(a.dias, 7);
  });

  test('lo de artistas saltados va al final, y con 3 saltos ya no se baja', () {
    Resultado de(String video, String artista) => Resultado(
        titulo: 'Tema $video', autor: '$artista - Topic', duracion: 200, url: 'https://www.youtube.com/watch?v=$video');
    final List<Resultado> candidatas = <Resultado>[
      de('a', 'Saltado Una Vez'),
      de('b', 'Nunca Saltado'),
      de('c', 'Saltado Mucho'),
      de('d', 'Otro'),
    ];
    final List<Resultado> orden = DescargasInteligentes.segunSaltos(
      candidatas,
      <String, int>{'saltado una vez': 1, 'saltado mucho': DescargasInteligentes.saltosParaQuitar},
    );
    expect(orden.map((Resultado r) => r.url.substring(r.url.length - 1)), <String>['b', 'd', 'a']);
    expect(DescargasInteligentes.segunSaltos(candidatas, const <String, int>{}), same(candidatas));
  });

  test('saltar es pasar a otra antes de 30 s, no que una corta acabe sola', () {
    expect(EstadoReproductor.esSalto(const Duration(seconds: 8), 210), isTrue);
    expect(EstadoReproductor.esSalto(const Duration(seconds: 45), 210), isFalse, reason: 'ya la oyo');
    expect(EstadoReproductor.esSalto(Duration.zero, 210), isFalse, reason: 'ni empezo');
    expect(EstadoReproductor.esSalto(const Duration(seconds: 24), 25), isFalse, reason: 'acabo sola');
  });

  test('el limite de espacio dice cuantas caben aun', () {
    const int mb = 1024 * 1024;
    final List<BajadaInteligente> bajadas = <BajadaInteligente>[_b('u1', 1), _b('u2', 1), _b('u3', 1)];
    expect(DescargasInteligentes.cabenAun(limiteMb: 0, bajadas: bajadas, pesos: const <String, int>{}), isNull);
    // Dos de 5 MB conocidas y una sin peso aun (cuenta como la media): 15 MB de 100.
    expect(
      DescargasInteligentes.cabenAun(limiteMb: 100, bajadas: bajadas, pesos: <String, int>{'u1': 5 * mb, 'u2': 5 * mb}),
      17,
    );
    expect(DescargasInteligentes.cabenAun(limiteMb: 10, bajadas: bajadas, pesos: <String, int>{'u1': 5 * mb, 'u2': 5 * mb}),
        0);
    expect(DescargasInteligentes.textoLimite(0), 'Sin limite');
    expect(DescargasInteligentes.textoLimite(2048), '2 GB');
  });

  test('el modo viaje junta canciones hasta llenar las horas', () {
    final List<Resultado> candidatas = <Resultado>[
      for (int i = 0; i < 40; i++)
        Resultado(titulo: 'T$i', autor: 'A', duracion: i == 0 ? 0 : 240, url: 'https://www.youtube.com/watch?v=v$i'),
    ];
    final List<Resultado> hora = DescargasInteligentes.paraHoras(candidatas, 1);
    // 210 s de la que no dice + 14 de 240 s = 3570 s; con la siguiente pasa de la hora.
    expect(hora, hasLength(16));
    expect(DescargasInteligentes.paraHoras(candidatas.take(5).toList(), 3), hasLength(5), reason: 'no hay para mas');
  });

  test('por animo: tus canciones de esa energia y tempo, o artistas de sus generos', () {
    final List<Elemento> canciones = <Elemento>[
      _cancion('Fuerte', 'Uno', uri: 'u-fuerte-1'),
      _cancion('Fuerte', 'Dos', uri: 'u-fuerte-2'),
      _cancion('Suave', 'Uno', uri: 'u-suave'),
      _cancion('Lento', 'Uno', uri: 'u-lenta-fuerte'),
    ];
    Rasgos r(double bpm) => Rasgos(bpm: bpm, confianza: 0.9, energia: 0, lufs: -9, pulsoInicioMs: 0, pulsoFinMs: 1000);
    final Map<String, Rasgos> rasgos = <String, Rasgos>{
      'u-fuerte-1': r(128),
      'u-fuerte-2': r(140),
      'u-suave': r(70),
      'u-lenta-fuerte': r(70),
    };
    final Map<String, double> percentiles = <String, double>{
      'u-fuerte-1': 0.9,
      'u-fuerte-2': 0.8,
      'u-suave': 0.1,
      'u-lenta-fuerte': 0.95,
    };
    const MezclaInteligente entrenar =
        MezclaInteligente(id: 'animo:entrenar', nombre: 'Para entrenar', tipo: TipoMezcla.animo, clave: 'entrenar');
    final List<({String artista, String tema, String? video})> s = DescargasInteligentes.semillasDe(
      entrenar,
      canciones,
      const <String, Escucha>{},
      const <String, String>{},
      rasgos: rasgos,
      percentil: (String uri) => percentiles[uri],
    );
    expect(s.where((({String artista, String tema, String? video}) x) => x.tema.isNotEmpty).map(
        (({String artista, String tema, String? video}) x) => x.artista).toSet(), <String>{'Fuerte'},
        reason: 'ni la suave ni la fuerte a 70 BPM');
    expect(s, hasLength(DescargasInteligentes.semillas), reason: 'el resto, artistas de reggaeton, electronica o rock');
    expect(entrenar.origen, 'Animo: Para entrenar');
  });
}
