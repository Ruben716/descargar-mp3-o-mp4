import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calidad.dart';
import 'catalogo.dart';
import 'volumen_parejo.dart';
import 'listas.dart';
import 'nucleo.dart';

/// Estado de la descarga, compartido por las pantallas.
///
/// Vive fuera de ellas porque una descarga puede empezar desde la lista de
/// resultados o desde la vista previa, y las dos tienen que ver el mismo
/// avance. Aqui tambien viven los ajustes elegidos, que valen para ambas.
class ControlDescarga extends ChangeNotifier {
  ControlDescarga._();

  static final ControlDescarga instancia = ControlDescarga._();

  /// Como se baja la primera vez, antes de haber elegido nada.
  ///
  /// Musica y no video: es una app para escuchar, y quien quiere el video lo
  /// elige una vez y ya se recuerda.
  static const Ajustes deFabrica = Ajustes(url: '', soloAudio: true);

  Ajustes ajustes = deFabrica;

  bool _activa = false;
  bool get activa => _activa;

  double? _porcentaje;
  double? get porcentaje => _porcentaje;

  String _estado = '';
  String get estado => _estado;

  String _mensaje = '';
  String get mensaje => _mensaje;

  bool _fallo = false;
  bool get fallo => _fallo;

  /// Lo que apunto el motor del ultimo fallo.
  ///
  /// El mensaje suelto no basta para saber que paso: el detalle dice que
  /// respondio la web. En este telefono logcat no sirve, porque el sistema
  /// filtra lo que escriben las apps, asi que tiene que verse en pantalla.
  List<String> _detalle = const <String>[];
  List<String> get detalle => _detalle;

  Timer? _reloj;

  int _indice = 0;
  int _total = 0;
  bool _cancelado = false;

  /// "3 de 183" mientras dura un lote; vacio si es una sola pista.
  String get progresoLote => _total > 1 ? '$_indice de $_total' : '';

  bool get enLote => _total > 1;

  bool get cancelando => _cancelado;

  /// Corta el lote. No interrumpe la pista en curso: esa termina y para ahi,
  /// que es mas limpio que dejar un archivo a medias.
  void cancelar() {
    if (!_activa) return;
    _cancelado = true;
    notifyListeners();
  }

  /// Avisa a la biblioteca de que hay algo nuevo que mostrar.
  VoidCallback? alTerminar;

  void cambiarAjustes(Ajustes nuevos) {
    ajustes = nuevos;
    notifyListeners();
    unawaited(_guardarAjustes());
  }

  /// Donde se guardan los ajustes. Publica: la copia de seguridad la lleva.
  static const String claveAjustes = 'ajustes_descarga_v1';

