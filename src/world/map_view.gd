class_name MapView
extends Node2D
## Draws the real city around the camera, one chunk at a time. Layers keep roads
## above every building, whichever chunk either belongs to.

const TARMAC: Array[Color] = [Color("3f4045"), Color("44454a"), Color("4a4b4f"), Color("525254"), Color("5a5957"), Color("5e5c58")]
const MURRAM_ROAD := Color("a8623f")
const VERGE_TARMAC := Color("a9633b")
const VERGE_MURRAM := Color("8f4f2d")
const ROOFS: Array[Color] = [Color("a4553a"), Color("8f8f8c"), Color("b5683f"), Color("7f4630"), Color("c2b8a3"), Color("5f7f8c"), Color("9a3f30"), Color("a8a39a")]
const KIND_ROOF := {
	"mosque": Color("e9f3ea"), "church": Color("b5352b"), "shrine": Color("7a4a26"), "hospital": Color("f4f6f6"),
	"mall": Color("6fa8c7"), "market": Color("e08a2c"), "stadium": Color("c9c9c4"), "university": Color("a8552f"),
	"school": Color("d9a441"), "hotel": Color("3e9a8c"), "fuel": Color("e23b2e"), "police": Color("2f5ca8"),
	"taxi_park": Color("f5c518"), "attraction": Color("8c5fb0"),
}
const GROUND_PATCHES: Array[Color] = [Color("5b7d42"), Color("527539"), Color("64844a"), Color("6e8450"), Color("7d7a4c")]
const TREE_GREENS: Array[Color] = [Color("2f5c2c"), Color("386a33"), Color("2a5129"), Color("44763a")]
const WATER := Color("3f7c8c")
const GROUNDS_LIMIT := 7000.0  ## Footprints bigger than this are grounds, not a building.
const WATER_TILE := 1000.0

var map: MapData
var _layers: Dictionary = {}
var _chunks: Dictionary = {}
var _queue: Array[Vector2i] = []
var _landmarks_by_chunk: Dictionary = {}
var _centre := Vector2i(-99, -99)
var _first := true


func _ready() -> void:
	map = MapData.shared()
	for layer in ["water", "ground", "trees", "buildings", "landmarks", "verge", "surface_minor", "surface_major", "markings"]:
		var n := Node2D.new()
		n.name = layer
		add_child(n)
		_layers[layer] = n
	for lm: Dictionary in map.landmarks:
		if (lm["fp"] as Array).size() >= 6:
			var c := _chunk_of(Vector2(lm["x"], lm["y"]))
			(_landmarks_by_chunk.get_or_add(c, []) as Array).append(lm)
	_build_water()


func _chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - map.min_xy.x) / map.chunk_size), int((p.y - map.min_xy.y) / map.chunk_size))


## Keeps the chunks around the focus loaded, at most one new one a frame so
## phones do not hitch. The very first call builds everything visible at once.
func focus(p: Vector2) -> void:
	var c := _chunk_of(p)
	if c != _centre:
		_centre = c
		_queue.clear()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := c + Vector2i(dx, dy)
				if k.x >= 0 and k.y >= 0 and k.x < map.chunk_w and k.y < map.chunk_h and not _chunks.has(k):
					_queue.append(k)
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
		for k: Vector2i in _chunks.keys():
			if absi(k.x - c.x) > 2 or absi(k.y - c.y) > 2:
				for node: Node in _chunks[k]:
					node.queue_free()
				_chunks.erase(k)
	if _first:
		_first = false
		while not _queue.is_empty():
			_build_chunk(_queue.pop_front())
	elif not _queue.is_empty():
		_build_chunk(_queue.pop_front())


func _add_mesh(layer: String, builder: MeshBuilder, nodes: Array) -> void:
	var mesh := builder.build()
	if mesh == null:
		return
	var inst := MeshInstance2D.new()
	inst.mesh = mesh
	(_layers[layer] as Node2D).add_child(inst)
	nodes.append(inst)


