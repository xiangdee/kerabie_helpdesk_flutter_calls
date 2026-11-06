import 'package:flutter/material.dart';
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

  Widget app({Widget? body}) => MaterialApp(
        builder: (context, child) => KerabieVoiceScope(controller: voice, palette: testPalette(), child: child!),
        home: Scaffold(body: body ?? const Center(child: Text('the app'))),
      );

  Future<void> startReady(WidgetTester tester) async {
    await voice.start();
    chat.emit('voice_ready');
    await tester.pump();
    await tester.pump();
  }

  testWidgets('nothing is drawn until a session starts, and the app is untouched', (tester) async {
    await tester.pumpWidget(app());

    expect(find.text('Kerabie Agent'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a session shows the panel with the orb, its state and what is said, over the visible app', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    chat.emit('voice_transcript', {'role': 'user', 'text': 'show me my order', 'final': false});
    chat.emit('voice_transcript', {'role': 'agent', 'text': 'Opening it now', 'final': false});
    await tester.pump();

    expect(find.text('Kerabie Agent'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('show me my order'), findsOneWidget);
    expect(find.text('Opening it now'), findsOneWidget);
    expect(find.byType(KerabieOrb), findsOneWidget);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('touches above the panel reach the app', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(body: Align(alignment: Alignment.topCenter, child: ElevatedButton(onPressed: () => taps++, child: const Text('Tap app')))));
    await startReady(tester);

    await tester.tap(find.text('Tap app'));

    expect(taps, 1);
  });

  testWidgets('the state words follow what the AI is doing', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    chat.emit('voice_state', {'state': 'thinking'});
    await tester.pump();
    // Working shows a changing word (Vibing, Wheezing, ...) with a please wait, so a wait never looks like a freeze.
    expect(find.textContaining('… please wait'), findsOneWidget);
    final first = tester.widget<Text>(find.textContaining('… please wait')).data;
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.widget<Text>(find.textContaining('… please wait')).data, isNot(first));

    chat.emit('voice_state', {'state': 'speaking'});
    await tester.pump();
    expect(find.text('Speaking'), findsOneWidget);
  });

  testWidgets('mute and unmute change the label and the status', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    await tester.tap(find.text('Mute'));
    await tester.pump();
    expect(find.text('Unmute'), findsOneWidget);
    expect(find.text('Muted'), findsOneWidget);

    await tester.tap(find.text('Unmute'));
    await tester.pump();
    expect(find.text('Mute'), findsOneWidget);
  });

  testWidgets('End stops the session and the panel goes away', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    await tester.tap(find.text('End'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(chat.stops, 1);
    expect(find.text('Kerabie Agent'), findsNothing);
  });

  testWidgets('the transcript opens to show every line, and closes again', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);
    for (final (i, text) in ['one', 'two', 'three'].indexed) {
      chat.emit('voice_transcript', {'role': i.isEven ? 'user' : 'agent', 'text': text, 'final': false});
      chat.emit('voice_transcript', {'role': i.isEven ? 'user' : 'agent', 'text': '', 'final': true});
    }
    await tester.pump();
    expect(find.text('one'), findsNothing); // only the last line of each speaker in the short panel

    await tester.tap(find.text('Transcript'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);

    await tester.tap(find.text('Smaller'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('one'), findsNothing);
  });

  testWidgets('it can shrink to a small orb that keeps listening, and open again', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await startReady(tester);

    await tester.tap(find.bySemanticsLabel('Make smaller'));
    await tester.pump();
    expect(find.text('Mute'), findsNothing);
    expect(find.byType(KerabieOrb), findsOneWidget);
    expect(voice.state.active, isTrue);

    expect(find.bySemanticsLabel(RegExp('Open Kerabie Agent')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kerabie-voice-small-orb')));
    await tester.pump();
    expect(find.text('Mute'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an error is shown in words and goes away by itself', (tester) async {
    await tester.pumpWidget(app());
    await voice.start();
    chat.emit('voice_error', {'code': 'limit_reached'});
    await tester.pump();

    expect(find.text('The voice minutes for this month are used up.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('The voice minutes for this month are used up.'), findsNothing);
  });

  testWidgets('the microphone being refused says so, with the name of the agent', (tester) async {
    audio.permission = false;
    await tester.pumpWidget(app());

    await voice.start();
    await tester.pump();

    expect(find.text('Allow the microphone to talk to Kerabie Agent.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Allow the microphone to talk to Kerabie Agent.'), findsNothing);
  });

  testWidgets('a session ended by the time limit is explained', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    chat.emit('voice_ended', {'reason': 'limit'});
    await tester.pump();

    expect(find.text('The session reached its time limit.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a goodbye ends quietly, with no message', (tester) async {
    await tester.pumpWidget(app());
    await startReady(tester);

    chat.emit('voice_ended', {'reason': 'goodbye'});
    await tester.pump();

    expect(find.text('Kerabie Agent'), findsNothing);
  });

  testWidgets('the button shows only when voice is available, and starts a session', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => KerabieVoiceScope(controller: voice, palette: testPalette(), child: child!),
      home: const Scaffold(body: Center(child: KerabieVoiceButton())),
    ));
    expect(find.text('Talk to Kerabie Agent'), findsOneWidget);

    await tester.tap(find.text('Talk to Kerabie Agent'));
    await tester.pump();
    expect(chat.started, [1]);
    expect(voice.state.active, isTrue);
    voice.stop(); // the connection timer must not outlive the test
    await tester.pump();
  });

  testWidgets('the button is hidden when calls are off, and disabled during another call', (tester) async {
    chat.aiVoiceEnabled = false;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => KerabieVoiceScope(controller: voice, palette: testPalette(), child: child!),
      home: const Scaffold(body: Center(child: KerabieVoiceButton())),
    ));
    expect(find.byType(FilledButton), findsNothing);

    chat.aiVoiceEnabled = true;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => KerabieVoiceScope(controller: voice, palette: testPalette(), child: child!),
      home: const Scaffold(body: Center(child: KerabieVoiceButton(otherCallActive: true))),
    ));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(chat.started, isEmpty);
  });
}
