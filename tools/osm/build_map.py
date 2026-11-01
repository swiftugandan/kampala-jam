#!/usr/bin/env python3
"""Turn raw Overpass extracts into the game's map files.

  python3 -I tools/osm/build_map.py

Reads  tools/osm/raw/*.json, tools/osm/landmarks_curated.json
Writes assets/data/map_kampala.bin   (geometry, little-endian typed arrays)
       assets/data/map_meta.json     (names, landmarks, flood sites, grid info)

Coordinates are metres on a local equirectangular projection centred on the
start, x east and y south (Godot's axes). The game scales them; see MapData.gd.
Map data (c) OpenStreetMap contributors, ODbL 1.0.
"""
import array
import heapq
import json
import math
import pathlib
import re
import sys
from collections import defaultdict

HERE = pathlib.Path(__file__).parent
RAW = HERE / "raw"
OUT = HERE.parent.parent / "assets" / "data"

CLASS_OF = {
    "motorway": 0, "trunk": 0, "motorway_link": 2, "trunk_link": 2,
    "primary": 1, "primary_link": 3, "secondary": 2, "secondary_link": 3,
    "tertiary": 3, "tertiary_link": 4, "unclassified": 4, "residential": 5,
    "living_street": 5,
}
# Metres either side of the centreline a building must lie within to be kept,
# by road class. Keeps the frontage a driver actually sees; drops back streets.
BUILDING_REACH = {0: 130, 1: 120, 2: 90, 3: 60, 4: 34, 5: 22}
MAX_SEG = 200.0    # metres; long segments are split so render chunks stay local
UNPAVED = {"unpaved", "ground", "dirt", "gravel", "compacted", "earth", "fine_gravel", "laterite", "mud", "sand"}
SEG_CELL = 120.0   # metres; drivable-area lookup grid
CHUNK = 480.0      # metres; render chunk
SEG_MARGIN = 26.0  # widest half-road in metres, so lookups never miss a kerb
SEG_SAMPLE = 14.0  # metres between grid stamps along a segment
SIMPLIFY = 2.5     # Douglas-Peucker tolerance in metres


def load(name):
    return json.loads((RAW / f"{name}.json").read_text())["elements"]


class Projection:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))
        self.ky = 110574.0

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, (self.lat0 - lat) * self.ky)


def dp(points, tol):
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        ln = math.hypot(dx, dy) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            d = abs((points[i][0] - ax) * dy - (points[i][1] - ay) * dx) / ln
            if d > best:
                best, bi = d, i
        if best > tol:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(points, keep) if k]


def subdivide(points, max_len):
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        n = int(math.hypot(b[0]-a[0], b[1]-a[1]) / max_len) + 1
        for t in range(1, n + 1):
            out.append((a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n))
    return out


