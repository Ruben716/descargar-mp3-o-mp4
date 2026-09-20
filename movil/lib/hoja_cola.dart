import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'tema.dart';

/// Lo que viene detras de lo que suena, y se puede tocar.
///
/// Hasta ahora la cola existia pero era invisible: se sabia que habia un
/// siguiente solo porque el boton estaba encendido. Aqui se ve entera, se
/// salta a cualquier pista, se quita lo que sobra y se reordena arrastrando.
Future<void> abrirCola(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tema.superficie,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext contexto) => const HojaCola(),
  );
}

class HojaCola extends StatelessWidget {
  const HojaCola({super.key});

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext context, ScrollController control) {
        return ListenableBuilder(
          listenable: estado,
          builder: (BuildContext context, _) {
            final List<Elemento> cola = estado.colaEnEscucha;
            final int sonando = estado.posicionEnEscucha;
            return Column(
              children: <Widget>[
                _Cabecera(estado: estado, pendientes: cola.length - sonando - 1),
                Expanded(
                  child: cola.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay nada en la cola.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : _Lista(
                          control: control,
                          cola: cola,
                          sonando: sonando,
                          estado: estado,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.estado, required this.pendientes});

  final EstadoReproductor estado;
  final int pendientes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Column(
        children: <Widget>[
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'En cola',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pendientes <= 0
                          ? 'Nada mas despues de esta'
                          : '$pendientes por sonar',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: estado.alternarAleatorio,
                tooltip: estado.aleatorio ? 'Quitar aleatorio' : 'Aleatorio',
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: estado.aleatorio ? Tema.acento : Colors.white38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.control,
    required this.cola,
    required this.sonando,
    required this.estado,
  });

  final ScrollController control;
  final List<Elemento> cola;
  final int sonando;
  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollController: control,
      padding: const EdgeInsets.only(bottom: 28),
      buildDefaultDragHandles: false,
      itemCount: cola.length,
      // onReorderItem y no onReorder: el nuevo ya viene con el indice corregido
      // por el hueco que deja la fila al salir, que es lo que se quiere aqui.
      onReorderItem: estado.moverEnCola,
      itemBuilder: (BuildContext context, int i) => _Fila(
        // La clave va por posicion y no por URI: la misma pista puede estar
        // repetida en la cola y dos filas con la misma clave rompen la lista.
        key: ValueKey<String>('$i:${cola[i].uri}'),
        posicion: i,
        elemento: cola[i],
        activa: i == sonando,
        pasada: i < sonando,
        estado: estado,
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.posicion,
    required this.elemento,
    required this.activa,
    required this.pasada,
    required this.estado,
    super.key,
  });

  final int posicion;
  final Elemento elemento;
  final bool activa;
  final bool pasada;
  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Material(
        color: activa ? Tema.acento.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => estado.saltarACola(posicion),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Opacity(
              // Lo ya escuchado se atenua: sigue ahi por si se quiere volver,
              // pero no compite con lo que falta, que es lo que se mira.
              opacity: pasada ? 0.45 : 1,
              child: Row(
                children: <Widget>[
                  PortadaLocal(elemento: elemento, lado: 44, radio: 11),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          nombreLimpio(elemento.nombre),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: activa ? Tema.acento : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatoTiempo(elemento.duracion),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (activa && estado.sonando)
                    const Icon(Icons.equalizer_rounded, color: Tema.acento, size: 18),
                  IconButton(
                    onPressed: () => estado.quitarDeCola(posicion),
                    tooltip: 'Quitar de la cola',
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                  ),
                  // Con el aleatorio puesto el orden lo decide el barajado, asi
                  // que no se ofrece un asa que no podria cumplir lo que promete.
                  if (!estado.aleatorio)
                    ReorderableDragStartListener(
                      index: posicion,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle_rounded,
                            size: 20, color: Colors.white24),
                      ),
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
