/// Where a live voice session stands: not started, connecting, or going on.
enum KerabieVoicePhase { idle, connecting, active }

/// What the AI is doing while a session goes on.
enum KerabieVoiceActivity { listening, thinking, speaking }

/// Why a session could not start or was cut off.
enum KerabieVoiceError { unavailable, limitReached, busy, permission, connection }

/// One line of the conversation, as it is said.
class KerabieVoiceLine {
  const KerabieVoiceLine({required this.id, required this.fromCustomer, required this.text, this.finished = false});

  final int id;
  final bool fromCustomer;
  final String text;

  /// The speaker has finished this line.
  final bool finished;

  KerabieVoiceLine copyWith({String? text, bool? finished}) =>
      KerabieVoiceLine(id: id, fromCustomer: fromCustomer, text: text ?? this.text, finished: finished ?? this.finished);
}

/// Everything the orb and the panel draw. Never changed in place: each change makes a new one.
class KerabieVoiceState {
  const KerabieVoiceState({
    this.phase = KerabieVoicePhase.idle,
    this.activity = KerabieVoiceActivity.listening,
    this.lines = const [],
    this.muted = false,
    this.error,
    this.endedReason,
  });

  final KerabieVoicePhase phase;
  final KerabieVoiceActivity activity;

  /// The last few lines, oldest first.
  final List<KerabieVoiceLine> lines;
  final bool muted;
  final KerabieVoiceError? error;

  /// Why the last session ended (`goodbye`, `limit`, `idle`, ...), until the next one starts.
  final String? endedReason;

  /// A session is starting or going on.
  bool get active => phase != KerabieVoicePhase.idle;

  static const maxLines = 8;

  KerabieVoiceState _with({KerabieVoicePhase? phase, KerabieVoiceActivity? activity, List<KerabieVoiceLine>? lines, bool? muted, KerabieVoiceError? error, String? endedReason, bool clearMessage = false}) =>
      KerabieVoiceState(
        phase: phase ?? this.phase,
        activity: activity ?? this.activity,
        lines: lines ?? this.lines,
        muted: muted ?? this.muted,
        error: clearMessage ? null : (error ?? this.error),
        endedReason: clearMessage ? null : (endedReason ?? this.endedReason),
      );

  KerabieVoiceState connecting() => KerabieVoiceState(phase: KerabieVoicePhase.connecting, muted: muted);

  KerabieVoiceState ready() => _with(phase: KerabieVoicePhase.active, activity: KerabieVoiceActivity.listening);

  /// Only while a session is active: a late event from a finished one must not bring it back.
  KerabieVoiceState withActivity(KerabieVoiceActivity next) => phase == KerabieVoicePhase.active ? _with(activity: next) : this;

  /// A piece of what someone said. Pieces of one speaker become one line; a change of speaker starts a new one.
  KerabieVoiceState withTranscript({required bool fromCustomer, required String text, required bool finished}) {
    final lines = List<KerabieVoiceLine>.of(this.lines);
    if (finished) {
      // Closes the speaker's open line. An empty closing piece never makes a line of its own.
      for (var i = lines.length - 1; i >= 0; i--) {
        if (lines[i].fromCustomer == fromCustomer && !lines[i].finished) {
          lines[i] = lines[i].copyWith(finished: true);
          break;
        }
      }
      return _with(lines: lines);
    }
    final last = lines.isEmpty ? null : lines.last;
    if (last != null && last.fromCustomer == fromCustomer && !last.finished) {
      lines[lines.length - 1] = last.copyWith(text: last.text + text);
    } else {
      lines.add(KerabieVoiceLine(id: (last?.id ?? 0) + 1, fromCustomer: fromCustomer, text: text));
    }
    return _with(lines: lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines);
  }

  /// The customer spoke over the AI: what it was saying is finished, and it listens.
  KerabieVoiceState interrupted() =>
      _with(activity: KerabieVoiceActivity.listening, lines: [for (final l in lines) l.fromCustomer ? l : l.copyWith(finished: true)]);

  KerabieVoiceState withMuted(bool value) => _with(muted: value);

  KerabieVoiceState failed(KerabieVoiceError why) => _with(phase: KerabieVoicePhase.idle, error: why);

  KerabieVoiceState ended(String reason) => _with(phase: KerabieVoicePhase.idle, activity: KerabieVoiceActivity.listening, endedReason: reason);

  /// Clears an error or a goodbye message once it has been seen.
  KerabieVoiceState dismissed() => KerabieVoiceState(muted: muted);
}
