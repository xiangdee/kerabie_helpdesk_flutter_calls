import 'dart:math' as math;
import 'dart:typed_data';

/// How loud a piece of 16-bit little-endian PCM is, from 0 (silence) to 1, for drawing the orb. Speech is rarely above a
/// third of full scale, so the level is lifted to use the orb's whole range.
double kerabiePcmLevel(Uint8List pcm) {
  final samples = pcm.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.min(1.0, math.sqrt(sum / samples) * 3.0);
}

/// The AI's speech arrives faster than it is spoken. The player asks for more only as it runs low, so the speech waits
/// here, and when the customer interrupts, everything not yet handed to the player is dropped: the player never holds more
/// than a moment of it.
class KerabieSpeechQueue {
  final _pieces = <Uint8List>[];
  int _frames = 0;

  /// Frames (16-bit samples) waiting.
  int get frames => _frames;
  bool get isEmpty => _pieces.isEmpty;

  void push(Uint8List pcm) {
    if (pcm.length < 2) return;
    _pieces.add(pcm);
    _frames += pcm.length ~/ 2;
  }

  /// The next piece, at most [maxFrames] long, or null when nothing waits. A longer piece is cut and the rest stays.
  Uint8List? take(int maxFrames) {
    if (_pieces.isEmpty || maxFrames <= 0) return null;
    final first = _pieces.first;
    final available = first.length ~/ 2;
    if (available <= maxFrames) {
      _pieces.removeAt(0);
      _frames -= available;
      return first;
    }
    _pieces[0] = Uint8List.sublistView(first, maxFrames * 2);
    _frames -= maxFrames;
    return Uint8List.sublistView(first, 0, maxFrames * 2);
  }

  /// Puts a piece back at the front, for one taken but not used.
  void pushFront(Uint8List pcm) {
    if (pcm.length < 2) return;
    _pieces.insert(0, pcm);
    _frames += pcm.length ~/ 2;
  }

  /// The customer interrupted: speech not yet handed to the player is dropped.
  void clear() {
    _pieces.clear();
    _frames = 0;
  }
}

/// Gives the player the AI's speech in time, not all at once: it never holds more than [aheadMs] of it, and an
/// interruption drops the rest. The clock is passed in so this can be tested without waiting.
class KerabieSpeechPacer {
  KerabieSpeechPacer({required this.feed, required this.sampleRate, DateTime Function()? now, this.aheadMs = 300}) : _now = now ?? DateTime.now;

  /// Hands a piece to the player.
  final void Function(Uint8List pcm) feed;
  final int sampleRate;
  final int aheadMs;
  final DateTime Function() _now;
  final _queue = KerabieSpeechQueue();
  DateTime? _playingUntil;

  void push(Uint8List pcm) {
    _queue.push(pcm);
    pump();
  }

  /// Gives the player what it needs. Called when speech arrives and on a short timer.
  void pump() {
    final aheadFrames = sampleRate * aheadMs ~/ 1000;
    for (var piece = _queue.take(aheadFrames); piece != null; piece = _queue.take(aheadFrames)) {
      final now = _now();
      final until = _playingUntil;
      final queuedMs = until == null ? 0 : until.difference(now).inMilliseconds;
      if (queuedMs >= aheadMs) {
        // The player has enough for now: put the piece back at the front by pushing the remainder order intact.
        _queue.pushFront(piece);
        return;
      }
      feed(piece);
      final start = until != null && until.isAfter(now) ? until : now;
      _playingUntil = start.add(Duration(microseconds: piece.length ~/ 2 * 1000000 ~/ sampleRate));
    }
  }

  /// The customer interrupted: speech not yet handed to the player is dropped.
  void clear() => _queue.clear();

  /// Nothing waiting and nothing still playing.
  bool get idle => _queue.isEmpty && (_playingUntil == null || !_playingUntil!.isAfter(_now()));
}
