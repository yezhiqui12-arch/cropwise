import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import '../services/advisor/advisor_gemini_settings.dart';
import '../theme/app_colors.dart';

class ArtificialIntelligenceScreen extends StatefulWidget {
  const ArtificialIntelligenceScreen({super.key});
  @override
  State<ArtificialIntelligenceScreen> createState() =>
      _ArtificialIntelligenceScreenState();
}

class _ArtificialIntelligenceScreenState
    extends State<ArtificialIntelligenceScreen> {
  final _store = const SecureAdvisorGeminiSettingsStore();
  AdvisorGeminiPreferences? _preferences;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _store.loadPreferences();
      if (mounted) setState(() => _preferences = value);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load preferences.');
    }
  }

  Future<void> _save(bool value) async {
    setState(() => _saving = true);
    try {
      final latest = await _store.loadPreferences();
      final updated = latest.copyWith(showSupportingSources: value);
      await _store.savePreferences(updated);
      if (mounted) {
        setState(() {
          _preferences = updated;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save preferences. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const AppText('Artificial Intelligence')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (_preferences == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_preferences != null)
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.cardBorder),
                  ),
                  child: SwitchListTile(
                    key: const Key('advisor_show_supporting_sources'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: const AppText(
                      'Supporting sources',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: AppText('Show references below Advisor replies.'),
                    ),
                    value: _preferences!.showSupportingSources,
                    onChanged: _saving ? null : _save,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.severeSeverityRing,
                        ),
                      ),
                      if (_preferences == null)
                        TextButton(
                          onPressed: _load,
                          child: const AppText('Try again'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
