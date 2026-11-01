import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One slice of a donut chart.
class ChartSegment {
  const ChartSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// Simple animated bar chart with a light grid and labels under each bar.
/// The tallest bar is drawn in the full color, the others are softer.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 170,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarsPainter(
              values: values,
              labels: labels,
              progress: progress,
              barColor: colors.primary,
              gridColor: colors.outlineVariant,
              textColor: colors.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.progress,
    required this.barColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<double> values;
  final List<String> labels;
  final double progress;
  final Color barColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 24.0;
    const topPad = 8.0;
    final chartHeight = size.height - bottomPad - topPad;
    if (chartHeight <= 0 || values.isEmpty) return;

    final maxValue = values.fold<double>(0, math.max);
    final scaleMax = maxValue <= 0 ? 1.0 : maxValue;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slot = size.width / values.length;
    final barWidth = math.min(slot * 0.5, 36.0);

    for (var i = 0; i < values.length; i++) {
      final barHeight = chartHeight * (values[i] / scaleMax) * progress;
      final x = slot * i + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, topPad + chartHeight - barHeight, barWidth, barHeight),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      );
      final isTop = maxValue > 0 && values[i] == maxValue;
      canvas.drawRRect(
        rect,
        Paint()..color = isTop ? barColor : barColor.withValues(alpha: 0.4),
      );

      if (i < labels.length) {
        final painter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(fontSize: 11, color: textColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(
            slot * i + (slot - painter.width) / 2,
            size.height - bottomPad + 8,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) {
    return old.progress != progress ||
        old.values != values ||
        old.labels != labels ||
        old.barColor != barColor ||
        old.gridColor != gridColor ||
        old.textColor != textColor;
  }
}

/// Animated donut chart. Put a widget in [center] to show a total inside.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.size = 140,
    this.center,
  });

  final List<ChartSegment> segments;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(
                  segments: segments,
                  progress: progress,
                  trackColor: colors.surfaceContainerHighest,
                ),
              ),
              ?center,
            ],
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.progress,
    required this.trackColor,
  });

  final List<ChartSegment> segments;
  final double progress;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final segment in segments) {
      final fullSweep = 2 * math.pi * segment.value / total;
      final gap = segments.length > 1 && fullSweep > 0.1 ? 0.04 : 0.0;
      final sweep = math.max(0.0, fullSweep * progress - gap);
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = segment.color,
        );
      }
      start += fullSweep * progress;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) {
    return old.progress != progress ||
        old.segments != segments ||
        old.trackColor != trackColor;
  }
}
