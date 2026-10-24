import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_language.dart';
import '../theme/app_colors.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  bool _saving = false;

  Future<void> _select(AppLanguage language) async {
    final controller = context.read<AppLanguageController>();
    if (_saving || controller.language == language) return;
    setState(() => _saving = true);
    try {
      await controller.setLanguage(language);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.language == AppLanguage.filipino
                  ? 'Hindi na-save ang wika. Subukan muli.'
                  : 'Could not save language. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<AppLanguageController>().language;
    final filipino = selected == AppLanguage.filipino;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(filipino ? 'Wika' : 'Language')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 20),
              child: Text(
                filipino
                    ? 'Piliin ang wika ng app.'
                    : 'Choose your app language.',
                style: const TextStyle(color: Color(0xFF647B6B), fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                filipino ? 'WIKA NG APP' : 'APP LANGUAGE',
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.3,
                  color: Color(0xFF78877D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFDDE7E0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _LanguageOption(
                    key: const Key('language_english_option'),
                    title: 'English',
                    subtitle: 'English',
                    monogram: 'EN',
                    selected: selected == AppLanguage.english,
                    enabled: !_saving,
                    onTap: () => _select(AppLanguage.english),
                  ),
                  const Divider(
                    height: 1,
                    indent: 76,
                    endIndent: 16,
                    color: Color(0xFFEDF1EE),
                  ),
                  _LanguageOption(
                    key: const Key('language_filipino_option'),
                    title: 'Filipino',
                    subtitle: 'Wikang Filipino',
                    monogram: 'FIL',
                    selected: selected == AppLanguage.filipino,
                    enabled: !_saving,
                    onTap: () => _select(AppLanguage.filipino),
                  ),
                ],
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.monogram,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String monogram;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFE5F1E7)
                  : const Color(0xFFF2F5F2),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              monogram,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF2D5940)
                    : const Color(0xFF617A68),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF293D31),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF78877D),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? const Color(0xFF3E7B53) : const Color(0xFFB7C5BA),
            size: 22,
          ),
        ],
      ),
    ),
  );
}
