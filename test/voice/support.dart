import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

/// A stand-in for the chat: records what the voice session sends, and lets the test push what the server would.
class FakeChat extends ChangeNotifier implements KerabieVoiceChat {
  FakeChat({this.aiVoiceEnabled = true});

  @override
  bool aiVoiceEnabled;
  @override
  bool isConnected = true;

  final started = <int>[];
  final chunks = <Uint8List>[];
  var stops = 0;
  final _events = StreamController<KerabieEvent>.broadcast(sync: true);

  @override
  Stream<KerabieEvent> get voiceEvents => _events.stream;

  @override
  Future<void> voiceStart() async => started.add(started.length + 1);

  @override
  void voiceAudio(Uint8List pcm) => chunks.add(pcm);

  @override
  void voiceStop() => stops++;

  void emit(String name, [Map<String, dynamic> data = const {}]) => _events.add(KerabieEvent(name, data));

  void connection(bool up) {
    isConnected = up;
    notifyListeners();
  }
}

/// A stand-in for the microphone and speaker.
class FakeAudio implements KerabieVoiceAudio {
  FakeAudio({this.permission = true});

  bool permission;
  bool failToStart = false;
  final mic = StreamController<Uint8List>.broadcast(sync: true);
  final played = <Uint8List>[];
  var cleared = 0;
  var stopped = 0;
  var speakerStarted = 0;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<Stream<Uint8List>> startMicrophone() async {
    if (failToStart) throw StateError('no microphone');
    return mic.stream;
  }

  @override
  Future<void> startSpeaker() async => speakerStarted++;

  @override
  void play(Uint8List pcm) => played.add(pcm);

  @override
  void clearPlayback() => cleared++;

  @override
  Future<void> stop() async => stopped++;
}

/// 16-bit little-endian PCM from sample values.
Uint8List pcm(List<int> samples) {
  final b = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

KerabiePalette testPalette() => const KerabiePalette(
      primary: Color(0xFF334155),
      secondary: Color(0xFF0F766E),
      gradient: false,
      radius: 16,
      background: Colors.white,
      surface: Color(0xFFF1F5F9),
      border: Color(0xFFE2E8F0),
      text: Color(0xFF0F172A),
      muted: Color(0xFF64748B),
      agentBubble: Color(0xFFF1F5F9),
      surfaceStrong: Color(0xFFE2E8F0),
      subtle: Color(0xFF94A3B8),
      inputBackground: Color(0xFFF8FAFC),
      dark: false,
    );
