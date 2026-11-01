import 'package:flutter/widgets.dart';

import 'wake_word.dart';

/// Wake the AI agent by saying its name ("Ted", "hi Ted", "hello Ted"). Put it anywhere in your tree; it draws nothing.
///
/// It listens only while the app is in the foreground and [enabled] is true, and it needs a [KerabieSpeechSource] (a few
/// lines around the speech plugin your app already uses). Pass `enabled: false` while a call is going or ringing, and
/// whenever your app should not be listening: it listens again once [enabled] has been false and true again.
///
/// ```dart
/// KerabieWakeWord(
///   name: 'Ted',
///   enabled: !inCall,
///   source: MySpeechSource(),
///   onWake: startAgent,
/// )
/// ```
class KerabieWakeWord extends StatefulWidget {
  const KerabieWakeWord({
    super.key,
    required this.name,
    required this.onWake,
    required this.source,
    this.enabled = true,
    this.aliases = const [],
    this.language = 'en-US',
    this.onDeviceOnly = true,
    this.onStateChanged,
  });

  /// The agent's name. Saying it alone, or after "hi", "hey" or "hello", wakes the agent.
  final String name;

  /// Called once when the name is heard.
  final VoidCallback onWake;

  final KerabieSpeechSource source;
  final bool enabled;

  /// Other spellings the speech engine produces for the name.
  final List<String> aliases;
  final String language;

  /// Only use recognition that runs on the phone, so no audio leaves it (default true).
  final bool onDeviceOnly;

  /// Why it is not listening: asking for permission, denied, or not supported on this phone.
  final ValueChanged<KerabieWakeWordState>? onStateChanged;

  @override
  State<KerabieWakeWord> createState() => _KerabieWakeWordState();
}

class _KerabieWakeWordState extends State<KerabieWakeWord> with WidgetsBindingObserver {
  late KerabieWakeWordController _controller;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = KerabieWakeWordController(
      name: widget.name,
      aliases: widget.aliases,
      source: widget.source,
      language: widget.language,
      onDeviceOnly: widget.onDeviceOnly,
      // The newest callback is used, so a rebuild with a new closure never leaves the old one behind.
      onWake: () => widget.onWake(),
    )..addListener(() => widget.onStateChanged?.call(_controller.state));
    _sync();
  }

  @override
  void didUpdateWidget(KerabieWakeWord old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.aliases != widget.aliases) _controller.rename(widget.name, widget.aliases);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() => _controller.setActive(widget.enabled && _foreground);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
