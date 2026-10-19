import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

import 'support.dart';

void main() {
  late FakeChat chat;
  late FakeMedia media;
  late KerabieCallController call;
  late KerabieController kerabie;

  setUp(() {
    chat = FakeChat();
    media = FakeMedia();
    call = makeCall(chat, media);
    // Never started, so it makes no network calls; the screen only reads its colours from it.
    kerabie = KerabieController(config: const KerabieConfig(widgetKey: 'wk_test', appName: 'Test', appVersion: '1.0.0'));
  });
  tearDown(() {
    call.dispose();
    chat.close();
    kerabie.dispose();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: KerabieCallScreen(call: call, chat: kerabie)));
  }

  testWidgets('says the call is starting while the request is in flight', (tester) async {
    final reply = Completer<KerabieCallJoin>();
    chat.onStart = (_) => reply.future;
    unawaited(call.start());
    await show(tester);
    expect(find.text('Starting the call…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    reply.complete(join());
    await tester.pump();
  });

  testWidgets('shows the place in the queue while every agent is busy', (tester) async {
    chat.onStart = (_) async => join(status: 'QUEUED', position: 3);
    await call.start();
    await show(tester);
    expect(find.textContaining("You're number 3 in line"), findsOneWidget);
    expect(find.textContaining('connect you as soon as someone is free'), findsOneWidget);
  });

  testWidgets('says it is calling while agents are rung, and cancelling ends it', (tester) async {
    await call.start();
    await show(tester);
    expect(find.textContaining('Calling'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(chat.ended, [31]);
    expect(find.text('Call cancelled'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('in a call with a person: shows their name, the timer and the controls', (tester) async {
    await call.start();
    chat.emit('accepted', {'callId': 31, 'handler': 'HUMAN', 'agentName': 'Ada'});
    await tester.runAsync(pump);
    await show(tester);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Camera off'), findsNothing); // a voice call has no camera button
  });

  testWidgets('in a call with the AI', (tester) async {
    chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'AI');
    await call.start();
    await show(tester);
    expect(find.text('AI assistant'), findsOneWidget);
  });

  testWidgets('mute switches the button to Unmute', (tester) async {
    chat.onStart = (_) async => join(status: 'ACTIVE');
    await call.start();
    await show(tester);
    await tester.tap(find.text('Mute'));
    await tester.pump();
    expect(find.text('Unmute'), findsOneWidget);
  });

  testWidgets('a video call has a camera button', (tester) async {
    chat.onStart = (_) async => join(status: 'ACTIVE', video: true);
    await call.start(video: true);
    await show(tester);
    expect(find.text('Camera off'), findsOneWidget);
    await tester.tap(find.text('Camera off'));
    await tester.pump();
    expect(find.text('Camera on'), findsOneWidget);
  });

  testWidgets('ending the call shows how it ended, and Close dismisses it', (tester) async {
    chat.onStart = (_) async => join(status: 'ACTIVE');
    await call.start();
    await show(tester);
    chat.emit('ended', {'callId': 31, 'reason': 'missed'});
    await tester.runAsync(pump);
    await tester.pump();
    expect(find.textContaining('Nobody was available'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(call.phase, KerabieCallPhase.idle);
  });

  testWidgets('shows the server\'s message when the call could not start', (tester) async {
    chat.onStart = (_) async => throw KerabieException('Calls are not available right now', status: 403);
    await call.start();
    await show(tester);
    expect(find.text('Calls are not available right now'), findsOneWidget);
  });

  testWidgets('the screen closes itself when the call is dismissed', (tester) async {
    await call.start();
    await call.hangUp();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KerabieCallScreen(call: call, chat: kerabie))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);

    call.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
