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
