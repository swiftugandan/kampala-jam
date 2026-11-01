class_name GameWorld
extends Node2D
## Assembles the map and the views of one running session, and owns the camera.

const ZOOM_SLOW := 4.4
const ZOOM_FAST := 2.9

var session: RaceSession
var camera := Camera2D.new()
var map_view := MapView.new()


func setup(race: RaceSession) -> void:
	session = race
	add_child(map_view)
	var route := WorldViews.RouteLine.new()
	route.session = race
	add_child(route)
	var hazards := WorldViews.Hazards.new()
	hazards.session = race
	hazards.camera = camera
	add_child(hazards)
	var traffic := WorldViews.Traffic.new()
	traffic.session = race
	add_child(traffic)
	var player := WorldViews.Player.new()
	player.session = race
	add_child(player)
	var labels := LabelView.new()
	labels.camera = camera
	add_child(labels)
	add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE * ZOOM_SLOW
	camera.position = race.car.pos
	map_view.focus(race.car.pos)


func _process(delta: float) -> void:
	if session == null:
		return
	var car := session.car
	var t := clampf(absf(car.speed) / 80.0, 0.0, 1.0)
	var target_zoom := lerpf(ZOOM_SLOW, ZOOM_FAST, t)
	camera.zoom = camera.zoom.lerp(Vector2.ONE * target_zoom, clampf(delta * 1.5, 0.0, 1.0))
	var ahead := car.pos + car.vel * 0.85
	camera.position = camera.position.lerp(ahead, clampf(delta * 4.0, 0.0, 1.0))
	map_view.focus(camera.position)
