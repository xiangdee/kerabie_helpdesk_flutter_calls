import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter_calls/src/wake_word.dart';

/// A speech engine the test drives by hand.
class FakeSpeech implements KerabieSpeechSource {
  FakeSpeech([this.result = KerabieSpeechStart.started]);

  KerabieSpeechStart result;
  int starts = 0;
  int stops = 0;
  bool? lastOnDeviceOnly;
  void Function(String)? _onText;
  void Function()? _onEnd;
  void Function(String)? _onError;

  @override
  Future<KerabieSpeechStart> start({required String language, required bool onDeviceOnly, required void Function(String text) onText, required void Function() onEnd, required void Function(String error) onError}) async {
    starts++;
    lastOnDeviceOnly = onDeviceOnly;
    _onText = onText;
    _onEnd = onEnd;
    _onError = onError;
    return result;
  }

  @override
  Future<void> stop() async => stops++;

  void hear(String text) => _onText?.call(text);
  void end() => _onEnd?.call();
  void fail(String error) => _onError?.call(error);
}

bool hears(String name, String said, [List<String> aliases = const []]) => heardWake(said, wakeNames(name, aliases));

void main() {
  group('normalising and distance', () {
    test('lower-cases and drops punctuation, accents and extra spaces', () {
      expect(normaliseSpeech('  Hello,  KERABIE!! '), 'hello kerabie');
      expect(normaliseSpeech('Héllo Zoë'), 'hello zoe');
    });

    test('counts the edits between two words', () {
      expect(speechDistance('kerabie', 'kerabie'), 0);
      expect(speechDistance('kerabie', 'kerabi'), 1);
      expect(speechDistance('kerabie', 'carabie'), 2);
      expect(speechDistance('', 'abc'), 3);
    });
  });

  group('waking the agent by name', () {
    test('wakes on the name alone, or after a greeting', () {
      expect(hears('Kerabie Agent', 'Kerabie Agent'), isTrue);
      expect(hears('Ted', 'Ted'), isTrue);
      expect(hears('Ted', 'hi Ted'), isTrue);
      expect(hears('Ted', 'Hello, Ted!'), isTrue);
      expect(hears('Ted', 'hey ted can you help me'), isTrue);
      expect(hears('Kerabie Agent', 'hi kerabie agent'), isTrue);
    });

    test('wakes on the first word of a longer name', () {
      expect(hears('Kerabie Agent', 'hello kerabie'), isTrue);
    });

    test('forgives small mishearings of a longer name, but not a short one', () {
      expect(hears('Kerabie', 'hi carabie'), isTrue);
      expect(hears('Kerabie', 'kerabi'), isTrue);
      expect(hears('Ted', 'hi tad'), isFalse);
      expect(hears('Ted', 'hi ned'), isFalse);
    });

    test('accepts spellings the speech engine produces', () {
      expect(hears('Kerabie', 'hey karaby', ['karaby']), isTrue);
    });

    test('does not wake on other words, a greeting alone, or an empty result', () {
      expect(hears('Ted', 'hello there'), isFalse);
      expect(hears('Ted', 'hi'), isFalse);
      expect(hears('Ted', 'the weather is nice'), isFalse);
      expect(hears('Ted', ''), isFalse);
      expect(hears('Kerabie Agent', 'agent'), isFalse);
    });

    test('does not listen for a name too short to be told apart', () {
      expect(wakeNames('Al'), isEmpty);
      expect(hears('Al', 'hi al'), isFalse);
    });

    test('lists the full name and its first word once each', () {
      expect(wakeNames('Kerabie Agent'), [
        ['kerabie', 'agent'],
        ['kerabie'],
      ]);
      expect(wakeNames('Ted'), [
        ['ted'],
      ]);
    });
  });

  group('the controller', () {
    late FakeSpeech speech;
    late int wakes;
    late KerabieWakeWordController c;

    KerabieWakeWordController make({bool onDeviceOnly = true, int maxFailures = 5}) => KerabieWakeWordController(
          name: 'Ted',
          source: speech,
          onWake: () => wakes++,
          onDeviceOnly: onDeviceOnly,
          restartDelay: const Duration(milliseconds: 5),
          maxFailures: maxFailures,
        );

    setUp(() {
      speech = FakeSpeech();
      wakes = 0;
      c = make();
    });
    tearDown(() => c.dispose());

    test('listens only while active, and says so', () async {
      expect(c.state, KerabieWakeWordState.off);
      await c.setActive(true);
      expect(speech.starts, 1);
      expect(c.state, KerabieWakeWordState.listening);
      await c.setActive(false);
      expect(speech.stops, 1);
      expect(c.state, KerabieWakeWordState.off);
    });

    test('uses on-device recognition unless told otherwise', () async {
      await c.setActive(true);
      expect(speech.lastOnDeviceOnly, isTrue);
      await c.setActive(false);
      c.dispose();
      c = make(onDeviceOnly: false);
      await c.setActive(true);
      expect(speech.lastOnDeviceOnly, isFalse);
    });

    test('wakes once on the name, stopping the microphone first', () async {
      await c.setActive(true);
      speech.hear('hello there');
      expect(wakes, 0);
      speech.hear('hi Ted');
      expect(wakes, 1);
      expect(speech.stops, 1);
      expect(c.state, KerabieWakeWordState.off);
      speech.hear('hi Ted'); // a late result after waking does nothing
      expect(wakes, 1);
    });

    test('stays quiet after waking until it has been switched off and on again', () async {
      await c.setActive(true);
      speech.hear('Ted');
      await c.setActive(true); // a rebuild while the call is starting
      expect(speech.starts, 1);
      await c.setActive(false);
      await c.setActive(true);
      expect(speech.starts, 2);
    });

    test('listens again when the engine ends a session by itself', () async {
      await c.setActive(true);
      speech.end();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(speech.starts, 2);
    });

    test('hearing nothing is not a failure, but real errors stop it trying forever', () async {
      c.dispose();
      c = make(maxFailures: 2);
      await c.setActive(true);
      speech.fail('no-speech');
      speech.end();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(speech.starts, 2);
      speech.fail('network');
      speech.end();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(speech.starts, 3);
      speech.fail('network');
      speech.end();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(speech.starts, 3, reason: 'gave up after two real failures');
    });

    test('says when permission was refused or the phone cannot do it', () async {
      speech.result = KerabieSpeechStart.denied;
      await c.setActive(true);
      expect(c.state, KerabieWakeWordState.denied);
      await c.setActive(false);
      speech.result = KerabieSpeechStart.unsupported;
      await c.setActive(true);
      expect(c.state, KerabieWakeWordState.unsupported);
    });

    test('a refused permission reported while listening is shown too', () async {
      await c.setActive(true);
      speech.fail('not-allowed');
      expect(c.state, KerabieWakeWordState.denied);
    });

    test('stops if it is switched off while still starting', () async {
      final starting = c.setActive(true);
      await c.setActive(false);
      await starting;
      expect(c.state, KerabieWakeWordState.off);
      expect(speech.stops, greaterThanOrEqualTo(1));
    });

    test('follows a rename', () async {
      await c.setActive(true);
      c.rename('Kerabie Agent');
      speech.hear('hi kerabie');
      expect(wakes, 1);
    });
  });
}
