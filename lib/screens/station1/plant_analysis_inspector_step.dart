import 'dart:io';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import 'field_workflow_components.dart';
import 'model_detection_image.dart';
import '../../models/da_monitoring.dart';
import '../../models/automatic_screening.dart';
import '../scan/scouting_ui.dart';

class PlantAnalysisInspectorStep extends StatefulWidget {
  const PlantAnalysisInspectorStep({
    super.key,
    required this.position,
    required this.stationNumber,
    required this.blockNumber,
    this.growthStage = 'v3_v6',
    this.cvDiagnosis,
    this.initialStatus,
    this.plantRecord,
    this.initialNotes,
    this.screeningOnly = false,
    this.isDaGuidedScouting = false,
    this.onSaveNotes,
    this.showContextHeader = true,
    this.actionGuidance,
    this.evidence,
    this.resolveEvidenceFile,
    this.onInspectEvidence,
    this.onRetakeEvidence,
    this.onCaptureEvidence,
    required this.isSaving,
    required this.onSaveDiagnosis,
    required this.onCancel,
  });

  final int position;
  final int stationNumber;
  final int blockNumber;
  final String growthStage;
  final PlantDiagnosisResult? cvDiagnosis;
  final String? initialStatus;
  final PlantObservationRecord? plantRecord;
  final String? initialNotes;
  final bool screeningOnly;
  final bool isDaGuidedScouting;
  final Future<void> Function(String? notes)? onSaveNotes;
  final bool showContextHeader;
  final Widget? actionGuidance;
  final EvidenceCaptureBundle? evidence;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Future<void> Function(EvidenceMediaRecord media)? onInspectEvidence;
  final Future<void> Function(EvidenceMediaRecord media)? onRetakeEvidence;
  final Future<void> Function(String viewType)? onCaptureEvidence;
  final bool isSaving;
  final Future<void> Function({required String status, String? notes})
  onSaveDiagnosis;
  final VoidCallback onCancel;

  @override
  State<PlantAnalysisInspectorStep> createState() =>
      _PlantAnalysisInspectorStepState();
}

