# Scan imagery deployment boundary

Status: Esri World Imagery is the current online background for both Map and
Scan. Approved licensed imagery packages may still replace it when available.

## Runtime priority

Scan requests imagery automatically in this order:

1. An approved high-resolution package supplied under a documented licence by
   DA, PhilSA, NAMRIA, or the LGU.
2. A prepared and licensed Sentinel-2 package for broad context.
3. Esri World Imagery for normal interactive viewing.
4. The deterministic offline illustrated field view generated from the saved
   field GeoJSON.

The illustrated view is drawn immediately and remains underneath imagery, so
loading or imagery failure never blocks scouting. It preserves the polygon's
shape, aspect ratio, and north orientation in local metric space. Its texture
and row lines are synthetic orientation aids clipped to the field polygon; they
are not remote observations of crop condition, obstacles, or actual row
positions.

## Approved local packages

Packages belong in the app's private documents directory:

`wormwise_field_imagery/<boundary-version-id>/`

Use `approved_imagery.json` for approved high-resolution imagery or
`sentinel2_imagery.json` for prepared Sentinel-2 imagery. A package is ignored
unless its manifest:

- uses schema `wormwise_field_imagery_v1`;
- identifies the expected source kind;
- names a file inside the same package directory;
- supplies non-empty display name, attribution, and licence reference;
- supplies valid geographic bounds that cover the entire confirmed field;
- points to an existing, non-empty image file.

Example:

```json
{
  "schema_version": "wormwise_field_imagery_v1",
  "source_kind": "approvedHighResolutionPackage",
  "image_file": "piat-field-2026.webp",
  "display_name": "DA licensed Piat field imagery",
  "attribution": "Department of Agriculture",
  "license_reference": "DA-PIAT-2026-001",
  "resolution_label": "0.5 m supplied imagery",
  "west": 121.70,
  "south": 17.65,
  "east": 121.71,
  "north": 17.66
}
```

The provider validates the manifest but cannot establish that a supplied
licence is legally sufficient. Product deployment still requires documentary
review of permitted devices, users, duration, derivative products, and local
retention/deletion rules.

## Esri World Imagery online display

The current online background uses the Esri World Imagery endpoint:

`https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}`

WormWise identifies tile requests with its stable Android application ID and
keeps visible Esri World Imagery attribution on the map.

This implementation requests only tiles needed for the evaluator's current
interactive viewport. It does not prefetch, bulk-download, scrape, package, or
offer an offline-download control. If tile loading fails, Scan switches
automatically to the deterministic offline illustrated field view without
blocking scouting.

Before production or institutional deployment, WormWise must review Esri's
current account, authentication, attribution, caching, and usage terms. The
current direct online reference is not an approved offline imagery package. A
provider change must not remove visible attribution or weaken the fallback.

## Sentinel-2 boundary

Sentinel-2 visible and near-infrared bands have 10-metre spatial resolution. A
prepared package can provide broad field context, but it cannot be presented as
plant-level, row-level, pest-level, or obstacle-level evidence. Its manifest
must state its source, acquisition date, processing, attribution, licence, and
`10 m broad context` resolution label.

## Official references

- Esri legal information: <https://www.esri.com/en-us/legal/overview>
- ESA Sentinel-2 facts and figures:
  <https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-2/Facts_and_figures>
- PhilSA CopPhil infrastructure: <https://infra.copphil.philsa.gov.ph/>
- NAMRIA products and services: <https://www.namria.gov.ph/>
