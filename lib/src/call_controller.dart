import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;

import 'call_media.dart';

/// What the call controller needs from the chat. [KerabieController] is the real one; tests use a fake.
abstract class KerabieCallChat {
  bool get callsEnabled;
  bool get videoEnabled;
  Future<KerabieCallJoin> startCall({bool video});
  Future<KerabieCallJoin?> currentCall();
  Future<void> endCall(int callId);
  Stream<KerabieCallEvent> get callEvents;

  /// The organisation asks for details before a chat, and this visitor has not given any yet.
  bool get needsDetails;
  void submitDetails(Map<String, String> answers);
}

/// Reads the calls settings from a [KerabieController].
class KerabieControllerCalls implements KerabieCallChat {
  KerabieControllerCalls(this.controller);

  final KerabieController controller;

  @override
  bool get callsEnabled => controller.settings.callsEnabled;
  @override
  bool get videoEnabled => controller.settings.videoCallsEnabled;
  @override
  Future<KerabieCallJoin> startCall({bool video = false}) => controller.startCall(video: video);
  @override
  Future<KerabieCallJoin?> currentCall() => controller.currentCall();
  @override
  Future<void> endCall(int callId) => controller.endCall(callId);
  @override
  Stream<KerabieCallEvent> get callEvents => controller.callEvents;
  @override
  bool get needsDetails => controller.needsPreChatDetails;
  @override
  void submitDetails(Map<String, String> answers) => controller.submitPreChat(answers);
}

enum KerabieCallPhase {
  idle,

  /// The organisation asks for the pre-chat details first (the same form as the chat).
  details,

  /// Asking Kerabie to start the call.
  starting,

  /// Every agent is busy: the customer is in the queue.
  waiting,

  /// Free agents are being rung.
  ringing,

  /// Answered by a person or the AI: audio (and video) is flowing.
  connected,

  /// Over, or could not start. [KerabieCallController.endReason] or [KerabieCallController.error] says why.
  ended,
}

/// One call at a time: start it, follow it, hang up. Rebuilds listeners when anything changes.
class KerabieCallController extends ChangeNotifier {
  KerabieCallController(KerabieController chat, {KerabieCallMedia? media})
      : this.forChat(KerabieControllerCalls(chat), media: media);

  KerabieCallController.forChat(this._chat, {KerabieCallMedia? media}) : _media = media ?? LiveKitCallMedia() {
    _media.onChanged = _notify;
    _media.onDisconnected = () => _finish('connection_lost');
    _events = _chat.callEvents.listen(_onEvent);
  }

  final KerabieCallChat _chat;
  final KerabieCallMedia _media;
  StreamSubscription<KerabieCallEvent>? _events;
  bool _disposed = false;
  bool _joining = false;
  bool _answeredEarly = false;
  KerabieCallJoin? _join;

  KerabieCallPhase _phase = KerabieCallPhase.idle;
  int? _callId;
  bool _video = false;
  String? _handler;
  String? _agentName;
  int? _queuePosition;
  String? _endReason;
  String? _error;

  KerabieCallPhase get phase => _phase;
  int? get callId => _callId;
  bool get video => _video;

  /// `HUMAN` or `AI`, once answered.
  String? get handler => _handler;
  String? get agentName => _agentName;

  /// Your place in the queue while [phase] is [KerabieCallPhase.waiting].
  int? get queuePosition => _queuePosition;

  /// Why a call ended: `hangup`, `cancelled`, `missed`, `declined`, `limit` or `connection_lost`.
  String? get endReason => _endReason;
  String? get error => _error;

  /// Calls are on in the dashboard and the plan still has minutes.
  bool get available => _chat.callsEnabled;
  bool get videoAvailable => _chat.callsEnabled && _chat.videoEnabled;

  bool get microphoneOn => _media.microphoneOn;
  bool get cameraOn => _media.cameraOn;
  VideoTrack? get remoteVideo => _media.remoteVideo;
  VideoTrack? get localVideo => _media.localVideo;

  /// Starts a call. A visitor who already has one is put back into it.
  Future<void> start({bool video = false}) async {
    if (!available || _phase != KerabieCallPhase.idle) return;
    _video = video && videoAvailable;
    // The organisation asks every visitor for details before a chat. A call asks the same, once.
    if (_chat.needsDetails) {
      _reset(KerabieCallPhase.details);
      _video = video && videoAvailable;
      _notify();
      return;
    }
    await _place();
  }

  /// The details were filled in: save them and place the call the visitor asked for.
  Future<void> submitDetails(Map<String, String> answers) async {
    if (_phase != KerabieCallPhase.details) return;
    _chat.submitDetails(answers);
    await _place();
  }

