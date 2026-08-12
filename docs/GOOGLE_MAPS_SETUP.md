# Google Maps setup retired

WormWise no longer depends on Google Maps, a Google Cloud API key, or a billing
account. This file is retained only so earlier project notes do not lead a
developer through an obsolete setup process.

The current field workflow is documented in
`docs/FIELD_LOCATION_AND_OPTIONAL_BOUNDARY.md` and
`FIELD_BOUNDARY_WORKFLOW.txt`.

The current development map uses `flutter_map` with OpenStreetMap tiles only as
an online orientation layer. The public OpenStreetMap tile service is not the
planned production or offline imagery source. A later deployment can use
MapLibre with a prepared, licensed offline Piat map package without changing the
field-location rules.
