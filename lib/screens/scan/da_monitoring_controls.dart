import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../models/da_monitoring.dart';
import '../../theme/app_colors.dart';
import 'scouting_ui.dart';

Future<List<String>?> showDaNaturalEnemiesDialog(
  BuildContext context, {
  List<String>? initial,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _NaturalEnemiesDialog(initial: initial),
);

class _NaturalEnemiesDialog extends StatefulWidget {
  const _NaturalEnemiesDialog({this.initial});
  final List<String>? initial;
  @override
  State<_NaturalEnemiesDialog> createState() => _NaturalEnemiesDialogState();
}

class _NaturalEnemiesDialogState extends State<_NaturalEnemiesDialog> {
  late Set<String> selected = {...?widget.initial};
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: const AppText('Likas na mga kaaway'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText('What did you observe during this walk?'),
          for (final entry in daEnemyLabels.entries.where(
            (e) => e.key != 'not_recorded',
          ))
            CheckboxListTile(
              key: Key('da_enemy_${entry.key}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: selected.contains(entry.key)
                  ? const Color(0xFFEAF3E8)
                  : Colors.white,
              controlAffinity: ListTileControlAffinity.trailing,
              title: AppText(entry.value),
              value: selected.contains(entry.key),
              onChanged: (checked) => setState(() {
                if (checked != true) {
                  selected.remove(entry.key);
                  return;
                }
                if (['none', 'unknown'].contains(entry.key)) {
                  selected = {entry.key};
                } else {
                  selected.removeAll(['none', 'unknown', 'not_recorded']);
                  selected.add(entry.key);
                }
              }),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, ['not_recorded']),
        child: const AppText('Skip'),
      ),
      FilledButton(
        key: const Key('da_enemy_continue'),
        onPressed: selected.isEmpty
            ? null
            : () => Navigator.pop(context, selected.toList()),
        child: const AppText('Continue'),
      ),
    ],
  );
}

/// Optional report corrections. Model output remains visible and unchanged.
class DaPlantCorrectionPanel extends StatefulWidget {
  const DaPlantCorrectionPanel({
    super.key,
    required this.finding,
    required this.initial,
    required this.onSave,
    this.initiallyExpanded = false,
    this.onClose,
  });
  final DaPlantFinding finding;
  final Map<String, bool?> initial;
  final Future<void> Function(Map<String, bool?>) onSave;
  final bool initiallyExpanded;
  final VoidCallback? onClose;
  @override
  State<DaPlantCorrectionPanel> createState() => _DaPlantCorrectionPanelState();
}

class _DaPlantCorrectionPanelState extends State<DaPlantCorrectionPanel> {
  late Map<String, bool?> values = Map.from(widget.initial);
  bool saving = false;
  String? status;
  @override
  Widget build(BuildContext context) {
    if (widget.initiallyExpanded && widget.onClose != null) {
      return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Correct observations',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        AppText(
                          'Optional · Auto keeps the model result',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close corrections',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(children: _choices()),
              ),
            ),
            _footer(),
          ],
        ),
      );
    }
    return ExpansionTile(
      initiallyExpanded: widget.initiallyExpanded,
      key: const Key('da_optional_correction'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      title: const AppText('Correct report observations'),
      subtitle: const AppText('Optional'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [..._choices(), _footer()],
    );
  }

  List<Widget> _choices() => [
    for (final entry in daSignLabels.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ScoutingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                entry.value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              AppText(
                'Model: ${widget.finding.values[entry.key] == null
                    ? 'Not assessed'
                    : widget.finding.values[entry.key] == true
                    ? 'Detected'
                    : 'Not detected'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final large = MediaQuery.textScalerOf(context).scale(14) > 22;
                  final options = <(String, String, bool?)>[
                    ('auto', 'Auto', null),
                    ('yes', 'Present', true),
                    ('no', 'Absent', false),
                  ];
                  final buttons = [
                    for (final option in options)
                      Padding(
                        padding: EdgeInsets.only(
                          right: large ? 0 : 6,
                          bottom: large ? 6 : 0,
                        ),
                        child: OutlinedButton(
                          key: Key('da_correct_${entry.key}_${option.$1}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            backgroundColor: values[entry.key] == option.$3
                                ? AppColors.primary
                                : Colors.white,
                            foregroundColor: values[entry.key] == option.$3
                                ? Colors.white
                                : AppColors.primary,
                            side: BorderSide(
                              color: values[entry.key] == option.$3
                                  ? AppColors.primary
                                  : const Color(0xFFDCE5D9),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: saving
                              ? null
                              : () => setState(() {
                                  values[entry.key] = option.$3;
                                  status = null;
                                }),
                          child: AppText(option.$2),
                        ),
                      ),
                  ];
                  return large
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: buttons,
                        )
                      : Row(
                          children: [
                            for (final button in buttons)
                              Expanded(child: button),
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ),
  ];

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE1E8DF))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppText(
              status!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        Row(
          children: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => setState(() {
                      values.clear();
                      status = null;
                    }),
              child: const AppText('Reset'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('da_save_correction'),
                onPressed: saving
                    ? null
                    : () async {
                        setState(() {
                          saving = true;
                          status = null;
                        });
                        try {
                          await widget.onSave(Map.from(values));
                          if (mounted) setState(() => status = 'Saved');
                        } catch (_) {
                          if (mounted)
                            setState(
                              () => status = 'Could not save. Try again.',
                            );
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const AppText('Save observations'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
