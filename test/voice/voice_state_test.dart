import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

KerabieVoiceState active() => const KerabieVoiceState().connecting().ready();

void main() {
  test('a session goes from connecting to active and back to idle with the reason', () {
    var s = const KerabieVoiceState().connecting();
    expect(s.phase, KerabieVoicePhase.connecting);
    s = s.ready();
    expect(s.phase, KerabieVoicePhase.active);
    s = s.ended('goodbye');
    expect(s.phase, KerabieVoicePhase.idle);
    expect(s.endedReason, 'goodbye');
  });

  test('starting again clears the last conversation, error and reason', () {
    final s = active().withTranscript(fromCustomer: true, text: 'hi', finished: false).ended('limit').connecting();
    expect(s.lines, isEmpty);
    expect(s.endedReason, isNull);
    expect(s.error, isNull);
  });

  test('activity only changes while a session is active', () {
    expect(const KerabieVoiceState().withActivity(KerabieVoiceActivity.speaking).activity, KerabieVoiceActivity.listening);
    expect(active().withActivity(KerabieVoiceActivity.speaking).activity, KerabieVoiceActivity.speaking);
  });

  test('pieces of one speaker become one line; a change of speaker starts a new one', () {
    final s = active()
        .withTranscript(fromCustomer: true, text: 'show me', finished: false)
        .withTranscript(fromCustomer: true, text: ' my order', finished: false)
        .withTranscript(fromCustomer: true, text: '', finished: true)
        .withTranscript(fromCustomer: false, text: 'Here it is', finished: false);
    expect(s.lines.map((l) => (l.fromCustomer, l.text, l.finished)), [(true, 'show me my order', true), (false, 'Here it is', false)]);
  });

  test('a finished line is not added to by the next piece', () {
    final s = active()
        .withTranscript(fromCustomer: true, text: 'a', finished: false)
        .withTranscript(fromCustomer: true, text: '', finished: true)
        .withTranscript(fromCustomer: true, text: 'b', finished: false);
    expect(s.lines.map((l) => l.text), ['a', 'b']);
  });

  test('a closing piece with no open line adds nothing', () {
    expect(active().withTranscript(fromCustomer: false, text: '', finished: true).lines, isEmpty);
  });

  test('an interruption finishes what the AI was saying and goes back to listening', () {
    final s = active()
        .withActivity(KerabieVoiceActivity.speaking)
        .withTranscript(fromCustomer: false, text: 'Your order is', finished: false)
        .interrupted();
    expect(s.activity, KerabieVoiceActivity.listening);
    expect(s.lines.single.finished, isTrue);
  });

  test('only the last few lines are kept', () {
    var s = active();
    for (var i = 0; i < KerabieVoiceState.maxLines + 5; i++) {
      final customer = i.isEven;
      s = s.withTranscript(fromCustomer: customer, text: '$i', finished: false).withTranscript(fromCustomer: customer, text: '', finished: true);
    }
    expect(s.lines, hasLength(KerabieVoiceState.maxLines));
    expect(s.lines.last.text, '${KerabieVoiceState.maxLines + 4}');
  });

  test('an error ends the attempt and says why', () {
    final s = const KerabieVoiceState().connecting().failed(KerabieVoiceError.limitReached);
    expect(s.phase, KerabieVoicePhase.idle);
    expect(s.error, KerabieVoiceError.limitReached);
    expect(s.active, isFalse);
  });

  test('mute is remembered, also into the next session', () {
    final muted = const KerabieVoiceState().withMuted(true);
    expect(muted.muted, isTrue);
    expect(muted.connecting().muted, isTrue);
    expect(muted.dismissed().muted, isTrue);
  });

  test('dismissing a message goes back to idle and clears it', () {
    expect(const KerabieVoiceState().connecting().failed(KerabieVoiceError.busy).dismissed().error, isNull);
    expect(active().ended('limit').dismissed().endedReason, isNull);
  });
}
