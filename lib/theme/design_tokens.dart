import 'package:flutter/material.dart';

/// Shared visual constants for field workflows.
///
/// These values favor strong separation and large targets in direct sunlight.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double control = 10;
  static const double card = 14;
  static const double prominent = 18;

  static const BorderRadius controlBorder = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius prominentBorder = BorderRadius.all(
    Radius.circular(prominent),
  );
}

abstract final class AppSizes {
  static const double minimumTouchTarget = 48;
  static const double primaryActionHeight = 56;
  static const double workflowMaxWidth = 720;
  static const double evidencePreviewHeight = 188;
}

abstract final class AppElevation {
  static const double card = 0;
  static const double stickyAction = 3;
}

abstract final class AppMotion {
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 240);
}
