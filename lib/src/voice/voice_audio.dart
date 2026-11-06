import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;

import 'speech_queue.dart';

/// The microphone and the speaker of the phone. [DeviceVoiceAudio] is the real one; tests use a fake.
abstract class KerabieVoiceAudio {
  /// Asks for the microphone if needed. False when the customer said no.
  Future<bool> requestPermission();

  /// Starts the microphone: 16-bit little-endian PCM at 16 kHz, mono, with echo cancelling so the AI does not hear itself.
  Future<Stream<Uint8List>> startMicrophone();

  /// Gets the speaker ready for the AI's speech: 16-bit little-endian PCM at 24 kHz, mono.
  Future<void> startSpeaker();

  /// Plays speech, in order, after what is already playing.
  void play(Uint8List pcm);

  /// The customer spoke over the AI: speech that has not started playing is dropped.
  void clearPlayback();

  /// Stops both and lets go of the audio hardware.
  Future<void> stop();
}

/// Speech from the AI is this many samples a second.
const kerabieVoiceOutputRate = 24000;

/// Records with `record` and plays with `flutter_pcm_sound`.
class DeviceVoiceAudio implements KerabieVoiceAudio {
  final _recorder = AudioRecorder();
  KerabieSpeechPacer? _pacer;
  Timer? _pace;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startMicrophone() => _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        // Android's voice-communication source switches the phone's own echo canceller on.
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication, speakerphone: true),
      ));

  @override
  Future<void> startSpeaker() async {
    await FlutterPcmSound.setLogLevel(LogLevel.none);
    await FlutterPcmSound.setup(sampleRate: kerabieVoiceOutputRate, channelCount: 1, iosAudioCategory: IosAudioCategory.playAndRecord);
    _pacer = KerabieSpeechPacer(
      sampleRate: kerabieVoiceOutputRate,
      feed: (pcm) => FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(pcm))),
    );
    _pace = Timer.periodic(const Duration(milliseconds: 50), (_) => _pacer?.pump());
  }

  @override
  void play(Uint8List pcm) => _pacer?.push(pcm);

  @override
  void clearPlayback() => _pacer?.clear();

  @override
  Future<void> stop() async {
    _pace?.cancel();
    _pace = null;
    _pacer?.clear();
    _pacer = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {
      // Already stopped.
    }
    try {
      await FlutterPcmSound.release();
    } catch (_) {
      // Never started.
    }
  }
}
