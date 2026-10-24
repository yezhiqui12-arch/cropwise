import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBootstrapResult {
  const SupabaseBootstrapResult({this.client, this.configurationError});

  final SupabaseClient? client;
  final String? configurationError;
}

class SupabaseBootstrap {
  static SupabaseBootstrapResult? _initialized;
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      _url.trim().isNotEmpty && _publishableKey.trim().isNotEmpty;

  static Future<SupabaseBootstrapResult> initialize() async {
    if (!isConfigured) {
      return const SupabaseBootstrapResult(
        configurationError:
            'Supabase is not configured; using local-only mode.',
      );
    }

    final initialized = _initialized;
    if (initialized != null) return initialized;
    try {
      await Supabase.initialize(url: _url, anonKey: _publishableKey);
      return _initialized = SupabaseBootstrapResult(
        client: Supabase.instance.client,
      );
    } catch (error) {
      return SupabaseBootstrapResult(
        configurationError: 'Supabase initialization failed: $error',
      );
    }
  }
}
