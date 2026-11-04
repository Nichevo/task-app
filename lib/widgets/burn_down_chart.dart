import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../gantt.dart';

/// Item 77: the burn-down drawn small: the ideal line dashed, what is actually left solid, and
/// the "at this pace" line dotted on to its finish.
class BurnDownChart extends StatelessWidget {
  const BurnDownChart({super.key, required this.burn, required this.now, this.height = 120});

  final BurnDown burn;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: burnSummary(burn),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _BurnPainter(burn, dayOf(now), scheme, Theme.of(context).textTheme.labelSmall!)),
      ),
    );
  }
}

class _BurnPainter extends CustomPainter {
  _BurnPainter(this.b, this.today, this.scheme, this.label);

  final BurnDown b;
  final DateTime today;
  final ColorScheme scheme;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 28.0, padB = 16.0, padT = 6.0, padR = 8.0;
    var last = b.end.isAfter(today) ? b.end : today;
    if (b.projected != null && b.projected!.isAfter(last)) {
      // Don't let a far-off projection squash the chart: cap it at twice the planned span.
      final cap = addDays(b.start, max(daysBetween(b.start, b.end), 7) * 2);
      last = b.projected!.isAfter(cap) ? cap : b.projected!;
    }
    final span = max(daysBetween(b.start, last), 1);
    final w = size.width - padL - padR, h = size.height - padT - padB;
    final top = max(b.total, 1.0);
    double x(DateTime d) => padL + w * daysBetween(b.start, d) / span;
    double y(double v) => padT + h * (1 - v / top);

    final axis = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + h), axis);
    canvas.drawLine(Offset(padL, padT + h), Offset(padL + w, padT + h), axis);
    _text(canvas, b.total.round().toString(), Offset(2, padT - 2));
    _text(canvas, '0', Offset(2, padT + h - 10));
    final fmt = DateFormat('d MMM');
    _text(canvas, fmt.format(b.start), Offset(padL, padT + h + 2));
    final endLabel = fmt.format(last);
    _text(canvas, endLabel, Offset(padL + w - 6 * endLabel.length.toDouble(), padT + h + 2));

    // Today.
    canvas.drawLine(Offset(x(today), padT), Offset(x(today), padT + h),
        Paint()
          ..color = scheme.primary.withValues(alpha: 0.4)
          ..strokeWidth = 1);

    // Ideal, dashed.
    _dashed(canvas, Offset(x(b.start), y(b.total)), Offset(x(b.end), y(0)),
        Paint()
          ..color = scheme.onSurfaceVariant
          ..strokeWidth = 1.5,
        6, 4);

    // Actual.
    final path = Path();
    for (var i = 0; i < b.left.length; i++) {
      final p = Offset(x(addDays(b.start, i)), y(b.left[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = scheme.primary
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);

    // At this pace, dotted.
    final proj = b.projected;
    if (proj != null && b.now > 0) {
      final late = proj.isAfter(b.end);
      final endX = proj.isAfter(last) ? x(last) : x(proj);
      final endY = proj.isAfter(last) ? y(b.now * (1 - daysBetween(today, last) / max(daysBetween(today, proj), 1))) : y(0);
      _dashed(canvas, Offset(x(today), y(b.now)), Offset(endX, endY),
          Paint()
            ..color = late ? scheme.error : scheme.tertiary
            ..strokeWidth = 2,
          2, 4);
    }
  }

  void _text(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, double dash, double gap) {
    final d = (b - a).distance;
    if (d == 0) return;
    final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += dash + gap) {
      canvas.drawLine(a + dir * t, a + dir * min(t + dash, d), p);
    }
  }

  @override
  bool shouldRepaint(_BurnPainter old) => true;
}
