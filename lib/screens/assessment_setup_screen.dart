import '../services/scouting_sampling_protocol.dart';
import 'dart:async';
import 'help_support_screen.dart';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';

import '../data/local/database_codes.dart';
import '../data/local/app_database.dart';
import '../localization/app_language.dart';
import '../data/repositories/field_repository.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../services/assessment_protocol_selector.dart';
import '../services/assessment_area_policy.dart';
import '../services/recent_weather_service.dart';
import '../services/treatment_entry_safety.dart';
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
  String? _evaluatorName;
  final _reentryController = TextEditingController();
  final _productController = TextEditingController();

  String _growthStage = 'v3_v6';
  String? _rainLast48Hours;
  String? _safetyStatus;
  DateTime? _applicationEndedAt;
  String _applicationTimePrecision = 'exact';
  String _reentryUnit = 'hours';
  String? _reentrySource;
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
      unawaited(_restoreSafetyDetails(assessment.id));
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

  Future<void> _restoreSafetyDetails(String assessmentId) async {
    final database = context.read<AppDatabase>();
    final check =
        await (database.select(database.safetyChecks)
              ..where((row) => row.assessmentId.equals(assessmentId))
              ..orderBy([(row) => OrderingTerm.desc(row.checkedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (!mounted || _loadedAssessmentId != assessmentId || check == null) {
      return;
    }
    final match = RegExp(
      r'^(\d+) (hours|days)$',
    ).firstMatch(check.reiTextUsed ?? '');
    final product = RegExp(
      r'Reported treatment/product: (.*?) \(not label-verified\)',
    ).firstMatch(check.notes ?? '');
    setState(() {
      _safetyStatus =
          check.resultStatus == DatabaseCodes.safeIntervalCompleted ||
              check.resultStatus == DatabaseCodes.blockedReiActive ||
              check.applicationEndAtUsed != null ||
              check.reiTextUsed != null
          ? DatabaseCodes.safeIntervalCompleted
          : check.resultStatus;
      _applicationEndedAt = check.applicationEndAtUsed?.toLocal();
      _applicationTimePrecision =
          check.notes?.contains('Application end time: approximate') == true
          ? 'approximate'
          : check.notes?.contains('Application end time: unknown') == true
          ? 'unknown'
          : 'exact';
      _reentryController.text = match?.group(1) ?? '';
      _reentryUnit = match?.group(2) ?? 'hours';
      _reentrySource =
          const {
            'product_label',
            'spray_record',
            'agricultural_adviser',
            'unknown',
          }.contains(check.reiSource)
          ? check.reiSource
          : null;
      _productController.text = product?.group(1) ?? '';
    });
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
    _reentryController.dispose();
    _productController.dispose();
    super.dispose();
  }

  String get _recommendedPattern => ScoutingSamplingProtocol.daPattern;

  TreatmentEntrySafety? get _treatment =>
      _safetyStatus == DatabaseCodes.safeIntervalCompleted
      ? TreatmentEntrySafety(
          applicationEndedAt: _applicationEndedAt,
          timePrecision: _applicationTimePrecision,
          reentryValue: int.tryParse(_reentryController.text.trim()),
          reentryUnit: _reentryUnit,
          source: _reentrySource,
          reportedProduct: _productController.text,
        )
      : null;

  String? get _resolvedSafetyStatus =>
      _treatment?.statusAt(DateTime.now()) ?? _safetyStatus;

  bool get _safetyAllowsEntry =>
      _resolvedSafetyStatus == DatabaseCodes.noRecentTreatment ||
      _resolvedSafetyStatus == DatabaseCodes.safeIntervalCompleted;

  Future<void> _submit() async {
    final provider = context.read<AssessmentWorkspaceProvider>();
    final existing = provider.currentAssessment;
    final area = provider.fieldWorkspace?.boundary?.areaHectares;
    if (!_formKey.currentState!.validate()) return;
    if (existing == null && _evaluatorName == null) {
      _showMessage('Select who is conducting the assessment.');
      return;
    }
    if (area != null && !AssessmentAreaPolicy.isWithinAssessmentLimit(area)) {
      _showMessage(
        'Formal assessment currently supports fields up to '
        '${AssessmentAreaPolicy.maxAssessmentAreaHectares.toStringAsFixed(0)} ha. '
        'The field remains saved, but scouting cannot begin.',
      );
      return;
    }
    if (_safetyStatus == null) {
      _showMessage('Select the field-entry safety situation.');
      return;
    }
    try {
      final result = existing == null
          ? await provider.createAssessment(
              evaluatorName: _evaluatorName!,
              assessmentMode: AssessmentProtocolSelector.assessmentModeFor(
                _growthStage,
              ),
              scoutingPattern: _recommendedPattern,
              patternReason: null,
              growthStage: _growthStage,
              growthStageUncertain: false,
              safetyStatus: _resolvedSafetyStatus!,
              interventionHistoryStatus:
                  _safetyStatus == DatabaseCodes.noRecentTreatment
                  ? 'no'
                  : _safetyStatus == DatabaseCodes.cannotConfirmSafety
                  ? 'unknown'
                  : 'yes',
              preferredLanguage: 'en',
              weatherContext: _fieldConditionContext,
              treatment: _treatment,
            )
          : await provider.recheckSafety(
              safetyStatus: _resolvedSafetyStatus!,
              treatment: _treatment,
              weatherContext: _fieldConditionContext,
            );
      if (!mounted) return;

      if (result.status == DatabaseCodes.inProgress) {
        await Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute(
            builder: (_) => AssessmentSessionScreen(assessmentId: result.id),
          ),
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
    final words = AppWords.of(context);
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
            label: words.stageOptionLabel(stage.code),
            description: words.stageOptionHelp(stage.code),
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
    ).showSnackBar(SnackBar(content: AppText(message)));
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
        body: Center(child: AppText('Select a maize field before assessment.')),
      );
    }
    if (!workspace.hasApproximateOutline) {
      return _BoundaryRequiredScreen(
        workspace: workspace,
        hasSavedAssessment: assessment != null,
      );
    }
    if (assessment?.status == DatabaseCodes.inProgress) {
      return AssessmentSessionScreen(assessmentId: assessment!.id);
    }

    final isExisting = assessment != null;
    final routePattern = isExisting
        ? assessment.scoutingPattern
        : _recommendedPattern;

    return Scaffold(
      appBar: AppBar(
        title: AppText(
          isExisting ? 'Review Assessment Safety' : 'Assessment Setup',
        ),
        actions: [
          IconButton(
            tooltip: AppWords.of(context).helpAndSupport,
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HelpSupportScreen(initialTopic: 'assess'),
              ),
            ),
          ),
        ],
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
              label: AppText(
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
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    _FieldSummaryCard(
                      fieldName: workspace.field.name,
                      areaHectares: workspace.boundary?.areaHectares,
                    ),
                    if (workspace.boundary != null)
                      _AssessmentWorkloadCard(
                        areaHectares: workspace.boundary!.areaHectares,
                        isDa:
                            routePattern == ScoutingSamplingProtocol.daPattern,
                      ),
                  ],
                ),
              ),
              if (isExisting) ...[
                const SizedBox(height: 12),
                _SafetyBlockedNotice(status: assessment.status),
              ],
              const SizedBox(height: 26),
              const _SectionTitle('Assessment details'),
              if (isExisting)
                const _LockedValue(
                  icon: Icons.person_outline,
                  value: 'Evaluator saved with this draft',
                )
              else
                DropdownButtonFormField<String>(
                  key: const Key('assessment_evaluator_input'),
                  initialValue: _evaluatorName,
                  decoration: InputDecoration(
                    labelText: AppWords.of(context).translate('Assessor'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items:
                      const [
                            'Farmer',
                            'Field technician',
                            'Agronomist',
                            'Others',
                          ]
                          .map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Text(name),
                            ),
                          )
                          .toList(),
                  onChanged: (name) => setState(() => _evaluatorName = name),
                  validator: (name) => name == null
                      ? AppWords.of(context).translate('Select a person.')
                      : null,
                ),
              const SizedBox(height: 12),
              AccessibleChoiceField<String>(
                key: const Key('growth_stage_choice'),
                label: AppWords.of(context).maizeGrowthStage,
                sheetTitle: AppWords.of(context).compareGrowthStages,
                value: _growthStage,
                options: _growthStageChoices,
                showImages: true,
                leadingIcon: Icons.timeline_outlined,
                onChanged: isExisting
                    ? null
                    : (value) {
                        setState(() {
                          _growthStage = value;
                        });
                      },
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Scouting route'),
              _AutomaticRouteCard(pattern: routePattern),
              const SizedBox(height: 22),
              const _SectionTitle('Recent rain'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: _RecentWeatherContent(
                  state: _weatherLookupState,
                  snapshot: _recentRain,
                  rainLast48Hours: _rainLast48Hours,
                  onChanged: (value) =>
                      setState(() => _rainLast48Hours = value),
                  onRetry: () => _startWeatherLookup(workspace),
                ),
              ),
              const SizedBox(height: 27),
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
                      title: 'Pesticide treatment applied',
                      subtitle:
                          'Record when spraying ended and the required re-entry period.',
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8F4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          AppText(
                            'Treatment details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const Key('treatment_time_precision'),
                        initialValue: _applicationTimePrecision,
                        decoration: InputDecoration(
                          labelText: AppWords.of(
                            context,
                          ).translate('When did spraying end?'),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'exact',
                            child: AppText('Exact date and time'),
                          ),
                          DropdownMenuItem(
                            value: 'approximate',
                            child: AppText('Approximate date'),
                          ),
                          DropdownMenuItem(
                            value: 'unknown',
                            child: AppText('Unknown'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _applicationTimePrecision = value ?? 'unknown';
                          _applicationEndedAt = null;
                        }),
                      ),
                      if (_applicationTimePrecision != 'unknown') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('treatment_end_date_button'),
                          onPressed: _pickApplicationEnd,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(56),
                            alignment: Alignment.centerLeft,
                          ),
                          icon: const Icon(Icons.event_outlined),
                          label: AppText(
                            _applicationEndedAt == null
                                ? 'Select end ${_applicationTimePrecision == 'exact' ? 'date and time' : 'date'}'
                                : '${MaterialLocalizations.of(context).formatShortDate(_applicationEndedAt!)}${_applicationTimePrecision == 'exact' ? ' · ${TimeOfDay.fromDateTime(_applicationEndedAt!).format(context)}' : ''}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              key: const Key('treatment_reentry_value'),
                              controller: _reentryController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: AppWords.of(
                                  context,
                                ).translate('Re-entry period'),
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              key: const Key('treatment_reentry_unit'),
                              initialValue: _reentryUnit,
                              decoration: InputDecoration(
                                labelText: AppWords.of(
                                  context,
                                ).translate('Unit'),
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'hours',
                                  child: AppText('Hours'),
                                ),
                                DropdownMenuItem(
                                  value: 'days',
                                  child: AppText('Days'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _reentryUnit = value ?? 'hours',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: const Key('treatment_reentry_source'),
                        initialValue: _reentrySource,
                        decoration: InputDecoration(
                          labelText: AppWords.of(
                            context,
                          ).translate('Source of re-entry period'),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'product_label',
                            child: AppText('Product label'),
                          ),
                          DropdownMenuItem(
                            value: 'spray_record',
                            child: AppText('Spray record'),
                          ),
                          DropdownMenuItem(
                            value: 'agricultural_adviser',
                            child: AppText('Agricultural adviser'),
                          ),
                          DropdownMenuItem(
                            value: 'unknown',
                            child: AppText('Unknown'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _reentrySource = value),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: const Key('treatment_product_input'),
                        controller: _productController,
                        decoration: InputDecoration(
                          labelText: AppWords.of(
                            context,
                          ).translate('Product used (optional)'),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _TreatmentEntryStatus(treatment: _treatment!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _selectSafety(String? value) {
    setState(() => _safetyStatus = value);
  }

  Future<void> _pickApplicationEnd() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _applicationEndedAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    if (_applicationTimePrecision == 'approximate') {
      setState(() => _applicationEndedAt = date);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: _applicationEndedAt == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_applicationEndedAt!),
    );
    if (time == null || !mounted) return;
    final endedAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (endedAt.isAfter(DateTime.now())) {
      _showMessage('The treatment end time cannot be in the future.');
      return;
    }
    setState(() => _applicationEndedAt = endedAt);
  }
}

class _TreatmentEntryStatus extends StatelessWidget {
  const _TreatmentEntryStatus({required this.treatment});

  final TreatmentEntrySafety treatment;

  @override
  Widget build(BuildContext context) {
    final status = treatment.statusAt(DateTime.now());
    final safeAt = treatment.safeEntryAt;
    final message = status == DatabaseCodes.safeIntervalCompleted
        ? 'The reported re-entry period has elapsed. Check any other label restrictions before entering.'
        : status == DatabaseCodes.blockedReiActive
        ? 'Do not enter yet. The reported re-entry period ends at ${safeAt!.toLocal()}.'
        : 'Entry safety is not confirmed. Check the product label or an authorized adviser before scouting.';
    return Container(
      key: const Key('treatment_entry_status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status == DatabaseCodes.safeIntervalCompleted
            ? AppColors.primaryLight
            : const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppText(message, style: const TextStyle(height: 1.35)),
    );
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
      appBar: AppBar(title: const AppText('Assessment Setup')),
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
            const AppText(
              'Complete field outline',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            AppText(
              hasSavedAssessment
                  ? 'Your saved assessment setup remains on this phone. Confirm the field outline before continuing it.'
                  : AppWords.of(context).format(
                      'Confirm the field outline before setting up an assessment for {field}.',
                      {'field': workspace.field.name},
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            const AppText(
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
                label: const AppText('Complete field outline'),
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
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.agriculture_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fieldName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  '${areaHectares?.toStringAsFixed(2) ?? '--'} ha',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
      title: AppText(value),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: AppText(
              AssessmentProtocolSelector.patternLabel(pattern),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const Icon(
            Icons.lock_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            AppText('Checking recent weather…'),
          ],
        ),
      );
    }
    if (state == _WeatherLookupState.available && snapshot != null) {
      return Container(
        key: const Key('automatic_recent_weather'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            const Icon(Icons.water_drop_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: AppText(
                'Last 48 hours · ${snapshot!.precipitationMm.toStringAsFixed(1)} mm',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
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
                child: AppText(
                  'Recent weather could not be retrieved. Add it only if known.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              IconButton(
                key: const Key('retry_recent_weather_button'),
                tooltip: AppWords.of(context).translate('Retry weather'),
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
            hintText: AppWords.of(
              context,
            ).translate('Add what you know (optional)'),
            options: const [
              AccessibleChoiceOption(value: 'yes', label: 'Yes'),
              AccessibleChoiceOption(value: 'no', label: 'No'),
              AccessibleChoiceOption(value: 'not_sure', label: 'I am not sure'),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SafetyExplanation extends StatelessWidget {
  const _SafetyExplanation();

  void _showWaitingPeriodHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('What is the waiting period?'),
        content: const AppText(
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
            child: const AppText('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Expanded(
            child: AppText(
              'Confirm treatment before entering.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: AppWords.of(
              context,
            ).translate('What is the waiting period?'),
            onPressed: () => _showWaitingPeriodHelp(context),
            icon: const Icon(Icons.help_outline, size: 21),
            visualDensity: VisualDensity.compact,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? AppColors.primaryLight : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: RadioListTile<String>(
          value: value,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 1,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12.5, height: 1.2),
          ),
        ),
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

class _AssessmentWorkloadCard extends StatelessWidget {
  const _AssessmentWorkloadCard({
    required this.areaHectares,
    required this.isDa,
  });

  final double areaHectares;
  final bool isDa;

  @override
  Widget build(BuildContext context) {
    final withinLimit = AssessmentAreaPolicy.isWithinAssessmentLimit(
      areaHectares,
    );
    final blocks = AssessmentAreaPolicy.requiredBlockCount(areaHectares);
    final message = withinLimit
        ? isDa
              ? '$blocks ${blocks == 1 ? 'block' : 'blocks'} · '
                    '${blocks * ScoutingSamplingProtocol.plantsPerBlock} plants · '
                    '20 plants per sampling block'
              : '$blocks ${blocks == 1 ? 'block' : 'blocks'} · '
                    '${blocks * 5} stations · ${blocks * 50} observations'
        : 'Formal assessment is limited to '
              '${AssessmentAreaPolicy.maxAssessmentAreaHectares.toStringAsFixed(0)} ha. '
              'This field can remain saved, but scouting cannot begin.';

    return Container(
      key: const Key('assessment_workload_card'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 11),
          Text(
            message,
            style: TextStyle(
              color: withinLimit
                  ? AppColors.textSecondary
                  : const Color(0xFF8A1C1C),
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (withinLimit && blocks > 1) ...[
            const SizedBox(height: 3),
            const AppText(
              'Confirm each block before scouting.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
