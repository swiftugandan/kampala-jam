class_name GameAudio
extends Node
## Engine, hooter, sirens, crunches and rain. All synthesised by tools/audio/make_sfx.py.

var session: RaceSession
var _engine: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _once: Dictionary = {}


func setup(race: RaceSession) -> void:
	session = race
	_engine = _player("engine", true, -14.0)
	_rain = _player("rain", true, -60.0)
	_siren = _player("siren", true, -6.0)
	for s in ["horn", "scratch", "crash", "splash", "whistle"]:
		_once[s] = _player(s, false, -6.0)
	_engine.play()
	race.honked.connect(func() -> void: (_once["horn"] as AudioStreamPlayer).play())
	race.penalty_incurred.connect(_on_penalty)
	race.convoy_started.connect(func() -> void: _siren.play())


func _player(sound: String, looping: bool, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/audio/%s.wav" % sound)
	if looping:
		var copy: AudioStreamWAV = stream.duplicate()
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = copy.data.size() / 2
		stream = copy
	p.stream = stream
	p.volume_db = volume
	add_child(p)
	return p


func _on_penalty(info: Dictionary) -> void:
	match info["type"]:
		"boda_scratch", "rebar_scratch", "vehicle_contact", "flag_ignored":
			(_once["scratch"] as AudioStreamPlayer).play()
		"flooded_ditch":
			(_once["splash"] as AudioStreamPlayer).play()
		"convoy_violation":
			(_once["whistle"] as AudioStreamPlayer).play()
		_:
			(_once["crash"] as AudioStreamPlayer).play()


func _process(delta: float) -> void:
	if session == null:
		return
	_engine.pitch_scale = lerpf(0.65, 1.9, clampf(absf(session.car.speed) / 86.0, 0.0, 1.0))
	var rain: float = session.director.rain
	_rain.volume_db = lerpf(-50.0, -8.0, rain)
	if rain > 0.02 and not _rain.playing:
		_rain.play()
	elif rain <= 0.0 and _rain.playing:
		_rain.stop()
	if _siren.playing:
		var c := session.director.convoy_active()
		if c == null:
			_siren.stop()
		else:
			var along := c.pos_at(c.head)[0] as Vector2
			var d := along.distance_to(session.car.pos)
			_siren.volume_db = lerpf(-1.0, -22.0, clampf(d / 900.0, 0.0, 1.0))
			_siren.pitch_scale = 1.0 + delta * 0.0


func stop_all() -> void:
	for child in get_children():
		(child as AudioStreamPlayer).stop()
