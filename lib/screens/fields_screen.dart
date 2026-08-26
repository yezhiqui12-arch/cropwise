import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
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
        const SnackBar(content: Text('Field saved offline and selected.')),
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
        const SnackBar(content: Text('Field changes saved offline.')),
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
              title: const Text('Edit field details'),
              subtitle: const Text('Name, area, location, and current crop'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              key: const Key('delete_field_action'),
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete field',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text('Move to Recently Deleted'),
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
        title: const Text('Delete this field?'),
        content: const Text(
          'It will move to Recently Deleted for 30 days. You can restore it '
          'during that time. After 30 days, its stored photographs are removed '
          'and the field cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_field_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Recently Deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<FieldWorkspaceProvider>().deleteField(
      workspace.field.id,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${workspace.field.name} deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Maize Fields'),
        actions: [
          IconButton(
            key: const Key('open_recently_deleted_fields_button'),
            tooltip: 'Recently Deleted',
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_field_fab'),
        onPressed: () => _openCreateField(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Field'),
      ),
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
          child: Text(
            'The local field database could not be loaded.\n${provider.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (provider.workspaces.isEmpty) {
      return _EmptyFields(onAdd: () => _openCreateField(context));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: provider.workspaces.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final workspace = provider.workspaces[index];
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
            const Text(
              'No maize fields yet',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Register a field to keep its outline, crop cycles, and assessments together on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add your first field'),
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
    final spatialState = workspace.spatialState;

    return Card(
      key: ValueKey('field_card_${workspace.field.id}'),
      elevation: 0,
      color: isSelected ? AppColors.primaryLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: isSelected
                    ? AppColors.primary
                    : AppColors.primaryLight,
                foregroundColor: isSelected ? Colors.white : AppColors.primary,
                child: const Icon(Icons.agriculture_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            workspace.field.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _locationLabel(workspace),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InfoChip(
                          icon: Icons.straighten,
                          label: boundary == null
                              ? 'Area unavailable'
                              : '${boundary.areaHectares.toStringAsFixed(2)} ha',
                        ),
                        _InfoChip(
                          icon: switch (spatialState) {
                            FieldSpatialState.approximateOutline =>
                              Icons.draw_outlined,
                            FieldSpatialState.entranceLocation =>
                              Icons.location_on_outlined,
                            FieldSpatialState.reportedAreaOnly =>
                              Icons.info_outline,
                          },
                          label: switch (spatialState) {
                            FieldSpatialState.approximateOutline =>
                              'Approximate outline',
                            FieldSpatialState.entranceLocation =>
                              'Entrance GPS recorded',
                            FieldSpatialState.reportedAreaOnly =>
                              'Boundary not added',
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('View details'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (onSelect != null)
                          TextButton(
                            onPressed: onSelect,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Use field'),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              'CURRENT',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
    return field.locationDescription?.trim().isNotEmpty == true
        ? field.locationDescription!
        : 'Location not entered';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
