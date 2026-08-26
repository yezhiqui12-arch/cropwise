import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';
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
  final _areaController = TextEditingController();
  final _municipalityController = TextEditingController(text: 'Piat');
  final _provinceController = TextEditingController(text: 'Cagayan');
  final _locationNotesController = TextEditingController();
  final _varietyController = TextEditingController();
  final _varietyFocusNode = FocusNode();
  final _plantingDateController = TextEditingController();

  String? _barangay;
  DateTime? _plantingDate;
  String? _intendedUse;

  bool get _isEditing => widget.workspace != null;
  bool get _hasConfirmedOutline =>
      widget.workspace?.hasApproximateOutline == true;

  static const List<String> _piatBarangays = [
    'Apayao',
    'Aquib',
    'Baung',
    'Calaoagan',
    'Catarauan',
    'Dugayung',
    'Gumarueng',
    'Macapil',
    'Maguilling',
    'Minanga',
    'Poblacion I',
    'Poblacion II',
    'Santa Barbara',
    'Santo Domingo',
    'Sicatna',
    'Villa Rey',
    'Villa Reyno',
    'Warat',
  ];

  static const List<String> _varietySuggestions = [
    'Pioneer (P3530 / 30T80)',
    'Dekalb (DK 8888S / DK 8131S)',
    'NK (NK 6410 / NK 8840)',
    'Bioseed',
    'IPB Var 6 (Traditional OPV)',
    'Native / Traditional White Corn',
  ];

  @override
  void initState() {
    super.initState();
    final workspace = widget.workspace;
    if (workspace == null) return;
    final field = workspace.field;
    final boundary = workspace.boundary;
    final cycle = workspace.cropCycle;
    _nameController.text = field.name;
    _areaController.text = boundary?.areaHectares.toStringAsFixed(2) ?? '';
    _municipalityController.text = field.municipalityCity ?? 'Piat';
    _provinceController.text = field.province ?? 'Cagayan';
    _locationNotesController.text = field.locationDescription ?? '';
    _varietyController.text = cycle?.varietyName ?? '';
    _barangay = field.barangay;
    _intendedUse = cycle?.intendedUse;
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
    _areaController.dispose();
    _municipalityController.dispose();
    _provinceController.dispose();
    _locationNotesController.dispose();
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

    final provider = context.read<FieldWorkspaceProvider>();
    try {
      if (_isEditing) {
        await provider.updateFieldDetails(
          fieldId: widget.workspace!.field.id,
          name: _nameController.text,
          areaHectares: double.parse(_areaController.text.trim()),
          varietyName: _varietyController.text.trim(),
          intendedUse: _intendedUse,
          plantingDate: _plantingDate,
        );
      } else {
        await provider.createField(
          name: _nameController.text,
          estimatedAreaHectares: double.parse(_areaController.text.trim()),
          barangay: _barangay,
          municipalityCity: _municipalityController.text,
          province: _provinceController.text,
          locationDescription: _locationNotesController.text,
          varietyName: _varietyController.text.trim(),
          intendedUse: _intendedUse,
          plantingDate: _plantingDate,
        );
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const FieldBoundarySetupScreen()),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the field: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = context.select<FieldWorkspaceProvider, bool>(
      (provider) => provider.isSaving,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Maize Field' : 'Add Maize Field'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: ElevatedButton.icon(
              key: const Key('save_field_button'),
              onPressed: isSaving ? null : _save,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                isSaving
                    ? 'Saving...'
                    : _isEditing
                    ? 'Save changes'
                    : 'Save Field',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
              _buildNotice(),
              const SizedBox(height: 20),
              const _SectionTitle('Field identity'),
              TextFormField(
                key: const Key('field_name_input'),
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Field name *',
                  hintText: 'Example: North Corn Plot',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a field name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field_area_input'),
                controller: _areaController,
                readOnly: _hasConfirmedOutline,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _hasConfirmedOutline
                      ? 'Calculated outline area (hectares)'
                      : 'Estimated area (hectares) *',
                  hintText: 'Example: 1.25',
                  suffixText: 'ha',
                  helperText: _hasConfirmedOutline
                      ? 'To change this value, edit the field boundary.'
                      : null,
                  filled: _hasConfirmedOutline,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final area = double.tryParse(value?.trim() ?? '');
                  if (area == null || area <= 0) {
                    return 'Enter an area greater than zero.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _SectionTitle(_isEditing ? 'Confirmed location' : 'Location'),
              AccessibleChoiceField<String>(
                key: const Key('field_barangay_choice'),
                label: 'Barangay',
                sheetTitle: 'Select barangay in Piat',
                value: _barangay,
                hintText: 'Select barangay',
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
                    ? 'Permanent location confirmed when this field was created.'
                    : null,
                onChanged: _isEditing
                    ? null
                    : (value) => setState(() => _barangay = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _municipalityController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Municipality or city',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _provinceController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Province',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationNotesController,
                readOnly: _isEditing,
                decoration: InputDecoration(
                  labelText: 'Landmark or location notes',
                  helperText: _isEditing ? 'Confirmed original location' : null,
                  filled: _isEditing,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Current maize crop'),
              RawAutocomplete<String>(
                textEditingController: _varietyController,
                focusNode: _varietyFocusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _varietySuggestions;
                  }
                  return _varietySuggestions.where((String option) {
                    return option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    );
                  });
                },
                onSelected: (String selection) {
                  _varietyController.text = selection;
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        key: const Key('field_variety_input'),
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Maize variety (if known)',
                          hintText:
                              'Type or choose variety (e.g. Pioneer, Dekalb)',
                          border: OutlineInputBorder(),
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
                            final String option = options.elementAt(index);
                            return ListTile(
                              title: Text(option),
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
              AccessibleChoiceField<String>(
                key: const Key('field_intended_use_choice'),
                label: 'How will this maize be used?',
                sheetTitle: 'Select intended use',
                value: _intendedUse,
                hintText: 'Select intended use (optional)',
                leadingIcon: Icons.inventory_2_outlined,
                options: const [
                  AccessibleChoiceOption(value: 'grain', label: 'Dry grain'),
                  AccessibleChoiceOption(
                    value: 'green_corn',
                    label: 'Green corn / fresh ears',
                  ),
                  AccessibleChoiceOption(value: 'silage', label: 'Silage'),
                  AccessibleChoiceOption(
                    value: 'seed',
                    label: 'Seed production',
                  ),
                  AccessibleChoiceOption(value: 'other', label: 'Other use'),
                ],
                onChanged: (value) => setState(() => _intendedUse = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plantingDateController,
                readOnly: true,
                onTap: _pickPlantingDate,
                decoration: const InputDecoration(
                  labelText: 'Planting date',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
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
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF8D6E00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isEditing
                  ? 'Update the field and crop details below. The originally confirmed location and barangay are permanent.'
                  : 'This registers the field offline using the farmer-reported area. After saving, add the field boundary to prepare its scouting map.',
              style: const TextStyle(color: Color(0xFF5D4A00), height: 1.35),
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
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
