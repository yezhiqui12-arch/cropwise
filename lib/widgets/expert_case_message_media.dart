import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../services/cloud/case_message_service.dart';
import '../services/cloud/expert_review_service.dart';
import '../theme/app_colors.dart';
import 'expert_review_presentation.dart'
    show evidencePlantLabel, openPhotoRequests;

Future<void> _zoomPhoto(
  BuildContext context, {
  String? url,
  File? file,
  required String caption,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: const Color(0xFF101A14),
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close photo',
              ),
              Expanded(
                child: Text(
                  caption,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 6,
              child: Center(
                child: file != null
                    ? Image.file(file)
                    : Image.network(
                        url!,
                        errorBuilder: (_, _, _) => const Text(
                          'Photo unavailable. Close and try again.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Pinch to zoom',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    ),
  ),
);

class ExpertMessagePhotos extends StatelessWidget {
  const ExpertMessagePhotos({
    super.key,
    required this.photos,
    required this.service,
  });
  final List<CaseMessageAttachment> photos;
  final CaseMessageService service;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final photo in photos)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: const Color(0xFFEFF5F0),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                final url = await service.photoUrl(photo.path, refresh: true);
                if (!context.mounted) return;
                if (url == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Photo unavailable. Check your connection and try again.',
                      ),
                    ),
                  );
                  return;
                }
                await _zoomPhoto(context, url: url, caption: photo.label);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (photo.url != null)
                    Image.network(
                      photo.url!,
                      height: 160,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const SizedBox(
                              height: 160,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 100,
                        child: Center(child: Text('Tap to reload photo')),
                      ),
                    )
                  else
                    const SizedBox(
                      height: 100,
                      child: Center(child: Text('Tap to load photo')),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      photo.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class ExpertCaseMessageComposer extends StatefulWidget {
  const ExpertCaseMessageComposer({
    super.key,
    required this.reviewCase,
    required this.owner,
    required this.service,
    required this.refresh,
  });
  final ExpertReviewCase reviewCase;
  final String owner;
  final CaseMessageService service;
  final Future<void> Function() refresh;
  @override
  State<ExpertCaseMessageComposer> createState() =>
      ExpertCaseMessageComposerState();
}

class ExpertCaseMessageComposerState extends State<ExpertCaseMessageComposer> {
  final _body = TextEditingController();
  CaseMessageDraft? _draft;
  bool _busy = false, _restoring = true;
  String? _error, _progress;
  bool get _editable =>
      !_restoring && !_busy && _draft != null && !_draft!.attempted;
  @override
  void initState() {
    super.initState();
    _body.addListener(_textChanged);
    unawaited(_restore());
  }

  @override
  void dispose() {
    _body.removeListener(_textChanged);
    _body.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final draft = await widget.service.loadDraft(
        widget.owner,
        widget.reviewCase.id,
      );
      final requests = openPhotoRequests(
        widget.reviewCase,
      ).where((m) => m.evidenceStatus != null).toList();
      if (draft.requestId == null &&
          draft.body.isEmpty &&
          draft.photos.isEmpty &&
          !draft.attempted &&
          requests.length == 1) {
        _linkRequest(draft, requests.single);
      }
      if (!mounted) return;
      _body.text = draft.body;
      setState(() {
        _draft = draft;
        _restoring = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _draft = CaseMessageDraft();
          _restoring = false;
          _error =
              'Could not restore your draft. Keep this screen open while replying.';
        });
      }
    }
  }

  void _textChanged() {
    if (!_editable) return;
    _draft!.body = _body.text;
    setState(() {});
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      await widget.service.saveDraft(
        widget.owner,
        widget.reviewCase.id,
        _draft!,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save the draft. Keep this screen open and retry.',
        );
      }
    }
  }

  Future<void> replyToRequest(
    ExpertMessage message, {
    bool choosePhotos = false,
  }) async {
    if (!_editable) return;
    if (_draft!.requestId == message.id) {
      if (choosePhotos) await _chooseSource();
      return;
    }
    if (message.evidenceStatus != null &&
        _draft!.photos.any(
          (photo) =>
              (photo.station != null &&
                  photo.station != message.requestedStation) ||
              (photo.plant != null && photo.plant != 1) ||
              (photo.blockRunId != null &&
                  photo.blockRunId != message.requestedBlockId),
        )) {
      setState(
        () => _error =
            'Some draft photos belong to another sampled plant. Remove them before replying to this request.',
      );
      return;
    }
    if (_draft!.body.isNotEmpty || _draft!.photos.isNotEmpty) {
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use this draft for the evidence request?'),
          content: const Text(
            'Your text and selected photos will be kept and linked to this request.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Link draft'),
            ),
          ],
        ),
      );
      if (use != true || !mounted) return;
    }
    setState(() {
      _linkRequest(_draft!, message);
    });
    await _persist();
    if (choosePhotos && mounted) await _chooseSource();
  }

  void _linkRequest(CaseMessageDraft draft, ExpertMessage message) {
    draft.requestId = message.id;
    draft.targetPlant = message.evidenceStatus != null
        ? message.requestedStation
        : null;
    draft.targetBlockId = message.requestedBlockId;
    draft.targetBlockSequence = message.requestedBlockSequence;
    draft.requestedViews = message.requestedViews;
    draft.samePlantConfirmed = false;
    if (draft.targetPlant != null) {
      for (final photo in draft.photos) {
        photo.station = draft.targetPlant;
        photo.plant = 1;
        photo.blockRunId = draft.targetBlockId;
      }
    }
  }

  Future<void> _chooseSource() async {
    if (!_editable) return;
    if (_draft!.requestId == null) {
      final requests = openPhotoRequests(widget.reviewCase);
      ExpertMessage? request;
      if (requests.length == 1) {
        request = requests.single;
      } else if (requests.isNotEmpty) {
        request = await showModalBottomSheet<ExpertMessage>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('Which photo request are you replying to?'),
                ),
                for (final message in requests)
                  ListTile(
                    leading: const Icon(Icons.add_a_photo_outlined),
                    title: Text(evidencePlantLabel(message)),
                    onTap: () => Navigator.pop(context, message),
                  ),
              ],
            ),
          ),
        );
        if (request == null || !mounted) return;
      }
      if (request != null) {
        await replyToRequest(request);
        if (!mounted || _draft!.requestId != request.id) return;
      }
    }
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Add evidence to this case',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Up to five photos. Replies to a plant request are linked to that block and plant automatically.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Use saved assessment photos'),
              onTap: () => Navigator.pop(context, 'assessment'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (source == 'assessment') {
        await _existingPhoto();
      } else {
        final picker = ImagePicker();
        final List<XFile> picked;
        if (source == 'camera') {
          final photo = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 88,
          );
          picked = photo == null ? [] : [photo];
        } else {
          picked = await picker.pickMultiImage(
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 88,
          );
        }
        if (!mounted) return;
        if (picked.length + _draft!.photos.length >
            CaseMessageService.maxPhotos) {
          throw StateError('Attach up to five photos per message.');
        }
        for (final photo in picked) {
          final staged = await widget.service.stagePhoto(
            widget.reviewCase.id,
            _draft!,
            photo.path,
            captureSource: source == 'camera' ? 'camera' : 'gallery',
            capturedAt: source == 'camera' ? DateTime.now().toUtc() : null,
          );
          _draft!.photos.add(staged);
          // A structured request already supplies the plant identity.
          if (_draft!.targetPlant == null) {
            await _editPhoto(staged, allowBusy: true);
          }
          await _persist();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _existingPhoto() async {
    final database = context.read<AppDatabase?>();
    if (database == null) {
      throw StateError('Saved assessment photos are unavailable.');
    }
    final photos =
        await (database.select(database.evidenceMedia)..where(
              (m) =>
                  m.assessmentId.equals(widget.reviewCase.assessmentId) &
                  m.deletedAt.isNull() &
                  m.storageState.equals(DatabaseCodes.evidenceStorageReady) &
                  m.isCanonicalEvidence.equals(true),
            ))
            .get();
    if (!mounted) return;
    final selected = await showModalBottomSheet<EvidenceMediaRecord>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 360,
          child: photos.isEmpty
              ? const Center(
                  child: Text(
                    'No saved photos are available for this assessment.',
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) => FutureBuilder<File>(
                    future: widget.service.files.resolve(
                      photos[index].localUri,
                    ),
                    builder: (context, snapshot) => InkWell(
                      onTap: () => Navigator.pop(context, photos[index]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: snapshot.data == null
                            ? const Center(child: CircularProgressIndicator())
                            : Image.file(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final file = await widget.service.files.resolve(selected.localUri);
    final station = selected.stationId == null
        ? null
        : await (database.select(
            database.stations,
          )..where((s) => s.id.equals(selected.stationId!))).getSingleOrNull();
    final plant = selected.plantObservationId == null
        ? null
        : await (database.select(database.plantObservations)
                ..where((p) => p.id.equals(selected.plantObservationId!)))
              .getSingleOrNull();
    if (_draft!.targetPlant != null &&
        station != null &&
        (station.stationNumber != _draft!.targetPlant ||
            station.assessmentBlockRunId != _draft!.targetBlockId ||
            (plant != null && plant.sequenceNumber != 1))) {
      throw StateError(
        'This saved photo belongs to a different sampled plant. Choose the requested plant or take a new photo.',
      );
    }
    final staged = await widget.service.stagePhoto(
      widget.reviewCase.id,
      _draft!,
      file.path,
      station: station?.stationNumber,
      plant: station == null ? null : plant?.sequenceNumber,
      blockRunId: station?.assessmentBlockRunId,
      captureSource: 'saved_assessment',
      capturedAt: selected.captureSource == 'gallery'
          ? null
          : selected.capturedAt,
    );
    _draft!.photos.add(staged);
    await _persist();
  }

  Future<({bool da, Map<String, int> blocks})> _photoPlan() async {
    final database = context.read<AppDatabase?>();
    if (database != null) {
      final assessment =
          await (database.select(database.assessments)
                ..where((a) => a.id.equals(widget.reviewCase.assessmentId)))
              .getSingleOrNull();
      if (assessment != null) {
        final runs =
            await (database.select(database.assessmentBlockRuns)..where(
                  (r) =>
                      r.assessmentId.equals(assessment.id) &
                      r.deletedAt.isNull(),
                ))
                .get();
        return (
          da: assessment.protocolVersion == 'wormwise-da-scattered-20-v1',
          blocks: {for (final run in runs) run.id: run.blockSequence},
        );
      }
    }
    return widget.service.photoPlan(widget.reviewCase.assessmentId);
  }

  Future<void> _editPhoto(
    CaseMessagePhoto photo, {
    bool allowBusy = false,
  }) async {
    if (!allowBusy && !_editable) return;
    final targeted = _draft!.targetPlant != null;
    final plan = targeted
        ? (da: true, blocks: <String, int>{})
        : await _photoPlan();
    if (!mounted) return;
    String? selectedBlock = plan.blocks.containsKey(photo.blockRunId)
        ? photo.blockRunId
        : plan.blocks.length == 1
        ? plan.blocks.keys.single
        : null;
    final caption = TextEditingController(text: photo.caption);
    final station = TextEditingController(
      text: photo.station?.toString() ?? '',
    );
    final plant = TextEditingController(text: photo.plant?.toString() ?? '');
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Photo details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: caption,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Caption (optional)',
                  ),
                ),
                if (!targeted && plan.da) ...[
                  if (plan.blocks.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: selectedBlock,
                      decoration: const InputDecoration(
                        labelText: 'Sampling block',
                      ),
                      items: [
                        for (final entry in plan.blocks.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text('Block ${entry.value}'),
                          ),
                      ],
                      onChanged: _draft!.targetPlant != null
                          ? null
                          : (value) => setDialog(() => selectedBlock = value),
                    ),
                  TextField(
                    controller: station,
                    readOnly: _draft!.targetPlant != null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sampled plant (1–20)',
                      helperText: 'Leave blank only for a general field photo.',
                    ),
                  ),
                ] else if (!targeted)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: station,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Station (optional)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: plant,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Plant (optional)',
                          ),
                        ),
                      ),
                    ],
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final s = int.tryParse(station.text),
                    p = plan.da
                        ? (station.text.trim().isEmpty ? null : 1)
                        : int.tryParse(plant.text);
                if (!targeted &&
                    plan.da &&
                    station.text.trim().isNotEmpty &&
                    (s == null ||
                        s < 1 ||
                        s > 20 ||
                        plan.blocks.isNotEmpty && selectedBlock == null)) {
                  setDialog(
                    () => error =
                        'Choose the sampling block and a plant from 1 to 20.',
                  );
                  return;
                }
                if (!targeted &&
                    ((station.text.isNotEmpty && (s == null || s <= 0)) ||
                        (plant.text.isNotEmpty &&
                            (p == null || p <= 0 || s == null)))) {
                  setDialog(
                    () => error =
                        'Use positive numbers. A plant needs a station.',
                  );
                  return;
                }
                photo.caption = caption.text.trim();
                photo.station = _draft!.targetPlant ?? s;
                photo.plant = _draft!.targetPlant != null ? 1 : p;
                photo.blockRunId = _draft!.targetPlant != null
                    ? _draft!.targetBlockId
                    : s == null
                    ? null
                    : selectedBlock;
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    caption.dispose();
    station.dispose();
    plant.dispose();
    if (saved == true && mounted) {
      setState(() {});
      await _persist();
    }
  }

  Future<void> _send() async {
    if (_draft == null || _busy || _restoring) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.send(
        owner: widget.owner,
        caseId: widget.reviewCase.id,
        draft: _draft!,
        progress: (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
      if (!mounted) return;
      _draft = CaseMessageDraft();
      _body.clear();
      // A refresh failure must not claim a successfully delivered reply failed.
      try {
        await widget.refresh();
      } catch (_) {
        if (mounted) {
          _error = 'Reply sent. Refresh the conversation to see it.';
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${error.toString().replaceFirst('Bad state: ', '')} Your draft is kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text(
          'A reply already delivered will remain in the conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.discard(widget.owner, widget.reviewCase.id, _draft!);
      if (!mounted) return;
      _draft = CaseMessageDraft();
      _body.clear();
      _error = null;
    } catch (error) {
      if (mounted) _error = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .48,
      ),
      child: SingleChildScrollView(
        child: Material(
          color: Colors.white,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.cardBorder)),
            ),
            child: _restoring
                ? const LinearProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_draft!.requestId != null)
                        Row(
                          children: [
                            const Icon(Icons.reply, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _draft!.targetPlant == null
                                    ? 'Replying to an evidence request'
                                    : 'Photos for Block ${_draft!.targetBlockSequence ?? 1} · Plant ${_draft!.targetPlant}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              onPressed: _editable
                                  ? () {
                                      setState(() {
                                        _draft!.requestId = null;
                                        _draft!.targetPlant = null;
                                        _draft!.targetBlockId = null;
                                        _draft!.targetBlockSequence = null;
                                        _draft!.requestedViews = [];
                                        _draft!.samePlantConfirmed = false;
                                      });
                                      unawaited(_persist());
                                    }
                                  : null,
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'Unlink request',
                            ),
                          ],
                        ),
                      if (_draft!.targetPlant != null &&
                          _draft!.photos.isNotEmpty) ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'These photos show the requested plant.',
                          ),
                          value: _draft!.samePlantConfirmed,
                          onChanged: _editable
                              ? (value) {
                                  setState(
                                    () => _draft!.samePlantConfirmed =
                                        value ?? false,
                                  );
                                  unawaited(_persist());
                                }
                              : null,
                        ),
                      ],
                      if (_draft!.photos.isNotEmpty)
                        SizedBox(
                          height: 118,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _draft!.photos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final photo = _draft!.photos[i];
                              return SizedBox(
                                width: 110,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: FutureBuilder<File>(
                                              future: widget.service.files
                                                  .resolve(photo.thumbnailUri),
                                              builder: (context, snapshot) => InkWell(
                                                onTap: () async {
                                                  final file = await widget
                                                      .service
                                                      .files
                                                      .resolve(photo.localUri);
                                                  if (context.mounted) {
                                                    await _zoomPhoto(
                                                      context,
                                                      file: file,
                                                      caption:
                                                          photo.caption.isEmpty
                                                          ? 'Selected evidence'
                                                          : photo.caption,
                                                    );
                                                  }
                                                },
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: snapshot.data == null
                                                      ? const SizedBox()
                                                      : Image.file(
                                                          snapshot.data!,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                _,
                                                                _,
                                                                _,
                                                              ) => const Icon(
                                                                Icons
                                                                    .broken_image_outlined,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: IconButton.filledTonal(
                                                padding: EdgeInsets.zero,
                                                onPressed: _editable
                                                    ? () async {
                                                        setState(
                                                          () => _draft!.photos
                                                              .remove(photo),
                                                        );
                                                        await _persist();
                                                        await widget.service
                                                            .removeLocalPhoto(
                                                              widget
                                                                  .reviewCase
                                                                  .id,
                                                              _draft!,
                                                              photo,
                                                            );
                                                      }
                                                    : null,
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 16,
                                                ),
                                                tooltip: 'Remove photo',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: 30,
                                      child: TextButton(
                                        onPressed: _editable
                                            ? () => _editPhoto(photo)
                                            : null,
                                        child: Text(
                                          photo.caption.isEmpty
                                              ? 'Add details'
                                              : photo.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed:
                                _editable &&
                                    _draft!.photos.length <
                                        CaseMessageService.maxPhotos
                                ? _chooseSource
                                : null,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            color: AppColors.primary,
                            tooltip: 'Attach evidence photos',
                          ),
                          Expanded(
                            child: TextField(
                              controller: _body,
                              enabled: _editable,
                              minLines: 1,
                              maxLines: 3,
                              maxLength: 8000,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: _draft!.targetPlant != null
                                    ? 'Note (optional)'
                                    : 'Message…',
                                hintMaxLines: 1,
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFFF4F7F4),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed:
                                !_busy &&
                                    !_restoring &&
                                    (_draft!.attempted ||
                                        (_draft!.body.trim().isNotEmpty ||
                                                _draft!.photos.isNotEmpty) &&
                                            (_draft!.targetPlant == null ||
                                                _draft!.photos.isEmpty ||
                                                _draft!.samePlantConfirmed))
                                ? _send
                                : null,
                            tooltip: _draft!.attempted
                                ? 'Retry reply'
                                : 'Send reply',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _draft!.attempted
                                        ? Icons.refresh
                                        : Icons.send_rounded,
                                  ),
                          ),
                        ],
                      ),
                      if (_progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _progress!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF9A3412),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _draft!.attempted
                                  ? 'Retry to confirm delivery. Draft kept on this phone.'
                                  : 'Up to 5 photos · Your expert will review them.',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (_draft!.photos.isNotEmpty ||
                              _draft!.body.isNotEmpty ||
                              _draft!.attempted)
                            TextButton(
                              onPressed: !_busy ? _discard : null,
                              child: const Text(
                                'Discard',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}
