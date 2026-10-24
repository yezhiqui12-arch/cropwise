import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../localization/app_text.dart';
import '../../models/da_batch_import.dart';
import '../../services/da_batch_import_store.dart';
import '../../theme/app_colors.dart';

class DaBatchImportScreen extends StatefulWidget {
  const DaBatchImportScreen({
    super.key,
    required this.store,
    required this.assessmentId,
    required this.blockId,
    required this.blockNumber,
    required this.plantNumbers,
    required this.primaryViewType,
    required this.supportViewTypes,
    required this.onSavePhoto,
    required this.onScreenPlant,
    required this.onValidatePhoto,
    required this.onValidateScreening,
    required this.onFinish,
    this.pickPhotos,
  });
  final DaBatchImportStore store;
  final String assessmentId, blockId, primaryViewType;
  final int blockNumber;
  final List<int> plantNumbers;
  final List<String> supportViewTypes;
  final Future<void> Function(int plant, String view, DaBatchPhoto photo)
  onSavePhoto;
  final Future<void> Function(int plant, Set<String> photoIds) onScreenPlant;
  final Future<bool> Function(int plant, String view, String photoId)
  onValidatePhoto;
  final Future<bool> Function(int plant, Set<String> photoIds)
  onValidateScreening;
  final Future<bool> Function() onFinish;
  final Future<List<XFile>> Function(int limit)? pickPhotos;
  @override
  State<DaBatchImportScreen> createState() => _DaBatchImportScreenState();
}

