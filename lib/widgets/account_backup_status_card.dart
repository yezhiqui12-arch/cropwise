import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_text.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';

class AccountBackupStatusCard extends StatefulWidget {
  const AccountBackupStatusCard({super.key, this.compact = false});
  final bool compact;

  @override
  State<AccountBackupStatusCard> createState() =>
      _AccountBackupStatusCardState();
}

class _AccountBackupStatusCardState extends State<AccountBackupStatusCard>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF205A36);
  static const _deep = Color(0xFF143D29);
  static const _muted = Color(0xFF667268);

  bool _checking = false;
  late final AnimationController _loading = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void dispose() {
    _loading.dispose();
    super.dispose();
  }

  Future<void> _verify(WormWiseCloudSyncService sync) async {
    setState(() => _checking = true);
    var verified = false;
    try {
      verified = await sync.verifyAccountBackup();
    } catch (_) {
      // The service retains retryable backup state.
    }
    if (!mounted) return;
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          verified && sync.backupVerified
              ? 'Saved to your account. Backup verified.'
              : (sync.lastError ??
                    'Backup has not finished. Tap Verify backup to retry.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<WormWiseCloudSyncService?>();
    if (sync == null || !sync.hasRegisteredAccount) {
      return const SizedBox.shrink();
    }

    final verified = sync.backupVerified;
    final syncing = _checking || sync.state == WormWiseCloudSyncState.syncing;
    if (syncing && !_loading.isAnimating) {
      _loading.repeat();
    } else if (!syncing && _loading.isAnimating) {
      _loading.stop();
    }
    final empty =
        sync.recordsReady &&
        !sync.hasBackupData &&
        !syncing &&
        sync.state != WormWiseCloudSyncState.error;
    final error = sync.state == WormWiseCloudSyncState.error && !syncing;
    final title = verified
        ? 'Saved to your account'
        : syncing
        ? 'Checking your backup'
        : error
        ? 'Backup needs attention'
        : empty
        ? 'No data to back up yet'
        : 'Backup not yet verified';
    var detail = verified
        ? 'Your records and photos are backed up.'
        : syncing
        ? 'Checking records and photos…'
        : empty
        ? 'New records will be backed up automatically.'
        : (sync.lastError ?? 'Verify your saved records and photos.');
    final time = sync.lastVerifiedAt?.toLocal();
    if (verified && time != null) {
      final locale = MaterialLocalizations.of(context);
      detail =
          'Verified ${locale.formatShortDate(time)} at ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
    }

    final accent = error ? const Color(0xFFA2463B) : _green;
    return Container(
      key: const Key('account_backup_status'),
      margin: EdgeInsets.symmetric(
        vertical: widget.compact ? 4 : 12,
        horizontal: widget.compact ? 12 : 0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E9E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: error
                        ? const Color(0xFFF9EBE9)
                        : const Color(0xFFEAF2EA),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: syncing
                        ? RotationTransition(
                            turns: _loading,
                            child: Icon(
                              Icons.sync_rounded,
                              color: accent,
                              size: 23,
                            ),
                          )
                        : Icon(
                            error
                                ? Icons.cloud_off_outlined
                                : verified
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_outlined,
                            color: accent,
                            size: 23,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        title,
                        style: const TextStyle(
                          color: _deep,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        detail,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (syncing)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: const Color(0xFFEAF2EA),
              color: accent,
            ),
          if (!widget.compact && !syncing) ...[
            const Divider(height: 1, color: Color(0xFFE1E9E1)),
            InkWell(
              key: const Key('verify_account_backup'),
              onTap: () => _verify(sync),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      AppText(
                        'Verify backup',
                        style: const TextStyle(
                          color: _green,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: _green,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
