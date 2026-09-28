import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Un motor de audio de mentira para las pruebas.
///
/// Sin el, cualquier carga chocaba con que en el escritorio no hay plugin, y
/// las pruebas del reproductor solo podian mirar lo que pasaba antes de tocar
/// el motor. Con el, la carga recorre el codigo de verdad de just_audio:
/// activarse, preguntar por el ecualizador, cargar y quedar listo.
class MotorFalso extends JustAudioPlatform {
  /// Cuantas veces fallara el ecualizador antes de responder bien.
  ///
  /// Reproduce lo que pasaba en el telefono: el plugin pregunta por las bandas
  /// antes de que Android haya creado el ecualizador, y revienta.
  int fallosDelEcualizador = 0;

  /// Cuantas veces se ha activado el motor desde cero.
  int activaciones = 0;

  /// Cuantas cargas le han llegado de verdad.
  int cargas = 0;

  void reiniciar() {
    fallosDelEcualizador = 0;
    activaciones = 0;
    cargas = 0;
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    activaciones++;
    return _JugadorFalso(request.id, this);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async =>
      DisposeAllPlayersResponse();
}

/// El mismo mensaje que dio el telefono, palabra por palabra.
const String falloDelEcualizadorEnAndroid =
    "java.lang.NullPointerException: Attempt to invoke virtual method 'short "
    "android.media.audiofx.Equalizer.getNumberOfBands()' on a null object reference";

class _JugadorFalso extends AudioPlayerPlatform {
  _JugadorFalso(super.id, this._motor);

  final MotorFalso _motor;
  final StreamController<PlaybackEventMessage> _eventos =
      StreamController<PlaybackEventMessage>.broadcast();

  /// La pista con la que se cargo: el de verdad arranca en esa, no en la primera.
  int _indice = 0;

  PlaybackEventMessage _evento(ProcessingStateMessage estado) => PlaybackEventMessage(
        processingState: estado,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: const Duration(seconds: 100),
        icyMetadata: null,
        currentIndex: _indice,
        androidAudioSessionId: null,
      );

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _eventos.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream<PlayerDataMessage>.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _motor.cargas++;
    _indice = request.initialIndex ?? 0;
    // Como el de verdad: responde a la carga y luego avisa de que esta listo.
    scheduleMicrotask(() => _eventos.add(_evento(ProcessingStateMessage.ready)));
    return LoadResponse(duration: const Duration(seconds: 100));
  }

  /// En el telefono el ecualizador sencillamente no existe todavia, asi que
  /// revienta cualquier cosa que se le pida: leer sus bandas la primera vez y
  /// restaurarlas en las siguientes activaciones.
  void _comprobarEcualizador() {
    if (_motor.fallosDelEcualizador > 0) {
      _motor.fallosDelEcualizador--;
      throw PlatformException(code: 'Error', message: falloDelEcualizadorEnAndroid);
    }
  }

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) async {
    _comprobarEcualizador();
    return AndroidEqualizerGetParametersResponse(
      parameters: AndroidEqualizerParametersMessage(
        minDecibels: -15,
        maxDecibels: 15,
        bands: <AndroidEqualizerBandMessage>[
          for (int i = 0; i < 5; i++)
            AndroidEqualizerBandMessage(
              index: i,
              lowerFrequency: 60.0 * (i + 1),
              upperFrequency: 60.0 * (i + 2),
              centerFrequency: 60.0 * (i + 1.5),
              gain: 0,
            ),
        ],
      ),
    );
  }

  // Lo demas no hace falta que haga nada: basta con que responda.
  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();
  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
    SetPreferredPeakBitRateRequest request,
  ) async =>
      SetPreferredPeakBitRateResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _eventos.close();
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async =>
      ConcatenatingInsertAllResponse();
  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async =>
      ConcatenatingRemoveRangeResponse();
  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse();
  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(
    AudioEffectSetEnabledRequest request,
  ) async =>
      AudioEffectSetEnabledResponse();
  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) async =>
      AndroidLoudnessEnhancerSetTargetGainResponse();
  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
    AndroidEqualizerBandSetGainRequest request,
  ) async {
    _comprobarEcualizador();
    return AndroidEqualizerBandSetGainResponse();
  }
}