class _DaBatchImportScreenState extends State<DaBatchImportScreen> {
  DaBatchImportDraft? _draft;
  bool _loading = true, _working = false, _arrange = false, _finishing = false;
  int _active = 0;
  String? _error, _phase;
  final Map<int, String> _failures = {};
  Future<void> _writes = Future.value();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
  });
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final draft = await widget.store.load(
        widget.assessmentId,
        widget.blockId,
      );
      if (draft != null) {
        for (
          var i = 0;
          i < draft.groups.length && i < draft.plantNumbers.length;
          i++
        ) {
          final group = draft.groups[i];
          for (var v = 0; v < group.length && v < 3; v++) {
            final photo = group[v];
            if (draft.saved.contains(photo.id) &&
                !await widget.onValidatePhoto(
                  draft.plantNumbers[i],
                  _view(v),
                  photo.id,
                )) {
              draft.saved.remove(photo.id);
              draft.screened.remove(draft.plantNumbers[i]);
            }
          }
          if (draft.screened.contains(draft.plantNumbers[i]) &&
              !await widget.onValidateScreening(
                draft.plantNumbers[i],
                group.map((p) => p.id).toSet(),
              )) {
            draft.screened.remove(draft.plantNumbers[i]);
          }
        }
        await widget.store.save(draft);
      }
      if (mounted)
        setState(() {
          _draft = draft;
          _arrange = draft != null && !draft.valid;
        });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the import draft.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _view(int i) =>
      i == 0 ? widget.primaryViewType : widget.supportViewTypes[i - 1];
  Future<void> _persist() {
    final snapshot = DaBatchImportDraft.fromJson(_draft!.toJson());
    _writes = _writes
        .catchError((_) {})
        .then((_) => widget.store.save(snapshot));
    return _writes;
  }

  Future<void> _change(VoidCallback action) async {
    if (_working || _draft?.locked == true) return;
    try {
      setState(() {
        action();
        _error = null;
        _active = _active.clamp(0, (_draft!.groups.length - 1).clamp(0, 59));
      });
      await _persist();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (mounted)
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
  }

  Future<void> _pick() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
      _phase = 'Copying photos';
    });
    try {
      final max = widget.plantNumbers.length * 3;
      final photos = widget.pickPhotos == null
          ? await ImagePicker().pickMultiImage(
              limit: max,
              requestFullMetadata: false,
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 85,
            )
          : await widget.pickPhotos!(max);
      if (photos.isEmpty) return;
      final draft = await widget.store.create(
        assessmentId: widget.assessmentId,
        blockId: widget.blockId,
        plantNumbers: widget.plantNumbers,
        paths: photos.map((p) => p.path).toList(),
      );
      if (mounted)
        setState(() {
          _draft = draft;
          _active = 0;
          _arrange = !draft.valid;
          if (draft.photos.length < photos.length)
            _error = 'Duplicate photos were removed.';
        });
    } catch (error) {
      _showError(error);
      await _load();
    } finally {
      if (mounted)
        setState(() {
          _working = false;
          _phase = null;
        });
    }
  }

  Future<void> _saveAndScreen() async {
    final draft = _draft!;
    if (!draft.valid || !draft.confirmed || _working) return;
    setState(() {
      _working = true;
      _error = null;
      _failures.clear();
      _arrange = false;
    });
    _toTop();
    try {
      draft.locked = true;
      await _persist();
      final groups = draft.groups;
      for (var i = 0; i < groups.length; i++) {
        if (!mounted) break;
        final number = draft.plantNumbers[i];
        final group = groups[i];
        try {
          // Validate even a persisted success marker before skipping it.
          for (var v = 0; v < group.length; v++) {
            if (!mounted) return;
            final photo = group[v];
            if (draft.saved.contains(photo.id) &&
                await widget.onValidatePhoto(number, _view(v), photo.id))
              continue;
            draft.screened.remove(number);
            if (mounted)
              setState(() {
                _active = i;
                _phase = 'Saving Plant $number';
              });
            await widget.onSavePhoto(number, _view(v), photo);
            draft.saved.add(photo.id);
            await _persist();
            if (mounted) setState(() {});
          }
          if (!mounted) return;
          if (draft.screened.contains(number) &&
              !await widget.onValidateScreening(
                number,
                group.map((p) => p.id).toSet(),
              )) {
            draft.screened.remove(number);
            await _persist();
          }
          if (!draft.screened.contains(number)) {
            if (mounted)
              setState(() {
                _active = i;
                _phase = 'Screening Plant $number';
              });
            await widget.onScreenPlant(number, group.map((p) => p.id).toSet());
            if (!await widget.onValidateScreening(
              number,
              group.map((p) => p.id).toSet(),
            )) {
              throw StateError('Screening was not saved. Retry this plant.');
            }
            draft.screened.add(number);
            await _persist();
            if (mounted) setState(() {});
          }
        } catch (error) {
          _failures[number] = error.toString().replaceFirst('Bad state: ', '');
          if (mounted) setState(() {});
        }
      }
      if (!draft.complete && mounted)
        setState(
          () => _error = '${_failures.length} plant(s) need another try.',
        );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted)
        setState(() {
          _working = false;
          _phase = null;
        });
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      final draft = _draft!;
      for (var i = 0; i < draft.groups.length; i++) {
        final number = draft.plantNumbers[i];
        if (!await widget.onValidateScreening(
          number,
          draft.groups[i].map((p) => p.id).toSet(),
        )) {
          draft.screened.remove(number);
        }
      }
      await _persist();
      if (!draft.complete) {
        throw StateError('Some plant results need another try.');
      }
      if (!await widget.onFinish()) return;
      await _writes;
      await widget.store.clear(_draft!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const AppText('Start another import?'),
        content: const AppText('Saved plant photos stay in the sample.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const AppText('Start new'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _writes;
    await widget.store.clear(_draft!);
    if (mounted) Navigator.pop(context, false);
  }

  void _move(String photoId, int target) =>
      _change(() => _draft!.move(photoId, target));
  Future<void> _photoActions(DaBatchPhoto photo) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const AppText('View photo'),
              onTap: () => Navigator.pop(c, 'view'),
            ),
            if (!_draft!.locked) ...[
              ListTile(
                leading: const Icon(Icons.photo_size_select_actual_outlined),
                title: const AppText('Use as overview'),
                onTap: () => Navigator.pop(c, 'overview'),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const AppText('Move to plant'),
                onTap: () => Navigator.pop(c, 'move'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const AppText('Remove photo'),
                onTap: () => Navigator.pop(c, 'remove'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'view') {
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.file(
                    File(photo.path),
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: AppText('Photo unavailable'),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const AppText('Close'),
              ),
            ],
          ),
        ),
      );
    } else if (choice == 'overview') {
      await _change(() => _draft!.makeOverview(photo.id));
    } else if (choice == 'remove') {
      await _change(() => _draft!.remove(photo.id));
    } else if (choice == 'move') {
      final group = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _draft!.groups.length; i++)
                    ActionChip(
                      label: AppText(_groupName(i)),
                      onPressed: () => Navigator.pop(c, i),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (group != null && mounted) _move(photo.id, group);
    }
  }

  String _groupName(int index) => index < _draft!.plantNumbers.length
      ? 'Plant ${_draft!.plantNumbers[index]}'
      : 'Group ${index + 1}';
  Widget _image(
    DaBatchPhoto photo, {
    BoxFit fit = BoxFit.cover,
    int width = 800,
  }) => Image.file(
    File(photo.path),
    fit: fit,
    cacheWidth: width,
    errorBuilder: (_, __, ___) => const ColoredBox(
      color: Color(0xFFE8ECE6),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppColors.textSecondary,
        ),
      ),
    ),
  );
  Widget _photo(DaBatchPhoto photo, {required bool overview}) {
    final body = InkWell(
      key: Key('batch_photo_${photo.id}'),
      onTap: _working ? null : () => _photoActions(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _image(photo),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppText(
                  overview ? 'Overview' : 'Closer view',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (_draft!.locked || _working) return body;
    return LongPressDraggable<String>(
      data: photo.id,
      feedback: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 100, height: 100, child: _image(photo)),
      ),
      childWhenDragging: Opacity(opacity: .3, child: body),
      child: body,
    );
  }

  Widget _workspace() {
    final draft = _draft!, groups = draft.groups;
    if (groups.isEmpty)
      return const Center(child: AppText('No photos. Start another import.'));
    final active = _active.clamp(0, groups.length - 1), group = groups[active];
    final number = active < draft.plantNumbers.length
        ? draft.plantNumbers[active]
        : null;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                '${groups.length} plants · ${draft.photos.length} photos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              AppText(
                'Block ${widget.blockNumber} · 20-plant sample',
                style: const TextStyle(color: Colors.white70),
              ),
              if (_working || draft.locked) ...[
                const SizedBox(height: 12),
                AppText(
                  'Photos saved ${draft.saved.length}/${draft.photos.length} · Plants screened ${draft.screened.length}/${groups.length}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: draft.photos.isEmpty
                      ? 0
                      : (draft.saved.length + draft.screened.length) /
                            (draft.photos.length + groups.length),
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
                if (_phase != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AppText(
                      _phase!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 32 + 20 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) => DragTarget<String>(
              onWillAcceptWithDetails: (_) => !_working && !draft.locked,
              onAcceptWithDetails: (d) => _move(d.data, i),
              builder: (_, candidates, __) => ChoiceChip(
                showCheckmark: false,
                key: Key('batch_group_$i'),
                selected: i == active || candidates.isNotEmpty,
                label: AppText(
                  i < draft.plantNumbers.length
                      ? '${draft.plantNumbers[i]}'
                      : 'Group ${i + 1}',
                ),
                avatar:
                    _failures.containsKey(
                      i < draft.plantNumbers.length
                          ? draft.plantNumbers[i]
                          : null,
                    )
                    ? const Icon(Icons.error_outline, size: 16)
                    : null,
                onSelected: _working
                    ? null
                    : (_) => setState(() => _active = i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (!_arrange) ...[
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              AppText(
                _groupName(active),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              AppText('${group.length}/3 photos'),
            ],
          ),
          const SizedBox(height: 12),
          DragTarget<String>(
            onWillAcceptWithDetails: (_) => !_working && !draft.locked,
            onAcceptWithDetails: (d) => _move(d.data, active),
            builder: (_, candidates, __) => Container(
              padding: candidates.isEmpty
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: candidates.isEmpty
                    ? Colors.transparent
                    : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 230,
                    width: double.infinity,
                    child: _photo(group.first, overview: true),
                  ),
                  if (group.length > 1) ...[
                    const SizedBox(height: 9),
                    SizedBox(
                      height: 88,
                      child: Row(
                        children: [
                          for (var i = 1; i < group.length && i < 3; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: i == group.length - 1 || i == 2
                                      ? 0
                                      : 8,
                                ),
                                child: _photo(group[i], overview: false),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (number != null && _failures[number] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _failures[number]!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
        if (!draft.locked) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('batch_arrange'),
            onPressed: _working
                ? null
                : () {
                    setState(() => _arrange = !_arrange);
                    _toTop();
                  },
            icon: const Icon(Icons.view_module_outlined),
            label: AppText(_arrange ? 'Close arrangement' : 'Arrange photos'),
          ),
          if (_arrange) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: AppText(
                'Tap the first photo of each plant. Tap again to join.',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (var count = 1; count <= 3; count++)
                  if ((draft.photos.length / count).ceil() <=
                      draft.plantNumbers.length)
                    ActionChip(
                      key: Key('batch_group_by_$count'),
                      label: AppText('$count per plant'),
                      onPressed: _working
                          ? null
                          : () => _change(() => draft.groupByCount(count)),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: draft.photos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio:
                    .85 /
                    MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.8),
              ),
              itemBuilder: (_, i) {
                final photo = draft.photos[i];
                final start = i == 0 || draft.starts.contains(photo.id);
                final groupIndex = groups.indexWhere(
                  (g) => g.any((p) => p.id == photo.id),
                );
                return InkWell(
                  key: Key('batch_boundary_$i'),
                  onTap: _working
                      ? null
                      : () => _change(() => draft.toggleStart(photo.id)),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: start
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox.expand(
                              child: _image(photo, width: 320),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppText(
                        start
                            ? _groupName(groupIndex)
                            : '${_groupName(groupIndex)} · close-up',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: start ? FontWeight.w700 : FontWeight.w400,
                          color: start
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (!draft.valid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: AppText(
                groups.length > draft.plantNumbers.length
                    ? 'Use up to ${draft.plantNumbers.length} plant groups.'
                    : 'Keep 1–3 photos in each plant group.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          CheckboxListTile(
            key: const Key('batch_confirm_groups'),
            contentPadding: EdgeInsets.zero,
            title: const AppText('I checked the plant groups'),
            value: draft.confirmed,
            onChanged: _working || !draft.valid
                ? null
                : (v) => _change(() => draft.confirmed = v == true),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: !_working && !_finishing,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8F5),
          title: const AppText('Batch import'),
          actions: [
            if (draft != null && !_working && !_finishing)
              IconButton(
                tooltip: 'Start another import',
                onPressed: _discard,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : draft == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 48,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              AppText(
                                'Block ${widget.blockNumber}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppText(
                                '${widget.plantNumbers.length} plants available · Up to ${widget.plantNumbers.length * 3} photos',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              const AppText(
                                'Select photos from several plants, then group each plant’s views.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _workspace(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: AppText(
                    _error!,
                    key: const Key('batch_error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('batch_primary'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _loading || _working || _finishing
                        ? null
                        : draft == null
                        ? (widget.plantNumbers.isEmpty ? null : _pick)
                        : draft.complete
                        ? _finish
                        : draft.valid && draft.confirmed
                        ? _saveAndScreen
                        : null,
                    icon: _working || _finishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            draft == null
                                ? Icons.photo_library_outlined
                                : draft.complete
                                ? Icons.arrow_forward
                                : Icons.auto_awesome_outlined,
                          ),
                    label: AppText(
                      _finishing
                          ? 'Opening sample'
                          : _working
                          ? (_phase ?? 'Saving photos')
                          : draft == null
                          ? 'Choose photos'
                          : draft.complete
                          ? 'Continue to sample'
                          : draft.locked
                          ? 'Retry unfinished plants'
                          : 'Save and screen',
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
