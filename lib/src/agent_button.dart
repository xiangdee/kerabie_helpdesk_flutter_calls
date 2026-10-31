import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

import 'agent_options.dart';
import 'agent_screens.dart';
import 'call_controller.dart';
import 'call_screen.dart';

/// The name of the agent unless you give it another.
const kerabieDefaultAgentName = 'Kerabie Agent';

/// A button that starts the AI voice agent, and the call screen it opens. Renders nothing when calls or the AI voice
/// agent are off in the dashboard, so it is safe to leave in your layout. Needs a [KerabieProvider] above it.
///
/// The agent uses the tools you connect to Kerabie as the signed-in customer ([getUserToken]) and asks your app to show
/// screens ([screens]) instead of reading lists aloud. A list, a confirmation and an address box are built in; add
/// `pick_saved_address`, `pick_schedule` and `open_screen` from your own data and navigation.
class KerabieAgentButton extends StatefulWidget {
  const KerabieAgentButton({
    super.key,
    this.name = kerabieDefaultAgentName,
    this.label,
    this.getUserToken,
    this.screens = const {},
    this.actions = const {},
  });

  /// The agent's name, on the button and the call screen.
  final String name;

  /// Button text. Defaults to "Talk to [name]".
  final String? label;

  /// The signed-in customer's token, or null when nobody is signed in.
  final FutureOr<String?> Function()? getUserToken;

  /// Your screens for the agent, by name. They replace the built-in ones of the same name.
  final Map<String, KerabieScreenHandler> screens;

  /// What the app can do for the agent on the device, such as adding to the app's own cart or starting its checkout.
  final Map<String, KerabieAgentAction> actions;

  @override
  State<KerabieAgentButton> createState() => _KerabieAgentButtonState();
}

class _KerabieAgentButtonState extends State<KerabieAgentButton> {
  KerabieCallController? _call;
  KerabieController? _chat;
  bool _screenOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = KerabieProvider.of(context, listen: false);
    if (_chat != chat) {
      _call?.dispose();
      _chat = chat;
      _call = KerabieCallController(chat, agent: _options());
      _call!.resume().then((resumed) {
        if (resumed && mounted) _openScreen();
      });
    }
  }

  KerabieAgentOptions _options() => KerabieAgentOptions(
        getUserToken: () => widget.getUserToken?.call(),
        // The call screen is on the root navigator, so dialogs are shown over it from there.
        screens: {
          ...builtInAgentScreens(() => Navigator.of(context, rootNavigator: true).context),
          ...widget.screens,
        },
        actions: widget.actions,
      );

  @override
  void dispose() {
    _call?.dispose();
    super.dispose();
  }

  Future<void> _openScreen() async {
    final call = _call;
    final chat = _chat;
    if (call == null || chat == null || _screenOpen) return;
    _screenOpen = true;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => KerabieCallScreen(call: call, chat: chat, aiName: widget.name)),
    );
    _screenOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final call = _call;
    if (chat == null || call == null) return const SizedBox.shrink();
    final palette = KerabiePalette.of(context, chat);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, call]),
      builder: (context, _) {
        if (!call.available) return const SizedBox.shrink();
        return FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.onPrimary,
            minimumSize: const Size(0, 44),
            shape: const StadiumBorder(),
          ),
          onPressed: call.phase == KerabieCallPhase.idle
              ? () {
                  call.start();
                  _openScreen();
                }
              : null,
          child: Text(widget.label ?? 'Talk to ${widget.name}'),
        );
      },
    );
  }
}
