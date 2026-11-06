import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

import 'support.dart';

void main() {
  late FakeChat chat;
  late FakeAudio audio;
  late KerabieVoiceController voice;

  setUp(() {
    chat = FakeChat();
    audio = FakeAudio();
    voice = KerabieVoiceController(chat: chat, audio: audio);
  });

  tearDown(() => voice.dispose());

  /// Starts a session and lets the server say it is ready.
  Future<void> startReady() async {
    await voice.start();
    chat.emit('voice_ready', {'inputRate': 16000, 'outputRate': 24000});
    await Future<void>.delayed(Duration.zero);
  }

  test('starting asks the server and shows that it is connecting', () async {
    await voice.start();

    expect(chat.started, [1]);
    expect(voice.state.phase, KerabieVoicePhase.connecting);
    expect(voice.state.active, isTrue);
  });

  test('a second start while one is going on does nothing', () async {
    await voice.start();
    await voice.start();

    expect(chat.started, [1]);
  });

  test('without the microphone permission nothing is started and the customer is told', () async {
    audio.permission = false;

    await voice.start();

    expect(voice.state.error, KerabieVoiceError.permission);
    expect(chat.started, isEmpty);
    expect(voice.state.active, isFalse);
  });

  test('when the server is ready the speaker and microphone start and the session is active', () async {
    await startReady();

    expect(voice.state.phase, KerabieVoicePhase.active);
    expect(audio.speakerStarted, 1);
  });

  test('the customer\'s speech goes to the server, and muting stops it', () async {
    await startReady();

    audio.mic.add(pcm([100, 200]));
    voice.setMuted(true);
    audio.mic.add(pcm([300, 400]));
    voice.setMuted(false);
    audio.mic.add(pcm([500, 600]));

    expect(chat.chunks, [pcm([100, 200]), pcm([500, 600])]);
  });

  test('the orb follows how loud each voice is', () async {
    await startReady();

    audio.mic.add(pcm(List.filled(50, 8000)));
    expect(voice.levels.value.input, greaterThan(0.3));

    chat.emit('voice_audio', {'pcm': pcm(List.filled(50, 8000))});
    expect(voice.levels.value.output, greaterThan(0.3));
  });

  test('what the AI says is played, and its words and state are shown', () async {
    await startReady();

    chat.emit('voice_state', {'state': 'thinking'});
    expect(voice.state.activity, KerabieVoiceActivity.thinking);
    chat.emit('voice_state', {'state': 'speaking'});
    chat.emit('voice_audio', {'pcm': pcm([1, 2, 3])});
    chat.emit('voice_transcript', {'role': 'agent', 'text': 'Here it is', 'final': false});

    expect(audio.played, [pcm([1, 2, 3])]);
    expect(voice.state.activity, KerabieVoiceActivity.speaking);
    expect(voice.state.lines.single.text, 'Here it is');
    expect(voice.state.lines.single.fromCustomer, isFalse);
  });

  test('speech that is not bytes is ignored', () async {
    await startReady();

    chat.emit('voice_audio', {'pcm': 'nope'});
    chat.emit('voice_audio');

    expect(audio.played, isEmpty);
  });

  test('when the customer speaks over the AI, the speech not yet played is dropped', () async {
    await startReady();
    chat.emit('voice_state', {'state': 'speaking'});

    chat.emit('voice_interrupted');

    expect(audio.cleared, 1);
    expect(voice.state.activity, KerabieVoiceActivity.listening);
  });

  test('the customer ends the session: the server is told and the audio is released', () async {
    await startReady();

    voice.stop();
    await Future<void>.delayed(Duration.zero);

    expect(chat.stops, 1);
    expect(audio.stopped, 1);
    expect(voice.state.phase, KerabieVoicePhase.idle);
    expect(voice.state.endedReason, 'user');
    expect(voice.levels.value, (input: 0.0, output: 0.0));
  });

  test('stopping when nothing is going on does nothing', () {
    voice.stop();

    expect(chat.stops, 0);
  });

  test('the server ending the session says why, and the speech stops being sent', () async {
    await startReady();

    chat.emit('voice_ended', {'reason': 'goodbye'});
    audio.mic.add(pcm([1, 2]));

    expect(voice.state.endedReason, 'goodbye');
    expect(voice.state.phase, KerabieVoicePhase.idle);
    expect(chat.chunks, isEmpty);
    expect(chat.stops, 0); // the server already knows
  });

  test('a late event from a finished session changes nothing', () async {
    await startReady();
    chat.emit('voice_ended', {'reason': 'limit'});

    chat.emit('voice_state', {'state': 'speaking'});
    chat.emit('voice_transcript', {'role': 'agent', 'text': 'late', 'final': false});
    chat.emit('voice_audio', {'pcm': pcm([1])});

    expect(voice.state.phase, KerabieVoicePhase.idle);
    expect(voice.state.lines, isEmpty);
    expect(audio.played, isEmpty);
  });

  test('each reason the server refuses is shown as its own error', () async {
    for (final (code, error) in [
      ('limit_reached', KerabieVoiceError.limitReached),
      ('busy', KerabieVoiceError.busy),
      ('unavailable', KerabieVoiceError.unavailable),
      ('something-new', KerabieVoiceError.unavailable),
    ]) {
      final c = FakeChat();
      final v = KerabieVoiceController(chat: c, audio: FakeAudio());
      await v.start();

      c.emit('voice_error', {'code': code});

      expect(v.state.error, error, reason: code);
      expect(v.state.active, isFalse);
      expect(c.stops, 1);
      v.dispose();
    }
  });

  test('losing the connection mid-session ends it with an error', () async {
    await startReady();

    chat.connection(false);

    expect(voice.state.error, KerabieVoiceError.connection);
    expect(audio.stopped, 1);
  });

  test('a microphone that cannot start ends the session with an error', () async {
    audio.failToStart = true;

    await startReady();

    expect(voice.state.error, KerabieVoiceError.unavailable);
    expect(chat.stops, 1);
  });

  test('a server that never answers is given up on after a few seconds', () {
    fakeAsync((async) {
      final v = KerabieVoiceController(chat: FakeChat(), audio: FakeAudio());
      v.start();
      async.flushMicrotasks();
      expect(v.state.phase, KerabieVoicePhase.connecting);

      async.elapse(const Duration(seconds: 11));

      expect(v.state.error, KerabieVoiceError.connection);
      v.dispose();
    });
  });

  test('a session can be started again after it ended', () async {
    await startReady();
    chat.emit('voice_ended', {'reason': 'goodbye'});

    await voice.start();

    expect(chat.started, [1, 2]);
    expect(voice.state.phase, KerabieVoicePhase.connecting);
    expect(voice.state.endedReason, isNull);
  });

  test('dismissing a message clears it, but never ends a session that is going on', () async {
    await voice.start();
    chat.emit('voice_error', {'code': 'busy'});
    voice.dismiss();
    expect(voice.state.error, isNull);

    await startReady();
    voice.dismiss();
    expect(voice.state.phase, KerabieVoicePhase.active);
  });

  test('available follows the dashboard setting', () {
    chat.aiVoiceEnabled = false;
    expect(voice.available, isFalse);
    chat.aiVoiceEnabled = true;
    expect(voice.available, isTrue);
  });

  test('disposing in the middle of a session stops it cleanly', () async {
    final v = KerabieVoiceController(chat: chat, audio: audio);
    await v.start();

    v.dispose();

    expect(chat.stops, 1);
  });

  test('the speech is sent as the bytes it is, with no change', () async {
    await startReady();
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));

    audio.mic.add(bytes);

    expect(chat.chunks.single, bytes);
  });
}
