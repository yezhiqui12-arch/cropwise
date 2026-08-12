# Field location and optional-boundary design

## Decision

WormWise must allow a user to register and assess a maize field without first
drawing or surveying its complete boundary. A phone alone cannot promise
centimeter-level or legal parcel accuracy. The application therefore records
what is actually known and labels it clearly.

## Supported spatial states

1. **Reported area only** - the user enters the farmer-reported or
   document-reported number of hectares. No coordinate or polygon is claimed.
2. **Entrance GPS recorded** - the app stores an averaged phone-GNSS point,
   its accuracy values, sample count, timestamp, and confidence. This is a
   reference point, not a field boundary.
3. **Approximate outline saved** - the user reviews and saves a polygon drawn
   on the map, recorded from accessible GPS corners, or created with both
   methods. It is a scouting aid, not a cadastral survey.

All three states are valid for starting a Fall Armyworm assessment. The app
must never imply that a reported area or entrance point is a confirmed polygon.

## Field registration

Required:

- Field name.
- Reported area greater than zero hectares.

Optional:

- Barangay and landmark within Piat, Cagayan.
- Entrance GPS.
- Maize variety, intended use, and planting date.
- Approximate outline, which can be added later.

When the user taps **Record field entrance**, the app:

1. Checks that phone location is enabled.
2. Requests foreground location permission if necessary.
3. Collects up to five usable readings for up to 12 seconds.
4. Rejects invalid readings and readings worse than 100 metres.
5. Produces an accuracy-weighted average coordinate.
6. Stores average accuracy, worst accuracy, sample count, time, and a
   phone-GNSS confidence code.
7. Still allows the field to be saved if location is unavailable or skipped.

## Optional approximate outline

The boundary screen supports these phone-only actions:

- Tap the map to add or move a point visually.
- Stand at an accessible corner and use the GPS-pin button to add an averaged
  phone-GNSS point.
- Mix visual points and GPS points when some edges are inaccessible.
- Undo, delete, clear, zoom, and recenter.
- Review calculated area and perimeter before saving.

Saved outlines carry a source label:

- `manual_draw`
- `phone_gnss_corners`
- `mixed_draw_phone_gnss`

They also carry a confidence code based on which points had GPS accuracy data.
The confirmation dialog explicitly says that the result is approximate and not
a cadastral or survey-grade boundary.

## Assessment behavior

An active registered field is sufficient to enable **Start Assessment**.
Boundary completion is not a prerequisite. The home and field screens show the
current spatial state so the user understands the available evidence.

The database is already capable of storing latitude, longitude, and horizontal
accuracy for assessment stations. The actual station-by-station assessment UI
must use those fields later so the locations of observations provide the main
field evidence even when no outline exists. That UI is not part of this change.

## Map and offline limitation

Polygon editing and local SQLite storage do not require Google Maps. The
current OpenStreetMap layer is useful during development when internet is
available, but it must not be treated as a deployable offline imagery service
or downloaded in bulk from the public tile server.

For deployment, prepare a licensed offline map package for Piat and display it
with MapLibre (or another provider-neutral renderer). The assessment and field
registration workflows must continue to function when no basemap is available.

## Acceptance checks

- A field saves with reported area only.
- A user can start an assessment for that field.
- A denied GPS permission does not prevent field saving.
- An entrance point displays as an entrance, not as a boundary.
- A user can create an approximate outline with map taps, GPS corners, or both.
- Saving an outline creates a new version without deleting prior field data.
- Restarting the app preserves the selected field and its spatial state.
- No Google API key or billing setup is needed.