func _build_chunk(k: Vector2i) -> void:
	var nodes: Array = []
	_chunks[k] = nodes
	var origin := map.min_xy + Vector2(k) * map.chunk_size
	var ground := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = k.x * 7919 + k.y * 104729
	# Soft patches of grass and bare earth, then the trees that make Kampala green.
	for i in 22:
		var c := origin + Vector2(rng.randf(), rng.randf()) * map.chunk_size
		var shade: Color = GROUND_PATCHES[rng.randi() % GROUND_PATCHES.size()]
		ground.disc(c, rng.randf_range(16.0, 46.0), shade, 22)
	var trees := MeshBuilder.new()
	for i in 90:
		var c := origin + Vector2(rng.randf(), rng.randf()) * map.chunk_size
		var r := rng.randf_range(2.2, 6.0)
		var leaf: Color = TREE_GREENS[rng.randi() % TREE_GREENS.size()]
		trees.disc(c + Vector2(r * 0.3, r * 0.4), r, Color(0.05, 0.08, 0.03, 0.3), 10)
		trees.disc(c, r, leaf, 10)
		trees.disc(c + Vector2(-r * 0.25, -r * 0.28), r * 0.6, leaf.lightened(0.14), 8)
	_add_mesh("trees", trees, nodes)
	_add_mesh("ground", ground, nodes)
	_add_mesh("buildings", _buildings_mesh(k, origin), nodes)
	if _landmarks_by_chunk.has(k):
		_add_mesh("landmarks", _landmarks_mesh(_landmarks_by_chunk[k]), nodes)
	_build_roads(k, origin, nodes)


func _buildings_mesh(k: Vector2i, origin: Vector2) -> MeshBuilder:
	var b := MeshBuilder.new()
	var c := k.y * map.chunk_w + k.x
	var first := map.bld_chunk_start[c]
	var last := map.bld_chunk_start[c + 1]
	var shadow := Color(0.08, 0.1, 0.05, 0.28)
	var bytes := map.bld_bytes
	var pts := PackedVector2Array()
	for i in range(first, last):
		var s := map.bld_start[i]
		var n := map.bld_start[i + 1] - s
		pts.resize(n)
		for j in n:
			var off := (s + j) * 4
			pts[j] = origin + Vector2(bytes.decode_s16(off), bytes.decode_s16(off + 2)) * 0.1
		b.convex(pts, shadow, Vector2(1.2, 1.6))
		b.convex(pts, ROOFS[(i * 2654435761 >> 7) % ROOFS.size()])
	return b


func _landmarks_mesh(list: Array) -> MeshBuilder:
	var b := MeshBuilder.new()
	for lm: Dictionary in list:
		var raw: Array = lm["fp"]
		var pts := PackedVector2Array()
		for i in range(0, raw.size() - 1, 2):
			pts.append(Vector2(raw[i], raw[i + 1]))
		var area := 0.0
		for i in pts.size():
			area += pts[i].cross(pts[(i + 1) % pts.size()])
		area = absf(area) * 0.5
		var kind: String = lm["kind"]
		var roof: Color = KIND_ROOF.get(kind, Color("d8cdb6"))
		if area > GROUNDS_LIMIT:
			# Campuses and resorts: mown grounds with a coloured edge, not a giant roof.
			b.convex(pts, Color(0.46, 0.62, 0.32, 0.75))
			for i in pts.size():
				b.band(pts[i], pts[(i + 1) % pts.size()], 1.0, roof)
			continue
		var height := 7.0 if int(lm["tier"]) == 1 else 3.5
		var up := Vector2(0, -height)
		var wall := roof.darkened(0.42)
		b.convex(pts, Color(0.08, 0.1, 0.05, 0.3), Vector2(2.5, 3.0))
		for i in pts.size():
			var a := pts[i]
			var c := pts[(i + 1) % pts.size()]
			b.quad(a, c, c + up, a + up, wall)
		b.convex(pts, roof, up)
	return b


