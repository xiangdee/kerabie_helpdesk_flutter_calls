# kerabie_helpdesk_flutter_calls

Voice and video calls for the [Kerabie](https://kerabie.com) help desk in a Flutter app. A call button and a call screen that sit on top of [`kerabie_helpdesk_flutter`](https://pub.dev/packages/kerabie_helpdesk_flutter).

Calls are a separate package so apps that only want chat do not carry the WebRTC code.

- Free agents are rung together and the first to answer wins
- The AI voice agent answers when nobody is free, if you turn it on
- A waiting screen with the customer's place in the queue
- Mute, camera and hang up; a call you reopen the app into is picked up again

## Before you start

- Chat set up with `kerabie_helpdesk_flutter` (a `KerabieProvider` above your app).
- Calls turned on in the dashboard under Settings, Widget, Calls, and call minutes on your plan.

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

## How a call is handled

A call goes to every free agent at once. When nobody is free the AI voice agent answers if you turned it on; otherwise the customer waits in the queue, and the call is marked missed after two minutes. Calls with a person and calls the AI answers are limited separately by your plan.

MIT licensed.
