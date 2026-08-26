import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';
import 'create_field_screen.dart';

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
        const SnackBar(content: Text('Field changes saved offline.')),
      );
    }
  }

  Future<void> _delete(FieldWorkspaceRecord workspace) async {
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
    if (confirmed != true || !mounted) return;
    try {
      await context.read<FieldWorkspaceProvider>().deleteField(
        workspace.field.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Field could not be deleted: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();
    final workspace = _currentWorkspace(provider);
    final boundary = workspace.boundary;
    final crop = workspace.cropCycle;
    final isActive = provider.activeFieldId == workspace.field.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Details'),
        actions: [
          IconButton(
            key: const Key('edit_field_button'),
            tooltip: 'Edit field details',
            onPressed: provider.isSaving ? null : () => _editField(workspace),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.primary,
                child: Icon(Icons.agriculture_outlined, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.field.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isActive ? 'Current field' : 'Saved field',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _DetailCard(
            title: 'Location and outline',
            icon: Icons.map_outlined,
            rows: [
              _DetailRow('Location', _locationLabel(workspace)),
              _DetailRow(
                'Area',
                boundary == null
                    ? 'Not available'
                    : '${boundary.areaHectares.toStringAsFixed(2)} ha',
              ),
              _DetailRow(
                'Outline',
                workspace.hasApproximateOutline
                    ? 'Confirmed approximate outline'
                    : 'Not yet confirmed',
              ),
            ],
            note:
                'Location, area, and outline are protected from direct editing. '
                'Boundary corrections create a new saved version from Map.',
          ),
          const SizedBox(height: 12),
          _DetailCard(
            title: 'Current maize crop',
            icon: Icons.eco_outlined,
            rows: [
              _DetailRow('Variety', crop?.varietyName ?? 'Not recorded'),
              _DetailRow('Use', _intendedUseLabel(crop?.intendedUse)),
              _DetailRow('Planting date', _dateLabel(crop?.plantingDate)),
            ],
          ),
          const SizedBox(height: 18),
          if (!isActive)
            FilledButton.icon(
              key: const Key('use_this_field_button'),
              onPressed: () => provider.selectField(workspace.field.id),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Use this field'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('delete_field_button'),
            onPressed: provider.isSaving ? null : () => _delete(workspace),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete field'),
          ),
        ],
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
        : 'Not recorded';
  }

  String _intendedUseLabel(String? value) => switch (value) {
    'grain' => 'Dry grain',
    'green_corn' => 'Green corn / fresh ears',
    'silage' => 'Silage',
    'seed' => 'Seed production',
    'other' => 'Other use',
    _ => 'Not recorded',
  };

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Not recorded';
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }
}

class RecentlyDeletedFieldsScreen extends StatelessWidget {
  const RecentlyDeletedFieldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<FieldRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Recently Deleted')),
      body: StreamBuilder<List<FieldWorkspaceRecord>>(
        stream: repository.watchRecentlyDeletedFieldWorkspaces(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Recently deleted fields could not load.'),
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
                child: Text(
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
                  subtitle: Text(_deletionLabel(workspace.field.updatedAt)),
                  trailing: TextButton(
                    key: ValueKey('restore_field_${workspace.field.id}'),
                    onPressed: () async {
                      await context.read<FieldWorkspaceProvider>().restoreField(
                        workspace.field.id,
                      );
                    },
                    child: const Text('Restore'),
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

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.note,
  });

  final String title;
  final IconData icon;
  final List<_DetailRow> rows;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final row in rows) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.label,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (note != null) ...[
              const Divider(),
              Text(
                note!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;
}
