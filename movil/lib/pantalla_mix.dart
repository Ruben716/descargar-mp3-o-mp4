import 'dart:async';

import 'package:flutter/material.dart';

import 'dialogos.dart';
import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'hecho_para_ti.dart';
import 'hoja_listas.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'secciones_inicio.dart';
import 'tema.dart';

/// Un mix de «Hecho para ti» o de «Tus mixes», con lo que se puede hacer con el.
///
/// Reproducir en su orden, en aleatorio, como una mezcla DJ (ordenado para
/// que fluya, con el fundido al compas) o guardarlo como lista para que no
/// cambie manana. En la «Sesion DJ» el boton grande es la mezcla.
class PantallaMix extends StatelessWidget {
  const PantallaMix({required this.mix, super.key});

  final Mix mix;

  Future<void> _guardar(BuildContext context) async {
    final String? nombre = await pedirNombreDeLista(context, inicial: mix.titulo);
    if (nombre == null || !context.mounted) return;
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (!await listas.crear(nombre)) {
      if (context.mounted) avisar(context, 'Ya tienes una lista que se llama «$nombre».');
      return;
    }
    await listas.anadirVarias(nombre, <String>[for (final Elemento e in mix.pistas) e.uri]);
    if (context.mounted) avisar(context, 'Guardado como «$nombre»');
  }

  @override
  Widget build(BuildContext context) {
    final List<Elemento> pistas = mix.pistas;
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            tooltip: 'Guardar como lista',
            onPressed: pistas.isEmpty ? null : () => _guardar(context),
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: pistas.length + 1,
        itemBuilder: (BuildContext context, int i) =>
            i == 0 ? _cabecera(context) : FilaPista(elemento: pistas[i - 1], enCola: pistas),
      ),
    );
  }

  Widget _cabecera(BuildContext context) {
    final List<Elemento> pistas = mix.pistas;
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final int segundos = pistas.fold(0, (int s, Elemento e) => s + e.duracion.round());
    void enOrden() => unawaited(estado.reproducirEnOrden(pistas));
    void comoDj() => unawaited(estado.reproducirDj(pistas, modo: mix.modoDj));
    final bool dj = mix.comoDj;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: PortadaMix(mix: mix, lado: 200, radio: 24)),
          const SizedBox(height: 18),
          Text(mix.titulo, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 24)),
          const SizedBox(height: 4),
          Text(mix.subtitulo, style: const TextStyle(color: Tema.textoSecundario, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '${pistas.length == 1 ? '1 cancion' : '${pistas.length} canciones'}  ·  ${formatoTiempo(segundos)}',
            style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: pistas.isEmpty ? null : (dj ? comoDj : enOrden),
                  icon: Icon(dj ? Icons.headphones_rounded : Icons.play_arrow_rounded, size: 20),
                  label: Text(dj ? 'Mezcla DJ' : 'Reproducir'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: pistas.isEmpty ? null : (dj ? enOrden : comoDj),
                  icon: Icon(dj ? Icons.play_arrow_rounded : Icons.headphones_rounded, size: 20),
                  label: Text(dj ? 'Reproducir' : 'Mezcla DJ'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Aleatorio',
                onPressed: pistas.isEmpty ? null : () => unawaited(estado.reproducirAleatorio(pistas)),
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
