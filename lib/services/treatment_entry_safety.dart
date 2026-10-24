import '../data/local/database_codes.dart';

/// Reported treatment facts used for the field-entry gate. An approximate or
/// unknown application end time cannot establish that the interval has ended.
class TreatmentEntrySafety {
  const TreatmentEntrySafety({
    required this.applicationEndedAt,
    required this.timePrecision,
    required this.reentryValue,
    required this.reentryUnit,
    required this.source,
    this.reportedProduct,
  });

  final DateTime? applicationEndedAt;
  final String timePrecision;
  final int? reentryValue;
  final String reentryUnit;
  final String? source;
  final String? reportedProduct;

  DateTime? get safeEntryAt {
    if (timePrecision != 'exact' ||
        applicationEndedAt == null ||
        reentryValue == null ||
        reentryValue! <= 0 ||
        source == null ||
        source == 'unknown') {
      return null;
    }
    final hours = reentryUnit == 'days'
        ? reentryValue! * 24
        : reentryUnit == 'hours'
        ? reentryValue!
        : null;
    return hours == null || hours > 365 * 24
        ? null
        : applicationEndedAt!.add(Duration(hours: hours));
  }

  String statusAt(DateTime now) {
    final safeAt = safeEntryAt;
    if (safeAt == null) return DatabaseCodes.cannotConfirmSafety;
    return now.isBefore(safeAt)
        ? DatabaseCodes.blockedReiActive
        : DatabaseCodes.safeIntervalCompleted;
  }

  String? get reentryText => reentryValue == null || reentryValue! <= 0
      ? null
      : '$reentryValue $reentryUnit';

  String? get safetyNote {
    final product = reportedProduct?.trim();
    final details = <String>['Application end time: $timePrecision'];
    if (product != null && product.isNotEmpty) {
      details.add('Reported treatment/product: $product (not label-verified)');
    }
    return '${details.join('; ')}.';
  }
}
