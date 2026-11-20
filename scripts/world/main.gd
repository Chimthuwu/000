extends Node3D

const SaveSystem = preload("res://scripts/save/save_manager.gd")

@onready var world: VoxelWorld = $VoxelWorld
@onready var player: VoxelPlayer = $Player
@onready var debug_label: Label = $HUD/DebugReadout
@onready var cycle: DayNightCycle = $DayNightCycle
@onready var gloom: GloomManager = $GloomManager
@onready var enemy_director: EnemyDirector = $EnemyDirector
@onready var buggy: DuneBuggy = $Buggy
@onready var hud: GameHUD = $HUD

var edit_journal := BlockEditJournal.new()
var debug_visible := false
var debug_refresh := 0.0
var pause_due_to_focus := false
var console_open := false
var clue_cooldown := 0.0
var last_clue_site := ""
var _auto_continue := false
var _hallow_checked := false

func _ready() -> void:
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$HUD.process_mode = Node.PROCESS_MODE_ALWAYS
	debug_label.visible = false
	# Journal every player edit live so the save stays sparse on an infinite map.
	world.block_edited.connect(edit_journal.on_block_edited)
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	gloom.unsettling_event.connect(_on_unsettling_event)
	player.progression.flag_set.connect(_on_progression_flag)
	_auto_continue = bool(SettingsStore.get_value("game", "continue_on_boot", false))

func _process(delta: float) -> void:
	if not world.player_tracking and player.spawned:
		world.player_tracking = true
	if not _hallow_checked and player.spawned:
		_hallow_checked = true
		_refresh_hallow()
	if Input.is_action_just_pressed("toggle_debug"):
		debug_visible = not debug_visible
		debug_label.visible = debug_visible
		debug_refresh = 0.0
		if debug_visible:
			debug_label.text = _debug_text()
	if Input.is_action_just_pressed("toggle_flashlight"):
		world.set_flashlight_enabled(not world.flashlight_enabled)
	if Input.is_action_just_pressed("save_world"):
		save_game()
	if Input.is_action_just_pressed("load_world"):
		load_game()
	if _auto_continue and world.is_generated and player.spawned:
		_auto_continue = false
		load_game()
	if world.is_generated and player.spawned:
		_update_environmental_clues(delta)
		if Input.is_action_just_pressed("debug_spawn_gloomlings"):
			enemy_director.debug_spawn_gloomlings(3)
		if Input.is_action_just_pressed("debug_spawn_lamp_eater"):
			enemy_director.debug_spawn_lamp_eater()
		if Input.is_action_just_pressed("debug_local_gloom"):
			var cell := Vector3i(floori(player.camera.global_position.x), floori(player.camera.global_position.y), floori(player.camera.global_position.z))
			gloom.set_level_for_cell(cell, 1.0)
	# The readout includes a voxel raycast, a group query and string formatting.
	# Only pay for it while the panel is visible, and only four times a second.
	if debug_visible:
		debug_refresh += delta
		if debug_refresh >= 0.25:
			debug_refresh = 0.0
			debug_label.text = _debug_text()

func _update_environmental_clues(delta: float) -> void:
	clue_cooldown -= delta
	if clue_cooldown > 0.0:
		return
	clue_cooldown = 0.5
	var cell := Vector3i(floori(player.position.x), 0, floori(player.position.z))
	var site := WorldGenerator.derelict_site_near(world.world_seed, cell.x, cell.z)
	var site_key := ""
	if not site.is_empty():
		site_key = "%d,%d" % [int(site["x"]), int(site["z"])]
	if site_key == last_clue_site:
		return
	last_clue_site = site_key
	if hud != null and not site_key.is_empty():
		hud.show_world_hint("ABANDONED CAMP — a cold torch and scattered ore. Something ate the rest.", 5.0)


# The Hallow is reserved for a future end-of-pre-hardmode Underworld event.
# The optional Hollow Warden must never unlock it; until that event exists the
# dev console `hallow on|off` command is the explicit debug override.
func _on_progression_flag(flag: StringName) -> void:
	if flag == &"underworld_vanquished":
		BiomeManager.set_hallow_enabled(true)


func _refresh_hallow() -> void:
	BiomeManager.set_hallow_enabled(player.progression.has_flag(&"underworld_vanquished"))


func _on_unsettling_event(_position: Vector3) -> void:
	if hud != null:
		hud.show_world_hint("SOMETHING MOVES BEYOND THE LIGHT", 4.0)


func _on_player_died() -> void:
	# Do not pause the tree: the world must keep breathing while the player is
	# dead, so the respawn lands in a world that continued to change.
	if hud != null:
		hud.show_death()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_respawned() -> void:
	if hud != null:
		hud.hide_death()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn_player() -> void:
	if not world.is_generated:
		return
	var spawn := Vector3(float(world.spawn_origin.x) + 0.5, float(world.spawn_height()) + 1.0, float(world.spawn_origin.z) + 0.5)
	world.set_generation_focus(world.spawn_origin)
	var caster := player.get_node_or_null("Lumencaster") as Lumencaster
	if caster != null:
		caster.stop_action_state()
	player.respawn_at(spawn)
	if hud != null:
		hud.hide_death()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _survival_save_data() -> Dictionary:
	var caster := player.get_node_or_null("Lumencaster") as Lumencaster
	var data := {
		"health": player.health,
		"god_mode": player.god_mode,
		"reserve": caster.reserve if caster != null else 0.0,
		"selected_cartridge": caster.selected_cartridge if caster != null else 0,
		"projector_block": String(caster.selected_projector_block) if caster != null else "",
		"temporary_lights": caster.serialize_temporary_lights() if caster != null else []
	}
	return {
		"player_stats": {
			"health": data["health"],
			"god_mode": data["god_mode"],
			"reserve": data["reserve"],
			"selected_cartridge": data["selected_cartridge"],
			"projector_block": data["projector_block"]
		},
		"inventory": caster.inventory.duplicate() if caster != null else {},
		"survival": data,
		# Agent 2: real inventory/equipment/hotbar/progression/stats in one
		# nested key of the existing v4 world save. No second save format.
		"gameplay": player.serialize_gameplay_state()
	}


