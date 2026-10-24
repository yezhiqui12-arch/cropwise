import 'dart:async';
import '../data/local/app_database.dart';
import '../services/cloud/field_catalog_service.dart';
import '../services/cloud/wormwise_identity_service.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';
import 'package:flutter/material.dart';
import '../localization/app_language.dart';
import '../localization/app_text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';
import '../services/arcgis_place_geocoder.dart';
import '../services/piat_barangay_centers.dart';
import '../widgets/accessible_choice_field.dart';
import 'boundary_map_screen.dart';

class CreateFieldScreen extends StatefulWidget {
  const CreateFieldScreen({super.key, this.workspace});

  final FieldWorkspaceRecord? workspace;

  @override
  State<CreateFieldScreen> createState() => _CreateFieldScreenState();
}

class _CreateFieldScreenState extends State<CreateFieldScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _municipalityController = TextEditingController(text: 'Piat');
  final _provinceController = TextEditingController(text: 'Cagayan');
  final _varietyController = TextEditingController();
  final _varietyFocusNode = FocusNode();
  final _plantingDateController = TextEditingController();

  String? _barangay;
  DateTime? _plantingDate;
  bool _isResolvingLocation = false;
  int _currentStep = 0;

  bool get _isEditing => widget.workspace != null;

  List<String> _piatBarangays = List.of(FieldCatalogService.barangays);
  List<String> _varietySuggestions = List.of(FieldCatalogService.varieties);
  String _catalogStatus = 'Saved Piat list available offline.';
  bool _savingCatalog = false;

  FieldCatalogService get _catalog => FieldCatalogService(
    context.read<AppDatabase>(),
    context.read<WormWiseIdentityService>().client,
  );

  Future<void> _loadCatalogs() async {
    final service = _catalog;
    final places = await service.cached(
      'piat_barangay_catalog',
      FieldCatalogService.barangays,
    );
    final crops = await service.cached(
      'maize_variety_catalog',
      FieldCatalogService.varieties,
    );
    if (!mounted) return;
    setState(() {
      _piatBarangays = places;
      if (_barangay != null && !places.contains(_barangay)) _barangay = null;
      _varietySuggestions = crops;
    });
    try {
      final fresh = await service.refresh(
        'piat_barangays',
        'piat_barangay_catalog',
      );
      if (mounted)
        setState(() {
          _piatBarangays = fresh;
          if (_barangay != null && !fresh.contains(_barangay)) _barangay = null;
          _catalogStatus = 'Piat list updated online. Available offline.';
        });
    } catch (_) {
      /* Keep the saved list when offline or awaiting migration. */
    }
    try {
      final fresh = await service.refresh(
        'maize_varieties',
        'maize_variety_catalog',
      );
      if (mounted) setState(() => _varietySuggestions = fresh);
    } catch (_) {
      /* Local entry remains available. */
    }
  }

  Future<bool> _confirmVariety() async {
    final name = _varietyController.text.trim();
    final key = FieldCatalogService.normalize(name);
    if (name.isEmpty) return true;
    final exact = _varietySuggestions.where(
      (v) => FieldCatalogService.normalize(v) == key,
    );
    if (exact.isNotEmpty) {
      _varietyController.text = exact.first;
      return true;
    }
    final similar = _varietySuggestions
        .where((v) {
          final known = FieldCatalogService.normalize(v);
          return known.contains(key) ||
              key.contains(known) ||
              _editDistance(key, known) <= 2;
        })
        .take(5)
        .toList();
    if (similar.isEmpty) return true;
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Did you mean an existing variety?'),
        children: [
          for (final value in similar)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, value),
              child: Text(value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, name),
            child: Text('Use my entry: $name'),
          ),
        ],
      ),
    );
    if (selected == null) return false;
    _varietyController.text = selected;
    return true;
  }

  int _editDistance(String a, String b) {
    var previous = List.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final next = [i];
      for (var j = 1; j <= b.length; j++) {
        final values = [
          next[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ]..sort();
        next.add(values.first);
      }
      previous = next;
    }
    return previous.last;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalogs());
    final workspace = widget.workspace;
    if (workspace == null) return;
    final field = workspace.field;
    final cycle = workspace.cropCycle;
    _nameController.text = field.name;
    _municipalityController.text = field.municipalityCity ?? 'Piat';
    _provinceController.text = field.province ?? 'Cagayan';
    _varietyController.text = cycle?.varietyName ?? '';
    _barangay = field.barangay;
    _plantingDate = cycle?.plantingDate?.toLocal();
    if (_plantingDate != null) {
      _plantingDateController.text = DateFormat(
        'MMM d, yyyy',
      ).format(_plantingDate!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _municipalityController.dispose();
    _provinceController.dispose();
    _varietyController.dispose();
    _varietyFocusNode.dispose();
    _plantingDateController.dispose();
    super.dispose();
  }

  Future<void> _pickPlantingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantingDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Select maize planting date',
    );
    if (picked == null) return;

    setState(() {
      _plantingDate = picked;
      _plantingDateController.text = DateFormat('MMM d, yyyy').format(picked);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_barangay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Select the field barangay first.')),
      );
      return;
    }

    if (_savingCatalog) return;
    setState(() => _savingCatalog = true);
    if (!await _confirmVariety() || !mounted) {
      if (mounted) setState(() => _savingCatalog = false);
      return;
    }
    final catalog = _catalog;
    final sync = context.read<WormWiseCloudSyncService>();
    final provider = context.read<FieldWorkspaceProvider>();
    try {
      if (_isEditing) {
        await provider.updateFieldDetails(
          fieldId: widget.workspace!.field.id,
          name: _nameController.text,
          barangay: _barangay,
          varietyName: _varietyController.text.trim(),
          plantingDate: _plantingDate,
        );
      } else {
        await provider.createField(
          name: _nameController.text,
          barangay: _barangay,
          municipalityCity: _municipalityController.text,
          province: _provinceController.text,
          varietyName: _varietyController.text.trim(),
          plantingDate: _plantingDate,
        );
        await _queueNewVariety(catalog, sync);
        if (!mounted) return;
        final barangay = _barangay;
        setState(() => _isResolvingLocation = true);
        final barangayCenter = PiatBarangayCenters.forName(barangay);
        final place = barangayCenter != null || barangay == null
            ? null
            : await const ArcGisPlaceGeocoder().locate(
                barangay: barangay,
                municipality: _municipalityController.text.trim(),
                province: _provinceController.text.trim(),
              );
        if (!mounted) return;
        setState(() => _isResolvingLocation = false);
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => FieldBoundarySetupScreen(
              initialLatitude: barangayCenter?.latitude ?? place?.latitude,
              initialLongitude: barangayCenter?.longitude ?? place?.longitude,
              locationLabel:
                  place?.label ??
                  [
                        barangay,
                        _municipalityController.text.trim(),
                        _provinceController.text.trim(),
                      ]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(', '),
            ),
          ),
        );
      }
      if (_isEditing) await _queueNewVariety(catalog, sync);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('Could not save the field: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingCatalog = false);
    }
  }

  Future<void> _queueNewVariety(
    FieldCatalogService catalog,
    WormWiseCloudSyncService sync,
  ) async {
    final name = _varietyController.text.trim();
    final key = FieldCatalogService.normalize(name);
    if (name.isEmpty ||
        _varietySuggestions.any((v) => FieldCatalogService.normalize(v) == key))
      return;
    if (const ['pioneer', 'dekalb', 'nk', 'bioseed'].contains(key)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Brand saved for this field. Enter a specific hybrid or variety to suggest it for everyone.',
            ),
          ),
        );
      return;
    }
    try {
      await catalog.queueVariety(name);
      unawaited(sync.synchronizeNow());
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Variety saved for this field. Suggestion queued for expert approval when online.',
            ),
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Field saved, but its variety suggestion could not be queued. Edit the field to retry.',
            ),
          ),
        );
    }
  }

  void _continueToCrop() {
    if (!_formKey.currentState!.validate()) return;
    if (_barangay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Select the field barangay first.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _currentStep = 1);
  }

  void _handleBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = context.select<FieldWorkspaceProvider, bool>(
      (provider) => provider.isSaving,
    );
    final isBusy = isSaving || _isResolvingLocation || _savingCatalog;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: AppText(_isEditing ? 'Edit Maize Field' : 'Add Maize Field'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: ElevatedButton(
              key: const Key('save_field_button'),
              onPressed: isBusy
                  ? null
                  : _currentStep == 0
                  ? _continueToCrop
                  : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBusy) ...[
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  AppText(
                    isBusy
                        ? _isResolvingLocation
                              ? 'Locating barangay...'
                              : 'Saving...'
                        : _currentStep == 0
                        ? 'Continue to maize crop'
                        : _isEditing
                        ? 'Save changes'
                        : 'Save & create boundary',
                  ),
                  if (!isBusy) ...[
                    const SizedBox(width: 10),
                    Icon(
                      _currentStep == 0
                          ? Icons.arrow_forward_rounded
                          : _isEditing
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              _CreationProgress(activeStep: _currentStep),
              const SizedBox(height: 22),
              if (_currentStep == 0) ...[
                const _SectionHeader(
                  title: 'Field Details',
                  subtitle: 'Tell us about your maize field.',
                ),
                const SizedBox(height: 14),
                _FormCard(
                  children: [
                    TextFormField(
                      key: const Key('field_name_input'),
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: AppWords.of(context).translate('Field name'),
                        hintText: AppWords.of(
                          context,
                        ).translate('Example: North Corn Plot'),
                        prefixIcon: Icon(Icons.grass_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? AppWords.of(
                              context,
                            ).translate('Enter a field name.')
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: _isEditing ? 'Confirmed location' : 'Field location',
                  subtitle: _isEditing
                      ? 'The location saved when this field was created.'
                      : 'Barangay is used to center the boundary map.',
                ),
                const SizedBox(height: 14),
                _FormCard(
                  children: [
                    AccessibleChoiceField<String>(
                      key: const Key('field_barangay_choice'),
                      label: 'Barangay *',
                      sheetTitle: 'Select barangay in Piat',
                      value: _barangay,
                      hintText: AppWords.of(
                        context,
                      ).translate('Select barangay'),
                      leadingIcon: Icons.location_on_outlined,
                      options: _piatBarangays
                          .map(
                            (barangay) => AccessibleChoiceOption(
                              value: barangay,
                              label: barangay,
                            ),
                          )
                          .toList(growable: false),
                      helperText: _isEditing
                          ? 'You can update the barangay. $_catalogStatus'
                          : _catalogStatus,
                      onChanged: (value) => setState(() => _barangay = value),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _municipalityController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: AppWords.of(
                          context,
                        ).translate('Municipality or city'),
                        prefixIcon: Icon(Icons.location_city_outlined),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _provinceController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: AppWords.of(context).translate('Province'),
                        prefixIcon: Icon(Icons.map_outlined),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: 'Maize Crop',
                  subtitle:
                      'Add what you know now. Optional details can be updated later.',
                ),
                const SizedBox(height: 14),
                _FormCard(
                  children: [
                    RawAutocomplete<String>(
                      textEditingController: _varietyController,
                      focusNode: _varietyFocusNode,
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _varietySuggestions;
                        }
                        return _varietySuggestions.where((String option) {
                          return FieldCatalogService.normalize(option).contains(
                            FieldCatalogService.normalize(
                              textEditingValue.text,
                            ),
                          );
                        });
                      },
                      onSelected: (String selection) {
                        _varietyController.text = selection;
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextFormField(
                          key: const Key('field_variety_input'),
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return null;
                            if (name.length < 2 ||
                                name.length > 120 ||
                                FieldCatalogService.normalize(name).isEmpty) {
                              return 'Enter a variety name of 2–120 characters.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: AppWords.of(
                              context,
                            ).translate('Maize variety (if known)'),
                            hintText: AppWords.of(context).translate(
                              'Type or choose a variety (e.g. Pioneer P3530YHR)',
                            ),
                            prefixIcon: Icon(Icons.agriculture_outlined),
                            helperText:
                                'New varieties are shared after expert approval. Enter the hybrid name, not only its brand.',
                            helperMaxLines: 3,
                          ),
                          onFieldSubmitted: (value) => onFieldSubmitted(),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 220,
                                maxWidth: 340,
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(
                                    index,
                                  );
                                  return ListTile(
                                    title: AppText(option),
                                    subtitle:
                                        FieldCatalogService.normalize(option) ==
                                            'pioneer30t80'
                                        ? const Text(
                                            'Documented Philippine use; current availability is unconfirmed.',
                                          )
                                        : null,
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _plantingDateController,
                      readOnly: true,
                      onTap: _pickPlantingDate,
                      decoration: InputDecoration(
                        labelText: AppWords.of(
                          context,
                        ).translate('Planting date'),
                        prefixIcon: Icon(Icons.event_available_outlined),
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildNotice(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isEditing
                  ? 'Update the field and crop details below. Piat and Cagayan remain fixed, while the barangay can be corrected.'
                  : 'This registers the field offline using the farmer-reported area. After saving, add the field boundary to prepare its scouting map.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreationProgress extends StatelessWidget {
  const _CreationProgress({required this.activeStep});

  final int activeStep;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${activeStep + 1} of 3',
      child: Row(
        children: [
          _ProgressStep(
            number: '1',
            label: 'Field info',
            active: activeStep == 0,
            completed: activeStep > 0,
          ),
          _ProgressLine(completed: activeStep > 0),
          _ProgressStep(
            number: '2',
            label: 'Maize crop',
            active: activeStep == 1,
          ),
          const _ProgressLine(),
          const _ProgressStep(number: '3', label: 'Boundary'),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({this.completed = false});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 24),
        color: completed
            ? AppColors.primary
            : AppColors.outlineVariant.withValues(alpha: 0.55),
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.number,
    required this.label,
    this.active = false,
    this.completed = false,
  });

  final String number;
  final String label;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final highlighted = active || completed;
    final color = highlighted ? AppColors.primary : AppColors.textMuted;
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlighted
                  ? AppColors.primary
                  : AppColors.surfaceContainer,
              shape: BoxShape.circle,
              boxShadow: active ? AppColors.cardShadow : null,
            ),
            child: completed
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : Text(
                    number,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            AppWords.of(context).translate(label),
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppWords.of(context).translate(title),
          style: const TextStyle(
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppWords.of(context).translate(subtitle),
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.severeSeverityRing),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.severeSeverityRing,
                width: 1.5,
              ),
            ),
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
}
