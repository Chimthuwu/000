extends Node3D

const SaveSystem = preload("res://scripts/save/save_manager.gd")
# Terraria's Merchant shows up once you're carrying 50 silver; this world's
# currency is flat "coin", so a flat threshold stands in for that.
const MERCHANT_COIN_THRESHOLD := 50

@onready var world: VoxelWorld = $VoxelWorld
@onready var player: VoxelPlayer = $Player
@onready var debug_label: Label = $HUD/DebugReadout
@onready var cycle: DayNightCycle = $DayNightCycle
@onready var night: NightManager = $NightManager
@onready var enemy_director: EnemyDirector = $EnemyDirector
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
var _guide: NpcBase = null
var _merchant: NpcBase = null
var _house_timer := 0.0

func _ready() -> void:
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$HUD.process_mode = Node.PROCESS_MODE_ALWAYS
	debug_label.visible = false
	# Journal every player edit live so the save stays sparse on an infinite map.
	world.block_edited.connect(edit_journal.on_block_edited)
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	night.unsettling_event.connect(_on_unsettling_event)
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
		if _guide == null:
			_spawn_guide()
		if _merchant == null and player.get("inventory") != null and player.inventory.count(&"coin") >= MERCHANT_COIN_THRESHOLD:
			_spawn_merchant()
		_update_environmental_clues(delta)
		_update_housing(delta)
		if Input.is_action_just_pressed("debug_spawn_nightlings"):
			enemy_director.debug_spawn_nightlings(3)
		if Input.is_action_just_pressed("debug_spawn_lamp_eater"):
			enemy_director.debug_spawn_lamp_eater()
		if Input.is_action_just_pressed("debug_local_night"):
			var cell := Vector3i(floori(player.camera.global_position.x), floori(player.camera.global_position.y), floori(player.camera.global_position.z))
			night.set_level_for_cell(cell, 1.0)
	# The readout includes a voxel raycast, a group query and string formatting.
	# Only pay for it while the panel is visible, and only four times a second.
	if debug_visible:
		debug_refresh += delta
		if debug_refresh >= 0.25:
			debug_refresh = 0.0
			debug_label.text = _debug_text()

## The Guide waits a few blocks from spawn, on the surface, and is the in-world
## entry point to the crafting guide (talk to him, then press G).
func _spawn_guide() -> void:
	var origin := world.spawn_origin
	# Pick the first flat candidate that is not standing inside a tree.
	var candidates := [Vector2i(6, 3), Vector2i(-6, 4), Vector2i(5, -6), Vector2i(-5, -5), Vector2i(8, 0)]
	var gx := origin.x + 6
	var gz := origin.z + 3
	for offset in candidates:
		var point: Vector2i = offset
		var cx: int = origin.x + point.x
		var cz: int = origin.z + point.y
		var clear := true
		var sites := WorldGenerator.collect_tree_sites_region(world.world_seed, cx - 3, cz - 3, cx + 3, cz + 3)
		for site in sites:
			if Vector2(float(site["x"]) - float(cx), float(site["z"]) - float(cz)).length() < 3.0:
				clear = false
				break
		if clear:
			gx = cx
			gz = cz
			break
	var gy := world.get_surface_height(gx, gz)
	if gy <= 0:
		gy = world.spawn_height()
	var guide := NpcBase.new()
	guide.name = "Guide"
	guide.npc_name = "Guide"
	guide.display_name = "Guide"
	guide.dialogue_lines = PackedStringArray([
		"Hello! My name is the Guide. I know everything about crafting.",
		"Show me a material and I will tell you what can be made with it.",
		"Press G to browse every recipe, and check the workbench requirements.",
		"Build a shelter and light it before nightfall. Good luck out there!",
		"A sealed room with a door, a torch, a chair and a workbench is a home. I would move into one.",
	])
	guide.interaction_radius = 3.0
	add_child(guide)
	guide.global_position = Vector3(float(gx) + 0.5, float(gy) + 1.0, float(gz) + 0.5)
	_guide = guide


