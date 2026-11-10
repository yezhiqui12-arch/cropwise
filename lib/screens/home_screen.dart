import 'package:flutter/scheduler.dart';
import '../localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/field_workspace_provider.dart';
import 'create_field_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/hero_assessment_card.dart';
import '../widgets/home_dashboard_sections.dart';
import '../widgets/tab_loading_skeleton.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.backgroundStartupEnabled = true});

  final bool backgroundStartupEnabled;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _deferredContentReady = false;
  bool _startupScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.backgroundStartupEnabled) _scheduleDeferredContent();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.backgroundStartupEnabled &&
        widget.backgroundStartupEnabled) {
      _scheduleDeferredContent();
    }
  }

  void _scheduleDeferredContent() {
    if (_startupScheduled || _deferredContentReady) return;
    _startupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SchedulerBinding.instance.scheduleTask<void>(() {
        if (mounted) setState(() => _deferredContentReady = true);
      }, Priority.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<FieldWorkspaceProvider>();

    if (fields.isLoading) {
      return const TabLoadingSkeleton(type: TabSkeletonType.home);
    }

    if (fields.activeWorkspace == null) {
      return const _NewUserHomeState();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeActiveFieldHero(enableMap: _deferredContentReady),
            const SizedBox(height: 14),

            const HeroAssessmentCard(),
            const SizedBox(height: 14),
            const HomeRecentAssessmentsCard(),
            if (_deferredContentReady)
              const HomeEvidenceNotice()
            else ...[
              const SizedBox(height: 14),
              const _DeferredHomeSection(
                icon: Icons.show_chart_rounded,
                label: 'Evidence trend will load shortly',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeferredHomeSection extends StatelessWidget {
  const _DeferredHomeSection({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 104,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.surfaceVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}

class _NewUserHomeState extends StatelessWidget {
  const _NewUserHomeState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/home_first_field_onboarding.png',
                      width: 250,
                      height: 190,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 4),
                    const AppText(
                      'Welcome to Cropwise',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AppText(
                      'Add your first maize field to see field conditions, plan an assessment, and keep FAW records together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _GettingStartedSteps(),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        key: const Key('empty_home_add_field_button'),
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateFieldScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const AppText('Add your first maize field'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GettingStartedSteps extends StatelessWidget {
  const _GettingStartedSteps();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(
        child: _SetupStep(
          number: '1',
          icon: Icons.agriculture_outlined,
          label: 'Add field',
        ),
      ),
      _StepConnector(),
      Expanded(
        child: _SetupStep(
          number: '2',
          icon: Icons.gesture_rounded,
          label: 'Draw boundary',
        ),
      ),
      _StepConnector(),
      Expanded(
        child: _SetupStep(
          number: '3',
          icon: Icons.fact_check_outlined,
          label: 'Assess',
        ),
      ),
    ],
  );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.icon,
    required this.label,
  });

  final String number;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary, size: 23),
      ),
      const SizedBox(height: 7),
      AppText(
        '$number. $label',
        textAlign: TextAlign.center,
        maxLines: 2,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 1.5,
    margin: const EdgeInsets.only(bottom: 24),
    color: AppColors.outlineVariant,
  );
}
