part of 'assessment_results_screen.dart';

class _DamageScreeningSummary extends StatelessWidget {
  const _DamageScreeningSummary({required this.stats});
  final AssessmentEvidenceStats stats;

  @override
  Widget build(BuildContext context) {
    final screened = stats.primaryDenominator.toInt();
    final positive = stats.primaryNumerator.toInt();
    final negative = math.max(0, screened - positive);
    final remaining = math.max(0, stats.totalRecorded - screened);
    final rate = screened == 0 ? 0.0 : (positive / screened).clamp(0.0, 1.0);
    return Container(
      key: const Key('primary_metric_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8E7DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: AppText(
                  'Damage screening',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF183F32),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: AppWords.of(context).translate('About this result'),
                icon: const Icon(
                  Icons.info_outline,
                  size: 21,
                  color: Color(0xFF547568),
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const AppText('Damage screening'),
                    content: const AppText(
                      'The percentage of screened plants with damage detected by Model 1. Each plant is counted once. Plants without a screening result are excluded. Expert-reviewed severity is reported separately.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const AppText('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            screened == 0
                ? '—'
                : _formatPrimaryMetricValue('percent', rate * 100),
            style: const TextStyle(
              fontSize: 54,
              height: 1.05,
              letterSpacing: -2,
              fontWeight: FontWeight.w800,
              color: Color(0xFF183F32),
            ),
          ),
          const SizedBox(height: 8),
          AppText(
            screened == 0
                ? 'No screening results yet'
                : '$positive of $screened plants with damage detected',
            style: const TextStyle(fontSize: 14, color: Color(0xFF52665D)),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8EFEB),
              color: const Color(0xFFB57036),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ScreeningCount(
                  value: positive,
                  label: 'Damage detected',
                  color: const Color(0xFFB57036),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScreeningCount(
                  value: negative,
                  label: 'No damage detected',
                  color: const Color(0xFF47765F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE5ECE8)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _ScreeningMeta(
                icon: Icons.location_on_outlined,
                text: '${stats.stationStats.length} stations',
              ),
              _ScreeningMeta(
                icon: Icons.photo_library_outlined,
                text:
                    '${stats.stationStats.fold<int>(0, (sum, s) => sum + s.photoCount)} photos',
              ),
              if (remaining > 0)
                _ScreeningMeta(
                  icon: Icons.pending_outlined,
                  text: '$remaining not screened',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreeningCount extends StatelessWidget {
  const _ScreeningCount({
    required this.value,
    required this.label,
    required this.color,
  });
  final int value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          AppText(
            '$value',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: Color(0xFF263E32),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      AppText(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF617269)),
      ),
    ],
  );
}

class _ScreeningMeta extends StatelessWidget {
  const _ScreeningMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: const Color(0xFF708077)),
      const SizedBox(width: 5),
      AppText(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFF617269)),
      ),
    ],
  );
}

