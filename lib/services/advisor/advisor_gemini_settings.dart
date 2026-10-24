import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../cloud/supabase_bootstrap.dart';
import '../cloud/account_app_data_service.dart';

class AdvisorGeminiPreferences {
  const AdvisorGeminiPreferences({
    this.enabled = true,
    this.shareFieldContext = true,
    this.shareLocation = false,
    this.allowPhotoUploads = false,
    this.showSupportingSources = false,
  });

  final bool enabled;
  final bool shareFieldContext;
  final bool shareLocation;
  final bool allowPhotoUploads;
  final bool showSupportingSources;
  AdvisorGeminiPreferences copyWith({bool? showSupportingSources}) =>
      AdvisorGeminiPreferences(
        enabled: enabled,
        shareFieldContext: shareFieldContext,
        shareLocation: shareLocation,
        allowPhotoUploads: allowPhotoUploads,
        showSupportingSources:
            showSupportingSources ?? this.showSupportingSources,
      );
}

abstract interface class AdvisorGeminiSettingsStore {
  Future<bool> isServiceConfigured();
  Future<AdvisorGeminiPreferences> loadPreferences();
  Future<void> savePreferences(AdvisorGeminiPreferences preferences);
}

class SecureAdvisorGeminiSettingsStore implements AdvisorGeminiSettingsStore {
  const SecureAdvisorGeminiSettingsStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  static const _enabled = 'wormwise_gemini_enabled';
  static const _shareField = 'wormwise_gemini_share_field';
  static const _shareLocation = 'wormwise_gemini_share_location';
  static const _sharePhotos = 'wormwise_gemini_share_photos';
  static const _showSources = 'wormwise_gemini_show_sources';

  @override
  Future<bool> isServiceConfigured() async => SupabaseBootstrap.isConfigured;

  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async {
    final values = await Future.wait([
      storage.read(key: _enabled),
      storage.read(key: _shareField),
      storage.read(key: _shareLocation),
      storage.read(key: _sharePhotos),
      storage.read(key: _showSources),
    ]);
    return AdvisorGeminiPreferences(
      enabled: values[0] != 'false',
      shareFieldContext: values[1] != 'false',
      shareLocation: values[2] == 'true',
      allowPhotoUploads: values[3] == 'true',
      showSupportingSources: values[4] == 'true',
    );
  }

  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {
    await Future.wait([
      storage.write(
        key: _showSources,
        value: preferences.showSupportingSources.toString(),
      ),
      storage.write(key: _enabled, value: preferences.enabled.toString()),
      storage.write(
        key: _shareField,
        value: preferences.shareFieldContext.toString(),
      ),
      storage.write(
        key: _shareLocation,
        value: preferences.shareLocation.toString(),
      ),
      storage.write(
        key: _sharePhotos,
        value: preferences.allowPhotoUploads.toString(),
      ),
    ]);
    AccountAppDataEvents.changed();
  }
}
