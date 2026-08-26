import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/local/database_codes.dart';
import '../data/repositories/field_repository.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../services/assessment_protocol_selector.dart';
import '../services/recent_weather_service.dart';
import '../theme/app_colors.dart';
import '../widgets/accessible_choice_field.dart';
import 'assessment_session_screen.dart';
import 'boundary_map_screen.dart';

class AssessmentSetupScreen extends StatefulWidget {
  const AssessmentSetupScreen({super.key, this.recentWeatherService});

  final RecentWeatherService? recentWeatherService;

  @override
  State<AssessmentSetupScreen> createState() => _AssessmentSetupScreenState();
}

class _AssessmentSetupScreenState extends State<AssessmentSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _evaluatorController = TextEditingController();
  final _safetySourceController = TextEditingController();
  final _safetyNotesController = TextEditingController();

  String _growthStage = 'v3_v6';
  String? _rainLast48Hours;
  String? _safetyStatus;
  bool _safeIntervalVerified = false;
  String? _loadedAssessmentId;
  String? _weatherLookupFieldId;
  RecentRainSnapshot? _recentRain;
  _WeatherLookupState _weatherLookupState = _WeatherLookupState.idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final assessment = context
        .watch<AssessmentWorkspaceProvider>()
        .currentAssessment;
    if (assessment != null && assessment.id != _loadedAssessmentId) {
      _loadedAssessmentId = assessment.id;
      _growthStage = assessment.growthStage;
    }
    final workspace = context.watch<FieldWorkspaceProvider>().activeWorkspace;
    if (assessment?.status != DatabaseCodes.inProgress &&
        workspace != null &&
        workspace.field.id != _weatherLookupFieldId) {
      _weatherLookupFieldId = workspace.field.id;
      _recentRain = null;
      _rainLast48Hours = null;
      _startWeatherLookup(workspace);
    }
  }

  Future<void> _startWeatherLookup(FieldWorkspaceRecord workspace) async {
    final location = resolveRecentWeatherCoordinates(
      storedLatitude: workspace.boundary?.centroidLatitude,
      storedLongitude: workspace.boundary?.centroidLongitude,
      boundaryGeoJson: workspace.boundary?.geometryGeojson ?? '',
    );
    if (location == null) {
      if (!mounted) return;
      setState(() => _weatherLookupState = _WeatherLookupState.unavailable);
      return;
    }
    setState(() => _weatherLookupState = _WeatherLookupState.loading);
    final repository = context.read<FieldRepository>();
    final cacheKey = 'recent_weather_${workspace.field.id}';
    try {
      final cached = RecentRainSnapshot.tryParse(
        await repository.readPreferenceValue(cacheKey),
      );
      if (cached != null &&
          DateTime.now().toUtc().difference(cached.fetchedAtUtc) <
              const Duration(hours: 3)) {
        if (!mounted || _weatherLookupFieldId != workspace.field.id) return;
        setState(() {
          _recentRain = cached;
          _weatherLookupState = _WeatherLookupState.available;
        });
        return;
      }
      final snapshot =
          await (widget.recentWeatherService ?? OpenMeteoRecentWeatherService())
              .recentRain(
                latitude: location.latitude,
                longitude: location.longitude,
              );
      await repository.savePreferenceValue(cacheKey, snapshot.toJson());
      if (!mounted || _weatherLookupFieldId != workspace.field.id) return;
      setState(() {
        _recentRain = snapshot;
        _weatherLookupState = _WeatherLookupState.available;
      });
    } catch (_) {
      if (!mounted || _weatherLookupFieldId != workspace.field.id) return;
      setState(() => _weatherLookupState = _WeatherLookupState.unavailable);
    }
  }

  @override
  void dispose() {
    _evaluatorController.dispose();
    _safetySourceController.dispose();
    _safetyNotesController.dispose();
    super.dispose();
  }

  String get _recommendedPattern =>
      AssessmentProtocolSelector.recommendedPatternFor(_growthStage);

  bool get _safetyAllowsEntry =>
      _safetyStatus == DatabaseCodes.noRecentTreatment ||
      _safetyStatus == DatabaseCodes.safeIntervalCompleted;

  Future<void> _submit() async {
    final provider = context.read<AssessmentWorkspaceProvider>();
    final existing = provider.currentAssessment;
    if (!_formKey.currentState!.validate()) return;
    if (_safetyStatus == null) {
      _showMessage('Select the field-entry safety situation.');
      return;
    }
    if (_safetyStatus == DatabaseCodes.safeIntervalCompleted &&
        (!_safeIntervalVerified ||
            _safetySourceController.text.trim().isEmpty)) {
      _showMessage(
        'State the label, record, or authorized guidance used and confirm that you verified it.',
      );
      return;
    }

    try {
      final result = existing == null
          ? await provider.createAssessment(
              evaluatorName: _evaluatorController.text,
              assessmentMode: AssessmentProtocolSelector.assessmentModeFor(
                _growthStage,
              ),
              scoutingPattern: _recommendedPattern,
              patternReason: null,
              growthStage: _growthStage,
              growthStageUncertain: false,
              safetyStatus: _safetyStatus!,
              interventionHistoryStatus:
                  _safetyStatus == DatabaseCodes.noRecentTreatment
                  ? 'no'
                  : _safetyStatus == DatabaseCodes.cannotConfirmSafety
                  ? 'unknown'
                  : 'yes',
              preferredLanguage: 'en',
              weatherContext: _fieldConditionContext,
              safetySource: _nullIfBlank(_safetySourceController.text),
              safetyNotes: _nullIfBlank(_safetyNotesController.text),
              safetyInputsVerified: _safeIntervalVerified,
            )
          : await provider.recheckSafety(
              safetyStatus: _safetyStatus!,
              safetySource: _nullIfBlank(_safetySourceController.text),
              safetyNotes: _nullIfBlank(_safetyNotesController.text),
              safetyInputsVerified: _safeIntervalVerified,
              weatherContext: _fieldConditionContext,
            );
      if (!mounted) return;

      if (result.status == DatabaseCodes.inProgress) {
        await Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute(builder: (_) => const AssessmentSessionScreen()),
        );
        return;
      }

      if (!DatabaseCodes.isGrowthStageImplemented(result.growthStage)) {
        _showMessage(
          '${AssessmentProtocolSelector.growthStageLabel(result.growthStage)} assessment workflow is not yet available. Your setup draft is saved on this phone.',
        );
        return;
      }

      _showMessage(
        'Assessment setup saved, but field entry is blocked until safety can be verified.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the assessment setup: $error');
    }
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get _fieldConditionContext {
    final automatic = _recentRain;
    if (automatic != null) {
      return [
        'open_meteo_precipitation_last_48h_mm=${automatic.precipitationMm.toStringAsFixed(2)}',
        'weather_period_end_utc=${automatic.periodEndUtc.toIso8601String()}',
        'weather_fetched_at_utc=${automatic.fetchedAtUtc.toIso8601String()}',
      ].join(';');
    }
    final parts = <String>[];
    if (_rainLast48Hours != null) {
      parts.add('rain_wet_field_last_48h=$_rainLast48Hours');
    }
    return parts.isEmpty ? null : parts.join(';');
  }

  List<AccessibleChoiceOption<String>> get _growthStageChoices {
    const stageAssets = <String, String>{
      've': 'assets/images/growth_stages/maize_emergence.jpg',
      'v1': 'assets/images/growth_stages/maize_emergence.jpg',
      'v2': 'assets/images/growth_stages/maize_emergence.jpg',
      'v3_v6': 'assets/images/growth_stages/maize_young_vegetative.jpg',
      'v7_v12': 'assets/images/growth_stages/maize_tall_vegetative.jpg',
      'vt_r2': 'assets/images/growth_stages/maize_silks.jpg',
      'r3_r6': 'assets/images/growth_stages/maize_mature_kernels.jpg',
    };
    const visualGroups = <String, String>{
      've': 'early_ve_v2',
      'v1': 'early_ve_v2',
      'v2': 'early_ve_v2',
      'v3_v6': 'young_v3_v6',
      'v7_v12': 'tall_v7_v12',
      'vt_r2': 'reproductive_vt_r2',
      'r3_r6': 'ear_fill_r3_r6',
    };
    const imageCaptions = <String, String>{
      've':
          'Early maize (VE-V2): compare the shoot, then count visible collars.',
      'v1':
          'Early maize (VE-V2): compare the shoot, then count visible collars.',
      'v2':
          'Early maize (VE-V2): compare the shoot, then count visible collars.',
      'v3_v6': 'Young maize (V3-V6): count collars on one plant.',
      'v7_v12':
          'Taller maize (V7-V12): count collars; height alone is unreliable.',
      'vt_r2':
          'Silking example within VT-R2: check tassels, silks, then kernels.',
      'r3_r6':
          'Mature-kernel example within R3-R6: open an ear and inspect the kernels.',
    };
    return AssessmentProtocolSelector.growthStages
        .map(
          (stage) => AccessibleChoiceOption(
            value: stage.code,
            label: stage.label,
            description: stage.help,
            assetPath: stageAssets[stage.code],
            visualGroup: visualGroups[stage.code],
            imageCaption: imageCaptions[stage.code],
          ),
        )
        .toList(growable: false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssessmentWorkspaceProvider>();
    final workspace = provider.fieldWorkspace;
    final assessment = provider.currentAssessment;

    if (provider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (workspace == null) {
      return const Scaffold(
        body: Center(child: Text('Select a maize field before assessment.')),
      );
    }
    if (!workspace.hasApproximateOutline) {
      return _BoundaryRequiredScreen(
        workspace: workspace,
        hasSavedAssessment: assessment != null,
      );
    }
    if (assessment?.status == DatabaseCodes.inProgress) {
      return const AssessmentSessionScreen();
    }

    final isExisting = assessment != null;
    final stageHelp = AssessmentProtocolSelector.growthStageHelp(_growthStage);
    final routePattern = isExisting
        ? assessment.scoutingPattern
        : _recommendedPattern;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isExisting ? 'Review Assessment Safety' : 'Assessment Setup',
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: FilledButton.icon(
              key: const Key('save_assessment_setup_button'),
              onPressed: provider.isSaving ? null : _submit,
              icon: provider.isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _safetyAllowsEntry
                          ? Icons.play_arrow
                          : Icons.save_outlined,
                    ),
              label: Text(
                provider.isSaving
                    ? 'Saving...'
                    : _safetyAllowsEntry
                    ? 'Save and Begin Scouting'
                    : 'Save Assessment Setup',
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FieldSummaryCard(
                fieldName: workspace.field.name,
                areaHectares: workspace.boundary?.areaHectares,
              ),
              if (isExisting) ...[
                const SizedBox(height: 12),
                _SafetyBlockedNotice(status: assessment.status),
              ],
              const SizedBox(height: 20),
              const _SectionTitle('Person conducting the assessment'),
              if (isExisting)
                const _LockedValue(
                  icon: Icons.person_outline,
                  value: 'Evaluator saved with this draft',
                )
              else
                TextFormField(
                  key: const Key('assessment_evaluator_input'),
                  controller: _evaluatorController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'Farmer, technician, or other evaluator',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the name of the person doing the assessment.'
                      : null,
                ),
              const SizedBox(height: 20),
              const _SectionTitle('Maize growth stage'),
              AccessibleChoiceField<String>(
                key: const Key('growth_stage_choice'),
                label: 'Best estimate *',
                sheetTitle: 'Compare maize growth stages',
                value: _growthStage,
                options: _growthStageChoices,
                showImages: true,
                leadingIcon: Icons.eco_outlined,
                onChanged: isExisting
                    ? null
                    : (value) {
                        setState(() {
                          _growthStage = value;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Text(
                stageHelp,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Scouting route'),
              _AutomaticRouteCard(pattern: routePattern),
              const SizedBox(height: 20),
              const _SectionTitle('Recent rain'),
              _RecentWeatherContent(
                state: _weatherLookupState,
                snapshot: _recentRain,
                rainLast48Hours: _rainLast48Hours,
                onChanged: (value) => setState(() => _rainLast48Hours = value),
                onRetry: () => _startWeatherLookup(workspace),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('Field-entry safety check'),
              const _SafetyExplanation(),
              const SizedBox(height: 10),
              RadioGroup<String>(
                groupValue: _safetyStatus,
                onChanged: _selectSafety,
                child: Column(
                  children: [
                    _SafetyOption(
                      key: const Key('safety_no_recent_treatment_option'),
                      value: DatabaseCodes.noRecentTreatment,
                      selected:
                          _safetyStatus == DatabaseCodes.noRecentTreatment,
                      title: 'No recent pesticide treatment',
                      subtitle:
                          'No treatment with a required waiting period was recently applied.',
                    ),
                    _SafetyOption(
                      key: const Key('safety_interval_completed_option'),
                      value: DatabaseCodes.safeIntervalCompleted,
                      selected:
                          _safetyStatus == DatabaseCodes.safeIntervalCompleted,
                      title: 'Treatment applied — waiting period ended',
                      subtitle:
                          'Checked using the label, spray record, or authorized advice.',
                    ),
                    _SafetyOption(
                      key: const Key('safety_interval_active_option'),
                      value: DatabaseCodes.blockedReiActive,
                      selected: _safetyStatus == DatabaseCodes.blockedReiActive,
                      title: 'Waiting period is still active',
                      subtitle: 'Do not enter or begin scouting.',
                    ),
                    _SafetyOption(
                      key: const Key('safety_cannot_confirm_option'),
                      value: DatabaseCodes.cannotConfirmSafety,
                      selected:
                          _safetyStatus == DatabaseCodes.cannotConfirmSafety,
                      title: 'Treatment history is unknown',
                      subtitle: 'Do not enter until it can be verified.',
                    ),
                  ],
                ),
              ),
              if (_safetyStatus == DatabaseCodes.safeIntervalCompleted) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('safety_source_input'),
                  controller: _safetySourceController,
                  decoration: const InputDecoration(
                    labelText: 'How was the waiting period verified? *',
                    hintText:
                        'Product label, farm record, or authorized advice',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                CheckboxListTile(
                  key: const Key('safety_verified_checkbox'),
                  value: _safeIntervalVerified,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I verified that the required interval has fully ended',
                  ),
                  onChanged: (value) =>
                      setState(() => _safeIntervalVerified = value ?? false),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _safetyNotesController,
                decoration: const InputDecoration(
                  labelText: 'Safety note (optional)',
                  hintText: 'Known spray date, product, or person consulted',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _selectSafety(String? value) {
    setState(() {
      _safetyStatus = value;
      if (value != DatabaseCodes.safeIntervalCompleted) {
        _safeIntervalVerified = false;
      }
    });
  }
}

class _BoundaryRequiredScreen extends StatelessWidget {
  const _BoundaryRequiredScreen({
    required this.workspace,
    required this.hasSavedAssessment,
  });

  final FieldWorkspaceRecord workspace;
  final bool hasSavedAssessment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessment Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.polyline_outlined,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Complete field outline',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              hasSavedAssessment
                  ? 'Your saved assessment setup remains on this phone. Confirm the field outline before continuing it.'
                  : 'Confirm the field outline before setting up an assessment for ${workspace.field.name}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The outline is an approximate guide for field scouting. It is not a legal or survey-grade property boundary.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton.icon(
                key: const Key('complete_field_outline_from_setup_button'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FieldBoundarySetupScreen(),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Complete field outline'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldSummaryCard extends StatelessWidget {
  const _FieldSummaryCard({
    required this.fieldName,
    required this.areaHectares,
  });

  final String fieldName;
  final double? areaHectares;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.agriculture_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fieldName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${areaHectares?.toStringAsFixed(2) ?? '--'} ha - field scouting setup',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _LockedValue extends StatelessWidget {
  const _LockedValue({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon),
      title: Text(value),
    );
  }
}

class _AutomaticRouteCard extends StatelessWidget {
  const _AutomaticRouteCard({required this.pattern});

  final String pattern;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('automatic_scouting_route'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AssessmentProtocolSelector.patternLabel(pattern),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.lock_outline, size: 19),
        ],
      ),
    );
  }
}

enum _WeatherLookupState { idle, loading, available, unavailable }

class _RecentWeatherContent extends StatelessWidget {
  const _RecentWeatherContent({
    required this.state,
    required this.snapshot,
    required this.rainLast48Hours,
    required this.onChanged,
    required this.onRetry,
  });

  final _WeatherLookupState state;
  final RecentRainSnapshot? snapshot;
  final String? rainLast48Hours;
  final ValueChanged<String> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == _WeatherLookupState.loading ||
        state == _WeatherLookupState.idle) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Checking recent weather…'),
        ],
      );
    }
    if (state == _WeatherLookupState.available && snapshot != null) {
      return Container(
        key: const Key('automatic_recent_weather'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.water_drop_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Rain in the last 2 days: '
                '${snapshot!.precipitationMm.toStringAsFixed(1)} mm\n'
                'That is about ${snapshot!.precipitationMm.toStringAsFixed(1)} litres of rain per square metre.',
                style: const TextStyle(height: 1.35),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Recent weather could not be retrieved. Add it only if known.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            IconButton(
              key: const Key('retry_recent_weather_button'),
              tooltip: 'Retry weather',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AccessibleChoiceField<String>(
          key: const Key('rain_last_48_hours_choice'),
          label: 'Did rain wet this field in the last 48 hours?',
          sheetTitle: 'Rain during the last 48 hours',
          value: rainLast48Hours,
          leadingIcon: Icons.water_drop_outlined,
          hintText: 'Add what you know (optional)',
          options: const [
            AccessibleChoiceOption(value: 'yes', label: 'Yes'),
            AccessibleChoiceOption(value: 'no', label: 'No'),
            AccessibleChoiceOption(value: 'not_sure', label: 'I am not sure'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SafetyExplanation extends StatelessWidget {
  const _SafetyExplanation();

  void _showWaitingPeriodHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What is the waiting period?'),
        content: const Text(
          'After some pesticides are applied, the product label requires people '
          'to wait a stated number of hours or days before entering the treated '
          'field without special protection. This is formally called the '
          'restricted-entry interval (REI). If the period is unknown, do not '
          'enter until the label, spray record, applicator, or agricultural '
          'adviser confirms it.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD666)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Was this field sprayed or treated recently? Check the product '
                  'label, spray record, or ask the applicator before entering.',
                  style: TextStyle(height: 1.35),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => _showWaitingPeriodHelp(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('What is the waiting period?'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyOption extends StatelessWidget {
  const _SafetyOption({
    super.key,
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  final String value;
  final bool selected;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outlineVariant,
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _SafetyBlockedNotice extends StatelessWidget {
  const _SafetyBlockedNotice({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status == DatabaseCodes.safetyBlocked
            ? 'This draft is saved, but field entry is blocked. Recheck safety below when reliable information becomes available.'
            : 'This draft was not started. Complete the safety check below.',
        style: const TextStyle(height: 1.4),
      ),
    );
  }
}