  Future<void> _place() async {
    final video = _video;
    _reset(KerabieCallPhase.starting);
    _video = video;
    _notify();
    try {
      final join = await _chat.startCall(video: _video);
      // The call can end (the visitor cancels, nobody is free) before the reply to this request arrives.
      if (_phase != KerabieCallPhase.starting) return;
      await _apply(join);
    } on KerabieException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Could not start the call. Try again in a moment.');
    }
  }

  /// Picks up a call that was still going when the app was closed. Returns whether there was one.
  Future<bool> resume() async {
    if (!available || _phase != KerabieCallPhase.idle) return false;
    try {
      final join = await _chat.currentCall();
      if (join == null || _disposed) return false;
      _reset(KerabieCallPhase.starting);
      await _apply(join);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ends the call, or cancels it before anyone answers.
  Future<void> hangUp() async {
    final id = _callId;
    if (_phase == KerabieCallPhase.idle || _phase == KerabieCallPhase.ended) return;
    // Nothing has been placed yet: just close the screen.
    if (_phase == KerabieCallPhase.details) {
      _reset(KerabieCallPhase.idle);
      _notify();
      return;
    }
    final wasConnected = _phase == KerabieCallPhase.connected;
    await _finish(wasConnected ? 'hangup' : 'cancelled');
    if (id != null) {
      try {
        await _chat.endCall(id);
      } catch (_) {
        // The server also closes the call when the room empties.
      }
    }
  }

  Future<void> toggleMicrophone() async {
    if (_phase != KerabieCallPhase.connected) return;
    await _media.setMicrophone(!_media.microphoneOn);
  }

  Future<void> toggleCamera() async {
    if (_phase != KerabieCallPhase.connected || !_video) return;
    try {
      await _media.setCamera(!_media.cameraOn);
    } catch (_) {
      // Keep the call going without the camera.
    }
  }

  /// Closes the call screen after the call is over.
  void dismiss() {
    if (_phase != KerabieCallPhase.ended) return;
    _reset(KerabieCallPhase.idle);
    _notify();
  }

  // ─── Internals ────────────────────────────────────────────────────────────────

  void _reset(KerabieCallPhase phase) {
    _phase = phase;
    _callId = null;
    _video = false;
    _handler = null;
    _agentName = null;
    _queuePosition = null;
    _endReason = null;
    _error = null;
    _join = null;
    _answeredEarly = false;
  }

  Future<void> _apply(KerabieCallJoin join) async {
    _join = join;
    _callId = join.callId;
    _video = join.video;
    _handler = join.handler ?? _handler;
    _queuePosition = join.queuePosition;
    // Somebody may have answered before the reply to the start request got here.
    switch (_answeredEarly ? 'ACTIVE' : join.status) {
      case 'ACTIVE':
        await _connect();
      case 'RINGING':
        _phase = KerabieCallPhase.ringing;
        _notify();
      default:
        _phase = KerabieCallPhase.waiting;
        _notify();
    }
  }

  Future<void> _connect() async {
    final join = _join;
    if (join == null || _joining || _phase == KerabieCallPhase.connected) return;
    _joining = true;
    try {
      await _media.join(url: join.livekitUrl, token: join.livekitToken, video: _video);
      if (_disposed || _phase == KerabieCallPhase.ended) {
        await _media.leave();
        return;
      }
      _phase = KerabieCallPhase.connected;
      _notify();
    } catch (_) {
      await _media.leave();
      final id = _callId;
      _fail('Could not join the call. Check that this app may use the microphone, then try again.');
      if (id != null) unawaited(_chat.endCall(id).catchError((_) {}));
    } finally {
      _joining = false;
    }
  }

  void _onEvent(KerabieCallEvent event) {
    if (_phase == KerabieCallPhase.idle) return;
    final id = event.callId;
    if (id != null && _callId != null && id != _callId) return;
    switch (event.name) {
      case 'ringing':
        if (_phase == KerabieCallPhase.starting || _phase == KerabieCallPhase.waiting) {
          _phase = KerabieCallPhase.ringing;
          _notify();
        }
      case 'queued':
        _phase = KerabieCallPhase.waiting;
        _queuePosition = (event.data['position'] as num?)?.toInt();
        _notify();
      case 'accepted':
        _handler = event.data['handler'] as String? ?? _handler;
        _agentName = event.data['agentName'] as String?;
        if (_join == null) {
          _answeredEarly = true; // the reply that carries the pass is still on its way
        } else {
          unawaited(_connect());
        }
      case 'ended':
        unawaited(_finish(event.data['reason'] as String? ?? 'hangup'));
    }
  }

  Future<void> _finish(String reason) async {
    if (_phase == KerabieCallPhase.ended || _phase == KerabieCallPhase.idle) return;
    _phase = KerabieCallPhase.ended;
    _endReason = reason;
    _notify();
    await _media.leave();
  }

  void _fail(String message) {
    _phase = KerabieCallPhase.ended;
    _error = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _media.dispose();
    super.dispose();
  }
}
