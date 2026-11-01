class_name MeshBuilder
extends RefCounted
## Collects coloured triangles into one mesh: a whole chunk costs one draw call.

var verts := PackedVector2Array()
var colours := PackedColorArray()


func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	colours.append(col)
	colours.append(col)
	colours.append(col)


func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


func band(a: Vector2, b: Vector2, half: float, col: Color) -> void:
	var dir := b - a
	if dir.length_squared() < 0.0001:
		return
	var n := Vector2(-dir.y, dir.x).normalized() * half
	quad(a + n, b + n, b - n, a - n, col)


func disc(c: Vector2, r: float, col: Color, sides := 10) -> void:
	var prev := c + Vector2(r, 0)
	for i in range(1, sides + 1):
		var next := c + Vector2.from_angle(TAU * i / sides) * r
		tri(c, prev, next, col)
		prev = next


func convex(pts: PackedVector2Array, col: Color, offset := Vector2.ZERO) -> void:
	for i in range(1, pts.size() - 1):
		tri(pts[0] + offset, pts[i] + offset, pts[i + 1] + offset, col)


func build() -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
