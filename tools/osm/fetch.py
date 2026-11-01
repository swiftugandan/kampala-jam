#!/usr/bin/env python3
"""Download the OpenStreetMap extract for Kampala Jam from the Overpass API.

Writes raw responses to tools/osm/raw/ (gitignored). Run build_map.py next.
Map data (c) OpenStreetMap contributors, licensed under ODbL 1.0.
"""
import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request

ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)
USER_AGENT = "kampala-jam-map-builder/1.0 (open-source game; data pipeline)"
# south, west, north, east: Munyonyo (S) to Namugongo (N), Entebbe Rd (W) to Kira (E)
BBOX = "0.205,32.570,0.415,32.690"
HIGHWAYS = (
    "motorway|trunk|primary|secondary|tertiary|unclassified|residential|"
    "motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|living_street"
)
QUERIES = {
    "roads": f'[out:json][timeout:180];way["highway"~"^({HIGHWAYS})$"]({BBOX});out body geom;',
    "water": f'[out:json][timeout:180];(way["waterway"~"^(stream|river|drain|ditch|canal)$"]({BBOX});way["natural"="wetland"]({BBOX});way["natural"="water"]({BBOX}););out body geom;',
    "buildings": f'[out:json][timeout:300];way["building"]({BBOX});out tags geom;',
    # Everything a local driver navigates by. Footprints are kept (out geom) so
    # build_map.py can draw the real building, not a pin.
    "landmarks": f'[out:json][timeout:240];(nwr["name"]["amenity"~"^(fuel|school|college|university|hospital|clinic|bank|marketplace|place_of_worship|police|bus_station|restaurant|bar|cinema|townhall|embassy|courthouse)$"]({BBOX});nwr["name"]["shop"~"^(mall|supermarket|department_store|wholesale)$"]({BBOX});nwr["name"]["tourism"~"^(hotel|attraction|museum|guest_house)$"]({BBOX});nwr["name"]["leisure"~"^(stadium|sports_centre|golf_course|park|water_park)$"]({BBOX});nwr["name"]["building"]({BBOX});nwr["name"]["office"]({BBOX});nwr["name"]["historic"]({BBOX});nwr["name"]["man_made"~"^(water_tower|tower|storage_tank|bridge)$"]({BBOX}););out tags geom center;',
    "places": f'[out:json][timeout:120];(node["place"~"^(suburb|neighbourhood|quarter|village|town|hamlet)$"]({BBOX});nwr["tourism"="attraction"]({BBOX});nwr["amenity"~"^(place_of_worship|university|hospital|marketplace)$"]["name"]({BBOX});nwr["tourism"="hotel"]["name"]({BBOX}););out center tags;',
}


def fetch(query: str) -> bytes:
    data = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(4):
        url = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=330) as r:
                return r.read()
        except Exception as e:  # network or Overpass overload: back off and try the mirror
            last = e
            print(f"  {url}: {e}; retrying", file=sys.stderr)
            time.sleep(20 * (attempt + 1))
    raise SystemExit(f"Overpass failed: {last}")


def main() -> None:
    raw = pathlib.Path(__file__).parent / "raw"
    raw.mkdir(exist_ok=True)
    wanted = sys.argv[1:] or list(QUERIES)
    for name in wanted:
        print(f"fetching {name}...")
        body = fetch(QUERIES[name])
        doc = json.loads(body)
        (raw / f"{name}.json").write_bytes(body)
        print(f"  {len(doc['elements'])} elements, {len(body)/1e6:.1f} MB")
        print(f"  osm_base {doc.get('osm3s', {}).get('timestamp_osm_base')}")
        time.sleep(5)


if __name__ == "__main__":
    main()
