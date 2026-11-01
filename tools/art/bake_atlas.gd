extends SceneTree
## Rasterises tools/art/svg/*.svg into one atlas, so all traffic is one draw call.
## Run after make_vehicles.py: godot --headless --path . -s res://tools/art/bake_atlas.gd

const ATLAS := 2048
const PAD := 6


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/svg/manifest.json"))
	var sprites: Dictionary = manifest["sprites"]
	var names: Array = sprites.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return sprites[a]["h"] > sprites[b]["h"])
	var atlas := Image.create(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	var rects := {}
	var x := PAD
	var y := PAD
	var shelf := 0
	for sprite_name: String in names:
		var img := Image.new()
		var err := img.load_svg_from_string(FileAccess.get_file_as_string("res://tools/art/svg/%s.svg" % sprite_name), 1.0)
		if err != OK:
			printerr("bad svg ", sprite_name)
			quit(1)
			return
		img.convert(Image.FORMAT_RGBA8)
		if x + img.get_width() + PAD > ATLAS:
			x = PAD
			y += shelf + PAD
			shelf = 0
		if y + img.get_height() + PAD > ATLAS:
			printerr("atlas overflow at ", sprite_name)
			quit(1)
			return
		atlas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, y))
		rects[sprite_name] = [x, y, img.get_width(), img.get_height()]
		x += img.get_width() + PAD
		shelf = maxi(shelf, img.get_height())
	atlas.save_png("res://assets/vehicles/atlas.png")
	var f := FileAccess.open("res://assets/data/vehicle_sprites.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"px_per_wu": manifest["px_per_wu"], "rects": rects}))
	print("baked %d sprites, used height %d" % [rects.size(), y + shelf])
	quit()
