# Recent weather data

## Current implementation

Assessment setup requests hourly precipitation from Open-Meteo for the selected
field coordinate and totals samples from the preceding 48 hours.

Coordinate selection uses:

1. the stored boundary centroid, when present; or
2. the center calculated from the confirmed boundary GeoJSON for older records
   whose centroid columns are empty.

A successful response is cached in local app preferences for three hours. The
assessment stores the precipitation total, period end, and retrieval time in
its weather-context text.

## Failure behavior

Weather retrieval must not block an offline assessment. If coordinates are
missing, connectivity fails, the service times out, or the response is invalid,
the setup screen exposes a concise manual recent-rain fallback and a retry
action.

Internet access alone does not guarantee retrieval: the phone must also be able
to reach the provider, the field must have usable coordinates, and the response
must contain recent hourly data.

## Interpretation boundary

Provider precipitation is contextual data. It does not prove that the specific
field is dry, muddy, flooded, recently irrigated, accessible, or safe to enter.
It must not override the treatment/re-entry safety gate.

The app stores the raw total rather than inventing a scientific rain category or
field-surface conclusion.

## Deployment review

The current integration uses Open-Meteo without an embedded API key. Before a
production or high-volume deployment, confirm the provider's current terms,
attribution expectations, availability guarantees, privacy implications, and
appropriate commercial/non-commercial endpoint for the intended organization.

Official documentation: <https://open-meteo.com/en/docs>

