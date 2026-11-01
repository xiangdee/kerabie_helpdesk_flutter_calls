## 0.3.0

- `KerabieAgentButton`: the AI voice agent for your app. It uses your tools as the signed-in customer (`getUserToken`) and asks your app to show screens (`screens`) instead of reading lists aloud. A list, a confirmation and an address box are built in; add `pick_saved_address`, `pick_schedule` and `open_screen` yourself. The agent is called "Kerabie Agent" unless you pass `name`.
- `KerabieCallController` takes `agent: KerabieAgentOptions(...)` for your own design.
- `otherCallActive` on `KerabieCallButton`, `KerabieAgentButton` and `KerabieCallController`: true once your app has answered another call (Zego, Agora, CallKeep, your own LiveKit). A Kerabie call in progress ends (`endReason` is `other_call`) and a new one is refused until it is false again.
- `KerabieWakeWord`: wake the agent by saying its name ("Ted", "hi Ted", "hello Ted"). You give it a `KerabieSpeechSource`, a few lines around the speech plugin your app already uses, so the package does not force a speech plugin and its permission strings on every app. It listens only while the app is in the foreground and `enabled` is true, and uses on-device recognition by default.
- The agent's types and built-in screens moved into `kerabie_helpdesk_flutter` 0.5.0 (they are still exported from here).
- Needs `kerabie_helpdesk_flutter` 0.5.0 and `livekit_client` 2.13 or newer.

## 0.2.0

- `KerabieCallButton.icon()`: a phone (and a camera when video is on) for the chat header. Pass it to `KerabieProvider(callActions: ...)`.
- A call asks for the pre-chat details first when the organisation has the form on and the customer is not identified (a new `details` phase on `KerabieCallController`, and `submitDetails`).
- Video calls show the customer's own camera as a small picture over the agent's video (`KerabieCallController.localVideo`).
- Needs `kerabie_helpdesk_flutter` 0.4.0.

## 0.1.1

- Works with kerabie_helpdesk_flutter 0.2.0.

## 0.1.0

- First release: `KerabieCallButton`, `KerabieCallScreen` and `KerabieCallController`.
- Voice and video calls with your support team, with a waiting screen and the customer's place in the queue.
- A call the customer reopens the app into is picked up again.
