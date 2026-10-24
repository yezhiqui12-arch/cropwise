import '../services/map_view_policy.dart';
import 'package:flutter/material.dart';
import '../localization/app_language.dart';
import '../localization/app_text.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../services/polygon_calculator.dart';
import '../theme/app_colors.dart';
import 'create_field_screen.dart';
import 'field_details_screen.dart';

class FieldsScreen extends StatelessWidget {
  const FieldsScreen({super.key});

  Future<void> _openCreateField(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateFieldScreen()),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Field saved offline and selected.')),
      );
    }
  }

  Future<void> _openEditField(
    BuildContext context,
    FieldWorkspaceRecord workspace,
  ) async {
    final provider = context.read<FieldWorkspaceProvider>();
    provider.selectField(workspace.field.id);
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFieldScreen(workspace: workspace),
      ),
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Field changes saved offline.')),
      );
    }
  }

  Future<void> _showFieldActions(
    BuildContext context,
    FieldWorkspaceRecord workspace,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                workspace.field.name,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              key: const Key('edit_field_details_action'),
              leading: const Icon(Icons.edit_outlined),
              title: const AppText('Edit field details'),
              subtitle: const AppText('Name, area, location, and current crop'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              key: const Key('delete_field_action'),
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const AppText(
                'Delete field',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const AppText('Move to Recently Deleted'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      await _openEditField(context, workspace);
    } else if (action == 'delete') {
      await _confirmDeleteField(context, workspace);
    }
  }

  Future<void> _confirmDeleteField(
    BuildContext context,
    FieldWorkspaceRecord workspace,
  ) async {
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
    if (confirmed != true || !context.mounted) return;
    await context.read<FieldWorkspaceProvider>().deleteField(
      workspace.field.id,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText('${workspace.field.name} deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const AppText('My Maize Fields'),
        actions: [
          IconButton(
            key: const Key('open_recently_deleted_fields_button'),
            tooltip: AppWords.of(context).translate('Recently Deleted'),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const RecentlyDeletedFieldsScreen(),
              ),
            ),
            icon: const Icon(Icons.restore_from_trash_outlined),
          ),
        ],
      ),
      floatingActionButton:
          !provider.isLoading && provider.workspaces.isNotEmpty
          ? FloatingActionButton.extended(
              key: const Key('add_field_fab'),
              onPressed: () => _openCreateField(context),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const AppText('Add Field'),
            )
          : null,
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, FieldWorkspaceProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppText(
            'The local field database could not be loaded.\n${provider.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (provider.workspaces.isEmpty) {
      return _EmptyFields(onAdd: () => _openCreateField(context));
    }

    final ordered = [...provider.workspaces]
      ..sort((a, b) {
        if (a.field.id == provider.activeFieldId) return -1;
        if (b.field.id == provider.activeFieldId) return 1;
        return a.field.name.compareTo(b.field.name);
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final workspace = ordered[index];
        final isSelected = workspace.field.id == provider.activeFieldId;
        return _FieldListCard(
          workspace: workspace,
          isSelected: isSelected,
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => FieldDetailsScreen(workspace: workspace),
            ),
          ),
          onLongPress: () => _showFieldActions(context, workspace),
          onSelect: isSelected
              ? null
              : () => provider.selectField(workspace.field.id),
        );
      },
    );
  }
}

class _EmptyFields extends StatelessWidget {
  const _EmptyFields({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.landscape_outlined,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            const AppText(
              'No maize fields yet',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const AppText(
              'Register a field to keep its outline, crop cycles, and assessments together on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              // Reuse the established add-field key: this button and the FAB
              // are mutually exclusive across the empty/populated states.
              key: const Key('add_field_fab'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const AppText('Add your first field'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldListCard extends StatelessWidget {
  const _FieldListCard({
    required this.workspace,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onSelect,
  });

  final FieldWorkspaceRecord workspace;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final areaLabel = boundary == null
        ? 'Area unavailable'
        : '${boundary.areaHectares.toStringAsFixed(2)} ha';
    final radius = BorderRadius.circular(16);
    return Material(
      key: ValueKey('field_card_${workspace.field.id}'),
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: isSelected
            ? _CurrentFieldCardContent(
                workspace: workspace,
                areaLabel: areaLabel,
                location: _locationLabel(workspace),
              )
            : SizedBox(
                height: 104,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewWidth = constraints.maxWidth < 340
                        ? 104.0
                        : 124.0;
                    return Row(
                      children: [
                        SizedBox(
                          width: previewWidth,
                          child: _FieldMapPreview(workspace: workspace),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        workspace.field.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        _locationLabel(workspace),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        areaLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton(
                                      onPressed: onSelect,
                                      style: TextButton.styleFrom(
                                        backgroundColor: AppColors.primaryLight,
                                        foregroundColor: AppColors.primary,
                                        visualDensity: VisualDensity.compact,
                                        minimumSize: const Size(0, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const AppText(
                                        'Use field',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _locationLabel(FieldWorkspaceRecord workspace) {
    final field = workspace.field;
    final parts = [
      field.barangay,
      field.municipalityCity,
      field.province,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return 'Location not entered';
  }
}

class _CurrentFieldCardContent extends StatelessWidget {
  const _CurrentFieldCardContent({
    required this.workspace,
    required this.areaLabel,
    required this.location,
  });
  final FieldWorkspaceRecord workspace;
  final String areaLabel;
  final String location;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _FieldMapPreview(workspace: workspace),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x32000000), Color(0xD9001A10)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      AppText(
                        'CURRENT FIELD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  workspace.field.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      areaLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldMapPreview extends StatelessWidget {
  const _FieldMapPreview({required this.workspace});
  final FieldWorkspaceRecord workspace;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final outline = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    ).toList(growable: false);
    final fallback =
        boundary?.centroidLatitude != null &&
            boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : const LatLng(17.7905, 121.4781);
    final center = outline.isEmpty
        ? fallback
        : PolygonCalculator.calculateCenter(outline);
    final hasMappedLocation =
        outline.length >= 3 ||
        (boundary?.centroidLatitude != null &&
            boundary?.centroidLongitude != null);
    if (!hasMappedLocation) {
      return Container(
        color: AppColors.primaryLight,
        alignment: Alignment.center,
        child: const Icon(
          Icons.map_outlined,
          color: AppColors.primary,
          size: 34,
        ),
      );
    }
    return IgnorePointer(
      child: FlutterMap(
        key: ValueKey(
          'field-list-map-${workspace.field.id}-${boundary?.id}-'
          '${boundary?.geometryGeojson.hashCode}',
        ),
        options: MapOptions(
          minZoom: MapViewPolicy.minZoom,
          maxZoom: MapViewPolicy.maxZoom,
          initialCenter: MapViewPolicy.initialCenter(center),
          initialZoom: outline.isEmpty ? 15 : 17,
          initialCameraFit: outline.length >= 3
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(outline),
                  padding: const EdgeInsets.all(18),
                  maxZoom: 18,
                )
              : null,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
          backgroundColor: const Color(0xFFE7EFE8),
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
          if (outline.length >= 3)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: outline,
                  color: const Color(0x2419C85A),
                  borderColor: const Color(0xAA8DFF63),
                  borderStrokeWidth: 7,
                ),
                Polygon(
                  points: outline,
                  color: Colors.transparent,
                  borderColor: const Color(0xFF064D2B),
                  borderStrokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [9, 6]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
