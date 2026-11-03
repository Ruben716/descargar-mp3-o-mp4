import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Que se le deja hacer a quien tiene la app.
enum EstadoAcceso {
  /// Leyendo lo guardado.
  cargando,

  /// Sin codigo, o el que tenia ya no vale: pide uno.
  sinCodigo,

  /// Pasaron mas de [Acceso.vigenciaApp] sin validar: no abre hasta renovar.
  caducado,

  /// Pasaron mas de [Acceso.vigenciaDescargas]: se oye lo que hay, pero no se
  /// busca ni se baja hasta renovar.
  sinDescargas,

  /// Todo.
  completo,
}

/// Lo que contesta el servidor cuando se le da un codigo.
enum RespuestaAcceso { ok, noExiste, desactivado, otroTelefono, espera, sinRed }

typedef ResultadoAcceso = ({RespuestaAcceso estado, String nombre});

/// El control de acceso: quien tiene el codigo de quien se lo dio puede usar la
/// app, y solo en un telefono.
///
/// El codigo se valida contra una funcion de Supabase (`validar_acceso`, ver
/// supabase/accesos.sql) y se guarda cuando se valido. Sin internet se
/// sigue con lo ultimo que dijo el servidor, con dos plazos: pasados
/// [vigenciaDescargas] dias no se busca ni se baja, y pasados [vigenciaApp]
/// no se abre. Cada vez que hay internet el plazo se renueva solo.
///
/// Si el servidor no contesta (caido, sin red) nunca se bloquea a nadie por
/// eso: solo cuenta lo que ya dijo. Bloquea a quien el servidor dice que no.
class Acceso extends ChangeNotifier {
  Acceso._();

  static final Acceso instancia = Acceso._();

  /// Apagado (en pruebas y en la consola), la app no pide nada. `main` lo
  /// enciende.
  static bool exigir = false;

  /// El proyecto de Supabase. La clave es la publica («publishable»): esta
  /// hecha para ir dentro de las apps, y sin permiso sobre ninguna tabla; lo
  /// unico que se puede hacer con ella es llamar a `validar_acceso`.
  static const String url = 'https://rqudigxjjjtscuvmpjrv.supabase.co';
  static const String clavePublica = 'sb_publishable_Ea4AR5HjueMUfBfSfaOGyA_f2ft92V-';

  static const Duration vigenciaDescargas = Duration(days: 7);
  static const Duration vigenciaApp = Duration(days: 30);

  /// Cuanto puede estar el reloj por detras de lo ultimo que se vio antes de
  /// pensar que lo atrasaron para alargar los plazos.
  static const Duration margenReloj = Duration(hours: 1);

  /// Con la app abierta se vuelve a validar pasado este tiempo.
  static const Duration renovarCada = Duration(hours: 6);

  static const String _claveCodigo = 'acceso_codigo';
  static const String _claveNombre = 'acceso_nombre';
  static const String _claveValidado = 'acceso_validado';
  static const String _claveVisto = 'acceso_visto';
  static const String _claveTelefono = 'acceso_telefono';

  static const String sinDescargasMensaje =
      'Hace mas de 7 dias que no validas tu acceso. Conectate a internet para renovarlo.';

  /// Como se le pregunta al servidor. Las pruebas ponen aqui un doble.
  static Future<ResultadoAcceso> Function(String codigo, String dispositivo) servidor = _preguntarAlServidor;

  /// Que telefono es: el de Android, resumido (ver MainActivity.idDispositivo).
  static Future<String> Function() idDispositivo = _idDelTelefono;

  static DateTime Function() ahora = DateTime.now;

  EstadoAcceso _estado = EstadoAcceso.cargando;
  String _codigo = '';
  String _nombre = '';
  int _validadoMs = 0;
  int _vistoMs = 0;
  bool _cargado = false;
  bool _validando = false;
  Future<void>? _renovando;

  /// Por que se le quito el acceso, para decirlo en la pantalla del codigo.
  String aviso = '';

  EstadoAcceso get estado => _estado;
  String get nombre => _nombre;
  bool get hayCodigo => _codigo.isNotEmpty;
  bool get validando => _validando;

  /// Cuando se valido por ultima vez; null si nunca.
  DateTime? get validado => _validadoMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(_validadoMs);