class _PlantAnalysisInspectorStepState
    extends State<PlantAnalysisInspectorStep> {
  String? _selectedStatus;
  late final TextEditingController _notesController;
  int _photoIndex = 0;

  @override
  void initState() {
    super.initState();
    final suggested = widget.cvDiagnosis?.suggestedPlantStatus;
    _selectedStatus = widget.initialStatus ?? suggested;
    _notesController = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = widget.cvDiagnosis;
    final isInfested =
        _selectedStatus == DatabaseCodes.plantCurrentPositive ||
        _selectedStatus == DatabaseCodes.reproductiveInfested ||
        _selectedStatus == DatabaseCodes.earExternalActive;
    final isOldDamage = _selectedStatus == DatabaseCodes.plantOldDamageOnly;
    final isNonFaw = _selectedStatus == DatabaseCodes.plantPossibleNonFaw;
    final isNotAssessable = _selectedStatus == DatabaseCodes.plantNotAssessable;

    final mediaList =
        widget.evidence?.media
            .where(
              (media) =>
                  media.deletedAt == null &&
                  (media.storageState == DatabaseCodes.evidenceStorageReady ||
                      media.storageState ==
                          DatabaseCodes.evidenceStorageStaged),
            )
            .toList() ??
        <EvidenceMediaRecord>[];
    final locatedPhotos =
        mediaList
            .where(
              (media) =>
                  media.deletedAt == null &&
                  media.storageState == DatabaseCodes.evidenceStorageReady &&
                  media.locationSource == 'phone_gps' &&
                  media.latitude != null &&
                  media.longitude != null &&
                  media.locationCapturedAt != null,
            )
            .toList()
          ..sort(
            (a, b) => a.locationCapturedAt!.compareTo(b.locationCapturedAt!),
          );
    final photoFix = locatedPhotos.isEmpty ? null : locatedPhotos.first;
    final latitude = photoFix?.latitude ?? widget.plantRecord?.latitude;
    final longitude = photoFix?.longitude ?? widget.plantRecord?.longitude;
    final accuracy = photoFix?.gpsAccuracyM ?? widget.plantRecord?.gpsAccuracyM;

    if (widget.isDaGuidedScouting && widget.screeningOnly) {
      return _guidedInspection(mediaList, latitude, longitude, accuracy);
    }

    return FieldWorkflowShell(
      scrollKey: const Key('plant_analysis_inspector'),
      bottomBar: widget.screeningOnly && widget.onSaveNotes != null
          ? StickyWorkflowActionBar(
              message: 'Optional field notes',
              actionLabel: 'Save notes and return',
              actionKey: const Key('save_da_plant_notes'),
              isSaving: widget.isSaving,
              onPressed: () => widget.onSaveNotes!(_notesController.text),
            )
          : widget.screeningOnly
          ? const SizedBox.shrink()
          : StickyWorkflowActionBar(
              message:
                  'Your field confirmation is saved as the final observation.',
              actionLabel: 'Save and return to review',
              actionKey: const Key('save_plant_confirmation'),
              isSaving: widget.isSaving,

              onPressed: widget.screeningOnly
                  ? widget.onCancel
                  : _selectedStatus == null
                  ? null
                  : () => widget.onSaveDiagnosis(
                      status: _selectedStatus!,
                      notes: _notesController.text.trim().isEmpty
                          ? null
                          : _notesController.text.trim(),
                    ),
            ),
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_on_outlined),
          title: AppText(
            photoFix?.captureSource == 'gallery'
                ? 'Location at upload'
                : 'Plant location',
          ),
          subtitle: Text(
            latitude != null && longitude != null
                ? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)} · ±${accuracy?.toStringAsFixed(0) ?? "?"} m'
                : 'Not recorded',
          ),
        ),

        if (widget.showContextHeader && widget.isDaGuidedScouting)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppText(
              'Plant ${widget.position} · Saved evidence',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          )
        else if (widget.showContextHeader)
          WorkflowContextHeader(
            key: const Key('manual_confirmation_header'),
            stageLabel: growthStageLabel(widget.growthStage),
            blockNumber: widget.blockNumber,
            stationNumber: widget.stationNumber,
            title: widget.screeningOnly
                ? 'Plant ${widget.position}'
                : '${const {'ve', 'v1', 'v2'}.contains(widget.growthStage) ? 'Confirm Seedling' : 'Confirm Plant'} ${widget.position}',
            subtitle: widget.screeningOnly
                ? 'Saved plant images'
                : 'Inspect the photos and confirm what you observed in the field.',
            completedCount: mediaList.isEmpty ? 0 : 1,
            totalCount: 1,
            attentionCount: mediaList.isEmpty ? 1 : 0,
          ),
        if (widget.actionGuidance != null) widget.actionGuidance!,
        const SizedBox(height: AppSpacing.sm),
        WorkflowFormSection(
          title: '1 · Evidence',
          icon: Icons.photo_library_outlined,
          subtitle: mediaList.isEmpty
              ? 'Photo evidence is missing'
              : '${mediaList.length} ${mediaList.length == 1 ? 'photo' : 'photos'} available',
          completed: mediaList.isNotEmpty,
          children: [_buildEvidenceGallery(context, mediaList)],
        ),
        if (!widget.screeningOnly || widget.showContextHeader)
          WorkflowFormSection(
            title: '2 · Model preview',
            icon: Icons.auto_awesome_outlined,
            subtitle: diagnosis == null
                ? widget.initialStatus == null
                      ? 'Older model details were not saved; confirm from the photo'
                      : 'Saved field observation available; older model details were not saved'
                : 'Compare this suggestion with the plant',
            completed: diagnosis != null,
            children: [_buildAiFindingsCard(context, diagnosis)],
          ),
        if (!widget.screeningOnly)
          WorkflowFormSection(
            title: '3 · Field confirmation',
            icon: Icons.fact_check_outlined,
            subtitle: 'Your observation controls the saved status',
            children: [
              _buildCorrectionSelector(
                context,
                isInfested: isInfested,
                isOldDamage: isOldDamage,
                isNonFaw: isNonFaw,
                isNotAssessable: isNotAssessable,
              ),
            ],
          ),
        if (widget.screeningOnly &&
            widget.onSaveNotes == null &&
            _notesController.text.trim().isNotEmpty)
          WorkflowFormSection(
            title: 'Field notes',
            icon: Icons.notes_outlined,
            children: [Text(_notesController.text)],
          ),
        if (!widget.screeningOnly || widget.onSaveNotes != null)
          WorkflowFormSection(
            title: widget.isDaGuidedScouting ? '3 · Field notes' : '4 · Notes',
            icon: Icons.notes_outlined,
            subtitle: 'Optional context for later review',
            initiallyExpanded: _notesController.text.isNotEmpty,
            completed: _notesController.text.isNotEmpty,
            children: [
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: AppWords.of(
                    context,
                  ).translate('Evaluator notes (optional)'),
                  hintText: AppWords.of(context).translate(
                    widget.isDaGuidedScouting
                        ? 'Record natural enemies and their counts, field conditions, or uncertainty…'
                        : 'Record conditions, uncertainty, or another cause…',
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
      ],
    );
  }

  Widget _guidedInspection(
    List<EvidenceMediaRecord> photos,
    double? latitude,
    double? longitude,
    double? accuracy,
  ) {
    final model = widget.cvDiagnosis;
    final signs = DaPlantFinding.fromModel(model).values;
    final index = photos.isEmpty ? 0 : _photoIndex.clamp(0, photos.length - 1);
    final photo = photos.isEmpty ? null : photos[index];
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('plant_analysis_inspector'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (widget.showContextHeader)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppText(
                    'Plant ${widget.position}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (photo != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        _viewLabel(photo.viewType),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ScoutingTag(
                      '${index + 1} / ${photos.length}',
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1.15,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.resolveEvidenceFile != null)
                          FutureBuilder<File>(
                            future: widget.resolveEvidenceFile!(photo.localUri),
                            builder: (context, state) {
                              if (state.hasData && state.data!.existsSync())
                                return ColoredBox(
                                  color: const Color(0xFF182018),
                                  child: ModelDetectionImage(
                                    file: state.data!,
                                    fit: BoxFit.contain,
                                    boxes: ModelDetectionImage.boxesForFile(
                                      model,
                                      state.data!,
                                    ),
                                  ),
                                );
                              return Container(
                                color: const Color(0xFFE7ECE4),
                                child: Center(
                                  child:
                                      state.connectionState !=
                                          ConnectionState.done
                                      ? const CircularProgressIndicator()
                                      : const Icon(
                                          Icons.image_outlined,
                                          size: 44,
                                          color: Colors.black38,
                                        ),
                                ),
                              );
                            },
                          )
                        else
                          Container(color: const Color(0xFFE7ECE4)),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const Key('guided_inspect_photo'),
                            onTap: widget.onInspectEvidence == null
                                ? null
                                : () => widget.onInspectEvidence!(photo),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.open_in_full,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (photos.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          ChoiceChip(
                            key: Key('guided_photo_$i'),
                            showCheckmark: false,
                            selected: i == index,
                            onSelected: (_) => setState(() => _photoIndex = i),
                            label: AppText('Photo ${i + 1}'),
                          ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    if (photos.length < 3 && widget.onCaptureEvidence != null)
                      TextButton.icon(
                        onPressed: () => widget.onCaptureEvidence!(
                          DatabaseCodes.evidenceViewCloseUp,
                        ),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const AppText('Add close-up'),
                      ),
                    if (widget.onRetakeEvidence != null)
                      TextButton.icon(
                        onPressed: () => widget.onRetakeEvidence!(photo),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const AppText('Retake photo'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else
                const ScoutingCard(child: AppText('No photos yet.')),
              ScoutingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: AppText(
                            'Model results',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppText(
                          model == null
                              ? 'Not screened'
                              : AutomaticScreening(model).label,
                          key: const Key('plant_details_screening_status'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (model?.classificationLabel != null)
                          ScoutingTag(
                            '${(model!.confidenceScore * 100).round()}% confidence',
                            color: const Color(0xFF687166),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    for (final sign in daSignLabels.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: AppText(
                                sign.value,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            ScoutingTag(
                              signs[sign.key] == null
                                  ? 'Not assessed'
                                  : signs[sign.key] == true
                                  ? 'Detected'
                                  : 'Not detected',
                              color: signs[sign.key] == true
                                  ? const Color(0xFF986023)
                                  : signs[sign.key] == false
                                  ? AppColors.primary
                                  : const Color(0xFF687166),
                            ),
                          ],
                        ),
                      ),
                    if (model?.classifierStage == 'overlay_complete' ||
                        model?.detectionBoxes.any((b) => b.classId == 1) ==
                            true)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Expanded(
                              child: AppText(
                                'Frass',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            ScoutingTag(
                              model!.detectionBoxes.any((b) => b.classId == 1)
                                  ? 'Detected'
                                  : 'Not detected',
                              color:
                                  model.detectionBoxes.any(
                                    (b) => b.classId == 1,
                                  )
                                  ? const Color(0xFF986023)
                                  : AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.actionGuidance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: widget.actionGuidance!,
                ),
              const SizedBox(height: 16),
              ScoutingCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const AppText(
                    'Capture location',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  leading: const Icon(Icons.location_on_outlined, size: 20),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: AppText(
                        latitude == null || longitude == null
                            ? 'Not recorded'
                            : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)} · ±${accuracy?.toStringAsFixed(0) ?? '?'} m',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onSaveNotes != null ||
                  _notesController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                ScoutingCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'Field notes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (widget.onSaveNotes != null)
                        TextField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Add a note (optional)',
                          ),
                        )
                      else
                        AppText(_notesController.text),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.onSaveNotes != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save_da_plant_notes'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: widget.isSaving
                    ? null
                    : () => widget.onSaveNotes!(_notesController.text),
                child: const AppText('Save notes'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEvidenceGallery(
    BuildContext context,
    List<EvidenceMediaRecord> mediaList,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            AppText(
              'Captured photos',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (mediaList.length < 3 && widget.onCaptureEvidence != null)
              TextButton.icon(
                onPressed: () => widget.onCaptureEvidence!(
                  DatabaseCodes.evidenceViewCloseUp,
                ),
                icon: const Icon(Icons.add_a_photo, size: 16),
                label: const AppText(
                  'Add Close-up',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (mediaList.isEmpty)
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(
              child: AppText(
                'No photos captured yet',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
        else
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: mediaList.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final media = mediaList[index];
                return _buildPhotoCard(media);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoCard(EvidenceMediaRecord media) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.resolveEvidenceFile != null)
            FutureBuilder<File>(
              future: widget.resolveEvidenceFile!(media.localUri),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.existsSync()) {
                  return ModelDetectionImage(
                    file: snapshot.data!,
                    boxes: ModelDetectionImage.boxesForFile(
                      widget.cvDiagnosis,
                      snapshot.data!,
                    ),
                  );
                }
                return Container(
                  color: Colors.black12,
                  child: const Center(
                    child: Icon(Icons.image_outlined, color: Colors.black45),
                  ),
                );
              },
            )
          else
            Container(color: Colors.black12),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: Colors.black87,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _viewLabel(media.viewType),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onInspectEvidence != null)
                    InkWell(
                      onTap: () => widget.onInspectEvidence!(media),
                      child: const Icon(
                        Icons.fullscreen,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  if (widget.onRetakeEvidence != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => widget.onRetakeEvidence!(media),
                      child: const Icon(
                        Icons.refresh,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiFindingsCard(
    BuildContext context,
    PlantDiagnosisResult? diagnosis,
  ) {
    if (diagnosis == null) {
      return const _ModelUnavailableNotice();
    }
    if (widget.screeningOnly)
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          diagnosis.classificationLabel == null
              ? 'Not assessed'
              : diagnosis.classificationLabel == 'FAW damage'
              ? 'Damage detected'
              : 'No damage detected',
        ),
        subtitle: diagnosis.classificationLabel == null
            ? null
            : AppText(
                '${(diagnosis.confidenceScore * 100).toStringAsFixed(0)}% confidence',
              ),
      );
    final isPos = diagnosis.isInfested;
    final themeColor = isPos
        ? const Color(0xFFB3261E)
        : const Color(0xFF176B3A);
    final bgColor = isPos ? const Color(0xFFFDE8E8) : const Color(0xFFEAF6EE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPos ? Icons.bug_report : Icons.check_circle,
                color: themeColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPos
                      ? 'Model preview: current FAW-consistent evidence'
                      : 'Model preview: no current signs detected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                ),
                child: AppText(
                  '${(diagnosis.confidenceScore * 100).toInt()}% match',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (isPos) ...[
            Row(
              children: [
                const AppText(
                  'Damage Severity: ',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                AppText(
                  'DA-BAFS score requires evaluator assessment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const AppText(
            'Visual Signs Detected by AI:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (diagnosis.detectedSigns.isEmpty)
            const AppText(
              '• No feeding injury, frass, or larvae detected',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sign in diagnosis.detectedSigns)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: 13,
                          color: isPos
                              ? const Color(0xFFB3261E)
                              : const Color(0xFF176B3A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          sign.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (diagnosis.detectionBoxes.any(
            (box) => box.classId >= 4 && box.classId <= 6,
          )) ...[
            const SizedBox(height: 10),
            const AppText(
              'Pest identification suggestions:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final box in diagnosis.detectionBoxes.where(
              (box) => box.classId >= 4 && box.classId <= 6,
            ))
              AppText(
                '${box.label} (${(box.confidence * 100).round()}% match) — confirm visually',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
          ] else if (diagnosis.detectionBoxes.any(
            (box) => box.classId == 2,
          )) ...[
            const SizedBox(height: 10),
            const AppText(
              'Larva detected; no confident pest identification. Confirm visually.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCorrectionSelector(
    BuildContext context, {
    required bool isInfested,
    required bool isOldDamage,
    required bool isNonFaw,
    required bool isNotAssessable,
  }) {
    final isClean = _selectedStatus == DatabaseCodes.plantNegative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText(
          'Confirm or correct the observation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const AppText(
          'Select what you can support from the plant and its evidence.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ConfirmationOptionChip(
              key: const Key('confirmation_option_negative'),
              label: 'No current signs',
              icon: isClean ? Icons.check_circle : Icons.check_circle_outline,
              selected: isClean,
              activeColor: const Color(0xFF176B3A),
              activeBgColor: const Color(0xFFEAF6EE),
              onTap: () => setState(() {
                _selectedStatus = DatabaseCodes.plantNegative;
              }),
            ),
            _ConfirmationOptionChip(
              key: const Key('confirmation_option_infested'),
              label: 'Current FAW-consistent evidence',
              icon: Icons.bug_report,
              selected: isInfested,
              activeColor: AppColors.severeSeverityRing,
              activeBgColor: AppColors.severeSeverityBg,
              onTap: () => setState(() {
                _selectedStatus = DatabaseCodes.plantCurrentPositive;
              }),
            ),
            _ConfirmationOptionChip(
              key: const Key('confirmation_option_old_damage'),
              label: 'Old damage only',
              icon: Icons.history_toggle_off,
              selected: isOldDamage,
              activeColor: const Color(0xFFB57400),
              activeBgColor: const Color(0xFFFFF3D6),
              onTap: () => setState(() {
                _selectedStatus = DatabaseCodes.plantOldDamageOnly;
              }),
            ),
            _ConfirmationOptionChip(
              key: const Key('confirmation_option_not_assessable'),
              label: 'Not assessable',
              icon: Icons.block_outlined,
              selected: isNotAssessable,
              activeColor: const Color(0xFF4E585C),
              activeBgColor: const Color(0xFFE8EAEB),
              onTap: () => setState(() {
                _selectedStatus = DatabaseCodes.plantNotAssessable;
              }),
            ),
          ],
        ),
      ],
    );
  }

  String _viewLabel(String? viewType) {
    return switch (viewType) {
      DatabaseCodes.evidenceViewWhorlOverview => 'Overview',
      DatabaseCodes.evidenceViewWholeSeedling => 'Seedling',
      DatabaseCodes.evidenceViewCloseUp => 'Close-up',
      DatabaseCodes.evidenceViewDiagnosticDetail => 'Detail',
      _ => 'Photo',
    };
  }
}

class _ConfirmationOptionChip extends StatelessWidget {
  const _ConfirmationOptionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.activeBgColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final Color activeBgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? activeBgColor : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? activeColor : AppColors.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? activeColor : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? activeColor : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelUnavailableNotice extends StatelessWidget {
  const _ModelUnavailableNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.model_training_outlined, color: AppColors.textSecondary),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppText(
            'The earlier model preview was not stored. Review the saved photo and confirm the observation; the model will not run again.',
          ),
        ),
      ],
    ),
  );
}
