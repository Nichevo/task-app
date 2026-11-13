import 'package:flutter/material.dart';

import '../pace.dart';

/// Item 96: a slim bar for work done or time left. [value] 0 to 1 is filled from the left;
/// [marker] draws a tick there (time gone, for the pace bar); [striped] fills it all with
/// stripes (overdue).
class ShadeBar extends StatelessWidget {
  const ShadeBar({
    super.key,
    required this.value,
    this.marker,
    this.striped = false,
    this.height = 5,
    this.ink = const Color(0xFF000000),
    this.fillAlpha = 0.55,
  });

  final double value;
  final double? marker;
  final bool striped;
  final double height;
  final Color ink;
  final double fillAlpha;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: marker == null ? height : height + 6,
    child: CustomPaint(
      painter: _BarPainter(
        value.clamp(0, 1).toDouble(),
        marker?.clamp(0, 1).toDouble(),
        striped,
        height,
        ink,
        fillAlpha,
      ),
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.marker, this.striped, this.height, this.ink, this.fillAlpha);

  final double value;
  final double? marker;
  final bool striped;
  final double height;
  final Color ink;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2) return;
    final top = (size.height - height) / 2;
    final track = RRect.fromLTRBR(0, top, size.width, top + height, Radius.circular(height / 2));
    canvas.drawRRect(track, Paint()..color = ink.withValues(alpha: 0.13));
    if (striped) {
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(Rect.fromLTWH(0, top, size.width, height), Paint()..color = ink.withValues(alpha: 0.15));
      final stripe = Paint()
        ..color = ink.withValues(alpha: fillAlpha)
        ..strokeWidth = 4;
      for (var x = -height; x < size.width + height; x += 8) {
        canvas.drawLine(Offset(x, top + height), Offset(x + height, top), stripe);
      }
      canvas.restore();
    } else if (value > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, top, size.width * value, top + height, Radius.circular(height / 2)),
        Paint()..color = ink.withValues(alpha: fillAlpha),
      );
    }
    final m = marker;
    if (m != null) {
      final x = (size.width * m).clamp(1.0, size.width - 1);
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), Paint()..color = ink.withValues(alpha: 0.87));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value ||
      old.marker != marker ||
      old.striped != striped ||
      old.ink != ink ||
      old.fillAlpha != fillAlpha;
}

/// A bar for time left: drains as the due date gets closer; stripes once overdue.
class TimeLeftBar extends StatelessWidget {
  const TimeLeftBar({super.key, required this.used, this.height = 5, this.ink = const Color(0xFF000000)});

  final double used;
  final double height;
  final Color ink;

  @override
  Widget build(BuildContext context) =>
      ShadeBar(value: 1 - used, striped: used >= 1, height: height, ink: ink, fillAlpha: used >= 1 ? 0.55 : 0.32);
}

/// "70% left" or "overdue".
String timeLeftLabel(double used) => used >= 1 ? 'overdue' : '${((1 - used) * 100).round()}% left';

/// A small pill with the pace verdict: dark when behind, light otherwise.
class PaceChip extends StatelessWidget {
  const PaceChip(this.pace, {super.key, this.small = false});

  final PaceInfo pace;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final label = pace.label;
    if (label == null) return const SizedBox.shrink();
    final behind = pace.verdict == Pace.behind;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: behind ? const Color(0xB8000000) : const Color(0x73FFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10.5 : 11,
          fontWeight: FontWeight.w600,
          color: behind ? Colors.white : const Color(0xDD000000),
        ),
      ),
    );
  }
}

/// A labelled bar row: "Steps ▬▬▬▭▭ 3/5".
class LabelledBar extends StatelessWidget {
  const LabelledBar({
    super.key,
    required this.label,
    required this.bar,
    required this.trailing,
    this.small = false,
    required this.ink,
  });

  final String label;
  final Widget bar;
  final String trailing;
  final bool small;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: small ? 10.5 : 11, color: ink.withValues(alpha: 0.7));
    return Padding(
      padding: EdgeInsets.only(top: small ? 1 : 3),
      child: Row(
        children: [
          SizedBox(
            width: small ? 34 : 44,
            child: Text(label, style: style),
          ),
          Expanded(child: bar),
          const SizedBox(width: 6),
          Text(trailing, style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
