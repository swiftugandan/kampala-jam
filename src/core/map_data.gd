class_name MapData
extends RefCounted
## The real road network, buildings and landmarks. Read-only after load.
## Units are map metres ("wu"); see tools/osm/build_map.py for the file format.

const BIN_PATH := "res://assets/data/map_kampala.bin"
const META_PATH := "res://assets/data/map_meta.json"
## Half road width per class: exaggerated from real life so the arcade car fits.
const HALF_WIDTH: Array[float] = [14.5, 12.5, 11.0, 10.0, 8.6, 7.6]

class RoadHit:
	var valid := false
	var edge := -1
	var clearance := -INF  ## Distance inside the road edge; negative when outside.
	var closest := Vector2.ZERO
	var tangent := Vector2.RIGHT
	var normal := Vector2.UP  ## Points from the centreline toward the query point.

class EdgePath:
	var pts := PackedVector2Array()
	var cum := PackedFloat32Array()
	var length := 0.0

	func sample(s: float) -> Array:
		var d := clampf(s, 0.0, length)
		var i := clampi(cum.bsearch(d) - 1, 0, pts.size() - 2)
		var seg_len := cum[i + 1] - cum[i]
		var t := 0.0 if seg_len < 0.001 else (d - cum[i]) / seg_len
		var tan := (pts[i + 1] - pts[i]).normalized()
		return [pts[i].lerp(pts[i + 1], t), tan]

static var _shared: MapData

var meta: Dictionary
var node_xy: PackedFloat32Array
var edge_a: PackedInt32Array
var edge_b: PackedInt32Array
var edge_class: PackedInt32Array
var edge_name: PackedInt32Array
var edge_flags: PackedInt32Array
var edge_geom_start: PackedInt32Array
var edge_geom_count: PackedInt32Array
var geom_xy: PackedFloat32Array
var seg_xy: PackedFloat32Array
var seg_edge: PackedInt32Array
var grid_start: PackedInt32Array
var grid_items: PackedInt32Array
var bld_chunk_start: PackedInt32Array
var bld_start: PackedInt32Array
var bld_bytes: PackedByteArray
var water_start: PackedInt32Array
var water_kind: PackedInt32Array
var water_xy: PackedFloat32Array

var road_names: Array
var landmarks: Array
var places: Array
var flood_sites: Array
var min_xy: Vector2
var max_xy: Vector2
var cell: float
var grid_w: int
var grid_h: int
var chunk_size: float
var chunk_w: int
var chunk_h: int
var adj_start: PackedInt32Array
var adj_edges: PackedInt32Array
var _paths: Dictionary = {}


static func shared() -> MapData:
	if _shared == null:
		_shared = MapData.new()
		_shared._load()
	return _shared


func _load() -> void:
	var text := FileAccess.get_file_as_string(META_PATH)
	meta = JSON.parse_string(text)
	assert(meta != null, "map_meta.json failed to parse")
	var buf := FileAccess.get_file_as_bytes(BIN_PATH)
	assert(not buf.is_empty(), "map_kampala.bin missing")
	var offset := 0
	for section: Dictionary in meta["layout"]:
		var count: int = section["count"]
		var size: int = count * (2 if section["type"] == "h" else 4)
		var part := buf.slice(offset, offset + size)
		offset += size
		match section["name"]:
			"node_xy": node_xy = part.to_float32_array()
			"edge_a": edge_a = part.to_int32_array()
			"edge_b": edge_b = part.to_int32_array()
			"edge_class": edge_class = part.to_int32_array()
			"edge_name": edge_name = part.to_int32_array()
			"edge_flags": edge_flags = part.to_int32_array()
			"edge_geom_start": edge_geom_start = part.to_int32_array()
			"edge_geom_count": edge_geom_count = part.to_int32_array()
			"geom_xy": geom_xy = part.to_float32_array()
			"seg_xy": seg_xy = part.to_float32_array()
			"seg_edge": seg_edge = part.to_int32_array()
			"grid_start": grid_start = part.to_int32_array()
			"grid_items": grid_items = part.to_int32_array()
			"bld_chunk_start": bld_chunk_start = part.to_int32_array()
			"bld_start": bld_start = part.to_int32_array()
			"bld_xy": bld_bytes = part
			"water_start": water_start = part.to_int32_array()
			"water_kind": water_kind = part.to_int32_array()
			"water_xy": water_xy = part.to_float32_array()
	road_names = meta["road_names"]
	landmarks = meta["landmarks"]
	places = meta["places"]
	flood_sites = meta["flood_sites"]
	var b: Array = meta["bounds"]
	min_xy = Vector2(b[0], b[1])
	max_xy = Vector2(b[2], b[3])
	cell = meta["grid"]["cell"]
	grid_w = int(meta["grid"]["w"])
	grid_h = int(meta["grid"]["h"])
	chunk_size = meta["chunks"]["size"]
	chunk_w = int(meta["chunks"]["w"])
	chunk_h = int(meta["chunks"]["h"])
	_build_adjacency()


