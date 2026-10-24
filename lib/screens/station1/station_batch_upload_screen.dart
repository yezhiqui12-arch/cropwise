import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local/database_codes.dart';
import '../../localization/app_text.dart';

/// One evidence slot kind shown on every plant card.
class BatchPhotoView {
  const BatchPhotoView({
    required this.viewType,
    required this.label,
    required this.icon,
    this.required = false,
  });

  final String viewType;
  final String label;
  final IconData icon;
  final bool required;
}

/// Imports up to three gallery photos (overview, close-up, detail) for each
/// missing plant in a station. Nothing is saved until the evaluator confirms.
class StationBatchUploadScreen extends StatefulWidget {
  const StationBatchUploadScreen({
    super.key,
    required this.stationNumber,
    required this.plantPositions,
    required this.onSavePhoto,
    required this.onAnalyzePlant,
    this.primaryViewType = DatabaseCodes.evidenceViewWhorlOverview,
    this.pickPhotos,
  });

  final int stationNumber;
  final List<int> plantPositions;
  final String primaryViewType;
  final Future<void> Function(int plantPosition, String viewType, String path)
  onSavePhoto;
  final Future<void> Function(int plantPosition) onAnalyzePlant;
  final Future<List<XFile>> Function(int limit)? pickPhotos;

  @override
  State<StationBatchUploadScreen> createState() =>
      _StationBatchUploadScreenState();
}

class _StationBatchUploadScreenState extends State<StationBatchUploadScreen> {
  static const _green = Color(0xFF176B3A);

  late final List<BatchPhotoView> _views = [
    BatchPhotoView(
      viewType: widget.primaryViewType,
      label: 'Overview',
      icon: Icons.local_florist_outlined,
      required: true,
    ),
    const BatchPhotoView(
      viewType: DatabaseCodes.evidenceViewCloseUp,
      label: 'Close-up',
      icon: Icons.zoom_in,
    ),
    const BatchPhotoView(
      viewType: DatabaseCodes.evidenceViewDiagnosticDetail,
      label: 'Detail',
      icon: Icons.biotech_outlined,
    ),
  ];

  /// plant position -> view index -> photo
  final Map<int, Map<int, XFile>> _photos = {};
  final Set<String> _saved = {};
  bool _working = false;
  bool _complete = false;
  int _done = 0;
  String? _error;

  int get _total => _photos.values.fold(0, (sum, slots) => sum + slots.length);
  int get _overviewCount =>
      widget.plantPositions.where((p) => _photos[p]?[0] != null).length;
  bool get _ready =>
      _overviewCount == widget.plantPositions.length && !_working;
  bool get _locked => _working || _saved.isNotEmpty;

