import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';

class AccountRecoveryView extends StatelessWidget {
  const AccountRecoveryView({
    super.key,
    required this.state,
    required this.detail,
    this.onRetry,
    this.onContinueWithLocalData,
  });

  final AccountRecoveryState state;
  final String detail;
  final VoidCallback? onRetry;
  final VoidCallback? onContinueWithLocalData;

  @override
  Widget build(BuildContext context) {
    final failed = state == AccountRecoveryState.error;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed)
                  const Icon(Icons.cloud_off_outlined, size: 48)
                else
                  const CircularProgressIndicator(
                    key: Key('account_recovery_progress'),
                  ),
                const SizedBox(height: 24),
                AppText(
                  failed
                      ? 'Account history is not ready'
                      : 'Restoring your account',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: AppText(detail, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                const AppText(
                  'Your fields, assessments, chats and settings load first. Photos continue in the background.',
                  textAlign: TextAlign.center,
                ),
                if (failed) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('retry_account_recovery'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const AppText('Retry restoration'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('continue_with_local_account_data'),
                    onPressed: onContinueWithLocalData,
                    child: const AppText(
                      "Continue with this phone's saved data",
                    ),
                  ),
                  const AppText(
                    'Cloud history may still be missing until restoration finishes.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
