import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

import 'orb.dart';
import 'voice_audio.dart';
import 'voice_controller.dart';
import 'voice_state.dart';
import 'working_words.dart';

/// Gives everything below it the live voice session, and draws the voice panel over the app. Put it once near the root,
/// inside [KerabieProvider], for example in `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(builder: (context, child) => KerabieVoiceScope(child: child!))
/// ```
///
/// The panel sits at the bottom and leaves the app above it visible and usable, so the customer sees the app change as the
/// AI opens screens and fills things in.
class KerabieVoiceScope extends StatefulWidget {
  const KerabieVoiceScope({super.key, required this.child, this.name = 'Kerabie Agent', this.bottomInset = 0, this.audio, this.controller, this.palette});

  final Widget child;

  /// What the AI is called on screen.
  final String name;

  /// Space to keep clear at the bottom, for a tab bar.
  final double bottomInset;

  /// The microphone and the speaker. Only tests give their own.
  final KerabieVoiceAudio? audio;

  /// A controller you made yourself (for tests). Without one, the scope makes its own from the `KerabieProvider` above it.
  final KerabieVoiceController? controller;

  /// The panel's colours. Without them they follow the chat's theme and the light or dark mode.
  final KerabiePalette? palette;

  /// The session controller, for your own button. Use [KerabieVoiceButton] for the usual one.
  static KerabieVoiceController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    assert(scope != null, 'Put a KerabieVoiceScope above this widget.');
    return scope!.notifier!;
  }

  @override
  State<KerabieVoiceScope> createState() => _KerabieVoiceScopeState();
}

class _KerabieVoiceScopeState extends State<KerabieVoiceScope> {
  KerabieVoiceController? _controller;
  KerabieController? _kerabie;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null) {
      _controller = widget.controller;
      return;
    }
    _kerabie = KerabieProvider.of(context, listen: false);
    _controller ??= KerabieVoiceController(chat: KerabieVoiceChat.from(_kerabie!), audio: widget.audio);
  }

  @override
  void dispose() {
    // A controller that was handed in belongs to whoever made it.
    if (widget.controller == null) _controller?.dispose();
    super.dispose();
  }

  KerabiePalette _palette(BuildContext context) => widget.palette ?? KerabiePalette.of(context, _kerabie!);

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return _Scope(
      notifier: controller,
      child: _KerabieVoicePanel(controller: controller, palette: _palette, name: widget.name, bottomInset: widget.bottomInset, app: widget.child),
    );
  }
}

class _Scope extends InheritedNotifier<KerabieVoiceController> {
  const _Scope({required super.notifier, required super.child});
}

/// A button that starts a voice session. Renders nothing when calls are off in the dashboard, so it is safe to leave in
/// your layout. Needs a [KerabieVoiceScope] above it.
class KerabieVoiceButton extends StatelessWidget {
  const KerabieVoiceButton({super.key, this.label = 'Talk to Kerabie Agent', this.otherCallActive = false});

  final String label;

  /// True while your app has a call going on: two things cannot share the microphone, so the button is disabled.
  final bool otherCallActive;

  @override
  Widget build(BuildContext context) {
    final voice = KerabieVoiceScope.of(context);
    if (!voice.available) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: otherCallActive || voice.state.active ? null : voice.start,
      icon: const Icon(Icons.mic),
      label: Text(label),
    );
  }
}

String _errorText(KerabieVoiceError e, String name) => switch (e) {
      KerabieVoiceError.unavailable => '$name is not available right now.',
      KerabieVoiceError.limitReached => 'The voice minutes for this month are used up.',
      KerabieVoiceError.busy => 'Voice is busy at the moment. Try again in a moment.',
      KerabieVoiceError.permission => 'Allow the microphone to talk to $name.',
      KerabieVoiceError.connection => 'The connection dropped. Try again.',
    };

const _endedText = {
  'limit': 'The session reached its time limit.',
  'idle': 'The session ended because it was quiet.',
  'error': 'Something went wrong. Try again.',
};

class _KerabieVoicePanel extends StatefulWidget {
  const _KerabieVoicePanel({required this.controller, required this.palette, required this.name, required this.bottomInset, required this.app});

  final KerabieVoiceController controller;
  final KerabiePalette Function(BuildContext) palette;
  final String name;
  final double bottomInset;
  final Widget app;

  @override
  State<_KerabieVoicePanel> createState() => _KerabieVoicePanelState();
}

class _KerabieVoicePanelState extends State<_KerabieVoicePanel> {
  bool _expanded = false;
  bool _small = false;
  Timer? _dismiss;
  int _tick = 0;
  final int _seed = DateTime.now().microsecondsSinceEpoch % 1000;
  Timer? _words;

  /// The app takes the space above the panel, so the panel never covers what the AI shows in it. The slots never move
  /// (the app is always the first child), so the app's own state survives the panel coming and going.
  Widget _frame({Widget? panel, Widget? orb}) => Stack(fit: StackFit.expand, children: [
        Column(children: [Expanded(child: widget.app), panel ?? const SizedBox.shrink()]),
        orb ?? const SizedBox.shrink(),
      ]);

  String? _message(KerabieVoiceState s) => s.error != null ? _errorText(s.error!, widget.name) : _endedText[s.endedReason];

