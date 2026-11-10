import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/local/app_database.dart';
import 'literal_translations.dart';
import 'literal_translations_extra.dart';
import 'literal_translations_long.dart';
import 'literal_translations_forms.dart';
import 'literal_translations_guide.dart';
import 'literal_translations_answers.dart';
import 'filipino_wording.dart';
import 'report_filipino.dart';
import 'dynamic_filipino.dart';

/// Language choice follows the current guest or account database view.
enum AppLanguage { english, filipino }

class AppLanguageController extends ChangeNotifier {
  AppLanguageController(this._database) {
    _subscription =
        (_database.select(_database.appPreferences)
              ..where((p) => p.preferenceKey.equals(preferenceKey)))
            .watch()
            .listen((_) => unawaited(load()));
  }

  static const preferenceKey = 'app_language';
  final AppDatabase _database;
  StreamSubscription<dynamic>? _subscription;
  AppLanguage _language = AppLanguage.english;
  bool _disposed = false;

  AppLanguage get language => _language;
  Locale get locale => Locale(_language == AppLanguage.filipino ? 'fil' : 'en');

  Future<void> load() async {
    if (_disposed) return;
    final row = await (_database.select(
      _database.appPreferences,
    )..where((p) => p.preferenceKey.equals(preferenceKey))).getSingleOrNull();
    if (_disposed) return;
    _language = row?.preferenceValue == 'fil'
        ? AppLanguage.filipino
        : AppLanguage.english;
    Intl.defaultLocale = locale.languageCode;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_disposed || _language == language) return;
    await _database
        .into(_database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            preferenceKey: preferenceKey,
            preferenceValue: language == AppLanguage.filipino ? 'fil' : 'en',
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (_disposed) return;
    _language = language;
    Intl.defaultLocale = locale.languageCode;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Approved UI wording. Keep scientific codes and stored values language neutral.
class AppWords {
  const AppWords(this.language);
  final AppLanguage language;

  static AppWords of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return AppWords(
      locale?.languageCode == 'fil'
          ? AppLanguage.filipino
          : AppLanguage.english,
    );
  }

  String get home => 'Home';
  String get assess => _pick('Assess', 'Pagsusuri');
  String get map => _pick('Map', 'Mapa');
  String get advisor => _pick('Advisor', 'Gabay');
  String get languageLabel => _pick('Language', 'Wika');
  String get myProfile => _pick('My Profile', 'Aking Profile');
  String get myFields => _pick('My Fields', 'Aking mga Bukid');
  String get guidelines => translate('Guidelines');
  String get settings => 'Settings';
  String get helpAndSupport => _pick('Help & Support', 'Tulong at Suporta');
  String get signOut => _pick('Sign Out', 'Mag-sign out');
  String get signOutQuestion =>
      _pick('Sign out of Cropwise?', 'Mag-sign out sa Cropwise?');
  String get signOutRetention => _pick(
    'Your fields, boundaries, assessments, and photos will stay saved on this phone.',
    'Mananatiling naka-save sa teleponong ito ang iyong mga bukid, hangganan, pagsusuri, at larawan.',
  );
  String get guestUser => _pick('Guest user', 'Bisita');
  String get wormwiseUser => _pick('Cropwise user', 'Gumagamit ng Cropwise');
  String get registeredAccount =>
      _pick('Registered account', 'Rehistradong account');
  String get dataSavedOnDevice => _pick(
    'Data saved on this device',
    'Naka-save ang datos sa device na ito',
  );
  String get fieldConditions => _pick('Field Conditions', 'Kalagayan ng Bukid');
  String get notifications => _pick('Notifications', 'Mga Abiso');
  String get cancel => _pick('Cancel', 'Kanselahin');
  String get english => 'English';
  String get filipino => 'Filipino';
  String get maizeGrowthStage =>
      _pick('Maize growth stage', 'Yugto ng paglaki ng mais');
  String get bestEstimate =>
      _pick('Best estimate *', 'Pinakamalapit na pagtataya *');
  String get compareGrowthStages => _pick(
    'Compare maize growth stages',
    'Ihambing ang mga yugto ng paglaki ng mais',
  );

  String get veV2 => _pick(
    'Emergence and early seedling (VE–V2)',
    'Pagsibol at maagang punla (VE–V2)',
  );
  String get v3V6 => _pick(
    'Young vegetative maize (V3–V6)',
    'Batang mais sa yugtong behetatibo (V3–V6)',
  );
  String get v7V12 => _pick(
    'Taller vegetative maize (V7–V12)',
    'Mas matangkad na mais sa yugtong behetatibo (V7–V12)',
  );
  String get vtR2 => _pick(
    'Tasseling to blister (VT–R2)',
    'Paglabas ng bulaklak hanggang blister (VT–R2)',
  );
  String get r3R6 => _pick(
    'Milk to maturity (R3–R6)',
    'Gatas na butil hanggang paghinog (R3–R6)',
  );

  String growthStage(String code) => switch (code.toLowerCase()) {
    've' || 'v1' || 'v2' || 've_v2' => veV2,
    'v3_v6' => v3V6,
    'v7_v12' => v7V12,
    'vt_r2' => vtR2,
    'r3_r6' => r3R6,
    _ => code,
  };

  String stageOptionLabel(String code) => switch (code) {
    've' => _pick('VE - emergence', 'VE - pagsibol'),
    'v1' => _pick(
      'V1 - one visible leaf collar',
      'V1 - isang nakikitang kuwelyo ng dahon',
    ),
    'v2' => _pick(
      'V2 - two visible leaf collars',
      'V2 - dalawang nakikitang kuwelyo ng dahon',
    ),
    'v3_v6' => _pick(
      'V3-V6 - three to six leaf collars',
      'V3-V6 - tatlo hanggang anim na kuwelyo ng dahon',
    ),
    'v7_v12' => _pick(
      'V7-V12 - seven to twelve leaf collars',
      'V7-V12 - pito hanggang labindalawang kuwelyo ng dahon',
    ),
    'vt_r2' => _pick(
      'VT-R2 - tasseling to blister stage',
      'VT-R2 - paglabas ng bulaklak hanggang blister stage',
    ),
    'r3_r6' => _pick(
      'R3-R6 - milk stage to maturity',
      'R3-R6 - gatas na butil hanggang paghinog',
    ),
    _ => code,
  };

  String stageOptionHelp(String code) => switch (code) {
    've' => _pick(
      'The shoot is just emerging from the soil.',
      'Nagsisimula pa lamang lumabas ang usbong mula sa lupa.',
    ),
    'v1' => _pick(
      'The lowest leaf has one visible collar and usually has a rounded tip.',
      'May isang nakikitang kuwelyo ang pinakamababang dahon at karaniwan ay bilugan ang dulo nito.',
    ),
    'v2' => _pick(
      'The two lowest leaves have visible collars; the second leaf has a pointed tip.',
      'May nakikitang kuwelyo ang dalawang pinakamababang dahon; matulis ang dulo ng ikalawang dahon.',
    ),
    'v3_v6' => _pick(
      'Count from the lowest rounded-tip leaf: three to six leaves have visible collars.',
      'Bilangin mula sa pinakamababang dahong bilugan ang dulo: tatlo hanggang anim na dahon ang may nakikitang kuwelyo.',
    ),
    'v7_v12' => _pick(
      'Count seven to twelve visible leaf collars. Do not use plant height alone.',
      'Bilangin ang pito hanggang labindalawang nakikitang kuwelyo ng dahon. Huwag umasa sa taas lamang ng halaman.',
    ),
    'vt_r2' => _pick(
      'VT: the lowest tassel branch is visible. R1: silks extend outside the husk. R2: blister-like kernels contain clear liquid.',
      'VT: nakikita ang pinakamababang sanga ng bulaklak. R1: nakausli ang mga buhok ng mais sa balat. R2: may malinaw na likido ang mga butil.',
    ),
    'r3_r6' => _pick(
      'Open an ear: milky fluid means R3, doughy contents R4, kernel dents R5, and a black layer at the kernel base R6.',
      'Buksan ang bunga: mala-gatas na likido sa R3, malalambot na laman sa R4, lubog sa butil sa R5, at itim na sapin sa paanan ng butil sa R6.',
    ),
    _ => '',
  };

  String _pick(String english, String filipino) =>
      language == AppLanguage.filipino ? simplifyFilipino(filipino) : english;

  /// Insert values only after translating the template, preserving user content.
  String format(String template, [Map<String, Object> arguments = const {}]) {
    final translated = translate(template);
    return translated.replaceAllMapped(RegExp(r'\{([a-zA-Z]+)\}'), (match) {
      final argument = arguments[match[1]];
      return argument == null ? match[0]! : argument.toString();
    });
  }

  String days(num count) => language == AppLanguage.filipino
      ? format('{count} days', {'count': count})
      : '$count ${count == 1 ? 'day' : 'days'}';

  String newUpdates(int count) => language == AppLanguage.filipino
      ? format('{count} new updates', {'count': count})
      : '$count new ${count == 1 ? 'update' : 'updates'}';

  String countOf(Object count, Object total) =>
      format('{count} of {total}', {'count': count, 'total': total});

  String translate(String english) {
    if (language != AppLanguage.filipino) return english;
    final translated =
        farmerFilipino[english] ??
        reportFilipino[english] ??
        literalFilipino[english] ??
        extraLiteralFilipino[english] ??
        longLiteralFilipino[english] ??
        formLiteralFilipino[english] ??
        guideLiteralFilipino[english] ??
        answerLiteralFilipino[english] ??
        _translateDynamic(english);
    return translated == english ? english : simplifyFilipino(translated);
  }

  String _translateDynamic(String value) {
    final templated = dynamicFilipino(value);
    if (templated != null) return templated;
    if (value.endsWith(
      ' Showing local guidance. Tap Regenerate to try again.',
    )) {
      return 'Hindi nakumpleto ang gabay ng AI. Ipinapakita muna ang offline na gabay. I-tap ang Regenerate para subukan muli.';
    }
    if (value ==
        'The AI service is not configured for this build. Showing local guidance.') {
      return 'Hindi pa available ang AI sa bersiyong ito. Ipinapakita muna ang offline na gabay.';
    }
    final match = RegExp(r'^Plant (\d+)$').firstMatch(value);
    if (match != null) return 'Halaman ${match[1]}';
    final station = RegExp(r'^Station (\d+)$').firstMatch(value);
    if (station != null) return 'Istasyon ${station[1]}';
    final stationDetails = RegExp(r'^Station (\d+) details$').firstMatch(value);
    if (stationDetails != null)
      return 'Detalye ng Istasyon ${stationDetails[1]}';
    final reviewPlant = RegExp(r'^Review Plant (\d+)$').firstMatch(value);
    if (reviewPlant != null) return 'Repasuhin ang Halaman ${reviewPlant[1]}';
    final obstacle = RegExp(r'^Obstacle (\d+)$').firstMatch(value);
    if (obstacle != null) return 'Harang ${obstacle[1]}';
    if (value.startsWith('Boundary could not be saved: ')) {
      return value.replaceFirst(
        'Boundary could not be saved: ',
        'Hindi ma-save ang hangganan: ',
      );
    }
    if (value.startsWith('Could not save the field: ')) {
      return value.replaceFirst(
        'Could not save the field: ',
        'Hindi ma-save ang bukid: ',
      );
    }
    if (value.startsWith('Growth stage could not be changed: ')) {
      return value.replaceFirst(
        'Growth stage could not be changed: ',
        'Hindi mapalitan ang yugto ng paglaki: ',
      );
    }
    if (value.startsWith('Station still needs attention: ')) {
      return value.replaceFirst(
        'Station still needs attention: ',
        'Kailangan pang asikasuhin ang istasyon: ',
      );
    }
    if (value.startsWith('Did you mean “')) {
      return value.replaceFirst(
        'Did you mean “',
        'Ang ibig mo bang sabihin ay “',
      );
    }
    return value;
  }
}
