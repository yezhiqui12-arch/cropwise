# Bundled Piat-area street map

`piat_streets.json` contains OpenStreetMap road, waterway, water, and landuse
geometry for approximately 121.42–121.56°E, 17.73–17.88°N. This is a coverage
rectangle around Piat and nearby fields, not an official municipal boundary.

Data: © OpenStreetMap contributors, licensed under ODbL 1.0.
Source and license: https://www.openstreetmap.org/copyright

Regenerate with `python tool/generate_piat_offline_map.py`. The generator fetches
raw map data from the OpenStreetMap API in small areas. It does not download
tiles from OpenStreetMap's public tile server.