func _build_adjacency() -> void:
	var n := node_xy.size() / 2
	var counts := PackedInt32Array()
	counts.resize(n + 1)
	counts.fill(0)
	var edges := edge_a.size()
	for e in edges:
		counts[edge_a[e]] += 1
		counts[edge_b[e]] += 1
	adj_start.resize(n + 1)
	var total := 0
	for i in n:
		adj_start[i] = total
		total += counts[i]
	adj_start[n] = total
	adj_edges.resize(total)
	var fill := adj_start.duplicate()
	for e in edges:
		adj_edges[fill[edge_a[e]]] = e
		fill[edge_a[e]] += 1
		adj_edges[fill[edge_b[e]]] = e
		fill[edge_b[e]] += 1


func node_pos(n: int) -> Vector2:
	return Vector2(node_xy[n * 2], node_xy[n * 2 + 1])


func half_width(edge: int) -> float:
	return HALF_WIDTH[edge_class[edge]]


func is_oneway(edge: int) -> bool:
	return edge_flags[edge] & 1 != 0


func is_unpaved(edge: int) -> bool:
	return edge_flags[edge] & 2 != 0


func road_name(edge: int) -> String:
	return road_names[edge_name[edge]]


func edge_path(edge: int) -> EdgePath:
	var cached: EdgePath = _paths.get(edge)
	if cached != null:
		return cached
	var p := EdgePath.new()
	var s := edge_geom_start[edge]
	var n := edge_geom_count[edge]
	p.pts.resize(n)
	p.cum.resize(n)
	var acc := 0.0
	for i in n:
		var v := Vector2(geom_xy[(s + i) * 2], geom_xy[(s + i) * 2 + 1])
		if i > 0:
			acc += v.distance_to(p.pts[i - 1])
		p.pts[i] = v
		p.cum[i] = acc
	p.length = acc
	_paths[edge] = p
	return p


## Finds the road a point is on, favouring the road it is deepest inside so
## junctions behave as a union of roads. Reuses `hit` to avoid allocating.
func road_at(p: Vector2, hit: RoadHit) -> bool:
	hit.valid = false
	hit.clearance = -INF
	var cx := int((p.x - min_xy.x) / cell)
	var cy := int((p.y - min_xy.y) / cell)
	if cx < 0 or cy < 0 or cx >= grid_w or cy >= grid_h:
		return false
	var c := cy * grid_w + cx
	for i in range(grid_start[c], grid_start[c + 1]):
		var si := grid_items[i]
		var ax := seg_xy[si * 4]
		var ay := seg_xy[si * 4 + 1]
		var dx := seg_xy[si * 4 + 2] - ax
		var dy := seg_xy[si * 4 + 3] - ay
		var len2 := dx * dx + dy * dy
		var t := 0.0 if len2 < 0.0001 else clampf(((p.x - ax) * dx + (p.y - ay) * dy) / len2, 0.0, 1.0)
		var qx := ax + dx * t
		var qy := ay + dy * t
		var dist := sqrt((p.x - qx) * (p.x - qx) + (p.y - qy) * (p.y - qy))
		var e := seg_edge[si]
		var clear := HALF_WIDTH[edge_class[e]] - dist
		if clear > hit.clearance:
			hit.clearance = clear
			hit.edge = e
			hit.closest = Vector2(qx, qy)
			hit.tangent = Vector2(dx, dy).normalized() if len2 > 0.0001 else Vector2.RIGHT
			hit.normal = (p - hit.closest).normalized() if dist > 0.001 else Vector2(-hit.tangent.y, hit.tangent.x)
			hit.valid = true
	return hit.valid


func nearest_node(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in node_xy.size() / 2:
		var dx := node_xy[i * 2] - p.x
		var dy := node_xy[i * 2 + 1] - p.y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


func landmark_named(display_name: String) -> Dictionary:
	for lm: Dictionary in landmarks:
		if lm["name"] == display_name:
			return lm
	return {}


func edges_named(road: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var idx := road_names.find(road)
	if idx < 0:
		return out
	for e in edge_name.size():
		if edge_name[e] == idx:
			out.append(e)
	return out
