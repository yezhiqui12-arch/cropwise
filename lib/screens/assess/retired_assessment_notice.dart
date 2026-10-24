import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_text.dart';
import '../../providers/field_workspace_provider.dart';
import '../assessment_setup_screen.dart';

/// Blocks retired records before their results or scouting actions are built.
class RetiredAssessmentNotice extends StatefulWidget {
  const RetiredAssessmentNotice({super.key, required this.fieldId});

  final String fieldId;

  static const message =
      'This assessment used an outdated scouting method and is no longer '
      'supported. Please conduct a new assessment using the current guidelines: '
      '20 plants per sampling block.';

  @override
  State<RetiredAssessmentNotice> createState() =>
      _RetiredAssessmentNoticeState();
}

class _RetiredAssessmentNoticeState extends State<RetiredAssessmentNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showNotice());
    });
  }

  Future<void> _showNotice() async {
    final startNew = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('retired_assessment_dialog'),
        scrollable: true,
        title: const AppText('Outdated assessment'),
        content: const AppText(RetiredAssessmentNotice.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const AppText('Start new assessment'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (startNew == true) {
      final fields = context.read<FieldWorkspaceProvider>();
      if (fields.workspaces.any((item) => item.field.id == widget.fieldId)) {
        fields.selectField(widget.fieldId);
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => const AssessmentSetupScreen()),
      );
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppText(
              RetiredAssessmentNotice.message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Keep the record blocked even if there is no previous route.
            OutlinedButton(
              onPressed: _showNotice,
              child: const AppText('Start new assessment'),
            ),
          ],
        ),
      ),
    ),
  );
}
