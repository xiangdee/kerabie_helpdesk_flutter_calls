import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether what was just heard is someone calling the agent: its name, or a greeting and its name ("hi Ted", "hello
/// Ted", "hey Ted"). Plain functions, so the rule can be tested without a phone or a microphone.

const _accents = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'e': 'èéêëēĕėęě',
  'i': 'ìíîïĩīĭįı',
  'n': 'ñńņň',
  'o': 'òóôõöøōŏő',
  's': 'śŝşš',
  'u': 'ùúûüũūŭůűų',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final _folded = <int, String>{
  for (final e in _accents.entries)
    for (final rune in e.value.runes) rune: e.key,
};

/// Lower case, letters and numbers only, single spaces. Speech engines add punctuation and capitals inconsistently.
String normaliseSpeech(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final folded = _folded[rune];
    if (folded != null) {
      out.write(folded);
    } else if ((rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39)) {
      out.writeCharCode(rune);
    } else {
      out.write(' ');
    }
  }
  return out.toString().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

/// Edits needed to turn one word into the other.
int speechDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      row.add([prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y));
    }
    prev = row;
  }
  return prev[b.length];
}

/// Speech engines mishear names, so a longer word may be one or two letters off. A short word must be exact.
int _tolerance(String word) => word.length >= 7 ? 2 : (word.length >= 4 ? 1 : 0);

/// The names to listen for: the full name, and its first word when the name has several ("Kerabie Agent" is also heard
/// as "Kerabie"). Extra spellings the speech engine tends to produce can be passed in.
List<List<String>> wakeNames(String name, [List<String> aliases = const []]) {
  final all = [name, name.trim().split(RegExp(r'\s+')).first, ...aliases];
  final seen = <String>{};
  final out = <List<String>>[];
  for (final n in all) {
    final words = normaliseSpeech(n).split(' ').where((w) => w.isNotEmpty).toList();
    final key = words.join(' ');
    // A one- or two-letter name would wake on any short word.
    if (key.length < 3 || !seen.add(key)) continue;
    out.add(words);
  }
  return out;
}

/// Whether the words heard contain the name (allowing small mishearings), with or without a greeting before it.
bool heardWake(String transcript, List<List<String>> names) {
  final heard = normaliseSpeech(transcript).split(' ').where((w) => w.isNotEmpty).toList();
  if (heard.isEmpty || names.isEmpty) return false;
  for (final name in names) {
    for (var start = 0; start + name.length <= heard.length; start++) {
      var all = true;
      for (var k = 0; k < name.length; k++) {
        if (speechDistance(heard[start + k], name[k]) > _tolerance(name[k])) {
          all = false;
          break;
        }
      }
      if (all) return true;
    }
  }
  return false;
}

/// How starting to listen went.
enum KerabieSpeechStart { started, denied, unsupported }

/// The phone's speech recognition. Plug in the plugin your app already uses (for example `speech_to_text`) by implementing
/// this, so the SDK does not force a speech plugin, and its permission strings, on every app that only wants calls.
abstract class KerabieSpeechSource {
  /// Starts listening. [onText] gets each partial or final transcript, [onEnd] is called when the engine stops by itself
  /// (engines end a session after a while), and [onError] gets an error code (`no-speech` and `aborted` are normal).
  /// Asks for permission the first time. With [onDeviceOnly] it must use recognition that runs on the phone, and answer
  /// [KerabieSpeechStart.unsupported] when the phone cannot.
  Future<KerabieSpeechStart> start({
    required String language,
    required bool onDeviceOnly,
    required void Function(String text) onText,
    required void Function() onEnd,
    required void Function(String error) onError,
  });

  Future<void> stop();
}

enum KerabieWakeWordState { off, asking, listening, denied, unsupported }

