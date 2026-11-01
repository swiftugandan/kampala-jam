class_name RouteFinder
extends RefCounted
## "Maps": shortest sensible route on the road graph. It only knows about
## closures the driver has already discovered, which is the joke and the game.

const CLASS_COST: Array[float] = [1.0, 1.08, 1.2, 1.35, 1.8, 2.4]

var map: MapData
var _astar := AStar2D.new()
var _edge_of: Dictionary = {}


func _init(map_data: MapData) -> void:
	map = map_data
	var n := map.node_xy.size() / 2
	_astar.reserve_space(n)
	for i in n:
		var best := CLASS_COST[5]
		for j in range(map.adj_start[i], map.adj_start[i + 1]):
			best = minf(best, CLASS_COST[map.edge_class[map.adj_edges[j]]])
		_astar.add_point(i, map.node_pos(i), best)
	for e in map.edge_a.size():
		var a := map.edge_a[e]
		var b := map.edge_b[e]
		if a == b:
			continue
		var oneway := map.is_oneway(e)
		_astar.connect_points(a, b, not oneway)
		_register(a, b, e)
		if not oneway:
			_register(b, a, e)


func _register(a: int, b: int, e: int) -> void:
	var key := (a << 32) | b
	if not _edge_of.has(key) or map.edge_path(e).length < map.edge_path(_edge_of[key]).length:
		_edge_of[key] = e


func block_edge(e: int) -> void:
	var a := map.edge_a[e]
	var b := map.edge_b[e]
	if a == b:
		return
	_astar.disconnect_points(a, b, true)


func unblock_edge(e: int) -> void:
	var a := map.edge_a[e]
	var b := map.edge_b[e]
	if a != b:
		_astar.connect_points(a, b, not map.is_oneway(e))


func connected(a: int, b: int) -> bool:
	return a == b or not _astar.get_id_path(a, b).is_empty()


func node_path(from_node: int, to_node: int) -> PackedInt64Array:
	return _astar.get_id_path(from_node, to_node)


func edge_between(a: int, b: int) -> int:
	return _edge_of.get((a << 32) | b, -1)


## Polyline for a node path, following each edge's real shape.
func polyline(nodes: PackedInt64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(nodes.size() - 1):
		var a: int = nodes[i]
		var b: int = nodes[i + 1]
		var e := edge_between(a, b)
		if e < 0:
			continue
		var pts := map.edge_path(e).pts
		if map.edge_a[e] == a:
			for k in range(1 if not out.is_empty() else 0, pts.size()):
				out.append(pts[k])
		else:
			for k in range(pts.size() - (2 if not out.is_empty() else 1), -1, -1):
				out.append(pts[k])
	return out


func edges_of(nodes: PackedInt64Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(nodes.size() - 1):
		var e := edge_between(nodes[i], nodes[i + 1])
		if e >= 0:
			out.append(e)
	return out
