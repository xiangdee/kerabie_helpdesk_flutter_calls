import 'dart:async';

import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter_calls/src/call_controller.dart';
import 'package:kerabie_helpdesk_flutter_calls/src/call_media.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;

KerabieCallJoin join({String status = 'RINGING', bool video = false, String? handler, int? position, int id = 31}) => KerabieCallJoin(
      callId: id,
      status: status,
      video: video,
      handler: handler,
      queuePosition: position,
      livekitUrl: 'wss://lk.test',
      livekitToken: 'jwt-$id',
    );

/// A stand-in for the chat: answers the call requests with what the test sets up, and lets the test push events.
class FakeChat implements KerabieCallChat {
  FakeChat({this.callsEnabled = true, this.videoEnabled = true});

  @override
  bool callsEnabled;
  @override
  bool videoEnabled;

  Future<KerabieCallJoin> Function(bool video)? onStart;
  KerabieCallJoin? current;
  Object? currentError;
  Object? endError;
  final startCalls = <bool>[];
  final ended = <int>[];
  final _events = StreamController<KerabieCallEvent>.broadcast(sync: true);

  @override
  Stream<KerabieCallEvent> get callEvents => _events.stream;

  @override
  Future<KerabieCallJoin> startCall({bool video = false}) {
    startCalls.add(video);
    return (onStart ?? (v) async => join(video: v))(video);
  }

  @override
  Future<KerabieCallJoin?> currentCall() async {
    if (currentError != null) throw currentError!;
    return current;
  }

  @override
  Future<void> endCall(int callId) async {
    ended.add(callId);
    if (endError != null) throw endError!;
  }

  void emit(String name, [Map<String, dynamic> data = const {'callId': 31}]) => _events.add(KerabieCallEvent(name, data));

  void close() => _events.close();
}

/// A stand-in for the audio and video: records what the controller asked of it.
class FakeMedia extends KerabieCallMedia {
  final joins = <({String url, String token, bool video})>[];
  int leaves = 0;
  Object? joinError;
  bool _mic = true;
  bool _camera = false;
  Object? cameraError;

  @override
  Future<void> join({required String url, required String token, required bool video}) async {
    if (joinError != null) throw joinError!;
    joins.add((url: url, token: token, video: video));
    _mic = true;
    _camera = video;
  }

  @override
  Future<void> leave() async => leaves++;

  @override
  Future<void> setMicrophone(bool on) async {
    _mic = on;
    onChanged?.call();
  }

  @override
  Future<void> setCamera(bool on) async {
    if (cameraError != null) throw cameraError!;
    _camera = on;
    onChanged?.call();
  }

  @override
  VideoTrack? get remoteVideo => null;
  @override
  bool get microphoneOn => _mic;
  @override
  bool get cameraOn => _camera;

  @override
  void dispose() {}
}

KerabieCallController makeCall(FakeChat chat, FakeMedia media) => KerabieCallController.forChat(chat, media: media);

Future<void> pump() => Future<void>.delayed(Duration.zero);
