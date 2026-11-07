import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

import 'speech_queue.dart';
import 'voice_audio.dart';
import 'voice_state.dart';

/// How loud the customer is and how loud the AI is, from 0 to 1, many times a second, for the orb.
typedef KerabieVoiceLevels = ({double input, double output});

/// How long the server gets to answer a start before the attempt is given up.
const _startTimeout = Duration(seconds: 10);

/// What a voice session needs from the chat. [KerabieVoiceChat.from] makes one from the `KerabieController`; tests use a fake.
abstract class KerabieVoiceChat implements Listenable {
  factory KerabieVoiceChat.from(KerabieController controller) = _ControllerChat;

  /// The AI voice agent is on in the dashboard and the plan has AI minutes.
  bool get aiVoiceEnabled;
  bool get isConnected;
  Stream<KerabieEvent> get voiceEvents;
  Future<void> voiceStart();
  void voiceAudio(Uint8List pcm);
  void voiceStop();
}

class _ControllerChat implements KerabieVoiceChat {
  _ControllerChat(this._c);

  final KerabieController _c;

  @override
  bool get aiVoiceEnabled => _c.settings.aiVoiceEnabled;
  @override
  bool get isConnected => _c.isConnected;
  @override
  Stream<KerabieEvent> get voiceEvents => _c.voiceEvents;
  @override
  Future<void> voiceStart() => _c.voiceStart();
  @override
  void voiceAudio(Uint8List pcm) => _c.voiceAudio(pcm);
  @override
  void voiceStop() => _c.voiceStop();
  @override
  void addListener(VoidCallback listener) => _c.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _c.removeListener(listener);
}

/// One live voice session with the AI. The orb and the panel read [state] and [levels]; [start] and [stop] are the only
/// ways in. Microphone speech goes to Kerabie over the chat's own connection; the AI's speech and what it is doing come
/// back as events.
class KerabieVoiceController extends ChangeNotifier {
  KerabieVoiceController({required this.chat, KerabieVoiceAudio? audio}) : _audio = audio ?? DeviceVoiceAudio();

  final KerabieVoiceChat chat;
  final KerabieVoiceAudio _audio;

  KerabieVoiceState _state = const KerabieVoiceState();
  KerabieVoiceState get state => _state;

  /// Updated many times a second, so the orb listens to this and the rest of the screen does not rebuild.
  final levels = ValueNotifier<KerabieVoiceLevels>((input: 0, output: 0));

  /// True when the dashboard has calls on. A session is refused with a clear message when AI calls are off or the plan's
  /// minutes are used up.
  bool get available => chat.aiVoiceEnabled;

  bool _running = false;
  StreamSubscription<KerabieEvent>? _events;
  StreamSubscription<Uint8List>? _mic;
  Timer? _startTimer;

  void _set(KerabieVoiceState next) {
    _state = next;
    notifyListeners();
  }

  /// Starts a session. Does nothing while one is going on.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _set(_state.connecting());

    final granted = await _audio.requestPermission().catchError((_) => false);
    if (!_running) return;
    if (!granted) return _fail(KerabieVoiceError.permission);

    _events = chat.voiceEvents.listen(_onEvent);
    chat.addListener(_onChat);
    _startTimer = Timer(_startTimeout, () => _fail(KerabieVoiceError.connection));
    await chat.voiceStart();
  }

  void _onChat() {
    if (_running && !chat.isConnected) _fail(KerabieVoiceError.connection);
  }

  void _onEvent(KerabieEvent e) {
    switch (e.name) {
      case 'voice_ready':
        unawaited(_onReady());
      case 'voice_state':
        final next = switch (e.data['state']) {
          'thinking' => KerabieVoiceActivity.thinking,
          'speaking' => KerabieVoiceActivity.speaking,
          _ => KerabieVoiceActivity.listening,
        };
        _set(_state.withActivity(next));
      case 'voice_transcript':
        _set(_state.withTranscript(fromCustomer: e.data['role'] == 'user', text: '${e.data['text'] ?? ''}', finished: e.data['final'] == true));
      case 'voice_audio':
        final pcm = e.data['pcm'];
        if (pcm is Uint8List) {
          _audio.play(pcm);
          _lastSpeech = DateTime.now();
          levels.value = (input: levels.value.input, output: kerabiePcmLevel(pcm));
        }
      case 'voice_interrupted':
        _audio.clearPlayback();
        _set(_state.interrupted());
      case 'voice_ended':
        _finish('${e.data['reason'] ?? 'closed'}');
      case 'voice_error':
        _fail(switch (e.data['code']) {
          'limit_reached' => KerabieVoiceError.limitReached,
          'busy' => KerabieVoiceError.busy,
          _ => KerabieVoiceError.unavailable,
        });
    }
  }

  Future<void> _onReady() async {
    _startTimer?.cancel();
    if (!_running) return;
    try {
      await _audio.startSpeaker();
      final mic = await _audio.startMicrophone();
      if (!_running) return;
      _mic = mic.listen((pcm) {
        levels.value = (input: kerabiePcmLevel(pcm), output: levels.value.output);
        if (_state.muted) return;
        chat.voiceAudio(_hearsItself() ? Uint8List(pcm.length) : pcm);
      });
    } catch (_) {
      return _fail(KerabieVoiceError.unavailable);
    }
    _set(_state.ready());
  }

  DateTime? _lastSpeech;

  /// On Android the speech plays on the media channel, which the phone's echo canceller does not know about, so the
  /// microphone picks the AI up and the AI takes it for the customer interrupting it, again and again. While the AI is
  /// speaking (and a moment after, for what is still in the speaker's buffer) the AI is sent silence instead of the
  /// microphone. The stream keeps flowing, so the session does not look idle. The cost: on Android the customer cannot
  /// talk over the AI.
  bool _hearsItself() {
    if (!Platform.isAndroid) return false;
    if (_state.activity == KerabieVoiceActivity.speaking) return true;
    final last = _lastSpeech;
    return last != null && DateTime.now().difference(last) < const Duration(milliseconds: 900);
  }

  void setMuted(bool muted) => _set(_state.withMuted(muted));

  /// Clears an error or a goodbye message once it has been seen.
  void dismiss() {
    if (!_running) _set(_state.dismissed());
  }

  /// The customer ends the session.
  void stop() {
    if (!_running) return;
    chat.voiceStop();
    _finish('user');
  }

  void _finish(String reason) {
    if (!_running) return;
    _cleanup();
    _set(_state.ended(reason));
  }

  void _fail(KerabieVoiceError why) {
    if (!_running) return;
    chat.voiceStop();
    _cleanup();
    _set(_state.failed(why));
  }

  /// Stops the microphone and the speaker and forgets the listeners.
  void _cleanup() {
    _running = false;
    _startTimer?.cancel();
    _startTimer = null;
    _events?.cancel();
    _events = null;
    _mic?.cancel();
    _mic = null;
    chat.removeListener(_onChat);
    unawaited(_audio.stop());
    levels.value = (input: 0, output: 0);
  }

  @override
  void dispose() {
    if (_running) {
      chat.voiceStop();
      _cleanup();
    }
    levels.dispose();
    super.dispose();
  }
}
