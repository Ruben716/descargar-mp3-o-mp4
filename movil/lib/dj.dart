import 'dart:math';

import 'nucleo.dart';
import 'ritmos.dart';

/// Una cancion tal como la ve el DJ: lo minimo para ordenar.
class PistaDj {
  const PistaDj(this.id, this.artista, this.rasgos);

  final String id;
  final String artista;

  /// null si aun no se ha analizado: entra igual, con coste neutro.
  final Rasgos? rasgos;
}

/// Como se ordena una mezcla.
enum ModoDj {
  /// Cada cancion encaja con la anterior en tempo y energia.
  flujo('Fluida', 'Cada cancion encaja con la anterior'),

  /// De lo mas suave a lo mas movido.
  subir('Subiendo', 'De menos a mas'),

  /// De lo mas movido a lo mas suave.
  bajar('Bajando', 'De mas a menos'),

  /// Sube hasta el 70 % y luego afloja, como una fiesta.
  arco('Fiesta', 'Sube, llega arriba y afloja al final');

  const ModoDj(this.titulo, this.pista);

  final String titulo;
  final String pista;
}

/// El DJ automatico: ordena una cola para que fluya.
///
/// Todo son funciones puras. El coste de pasar de una cancion a otra mezcla
/// el tempo (perdonando el doble y la mitad, como hace un DJ), la energia, la
/// tonalidad si se sabe y no repetir artista.
class Dj {
  Dj._();

  /// Las mas largas (sesiones, episodios) no entran en una mezcla.
  static const Duration largoMaximo = Duration(minutes: 12);

  /// Distancia de tempo en octavas, perdonando el doble y la mitad.
  ///
  /// 87 y 174 son la misma cancion para un DJ: se mezclan a medio tiempo.
  static double distanciaTempo(double a, double b) {
    final double x = log(b / a) / ln2;
    return <double>[x.abs(), (x - 1).abs() + 0.03, (x + 1).abs() + 0.03].reduce(min);
  }

  /// 0 si cuadran (menos de un 2 %), 1 si hay mas de un 6 % de diferencia.
  static double costeTempo(Rasgos? a, Rasgos? b) {
    if (a == null || b == null || !a.conPulso || !b.conPulso) return 0.5;
    final double d = distanciaTempo(a.bpm!, b.bpm!);
    return min(1, pow(d / 0.085, 2).toDouble());
  }

  /// Rueda Camelot: misma casilla, vecinas (+-1) o relativa (A<->B) suenan bien.
  static double costeTono(String? a, String? b) {
    final int? na = a == null || a.length < 2 ? null : int.tryParse(a.substring(0, a.length - 1));
    final int? nb = b == null || b.length < 2 ? null : int.tryParse(b.substring(0, b.length - 1));
    if (na == null || nb == null) return 0.3;
    final bool mismaLetra = a![a.length - 1] == b![b.length - 1];
    final int salto = min((na - nb).abs(), 12 - (na - nb).abs());
    if (salto == 0) return mismaLetra ? 0 : 0.1;
    if (salto == 1 && mismaLetra) return 0.1;
    if (salto == 2 && mismaLetra) return 0.4;
    return 1;
  }

  /// Cuanto se diferencian dos canciones, de 0 (iguales) a 1, en tempo y en
  /// energia bruta. Sin analizar, 0,5: ni se parecen ni dejan de parecerse.
  static double diferencia(Rasgos? a, Rasgos? b) {
    if (a == null || b == null) return 0.5;
    return (0.6 * costeTempo(a, b) + 0.4 * (a.energia - b.energia).abs()).clamp(0.0, 1.0);
  }

  /// Percentil de energia de cada cancion dentro de la lista (0..1).
  static Map<String, double> percentiles(List<PistaDj> pistas) {
    final List<PistaDj> medidas = pistas.where((PistaDj p) => p.rasgos != null).toList()
      ..sort((PistaDj a, PistaDj b) => a.rasgos!.energia.compareTo(b.rasgos!.energia));
    final int n = medidas.length;
    return <String, double>{
      for (int i = 0; i < n; i++) medidas[i].id: n == 1 ? 0.5 : i / (n - 1),
    };
  }