func save_game() -> void:
	if not world.is_generated or not player.spawned:
		return
	var extra := {
		"day_night_elapsed": cycle.elapsed_seconds,
		"gloom_levels": gloom.to_save_array(),
		"buggy": buggy.to_save_data()
	}
	extra.merge(_survival_save_data(), true)
	SaveSystem.save_world(world, edit_journal, player.position, extra)


func load_game() -> void:
	if not world.is_generated:
		return
	var had_directory := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://worlds/%d" % world.world_seed))
	var save_data := SaveSystem.load_world(world.world_seed, world)
	if save_data.is_empty() or not world.restore_save(save_data):
		if had_directory:
			# Approved migration policy: old formats are discarded, not converted.
			var caster := player.get_node_or_null("Lumencaster") as Lumencaster
			if caster != null:
				caster.show_context_hint(SaveSystem.FORMAT_CHANGED_MESSAGE, 3.0)
		return
	# restore_save wiped the world's modified_chunks; re-seed the live journal
	# from the loaded edits so subsequent saves keep old edits.
	edit_journal.seed_from_edits(save_data.get("edited_cells", {}))
	var metadata: Dictionary = save_data["metadata"]
	var saved_position: Array = metadata.get("player_position", [])
	var m4_data: Dictionary = metadata.get("m4", {})
	var buggy_data: Dictionary = m4_data.get("buggy", {})
	buggy.apply_save_data(buggy_data)
	if saved_position.size() == 3:
		player.position = Vector3(saved_position[0], saved_position[1], saved_position[2])
	if bool(buggy_data.get("driving", false)):
		player.position = buggy.get_exit_position()
	cycle.restore_time(float(m4_data.get("day_night_elapsed", 0.0)))
	gloom.restore_from_array(m4_data.get("gloom_levels", []))
	_restore_survival_state(metadata, m4_data)
	# Agent 2: restore the real gameplay state from the same nested key.
	if m4_data.has("gameplay"):
		player.deserialize_gameplay_state(m4_data["gameplay"])
	# A loaded save may already have defeated the Warden; Hallow applies to newly
	# streamed terrain from that point on.
	_refresh_hallow()


func _restore_survival_state(metadata: Dictionary, m4_data: Dictionary) -> void:
	var survival: Dictionary = m4_data.get("survival", {})
	var caster := player.get_node_or_null("Lumencaster") as Lumencaster
	if not survival.is_empty():
		player.health = clampf(float(survival.get("health", player.health)), 0.0, VoxelPlayer.MAX_HEALTH)
		player.regen_grace = 2.0
		player.god_mode = bool(survival.get("god_mode", false))
		player.dead = player.health <= 0.0
		player.damage_cooldown = 0.0
		if caster != null:
			caster.reserve = clampf(float(survival.get("reserve", caster.reserve)), 0.0, caster.CONFIG.reserve_capacity)
			caster.selected_cartridge = clampi(int(survival.get("selected_cartridge", 0)), 0, caster.CARTRIDGES.size() - 1)
			var block_name := String(survival.get("projector_block", ""))
			if block_name != "" and world.block_ids.has(StringName(block_name)):
				caster.selected_projector_block = StringName(block_name)
			caster.restore_temporary_lights(survival.get("temporary_lights", []))
	var saved_inventory: Dictionary = metadata.get("inventory", {})
	if caster != null and not saved_inventory.is_empty():
		caster.inventory = saved_inventory.duplicate()
	if player.dead and hud != null:
		hud.show_death()


func _debug_text() -> String:
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var generated: int = world.generated_chunk_count
	var meshed: int = world.meshed_chunk_count
	var loaded: int = world.chunk_records.size()
	var block_total: int = world.loaded_block_count() if world.is_generated else 0
	var light_cell := Vector3i(floori(player.camera.global_position.x), floori(player.camera.global_position.y), floori(player.camera.global_position.z))
	var hit: Dictionary = player._voxel_raycast(7.0)
	if not hit.is_empty():
		light_cell = hit["previous_air"]
	var light_level: int = world.get_light_level(light_cell) if world.is_generated else 0
	var gloom_level := world.get_gloom_level(light_cell)
	var chunk_coords: Vector3i = world._chunk_of(light_cell)
	var biome_name := BiomeManager.biome_name(world.get_biome_at(light_cell))
	return "LUMENFALL M4 | FPS %d | Draw %d | HP %d | %s | %s | LIGHT %d | GLOOM %.2f\nChunks %d loaded, %d generated, %d meshed, %d lit | blocks %d\nGloom chunk %s | enemies %d | static lights %d | WASD move | 1–4 cartridges | WHEEL cartridges/projector | K save | J load | F3 HUD | F flashlight %s | F6 gloomlings | F7 lamp eater | F8 local gloom" % [Engine.get_frames_per_second(), draw_calls, roundi(player.health), cycle.phase_name.to_upper(), biome_name, light_level, gloom_level, loaded, generated, meshed, world.initialized_light_chunks, block_total, str(chunk_coords), get_tree().get_nodes_in_group("enemies").size(), world.static_light_sources.size(), "ON" if world.flashlight_enabled else "OFF"]

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pause_due_to_focus = true
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and pause_due_to_focus:
		pause_due_to_focus = false
		get_tree().paused = false