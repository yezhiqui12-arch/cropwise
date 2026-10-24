import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/computer_vision/faw_computer_vision_service.dart';

class ModelDetectionImage extends StatelessWidget {
  const ModelDetectionImage({
    super.key,
    required this.file,
    required this.boxes,
    this.fit = BoxFit.cover,
  });

  final File file;
  final List<ModelDetectionBox> boxes;
  final BoxFit fit;

  static List<ModelDetectionBox> boxesForFile(
    PlantDiagnosisResult? diagnosis,
    File file,
  ) {
    if (diagnosis == null) return const [];
    final path = file.absolute.path.toLowerCase();
    return diagnosis.detectionBoxes
        .where(
          (box) => File(box.sourcePath).absolute.path.toLowerCase() == path,
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.file(
        file,
        fit: fit,
        errorBuilder: (context, error, stack) => const ColoredBox(
          color: Color(0xFFE7ECE4),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 36,
              color: Colors.black38,
            ),
          ),
        ),
      ),
      if (boxes.isNotEmpty)
        IgnorePointer(
          child: CustomPaint(painter: _DetectionPainter(boxes, fit)),
        ),
    ],
  );
}

class _DetectionPainter extends CustomPainter {
  const _DetectionPainter(this.boxes, this.fit);

  final List<ModelDetectionBox> boxes;
  final BoxFit fit;

  static const _colors = [
    Color(0xFFFFC107),
    Color(0xFF00BCD4),
    Color(0xFF4CAF50),
    Color(0xFFE040FB),
    Color(0xFFEF6C00),
    Color(0xFF7B1FA2),
    Color(0xFF1565C0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final color = _colors[box.classId.clamp(0, _colors.length - 1).toInt()];
      final fitted = applyBoxFit(
        fit,
        Size(box.imageWidth.toDouble(), box.imageHeight.toDouble()),
        size,
      );
      final destination = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & size,
      );
      final rect = Rect.fromLTRB(
        destination.left + box.left * destination.width,
        destination.top + box.top * destination.height,
        destination.left + box.right * destination.width,
        destination.top + box.bottom * destination.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size.shortestSide / 140),
      );
      final label = '${box.label} ${(box.confidence * 100).round()}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            backgroundColor: color.withValues(alpha: 0.9),
            fontSize: math.max(8, size.shortestSide / 18),
            fontWeight: FontWeight.w600,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(1, size.width - rect.left));
      textPainter.paint(
        canvas,
        Offset(rect.left, math.max(0, rect.top - textPainter.height)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.boxes != boxes || oldDelegate.fit != fit;
}
