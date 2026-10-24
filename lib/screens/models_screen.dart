import '../localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/local/app_database.dart';
import '../services/computer_vision/detection_preferences.dart';
import '../localization/app_text.dart';
import '../theme/app_colors.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const AppText('Models')),
    body: const _ModelsUsedTab(),
  );
}

class _ModelsUsedTab extends StatelessWidget {
  const _ModelsUsedTab();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: AppText(
          'IMAGE MODELS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: Color(0xFF748178),
          ),
        ),
      ),
      const _ModelPanel(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              _ModelIcon(Icons.image_search_outlined),
              SizedBox(width: 14),
              Expanded(
                child: _ModelTitle(
                  number: 'MODEL 1',
                  title: 'Damage screening',
                ),
              ),
              SizedBox(width: 8),
              _StatusPill('Always on'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      const _ModelTwoSetting(),
      const SizedBox(height: 28),
      const Row(
        children: [
          Expanded(
            child: AppText(
              'ADVISORY',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: Color(0xFF748178),
              ),
            ),
          ),
          AppText(
            'Google Gemini',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF54685C),
            ),
          ),
        ],
      ),
    ],
  );
}

class _ModelPanel extends StatelessWidget {
  const _ModelPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDDE7E0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _ModelIcon extends StatelessWidget {
  const _ModelIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFFEDF4EF),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, size: 23, color: const Color(0xFF28563E)),
  );
}

class _ModelTitle extends StatelessWidget {
  const _ModelTitle({required this.number, required this.title});
  final String number, title;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        number,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: Color(0xFF7B8B80),
        ),
      ),
      const SizedBox(height: 5),
      AppText(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF233C2D),
        ),
      ),
    ],
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF4EF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: AppText(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Color(0xFF446C50),
      ),
    ),
  );
}

class _ModelTwoSetting extends StatefulWidget {
  const _ModelTwoSetting();
  @override
  State<_ModelTwoSetting> createState() => _ModelTwoSettingState();
}

class _ModelTwoSettingState extends State<_ModelTwoSetting> {
  final _infoKey = GlobalKey<TooltipState>();
  bool _ready = false;
  bool _saving = false;
  Stream<({int count, bool? enabled})>? _lockStream;
  @override
  void initState() {
    super.initState();
    DetectionPreferences.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lockStream ??= DetectionPreferences.watchLock(context.read<AppDatabase>());
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<({int count, bool? enabled})>(
    stream: _lockStream,
    builder: (context, lock) => ValueListenableBuilder<bool>(
      valueListenable: DetectionPreferences.enabled,
      builder: (context, defaultEnabled, _) {
        final enabled = lock.data?.enabled ?? defaultEnabled;
        final locked = (lock.data?.count ?? 0) > 0;
        return _ModelPanel(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 10, 16),
                child: Row(
                  children: [
                    const _ModelIcon(Icons.center_focus_strong),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: _ModelTitle(
                        number: 'MODEL 2',
                        title: 'Evidence detection',
                      ),
                    ),
                    Tooltip(
                      key: _infoKey,
                      message:
                          'Suggests damage, frass, egg and larva locations. Detections may be incorrect. The setting is fixed for each assessment.',
                      triggerMode: TooltipTriggerMode.manual,
                      child: IconButton(
                        tooltip: AppWords.of(
                          context,
                        ).translate('About Model 2'),
                        onPressed: () =>
                            _infoKey.currentState?.ensureTooltipVisible(),
                        icon: const Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Color(0xFF6B7F71),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
                indent: 18,
                endIndent: 18,
                color: Color(0xFFEBF0EC),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 7, 12, 7),
                child: Row(
                  children: [
                    if (locked) ...[
                      const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: Color(0xFF708077),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: AppText(
                        locked
                            ? 'Locked for this assessment'
                            : 'Enable Model 2',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF52685A),
                        ),
                      ),
                    ),
                    Switch(
                      value: enabled,
                      activeTrackColor: const Color(0xFF28563E),
                      onChanged:
                          !_ready ||
                              _saving ||
                              !lock.hasData ||
                              lock.hasError ||
                              locked
                          ? null
                          : (value) async {
                              setState(() => _saving = true);
                              try {
                                await DetectionPreferences.setEnabled(
                                  value,
                                  database: context.read<AppDatabase>(),
                                );
                              } catch (_) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: AppText(
                                        'Could not change the model setting.',
                                      ),
                                    ),
                                  );
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                    ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFFF5F8F5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: Color(0xFF819286),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        'Pest identification',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF576E5E),
                        ),
                      ),
                    ),
                    AppText(
                      'On larva detection',
                      style: TextStyle(fontSize: 11, color: Color(0xFF809085)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
