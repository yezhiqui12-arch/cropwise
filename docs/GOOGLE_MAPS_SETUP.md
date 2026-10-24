# Google Maps setup retired

WormWise no longer depends on Google Maps, a Google Cloud API key, or a billing
account. This file is retained only so earlier project notes do not lead a
developer through an obsolete setup process.

The current field workflow is documented in
`docs/FIELD_LOCATION_AND_OPTIONAL_BOUNDARY.md` and
`FIELD_BOUNDARY_WORKFLOW.txt`.

The field overview and outline editor currently use `flutter_map` with Esri
World Imagery as an online drawing reference and provide an OpenStreetMap
alternative. This direct imagery integration still needs production review for
provider terms, authentication, attribution, availability, and expected usage.

Scout uses the same Esri World Imagery background as the Map tab and falls back
automatically to its deterministic illustrated field view. A later deployment
can use a prepared, licensed offline Piat imagery package without changing the
field-location rules.