func _build_roads(k: Vector2i, origin: Vector2, nodes: Array) -> void:
	var verge := MeshBuilder.new()
	var minor := MeshBuilder.new()
	var major := MeshBuilder.new()
	var marks := MeshBuilder.new()
	var size := map.chunk_size
	var cells := int(ceil(size / map.cell)) + 1
	var cx0 := int((origin.x - map.min_xy.x) / map.cell)
	var cy0 := int((origin.y - map.min_xy.y) / map.cell)
	var seen := {}
	var rect := Rect2(origin, Vector2(size, size))
	for cy in range(cy0, mini(cy0 + cells, map.grid_h)):
		for cx in range(cx0, mini(cx0 + cells, map.grid_w)):
			var c := cy * map.grid_w + cx
			for i in range(map.grid_start[c], map.grid_start[c + 1]):
				var si := map.grid_items[i]
				if seen.has(si):
					continue
				seen[si] = true
				var a := Vector2(map.seg_xy[si * 4], map.seg_xy[si * 4 + 1])
				var b := Vector2(map.seg_xy[si * 4 + 2], map.seg_xy[si * 4 + 3])
				if not rect.has_point((a + b) * 0.5):
					continue
				var e := map.seg_edge[si]
				var cls := map.edge_class[e]
				var hw := MapData.HALF_WIDTH[cls]
				var unpaved := map.is_unpaved(e)
				var vc := VERGE_MURRAM if unpaved else VERGE_TARMAC
				var sc := MURRAM_ROAD if unpaved else TARMAC[cls]
				verge.band(a, b, hw + 2.4, vc)
				verge.disc(a, hw + 2.4, vc)
				verge.disc(b, hw + 2.4, vc)
				# Major roads paint last, so a side road meets the main road cleanly.
				var surface := minor if cls >= 4 else major
				surface.band(a, b, hw, sc)
				surface.disc(a, hw, sc)
				surface.disc(b, hw, sc)
				if not unpaved and cls <= 3:
					_dashes(marks, a, b, map.is_oneway(e))
	_add_mesh("verge", verge, nodes)
	_add_mesh("surface_minor", minor, nodes)
	_add_mesh("surface_major", major, nodes)
	_add_mesh("markings", marks, nodes)


func _dashes(m: MeshBuilder, a: Vector2, b: Vector2, oneway: bool) -> void:
	if oneway:
		return
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var d := 4.0
	var col := Color(0.93, 0.91, 0.82, 0.7)
	while d < length - 7.0:
		m.band(a + dir * d, a + dir * (d + 7.0), 0.28, col)
		d += 16.0


func _build_water() -> void:
	var tiles: Dictionary = {}
	for i in map.water_kind.size():
		var s := map.water_start[i]
		var n := map.water_start[i + 1] - s
		var kind := map.water_kind[i]
		if kind == 2:
			var poly := PackedVector2Array()
			poly.resize(n)
			for j in n:
				poly[j] = Vector2(map.water_xy[(s + j) * 2], map.water_xy[(s + j) * 2 + 1])
			var tri := Geometry2D.triangulate_polygon(poly)
			if tri.is_empty():
				continue
			var b: MeshBuilder = _water_tile(tiles, poly[0])
			for t in range(0, tri.size(), 3):
				b.tri(poly[tri[t]], poly[tri[t + 1]], poly[tri[t + 2]], WATER)
		else:
			var half := 2.4 if kind == 0 else 1.0
			for j in n - 1:
				var a := Vector2(map.water_xy[(s + j) * 2], map.water_xy[(s + j) * 2 + 1])
				var c := Vector2(map.water_xy[(s + j + 1) * 2], map.water_xy[(s + j + 1) * 2 + 1])
				var b: MeshBuilder = _water_tile(tiles, a)
				b.band(a, c, half, WATER)
	for key: Vector2i in tiles:
		var mesh: ArrayMesh = (tiles[key] as MeshBuilder).build()
		if mesh:
			var inst := MeshInstance2D.new()
			inst.mesh = mesh
			(_layers["water"] as Node2D).add_child(inst)


func _water_tile(tiles: Dictionary, p: Vector2) -> MeshBuilder:
	var key := Vector2i(int(floor(p.x / WATER_TILE)), int(floor(p.y / WATER_TILE)))
	if not tiles.has(key):
		tiles[key] = MeshBuilder.new()
	return tiles[key]
