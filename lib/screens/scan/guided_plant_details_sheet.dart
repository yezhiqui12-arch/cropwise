import 'dart:io';
import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../models/guided_plant_details.dart';
import '../../theme/app_colors.dart';
import '../station1/evidence_photo_viewer.dart';
import '../station1/plant_analysis_inspector_step.dart';
import '../../models/da_monitoring.dart';
import 'da_monitoring_controls.dart';
import '../../data/repositories/plant_action_repository.dart';
import 'plant_action_guidance_panel.dart';
import 'scouting_ui.dart';

class GuidedPlantDetailsSheet extends StatefulWidget {
  const GuidedPlantDetailsSheet({
    super.key,
    required this.number,
    required this.loadDetails,
    required this.resolveFile,
    required this.blockNumber,
    required this.growthStage,
    this.onSaveCorrection,
    this.actionRepository,
    this.onSaveNotes,
  });
  final int number, blockNumber;
  final String growthStage;
  final Future<GuidedPlantDetails> Function() loadDetails;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(Map<String, bool?> values)? onSaveCorrection;
  final PlantActionRepository? actionRepository;
  final Future<void> Function(String? notes)? onSaveNotes;
  @override
  State<GuidedPlantDetailsSheet> createState() =>
      _GuidedPlantDetailsSheetState();
}

class _GuidedPlantDetailsSheetState extends State<GuidedPlantDetailsSheet> {
  late Future<GuidedPlantDetails> _details;
  Map<String, bool?>? _savedCorrections;
  @override
  void initState() {
    super.initState();
    // Opening details may refresh the active plant's model preview. Defer that
    // callback until this frame finishes so provider notifications cannot fire
    // while the modal is building.
    _details = Future(widget.loadDetails);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Plant ${widget.number}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      'Block ${widget.blockNumber}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close plant details',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<GuidedPlantDetails>(
            future: _details,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (state.hasError || !state.hasData)
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppText('Plant details could not be loaded.'),
                      TextButton(
                        onPressed: () {
                          final retry = widget.loadDetails();
                          setState(() {
                            _details = retry;
                          });
                        },
                        child: const AppText('Retry'),
                      ),
                    ],
                  ),
                );
              final details = state.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        if (widget.onSaveNotes != null && details.plant != null)
                          TextButton.icon(
                            key: const Key('guided_details_notes'),
                            icon: const Icon(Icons.notes_outlined, size: 18),
                            label: const AppText('Field notes'),
                            onPressed: () => _editNotes(details),
                          ),
                        AppText(
                          '${details.samplingStatus} · ${details.photos.length} ${details.photos.length == 1 ? 'photo' : 'photos'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        if (widget.onSaveCorrection != null &&
                            details.photos.isNotEmpty)
                          TextButton.icon(
                            key: const Key('da_open_correction'),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const AppText(
                              'Correct observations',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final record = details.monitoring?.plant(
                                details.snapshot.prepared.run.id,
                                widget.number,
                              );
                              final saved =
                                  record != null &&
                                      record['signature'] ==
                                          daPhotoSignature(details.photos)
                                  ? record['overrides']
                                  : null;
                              final initial =
                                  _savedCorrections ??
                                  daObservationOverrides(saved);
                              await showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                backgroundColor: AppColors.background,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(26),
                                  ),
                                ),
                                builder: (_) => FractionallySizedBox(
                                  heightFactor: .94,
                                  child: DaPlantCorrectionPanel(
                                    onClose: () => Navigator.pop(context),
                                    finding: DaPlantFinding.fromModel(
                                      details.diagnosis,
                                    ),
                                    initial: initial,
                                    initiallyExpanded: true,
                                    onSave: (values) async {
                                      await widget.onSaveCorrection!(values);
                                      _savedCorrections = values;
                                    },
                                  ),
                                ),
                              );
                              if (mounted && _savedCorrections != null) {
                                setState(() {
                                  _details = widget.loadDetails();
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  if (details.photos.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: AppText('No photos yet.'),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: PlantAnalysisInspectorStep(
                        position: widget.number,
                        stationNumber: widget.number,
                        blockNumber: widget.blockNumber,
                        growthStage: widget.growthStage,
                        cvDiagnosis: details.diagnosis,
                        plantRecord: details.plant,
                        initialNotes: details.plant?.evaluatorNotes,
                        evidence: details.evidence,
                        screeningOnly: true,
                        isDaGuidedScouting: true,
                        showContextHeader: false,
                        actionGuidance: widget.actionRepository == null
                            ? null
                            : PlantActionGuidancePanel(
                                repository: widget.actionRepository!,
                                assessmentId: details.photos.first.assessmentId,
                                blockRunId: details.snapshot.prepared.run.id,
                                number: widget.number,
                                revision:
                                    '${daPhotoSignature(details.photos)}:$_savedCorrections',
                                loadDetails: () async => details,
                                resolveFile: widget.resolveFile,
                              ),
                        resolveEvidenceFile: widget.resolveFile,
                        isSaving: false,
                        onSaveDiagnosis: ({required status, notes}) async {},
                        onCancel: () => Navigator.pop(context),
                        onInspectEvidence: (media) async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EvidencePhotoViewer(
                                media: media,
                                scopeLabel: 'Plant ${widget.number}',
                                resolveFile: widget.resolveFile,
                                cvDiagnosis: details.diagnosis,
                                scoutingStyle: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> _editNotes(GuidedPlantDetails details) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (_) => _PlantNotesEditor(
        initialNotes: details.plant?.evaluatorNotes,
        onSave: widget.onSaveNotes!,
      ),
    );
    if (mounted && saved == true) {
      setState(() {
        _details = Future(widget.loadDetails);
      });
    }
  }
}

class _PlantNotesEditor extends StatefulWidget {
  const _PlantNotesEditor({this.initialNotes, required this.onSave});
  final String? initialNotes;
  final Future<void> Function(String? notes) onSave;
  @override
  State<_PlantNotesEditor> createState() => _PlantNotesEditorState();
}

class _PlantNotesEditorState extends State<_PlantNotesEditor> {
  late final _controller = TextEditingController(
    text: widget.initialNotes ?? '',
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppText(
            'Field notes',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const AppText(
            'Optional',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ScoutingCard(
            child: TextField(
              key: const Key('guided_details_notes_input'),
              controller: _controller,
              maxLines: 4,
              enabled: !_saving,
              decoration: const InputDecoration(
                hintText: 'Add a note about this plant',
                border: InputBorder.none,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(_error!),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('guided_details_save_notes'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
            onPressed: _saving
                ? null
                : () async {
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    try {
                      await widget.onSave(_controller.text.trim());
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (_) {
                      if (mounted)
                        setState(() {
                          _error = 'Could not save notes. Try again.';
                          _saving = false;
                        });
                    }
                  },
            child: AppText(_saving ? 'Saving…' : 'Save notes'),
          ),
        ],
      ),
    ),
  );
}
