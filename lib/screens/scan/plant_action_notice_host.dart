import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/repositories/plant_action_repository.dart';
import '../../models/da_monitoring.dart';
import '../../models/guided_plant_details.dart';
import '../../models/plant_action_guidance.dart';
import '../../theme/app_colors.dart';
import 'plant_action_guidance_panel.dart';

/// Lives outside the draggable sheet so collapsing the map cannot hide notices.
class PlantActionNoticeHost extends StatefulWidget {
  const PlantActionNoticeHost({
    super.key,
    required this.repository,
    required this.assessmentId,
    required this.blockRunId,
    required this.number,
    required this.revision,
    required this.enabled,
    required this.loadDetails,
    required this.resolveFile,
    required this.child,
  });
  final PlantActionRepository repository;
  final String assessmentId, blockRunId, revision;
  final int number;
  final bool enabled;
  final Future<GuidedPlantDetails> Function() loadDetails;
  final Future<File> Function(String uri) resolveFile;
  final Widget child;

  @override
  State<PlantActionNoticeHost> createState() => _PlantActionNoticeHostState();
}

class _PlantActionNoticeHostState extends State<PlantActionNoticeHost> {
  int _generation = 0;
  bool _showing = false;
  DialogRoute<void>? _notice;
  NavigatorState? _navigator;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reconsider when the camera/import route closes, without showing over it.
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PlantActionNoticeHost old) {
    super.didUpdateWidget(old);
    final changedPlant =
        old.assessmentId != widget.assessmentId ||
        old.blockRunId != widget.blockRunId ||
        old.number != widget.number ||
        old.repository.ownerId != widget.repository.ownerId;
    if (changedPlant ||
        old.revision != widget.revision ||
        old.enabled != widget.enabled) {
      _generation++;
      if (changedPlant || !widget.enabled) _dismissNotice();
      _schedule();
    }
  }

  void _dismissNotice() {
    final route = _notice;
    final navigator = _navigator;
    if (route == null || navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consider();
    });
  }

  Future<void> _consider() async {
    if (!widget.enabled ||
        _showing ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = _generation;
    final repository = widget.repository;
    final assessment = widget.assessmentId;
    final block = widget.blockRunId;
    final number = widget.number;
    final resolveFile = widget.resolveFile;
    DialogRoute<void>? presented;
    bool current() =>
        mounted &&
        generation == _generation &&
        widget.enabled &&
        ModalRoute.of(context)?.isCurrent == true;
    try {
      final details = await widget.loadDetails();
      if (!current() ||
          details.photos.isEmpty ||
          details.snapshot.prepared.run.id != block ||
          details.snapshot.stationNumber != number ||
          details.snapshot.reviewIsCurrent) {
        return;
      }
      final finding = DaPlantFinding.fromModel(details.diagnosis)
          .withCorrections(
            details.monitoring?.plant(block, number),
            daPhotoSignature(details.photos),
          );
      final guides = await repository.pendingNotices(
        assessment,
        PlantActionGuide.resolve(details.diagnosis, finding: finding),
      );
      if (!mounted || !current() || _showing || guides.isEmpty) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      final title = guides.length > 1
          ? 'Findings detected'
          : switch (guides.first.kind) {
              PlantActionKind.larva => 'Larva detected',
              PlantActionKind.eggs => 'Eggs detected',
              PlantActionKind.inspectWhorl => 'Frass detected',
              PlantActionKind.inspectDamage => 'Damage detected',
            };
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          key: const Key('plant_action_notice'),
          backgroundColor: AppColors.background,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: MediaQuery.sizeOf(context).height * .90,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          guides.first.kind == PlantActionKind.larva ||
                                  guides.first.kind == PlantActionKind.eggs
                              ? Icons.bug_report_outlined
                              : Icons.fact_check_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plant $number',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: PlantActionGuidancePanel(
                      repository: repository,
                      assessmentId: assessment,
                      blockRunId: block,
                      number: number,
                      atPlant: true,
                      initiallyExpanded: true,
                      showHeading: false,
                      guideIds: guides.map((g) => g.id).toSet(),
                      loadDetails: () async => details,
                      resolveFile: resolveFile,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const Key('plant_action_notice_continue'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue scouting'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      presented = route;
      _showing = true;
      _notice = route;
      _navigator = navigator;
      final closed = navigator.push(route);
      // Only persist suppression after the notification actually reaches a frame.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && route.isActive && generation == _generation) {
        try {
          await repository.markNoticesShown(assessment, guides);
        } catch (_) {
          // The already-visible notice stays dismissible if local saving fails.
        }
      }
      await closed;
    } catch (_) {
      // Optional notification failure must not change evidence or block scouting.
    } finally {
      if (presented != null && identical(_notice, presented)) {
        _notice = null;
        _navigator = null;
        _showing = false;
        if (mounted) _schedule();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _dismissNotice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