  /// Guarda como se bajo lo ultimo, para no tener que elegirlo cada vez.
  ///
  /// El trozo a recortar no: vale para un video concreto, y recordarlo
  /// cortaria sin avisar lo siguiente que se bajara.
  Future<void> _guardarAjustes() async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setString(
        claveAjustes,
        jsonEncode(<String, dynamic>{
          'soloAudio': ajustes.soloAudio,
          'calidad': ajustes.calidad,
          'formatoAudio': ajustes.formatoAudio,
          'bitrate': ajustes.bitrate,
          'subtitulos': ajustes.subtitulos,
          'sinPatrocinios': ajustes.sinPatrocinios,
          'normalizar': ajustes.normalizar,
          'etiquetasLimpias': ajustes.etiquetasLimpias,
          'portadaOficial': ajustes.portadaOficial,
        }),
      );
    } catch (_) {
      // Quedarse sin recordarlo no puede impedir descargar.
    }
  }

  /// Lo elegido la ultima vez, al abrir la app.
  ///
  /// Antes se perdia al cerrarla: cada vez volvia a Video a 720p, aunque la
  /// hoja de descarga diga que recuerda lo elegido.
  Future<void> recuperarAjustes() async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final String? crudo = memoria.getString(claveAjustes);
      if (crudo == null) return;
      final Map<String, dynamic> d = jsonDecode(crudo) as Map<String, dynamic>;
      const Ajustes base = deFabrica;
      ajustes = Ajustes(
        url: '',
        soloAudio: d['soloAudio'] as bool? ?? base.soloAudio,
        calidad: (d['calidad'] as num?)?.toInt() ?? base.calidad,
        formatoAudio: d['formatoAudio'] as String? ?? base.formatoAudio,
        bitrate: d['bitrate'] as String? ?? base.bitrate,
        subtitulos: d['subtitulos'] as String? ?? base.subtitulos,
        sinPatrocinios: d['sinPatrocinios'] as bool? ?? base.sinPatrocinios,
        normalizar: d['normalizar'] as bool? ?? base.normalizar,
        etiquetasLimpias: d['etiquetasLimpias'] as bool? ?? base.etiquetasLimpias,
        portadaOficial: d['portadaOficial'] as bool? ?? base.portadaOficial,
      );
      notifyListeners();
    } catch (_) {
      // Un ajuste guardado que ya no se entiende: se sigue con los de fabrica.
    }
  }

  void limpiarMensaje() {
    if (_mensaje.isEmpty) return;
    _mensaje = '';
    _fallo = false;
    _detalle = const <String>[];
    notifyListeners();
  }

  /// Vuelve al estado inicial. Mismo motivo que en el reproductor: es un
  /// unico objeto compartido y conviene poder empezar de cero.
  void reiniciar() {
    _reloj?.cancel();
    _activa = false;
    _porcentaje = null;
    _estado = '';
    _mensaje = '';
    _fallo = false;
    _detalle = const <String>[];
    _indice = 0;
    _total = 0;
    _cancelado = false;
    _listaCreada = '';
    ajustes = deFabrica;
    notifyListeners();
  }

  Future<void> iniciar(String url, {Ajustes? con}) => iniciarVarios(<String>[url], con: con);

  /// Descarga una lista entera, una detras de otra.
  ///
  /// Un fallo suelto no detiene el resto: al final se dice cuantas salieron.
  /// Cuantas pistas se bajan a la vez.
  ///
  /// Medido: casi todo el tiempo de una pista se va en preguntarle a
  /// YouTube por los formatos, no en transferir. Solapar esas esperas hace
  /// el lote unas dos veces mas rapido. Tres es un termino prudente: mas
  /// arriesga que YouTube empiece a rechazar peticiones.
  static const int simultaneas = 3;

  ///
  /// Con [con] se baja con esos ajustes sin tocar los guardados: el anime
  /// siempre como video aunque la app este puesta en musica.
  Future<void> iniciarVarios(List<String> urls, {String nombreLista = '', Ajustes? con}) async {
    if (_activa || urls.isEmpty) return;
    final Ajustes usados = con ?? ajustes;
    _activa = true;
    _cancelado = false;
    _indice = 0;
    _total = urls.length;
    _porcentaje = null;
    _estado = 'Preparando...';
    _mensaje = '';
    _fallo = false;
    _detalle = const <String>[];
    notifyListeners();
    _vigilar();

    int correctas = 0;
    int fallidas = 0;
    int reutilizadas = 0;
    String ultimoError = '';
    // Los URI de biblioteca de lo que se va guardando, para recrear la lista.
    final List<String> guardados = <String>[];
    final List<String> pendientes = List<String>.from(urls);
    final bool esLote = urls.length > 1;
    // Lo que el catalogo dice que ya tenemos vale solo si sigue en el
    // telefono: si se borro por fuera, hay que volver a bajarlo.
    final Set<String> enBiblioteca = await _urisDeBiblioteca();

    Future<void> trabajador() async {
      while (!_cancelado && pendientes.isNotEmpty) {
        final String url = pendientes.removeAt(0);
        try {
          final String? ya = await Catalogo.instancia.buscar(
            url,
            audio: usados.soloAudio,
          );
          if (ya != null && enBiblioteca.contains(ya)) {
            // Ya esta bajada: se aprovecha y solo entra en la lista.
            guardados.add(ya);
            reutilizadas++;
            _indice++;
            notifyListeners();
            continue;
          }
          // En un lote no avisa cada pista: al final se manda uno solo.
          final ({List<String> archivos, CalidadAudio? origen}) bajada =
              await Nucleo.descargar(usados.copiar(url: url), avisar: !esLote);
          final List<String> nuevos = bajada.archivos;
          guardados.addAll(nuevos);
          for (final String uri in nuevos) {
            await Catalogo.instancia.registrar(url, audio: usados.soloAudio, uri: uri);
            // Se mide cuanto suena en cuanto llega, para el volumen parejo.
            if (usados.soloAudio) VolumenParejo.instancia.pedirSiFalta(uri);
            // Para poder decir despues, sin inventar, de donde salio el sonido.
            final CalidadAudio? origen = bajada.origen;
            if (origen != null) await Catalogo.instancia.anotarCalidad(uri, origen);
          }
          correctas++;
          alTerminar?.call();
        } on ErrorNucleo catch (error) {
          fallidas++;
          ultimoError = error.mensaje;
          _detalle = error.registro;
        } catch (error) {
          fallidas++;
          ultimoError = '$error';
          _detalle = const <String>[];
        }
        _indice++;
        notifyListeners();
      }
    }

    try {
      final int cuantos = urls.length < simultaneas ? urls.length : simultaneas;
      await Future.wait(List<Future<void>>.generate(cuantos, (_) => trabajador()));
      await _recrearLista(nombreLista, guardados);
      _ultimas = List<String>.unmodifiable(guardados);
      _ultimasSonAudio = usados.soloAudio;
      if (esLote && correctas > 0) {
        await Nucleo.avisarLote(correctas, audio: usados.soloAudio);
      }
      _resumen(correctas, fallidas, reutilizadas, ultimoError);
    } finally {
      // El trozo era para lo que se acaba de bajar. Si se quedara puesto, lo
      // siguiente tambien saldria recortado sin que nadie lo pidiera.
      if (ajustes.fragmento.isNotEmpty) ajustes = ajustes.copiar(fragmento: '');
      _reloj?.cancel();
      _activa = false;
      _cancelado = false;
      _indice = 0;
      _total = 0;
      _estado = '';
      _porcentaje = null;
      notifyListeners();
    }
  }

  /// Deja en la app una lista con lo que se acaba de bajar.
  ///
  /// Si ya existe una con ese nombre se numera, para no mezclar dos descargas
  /// distintas en la misma.
  Future<void> _recrearLista(String nombre, List<String> uris) async {
    if (nombre.trim().isEmpty || uris.isEmpty) return;
    final Listas listas = Listas.instancia;
    await listas.cargar();
    String elegido = nombre.trim();
    int intento = 2;
    while (listas.nombres.contains(elegido)) {
      elegido = '${nombre.trim()} ($intento)';
      intento++;
    }
    await listas.crear(elegido);
    for (final String uri in uris) {
      await listas.anadir(elegido, uri);
    }
    _listaCreada = elegido;
  }

  String _listaCreada = '';

  /// Lo que dejo en la biblioteca la ultima descarga, para poder ir a oirlo.
  List<String> _ultimas = const <String>[];
  List<String> get ultimas => _ultimas;

  /// Si la ultima descarga era musica (y no video).
  bool _ultimasSonAudio = true;
  bool get ultimasSonAudio => _ultimasSonAudio;

  /// Nombre de la lista recien creada, para poder mencionarla al terminar.
  String get listaCreada => _listaCreada;

  /// Los URI que hay ahora mismo en la biblioteca del telefono.
  Future<Set<String>> _urisDeBiblioteca() async {
    try {
      final List<Elemento> elementos = await Nucleo.biblioteca();
      return elementos.map((Elemento e) => e.uri).toSet();
    } catch (_) {
      // Sin la biblioteca se descarga todo, que es el comportamiento seguro.
      return <String>{};
    }
  }

  void _resumen(int correctas, int fallidas, int reutilizadas, String ultimoError) {
    if (_total == 1) {
      _fallo = fallidas > 0;
      if (reutilizadas > 0) {
        _mensaje = 'Ya la tenias en tu biblioteca.';
        return;
      }
      _mensaje = _fallo ? ultimoError : 'Guardado en tu biblioteca.';
      return;
    }
    final String corte = _cancelado ? ' (cancelado)' : '';
    final String creada =
        _listaCreada.isEmpty ? '' : ' Se creo la lista "$_listaCreada".';
    final String repetidas =
        reutilizadas == 0 ? '' : ' $reutilizadas ya las tenias.';
    _fallo = correctas == 0 && reutilizadas == 0;
    _mensaje = fallidas == 0
        ? '$correctas guardadas en tu biblioteca$corte.$repetidas$creada'
        : '$correctas guardadas, $fallidas con error$corte.$repetidas$creada'
            '\n\nUltimo error: $ultimoError';
  }

  /// Python publica el avance y aqui se consulta mientras dure la descarga.
  void _vigilar() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (Timer reloj) async {
      if (!_activa) {
        reloj.cancel();
        return;
      }
      try {
        final Avance avance = await Nucleo.progreso();
        if (enLote) {
          // Con varias a la vez el porcentaje de una sola no significa nada:
          // manda el recuento de pistas.
          _porcentaje = null;
          _estado = 'Hasta $simultaneas a la vez';
          notifyListeners();
          return;
        }
        _porcentaje = avance.porcentaje >= 0 ? avance.porcentaje / 100 : null;
        _estado = switch (avance.estado) {
          'downloading' => _velocidad(avance.velocidad),
          'finished' => 'Uniendo con FFmpeg...',
          _ => 'Preparando...',
        };
        notifyListeners();
      } catch (_) {
        // Una consulta perdida no debe romper la descarga en curso.
      }
    });
  }

  static String _velocidad(int octetos) {
    if (octetos <= 0) return 'Descargando...';
    const List<String> unidades = <String>['B', 'KB', 'MB', 'GB'];
    double valor = octetos.toDouble();
    int i = 0;
    while (valor >= 1024 && i < unidades.length - 1) {
      valor /= 1024;
      i++;
    }
    return '${valor.toStringAsFixed(1)} ${unidades[i]}/s';
  }
}
