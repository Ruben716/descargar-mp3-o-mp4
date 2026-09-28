import 'package:flutter/material.dart';

import 'calidad.dart';
import 'hoja_ajustes.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'tema.dart';

/// En una linea, lo que va a salir: asi no hace falta abrir las opciones para
/// saber si se va a bajar en MP3 o en FLAC.
String resumenDescarga(Ajustes a) {
  final List<String> partes = <String>[];
  if (a.soloAudio) {
    final String formato = a.formatoAudio.toUpperCase();
    partes.add(const <String>['flac', 'wav'].contains(a.formatoAudio)
        ? '$formato · sin perdida'
        : '$formato · ${a.bitrate} kb/s');
  } else {
    partes.add(a.calidad == 0 ? 'MP4 · la mejor calidad' : 'MP4 · hasta ${a.calidad}p');
    if (a.subtitulos.isNotEmpty) partes.add('subtitulos ${a.subtitulos}');
  }
  if (a.fragmento.isNotEmpty) partes.add('solo un trozo');
  return partes.join(' · ');
}

/// Lo que se va a descargar, tal y como se ensenia en la hoja.
class QueSeDescarga {
  const QueSeDescarga({
    required this.titulo,
    this.subtitulo = '',
    this.miniatura = '',
    this.cantidad = 1,
    this.origen,
  });

  final String titulo;
  final String subtitulo;
  final String miniatura;

  /// La calidad con la que llegaria el audio, si ya se comprobo.
  final CalidadAudio? origen;

  /// Mas de una cuando se baja una lista entera.
  final int cantidad;
}

/// Pregunta como se quiere lo que se va a descargar, justo antes de bajarlo.
///
/// Antes «Video» y «Musica» estaban fijos arriba de la pantalla, lejos del
/// boton, y era facil bajar un video queriendo la cancion. Aqui la eleccion se
/// hace con lo que se va a descargar delante, y se recuerda para la siguiente.
/// Devuelve los ajustes elegidos, o null si se cierra sin descargar.
Future<Ajustes?> preguntarComoDescargar(
  BuildContext context, {
  required QueSeDescarga que,
  required Ajustes ajustes,
}) =>
    showModalBottomSheet<Ajustes>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => HojaDescarga(que: que, inicial: ajustes),
    );

class HojaDescarga extends StatefulWidget {
  const HojaDescarga({required this.que, required this.inicial, super.key});

  final QueSeDescarga que;
  final Ajustes inicial;

  @override
  State<HojaDescarga> createState() => _HojaDescargaState();
}

class _HojaDescargaState extends State<HojaDescarga> {
  late Ajustes _a = widget.inicial;

  Future<void> _masOpciones() async {
    final Ajustes? nuevos = await showModalBottomSheet<Ajustes>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => HojaAjustes(inicial: _a),
    );
    if (nuevos != null && mounted) setState(() => _a = nuevos);
  }

  /// Si lo elegido no le saca partido al origen, se dice y se ofrece arreglarlo.
  Widget? _consejo() {
    final CalidadAudio? origen = widget.que.origen;
    if (origen == null || !_a.soloAudio) return null;
    final String? texto = consejoDeFormato(origen, _a.formatoAudio);
    if (texto == null) return null;
    // Sin perdida en el origen: FLAC lo guarda entero. Con perdida, lo mejor
    // es no reconvertir, y MP3 es lo que entiende cualquier aparato.
    final String propuesto = origen.sinPerdida ? 'flac' : 'mp3';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lightbulb_outline_rounded, size: 18, color: Colors.white60),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
          TextButton(
            onPressed: () => setState(() => _a = _a.copiar(formatoAudio: propuesto)),
            child: Text('Usar ${propuesto.toUpperCase()}'),
          ),
        ],
      ),
    );
  }

  String get _textoBoton {
    final String que = _a.soloAudio ? 'musica' : 'video';
    final int n = widget.que.cantidad;
    return n > 1 ? 'Descargar las $n en $que' : 'Descargar $que';
  }

  @override
  Widget build(BuildContext context) {
    final QueSeDescarga que = widget.que;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Lo que se va a bajar, para no equivocarse de resultado.
            Row(
              children: <Widget>[
                if (que.miniatura.isNotEmpty) ...<Widget>[
                  PortadaRemota(url: que.miniatura, ancho: 96, alto: 56),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        que.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      if (que.subtitulo.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          que.subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (que.origen case final CalidadAudio origen) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: <Widget>[
                  const Text('Llega en  ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  SelloCalidad(calidad: origen, grande: true),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Text('¿Como lo quieres?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Opcion(
                    icono: Icons.music_note_rounded,
                    titulo: 'Musica',
                    detalle: resumenDescarga(_a.copiar(soloAudio: true)),
                    elegida: _a.soloAudio,
                    alElegir: () => setState(() => _a = _a.copiar(soloAudio: true)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Opcion(
                    icono: Icons.movie_rounded,
                    titulo: 'Video',
                    detalle: resumenDescarga(_a.copiar(soloAudio: false)),
                    elegida: !_a.soloAudio,
                    alElegir: () => setState(() => _a = _a.copiar(soloAudio: false)),
                  ),
                ),
              ],
            ),
            if (_consejo() case final Widget consejo) consejo,
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _masOpciones,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Mas opciones'),
              ),
            ),
            const SizedBox(height: 8),
            BotonDegradado(
              texto: _textoBoton,
              icono: Icons.arrow_downward_rounded,
              alPulsar: () => Navigator.of(context).pop(_a),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una de las dos maneras de bajarlo, grande para acertar con el dedo.
class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.elegida,
    required this.alElegir,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final bool elegida;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: elegida,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: elegida ? Tema.acento.withValues(alpha: 0.16) : Tema.superficieAlta,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: elegida ? Tema.acento : Colors.transparent, width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: alElegir,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(icono, color: elegida ? Tema.acento : Colors.white70),
                      const Spacer(),
                      if (elegida)
                        const Icon(Icons.check_circle_rounded, color: Tema.acento, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
