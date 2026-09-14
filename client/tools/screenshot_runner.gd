extends SceneTree
## Used by scripts/screenshot.sh: loads SCREENSHOT_SCENE, waits a few frames, saves the viewport to SCREENSHOT_OUT.


func _init() -> void:
	var scene_path: String = OS.get_environment("SCREENSHOT_SCENE")
	var out: String = OS.get_environment("SCREENSHOT_OUT")
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("cannot load %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(out)
	if err != OK:
		push_error("save_png failed: %s" % err)
	quit(0 if err == OK else 1)
