import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'voice_controller.dart';
import 'voice_state.dart';

/// The orb: it swells with the customer's voice while they talk, with the AI's voice while it talks, and breathes slowly
/// while the AI is working. Drawn with plain canvas circles, so it needs no graphics library.
class KerabieOrb extends StatefulWidget {
  const KerabieOrb({super.key, required this.activity, required this.levels, required this.color, this.size = 84});

  final KerabieVoiceActivity activity;

  /// The loudness of the two voices, from [KerabieVoiceController.levels].
  final ValueListenable<KerabieVoiceLevels> levels;
  final Color color;
  final double size;

  @override
  State<KerabieOrb> createState() => _KerabieOrbState();
}

class _KerabieOrbState extends State<KerabieOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: _period)..repeat(reverse: true);
  double _smooth = 0;

  Duration get _period => Duration(milliseconds: widget.activity == KerabieVoiceActivity.thinking ? 700 : 1600);

  @override
  void didUpdateWidget(KerabieOrb old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) {
      _breath
        ..duration = _period
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thinking = widget.activity == KerabieVoiceActivity.thinking;
    return Semantics(
      label: widget.activity.name,
      child: SizedBox.square(
        dimension: widget.size * 1.7,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, widget.levels]),
          builder: (context, _) {
            final levels = widget.levels.value;
            final target = switch (widget.activity) {
              KerabieVoiceActivity.speaking => levels.output,
              KerabieVoiceActivity.listening => levels.input,
              KerabieVoiceActivity.thinking => 0.0,
            };
            // Follows the voice: moves a part of the way each frame, so the motion is smooth.
            _smooth += (target - _smooth) * 0.35;
            return CustomPaint(painter: _OrbPainter(color: widget.color, size: widget.size, swell: _smooth, breath: _breath.value, thinking: thinking));
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.color, required this.size, required this.swell, required this.breath, required this.thinking});

  final Color color;
  final double size;
  final double swell;
  final double breath;
  final bool thinking;

  @override
  void paint(Canvas canvas, Size area) {
    final center = area.center(Offset.zero);
    final radius = size / 2;
    final pulse = thinking ? 0.1 : 0.03;
    final glow = 1.15 + swell * 0.6 + breath * (thinking ? 0.2 : 0.06);
    final core = 1 + swell * 0.28 + breath * pulse;
    canvas.drawCircle(center, radius * glow, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawCircle(center, radius * core, Paint()..color = color);
    canvas.drawCircle(center, radius * 0.42, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.swell != swell || old.breath != breath || old.color != color || old.size != size || old.thinking != thinking;
}
