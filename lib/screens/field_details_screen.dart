import '../services/map_view_policy.dart';
import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import '../localization/app_language.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../services/polygon_calculator.dart';
import '../theme/app_colors.dart';
import 'create_field_screen.dart';
import 'offline_field_map_screen.dart';

class FieldDetailsScreen extends StatefulWidget {
  const FieldDetailsScreen({super.key, required this.workspace});

  final FieldWorkspaceRecord workspace;

  @override
  State<FieldDetailsScreen> createState() => _FieldDetailsScreenState();
}

class _FieldDetailsScreenState extends State<FieldDetailsScreen> {
  FieldWorkspaceRecord _currentWorkspace(FieldWorkspaceProvider provider) {
    for (final workspace in provider.workspaces) {
      if (workspace.field.id == widget.workspace.field.id) return workspace;
    }
    return widget.workspace;
  }

  Future<void> _editField(FieldWorkspaceRecord workspace) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFieldScreen(workspace: workspace),
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Field changes saved offline.')),
      );
    }
  }

  Future<void> _delete(FieldWorkspaceRecord workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const AppText('Delete this field?'),
        content: const AppText(
          'It will move to Recently Deleted for 30 days. You can restore it '
          'during that time. After 30 days, its stored photographs are removed '
          'and the field cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_field_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const AppText('Move to Recently Deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<FieldWorkspaceProvider>().deleteField(
        workspace.field.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('Field could not be deleted: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();
    final workspace = _currentWorkspace(provider);
    final crop = workspace.cropCycle;
    final isActive = provider.activeFieldId == workspace.field.id;

    final planted = crop?.plantingDate?.toLocal();
    final cropAge = planted == null
        ? AppWords.of(context).translate('Not recorded')
        : AppWords.of(
            context,
          ).days(DateTime.now().difference(planted).inDays.clamp(0, 99999));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const AppText('Field Details')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            sliver: SliverList.list(
              children: [
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFDDE7E0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 194,
                        width: double.infinity,
                        child: _FieldHeaderMap(workspace: workspace),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              size: 18,
                              color: Color(0xFF50735C),
                            ),
                            const SizedBox(width: 9),
                            const Expanded(
                              child: AppText(
                                'Field boundary',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF293D31),
                                ),
                              ),
                            ),
                            AppText(
                              workspace.hasApproximateOutline
                                  ? 'Mapped'
                                  : 'Not mapped',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF647B6B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FieldOverviewCard(
                  workspace: workspace,
                  isActive: isActive,
                  cropAge: cropAge,
                ),
                const SizedBox(height: 20),
                _SectionLabel('FIELD TOOLS'),
                const SizedBox(height: 9),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFDDE7E0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    leading: const Icon(
                      Icons.offline_pin_outlined,
                      color: Color(0xFF50735C),
                    ),
                    title: const AppText(
                      'Offline field map',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const AppText(
                      'Manage saved map',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF92A096),
                    ),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            OfflineFieldMapScreen(workspace: workspace),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _SectionLabel('FIELD RECORD'),
                const SizedBox(height: 9),
                _DetailCard(
                  title: 'Crop details',
                  icon: Icons.agriculture_outlined,
                  rows: [
                    _DetailRow(
                      'Maize variety',
                      crop?.varietyName ??
                          AppWords.of(context).translate('Not recorded'),
                      Icons.agriculture_outlined,
                    ),
                    _DetailRow(
                      'Planting date',
                      _dateLabel(crop?.plantingDate),
                      Icons.calendar_today_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DetailCard(
                  title: 'Location',
                  icon: Icons.info_outline,
                  rows: [
                    _DetailRow(
                      'Barangay',
                      workspace.field.barangay ??
                          AppWords.of(context).translate('Not recorded'),
                      Icons.location_on_outlined,
                    ),
                    _DetailRow(
                      'Municipality / City',
                      workspace.field.municipalityCity ??
                          AppWords.of(context).translate('Not recorded'),
                      Icons.location_city_outlined,
                    ),
                    _DetailRow(
                      'Province',
                      workspace.field.province ??
                          AppWords.of(context).translate('Not recorded'),
                      Icons.map_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('edit_field_button'),
                        onPressed: provider.isSaving
                            ? null
                            : () => _editField(workspace),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFFE5F4E9),
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const AppText('Edit field'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('delete_field_button'),
                        onPressed: provider.isSaving
                            ? null
                            : () => _delete(workspace),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          foregroundColor: Colors.red.shade700,
                          backgroundColor: const Color(0xFFFFE9E7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const AppText('Delete field'),
                      ),
                    ),
                  ],
                ),
                if (!isActive) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('use_this_field_button'),
                    onPressed: () => provider.selectField(workspace.field.id),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const AppText('Use this field'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return AppWords.of(context).translate('Not recorded');
    return DateFormat('MMM d, yyyy').format(value.toLocal());
  }
}

class RecentlyDeletedFieldsScreen extends StatelessWidget {
  const RecentlyDeletedFieldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<FieldRepository>();
    return Scaffold(
      appBar: AppBar(title: const AppText('Recently Deleted')),
      body: StreamBuilder<List<FieldWorkspaceRecord>>(
        stream: repository.watchRecentlyDeletedFieldWorkspaces(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: AppText('Recently deleted fields could not load.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final fields = snapshot.data!;
          if (fields.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppText(
                  'Recently Deleted is empty',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: fields.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final workspace = fields[index];
              return Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.restore_from_trash_outlined),
                  title: Text(
                    workspace.field.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: AppText(_deletionLabel(workspace.field.updatedAt)),
                  trailing: TextButton(
                    key: ValueKey('restore_field_${workspace.field.id}'),
                    onPressed: () async {
                      await context.read<FieldWorkspaceProvider>().restoreField(
                        workspace.field.id,
                      );
                    },
                    child: const AppText('Restore'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _deletionLabel(DateTime requestedAt) {
    final deletionAt = requestedAt.toUtc().add(const Duration(days: 30));
    final remaining = deletionAt.difference(DateTime.now().toUtc());
    final days = remaining.inSeconds <= 0
        ? 0
        : (remaining.inSeconds / Duration.secondsPerDay).ceil();
    return days == 1
        ? 'Permanently deleted in 1 day'
        : 'Permanently deleted in $days days';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: AppText(
      title,
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.3,
        color: Color(0xFF78877D),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFDDE7E0)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFF50735C)),
              const SizedBox(width: 10),
              AppText(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF293D31),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    row.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF78877D),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF293D31),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _DetailRow {
  const _DetailRow(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _FieldHeaderMap extends StatelessWidget {
  const _FieldHeaderMap({required this.workspace});

  final FieldWorkspaceRecord workspace;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final points = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    ).toList(growable: false);
    final fallback =
        boundary?.centroidLatitude != null &&
            boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : const LatLng(17.7905, 121.4781);
    return FlutterMap(
      key: ValueKey('field-details-map-${workspace.field.id}-${boundary?.id}'),
      options: MapOptions(
        minZoom: MapViewPolicy.minZoom,
        maxZoom: MapViewPolicy.maxZoom,
        initialCenter: MapViewPolicy.initialCenter(
          points.isEmpty ? fallback : PolygonCalculator.calculateCenter(points),
        ),
        initialZoom: points.length >= 3 ? 17 : 15,
        initialCameraFit: points.length >= 3
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(26),
                maxZoom: 18,
              )
            : null,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
        backgroundColor: AppColors.surfaceContainer,
      ),
      children: [
        TileLayer(
          tileUpdateTransformer: TileUpdateTransformers.debounce(
            const Duration(milliseconds: 160),
          ),
          panBuffer: 0,
          keepBuffer: 3,
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.wormwise.app.wormwise',
          maxNativeZoom: 18,
        ),
        TileLayer(
          tileUpdateTransformer: TileUpdateTransformers.debounce(
            const Duration(milliseconds: 160),
          ),
          panBuffer: 0,
          keepBuffer: 3,
          urlTemplate:
              'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.wormwise.app.wormwise',
          maxNativeZoom: 19,
        ),
        if (points.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: points,
                color: const Color(0x2419C85A),
                borderColor: const Color(0xAA8DFF63),
                borderStrokeWidth: 8,
              ),
              Polygon(
                points: points,
                color: Colors.transparent,
                borderColor: const Color(0xFF064D2B),
                borderStrokeWidth: 3.5,
                pattern: StrokePattern.dashed(segments: const [10, 7]),
              ),
            ],
          ),
      ],
    );
  }
}

class _FieldOverviewCard extends StatelessWidget {
  const _FieldOverviewCard({
    required this.workspace,
    required this.isActive,
    required this.cropAge,
  });

  final FieldWorkspaceRecord workspace;
  final bool isActive;
  final String cropAge;

  @override
  Widget build(BuildContext context) {
    final field = workspace.field;
    final location = [
      field.barangay,
      field.municipalityCity,
      field.province,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFDDE7E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF293D31),
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F1E7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const AppText(
                      'Current',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D5940),
                      ),
                    ),
                  ),
              ],
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Color(0xFF78877D),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF647B6B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    icon: Icons.dashboard_outlined,
                    value: workspace.boundary == null
                        ? 'Not recorded'
                        : '${workspace.boundary!.areaHectares.toStringAsFixed(2)} ha',
                    label: 'Area',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OverviewMetric(
                    icon: Icons.timer_outlined,
                    value: cropAge,
                    label: 'Crop age',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7F4),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF78877D)),
        ),
        const SizedBox(height: 5),
        AppText(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF293D31),
          ),
        ),
      ],
    ),
  );
}
