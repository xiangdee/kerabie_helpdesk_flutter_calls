import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter_calls/src/voice/speech_queue.dart';

import 'support.dart';

void main() {
  group('kerabiePcmLevel', () {
    test('silence is 0 and empty input is 0', () {
      expect(kerabiePcmLevel(pcm(List.filled(100, 0))), 0);
      expect(kerabiePcmLevel(Uint8List(0)), 0);
      expect(kerabiePcmLevel(Uint8List(1)), 0);
    });

    test('louder speech is a higher level, and the level never passes 1', () {
      final quiet = kerabiePcmLevel(pcm(List.filled(100, 1000)));
      final loud = kerabiePcmLevel(pcm(List.filled(100, 8000)));
      expect(loud, greaterThan(quiet));
      expect(kerabiePcmLevel(pcm(List.filled(100, 32767))), 1);
      expect(kerabiePcmLevel(pcm(List.filled(100, -32768))), 1);
    });
  });

  group('KerabieSpeechQueue', () {
    test('gives pieces back in order', () {
      final q = KerabieSpeechQueue()..push(pcm([1, 2]))..push(pcm([3, 4]));
      expect(q.frames, 4);
      expect(q.take(10), pcm([1, 2]));
      expect(q.take(10), pcm([3, 4]));
      expect(q.take(10), isNull);
      expect(q.isEmpty, isTrue);
    });

    test('cuts a long piece and keeps the rest, in order', () {
      final q = KerabieSpeechQueue()..push(pcm([1, 2, 3, 4, 5]));
      expect(q.take(2), pcm([1, 2]));
      expect(q.frames, 3);
      expect(q.take(2), pcm([3, 4]));
      expect(q.take(2), pcm([5]));
      expect(q.isEmpty, isTrue);
    });

    test('a piece put back goes to the front', () {
      final q = KerabieSpeechQueue()..push(pcm([1]))..push(pcm([2]));
      final first = q.take(5)!;
      q.pushFront(first);
      expect(q.take(5), pcm([1]));
      expect(q.take(5), pcm([2]));
    });

    test('nothing is taken for a zero limit, and pieces under one sample are ignored', () {
      final q = KerabieSpeechQueue()..push(Uint8List(1));
      expect(q.isEmpty, isTrue);
      q.push(pcm([1]));
      expect(q.take(0), isNull);
    });

    test('clearing drops everything', () {
      final q = KerabieSpeechQueue()..push(pcm([1, 2, 3]));
      q.clear();
      expect(q.isEmpty, isTrue);
      expect(q.frames, 0);
    });
  });

  group('KerabieSpeechPacer', () {
    // One second of 24 kHz speech is 24000 samples.
    Uint8List second() => Uint8List(24000 * 2);

    test('gives the player only what it needs, not everything at once', () {
      var now = DateTime(2026, 11, 2);
      final fed = <int>[];
      final pacer = KerabieSpeechPacer(feed: (b) => fed.add(b.length ~/ 2), sampleRate: 24000, now: () => now, aheadMs: 300);

      for (var i = 0; i < 5; i++) {
        pacer.push(second());
      }

      // One 300 ms bite, then it waits: the player holds 300 ms and no more.
      expect(fed, [7200]);
      now = now.add(const Duration(milliseconds: 200));
      pacer.pump();
      expect(fed.length, 2);
      expect(pacer.idle, isFalse);
    });

    test('an interruption drops what has not been handed over', () {
      var now = DateTime(2026, 11, 2);
      final fed = <int>[];
      final pacer = KerabieSpeechPacer(feed: (b) => fed.add(b.length), sampleRate: 24000, now: () => now, aheadMs: 300);
      for (var i = 0; i < 5; i++) {
        pacer.push(second());
      }

      pacer.clear();
      now = now.add(const Duration(seconds: 5));
      pacer.pump();

      expect(fed.length, 1);
      expect(pacer.idle, isTrue);
    });

    test('is idle when nothing waits and the last piece has played', () {
      var now = DateTime(2026, 11, 2);
      final pacer = KerabieSpeechPacer(feed: (_) {}, sampleRate: 24000, now: () => now, aheadMs: 300);
      expect(pacer.idle, isTrue);
      pacer.push(Uint8List(2400 * 2)); // 100 ms
      expect(pacer.idle, isFalse);
      now = now.add(const Duration(milliseconds: 150));
      expect(pacer.idle, isTrue);
    });

    test('everything pushed is eventually played, in order, with nothing lost', () {
      var now = DateTime(2026, 11, 2);
      final fed = <Uint8List>[];
      final pacer = KerabieSpeechPacer(feed: fed.add, sampleRate: 24000, now: () => now, aheadMs: 300);
      final all = Uint8List.fromList(List.generate(24000 * 2, (i) => i % 251));
      pacer.push(all);

      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(milliseconds: 50));
        pacer.pump();
      }

      expect(fed.expand((b) => b).toList(), all);
    });
  });
}
