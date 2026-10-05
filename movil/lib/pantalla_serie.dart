import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'canales_oficiales.dart';
import 'control_descarga.dart';
import 'dialogos.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'pantalla_episodio.dart';
import 'portadas.dart';
import 'tema.dart';

/// Una lista oficial (una temporada, una serie entera) con sus episodios.
class PantallaSerie extends StatefulWidget {
  const PantallaSerie({required this.lista, super.key});

  final Resultado lista;

  @override
  State<PantallaSerie> createState() => _PantallaSerieState();
}

class _PantallaSerieState extends State<PantallaSerie> {
  late Future<({List<Resultado> episodios, bool soloClips})> _carga =
      CanalesOficiales.episodiosDe(widget.lista);

  void _reintentar() => setState(() => _carga = CanalesOficiales.episodiosDe(widget.lista));

  Future<void> _descargarTodos(List<Resultado> episodios) async {
    final bool si = await confirmar(
      context,
      titulo: 'Descargar ${episodios.length} episodios',
      mensaje: 'Se bajan como video, uno detras de otro. Un episodio ocupa unos '
          '100 a 300 MB segun la calidad: mira que tengas espacio.',
      accion: 'Descargar',
      peligro: false,
    );
    if (!si || !mounted) return;
    avisar(context, 'Descargando: puedes seguir usando la app mientras tanto.');
    await descargarComoVideo(<String>[for (final Resultado e in episodios) e.url]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.lista.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${widget.lista.autor} · ${CanalesOficiales.idiomaDe(widget.lista.autor)}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: FutureBuilder<({List<Resultado> episodios, bool soloClips})>(
        future: _carga,
        builder: (BuildContext context, AsyncSnapshot<({List<Resultado> episodios, bool soloClips})> estado) {
          if (estado.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (estado.hasError) {
            return _SinSerie(
              mensaje: estado.error is ErrorNucleo
                  ? (estado.error! as ErrorNucleo).mensaje
                  : 'No se pudo abrir la lista.',
              alReintentar: _reintentar,
            );
          }
          final List<Resultado> episodios = estado.data!.episodios;
          if (episodios.isEmpty) {
            return _SinSerie(mensaje: 'Esta lista esta vacia.', alReintentar: _reintentar);
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: episodios.length + 1,
            itemBuilder: (BuildContext context, int i) {
              if (i == 0) return _cabecera(episodios, soloClips: estado.data!.soloClips);
              final Resultado episodio = episodios[i - 1];
              return AparecerEscalonado(
                indice: i,
                child: _FilaEpisodio(
                  episodio: episodio,
                  alVer: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PantallaEpisodio(
                      episodio: episodio,
                      siguientes: episodios.sublist(i),
                    ),
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _cabecera(List<Resultado> episodios, {required bool soloClips}) {
    final int segundos = episodios.fold<int>(0, (int s, Resultado e) => s + e.duracion.round());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            soloClips
                ? '${episodios.length} videos'
                : '${episodios.length} ${episodios.length == 1 ? 'episodio' : 'episodios'}'
                    '  ·  ${formatoTiempo(segundos)}',
            style: const TextStyle(color: Colors.white60),
          ),
          if (soloClips) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'Esta lista solo tiene avances y escenas cortas, no episodios completos.',
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: ControlDescarga.instancia,
              builder: (BuildContext context, _) => OutlinedButton.icon(
                onPressed: ControlDescarga.instancia.activa ? null : () => _descargarTodos(episodios),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(
                  ControlDescarga.instancia.activa
                      ? 'Descargando ${ControlDescarga.instancia.progresoLote}'
                      : 'Descargar todos',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaEpisodio extends StatelessWidget {
  const _FilaEpisodio({required this.episodio, required this.alVer});

  final Resultado episodio;
  final VoidCallback alVer;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alVer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Stack(
              children: <Widget>[
                PortadaRemota(url: episodio.miniatura, ancho: 136, alto: 77),
                if (episodio.duracion > 0)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: Text(
                          formatoTiempo(episodio.duracion.round()),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                episodio.titulo,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3),
              ),
            ),
            IconButton(
              tooltip: 'Descargar',
              onPressed: ControlDescarga.instancia.activa
                  ? null
                  : () {
                      avisar(context, 'Descargando el episodio como video.');
                      descargarComoVideo(<String>[episodio.url]);
                    },
              icon: const Icon(Icons.download_rounded, color: Tema.acento),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinSerie extends StatelessWidget {
  const _SinSerie({required this.mensaje, required this.alReintentar});

  final String mensaje;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.video_library_outlined, size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: alReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
