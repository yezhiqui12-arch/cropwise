# Field registration, location, and required assessment outline

> The filename is retained so existing project links continue to work. The
> assessment outline is no longer optional.

## Current decision

A field may be registered before its full outline is available, but a new
assessment cannot proceed to setup or active sampling until the selected field has a
confirmed approximate outline.

The app must show **Complete field outline** when the outline is missing. It
must preserve any assessment draft already associated with that field.

The outline is an approximate scouting aid. It must never be described as a
legal, cadastral, property, or survey-grade boundary.

## Spatial records

WormWise distinguishes:

1. **Reported area** — a farmer- or document-reported number; no polygon is
   implied.
2. **Entrance GPS** — an averaged phone-location reference point; it is not a
   boundary.
3. **Confirmed approximate outline** — a reviewed polygon used for assessment
   gating, route layout, and map orientation.
4. **Station locations** — evaluator-confirmed observation locations recorded
   during the assessment.

Only state 3 satisfies the new-assessment outline gate.

## Field registration and management

Required registration data:

- Field name
- Reported area greater than zero hectares

Optional crop-cycle and location context may include barangay, landmark,
entrance GPS, variety, intended use, and planting date.

The My Maize Fields screen provides field details and name editing. A delete
request moves a field to **Recently Deleted** for 30 days. It can be restored
during that period. After the retention period, app startup removes its stored
evidence files and marks the local records deleted while retaining the minimal
audit/tombstone metadata needed to explain the deletion.

## Entrance GPS

When entrance GPS is requested, the app checks location services, requests
foreground permission when required, collects multiple usable phone readings,
and stores the averaged coordinate with reported accuracy and time. Registration
can still be saved if entrance location is unavailable; assessment cannot start
until the outline is later confirmed.

## Outline editor

The editor supports visual points, averaged GPS corner points, or a mixture of
both. It validates a minimum of three points and rejects invalid geometry before
saving. Saving creates a new boundary version rather than deleting earlier
field or assessment data.

The confirmation must communicate:

> This is an approximate field outline for scouting orientation and area
> estimation. It is not a cadastral, legal, or survey-grade boundary.

## Map behavior

The field overview and outline editor currently open with Esri World Imagery
and allow switching to OpenStreetMap. That online imagery integration is a
development reference and still requires a deployment review of provider terms,
attribution, authentication, availability, and expected usage.

Scout now uses the same Esri World Imagery online background as the Map tab.
Scout falls back to the deterministic offline illustrated field view when the
online imagery is unavailable.

Route, stations, obstacles, current position, scale, north orientation, and the
confirmed outline remain app-owned overlays. Missing online tiles must not
block saved-outline editing, assessment resume, or field collection.

## Acceptance checks

- A field can be registered before an outline is available.
- A new assessment cannot enter setup or active sampling without a confirmed outline.
- The gate cannot be bypassed through a legacy Home or Assess route.
- Existing drafts are preserved when an outline is missing.
- Entrance GPS is never presented as a polygon.
- Saving a corrected outline creates a new version.
- Restart preserves the selected field and its current spatial state.
- Recently Deleted fields can be restored within 30 days.
- Expired evidence files are removed through the deletion lifecycle.