def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts
    def half(seq):
        out = []
        for p in seq:
            while len(out) > 1 and (out[-1][0]-out[-2][0])*(p[1]-out[-2][1]) - (out[-1][1]-out[-2][1])*(p[0]-out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out[:-1]
    return half(pts) + half(reversed(pts))


def seg_intersect(p, q, r, s):
    d1 = (q[0]-p[0], q[1]-p[1]); d2 = (s[0]-r[0], s[1]-r[1])
    den = d1[0]*d2[1] - d1[1]*d2[0]
    if abs(den) < 1e-9:
        return None
    t = ((r[0]-p[0])*d2[1] - (r[1]-p[1])*d2[0]) / den
    u = ((r[0]-p[0])*d1[1] - (r[1]-p[1])*d1[0]) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return (p[0]+t*d1[0], p[1]+t*d1[1])
    return None


def centre_of(el):
    if "center" in el:
        return el["center"]["lat"], el["center"]["lon"]
    if "lat" in el:
        return el["lat"], el["lon"]
    g = el.get("geometry") or []
    if g:
        return sum(p["lat"] for p in g)/len(g), sum(p["lon"] for p in g)/len(g)
    return None


def footprint(el, proj):
    g = [p for p in (el.get("geometry") or []) if p]
    if el["type"] == "relation":
        g = [p for m in el.get("members", []) if m.get("role") != "inner" for p in (m.get("geometry") or [])]
    return [proj(p["lat"], p["lon"]) for p in g]


def main():
    curated = json.loads((HERE / "landmarks_curated.json").read_text())
    named = load("landmarks") + load("places")
    start_el = next((e for e in named if re.search(curated["start"]["match"], e["tags"].get("name", "")) and e["type"] == "way"), None)
    finish_el = next((e for e in named if re.search(curated["finish"]["match"], e["tags"].get("name", "")) and e["type"] == "way"), None)
    if not start_el or not finish_el:
        sys.exit("start or finish landmark missing from OSM data")
    proj = Projection(*centre_of(start_el))

    # ---- roads: split ways at shared nodes -------------------------------
    use = defaultdict(int)
    ways = load("roads")
    for w in ways:
        for n in w["nodes"]:
            use[n] += 1
    coord, raw_edges = {}, []
    for w in ways:
        cls = CLASS_OF[w["tags"]["highway"]]
        name = w["tags"].get("name", "")
        ow = 1 if w["tags"].get("oneway") in ("yes", "1", "true") or w["tags"].get("junction") == "roundabout" else 0
        rev = w["tags"].get("oneway") == "-1"
        surface = w["tags"].get("surface", "")
        unpaved = surface in UNPAVED or (cls == 5 and surface == "")
        ids, geo = list(w["nodes"]), [proj(p["lat"], p["lon"]) for p in w["geometry"]]
        if rev:
            ids.reverse(); geo.reverse(); ow = 1
        cur = [geo[0]]; a = ids[0]; coord[a] = geo[0]
        for i in range(1, len(ids)):
            coord[ids[i]] = geo[i]
            cur.append(geo[i])
            if use[ids[i]] > 1 or i == len(ids) - 1:
                raw_edges.append((a, ids[i], cls, name, ow | (2 if unpaved else 0), cur))
                a, cur = ids[i], [geo[i]]
    # largest connected component only: everything reachable from everything
    adj = defaultdict(list)
    for e in raw_edges:
        adj[e[0]].append(e[1]); adj[e[1]].append(e[0])
    seen, best = set(), set()
    for n in adj:
        if n in seen:
            continue
        comp, st = {n}, [n]
        while st:
            for m in adj[st.pop()]:
                if m not in comp:
                    comp.add(m); st.append(m)
        seen |= comp
        if len(comp) > len(best):
            best = comp
    edges = [e for e in raw_edges if e[0] in best and e[0] != e[1] or (e[0] in best and len(e[5]) > 3)]
    node_index = {}
    for e in edges:
        for n in (e[0], e[1]):
            node_index.setdefault(n, len(node_index))
    node_xy = [None] * len(node_index)
    for n, i in node_index.items():
        node_xy[i] = coord[n]
    names, name_ix = [""], {"": 0}
    e_a, e_b, e_cls, e_name, e_flags, e_gs, e_gn, geom = [], [], [], [], [], [], [], []
    for a, b, cls, name, ow, pts in edges:
        pts = subdivide(dp(pts, SIMPLIFY), MAX_SEG)
        e_a.append(node_index[a]); e_b.append(node_index[b]); e_cls.append(cls)
        e_name.append(name_ix.setdefault(name, len(name_ix)))
        if e_name[-1] == len(names):
            names.append(name)
        e_flags.append(ow)
        e_gs.append(len(geom) // 2); e_gn.append(len(pts))
        for p in pts:
            geom += [p[0], p[1]]
    # segments and lookup grid
    xs = [p[0] for p in node_xy]; ys = [p[1] for p in node_xy]
    minx, miny = min(xs) - 300, min(ys) - 300
    maxx, maxy = max(xs) + 300, max(ys) + 300
    gw, gh = int((maxx-minx)/SEG_CELL)+1, int((maxy-miny)/SEG_CELL)+1
    grid = defaultdict(list)
    seg_xy, seg_edge = [], []
    for ei in range(len(e_a)):
        s, n = e_gs[ei], e_gn[ei]
        for k in range(n - 1):
            ax, ay, bx, by = geom[2*(s+k)], geom[2*(s+k)+1], geom[2*(s+k)+2], geom[2*(s+k)+3]
            si = len(seg_edge)
            seg_xy += [ax, ay, bx, by]; seg_edge.append(ei)
            # Every point of the road must find this segment in its cell. Each sample
            # stamps a square of SEG_MARGIN, so between samples the guaranteed reach is
            # SEG_MARGIN - spacing/2, which has to exceed the widest half-road plus verge.
            ln = math.hypot(bx-ax, by-ay)
            steps = max(1, math.ceil(ln / SEG_SAMPLE))
            cells = set()
            for t in range(steps + 1):
                x = ax + (bx-ax)*t/steps; y = ay + (by-ay)*t/steps
                cx0 = int((x-SEG_MARGIN-minx)/SEG_CELL); cx1 = int((x+SEG_MARGIN-minx)/SEG_CELL)
                cy0 = int((y-SEG_MARGIN-miny)/SEG_CELL); cy1 = int((y+SEG_MARGIN-miny)/SEG_CELL)
                for cy in range(cy0, cy1+1):
                    for cx in range(cx0, cx1+1):
                        cells.add(cy*gw+cx)
            for c in cells:
                grid[c].append(si)
    gs_start, gs_items = [0], []
    for c in range(gw*gh):
        gs_items += grid.get(c, [])
        gs_start.append(len(gs_items))

    # ---- buildings near the roads ----------------------------------------
    print("filtering buildings...")
    REACH_CELL = 20.0
    near = set()
    for ei in range(len(e_a)):
        reach = BUILDING_REACH[e_cls[ei]]
        r = int(reach / REACH_CELL) + 1
        disc = [(dx, dy) for dy in range(-r, r+1) for dx in range(-r, r+1) if math.hypot(dx, dy)*REACH_CELL <= reach]
        s0, n = e_gs[ei], e_gn[ei]
        for k in range(n - 1):
            x, y = geom[2*(s0+k)], geom[2*(s0+k)+1]
            x2, y2 = geom[2*(s0+k)+2], geom[2*(s0+k)+3]
            steps = int(math.hypot(x2-x, y2-y)/REACH_CELL) + 1
            for t in range(steps + 1):
                cx = int((x+(x2-x)*t/steps)//REACH_CELL); cy = int((y+(y2-y)*t/steps)//REACH_CELL)
                for dx, dy in disc:
                    near.add((cx+dx, cy+dy))
    chunks = defaultdict(list)
    kept = total = 0
    for b in load("buildings"):
        total += 1
        g = b.get("geometry") or []
        if len(g) < 3:
            continue
        pts = [proj(p["lat"], p["lon"]) for p in g]
        cx = sum(p[0] for p in pts)/len(pts); cy = sum(p[1] for p in pts)/len(pts)
        if (int(cx//REACH_CELL), int(cy//REACH_CELL)) not in near:
            continue
        h = hull(pts)  # convex, so the renderer never needs to triangulate
        if len(h) < 3:
            continue
        kept += 1
        chunks[(int((cx-minx)//CHUNK), int((cy-miny)//CHUNK))].append(h)
    cw, ch = int((maxx-minx)/CHUNK)+1, int((maxy-miny)/CHUNK)+1
    bld_chunk_start, bld_start, bld_xy = [0], [0], []
    for cy in range(ch):
        for cx in range(cw):
            ox, oy = minx + cx*CHUNK, miny + cy*CHUNK
            for h in chunks.get((cx, cy), []):
                for p in h:
                    # decimetres from the chunk corner: 4 bytes a vertex, not 8
                    bld_xy += [max(-32768, min(32767, round((p[0]-ox)*10))), max(-32768, min(32767, round((p[1]-oy)*10)))]
                bld_start.append(len(bld_xy)//2)
            bld_chunk_start.append(len(bld_start)-1)
    print(f"  kept {kept} of {total}")

    # ---- water and flood sites -------------------------------------------
    water = load("water")
    w_start, w_xy, w_kind = [0], [], []  # kind 0 line stream, 1 drain, 2 polygon
    site_cells = {}
    lines = []
    for w in water:
        tags = w["tags"]; g = w.get("geometry") or []
        if len(g) < 2:
            continue
        pts = [proj(p["lat"], p["lon"]) for p in g]
        ww = tags.get("waterway")
        if ww:
            kind = 1 if ww in ("drain", "ditch") else 0
            p2 = dp(pts, 4.0)
            lines.append((p2, tags.get("name", ""), kind))
        else:
            if w["tags"].get("name", "") and re.search("tank|settler|filter|pool|chamber|sludge", tags["name"], re.I):
                continue
            if len(pts) < 4:
                continue
            area = abs(sum(pts[i][0]*pts[i+1][1]-pts[i+1][0]*pts[i][1] for i in range(len(pts)-1)))/2
            if area < 800:
                continue
            kind = 2; p2 = dp(pts[:-1], 5.0)
            if len(p2) < 3:
                continue
        w_kind.append(kind)
        for p in p2:
            w_xy += [p[0], p[1]]
        w_start.append(len(w_xy)//2)
    print("finding flood sites...")
    wgrid = defaultdict(list)
    for li, (pts, _, _) in enumerate(lines):
        for k in range(len(pts)-1):
            n = max(1, int(math.hypot(pts[k+1][0]-pts[k][0], pts[k+1][1]-pts[k][1])/100))
            for t in range(n+1):
                x = pts[k][0]+(pts[k+1][0]-pts[k][0])*t/n; y = pts[k][1]+(pts[k+1][1]-pts[k][1])*t/n
                wgrid[(int(x//100), int(y//100))].append((li, k))
    sites = []
    for si in range(len(seg_edge)):
        ei = seg_edge[si]
        if e_cls[ei] > 4:
            continue
        ax, ay, bx, by = seg_xy[4*si:4*si+4]
        n = max(1, int(math.hypot(bx-ax, by-ay)/100))
        cand = set()
        for t in range(n+1):
            cand |= set(wgrid.get((int((ax+(bx-ax)*t/n)//100), int((ay+(by-ay)*t/n)//100)), ()))
        for li, k in cand:
            pts, wname, kind = lines[li]
            hit = seg_intersect((ax, ay), (bx, by), pts[k], pts[k+1])
            if hit:
                key = (int(hit[0]//150), int(hit[1]//150))
                if key not in site_cells:
                    site_cells[key] = 1
                    sites.append({"x": round(hit[0], 1), "y": round(hit[1], 1), "edge": ei, "water": wname, "class": e_cls[ei], "major_water": kind == 0})
    print(f"  {len(sites)} flood sites, {sum(1 for s in sites if s['major_water'])} on streams")

    # ---- landmarks --------------------------------------------------------
    seen_names = {}
    def kind_of(t):
        a = t.get("amenity", ""); s = t.get("shop", ""); to = t.get("tourism", ""); l = t.get("leisure", "")
        if a == "place_of_worship":
            return "mosque" if t.get("religion") == "muslim" or re.search("mosque|masjid", t.get("name", ""), re.I) else "church"
        return {"fuel": "fuel", "school": "school", "college": "school", "university": "university",
                "hospital": "hospital", "bank": "bank", "marketplace": "market", "police": "police",
                "bus_station": "taxi_park", "restaurant": "eat", "bar": "eat", "cinema": "eat"}.get(a) \
            or {"mall": "mall", "supermarket": "mall", "department_store": "mall", "wholesale": "mall"}.get(s) \
            or {"hotel": "hotel", "guest_house": "hotel", "attraction": "attraction", "museum": "attraction"}.get(to) \
            or {"stadium": "stadium", "sports_centre": "stadium", "golf_course": "park", "park": "park"}.get(l)
    def in_map(x, y):
        return minx < x < maxx and miny < y < maxy
    landmarks = []
    els = load("landmarks")
    hero_specs = curated["heroes"] + [dict(curated["start"], role="start"), dict(curated["finish"], role="finish")]
    used_ids = set()
    for spec in hero_specs:
        hits = [e for e in els if re.search(spec["match"], e["tags"].get("name", ""))]
        hits += [e for e in load("places") if re.search(spec["match"], e["tags"].get("name", "")) and e["type"] == "way"]
        if not hits:
            sys.exit(f"curated landmark not in OSM data: {spec['match']}")
        hits.sort(key=lambda e: 0 if e["type"] != "node" else 1)
        e = hits[0]
        used_ids.add(e["id"])
        c = centre_of(e); x, y = proj(*c)
        fp = hull(footprint(e, proj)) if e["type"] != "node" else []
        lm = {"name": spec["display"], "kind": spec["kind"], "tier": 1, "x": round(x, 1), "y": round(y, 1), "fp": [round(v, 1) for p in fp[:60] for v in p]}
        if "role" in spec:
            lm["role"] = spec["role"]
        landmarks.append(lm)
    junk = re.compile(r"branch$|^(mosque|church|school|bank|hotel|hospital|kyambogo|lugogo|bugolobi)$|atm|agent|mobile money", re.I)
    for e in els:
        if e["id"] in used_ids:
            continue
        t = e["tags"]; name = t.get("name", "").strip()
        kind = kind_of(t)
        c = centre_of(e)
        if not kind or not c or len(name) < 4 or junk.search(name):
            continue
        x, y = proj(*c)
        if not in_map(x, y):
            continue
        cell = (name.lower(), int(x//250), int(y//250))
        if cell in seen_names:
            continue
        seen_names[cell] = 1
        fp = hull(footprint(e, proj)) if e["type"] != "node" else []
        # Tier 2 gets an icon on the map; tier 3 is a roadside label only.
        tier = 2 if kind in ("mosque", "church", "market", "hospital", "university", "stadium", "mall", "fuel", "police", "taxi_park", "attraction", "hotel") or (kind == "school" and fp) else 3
        landmarks.append({"name": name[:44], "kind": kind, "tier": tier, "x": round(x, 1), "y": round(y, 1), "fp": [round(v, 1) for p in fp[:40] for v in p]})
    places = []
    for p in load("places"):
        t = p["tags"]
        if t.get("place") in ("suburb", "neighbourhood", "quarter", "town") and p["type"] == "node":
            x, y = proj(p["lat"], p["lon"])
            if in_map(x, y):
                places.append({"name": t["name"], "x": round(x, 1), "y": round(y, 1), "rank": 0 if t["place"] in ("suburb", "town") else 1})

    # ---- report: the route a road-class-weighted driver would take --------
    start_xy = proj(*centre_of(start_el)); finish_xy = proj(*centre_of(finish_el))
    nearest = lambda q: min(range(len(node_xy)), key=lambda i: (node_xy[i][0]-q[0])**2+(node_xy[i][1]-q[1])**2)
    sn, fn = nearest(start_xy), nearest(finish_xy)
    speed = {0: 1.0, 1: 1.1, 2: 1.25, 3: 1.4, 4: 1.8, 5: 2.2}
    gadj = defaultdict(list)
    for ei in range(len(e_a)):
        s, n = e_gs[ei], e_gn[ei]
        ln = sum(math.hypot(geom[2*(s+k+1)]-geom[2*(s+k)], geom[2*(s+k+1)+1]-geom[2*(s+k)+1]) for k in range(n-1))
        gadj[e_a[ei]].append((e_b[ei], ei, ln))
        if not e_flags[ei] & 1:
            gadj[e_b[ei]].append((e_a[ei], ei, ln))
    dist = {sn: 0}; prev = {}; pq = [(0, sn)]
    while pq:
        d, u = heapq.heappop(pq)
        if d > dist.get(u, 1e18):
            continue
        if u == fn:
            break
        for v, ei, ln in gadj[u]:
            nd = d + ln*speed[e_cls[ei]]
            if nd < dist.get(v, 1e18):
                dist[v] = nd; prev[v] = (u, ei); heapq.heappush(pq, (nd, v))
    if fn not in prev:
        sys.exit("no route from start to finish")
    path, route_len, order, n = [], 0.0, [], fn
    while n != sn:
        u, ei = prev[n]; path.append(ei); n = u
    path.reverse()
    pts_on_route = []
    for ei in path:
        s, cnt = e_gs[ei], e_gn[ei]
        route_len += sum(math.hypot(geom[2*(s+k+1)]-geom[2*(s+k)], geom[2*(s+k+1)+1]-geom[2*(s+k)+1]) for k in range(cnt-1))
        pts_on_route += [(geom[2*(s+k)], geom[2*(s+k)+1]) for k in range(cnt)]
        nm = names[e_name[ei]] or "(unnamed)"
        if not order or order[-1] != nm:
            order.append(nm)
    print(f"route {route_len/1000:.1f} km via: " + " > ".join(order))
    for lm in landmarks:
        if lm["tier"] == 1:
            d = min(math.hypot(lm["x"]-p[0], lm["y"]-p[1]) for p in pts_on_route)
            print(f"  {d:6.0f} m from route: {lm['name']}")
    near_route = sum(1 for lm in landmarks if min(math.hypot(lm["x"]-p[0], lm["y"]-p[1]) for p in pts_on_route) < 150)
    print(f"  {near_route} named places within 150 m of that route")

    # ---- write -------------------------------------------------------------
    sections = [
        ("node_xy", "f", [v for p in node_xy for v in p]),
        ("edge_a", "i", e_a), ("edge_b", "i", e_b), ("edge_class", "i", e_cls),
        ("edge_name", "i", e_name), ("edge_flags", "i", e_flags),
        ("edge_geom_start", "i", e_gs), ("edge_geom_count", "i", e_gn), ("geom_xy", "f", geom),
        ("seg_xy", "f", seg_xy), ("seg_edge", "i", seg_edge),
        ("grid_start", "i", gs_start), ("grid_items", "i", gs_items),
        ("bld_chunk_start", "i", bld_chunk_start), ("bld_start", "i", bld_start), ("bld_xy", "h", bld_xy),
        ("water_start", "i", w_start), ("water_kind", "i", w_kind), ("water_xy", "f", w_xy),
    ]
    OUT.mkdir(parents=True, exist_ok=True)
    layout = []
    with open(OUT / "map_kampala.bin", "wb") as f:
        for name, code, vals in sections:
            arr = array.array(code, vals)
            assert arr.itemsize == (2 if code == "h" else 4)
            if sys.byteorder != "little":
                arr.byteswap()
            layout.append({"name": name, "type": code, "count": len(arr)})
            arr.tofile(f)
    meta = {
        "attribution": "Map data (c) OpenStreetMap contributors, ODbL 1.0",
        "osm_timestamp": json.loads((RAW / "roads.json").read_text()).get("osm3s", {}).get("timestamp_osm_base", ""),
        "layout": layout,
        "bounds": [minx, miny, maxx, maxy],
        "grid": {"cell": SEG_CELL, "w": gw, "h": gh},
        "chunks": {"size": CHUNK, "w": cw, "h": ch},
        "start": {"x": node_xy[sn][0], "y": node_xy[sn][1], "node": sn},
        "finish": {"x": node_xy[fn][0], "y": node_xy[fn][1], "node": fn},
        "road_names": names, "landmarks": landmarks, "places": places, "flood_sites": sites,
    }
    (OUT / "map_meta.json").write_text(json.dumps(meta, separators=(",", ":")))
    print(f"{len(e_a)} edges, {len(node_xy)} nodes, {len(seg_edge)} segments, {len(landmarks)} landmarks, {len(places)} places")
    print(f"bin {(OUT/'map_kampala.bin').stat().st_size/1e6:.1f} MB, meta {(OUT/'map_meta.json').stat().st_size/1e6:.2f} MB")


if __name__ == "__main__":
    main()