  /// Ordena [pistas] para que fluyan. [primera] (si se da) va delante.
  ///
  /// flujo: vecino mas cercano + 2-opt. subir/bajar: en cada paso compiten
  /// solo las [ventana] de menos (o mas) energia que quedan, y gana la que
  /// mejor encaja en tempo y tono: la curva se respeta y el tempo fluye.
  /// arco: una subida con dos de cada tres y una bajada con el resto.
  static List<PistaDj> ordenar(
    List<PistaDj> pistas, {
    ModoDj modo = ModoDj.flujo,
    String? primera,
    Random? azar,
    int ventana = 5,
  }) {
    if (pistas.length <= 2) {
      final List<PistaDj> pocas = List<PistaDj>.of(pistas);
      final int i = pocas.indexWhere((PistaDj p) => p.id == primera);
      if (i > 0) pocas.insert(0, pocas.removeAt(i));
      return pocas;
    }
    final Random suerte = azar ?? Random();
    final Map<String, double> e = percentiles(pistas);
    double energia(PistaDj p) => e[p.id] ?? 0.5;
    double coste(PistaDj a, PistaDj b) =>
        0.45 * costeTempo(a.rasgos, b.rasgos) +
        0.35 * (energia(a) - energia(b)).abs() +
        0.12 * costeTono(a.rasgos?.camelot, b.rasgos?.camelot) +
        0.08 * (a.artista.isNotEmpty && a.artista == b.artista ? 1 : 0);

    if (modo == ModoDj.arco) {
      final List<PistaDj> porEnergia = List<PistaDj>.of(pistas)
        ..sort((PistaDj a, PistaDj b) => energia(a).compareTo(energia(b)));
      final Set<String> reservadas = <String>{
        for (int i = 0; i < porEnergia.length - 2; i++)
          if (i % 3 == 1 && porEnergia[i].id != primera) porEnergia[i].id,
      };
      final List<PistaDj> bajada = porEnergia.where((PistaDj p) => reservadas.contains(p.id)).toList();
      final List<PistaDj> subida = porEnergia.where((PistaDj p) => !reservadas.contains(p.id)).toList();
      final List<PistaDj> primero = _voraz(subida, coste, energia, ModoDj.subir, primera, suerte, ventana);
      if (bajada.isEmpty) return primero;
      final List<PistaDj> despues = _voraz(
        bajada,
        coste,
        energia,
        ModoDj.bajar,
        null,
        suerte,
        ventana,
        desde: primero.last,
      );
      return <PistaDj>[...primero, ...despues];
    }
    final List<PistaDj> salida = _voraz(pistas, coste, energia, modo, primera, suerte, ventana);
    if (modo == ModoDj.flujo) _dosOpt(salida, coste);
    return salida;
  }

  static List<PistaDj> _voraz(
    List<PistaDj> pistas,
    double Function(PistaDj, PistaDj) coste,
    double Function(PistaDj) energia,
    ModoDj modo,
    String? primera,
    Random suerte,
    int ventana, {
    PistaDj? desde,
  }) {
    final List<PistaDj> quedan = List<PistaDj>.of(pistas);
    final List<PistaDj> salida = <PistaDj>[];
    // Las que tocan ahora segun la curva: todas en flujo, las de los extremos si no.
    Iterable<PistaDj> turno() => switch (modo) {
          ModoDj.subir => (List<PistaDj>.of(quedan)
                ..sort((PistaDj a, PistaDj b) => energia(a).compareTo(energia(b))))
              .take(ventana),
          ModoDj.bajar => (List<PistaDj>.of(quedan)
                ..sort((PistaDj a, PistaDj b) => energia(b).compareTo(energia(a))))
              .take(ventana),
          _ => quedan,
        };
    PistaDj? actual = desde;
    if (primera != null) {
      final int i = quedan.indexWhere((PistaDj p) => p.id == primera);
      if (i >= 0) {
        actual = quedan.removeAt(i);
        salida.add(actual);
      }
    }
    if (actual == null) {
      // Sin nada antes, se empieza por la mas suave de las que tocan.
      actual = turno().reduce((PistaDj a, PistaDj b) => energia(a) <= energia(b) ? a : b);
      quedan.remove(actual);
      salida.add(actual);
    }
    while (quedan.isNotEmpty) {
      PistaDj? mejor;
      double mejorCoste = double.infinity;
      for (final PistaDj c in turno()) {
        final double v = coste(actual!, c) + suerte.nextDouble() * 0.02;
        if (v < mejorCoste) {
          mejorCoste = v;
          mejor = c;
        }
      }
      actual = mejor!;
      quedan.remove(actual);
      salida.add(actual);
    }
    return salida;
  }