## Once the player is carrying enough coin, a Merchant turns up wandering near
## them - unhoused, same as the Guide would be if he had to earn his spot. The
## existing _update_housing() flow is what actually moves them into a house;
## this just puts them in the world so there is someone for it to find.
func _spawn_merchant() -> void:
	var px := floori(player.global_position.x)
	var pz := floori(player.global_position.z)
	var offsets := [Vector2i(5, 3), Vector2i(-5, 4), Vector2i(4, -5), Vector2i(-4, -4), Vector2i(6, 0)]
	var gx := px + 5
	var gz := pz + 3
	for offset in offsets:
		var point: Vector2i = offset
		var cx: int = px + point.x
		var cz: int = pz + point.y
		if world.is_chunk_loaded_at(Vector3i(cx, world.get_surface_height(cx, cz), cz)):
			gx = cx
			gz = cz
			break
	var gy := world.get_surface_height(gx, gz)
	if gy <= 0:
		gy = floori(player.global_position.y)
	var merchant := NpcBase.new()
	merchant.name = "Merchant"
	merchant.npc_name = "Merchant"
	merchant.display_name = "Merchant"
	var profile: NpcProfile = player.npc_service.profiles.get(&"merchant")
	if profile != null:
		merchant.shop_items = profile.shop_items.duplicate()
	merchant.quest_id = &"ore_delivery"
	merchant.dialogue_lines = PackedStringArray([
		"Well now, a customer! I've got torches, salves and tools for sale.",
		"Build me a proper house - sealed, lit, a chair and a workbench - and I'll set up shop for good.",
		"Press B any time to see what I'm selling, once I've moved in.",
		"The Watch could use copper ore. Bring six and I'll make it worth your while.",
	])
	merchant.interaction_radius = 3.0
	add_child(merchant)
	merchant.global_position = Vector3(float(gx) + 0.5, float(gy) + 1.0, float(gz) + 0.5)
	_merchant = merchant
	hud.show_world_hint("A MERCHANT HAS ARRIVED NEARBY.", 4.0)


## Terraria house rules, adapted: the room the player is standing in must be
## sealed, with a door, a light, a chair and a workbench. When one qualifies,
## the nearest NPC without a home moves in - which is what makes merchants
## and the Guide actual residents instead of wandering set dressing.
func _update_housing(delta: float) -> void:
	if hud == null or not player.spawned or not world.is_generated:
		return
	_house_timer -= delta
	if _house_timer > 0.0:
		return
	# The flood fill is bounded but still walks a room; four times a second is
	# plenty to react to a roof being closed or a chair being placed.
	_house_timer = 0.25
	var cell := Vector3i(floori(player.position.x), floori(player.position.y + 0.5), floori(player.position.z))
	var report := HouseValidator.validate(world, cell)
	# Outdoors has no house to report; only speak once the player is inside
	# something that is at least sealed.
	var show := bool(report.get("sealed", false))
	hud.set_house_status(HouseValidator.summary(report) if show else "", bool(report.get("valid", false)))
	if bool(report.get("valid", false)):
		_house_nearest_npc(report)