  Future<List<XFile>> _pick(int limit) async {
    if (widget.pickPhotos != null) return widget.pickPhotos!(limit);
    const quality = (maxWidth: 2048.0, maxHeight: 2048.0, imageQuality: 85);
    if (limit == 1) {
      final one = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: quality.maxWidth,
        maxHeight: quality.maxHeight,
        imageQuality: quality.imageQuality,
      );
      return one == null ? const [] : [one];
    }
    return ImagePicker().pickMultiImage(
      limit: limit,
      requestFullMetadata: false,
      maxWidth: quality.maxWidth,
      maxHeight: quality.maxHeight,
      imageQuality: quality.imageQuality,
    );
  }

  /// Fills empty overview slots in plant order.
  Future<void> _fillOverviews() async {
    final empty = widget.plantPositions
        .where((p) => _photos[p]?[0] == null)
        .toList();
    if (empty.isEmpty || _locked) return;
    try {
      final picked = await _pick(empty.length);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        for (var i = 0; i < picked.length && i < empty.length; i++) {
          (_photos[empty[i]] ??= {})[0] = picked[i];
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Gallery failed: $error');
    }
  }

  Future<void> _pickSlot(int position, int viewIndex) async {
    if (_locked) return;
    try {
      final picked = await _pick(1);
      if (!mounted || picked.isEmpty) return;
      setState(() => (_photos[position] ??= {})[viewIndex] = picked.first);
    } catch (error) {
      if (mounted) setState(() => _error = 'Gallery failed: $error');
    }
  }

  Future<void> _slotActions(int position, int viewIndex) async {
    final photo = _photos[position]?[viewIndex];
    if (photo == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const AppText('View'),
              onTap: () => Navigator.pop(sheet, 'view'),
            ),
            if (!_locked) ...[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const AppText('Replace'),
                onTap: () => Navigator.pop(sheet, 'replace'),
              ),
              if (widget.plantPositions.length > 1)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const AppText('Move to another plant'),
                  onTap: () => Navigator.pop(sheet, 'move'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const AppText('Remove'),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        _showPhoto(photo);
      case 'replace':
        await _pickSlot(position, viewIndex);
      case 'remove':
        setState(() => _photos[position]?.remove(viewIndex));
      case 'move':
        final target = await _choosePlant(position, viewIndex);
        if (target == null || !mounted) return;
        setState(() {
          final other = _photos[target]?[viewIndex];
          (_photos[target] ??= {})[viewIndex] = photo;
          if (other == null) {
            _photos[position]!.remove(viewIndex);
          } else {
            _photos[position]![viewIndex] = other;
          }
        });
    }
  }

  Future<int?> _choosePlant(int from, int viewIndex) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in widget.plantPositions)
                if (p != from)
                  ActionChip(
                    avatar: _photos[p]?[viewIndex] != null
                        ? const Icon(Icons.swap_horiz, size: 16)
                        : null,
                    label: AppText('Plant $p'),
                    onPressed: () => Navigator.pop(sheet, p),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhoto(XFile photo) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: Image.file(File(photo.path), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _import() async {
    if (!_ready) return;
    setState(() {
      _working = true;
      _error = null;
    });
    for (final position in widget.plantPositions) {
      final slots = _photos[position] ?? const {};
      for (final entry
          in (slots.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
        final key = '$position:${entry.key}';
        if (_saved.contains(key)) continue;
        try {
          if (!mounted) return;
          await widget.onSavePhoto(
            position,
            _views[entry.key].viewType,
            entry.value.path,
          );
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _working = false;
            _error = 'Plant $position not saved. Tap to retry.';
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _saved.add(key);
          _done = _saved.length;
        });
      }
    }
    for (final position in widget.plantPositions) {
      try {
        await widget.onAnalyzePlant(position);
      } catch (_) {
        // Station review retries screening for plants that failed here.
      }
      if (!mounted) return;
    }
    setState(() {
      _working = false;
      _complete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.plantPositions.length;
    final missingOverviews = count - _overviewCount;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8F5),
          title: AppText('Station ${widget.stationNumber} · Upload'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _working || _complete
                  ? (_total == 0 ? 1 : _done / _total)
                  : count == 0
                  ? 0
                  : _overviewCount / count,
              minHeight: 4,
              backgroundColor: Colors.black12,
              color: _green,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        '$_overviewCount/$count overviews',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (missingOverviews > 0 && !_locked)
                      FilledButton.tonalIcon(
                        key: const Key('choose_station_photos'),
                        onPressed: _fillOverviews,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: AppText('Fill $missingOverviews'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final position = widget.plantPositions[index];
                    return _BatchPlantCard(
                      key: Key('batch_plant_$position'),
                      position: position,
                      views: _views,
                      photos: _photos[position] ?? const {},
                      savedKeys: _saved,
                      onEmptyTap: (v) => _pickSlot(position, v),
                      onFilledTap: (v) => _slotActions(position, v),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    key: const Key('import_station_photos'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _complete
                        ? () => Navigator.pop(context, true)
                        : _ready
                        ? _import
                        : null,
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(_complete ? Icons.check : Icons.upload),
                    label: AppText(
                      _complete
                          ? 'Done'
                          : _working
                          ? 'Saving $_done/$_total'
                          : 'Save $_total ${_total == 1 ? 'photo' : 'photos'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchPlantCard extends StatelessWidget {
  const _BatchPlantCard({
    super.key,
    required this.position,
    required this.views,
    required this.photos,
    required this.savedKeys,
    required this.onEmptyTap,
    required this.onFilledTap,
  });

  final int position;
  final List<BatchPhotoView> views;
  final Map<int, XFile> photos;
  final Set<String> savedKeys;
  final ValueChanged<int> onEmptyTap;
  final ValueChanged<int> onFilledTap;

  @override
  Widget build(BuildContext context) {
    final hasOverview = photos[0] != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOverview
              ? const Color(0xFF176B3A).withValues(alpha: .35)
              : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PlantBadge(position: position, done: hasOverview),
              const SizedBox(width: 10),
              AppText(
                'Plant $position',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              AppText(
                '${photos.length}/3',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < views.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: EvidenceSlot(
                    label: views[i].label,
                    icon: views[i].icon,
                    required: views[i].required,
                    file: photos[i] == null ? null : File(photos[i]!.path),
                    saved: savedKeys.contains('$position:$i'),
                    onTap: () =>
                        photos[i] == null ? onEmptyTap(i) : onFilledTap(i),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlantBadge extends StatelessWidget {
  const _PlantBadge({required this.position, required this.done});

  final int position;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: done ? const Color(0xFF176B3A) : const Color(0xFFE8ECE8),
      foregroundColor: done ? Colors.white : Colors.black54,
      child: done
          ? const Icon(Icons.check, size: 16)
          : Text(
              '$position',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
    );
  }
}

/// Square evidence slot used by the batch screen: an empty dashed target or a
/// filled photo with its view label always visible.
class EvidenceSlot extends StatelessWidget {
  const EvidenceSlot({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.required = false,
    this.file,
    this.image,
    this.saved = false,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final bool required;
  final File? file;
  final Widget? image;
  final bool saved;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B3A);
    final filled = file != null || image != null;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: filled
            ? Colors.black
            : required
            ? const Color(0xFFEAF4EC)
            : const Color(0xFFF4F5F3),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: filled
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    image ??
                        Image.file(
                          file!,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                          ),
                        ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _SlotTag(label: label, icon: icon),
                    ),
                    if (saved)
                      const Positioned(
                        top: 6,
                        left: 6,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: green,
                          child: Icon(
                            Icons.check,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (trailing != null)
                      Positioned(top: 4, right: 4, child: trailing!),
                  ],
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: required
                          ? green.withValues(alpha: .45)
                          : Colors.black12,
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 22,
                        color: required ? green : Colors.black45,
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: required ? green : Colors.black54,
                        ),
                      ),
                      if (required)
                        const AppText(
                          'Required',
                          style: TextStyle(fontSize: 10, color: green),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SlotTag extends StatelessWidget {
  const _SlotTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          AppText(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
