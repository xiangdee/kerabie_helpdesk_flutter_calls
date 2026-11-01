import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

import 'support.dart';

void main() {
  late FakeChat chat;
  late FakeMedia media;
  late KerabieCallController call;

  setUp(() {
    chat = FakeChat();
    media = FakeMedia();
    call = makeCall(chat, media);
  });
  tearDown(() {
    call.dispose();
    chat.close();
  });

  group('availability', () {
    test('follows the dashboard: calls and video', () {
      expect(call.available, isTrue);
      expect(call.videoAvailable, isTrue);
      chat.videoEnabled = false;
      expect(call.videoAvailable, isFalse);
      chat.callsEnabled = false;
      expect(call.available, isFalse);
      expect(call.videoAvailable, isFalse);
    });

    test('does nothing when calls are off', () async {
      chat.callsEnabled = false;
      await call.start();
      expect(call.phase, KerabieCallPhase.idle);
      expect(chat.startCalls, isEmpty);
    });
  });

  group('pre-chat details', () {
    test('asks for them before placing the call', () async {
      chat.needsDetails = true;
      await call.start(video: true);
      expect(call.phase, KerabieCallPhase.details);
      expect(chat.startCalls, isEmpty);
    });

    test('places the call, with the video choice kept, once they are filled in', () async {
      chat.needsDetails = true;
      await call.start(video: true);
      await call.submitDetails({'name': 'Ada'});
      expect(chat.submitted, [{'name': 'Ada'}]);
      expect(chat.startCalls, [true]);
      expect(call.phase, isNot(KerabieCallPhase.details));
    });

    test('closes without a call when cancelled', () async {
      chat.needsDetails = true;
      await call.start();
      await call.hangUp();
      expect(call.phase, KerabieCallPhase.idle);
      expect(chat.startCalls, isEmpty);
      expect(chat.ended, isEmpty);
    });

    test('does not ask again once details are known', () async {
      await call.start();
      expect(chat.startCalls, hasLength(1));
    });
  });

  group('starting', () {
    test('the AI answers at once: joins the room and is connected', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'AI');
      await call.start();
      expect(call.phase, KerabieCallPhase.connected);
      expect(call.handler, 'AI');
      expect(media.joins.single, (url: 'wss://lk.test', token: 'jwt-31', video: false));
    });

    test('rings free agents without joining the room yet', () async {
      await call.start();
      expect(call.phase, KerabieCallPhase.ringing);
      expect(media.joins, isEmpty);
    });

    test('waits in the queue and says the place in line', () async {
      chat.onStart = (_) async => join(status: 'QUEUED', position: 2);
      await call.start();
      expect(call.phase, KerabieCallPhase.waiting);
      expect(call.queuePosition, 2);
    });

    test('shows starting while the request is in flight', () async {
      final reply = Completer<KerabieCallJoin>();
      chat.onStart = (_) => reply.future;
      final started = call.start();
      expect(call.phase, KerabieCallPhase.starting);
      reply.complete(join());
      await started;
      expect(call.phase, KerabieCallPhase.ringing);
    });

    test('ignores a second start while a call is going', () async {
      await call.start();
      await call.start();
      expect(chat.startCalls, hasLength(1));
    });

    test('asks for video only when the dashboard allows it', () async {
      await call.start(video: true);
      expect(chat.startCalls.single, isTrue);
      expect(call.video, isTrue);
    });

    test('drops the camera when video is not allowed', () async {
      chat.videoEnabled = false;
      chat.onStart = (v) async => join(status: 'ACTIVE', video: v);
      await call.start(video: true);
      expect(chat.startCalls.single, isFalse);
      expect(media.joins.single.video, isFalse);
    });

    test('says why when the server refuses', () async {
      chat.onStart = (_) async => throw KerabieException('Calls are not available right now', status: 403);
      await call.start();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.error, 'Calls are not available right now');
    });

    test('gives a plain message for any other failure', () async {
      chat.onStart = (_) async => throw StateError('boom');
      await call.start();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.error, isNotNull);
      expect(call.error, isNot(contains('boom')));
    });
  });

  group('following the call', () {
    test('ringing, then answered by a person: joins the room with that agent\'s name', () async {
      await call.start();
      chat.emit('accepted', {'callId': 31, 'handler': 'HUMAN', 'agentName': 'Ada'});
      await pump();
      expect(call.phase, KerabieCallPhase.connected);
      expect(call.handler, 'HUMAN');
      expect(call.agentName, 'Ada');
      expect(media.joins, hasLength(1));
    });

    test('moves between waiting and ringing as the server says', () async {
      chat.onStart = (_) async => join(status: 'QUEUED', position: 3);
      await call.start();
      chat.emit('queued', {'callId': 31, 'position': 1});
      expect(call.queuePosition, 1);
      chat.emit('ringing');
      expect(call.phase, KerabieCallPhase.ringing);
    });

    test('joins only once however many times it is told it was answered', () async {
      await call.start();
      chat.emit('accepted', {'callId': 31, 'handler': 'HUMAN'});
      chat.emit('accepted', {'callId': 31, 'handler': 'HUMAN'});
      await pump();
      expect(media.joins, hasLength(1));
    });

    test('being answered before the reply to the start request still connects', () async {
      final reply = Completer<KerabieCallJoin>();
      chat.onStart = (_) => reply.future;
      final started = call.start();
      chat.emit('accepted', {'callId': 31, 'handler': 'HUMAN', 'agentName': 'Ada'});
      reply.complete(join(status: 'RINGING'));
      await started;
      await pump();
      expect(call.phase, KerabieCallPhase.connected);
      expect(media.joins, hasLength(1));
    });

    test('the call ending before the reply arrives stays ended', () async {
      final reply = Completer<KerabieCallJoin>();
      chat.onStart = (_) => reply.future;
      final started = call.start();
      chat.emit('ended', {'callId': 31, 'reason': 'missed'});
      reply.complete(join());
      await started;
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.endReason, 'missed');
      expect(media.joins, isEmpty);
    });

    test('the other side hanging up ends the call and leaves the room', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'HUMAN');
      await call.start();
      chat.emit('ended', {'callId': 31, 'reason': 'hangup'});
      await pump();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.endReason, 'hangup');
      expect(media.leaves, 1);
    });

    test('reports when the minutes ran out', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      chat.emit('ended', {'callId': 31, 'reason': 'limit'});
      await pump();
      expect(call.endReason, 'limit');
    });

    test('ignores events about another call', () async {
      await call.start();
      chat.emit('ended', {'callId': 99, 'reason': 'hangup'});
      chat.emit('accepted', {'callId': 99, 'handler': 'HUMAN'});
      await pump();
      expect(call.phase, KerabieCallPhase.ringing);
      expect(media.joins, isEmpty);
    });

    test('ignores events when there is no call', () async {
      chat.emit('ended', {'callId': 31, 'reason': 'hangup'});
      chat.emit('accepted', {'callId': 31});
      await pump();
      expect(call.phase, KerabieCallPhase.idle);
    });

    test('a dropped connection ends the call', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      media.onDisconnected!.call();
      await pump();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.endReason, 'connection_lost');
    });
  });

  group('when joining the room fails', () {
    test('ends the call with a plain message and frees the customer', () async {
      media.joinError = StateError('no microphone');
      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      await pump();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.error, contains('microphone'));
      expect(chat.ended, [31]);
      expect(media.leaves, greaterThanOrEqualTo(1));
    });
  });

  group('hanging up', () {
    test('cancels a call that was not answered yet', () async {
      await call.start();
      await call.hangUp();
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.endReason, 'cancelled');
      expect(chat.ended, [31]);
    });

    test('ends a call in progress and leaves the room', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      await call.hangUp();
      expect(call.endReason, 'hangup');
      expect(chat.ended, [31]);
      expect(media.leaves, 1);
    });

    test('does nothing with no call, or one that already ended', () async {
      await call.hangUp();
      expect(chat.ended, isEmpty);
      await call.start();
      await call.hangUp();
      await call.hangUp();
      expect(chat.ended, [31]);
    });

    test('still ends locally when the server cannot be reached', () async {
      chat.endError = KerabieException('offline');
      await call.start();
      await expectLater(call.hangUp(), completes);
      expect(call.phase, KerabieCallPhase.ended);
    });

    test('dismiss returns to idle only after the call ended', () async {
      await call.start();
      call.dismiss();
      expect(call.phase, KerabieCallPhase.ringing);
      await call.hangUp();
      call.dismiss();
      expect(call.phase, KerabieCallPhase.idle);
      expect(call.callId, isNull);
    });

    test('a new call can start after the last one was dismissed', () async {
      await call.start();
      await call.hangUp();
      call.dismiss();
      await call.start();
      expect(chat.startCalls, hasLength(2));
      expect(call.phase, KerabieCallPhase.ringing);
    });
  });

  group('microphone and camera', () {
    test('mute and unmute during a call', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      expect(call.microphoneOn, isTrue);
      await call.toggleMicrophone();
      expect(call.microphoneOn, isFalse);
      await call.toggleMicrophone();
      expect(call.microphoneOn, isTrue);
    });

    test('camera switches only on a video call', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', video: true);
      await call.start(video: true);
      expect(call.cameraOn, isTrue);
      await call.toggleCamera();
      expect(call.cameraOn, isFalse);
    });

    test('camera and microphone controls do nothing outside a call, or without video', () async {
      await call.toggleMicrophone();
      await call.toggleCamera();
      expect(media.microphoneOn, isTrue);

      chat.onStart = (_) async => join(status: 'ACTIVE');
      await call.start();
      await call.toggleCamera();
      expect(media.cameraOn, isFalse);
    });

    test('a camera that cannot start does not end the call', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', video: true);
      await call.start(video: true);
      media.cameraError = StateError('denied');
      await expectLater(call.toggleCamera(), completes);
      expect(call.phase, KerabieCallPhase.connected);
    });
  });

  group('resume', () {
    test('picks up a call that was still going', () async {
      chat.current = join(status: 'ACTIVE', handler: 'HUMAN');
      expect(await call.resume(), isTrue);
      expect(call.phase, KerabieCallPhase.connected);
      expect(media.joins, hasLength(1));
    });

    test('shows the queue for a call that is still waiting', () async {
      chat.current = join(status: 'QUEUED', position: 4);
      expect(await call.resume(), isTrue);
      expect(call.phase, KerabieCallPhase.waiting);
      expect(call.queuePosition, 4);
    });

    test('returns false with no call, on an error, when calls are off, or when a call is already going', () async {
      expect(await call.resume(), isFalse);

      chat.currentError = KerabieException('offline');
      expect(await call.resume(), isFalse);
      chat.currentError = null;

      chat.callsEnabled = false;
      chat.current = join(status: 'ACTIVE');
      expect(await call.resume(), isFalse);
      chat.callsEnabled = true;

      await call.start();
      expect(await call.resume(), isFalse);
    });
  });

  test('notifies listeners as the call moves', () async {
    var changes = 0;
    call.addListener(() => changes++);
    chat.onStart = (_) async => join(status: 'ACTIVE');
    await call.start();
    await call.hangUp();
    expect(changes, greaterThanOrEqualTo(3));
  });

  test('does not touch anything after being disposed', () async {
    final other = makeCall(chat, FakeMedia());
    other.dispose();
    chat.emit('ended');
    await pump();
  });

  group('the AI agent', () {
    KerabieCallController? agent;
    // Not every test makes one.
    tearDown(() {
      agent?.dispose();
      agent = null;
    });

    KerabieCallController make(KerabieAgentOptions options) => agent = KerabieCallController.forChat(chat, media: media, agent: options);

    test('sends the signed-in customer token and the screens the app can show', () async {
      make(KerabieAgentOptions(getUserToken: () async => 'jwt-abc', screens: {'confirm_action': (_) async => 'yes', 'pick_schedule': (_) async => 'x'}));
      await agent!.start();
      expect(chat.startTokens.single, 'jwt-abc');
      expect(chat.startTools.single, ['confirm_action', 'pick_schedule']);
    });

    test('sends no token when nobody is signed in, and when the token cannot be read', () async {
      make(KerabieAgentOptions(getUserToken: () async => null, screens: const {}));
      await agent!.start();
      expect(chat.startTokens.single, isNull);
      agent!.dispose();
      chat.startTokens.clear();
      make(KerabieAgentOptions(getUserToken: () => throw StateError('storage'), screens: const {}));
      await agent!.start();
      expect(chat.startTokens.single, isNull);
    });

    test('hands the screens to the room when the call connects', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'AI');
      make(KerabieAgentOptions(screens: {'confirm_action': (_) async => 'yes'}));
      await agent!.start();
      expect(media.joinedScreens.keys, ['confirm_action']);
    });

    test('describes the app\'s actions to the server and hands them to the room', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'AI');
      make(KerabieAgentOptions(actions: {
        'add_to_cart': KerabieAgentAction(
          description: 'Adds an item to the cart in the app',
          parameters: const {'type': 'object', 'properties': {'itemId': {'type': 'string'}}},
          run: (args) async => 'added',
        ),
      }));
      await agent!.start();
      expect(chat.startActions.single, [
        {
          'name': 'add_to_cart',
          'description': 'Adds an item to the cart in the app',
          'parameters': {'type': 'object', 'properties': {'itemId': {'type': 'string'}}},
        },
      ]);
      expect(media.joinedActions.keys, ['add_to_cart']);
      expect(await media.joinedActions['add_to_cart']!.run({}), 'added');
    });

    test('a plain call sends no token and no screens', () async {
      await call.start();
      expect(chat.startTokens.single, isNull);
      expect(chat.startTools.single, isEmpty);
      expect(chat.startActions.single, isEmpty);
    });
  });

  group('one call at a time', () {
    test('will not start a call while the app has another one', () async {
      call.otherCallActive = true;
      await call.start();
      expect(chat.startCalls, isEmpty);
      expect(call.phase, KerabieCallPhase.idle);
      call.otherCallActive = false;
      await call.start();
      expect(chat.startCalls, hasLength(1));
    });

    test('ends a call in progress when the app answers another, and tells the server', () async {
      chat.onStart = (_) async => join(status: 'ACTIVE', handler: 'AI');
      await call.start();
      expect(call.phase, KerabieCallPhase.connected);
      call.otherCallActive = true;
      await Future<void>.delayed(Duration.zero);
      expect(call.phase, KerabieCallPhase.ended);
      expect(call.endReason, 'other_call');
      expect(chat.ended, [31]);
      expect(media.leaves, greaterThan(0));
    });

    test('ends a call that is still ringing or waiting', () async {
      await call.start();
      expect(call.phase, KerabieCallPhase.ringing);
      call.otherCallActive = true;
      await Future<void>.delayed(Duration.zero);
      expect(call.endReason, 'other_call');
      expect(chat.ended, [31]);
    });

    test('closes the details form without calling anyone', () async {
      chat.needsDetails = true;
      await call.start();
      expect(call.phase, KerabieCallPhase.details);
      call.otherCallActive = true;
      await Future<void>.delayed(Duration.zero);
      expect(call.phase, KerabieCallPhase.idle);
      expect(chat.ended, isEmpty);
    });

    test('ends a call that was still being placed when the other call started', () async {
      final reply = Completer<KerabieCallJoin>();
      chat.onStart = (_) => reply.future;
      final starting = call.start();
      await Future<void>.delayed(Duration.zero);
      call.otherCallActive = true;
      reply.complete(join());
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(call.endReason, 'other_call');
      expect(chat.ended, [31]);
    });

    test('does nothing when there is no call, and when the flag does not change', () async {
      call.otherCallActive = true;
      call.otherCallActive = true;
      expect(call.phase, KerabieCallPhase.idle);
      expect(chat.ended, isEmpty);
    });
  });
}