  /// En que estado queda quien valido en [validadoMs] (y vio la hora [vistoMs]),
  /// estando en [ahoraMs]. Sin hacer nada con la red: todo se decide con esto.
  static EstadoAcceso estadoDe({
    required bool hayCodigo,
    required int validadoMs,
    required int vistoMs,
    required int ahoraMs,
  }) {
    if (!hayCodigo || validadoMs <= 0) return EstadoAcceso.sinCodigo;
    // Con el reloj atrasado se podria alargar el plazo: hasta volver a validar
    // contra el servidor no se da nada por bueno.
    if (ahoraMs < vistoMs - margenReloj.inMilliseconds) return EstadoAcceso.caducado;
    final int edad = ahoraMs - validadoMs;
    if (edad > vigenciaApp.inMilliseconds) return EstadoAcceso.caducado;
    if (edad > vigenciaDescargas.inMilliseconds) return EstadoAcceso.sinDescargas;
    return EstadoAcceso.completo;
  }

  /// Buscar y bajar: con la puerta apagada siempre; encendida, solo con
  /// el acceso completo.
  bool get puedeDescargar => !exigir || _estado == EstadoAcceso.completo;

  /// Como [puedeDescargar], pero si el plazo de las descargas vencio intenta
  /// renovarlo ahora mismo: con internet, el usuario ni se entera.
  Future<bool> permiteDescargar() async {
    if (puedeDescargar) return true;
    if (_estado == EstadoAcceso.sinDescargas) await revalidar();
    return puedeDescargar;
  }