  /// Mejora local: dar la vuelta a un tramo si las dos uniones salen mas baratas.
  /// La primera no se mueve. Solo en flujo, donde el coste es simetrico.
  static void _dosOpt(List<PistaDj> ruta, double Function(PistaDj, PistaDj) coste, {int vueltas = 4}) {
    final int n = ruta.length;
    for (int vuelta = 0; vuelta < vueltas; vuelta++) {
      bool mejoro = false;
      for (int i = 1; i < n - 1; i++) {
        for (int j = i + 1; j < n; j++) {
          final double antes = coste(ruta[i - 1], ruta[i]) + (j + 1 < n ? coste(ruta[j], ruta[j + 1]) : 0);
          final double despues = coste(ruta[i - 1], ruta[j]) + (j + 1 < n ? coste(ruta[i], ruta[j + 1]) : 0);
          if (despues + 1e-9 < antes) {
            final List<PistaDj> tramo = ruta.sublist(i, j + 1).reversed.toList();
            ruta.setRange(i, j + 1, tramo);
            mejoro = true;
          }
        }
      }
      if (!mejoro) return;
    }
  }

  /// Coste total de una ruta, para comparar en las pruebas.
  static double costeRuta(List<PistaDj> ruta) {
    final Map<String, double> e = percentiles(ruta);
    double t = 0;
    for (int i = 1; i < ruta.length; i++) {
      t += costeTempo(ruta[i - 1].rasgos, ruta[i].rasgos) +
          ((e[ruta[i - 1].id] ?? .5) - (e[ruta[i].id] ?? .5)).abs();
    }
    return t;
  }

  /// Lo mismo que [ordenar], pero con canciones de la biblioteca.
  ///
  /// Las de mas de [largoMaximo] (sesiones, episodios) no entran: una mezcla
  /// no se hace con un podcast en medio. Si solo hay de esas, se devuelven tal
  /// cual, para no dejar a nadie sin musica.
  static List<Elemento> ordenarElementos(
    List<Elemento> elementos, {
    required Rasgos? Function(String uri) rasgos,
    ModoDj modo = ModoDj.flujo,
    String? primera,
    Random? azar,
  }) {
    final List<Elemento> cortas = <Elemento>[
      for (final Elemento e in elementos)
        if (e.duracion <= largoMaximo.inSeconds || e.uri == primera) e,
    ];
    if (cortas.isEmpty) return List<Elemento>.of(elementos);
    // Por URI, para que dos copias de la misma cancion no se pisen.
    final Map<String, Elemento> porUri = <String, Elemento>{for (final Elemento e in cortas) e.uri: e};
    final List<PistaDj> pistas = <PistaDj>[
      for (final Elemento e in porUri.values) PistaDj(e.uri, e.artista.toLowerCase(), rasgos(e.uri)),
    ];
    return <Elemento>[
      for (final PistaDj p in ordenar(pistas, modo: modo, primera: primera, azar: azar)) porUri[p.id]!,
    ];
  }
}

/// Donde cortar una cancion y desde donde empezar para el fundido al compas.
class CorteAlCompas {
  const CorteAlCompas({
    required this.inicio,
    required this.fin,
    required this.salida,
    required this.entrada,
  });

  /// Desde donde suena (primer golpe, con un pelin de margen).
  final Duration inicio;

  /// Hasta donde suena: justo donde caeria el pulso siguiente al ultimo.
  final Duration fin;

  /// Cuanto dura la bajada final (multiplo de 4 pulsos) y la subida inicial (1 compas).
  final Duration salida;
  final Duration entrada;

  static const Duration margenAtaque = Duration(milliseconds: 20);

  /// null si la cancion no tiene pulso fiable o es demasiado corta: entonces
  /// se usa el fundido de siempre.
  static CorteAlCompas? calcular(Rasgos r, {required Duration fundido, required Duration total}) {
    final double? periodo = r.periodoMs;
    if (periodo == null || r.pulsoInicioMs == null || r.pulsoFinMs == null) return null;
    final int inicioMs = max(0, r.pulsoInicioMs! - margenAtaque.inMilliseconds);
    final int finMs = total > Duration.zero
        ? min(total.inMilliseconds, (r.pulsoFinMs! + periodo).round())
        : (r.pulsoFinMs! + periodo).round();
    if (finMs - inicioMs < 30000) return null;
    final int pulsos = fundido <= Duration.zero ? 0 : max(4, (fundido.inMilliseconds / periodo / 4).round() * 4);
    return CorteAlCompas(
      inicio: Duration(milliseconds: inicioMs),
      fin: Duration(milliseconds: finMs),
      salida: Duration(milliseconds: (pulsos * periodo).round()),
      entrada: Duration(milliseconds: fundido <= Duration.zero ? 0 : (4 * periodo).round()),
    );
  }
}
