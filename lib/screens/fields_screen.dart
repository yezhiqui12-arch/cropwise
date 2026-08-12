import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';
import 'create_field_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Maize Fields')),
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
          onTap: () {
            provider.selectField(workspace.field.id);
            Navigator.pop(context);
          },
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
              'Register a field so its crop cycles, assessments, boundaries, and reports stay connected.',
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
  });

  final FieldWorkspaceRecord workspace;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final spatialState = workspace.spatialState;

    return Card(
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
