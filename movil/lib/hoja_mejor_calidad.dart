import 'package:flutter/material.dart';

import 'calidad.dart';
import 'catalogo.dart';
import 'control_descarga.dart';
import 'dialogos.dart';
import 'estado_reproductor.dart';
import 'mejor_calidad.dart';
import 'nucleo.dart';
import 'pantalla_episodio.dart';
import 'tema.dart';
import 'videoclip.dart';

/// Busca una version mejor de [elemento], deja elegirla y la cambia.
///
/// Devuelve el URI de la nueva si se cambio, o null si no.
Future<String?> buscarMejorCalidad(BuildContext context, Elemento elemento) async {
  final CalidadAudio actual = await Catalogo.instancia.calidadDe(elemento.uri) ?? CalidadAudio.tipicaDeYoutube;
  if (!context.mounted) return null;
  final Alternativa? elegida = await showModalBottomSheet<Alternativa>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => HojaMejorCalidad(elemento: elemento, actual: actual),
  );
  if (elegida == null || !context.mounted) return null;
  if (ControlDescarga.instancia.activa) {
    avisar(context, 'Hay una descarga en marcha: prueba cuando termine.');
    return null;
  }
  avisar(context, 'Bajando la version en ${elegida.calidad.etiqueta}...');
  final String? nueva = await MejorCalidad.cambiar(elemento, elegida);
  if (!context.mounted) return nueva;
  if (nueva == null) {
    avisar(context, 'No se pudo bajar esa version. La tuya sigue como estaba.');
    return null;
  }
  final bool borrar = await confirmar(
    context,
    titulo: 'Ya tienes la mejor version',
    mensaje: 'Se paso a ${elegida.calidad.etiqueta}, con sus listas, Me gusta y escuchas. '
        '¿Borro la version anterior (${actual.etiqueta}) para liberar espacio?',
    accion: 'Borrar la anterior',
  );
  if (borrar) await MejorCalidad.borrarAnterior(elemento.uri);
  return nueva;
}

class HojaMejorCalidad extends StatefulWidget {
  const HojaMejorCalidad({required this.elemento, required this.actual, super.key});

  final Elemento elemento;
  final CalidadAudio actual;

  @override
  State<HojaMejorCalidad> createState() => _HojaMejorCalidadState();
}

class _HojaMejorCalidadState extends State<HojaMejorCalidad> {
  late final Future<List<Alternativa>> _busqueda = MejorCalidad.buscar(widget.elemento, widget.actual);

  @override
  Widget build(BuildContext context) {
    final ({String artista, String tema}) partes = widget.elemento.partes;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Buscar mejor calidad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${partes.tema}${partes.artista.isEmpty ? '' : ' · ${partes.artista}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text('Ahora: ${widget.actual.etiqueta}', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            const SizedBox(height: 14),
            FutureBuilder<List<Alternativa>>(
              future: _busqueda,
              builder: (BuildContext context, AsyncSnapshot<List<Alternativa>> estado) {
                if (estado.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: <Widget>[
                        SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            'Buscando en Bandcamp, Audius, Archive y SoundCloud...',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final List<Alternativa> opciones = estado.data ?? const <Alternativa>[];
                if (opciones.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No hay una version mejor en las fuentes que se pueden bajar. '
                      'La que tienes es la mejor disponible.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final Alternativa a in opciones)
                        Card(
                          color: Tema.superficieAlta,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              a.calidad.sinPerdida ? Icons.workspace_premium_rounded : Icons.high_quality_rounded,
                              color: a.calidad.sinPerdida ? const Color(0xFFFFC857) : Tema.acento,
                            ),
                            title: Text(a.calidad.etiqueta, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              '${a.fuente.etiqueta} · ${a.resultado.titulo}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Text('Cambiar', style: TextStyle(color: Tema.acento, fontWeight: FontWeight.w700)),
                            onTap: () => Navigator.of(context).pop(a),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Busca el videoclip oficial de la cancion y lo abre, sin bajarlo.
Future<void> verVideoclip(BuildContext context, Elemento elemento) async {
  avisar(context, 'Buscando el videoclip...');
  final Resultado? clip;
  try {
    clip = await Videoclip.buscar(elemento);
  } catch (error) {
    if (context.mounted) avisar(context, 'No se pudo buscar: $error');
    return;
  }
  if (!context.mounted) return;
  if (clip == null) {
    avisar(context, 'No encontre el videoclip de esta cancion.');
    return;
  }
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  // Dos audios a la vez no se entienden: la musica se pausa.
  final EstadoReproductor estado = EstadoReproductor.instancia;
  if (estado.sonando) await estado.alternar();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PantallaEpisodio(episodio: clip!)));
}
