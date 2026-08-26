import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AccessibleChoiceOption<T> {
  const AccessibleChoiceOption({
    required this.value,
    required this.label,
    this.description,
    this.assetPath,
    this.visualGroup,
    this.imageCaption,
  });

  final T value;
  final String label;
  final String? description;
  final String? assetPath;

  /// Consecutive choices with the same value share one representative image.
  final String? visualGroup;
  final String? imageCaption;
}

class AccessibleChoiceField<T> extends StatelessWidget {
  const AccessibleChoiceField({
    super.key,
    required this.label,
    required this.sheetTitle,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hintText = 'Tap to select',
    this.helperText,
    this.leadingIcon,
    this.showImages = false,
  });

  final String label;
  final String sheetTitle;
  final List<AccessibleChoiceOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String hintText;
  final String? helperText;
  final IconData? leadingIcon;
  final bool showImages;

  AccessibleChoiceOption<T>? get _selectedOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  List<_ChoiceGroup<T>> _choiceGroups() {
    final groups = <_ChoiceGroup<T>>[];
    for (var index = 0; index < options.length; index++) {
      final option = options[index];
      final key = showImages
          ? option.visualGroup ?? '__single_$index'
          : '__single_$index';
      if (groups.isNotEmpty && groups.last.key == key) {
        groups.last.options.add(option);
      } else {
        groups.add(
          _ChoiceGroup(
            key: key,
            options: [option],
            assetPath: showImages ? option.assetPath : null,
            imageCaption: showImages ? option.imageCaption : null,
          ),
        );
      }
    }
    return groups;
  }

  Future<void> _openChoices(BuildContext context) async {
    if (onChanged == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    final groups = _choiceGroups();
    final selected = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: showImages ? 0.92 : 0.74,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sheetTitle,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (showImages)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Photos show representative stage groups. Use the description to check collars, tassels, silks, or kernels before selecting.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _ChoiceGroupCard<T>(
                    group: group,
                    selectedValue: value,
                    onSelected: (choice) => Navigator.pop(sheetContext, choice),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) onChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    final enabled = onChanged != null;
    return Semantics(
      button: enabled,
      label: label,
      value: selected?.label ?? hintText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => _openChoices(context) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 76),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: enabled
                      ? Colors.transparent
                      : AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: enabled
                        ? AppColors.textSecondary
                        : AppColors.outlineVariant,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (leadingIcon != null) ...[
                      Icon(
                        leadingIcon,
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            selected?.label ?? hintText,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.25,
                              fontWeight: selected == null
                                  ? FontWeight.normal
                                  : FontWeight.w700,
                              color: selected == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      enabled ? Icons.keyboard_arrow_down : Icons.lock_outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (helperText != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                helperText!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceGroup<T> {
  _ChoiceGroup({
    required this.key,
    required this.options,
    this.assetPath,
    this.imageCaption,
  });

  final String key;
  final List<AccessibleChoiceOption<T>> options;
  final String? assetPath;
  final String? imageCaption;
}

class _ChoiceGroupCard<T> extends StatelessWidget {
  const _ChoiceGroupCard({
    required this.group,
    required this.selectedValue,
    required this.onSelected,
  });

  final _ChoiceGroup<T> group;
  final T? selectedValue;
  final ValueChanged<T> onSelected;

  Future<void> _showImagePreview(BuildContext context, String assetPath) {
    final title = group.imageCaption ?? group.options.first.label;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 64,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            key: const ValueKey('choice_image_preview_panel'),
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: screen.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close image',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ColoredBox(
                    color: Colors.black,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.asset(assetPath, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Pinch to zoom. Drag while zoomed to inspect the plant.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final containsSelection = group.options.any(
      (option) => option.value == selectedValue,
    );
    final assetPath = group.assetPath;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: containsSelection
              ? AppColors.primary
              : AppColors.outlineVariant,
          width: containsSelection ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (assetPath != null)
            Semantics(
              button: true,
              label: 'Open and zoom ${group.imageCaption ?? 'stage photo'}',
              child: InkWell(
                key: ValueKey('choice_image_${group.key}'),
                onTap: () => _showImagePreview(context, assetPath),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppColors.surfaceContainer,
                          child: Center(child: Icon(Icons.image_not_supported)),
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in, color: Colors.white, size: 18),
                          SizedBox(width: 5),
                          Text(
                            'Tap to enlarge',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (group.imageCaption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                group.imageCaption!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          for (var index = 0; index < group.options.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _ChoiceRow<T>(
              option: group.options[index],
              selected: group.options[index].value == selectedValue,
              onSelected: onSelected,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final AccessibleChoiceOption<T> option;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(option.value),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      option.description!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