func _house_nearest_npc(report: Dictionary) -> void:
	var best: NpcBase = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as NpcBase
		if npc == null or not is_instance_valid(npc):
			continue
		if player.npc_service.is_resident(npc):
			continue
		var distance: float = npc.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = npc
	if best == null:
		return
	if not player.npc_service.house_npc(best):
		return
	# Terraria moves the resident into the house; put them in the middle of the
	# room so the player can actually find them there.
	var cells: Array = report.get("cells", [])
	if not cells.is_empty():
		var inside: Vector3i = cells[cells.size() / 2]
		best.global_position = Vector3(inside) + Vector3(0.5, 0.1, 0.5)
	hud.show_world_hint("%s HAS MOVED IN." % best.display_name.to_upper(), 4.0)
	player.set_status("%s IS NOW A RESIDENT" % best.display_name.to_upper())


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
		hud.show_world_hint("ABANDONED CAMP — a cold torch and scattered ore.", 5.0)


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
		hud.show_world_hint("THE CAVERNS SHIFT IN THE DARK", 4.0)


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
	var caster := player.get_node_or_null("ArcaneCaster") as ArcaneCaster
	if caster != null:
		caster.stop_action_state()
	player.respawn_at(spawn)
	if hud != null:
		hud.hide_death()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _survival_save_data() -> Dictionary:
	var caster := player.get_node_or_null("ArcaneCaster") as ArcaneCaster
	var data := {
		"health": player.health,
		"god_mode": player.god_mode,
		"reserve": caster.reserve if caster != null else 0.0,
		"selected_cartridge": caster.selected_cartridge if caster != null else 0,
		"temporary_lights": caster.serialize_temporary_lights() if caster != null else []
	}
	return {
		"player_stats": {
			"health": data["health"],
			"god_mode": data["god_mode"],
			"reserve": data["reserve"],
			"selected_cartridge": data["selected_cartridge"],
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
		"night_levels": night.to_save_array()
	}
	# Persist felled tree sites so they stay gone after save/load
	var vegetation: WorldVegetation = world.vegetation
	if vegetation != null and not vegetation.felled_sites.is_empty():
		var felled_data: Dictionary = {}
		for cell: Vector3i in vegetation.felled_sites.keys():
			felled_data[str(cell)] = true
		extra["felled_sites"] = felled_data
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
			var caster := player.get_node_or_null("ArcaneCaster") as ArcaneCaster
			if caster != null:
				caster.show_context_hint(SaveSystem.FORMAT_CHANGED_MESSAGE, 3.0)
		return
	# restore_save wiped the world's modified_chunks; re-seed the live journal
		# from the loaded edits so subsequent saves keep old edits.
		edit_journal.seed_from_edits(save_data.get("edited_cells", {}))
		var metadata: Dictionary = save_data["metadata"]
		var saved_position: Array = metadata.get("player_position", [])
		var m4_data: Dictionary = metadata.get("m4", {})
		if saved_position.size() == 3:
			player.position = Vector3(saved_position[0], saved_position[1], saved_position[2])
		cycle.restore_time(float(m4_data.get("day_night_elapsed", 0.0)))
		night.restore_from_array(m4_data.get("night_levels", []))
		_restore_survival_state(metadata, m4_data)
		# Restore felled tree sites so they stay gone after save/load
		var vegetation: WorldVegetation = world.vegetation
		if vegetation != null and m4_data.has("felled_sites"):
			var felled_data: Dictionary = m4_data["felled_sites"]
			for cell_str: String in felled_data.keys():
				# Parse "Vector3i(x, y, z)" string back to Vector3i
				var parts := cell_str.trim_prefix("Vector3i(").trim_suffix(")").split(", ")
				if parts.size() == 3:
					var cell := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
					vegetation.felled_sites[cell] = true
		# Agent 2: restore the real gameplay state from the same nested key.
		if m4_data.has("gameplay"):
			player.deserialize_gameplay_state(m4_data["gameplay"])
		# A loaded save may already have defeated the Warden; Hallow applies to newly
		# streamed terrain from that point on.
		_refresh_hallow()


func _restore_survival_state(metadata: Dictionary, m4_data: Dictionary) -> void:
	var survival: Dictionary = m4_data.get("survival", {})
	var caster := player.get_node_or_null("ArcaneCaster") as ArcaneCaster
	if not survival.is_empty():
		player.health = clampf(float(survival.get("health", player.health)), 0.0, VoxelPlayer.MAX_HEALTH)
		player.regen_grace = 2.0
		player.god_mode = bool(survival.get("god_mode", false))
		player.dead = player.health <= 0.0
		player.damage_cooldown = 0.0
		if caster != null:
			caster.reserve = clampf(float(survival.get("reserve", caster.reserve)), 0.0, caster.CONFIG.reserve_capacity)
			caster.selected_cartridge = clampi(int(survival.get("selected_cartridge", 0)), 0, caster.CARTRIDGES.size() - 1)
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
	var night_level := world.get_night_level(light_cell)
	var chunk_coords: Vector3i = world._chunk_of(light_cell)
	var biome_name := BiomeManager.biome_name(world.get_biome_at(light_cell))
	return "TERRARIA 3D M4 | FPS %d | Draw %d | HP %d | %s | %s | LIGHT %d | NIGHT %.2f\nChunks %d loaded, %d generated, %d meshed, %d lit | blocks %d\nNight chunk %s | enemies %d | static lights %d | WASD move | 1–0 or WHEEL hotbar | K save | J load | F3 HUD | F flashlight %s | F6 nightlings | F7 lamp eater | F8 local night" % [Engine.get_frames_per_second(), draw_calls, roundi(player.health), cycle.phase_name.to_upper(), biome_name, light_level, night_level, loaded, generated, meshed, world.initialized_light_chunks, block_total, str(chunk_coords), get_tree().get_nodes_in_group("enemies").size(), world.static_light_sources.size(), "ON" if world.flashlight_enabled else "OFF"]

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pause_due_to_focus = true
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and pause_due_to_focus:
		pause_due_to_focus = false
		get_tree().paused = false