  /// Lee lo guardado y, si hay codigo, lo renueva sin esperar.
  Future<void> cargar() async {
    if (!_cargado) {
      _cargado = true;
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        _codigo = prefs.getString(_claveCodigo) ?? '';
        _nombre = prefs.getString(_claveNombre) ?? '';
        _validadoMs = prefs.getInt(_claveValidado) ?? 0;
        _vistoMs = prefs.getInt(_claveVisto) ?? 0;
      } catch (_) {
        // Sin poder leer, se pide el codigo otra vez.
      }
    }
    await _recalcular();
    if (hayCodigo) unawaited(revalidar());
  }

  /// Al volver a la app: recalcula los plazos y, si ya toca, renueva.
  Future<void> alVolver() async {
    if (!exigir || !_cargado) return;
    await _recalcular();
    final int edad = ahora().millisecondsSinceEpoch - _validadoMs;
    final bool toca = edad > renovarCada.inMilliseconds || _estado != EstadoAcceso.completo;
    if (hayCodigo && toca) unawaited(revalidar());
  }

  /// Prueba un codigo escrito por el usuario. Devuelve el motivo si no vale,
  /// o null si ya puede entrar.
  Future<String?> introducir(String escrito) async {
    final String codigo = _limpiar(escrito);
    if (codigo.length < 8) return mensajeDe(RespuestaAcceso.noExiste);
    _validando = true;
    notifyListeners();
    try {
      final ResultadoAcceso r = await servidor(codigo, await _telefono());
      if (r.estado != RespuestaAcceso.ok) return mensajeDe(r.estado);
      _codigo = codigo;
      _nombre = r.nombre;
      aviso = '';
      await _guardarValidado();
      return null;
    } finally {
      _validando = false;
      await _recalcular();
    }
  }

  /// Vuelve a preguntar con el codigo guardado. Sin red no cambia nada. Si ya
  /// hay una pregunta en camino, se espera a esa: no se hacen dos a la vez.
  Future<void> revalidar() => _renovando ??= _revalidar().whenComplete(() => _renovando = null);

  Future<void> _revalidar() async {
    if (!hayCodigo) return;
    _validando = true;
    notifyListeners();
    try {
      final ResultadoAcceso r = await servidor(_codigo, await _telefono());
      switch (r.estado) {
        case RespuestaAcceso.ok:
          _nombre = r.nombre.isNotEmpty ? r.nombre : _nombre;
          await _guardarValidado();
        case RespuestaAcceso.noExiste:
        case RespuestaAcceso.desactivado:
        case RespuestaAcceso.otroTelefono:
          aviso = mensajeDe(r.estado);
          await _olvidarCodigo();
        case RespuestaAcceso.espera:
        case RespuestaAcceso.sinRed:
          break;
      }
    } finally {
      _validando = false;
      await _recalcular();
    }
  }

  /// Quita el codigo guardado (para escribir otro).
  Future<void> cerrar() async {
    aviso = '';
    await _olvidarCodigo();
    await _recalcular();
  }

  static String mensajeDe(RespuestaAcceso r) => switch (r) {
        RespuestaAcceso.ok => '',
        RespuestaAcceso.noExiste => 'Ese codigo no existe. Revisalo e intenta otra vez.',
        RespuestaAcceso.desactivado => 'Ese codigo esta desactivado. Pidele uno nuevo a quien te dio la app.',
        RespuestaAcceso.otroTelefono => 'Ese codigo ya se usa en otro telefono.',
        RespuestaAcceso.espera => 'Demasiados intentos. Espera unos minutos y vuelve a probar.',
        RespuestaAcceso.sinRed => 'No hay conexion. Conectate a internet para validar el codigo.',
      };

  /// Sin espacios ni guiones y en mayusculas: «1d43 b59c-7f4e» vale.
  static String _limpiar(String texto) => texto.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<void> _guardarValidado() async {
    final int ahoraMs = ahora().millisecondsSinceEpoch;
    _validadoMs = ahoraMs;
    _vistoMs = max(_vistoMs, ahoraMs);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveCodigo, _codigo);
      await prefs.setString(_claveNombre, _nombre);
      await prefs.setInt(_claveValidado, _validadoMs);
      await prefs.setInt(_claveVisto, _vistoMs);
    } catch (_) {
      // Sin guardar, vale hasta cerrar la app y despues se pide otra vez.
    }
  }

  Future<void> _olvidarCodigo() async {
    _codigo = '';
    _nombre = '';
    _validadoMs = 0;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveCodigo);
      await prefs.remove(_claveNombre);
      await prefs.remove(_claveValidado);
    } catch (_) {
      // Se queda en memoria; al reabrir se vuelve a validar.
    }
  }

  /// Pone el estado al dia y apunta la hora mas alta vista (para el reloj).
  Future<void> _recalcular() async {
    final int ahoraMs = ahora().millisecondsSinceEpoch;
    _estado = estadoDe(hayCodigo: hayCodigo, validadoMs: _validadoMs, vistoMs: _vistoMs, ahoraMs: ahoraMs);
    if (ahoraMs > _vistoMs && hayCodigo) {
      _vistoMs = ahoraMs;
      try {
        await (await SharedPreferences.getInstance()).setInt(_claveVisto, _vistoMs);
      } catch (_) {
        // No es grave.
      }
    }
    notifyListeners();
  }

  /// El telefono: el de Android o, si no lo da, uno al azar que se guarda.
  Future<String> _telefono() async {
    final String id = await idDispositivo();
    if (id.length >= 8) return id;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String guardado = prefs.getString(_claveTelefono) ?? '';
      if (guardado.length >= 8) return guardado;
      final Random azar = Random.secure();
      final String nuevo = List<String>.generate(32, (_) => azar.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_claveTelefono, nuevo);
      return nuevo;
    } catch (_) {
      return 'sin-id-${_codigo.hashCode}';
    }
  }

  static Future<String> _idDelTelefono() => Nucleo.idDispositivo();

  static Future<ResultadoAcceso> _preguntarAlServidor(String codigo, String dispositivo) async {
    final HttpClient cliente = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest peticion = await cliente.postUrl(Uri.parse('$url/rest/v1/rpc/validar_acceso'));
      peticion.headers
        ..set('apikey', clavePublica)
        ..contentType = ContentType.json;
      peticion.add(utf8.encode(jsonEncode(<String, String>{'p_codigo': codigo, 'p_dispositivo': dispositivo})));
      final HttpClientResponse respuesta = await peticion.close().timeout(const Duration(seconds: 15));
      final String cuerpo = await respuesta.transform(utf8.decoder).join();
      // Un 503 o un proyecto pausado no son un «no»: no se bloquea a nadie por eso.
      if (respuesta.statusCode != 200) return (estado: RespuestaAcceso.sinRed, nombre: '');
      final Map<String, dynamic> datos = jsonDecode(cuerpo) as Map<String, dynamic>;
      final RespuestaAcceso estado = switch (datos['estado']) {
        'ok' => RespuestaAcceso.ok,
        'no_existe' => RespuestaAcceso.noExiste,
        'desactivado' => RespuestaAcceso.desactivado,
        'otro_telefono' => RespuestaAcceso.otroTelefono,
        'espera' => RespuestaAcceso.espera,
        _ => RespuestaAcceso.sinRed,
      };
      return (estado: estado, nombre: datos['nombre']?.toString() ?? '');
    } catch (_) {
      return (estado: RespuestaAcceso.sinRed, nombre: '');
    } finally {
      cliente.close(force: true);
    }
  }

  @visibleForTesting
  void reiniciar() {
    exigir = false;
    servidor = _preguntarAlServidor;
    idDispositivo = _idDelTelefono;
    ahora = DateTime.now;
    _estado = EstadoAcceso.cargando;
    _codigo = '';
    _nombre = '';
    _validadoMs = 0;
    _vistoMs = 0;
    _cargado = false;
    _validando = false;
    _renovando = null;
    aviso = '';
  }
}