/// Listens for the agent's name while it is [setActive], and calls [onWake] once when it hears it. After waking it stays
/// quiet until [setActive] has been false and true again: the call that follows needs the microphone.
class KerabieWakeWordController extends ChangeNotifier {
  KerabieWakeWordController({
    required String name,
    required this.onWake,
    required this.source,
    List<String> aliases = const [],
    this.language = 'en-US',
    this.onDeviceOnly = true,
    this.restartDelay = const Duration(milliseconds: 400),
    this.maxFailures = 5,
  }) : _names = wakeNames(name, aliases);

  final VoidCallback onWake;
  final KerabieSpeechSource source;
  final String language;
  final bool onDeviceOnly;

  /// How long to wait before listening again after the engine stops by itself.
  final Duration restartDelay;

  /// After this many failures in a row it gives up, rather than draining the battery in a loop.
  final int maxFailures;

  List<List<String>> _names;
  KerabieWakeWordState _state = KerabieWakeWordState.off;
  bool _active = false;
  bool _listening = false;
  bool _suppressed = false;
  bool _disposed = false;
  int _failures = 0;
  Timer? _timer;

  KerabieWakeWordState get state => _state;

  /// The agent was renamed.
  void rename(String name, [List<String> aliases = const []]) => _names = wakeNames(name, aliases);

  /// Listen (true) or stop (false). The widget passes "enabled and the app is in the foreground".
  Future<void> setActive(bool active) async {
    if (!active) {
      _suppressed = false;
      if (!_active) return;
      _active = false;
      await _halt();
      _set(KerabieWakeWordState.off);
      return;
    }
    if (_active || _suppressed) return;
    _active = true;
    _failures = 0;
    _set(KerabieWakeWordState.asking);
    await _begin();
  }

  Future<void> _begin() async {
    if (!_active || _listening || _disposed) return;
    _listening = true;
    final result = await source.start(language: language, onDeviceOnly: onDeviceOnly, onText: _onText, onEnd: _onEnd, onError: _onError);
    if (_disposed) return;
    if (!_active) {
      // Switched off while it was starting.
      if (result == KerabieSpeechStart.started) await source.stop();
      _listening = false;
      return;
    }
    switch (result) {
      case KerabieSpeechStart.started:
        _set(KerabieWakeWordState.listening);
      case KerabieSpeechStart.denied:
        _listening = false;
        _set(KerabieWakeWordState.denied);
      case KerabieSpeechStart.unsupported:
        _listening = false;
        _set(KerabieWakeWordState.unsupported);
    }
  }

  void _onText(String text) {
    if (!_listening || !_active || !heardWake(text, _names)) return;
    // Stop first: the call that follows needs the microphone.
    _listening = false;
    _suppressed = true;
    _active = false;
    _timer?.cancel();
    unawaited(source.stop());
    _set(KerabieWakeWordState.off);
    onWake();
  }

  /// The engine stopped by itself (engines end a session after a while, and report an error and then an end): listen
  /// again, once, unless it keeps failing. A stop that this controller asked for does not come back.
  void _onEnd() => _scheduleRestart();

  void _onError(String error) {
    // Our own stop, or the engine giving way to something else: not a reason to listen again.
    if (error == 'aborted') return;
    if (error == 'not-allowed') {
      _listening = false;
      _set(KerabieWakeWordState.denied);
      return;
    }
    // Hearing nothing for a while is normal, not a failure.
    if (error != 'no-speech') _failures++;
    _scheduleRestart();
  }

  void _scheduleRestart() {
    if (!_active || _suppressed || _disposed) return;
    _listening = false;
    _timer?.cancel();
    if (_failures >= maxFailures) return;
    _timer = Timer(restartDelay, () => unawaited(_begin()));
  }

  Future<void> _halt() async {
    _timer?.cancel();
    _timer = null;
    if (_listening) {
      _listening = false;
      await source.stop();
    }
  }

  void _set(KerabieWakeWordState next) {
    if (_state == next || _disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_listening) unawaited(source.stop());
    super.dispose();
  }
}
