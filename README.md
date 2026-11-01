# kerabie_helpdesk_flutter_calls

Voice and video calls for the [Kerabie](https://kerabie.com) help desk in a Flutter app. A call button and a call screen that sit on top of [`kerabie_helpdesk_flutter`](https://pub.dev/packages/kerabie_helpdesk_flutter).

Calls are a separate package so apps that only want chat do not carry the WebRTC code.

- Free agents are rung together and the first to answer wins
- The AI voice agent answers when nobody is free, if you turn it on
- A waiting screen with the customer's place in the queue
- Mute, camera and hang up; a call you reopen the app into is picked up again

## Before you start

- Chat set up with `kerabie_helpdesk_flutter` (a `KerabieProvider` above your app).
- Calls turned on in the dashboard under Settings, Calls, and call minutes on your plan.

## Install

```bash
flutter pub add kerabie_helpdesk_flutter_calls
```

It needs Flutter 3.27 or later and Dart 3.6 or later.

### iOS

Add a reason for the microphone, and the camera if you use video, to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Talk to our support team</string>
<key>NSCameraUsageDescription</key>
<string>Show our support team what you see</string>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.camera" />
<uses-feature android:name="android.hardware.camera.autofocus" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
```

## Add the button

```dart
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

// Anywhere under KerabieProvider. It shows nothing when calls are off or the plan has no minutes left.
const KerabieCallButton(label: 'Call us'),
const KerabieCallButton(label: 'Video call', video: true),
```

To put call buttons in the chat header itself, pass the icon variant to the provider. It is a widget you pass in, so the main package never carries the call code:

```dart
KerabieProvider(
  config: ...,
  callActions: const KerabieCallButton.icon(),
  child: ...,
)
```

The button opens a call screen with the queue position, ringing, the call itself and how it ended.

## Your own button

```dart
final call = KerabieCallController(KerabieProvider.of(context, listen: false));

if (call.available) {
  call.start(); // then show KerabieCallScreen(call: call, chat: chat), or your own screen
}
```

| Member | Description |
|---|---|
| `available`, `videoAvailable` | Calls, and video, are on in the dashboard |
| `phase` | `idle`, `starting`, `waiting`, `ringing`, `connected` or `ended` |
| `queuePosition` | Your place in line while `waiting` |
| `handler` | `HUMAN` or `AI`, once answered |
| `endReason` | `hangup`, `cancelled`, `missed`, `declined`, `limit` or `connection_lost` |
| `start({video})` | Starts a call; a customer who already has one is put back into it |
| `resume()` | Picks up a call that was going when the app was closed |
| `hangUp()` | Ends the call, or cancels it before it is answered |
| `toggleMicrophone()`, `toggleCamera()` | Mute and camera |
| `dismiss()` | Closes the call screen after it ended |

Call `dispose()` on a controller you create yourself.

## AI agent for your app

A voice agent inside your app that uses your tools as the signed-in customer, shows screens instead of reading lists, and hands over to your team with a summary. Read [AI agent for your app](https://kerabie.com/docs/ai/app-agent) for how tools, secure routes and screens work. It needs the same setup as calls: calls and the AI voice agent turned on in the dashboard, and the microphone permission.

```dart
import 'package:kerabie_helpdesk_flutter_calls/kerabie_helpdesk_flutter_calls.dart';

KerabieAgentButton(
  name: 'Kerabie Agent', // optional, shown on the button and the call screen
  getUserToken: () async => auth.currentToken, // null when nobody is signed in
  screens: {
    // Screens that need your data or your design. A list, a confirmation and an address box are built in.
    'pick_saved_address': (payload) async => pickAddress(payload['purpose']),  // the address id, or 'none' to type a new one
    'pick_schedule': (payload) async => pickDateTime(),                        // ISO 8601 date and time
    'open_screen': (payload) async { openScreen(payload['screen']); return 'opened'; },
  },
)
```

To let the agent do things in the app itself, such as adding to its own cart, pass `actions: {'add_to_cart': KerabieAgentAction(description: ..., parameters: {...}, run: (args) async => ...)}`. Each becomes a tool named `action_<name>`.

Each handler shows your screen and returns the customer's answer, which the agent reads back. Throw if the customer closes it. The agent only uses the screens you list. Addresses are never taken by voice. For your own design pass `KerabieAgentOptions(getUserToken:, screens:)` as `agent:` to `KerabieCallController`.

## One call at a time

Two calls cannot share the microphone, and only your app can see its other calls, so your app tells the package. Pass `otherCallActive` to `KerabieCallButton` and `KerabieAgentButton` (or set it on a `KerabieCallController`): true once the customer **answers** the other call, not while it only rings, so they choose first. A Kerabie call in progress then ends ("This call ended because another call started"), the buttons are disabled and a new call is refused. Set it back to false when the other call ends. A Kerabie call is never put on hold: a held call keeps running on Kerabie's side and the minutes count.

If your app already uses LiveKit, reuse it: `livekit_client` must be 2.13 or newer. If it uses another calling or WebRTC plugin, tell your team before adding this package, because two WebRTC stacks can clash.

## Wake the agent by saying its name

```dart
KerabieWakeWord(
  name: 'Ted',                  // the agent's name
  enabled: !inCall,             // never listen during a call
  source: MySpeechSource(),     // your speech plugin, see below
  onWake: startAgent,
)
```

"Ted", "hi Ted", "hello Ted" and "hey Ted" all wake it, and small mishearings of a longer name are forgiven. It listens only while the app is open on screen, uses recognition that runs on the phone unless you pass `onDeviceOnly: false`, and listens again only after `enabled` has been false and true again. Offer it as a setting the customer turns on: the microphone is open while it listens, and the phone shows its microphone indicator.

The package does not include a speech plugin, so apps that only want calls do not carry one. Implement `KerabieSpeechSource` around the plugin you use. An example with `speech_to_text` (check that plugin's current API, and add its microphone and speech permission strings):

```dart
class SttSource implements KerabieSpeechSource {
  final _stt = SpeechToText();

  @override
  Future<KerabieSpeechStart> start({required String language, required bool onDeviceOnly, required void Function(String) onText, required void Function() onEnd, required void Function(String) onError}) async {
    final ok = await _stt.initialize(
      onError: (e) => onError(e.errorMsg),
      onStatus: (s) { if (s == 'done' || s == 'notListening') onEnd(); },
    );
    if (!ok) return KerabieSpeechStart.denied;
    if (onDeviceOnly && !await _stt.hasPermission) return KerabieSpeechStart.denied;
    await _stt.listen(
      localeId: language,
      onResult: (r) => onText(r.recognizedWords),
      listenOptions: SpeechListenOptions(onDevice: onDeviceOnly, partialResults: true),
    );
    return KerabieSpeechStart.started;
  }

  @override
  Future<void> stop() => _stt.stop();
}
```

## How a call is handled

If you ask customers for their details before a chat (the pre-chat form in the dashboard), the call asks the same questions first, once. Pass `user` in `KerabieConfig`, or call `setUser` after login, and a customer you have identified is never asked. On a video call the customer sees the agent, with their own camera as a small picture in the corner.

A call goes to every free agent at once. When nobody is free the AI voice agent answers if you turned it on; otherwise the customer waits in the queue, and the call is marked missed after two minutes. Calls with a person and calls the AI answers are limited separately by your plan.

MIT licensed.
