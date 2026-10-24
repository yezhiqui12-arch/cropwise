# Assess tab and historical review

Assess is the local assessment history, result, evidence, and resume hub. Active
sampling opens as a route-local session; it is not a separate bottom-navigation
destination.

## Implemented behavior

- Browse assessments with field and status filters and progressive loading.
- Preserve each record's original field, crop cycle, boundary version, protocol,
  block definitions, observations, evidence, and result snapshot.
- Resume eligible draft, safety-blocked, or in-progress records by assessment
  ID without changing the globally selected field.
- Keep completed, cancelled, invalid, and otherwise historical records
  read-only.
- Show explicit loading, empty, unavailable, missing-evidence, stale-review,
  and retry states.
- Present current DA results using the exact saved block and plant counts.
- Display numbered sampling points, saved evidence, and recorded location state
  without interpolating a continuous field-severity surface.
- Keep automatic screening, sampled infestation, expert damage incidence, and
  Davis severity distinct.
- Generate an offline PDF using the saved result and the user's selected map,
  coordinate, and evidence options.

## Readiness and completion

Readiness comes from the current protocol-aware completion service. For a DA
assessment, every required block must contain all 20 numbered plant records and
the applicable evidence, review, safety, and stage-specific data. Counts do not
treat missing or unconfirmed plants as negative.

Completion recalculates and saves formula-versioned metrics atomically. Missing
or zero denominators display as unavailable. Historical records are never
silently rewritten merely because they are opened in Assess.

## Main implementation areas

- `lib/data/repositories/assessment_history_repository.dart`
- `lib/providers/assessment_history_provider.dart`
- `lib/models/assessment_history_models.dart`
- `lib/screens/assess/`
- `lib/data/services/scouting_completion_service.dart`
- `lib/services/assessment_pdf_export_service.dart`