  @override
  void dispose() {
    _dismiss?.cancel();
    _words?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = widget.controller.state;
        final message = s.active ? null : _message(s);

        // A message is shown for a few seconds, then the panel goes away by itself.
        _dismiss?.cancel();
        if (message != null) _dismiss = Timer(const Duration(seconds: 5), widget.controller.dismiss);
        if (!s.active && (_expanded || _small)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _expanded = _small = false);
          });
        }

        // While the AI works, the status changes word by word (Vibing, Wheezing, ...) so a wait never looks like a freeze.
        final working = s.active && s.activity == KerabieVoiceActivity.thinking;
        if (working && _words == null) {
          _words = Timer.periodic(const Duration(milliseconds: 1400), (_) {
            if (mounted) setState(() => _tick++);
          });
        } else if (!working && _words != null) {
          _words!.cancel();
          _words = null;
        }

        if (!s.active && message == null) return _frame();
        final palette = widget.palette(context);

        if (_small && s.active) {
          return _frame(
            orb: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + widget.bottomInset),
              child: Semantics(
                button: true,
                label: 'Open ${widget.name}',
                child: GestureDetector(
                  key: const ValueKey('kerabie-voice-small-orb'),
                  onTap: () => setState(() => _small = false),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background, border: Border.all(color: palette.border), boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))]),
                    child: Center(child: KerabieOrb(activity: s.activity, levels: widget.controller.levels, color: palette.primary, size: 30)),
                  ),
                ),
              ),
            ),
          ));
        }

        final height = MediaQuery.sizeOf(context).height;
        final panelHeight = (height * (_expanded ? 0.6 : 0.27)).clamp(260.0, double.infinity);
        final style = TextStyle(color: palette.text, fontFamily: palette.fontFamily, decoration: TextDecoration.none);
        final status = message != null
            ? ''
            : s.phase == KerabieVoicePhase.connecting
                ? 'Connecting'
                : s.muted
                    ? 'Muted'
                    : switch (s.activity) { KerabieVoiceActivity.listening => 'Listening', KerabieVoiceActivity.thinking => '${workingWord(_tick, _seed)}… please wait', KerabieVoiceActivity.speaking => 'Speaking' };

        final lastCustomer = s.lines.where((l) => l.fromCustomer).lastOrNull;
        final lastAgent = s.lines.where((l) => !l.fromCustomer).lastOrNull;

        return _frame(
          panel: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: panelHeight,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + widget.bottomInset),
              decoration: BoxDecoration(
                color: palette.background,
                border: Border.all(color: palette.border, width: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [BoxShadow(blurRadius: 16, color: Color(0x2E000000), offset: Offset(0, -4))],
              ),
              child: Column(children: [
                Row(children: [
                  Flexible(child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(fontSize: 15, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status, style: style.copyWith(fontSize: 13, color: palette.muted))),
                  // No tooltip or ink here: the panel sits above the app's navigator, so there is no overlay to draw them in.
                  if (s.active)
                    Semantics(
                      button: true,
                      label: 'Make smaller',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _small = true),
                        child: SizedBox(width: 36, height: 36, child: Icon(Icons.remove, size: 18, color: palette.muted)),
                      ),
                    ),
                ]),
                if (message != null)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(message, textAlign: TextAlign.center, style: style.copyWith(fontSize: 15)),
                      const SizedBox(height: 14),
                      _PanelButton(label: 'Close', background: palette.surface, color: palette.text, onTap: widget.controller.dismiss),
                    ]),
                  )
                else ...[
                  // The orb takes little room in the column; its glow is drawn outside that room.
                  SizedBox(
                    height: 72,
                    child: OverflowBox(
                      maxHeight: 120,
                      child: KerabieOrb(
                        activity: s.phase == KerabieVoicePhase.connecting ? KerabieVoiceActivity.thinking : s.activity,
                        levels: widget.controller.levels,
                        color: s.activity == KerabieVoiceActivity.speaking ? palette.primary.withValues(alpha: 0.9) : palette.primary,
                        size: _expanded ? 56 : 52,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _expanded
                        ? ListView(children: [
                            for (final l in s.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(l.text.trim(), textAlign: l.fromCustomer ? TextAlign.right : TextAlign.left, style: style.copyWith(fontSize: 15, color: l.fromCustomer ? palette.muted : palette.text)),
                              ),
                          ])
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            if (lastCustomer != null) Text(lastCustomer.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: style.copyWith(fontSize: 13, color: palette.muted)),
                            if (lastAgent != null) Text(lastAgent.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: style.copyWith(fontSize: 15)),
                          ]),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _PanelButton(label: s.muted ? 'Unmute' : 'Mute', background: palette.surface, color: palette.text, onTap: () => widget.controller.setMuted(!s.muted)),
                    const SizedBox(width: 10),
                    _PanelButton(label: _expanded ? 'Smaller' : 'Transcript', background: palette.surface, color: palette.text, onTap: () => setState(() => _expanded = !_expanded)),
                    const SizedBox(width: 10),
                    _PanelButton(label: 'End', background: const Color(0xFFDC2626), color: Colors.white, onTap: widget.controller.stop),
                  ]),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.label, required this.background, required this.color, required this.onTap});

  final String label;
  final Color background;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
        ),
      ),
    );
  }
}
