import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

import 'call_controller.dart';
import 'call_screen.dart';

/// A "Call us" button and the call screen it opens. Renders nothing when calls are off in the dashboard or the plan
/// has no minutes left, so it is safe to leave in your layout. Needs a [KerabieProvider] above it.
class KerabieCallButton extends StatefulWidget {
  const KerabieCallButton({super.key, this.video = false, this.label = 'Call us'});

  /// Start with the camera on. Only used when the dashboard allows video.
  final bool video;
  final String label;

  @override
  State<KerabieCallButton> createState() => _KerabieCallButtonState();
}

class _KerabieCallButtonState extends State<KerabieCallButton> {
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
      _call = KerabieCallController(chat);
      // A call that was going when the app was closed picks up again.
      _call!.resume().then((resumed) {
        if (resumed && mounted) _openScreen();
      });
    }
  }

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
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => KerabieCallScreen(call: call, chat: chat)),
    );
    _screenOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final call = _call;
    if (chat == null || call == null) return const SizedBox.shrink();
    final palette = KerabiePalette.of(context, chat);
    // The settings arrive after the chat starts, so the button appears once the dashboard has said calls are on.
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
                  call.start(video: widget.video);
                  _openScreen();
                }
              : null,
          child: Text(widget.label),
        );
      },
    );
  }
}
