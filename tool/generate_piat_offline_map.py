import json
import time
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
import requests

# Broad Piat-area sheet, including the fields east of the town centre.
BBOX = (121.42, 17.73, 121.56, 17.88)
URL = 'https://api.openstreetmap.org/api/0.6/map'
HEADERS = {'User-Agent': 'WormWiseCapstone/1.0 (local Piat street map)'}
session = requests.Session()
nodes = {}
ways = {}
requests_made = 0

def fetch(bounds, depth=0):
    global requests_made
    west, south, east, north = bounds
    response = session.get(URL, params={'bbox': f'{west:.6f},{south:.6f},{east:.6f},{north:.6f}'},
                           headers=HEADERS, timeout=60)
    requests_made += 1
    if response.status_code == 400 and b'too many nodes' in response.content and depth < 5:
        mid_lon, mid_lat = (west+east)/2, (south+north)/2
        for cell in ((west,south,mid_lon,mid_lat),(mid_lon,south,east,mid_lat),
                     (west,mid_lat,mid_lon,north),(mid_lon,mid_lat,east,north)):
            fetch(cell, depth+1)
        return
    response.raise_for_status()
    root = ET.fromstring(response.content)
    for element in root:
        if element.tag == 'node':
            nodes[element.attrib['id']] = (round(float(element.attrib['lat']), 5),
                                           round(float(element.attrib['lon']), 5))
        elif element.tag == 'way':
            ways[element.attrib['id']] = element
    time.sleep(0.12)

fetch(BBOX)
features = []
counts = Counter()
for way_id, way in ways.items():
    tags = {t.attrib['k']: t.attrib['v'] for t in way.findall('tag')}
    if 'highway' in tags:
        kind = 'road'
        road_class = tags['highway']
    elif 'waterway' in tags:
        kind = 'waterway'
        road_class = None
    elif tags.get('natural') == 'water' or 'water' in tags:
        kind = 'water'
        road_class = None
    elif 'building' in tags:
        kind = 'building'
        road_class = None
    elif 'landuse' in tags:
        kind = 'landuse'
        road_class = None
    else:
        continue
    coords = []
    for nd in way.findall('nd'):
        point = nodes.get(nd.attrib['ref'])
        if point is not None and (not coords or point != coords[-1]):
            coords.append(point)
    if len(coords) < 2: continue
    if kind in ('building','water','landuse') and (len(coords) < 4 or coords[0] != coords[-1]):
        continue
    # Keep a compact set of area shapes; roads remain the primary local map.
    # A street map needs the road network; thousands of building polygons
    # add bundle size and slow the Flutter vector layer on field devices.
    if kind == 'building': continue
    counts[kind] += 1
    features.append({'k':kind,'c':coords, **({'r':road_class} if road_class else {}),
                     **({'n':tags['name'][:80]} if tags.get('name') else {})})

out = {'version':1,'source':'OpenStreetMap','license':'ODbL 1.0',
       'attribution':'© OpenStreetMap contributors',
       'source_url':'https://www.openstreetmap.org/copyright',
       'downloaded_at':datetime.now(timezone.utc).isoformat(),
       'bounds':BBOX,'features':features}
path = Path('assets/maps/piat_streets.json')
path.write_text(json.dumps(out,separators=(',',':'),ensure_ascii=False),encoding='utf-8')
print('requests',requests_made,'nodes',len(nodes),'ways',len(ways),'features',dict(counts),'bytes',path.stat().st_size)
