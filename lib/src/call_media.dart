import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'agent_options.dart';

/// The audio and video side of a call. [LiveKitCallMedia] is the real one; tests use a fake.
abstract class KerabieCallMedia {
  /// Joins the call's room with the pass the server gave. Starts the microphone, and the camera when [video] is true.
  ///
  /// [screens] are the app's screens the AI agent may ask for. Each is answered through an RPC named `kerabie.ui.<name>`.
  ///
  /// [actions] are what the app can do for the agent on the device, answered through an RPC named `kerabie.action.<name>`.
  Future<void> join({required String url, required String token, required bool video, Map<String, KerabieScreenHandler> screens = const {}, Map<String, KerabieAgentAction> actions = const {}});

  Future<void> leave();
  Future<void> setMicrophone(bool on);
  Future<void> setCamera(bool on);

  /// The other side's video, when there is one.
  VideoTrack? get remoteVideo;

  /// Your own camera, when it is on, shown small over the other side's video.
  VideoTrack? get localVideo;

  bool get microphoneOn;
  bool get cameraOn;

  /// Called when anything the screen shows has changed (a track arrived, the microphone was muted).
  VoidCallback? onChanged;

  /// Called when the connection to the room ended on its own, for example when the network dropped for good.
  VoidCallback? onDisconnected;

  void dispose();
}

/// Carries the call over LiveKit.
class LiveKitCallMedia extends KerabieCallMedia {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideo;

  @override
  VideoTrack? get remoteVideo => _remoteVideo;

  @override
  VideoTrack? get localVideo {
    for (final pub in _room?.localParticipant?.videoTrackPublications ?? const <LocalTrackPublication<LocalVideoTrack>>[]) {
      final track = pub.track;
      if (track != null && !pub.muted) return track;
    }
    return null;
  }

  @override
  bool get microphoneOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  @override
  bool get cameraOn => _room?.localParticipant?.isCameraEnabled() ?? false;

  @override
  Future<void> join({required String url, required String token, required bool video, Map<String, KerabieScreenHandler> screens = const {}, Map<String, KerabieAgentAction> actions = const {}}) async {
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
    _room = room;
    _listener = room.createListener()
      ..on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack) _remoteVideo = e.track as VideoTrack;
        onChanged?.call();
      })
      ..on<TrackUnsubscribedEvent>((e) {
        if (e.track == _remoteVideo) _remoteVideo = null;
        onChanged?.call();
      })
      ..on<LocalTrackPublishedEvent>((_) => onChanged?.call())
      ..on<LocalTrackUnpublishedEvent>((_) => onChanged?.call())
      ..on<RoomDisconnectedEvent>((_) {
        if (_room == room) onDisconnected?.call();
      });

    // The AI agent asks the app to show a screen (a picker, a confirmation) and waits for what the customer chose.
    screens.forEach((name, handler) {
      room.registerRpcMethod('kerabie.ui.$name', (data) async {
        var payload = <String, dynamic>{};
        try {
          final decoded = jsonDecode(data.payload);
          if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
        } catch (_) {
          // An unreadable request is treated as empty.
        }
        return handler(payload);
      });
    });

    actions.forEach((name, action) {
      room.registerRpcMethod('kerabie.action.$name', (data) async {
        var args = <String, dynamic>{};
        try {
          final decoded = jsonDecode(data.payload);
          if (decoded is Map) args = Map<String, dynamic>.from(decoded);
        } catch (_) {
          // An unreadable request is treated as empty.
        }
        return action.run(args);
      });
    });

    await room.connect(url, token);
    await room.localParticipant?.setMicrophoneEnabled(true);
    if (video) {
      // A camera that cannot start must not end an otherwise good call.
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (_) {}
    }
    onChanged?.call();
  }

  @override
  Future<void> leave() async {
    final room = _room;
    _room = null;
    _remoteVideo = null;
    await _listener?.dispose();
    _listener = null;
    await room?.disconnect();
    await room?.dispose();
  }

  @override
  Future<void> setMicrophone(bool on) async {
    await _room?.localParticipant?.setMicrophoneEnabled(on);
    onChanged?.call();
  }

  @override
  Future<void> setCamera(bool on) async {
    await _room?.localParticipant?.setCameraEnabled(on);
    onChanged?.call();
  }

  @override
  void dispose() {
    onChanged = null;
    onDisconnected = null;
    leave();
  }
}