/// Deja pasar a la app solo con acceso: si no, la pantalla del codigo.
class PuertaDeAcceso extends StatefulWidget {
  const PuertaDeAcceso({required this.hijo, super.key});

  final Widget hijo;

  @override
  State<PuertaDeAcceso> createState() => _PuertaDeAccesoState();
}

class _PuertaDeAccesoState extends State<PuertaDeAcceso> with WidgetsBindingObserver {
  final Acceso _acceso = Acceso.instancia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _acceso.addListener(_refrescar);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _acceso.removeListener(_refrescar);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) unawaited(_acceso.alVolver());
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (_acceso.estado) {
      case EstadoAcceso.completo:
      case EstadoAcceso.sinDescargas:
        return widget.hijo;
      case EstadoAcceso.cargando:
        return const Scaffold(
          backgroundColor: Tema.fondo,
          body: Center(child: CircularProgressIndicator()),
        );
      case EstadoAcceso.sinCodigo:
      case EstadoAcceso.caducado:
        return const PantallaCodigo();
    }
  }
}

/// Pide el codigo de acceso, o renovar el que se tiene si caduco.
class PantallaCodigo extends StatefulWidget {
  const PantallaCodigo({super.key});

  @override
  State<PantallaCodigo> createState() => _PantallaCodigoState();
}

class _PantallaCodigoState extends State<PantallaCodigo> {
  final Acceso _acceso = Acceso.instancia;
  final TextEditingController _texto = TextEditingController();
  String _error = '';

  @override
  void initState() {
    super.initState();
    _acceso.addListener(_refrescar);
  }

  @override
  void dispose() {
    _acceso.removeListener(_refrescar);
    _texto.dispose();
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    final String? motivo = await _acceso.introducir(_texto.text);
    if (mounted) setState(() => _error = motivo ?? '');
  }

  Future<void> _renovar() async {
    await _acceso.revalidar();
    if (!mounted) return;
    setState(() => _error = _acceso.estado == EstadoAcceso.completo
        ? ''
        : Acceso.mensajeDe(RespuestaAcceso.sinRed));
  }

  @override
  Widget build(BuildContext context) {
    final bool caducado = _acceso.estado == EstadoAcceso.caducado && _acceso.hayCodigo;
    final String mensaje = _error.isNotEmpty ? _error : _acceso.aviso;
    final bool ocupado = _acceso.validando;
    return Scaffold(
      backgroundColor: Tema.fondo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.lock_outline_rounded, size: 44, color: Tema.acento),
                  const SizedBox(height: 18),
                  Text(
                    caducado ? 'Renueva tu acceso' : 'Acceso a Tumbao',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    caducado
                        ? 'Hace mas de 30 dias que no se valida tu acceso. Conectate a internet y toca Renovar.'
                        : 'Escribe el codigo que te dio quien te paso la app. Hace falta internet la primera vez.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Tema.textoSecundario, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  if (caducado) ...<Widget>[
                    BotonDegradado(
                      texto: ocupado ? 'Validando' : 'Renovar',
                      icono: Icons.refresh_rounded,
                      alPulsar: ocupado ? null : _renovar,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'O entra con otro codigo:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Tema.textoTenue, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _texto,
                    enabled: !ocupado,
                    autocorrect: false,
                    enableSuggestions: false,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 -]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
                    onSubmitted: (_) => _entrar(),
                  ),
                  if (mensaje.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      mensaje,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Tema.peligro, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (caducado)
                    OutlinedButton(
                      onPressed: ocupado ? null : _entrar,
                      child: const Text('Entrar con este codigo'),
                    )
                  else
                    BotonDegradado(
                      texto: ocupado ? 'Validando' : 'Entrar',
                      icono: Icons.login_rounded,
                      alPulsar: ocupado ? null : _entrar,
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
