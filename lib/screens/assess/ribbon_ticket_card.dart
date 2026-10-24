import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../localization/app_language.dart';

/// Shared ticket styling; all labels and actions are supplied by the saved record.
class RibbonTicketCard extends StatelessWidget {
  const RibbonTicketCard({
    super.key,
    required this.status,
    required this.title,
    required this.description,
    required this.photos,
    required this.color,
    required this.icon,
    this.onTap,
    this.plant = false,
    this.showPhotoCount = true,
    this.actionLabel,
  });
  final String status, title, description;
  final int photos;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool plant;
  final bool showPhotoCount;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return PhysicalShape(
      clipper: const _TicketClipper(),
      color: Color.lerp(Colors.white, color, .045)!,
      elevation: 2,
      shadowColor: color.withValues(alpha: .22),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: CustomPaint(
            foregroundPainter: _TicketDecoration(color),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(1, 1, 1, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: plant && !large ? 3 : 5,
                        child: ClipPath(
                          clipper: const _RibbonClipper(),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 9, 26, 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color.lerp(color, Colors.white, .20)!,
                                  color,
                                ],
                              ),
                            ),
                            child: Text(
                              AppWords.of(
                                context,
                              ).translate(status).toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: .85,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (plant && !large)
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 9, right: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: AppText(
                                    title,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (onTap != null)
                                  const Icon(Icons.chevron_right, size: 20),
                              ],
                            ),
                          ),
                        ),
                      if (!plant || large) const SizedBox(width: 42),
                    ],
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: large ? 62 : 76,
                          child: Center(
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.withValues(alpha: .11),
                              ),
                              child: Icon(icon, color: color, size: 27),
                            ),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(1, 1),
                          painter: _Perforation(color),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 1, 18, 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!plant || large) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AppText(
                                          title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      if (onTap != null)
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                ],
                                AppText(
                                  description,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        height: 1.35,
                                        color: const Color(0xFF526058),
                                      ),
                                ),
                                if (showPhotoCount) ...[
                                  const SizedBox(height: 5),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.photo_outlined,
                                        size: 16,
                                        color: Color(0xFF246A36),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: AppText(
                                          '$photos ${photos == 1 ? 'photo available' : 'photos available'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF526058),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (actionLabel != null) ...[
                                  const SizedBox(height: 9),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AppText(
                                          actionLabel!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: color,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 17,
                                        color: color,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 13)
    ..lineTo(14, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width - 22, s.height)
    ..lineTo(22, s.height)
    ..lineTo(0, 13)
    ..close();
  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper();
  @override
  Path getClip(Size s) {
    var path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(15)),
      );
    for (double y = 21; y < s.height - 16; y += 9) {
      final holes = Path()
        ..addOval(Rect.fromCircle(center: Offset(0, y), radius: 2.5))
        ..addOval(Rect.fromCircle(center: Offset(s.width, y), radius: 2.5));
      path = Path.combine(PathOperation.difference, path, holes);
    }
    return path;
  }

  @override
  bool shouldReclip(_TicketClipper oldClipper) => false;
}

class _Perforation extends CustomPainter {
  const _Perforation(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color.withValues(alpha: .25)
      ..strokeWidth = 1;
    for (double y = 0; y < s.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_Perforation oldDelegate) => color != oldDelegate.color;
}

class _TicketDecoration extends CustomPainter {
  const _TicketDecoration(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      const _TicketClipper().getClip(s),
      Paint()
        ..color = color.withValues(alpha: .26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.save();
    canvas.translate(s.width - 18, s.height + 6);
    final paint = Paint()..color = color.withValues(alpha: .08);
    for (var i = 0; i < 4; i++) {
      final y = -14.0 - i * 15;
      canvas.drawPath(
        Path()
          ..moveTo(0, y + 14)
          ..quadraticBezierTo(-40, y + 8, -39, y - 15)
          ..quadraticBezierTo(-10, y - 18, 0, y + 14),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, y + 10)
          ..quadraticBezierTo(20, y - 3, 8, y - 27)
          ..quadraticBezierTo(-7, y - 19, 0, y + 10),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TicketDecoration oldDelegate) =>
      color != oldDelegate.color;
}
