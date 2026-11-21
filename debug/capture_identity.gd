extends SceneTree

# Visual evidence for the Terraria identity pass. Boots the real game, frames a
# surface vista (trees, grass, flowers), then opens the inventory and the
# Guide's crafting list and writes one PNG per shot.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_identity.gd

const SHOT_DIR := "res://debug/evidence"

var main: Node
var world: VoxelWorld
var player: VoxelPlayer
var camera: Camera3D
var hud: GameHUD


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("IDENTITYCAP FAIL: main.tscn did not load")
		quit(1)
		return
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _capture(shot_name: String, detail := "") -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/identity_%s.png" % [SHOT_DIR, shot_name]
	var error := image.save_png(path)
	print("IDENTITYCAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	camera = player.get_node("Camera3D")
	hud = main.get_node("HUD")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 3000:
		await process_frame
		frames += 1
	print("IDENTITYCAP world generated=%s spawned=%s frames=%d" % [str(world.is_generated), str(player.spawned), frames])
	await _wait(2.5)

	# --- Surface vista: low three-quarter view into the Forest canopy. ---
	var sx := 64
	var sz := 64
	var surface := world.get_surface_height(sx, sz)
	world.set_generation_focus(Vector3i(sx, surface, sz))
	camera.global_position = Vector3(float(sx) - 22.0, float(surface) + 7.5, float(sz) - 22.0)
	camera.look_at(Vector3(float(sx) + 16.0, float(surface) + 3.5, float(sz) + 16.0), Vector3.UP)
	camera.far = 360.0
	await _wait(1.2)
	await _capture("surface", "forest trees and ground cover")

	# --- Close ground-level frame: block textures and tree bases. ---
	player.set_process(false)
	var highest := surface
	for dz in range(-10, 11, 2):
		for dx in range(-10, 11, 2):
			highest = maxi(highest, world.get_surface_height(sx + dx, sz + dz))
	camera.global_position = Vector3(float(sx) - 9.0, float(highest) + 2.6, float(sz) - 9.0)
	camera.look_at(Vector3(float(sx) + 8.0, float(highest) + 3.2, float(sz) + 8.0), Vector3.UP)
	await _wait(0.6)
	await _capture("ground", "close terrain and trunk detail")

	# --- Guide NPC: stand next to him and look at the character. ---
	var guide := main.get_node_or_null("Guide")
	if guide != null:
		var gpos: Vector3 = guide.global_position
		# Freeze the player controller so its third-person boom stops resetting
		# the camera position while this shot is framed.
		player.set_process(false)
		camera.global_position = gpos + Vector3(2.6, 1.5, 2.6)
		camera.look_at(gpos + Vector3(0.0, 0.95, 0.0), Vector3.UP)
		await _wait(0.8)
		await _capture("guide_npc", "guide character at %s" % str(gpos))
		player.set_process(true)
	else:
		print("IDENTITYCAP guide_npc MISSING: no Guide node in scene")

	# --- Inventory panel. ---
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud._toggle_inventory()
	await _wait(0.6)
	await _capture("inventory", "inventory grid and hotbar")

	# --- Guide crafting list for a real material. ---
	hud._toggle_inventory()
	if player.inventory != null:
		player.inventory.add_item(&"wood", 24)
		player.inventory.add_item(&"stone", 24)
		player.inventory.set_slot("hotbar", 0, {"id": &"wood", "amount": 24})
		player.inventory.select(0)
	hud._toggle_guide()
	await _wait(0.6)
	var listing := 0
	if hud.guide_list != null:
		listing = hud.guide_list.get_child_count()
	print("IDENTITYCAP guide_list_entries=%d detail=%s" % [listing, "" if hud.guide_detail == null else hud.guide_detail.text.substr(0, 80)])
	await _capture("guide_panel", "recipe list filtered by the held material")

	quit(0)
