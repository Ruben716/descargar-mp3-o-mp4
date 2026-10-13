/// Piezas de Inicio que tambien usa Explorar: estantes, tarjetas, la rejilla
/// de accesos y la pastilla de «Pidele a Tumbao».
///
/// Ninguna pide nada al construirse salvo las portadas de lo que ensenia, y
/// solo de canciones de la biblioteca (ver la prueba de las 3 caratulas).
library;

import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'hecho_para_ti.dart';
import 'nucleo.dart';
import 'pantalla_pidele.dart';
import 'pantalla_radio.dart';
import 'portadas.dart';
import 'radio_mundial.dart';
import 'tema.dart';

/// El titulo de un estante, con «Ver todo» si lleva a algun sitio.
class TituloEstante extends StatelessWidget {
  const TituloEstante({required this.texto, this.alVerTodo, super.key});

  final String texto;
  final VoidCallback? alVerTodo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: ConstrainedBox(
        // Con o sin boton, todos los titulos ocupan lo mismo.
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                texto,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ),
            if (alVerTodo != null) TextButton(onPressed: alVerTodo, child: const Text('Ver todo')),
          ],
        ),
      ),
    );
  }
}

/// Un estante: titulo, «Ver todo» y un carrusel que se construye a demanda.
class Estante extends StatelessWidget {
  const Estante({
    required this.titulo,
    required this.cuantos,
    required this.construir,
    this.alVerTodo,
    this.alto = 186,
    this.pie,
    super.key,
  });

  final String titulo;
  final int cuantos;
  final IndexedWidgetBuilder construir;
  final VoidCallback? alVerTodo;

  /// Lo que mide el carrusel: el de las tarjetas que lleva dentro.
  final double alto;

  /// Algo debajo del carrusel, como «Encontrar mas sin perdida».
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TituloEstante(texto: titulo, alVerTodo: alVerTodo),
        SizedBox(
          height: alto,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: cuantos,
            itemBuilder: construir,
          ),
        ),
        if (pie != null) Padding(padding: const EdgeInsets.fromLTRB(12, 2, 20, 0), child: pie),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Tarjeta cuadrada de un carrusel.
class TarjetaEstante extends StatelessWidget {
  const TarjetaEstante({
    required this.subtitulo,
    required this.alPulsar,
    this.elemento,
    this.titulo,
    this.portada,
    this.sello,
    this.progreso,
    this.ancho = 130,
    this.resaltada = false,
    super.key,
  });

  final Elemento? elemento;
  final String? titulo;
  final String subtitulo;
  final VoidCallback alPulsar;

  /// En lugar de la portada de [elemento] (un mosaico, un logo...).
  final Widget? portada;

  /// Debajo del subtitulo: el sello de calidad, por ejemplo.
  final Widget? sello;

  /// De 0 a 1, lo que se lleva oido. null si no viene al caso.
  final double? progreso;
  final double ancho;

  /// Lo que suena ahora: el subtitulo va en el color de la app.
  final bool resaltada;

  @override
  Widget build(BuildContext context) {
    final Elemento? pista = elemento;
    final double? avance = progreso;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: alPulsar,
        child: SizedBox(
          width: ancho,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              portada ??
                  (pista == null
                      ? CuadroIcono(icono: Icons.queue_music_rounded, lado: ancho)
                      : PortadaLocal(elemento: pista, lado: ancho, radio: 18)),
              if (avance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: avance.clamp(0, 1).toDouble(),
                      minHeight: 3,
                      color: Tema.acento,
                      backgroundColor: Tema.pista,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                titulo ?? pista?.etiqueta ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: resaltada ? Tema.acento : Tema.textoTenue, fontSize: 11),
              ),
              if (sello != null) Padding(padding: const EdgeInsets.only(top: 4), child: sello),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un cuadro con el degradado de marca y un icono, cuando no hay portada.
class CuadroIcono extends StatelessWidget {
  const CuadroIcono({required this.icono, required this.lado, this.radio = 18, super.key});

  final IconData icono;
  final double lado;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(gradient: Tema.degradado, borderRadius: BorderRadius.circular(radio)),
      child: Icon(icono, color: const Color(0x73040814), size: lado * 0.32),
    );
  }
}

