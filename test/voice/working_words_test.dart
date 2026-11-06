import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter_calls/src/voice/working_words.dart';

void main() {
  test('one word per tick, cycling through all of them, from any seed', () {
    expect({for (var i = 0; i < workingWords.length; i++) workingWord(i)}.length, workingWords.length);
    expect(workingWord(workingWords.length), workingWord(0));
    expect(workingWord(3, 5), workingWord(8));
    expect(workingWords.every((w) => RegExp(r'^[A-Z][a-z]+$').hasMatch(w)), isTrue);
  });
}