class _ScreeningStationTile extends StatelessWidget {
  const _ScreeningStationTile({required this.station, required this.onTap});
  final StationEvidenceStats station;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final count = station.assessableCount;
    final positive = station.damageCount;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFDCE6E0)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF3EF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AppText(
                      '${station.stationNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF265640),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Station ${station.stationNumber}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AppText(
                          'Block ${station.blockSequence} · ${station.photoCount} photos',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF738077),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    count == 0
                        ? '—'
                        : _formatPrimaryMetricValue(
                            'percent',
                            positive / count * 100,
                          ),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF244F3B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 19,
                    color: Color(0xFF839489),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: count == 0 ? 0 : (positive / count).clamp(0.0, 1.0),
                  minHeight: 5,
                  color: const Color(0xFFB57036),
                  backgroundColor: const Color(0xFFEDF1EE),
                ),
              ),
              const SizedBox(height: 8),
              AppText(
                count == 0
                    ? 'No damage-screening result'
                    : '$positive of $count plants with damage detected',
                style: const TextStyle(fontSize: 12, color: Color(0xFF66786C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverallInfestationHeroCard extends StatelessWidget {
  const _OverallInfestationHeroCard({
    required this.detail,
    required this.stats,
    required this.completed,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    if (stats.screeningMode) return _DamageScreeningSummary(stats: stats);
    final words = AppWords.of(context);
    final denominatorLabel = _primaryMetricDenominatorLabel(
      stats.primaryMetricCode,
      detail.assessment.growthStage,
    );
    final metricTitle = _primaryMetricTitle(stats.primaryMetricCode);
    final isZero = stats.isZeroDenominator;
    final metricValueText = _formatPrimaryMetricValue(
      stats.primaryUnit,
      stats.overallInfestationPercent,
    );
    final fractionText = isZero
        ? 'Unavailable'
        : '${_formatMetricCount(stats.primaryNumerator)} ${words.language == AppLanguage.filipino ? 'sa' : 'of'} '
              '${_formatMetricCount(stats.primaryDenominator)} ${words.translate(denominatorLabel)}';

    String? daBafsTitle;
    String? daBafsDetail;
    for (final m in detail.resultSummary.metrics) {
      if (m.metricCode == DatabaseCodes.daBafsMedianScore) {
        daBafsTitle = 'DA-BAFS median leaf-damage score';
        int? min;
        int? max;
        final dist = m.scoreDistribution;
        if (dist.isNotEmpty) {
          final sorted = dist.keys.toList()..sort();
          min = sorted.first;
          max = sorted.last;
        }
        final uncertain = m.uncertainScoreCount;
        final rangeLabel = min != null && max != null
            ? '${words.language == AppLanguage.filipino ? 'Saklaw ng naobserbahang score' : 'Observed score range'} $min–$max'
            : words.translate('Ordinal score');
        daBafsDetail = uncertain > 0
            ? '$rangeLabel · $uncertain ${words.translate('uncertain')}'
            : rangeLabel;
      }
    }

    return Container(
      key: const Key('primary_metric_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2FAF5), Colors.white],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E7DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  words.translate(metricTitle),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.info_outline,
                  color: Color(0xFF1F563F),
                  size: 21,
                ),
                tooltip: AppWords.of(context).translate('Explain this metric'),
                onPressed: () => _showMetricExplanation(
                  context,
                  metricTitle: metricTitle,
                  fractionText: fractionText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isZero) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'Unavailable',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  AppText(
                    'The combined denominator is zero.',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  AppText(
                    'No partial result is shown because the required plants could not be assessed.',
                    style: TextStyle(color: Color(0xFFB45309), fontSize: 13),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              metricValueText,
              style: const TextStyle(
                color: Color(0xFF152923),
                fontSize: 48,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              fractionText,
              style: const TextStyle(
                color: Color(0xFF20332C),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stats.primaryUnit == 'percent'
                  ? '${words.language == AppLanguage.filipino ? 'Nasampolang' : 'Sampled'} ${words.translate(metricTitle).toLowerCase()}'
                  : words.translate('Saved assessment result'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: Color(0xFFD8E7DE)),
            const SizedBox(height: 8),
            const AppText(
              'Based on saved assessment data. Not a live reading.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
            if (daBafsTitle != null && daBafsDetail != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: Color(0xFF2E7D32),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          words.translate(daBafsTitle),
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          daBafsDetail,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showMetricExplanation(
    BuildContext context, {
    required String metricTitle,
    required String fractionText,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppWords.of(context).translate(metricTitle)),
        content: AppText(
          '$fractionText\n\n'
          'This is the saved descriptive whole-assessment metric for the current growth stage. '
          'WormWise does not treat this value as an automatic pesticide or treatment threshold.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('OK'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. TAB 1: FAW EVIDENCE BREAKDOWN (4 CARDS ROW)
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenceBreakdownRow extends StatelessWidget {
  const _EvidenceBreakdownRow({required this.stats});

  final AssessmentEvidenceStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('recorded_evidence_4_across'),
      children: [
        Expanded(
          child: _EvidenceItemCard(
            title: 'Damage',
            count: stats.damageCount,
            icon: Icons.image_search_outlined,
            iconColor: const Color(0xFF398752),
            bgColor: const Color(0xFFE8F4EB),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EvidenceItemCard(
            title: stats.screeningMode ? 'Frass hints' : 'Frass',
            display: stats.screeningMode && stats.highlightedPlants == 0
                ? 'Not assessed'
                : null,
            count: stats.frassCount,
            icon: Icons.blur_on_rounded,
            iconColor: const Color(0xFF8A7058),
            bgColor: const Color(0xFFF4F0EA),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EvidenceItemCard(
            title: stats.screeningMode ? 'Larva hints' : 'Larva',
            display: stats.screeningMode && stats.highlightedPlants == 0
                ? 'Not assessed'
                : null,
            count: stats.larvaCount,
            icon: Icons.bug_report_outlined,
            iconColor: const Color(0xFF668936),
            bgColor: const Color(0xFFEDF4E8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EvidenceItemCard(
            title: stats.screeningMode ? 'Egg hints' : 'Eggs',
            display: stats.screeningMode && stats.highlightedPlants == 0
                ? 'Not assessed'
                : null,
            count: stats.eggCount,
            icon: Icons.bubble_chart_outlined,
            iconColor: const Color(0xFF8970BA),
            bgColor: const Color(0xFFF1EDF8),
          ),
        ),
      ],
    );
  }
}

class _EvidenceItemCard extends StatelessWidget {
  const _EvidenceItemCard({
    required this.title,
    this.display,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });

  final String title;
  final String? display;
  final int count;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD8E7DE)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          AppText(
            display ?? '$count',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. TAB 1: FAW EVIDENCE BY TYPE BAR CHART (fl_chart)
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenceTypeBarChart extends StatelessWidget {
  const _EvidenceTypeBarChart({required this.stats});

  final AssessmentEvidenceStats stats;

  @override
  Widget build(BuildContext context) {
    final maxY = math.max<double>(
      10,
      [
            stats.damageCount.toDouble(),
            stats.frassCount.toDouble(),
            stats.larvaCount.toDouble(),
            stats.eggCount.toDouble(),
          ].reduce(math.max) *
          1.3,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E9E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart_rounded, color: Color(0xFF2E7D32), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: AppText(
                  'Evidence categories',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 142,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1E293B),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final labels = ['Damage', 'Frass', 'Larva', 'Egg'];
                      return BarTooltipItem(
                        '${labels[group.x]}: ${rod.toY.toInt()} recorded observations',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const AppText(
                      'Records',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxY > 20 ? 10 : 5,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildBottomTitle(idx),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 20 ? 10 : 5,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _makeBarGroup(
                    0,
                    stats.damageCount.toDouble(),
                    const Color(0xFF398752),
                  ),
                  _makeBarGroup(
                    1,
                    stats.frassCount.toDouble(),
                    const Color(0xFF8A7058),
                  ),
                  _makeBarGroup(
                    2,
                    stats.larvaCount.toDouble(),
                    const Color(0xFFE2AC42),
                  ),
                  _makeBarGroup(
                    3,
                    stats.eggCount.toDouble(),
                    const Color(0xFF8970BA),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTitle(int index) {
    final icons = [
      Icons.image_search_outlined,
      Icons.blur_on_rounded,
      Icons.bug_report_outlined,
      Icons.bubble_chart_outlined,
    ];
    final labels = ['Damage', 'Frass', 'Larva', 'Egg'];
    final colors = [
      const Color(0xFF398752),
      const Color(0xFF8A7058),
      const Color(0xFFE2AC42),
      const Color(0xFF8970BA),
    ];
    if (index < 0 || index >= labels.length) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icons[index], size: 12, color: colors[index]),
        const SizedBox(width: 3),
        Text(
          labels[index],
          style: TextStyle(
            color: colors[index],
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  BarChartGroupData _makeBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      showingTooltipIndicators: [],
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 36,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 0,
            color: const Color(0xFFF1F5F9),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ASSESSMENT RESULT DETAILS SCREEN (BACKWARD COMPATIBLE WRAPPER)
// ─────────────────────────────────────────────────────────────────────────────