/// Cuatro portadas en cuadricula, como las listas de Spotify.
///
/// Con menos de cuatro canciones distintas basta la primera: un mosaico con
/// huecos se ve roto. Solo pide portadas de canciones de la biblioteca.
class MosaicoPortadas extends StatelessWidget {
  const MosaicoPortadas({required this.pistas, required this.lado, this.radio = 18, super.key});

  final List<Elemento> pistas;
  final double lado;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final List<Elemento> distintas = <Elemento>[];
    final Set<String> vistas = <String>{};
    for (final Elemento p in pistas) {
      if (vistas.add(p.uri)) distintas.add(p);
      if (distintas.length == 4) break;
    }
    if (distintas.isEmpty) return CuadroIcono(icono: Icons.queue_music_rounded, lado: lado, radio: radio);
    if (distintas.length < 4) return PortadaLocal(elemento: distintas.first, lado: lado, radio: radio);
    final double mitad = lado / 2;
    Widget cuarto(int i) => PortadaLocal(elemento: distintas[i], lado: mitad, radio: 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(
        width: lado,
        height: lado,
        child: Column(
          children: <Widget>[
            Row(children: <Widget>[cuarto(0), cuarto(1)]),
            Row(children: <Widget>[cuarto(2), cuarto(3)]),
          ],
        ),
      ),
    );
  }
}

/// El icono y el color de cada clase de mix.
extension AspectoMix on ClaseMix {
  IconData get icono => switch (this) {
        ClaseMix.diario => Icons.today_rounded,
        ClaseMix.redescubre => Icons.history_rounded,
        ClaseMix.sinEscuchar => Icons.new_releases_outlined,
        ClaseMix.repeticion => Icons.repeat_rounded,
        ClaseMix.artista => Icons.person_rounded,
        ClaseMix.moverse => Icons.bolt_rounded,
        ClaseMix.tranqui => Icons.nightlight_round,
        ClaseMix.concentrarte => Icons.center_focus_strong_rounded,
        ClaseMix.sesionDj => Icons.headphones_rounded,
      };

  Color get color => switch (this) {
        ClaseMix.diario || ClaseMix.repeticion || ClaseMix.concentrarte => Tema.acento,
        ClaseMix.redescubre || ClaseMix.moverse || ClaseMix.sesionDj => Tema.acentoHielo,
        ClaseMix.sinEscuchar || ClaseMix.artista || ClaseMix.tranqui => Tema.azulProfundo,
      };
}

/// La portada de un mix: su mosaico con un velo de su color y su icono.
class PortadaMix extends StatelessWidget {
  const PortadaMix({required this.mix, required this.lado, this.radio = 18, super.key});

