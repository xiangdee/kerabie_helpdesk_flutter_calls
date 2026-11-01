/// Voice and video calls for the Kerabie help desk in a Flutter app.
///
/// Add a [KerabieCallButton] anywhere under the `KerabieProvider` from `kerabie_helpdesk_flutter`. It appears when
/// calls are on in the Kerabie dashboard and your plan has minutes.
library;

export 'src/agent_button.dart' show KerabieAgentButton, kerabieDefaultAgentName;
export 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart' show KerabieAgentAction, KerabieAgentOptions, KerabieScreenHandler;
export 'src/call_button.dart' show KerabieCallButton;
export 'src/call_controller.dart' show KerabieCallController, KerabieCallPhase;
export 'src/call_screen.dart' show KerabieCallScreen;
export 'src/wake_word.dart' show KerabieSpeechSource, KerabieSpeechStart, KerabieWakeWordController, KerabieWakeWordState, heardWake, wakeNames;
export 'src/wake_word_widget.dart' show KerabieWakeWord;
