import 'dart:async';
import '../localization/app_language.dart';
import '../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../services/recent_weather_service.dart';
import '../theme/app_colors.dart';

class LiveFieldConditionsCard extends StatefulWidget {
  const LiveFieldConditionsCard({super.key, this.weatherService});

  final OpenMeteoCurrentWeatherService? weatherService;

  @override
  State<LiveFieldConditionsCard> createState() =>
      _LiveFieldConditionsCardState();
}

class _LiveFieldConditionsCardState extends State<LiveFieldConditionsCard> {
  String? _fieldKey;
  CurrentFieldWeather? _weather;
  String? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = context.watch<FieldWorkspaceProvider>().activeWorkspace;
    final key = workspace == null
        ? null
        : '${workspace.field.id}:${workspace.boundary?.id}';
    if (key == _fieldKey) return;
    _fieldKey = key;
    _weather = null;
    _error = null;
    if (workspace != null) unawaited(_refresh(workspace));
  }

  Future<void> _refresh(FieldWorkspaceRecord workspace) async {
    final coordinates = resolveRecentWeatherCoordinates(
      storedLatitude: workspace.boundary?.centroidLatitude,
      storedLongitude: workspace.boundary?.centroidLongitude,
      boundaryGeoJson: workspace.boundary?.geometryGeojson ?? '',
    );
    if (coordinates == null) {
      if (mounted) {
        setState(() => _error = 'Add a field boundary to load weather.');
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await (widget.weatherService ??
                  const OpenMeteoCurrentWeatherService())
              .current(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
              );
      if (!mounted ||
          _fieldKey != '${workspace.field.id}:${workspace.boundary?.id}') {
        return;
      }
      setState(() => _weather = result);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Current weather could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<FieldWorkspaceProvider>().activeWorkspace;
    final weather = _weather;
    return Container(
      key: const Key('field_conditions_card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 15),
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'Field Conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    AppText(
                      '${_location(workspace)}  •  ${weather == null
                          ? _loading
                                ? 'Updating…'
                                : 'Live weather'
                          : _updated(weather.observedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 38,
                child: IconButton(
                  tooltip: AppWords.of(
                    context,
                  ).translate('Refresh field conditions'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: workspace == null || _loading
                      ? null
                      : () => _refresh(workspace),
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (weather != null)
            SizedBox(
              height: 76,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: _Temperature(weather: weather)),
                  const _VerticalDivider(),
                  Expanded(
                    flex: 9,
                    child: _Condition(
                      icon: Icons.water_drop,
                      color: const Color(0xFF1687B5),
                      label: 'Soil Moisture',
                      value: weather.soilMoisture == null
                          ? 'Unavailable'
                          : '${(weather.soilMoisture! * 100).round()}%',
                    ),
                  ),
                  const _VerticalDivider(),
                  Expanded(
                    flex: 9,
                    child: _Condition(
                      icon: Icons.agriculture_outlined,
                      color: AppColors.primary,
                      label: 'Conditions',
                      value: weatherLabelForCode(weather.weatherCode),
                    ),
                  ),
                ],
              ),
            )
          else if (_loading)
            const SizedBox(
              height: 76,
              child: Center(
                child: AppText(
                  'Loading current field weather…',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: AppText(
                      _error ?? 'Weather is unavailable.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _location(FieldWorkspaceRecord? workspace) {
    if (workspace == null) return 'Active field';
    final values = [
      workspace.field.barangay,
      workspace.field.municipalityCity,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return values.isEmpty ? workspace.field.name : values.join(', ');
  }

  String _updated(DateTime time) {
    final elapsed = DateTime.now().difference(time).abs();
    if (elapsed.inMinutes < 2) return 'Updated now';
    if (elapsed.inMinutes < 60) return 'Updated ${elapsed.inMinutes} min ago';
    return 'Updated ${elapsed.inHours} hr ago';
  }
}

class _Temperature extends StatelessWidget {
  const _Temperature({required this.weather});
  final CurrentFieldWeather weather;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(
        _weatherIcon(weather.weatherCode, weather.isDay),
        color: _weatherColor(weather.weatherCode, weather.isDay),
        size: 37,
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '${weather.temperatureC.round()}°C',
              style: const TextStyle(
                fontSize: 23,
                height: 1,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            AppText(
              weatherLabelForCode(weather.weatherCode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Condition extends StatelessWidget {
  const _Condition({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 37,
        height: 37,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      const SizedBox(height: 5),
      AppText(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
      ),
      Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 6),
    color: AppColors.surfaceVariant,
  );
}

IconData _weatherIcon(int code, bool isDay) {
  if (code == 0) {
    return isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined;
  }
  if (code <= 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.water_drop_outlined;
}

Color _weatherColor(int code, bool isDay) {
  if (code == 0 && isDay) return const Color(0xFFFF981F);
  if (code >= 95) return AppColors.moderateSeverityRing;
  return const Color(0xFF1687B5);
}