  final Mix mix;
  final double lado;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final Color color = mix.clase.color;
    return SizedBox(
      width: lado,
      height: lado,
      child: Stack(
        children: <Widget>[
          MosaicoPortadas(pistas: mix.pistas, lado: lado, radio: radio),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radio),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[color.withValues(alpha: 0), Tema.fondo.withValues(alpha: 0.85)],
                    stops: const <double>[0.45, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(mix.clase.icono, size: lado < 100 ? 12 : 16, color: Tema.tinta),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un mix en un estante.
class TarjetaMix extends StatelessWidget {
  const TarjetaMix({required this.mix, required this.alPulsar, super.key});

  /// Lo que ocupa: la portada, el titulo y dos lineas de subtitulo.
  static const double alto = 214;

  final Mix mix;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: alPulsar,
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PortadaMix(mix: mix, lado: 150),
              const SizedBox(height: 8),
              Text(
                mix.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                mix.subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tema.textoTenue, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una ficha de la rejilla de accesos rapidos.
class AccesoRapido {
  const AccesoRapido({required this.titulo, required this.portada, required this.alPulsar, this.activo = false});

  final String titulo;

  /// Lo de la izquierda, de 56 px: un mosaico, un logo o un icono.
  final Widget portada;
  final VoidCallback alPulsar;

  /// Lo que suena ahora (la radio en vivo): el titulo va en el acento.
  final bool activo;
}

/// Rejilla de accesos de dos columnas, como la de arriba de Spotify.
///
/// Sin fichas no ocupa nada: las vacias ya las quita quien la arma.
class RejillaAccesos extends StatelessWidget {
  const RejillaAccesos({required this.accesos, super.key});

  /// Lo que mide cada ficha.
  static const double alto = 56;

  final List<AccesoRapido> accesos;

  @override
  Widget build(BuildContext context) {
    if (accesos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < accesos.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                children: <Widget>[
                  Expanded(child: _Ficha(acceso: accesos[i])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < accesos.length ? _Ficha(acceso: accesos[i + 1]) : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.acceso});

  final AccesoRapido acceso;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tema.superficieAlta,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: acceso.alPulsar,
        child: SizedBox(
          height: RejillaAccesos.alto,
          child: Row(
            children: <Widget>[
              SizedBox.square(dimension: RejillaAccesos.alto, child: acceso.portada),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  acceso.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.2,
                    color: acceso.activo ? Tema.acento : Tema.texto,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre «Pidele a Tumbao», con [frase] ya escrita si se toco un ejemplo.
void abrirPidele(BuildContext context, {String frase = ''}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PantallaPidele(frase: frase)),
  );
}

/// La entrada a «Pidele a Tumbao»: parece un campo pero no lo es.
///
/// Es un boton con forma de campo a proposito: un TextField de verdad en
/// Inicio sacaria el teclado sin querer y se confundiria con el de Descargar.
/// Debajo, unos ejemplos que cambian segun la hora y se pueden tocar.
class PastillaPidele extends StatelessWidget {
  const PastillaPidele({this.hora, this.conEjemplos = true, super.key});

  /// La hora con que se eligen los ejemplos; null es la de ahora.
  final int? hora;
  final bool conEjemplos;

  /// Lo que se le puede pedir a esta [hora] (0 a 23).
  static List<String> ejemplos(int hora) {
    if (hora < 6) {
      return const <String>['algo tranquilo para dormir', 'radio de jazz en FLAC', 'lo que baje este mes'];
    }
    if (hora < 12) {
      return const <String>['algo con energia para empezar', 'mis favoritas', 'lo que baje este mes'];
    }
    if (hora < 16) {
      return const <String>['salsa para cocinar', 'algo para concentrarme una hora', 'mis favoritas'];
    }
    if (hora < 21) {
      return const <String>['algo para moverse', 'lo que baje este mes', 'radio de salsa'];
    }
    return const <String>['algo tranquilo de una hora', 'radio de jazz en FLAC', 'mis favoritas'];
  }

  @override
  Widget build(BuildContext context) {
    final List<String> frases = ejemplos(hora ?? DateTime.now().hour);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: Tema.superficie,
            shape: const StadiumBorder(side: BorderSide(color: Tema.contorno)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => abrirPidele(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome_rounded, color: Tema.acento, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Pidele a Tumbao',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '«${frases.first}»',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: Tema.textoTenue, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (conEjemplos) ...<Widget>[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String frase in frases)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Tema.superficie,
                        label: Text(frase, style: const TextStyle(fontSize: 12)),
                        onPressed: () => abrirPidele(context, frase: frase),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta ancha de una fila, como la de «Radio en vivo».
class TarjetaFila extends StatelessWidget {
  const TarjetaFila({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.alPulsar,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alPulsar,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(icono, color: Tema.acento, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una emisora guardada, que se pone en vivo al tocarla.
class TarjetaEmisora extends StatelessWidget {
  const TarjetaEmisora({required this.emisora, super.key});

  static const double alto = 150;

  final EstacionRadio emisora;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final bool sonando = estado.actual?.enVivo?.url == emisora.url;
    return TarjetaEstante(
      ancho: 96,
      portada: LogoEmisora(emisora: emisora, lado: 96),
      titulo: emisora.nombre,
      subtitulo: sonando ? 'Sonando' : emisora.sello,
      resaltada: sonando,
      alPulsar: () => estado.reproducirEmisora(emisora),
    );
  }
}

/// Cuando llego una descarga: «hoy», «ayer», «hace 3 dias»... o null si no se
/// sabe (fecha 0) o hace mas de una semana, que ya no dice nada.
String? cuandoLlego(int fechaSegundos, DateTime ahora) {
  if (fechaSegundos <= 0) return null;
  final DateTime llego = DateTime.fromMillisecondsSinceEpoch(fechaSegundos * 1000);
  final int dias = DateTime(ahora.year, ahora.month, ahora.day)
      .difference(DateTime(llego.year, llego.month, llego.day))
      .inDays;
  if (dias < 0) return null;
  if (dias == 0) return 'hoy';
  if (dias == 1) return 'ayer';
  if (dias < 7) return 'hace $dias dias';
  return null;
}
