import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrackRenderer, VideoViewFit, VideoViewMirrorMode;

import 'call_controller.dart';

const _danger = Color(0xFFDC2626);

const _endedText = {
  'hangup': 'Call ended',
  'cancelled': 'Call cancelled',
  'missed': 'Nobody was available to take your call. Please try again, or send us a message.',
  'declined': 'Nobody was available to take your call. Please try again, or send us a message.',
  'limit': 'The call reached its time limit.',
  'connection_lost': 'The call was cut off. Please try again.',
  'other_call': 'This call ended because another call started.',
};

String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// The call screen: waiting, ringing, the call itself, and how it ended. It closes itself when the call is dismissed.
/// [KerabieCallButton] opens it for you; open it yourself with [KerabieCallController.start] for your own button.
class KerabieCallScreen extends StatefulWidget {
  const KerabieCallScreen({super.key, required this.call, required this.chat, this.aiName = 'AI assistant'});

  /// What the AI is called on screen.
  final String aiName;

  final KerabieCallController call;
  final KerabieController chat;

  @override
  State<KerabieCallScreen> createState() => _KerabieCallScreenState();
}

class _KerabieCallScreenState extends State<KerabieCallScreen> {
  Timer? _ticker;
  DateTime? _since;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    widget.call.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.call.removeListener(_onChange);
    _ticker?.cancel();
    super.dispose();
  }

  void _onChange() {
    final call = widget.call;
    if (call.phase == KerabieCallPhase.idle && mounted) {
      Navigator.of(context).maybePop();
      return;
    }
    if (call.phase == KerabieCallPhase.connected) {
      if (_ticker == null) {
        _since = DateTime.now();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds = DateTime.now().difference(_since!).inSeconds);
        });
      }
    } else {
      _ticker?.cancel();
      _ticker = null;
      _seconds = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KerabieScope(
      notifier: widget.chat,
      child: AnimatedBuilder(
        animation: widget.call,
        builder: (context, _) {
          final call = widget.call;
          final palette = KerabiePalette.of(context, widget.chat);
          final phase = call.phase;
          return PopScope(
            // Leaving mid-call by accident would leave the microphone on behind a hidden screen.
            canPop: phase == KerabieCallPhase.ended || phase == KerabieCallPhase.idle,
            child: Scaffold(
              backgroundColor: palette.background,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    children: [
                      Expanded(child: Center(child: _body(call, palette))),
                      _controls(call, palette),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(KerabieCallController call, KerabiePalette palette) {
    TextStyle strong() => TextStyle(color: palette.text, fontSize: 20, fontWeight: FontWeight.w700);
    TextStyle quiet() => TextStyle(color: palette.muted, fontSize: 14, height: 1.4);

    switch (call.phase) {
      case KerabieCallPhase.connected:
        final who = call.handler == 'AI' ? widget.aiName : (call.agentName ?? 'Support');
        final video = call.remoteVideo;
        final self = call.localVideo;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (call.video && (video != null || self != null))
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      if (video != null) VideoTrackRenderer(video, fit: VideoViewFit.cover),
                      // Your own camera, small, in the corner
                      if (self != null && call.cameraOn)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          width: 92,
                          height: 124,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoTrackRenderer(self, fit: VideoViewFit.cover, mirrorMode: VideoViewMirrorMode.mirror),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              CircleAvatar(
                radius: 48,
                backgroundColor: palette.primary,
                child: Text(who.trim().isEmpty ? 'S' : who.trim()[0].toUpperCase(),
                    style: TextStyle(color: palette.onPrimary, fontSize: 38, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 14),
            Text(who, style: strong()),
            const SizedBox(height: 4),
            Text(_clock(_seconds), style: quiet()),
          ],
        );
      case KerabieCallPhase.ended:
        final text = call.error ?? _endedText[call.endReason ?? 'hangup'] ?? 'Call ended';
        return Text(text, textAlign: TextAlign.center, style: strong());
      case KerabieCallPhase.details:
        return KerabiePreChatForm(
          fields: widget.chat.preChatFields,
          title: 'Before we call',
          subtitle: 'Share your details so we can follow up',
          submitLabel: 'Start call',
          requireContact: identical(widget.chat.preChatFields, kerabieDefaultPreChatFields),
          initial: {'name': widget.chat.currentUser?.name ?? '', 'email': widget.chat.currentUser?.email ?? ''},
          palette: palette,
          onSubmit: call.submitDetails,
        );
      case KerabieCallPhase.idle:
      case KerabieCallPhase.starting:
      case KerabieCallPhase.waiting:
      case KerabieCallPhase.ringing:
        final status = switch (call.phase) {
          KerabieCallPhase.starting => 'Starting the call…',
          KerabieCallPhase.waiting => "Everyone is busy right now. You're number ${call.queuePosition ?? 1} in line.",
          _ => 'Calling… waiting for someone to answer.',
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: palette.primary),
            const SizedBox(height: 20),
            Text(status, textAlign: TextAlign.center, style: strong()),
            if (call.phase == KerabieCallPhase.waiting) ...[
              const SizedBox(height: 8),
              Text('Stay on this screen. We will connect you as soon as someone is free.', textAlign: TextAlign.center, style: quiet()),
            ],
          ],
        );
    }
  }

  Widget _controls(KerabieCallController call, KerabiePalette palette) {
    if (call.phase == KerabieCallPhase.ended) {
      return _RoundButton(icon: Icons.close_rounded, label: 'Close', background: palette.primary, foreground: palette.onPrimary, onTap: call.dismiss);
    }
    final connected = call.phase == KerabieCallPhase.connected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (connected) ...[
          _RoundButton(
            icon: call.microphoneOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: call.microphoneOn ? 'Mute' : 'Unmute',
            background: palette.surface,
            foreground: palette.text,
            onTap: call.toggleMicrophone,
          ),
          if (call.video) ...[
            const SizedBox(width: 22),
            _RoundButton(
              icon: call.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: call.cameraOn ? 'Camera off' : 'Camera on',
              background: palette.surface,
              foreground: palette.text,
              onTap: call.toggleCamera,
            ),
          ],
          const SizedBox(width: 22),
        ],
        _RoundButton(
          icon: Icons.call_end_rounded,
          label: connected ? 'End' : 'Cancel',
          background: _danger,
          foreground: Colors.white,
          onTap: call.hangUp,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.background, required this.foreground, required this.onTap});

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 68, height: 68, child: Icon(icon, color: foreground, size: 28)),
            ),
          ),
          // The label is part of the target too, so the whole button is easy to hit.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label, style: TextStyle(color: foreground == Colors.white ? background : foreground, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
