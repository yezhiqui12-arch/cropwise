import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/assessment_state.dart';
import '../providers/wormwise_provider.dart';
import '../theme/app_colors.dart';

class ResultSummaryCard extends StatelessWidget {
  const ResultSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WormWiseProvider>(context);

    switch (provider.currentState) {
      case AssessmentState.ready:
        return _buildReadyPreviousSummary(context);
      case AssessmentState.inProgress:
        return _buildOngoingSummary(context, provider);
      case AssessmentState.completed:
        return _buildCompletedSummary(context, provider);
    }
  }

  // State 1 (Ready / No Assessment Today): Shows Previous Latest Assessment Card from zip2
  Widget _buildReadyPreviousSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Stable Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Latest Assessment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceVariant),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.remove,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Stable',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Ring Chart (35% Moderate)
          Center(
            child: SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 40,
                      startDegreeOffset: 270,
                      sections: [
                        PieChartSectionData(
                          color: AppColors.moderateSeverityRing,
                          value: 35,
                          radius: 12,
                          showTitle: false,
                        ),
                        PieChartSectionData(
                          color: AppColors.surfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                          value: 65,
                          radius: 12,
                          showTitle: false,
                        ),
                      ],
                    ),
                  ),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '35%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.moderateSeverityRing,
                        ),
                      ),
                      Text(
                        'Moderate',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Legend Indicators
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 4, backgroundColor: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Low',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 4,
                    backgroundColor: AppColors.moderateSeverityRing,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Mod',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 4,
                    backgroundColor: AppColors.severeSeverityRing,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'High',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Footer Text
          const Center(
            child: Column(
              children: [
                Text(
                  'Based on previous assessment',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Last assessed: 2 days ago',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // State 2: Today's Result Summary (Completed)
  Widget _buildCompletedSummary(
    BuildContext context,
    WormWiseProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Today\'s Result Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  'Share',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Left Donut Chart Ring (28% LOW)
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 36,
                        startDegreeOffset: 270,
                        sections: [
                          PieChartSectionData(
                            color: const Color(0xFF1B5E20),
                            value: provider.infestationPercent.toDouble(),
                            radius: 12,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: AppColors.surfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                            value: (100 - provider.infestationPercent)
                                .toDouble(),
                            radius: 12,
                            showTitle: false,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${provider.infestationPercent}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Text(
                          'LOW',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Right 2x2 Metric Grid
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Healthy',
                            value: '${provider.completedHealthy}',
                            valueColor: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Suspected FAW',
                            value: '${provider.completedSuspected}',
                            valueColor: AppColors.severeSeverityRing,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Damage',
                            value: provider.damageSeverity,
                            valueColor: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Est. Time',
                            value: provider.estScoutTime,
                            valueColor: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // State 2 (In Progress): Ongoing Assessment Summary
  Widget _buildOngoingSummary(BuildContext context, WormWiseProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ongoing Assessment Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 32,
                        sections: [
                          PieChartSectionData(
                            color: AppColors.primary,
                            value:
                                (provider.currentStops / provider.totalStops) *
                                100,
                            radius: 10,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: AppColors.surfaceVariant,
                            value:
                                (1 -
                                    (provider.currentStops /
                                        provider.totalStops)) *
                                100,
                            radius: 10,
                            showTitle: false,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${provider.currentStops}/${provider.totalStops}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Text(
                          'STOPS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _buildSummaryRow(
                      'Photos Captured',
                      '${provider.photosCaptured}',
                      false,
                    ),
                    const Divider(height: 12),
                    _buildSummaryRow(
                      'Healthy Plants',
                      '${provider.healthyCount}',
                      false,
                    ),
                    const Divider(height: 12),
                    _buildSummaryRow(
                      'Suspected FAW',
                      '${provider.suspectedFawCount}',
                      true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Started Today, 9:14 AM',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isError) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isError
                ? AppColors.severeSeverityRing
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
