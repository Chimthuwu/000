extends Node3D
class_name ArcaneCaster

signal noise_emitted(world_position: Vector3, strength: float)
signal combat_hit(cell: Vector3i, damage: float, cartridge_id: StringName)
signal fired(cartridge_id: StringName, kick: float)
signal cartridge_changed(index: int, cartridge: CartridgeDef)

const CARTRIDGES: Array[CartridgeDef] = [
	preload("res://data/cartridges/excavator.tres"),
	preload("res://data/cartridges/beacon.tres"),
	preload("res://data/cartridges/photon_slug.tres"),
	preload("res://data/cartridges/flare.tres")
]
const CONFIG: ArcaneCasterConfig = preload("res://data/cartridges/arcane_caster_config.tres")

var player: Node3D
var world: VoxelWorld
var camera: Camera3D

var reserve := 0.0
var selected_cartridge := 0
var inventory: Dictionary = {}
var temporary_lights: Array[Dictionary] = []
var status_message := ""
var status_time := 0.0
var hint_text := ""
var hint_time := 0.0
var hint_fade := 0.0
var hint_suppress_time := 0.0
var projectiles: Array[Dictionary] = []

# The legacy ArcaneCaster stays in the scene because saves, the vehicle prompts
# and the enemy drain still address it, but it no longer reads input, fires or
# edits the world: block placement and mining belong to the player hotbar.
var disabled := true

func _ready() -> void:
	player = get_parent()
	world = player.get_parent().get_node("VoxelWorld") as VoxelWorld
	camera = player.get_node("Camera3D") as Camera3D
	reserve = CONFIG.starting_reserve
	set_process_unhandled_input(false)

func _process(delta: float) -> void:
	if world.is_generated and player.get("spawned"):
		var player_cell := Vector3i(floori(player.position.x), floori(player.position.y), floori(player.position.z))
		var light_level := world.get_light_level(player_cell)
		if light_level > 0:
			reserve = minf(CONFIG.reserve_capacity, reserve + CONFIG.recharge_per_second_at_full_light * float(light_level) / 15.0 * delta)
		elif world.get_night_level(player_cell) >= 0.7:
			# Standing unlit in high Night bleeds the reserve. Light is not just
			# ammo: it is the thing keeping the dark from taking your tools.
			reserve = maxf(0.0, reserve - 2.5 * delta)
	_update_temporary_lights(delta)
	if world.is_generated:
		_update_projectiles(delta)
	if status_time > 0.0:
		status_time -= delta
	else:
		status_message = ""
	if hint_time > 0.0:
		hint_time = maxf(0.0, hint_time - delta)
	hint_suppress_time = maxf(0.0, hint_suppress_time - delta)

func _fire_selected_cartridge() -> void:
	var cartridge: CartridgeDef = CARTRIDGES[selected_cartridge]
	var player_cell := Vector3i(floori(player.position.x), floori(player.position.y), floori(player.position.z))
	var light_level := world.get_light_level(player_cell)
	if light_level < cartridge.minimum_light:
		_set_status("TOO DARK TO FIRE")
		return
	if reserve < cartridge.energy_cost:
		_set_status("LOW MANA RESERVE")
		return
	reserve -= cartridge.energy_cost
	fired.emit(cartridge.cartridge_id, _kick_for(cartridge))
	if cartridge.action == "flare":
		_fire_flare(cartridge)
	else:
		_fire_hitscan(cartridge)

func _kick_for(cartridge: CartridgeDef) -> float:
	match cartridge.action:
		"photon":
			return 0.62
		"flare":
			return 0.46
		"beacon":
			return 0.30
		_:
			return 0.38

# Photon Slug traces a beam, the Beacon plants a pulsing light, and the
# Excavator drills a short burst into whatever surface it hits.
func _fire_hitscan(cartridge: CartridgeDef) -> void:
	var direction := -camera.global_basis.z.normalized()
	var hit := _voxel_raycast(cartridge.range)
	var event_position: Vector3 = camera.global_position + direction * cartridge.range
	var impact_direction := Vector3.UP
	var impacted := false
	var enemy_hit := _enemy_raycast(cartridge.range)
	if not enemy_hit.is_empty() and (hit.is_empty() or float(enemy_hit["distance"]) < float(hit["distance"])):
		var enemy: NightEnemy = enemy_hit["enemy"]
		event_position = enemy_hit["point"]
		impacted = true
		if cartridge.damage > 0.0:
			enemy.apply_damage(cartridge.damage)
			combat_hit.emit(Vector3i(floori(enemy.position.x), floori(enemy.position.y), floori(enemy.position.z)), cartridge.damage, cartridge.cartridge_id)
		hit = {}
	elif not hit.is_empty():
		event_position = hit["point"]
		impact_direction = Vector3(hit["face_normal"])
		impacted = true
		if cartridge.damage > 0.0:
			combat_hit.emit(hit["cell"], cartridge.damage, cartridge.cartridge_id)
	match cartridge.action:
		"excavate":
			if not hit.is_empty():
				_mine_burst(hit)
			else:
				_set_status("NO BLOCK IN RANGE")
		"beacon":
			if _place_temporary_light(cartridge, hit):
				var planted: Vector3i = hit["cell"] + hit["face_normal"]
				Vfx.pillar(world, Vector3(planted) + Vector3(0.5, 0.0, 0.5), cartridge.accent_color, 4.0, 1.4)
		"photon":
			Vfx.beam(world, camera.global_position + direction * 0.45, event_position, cartridge.accent_color, 0.05, 0.14, 8.0)
			_set_status("PHOTON BEAM HIT" if impacted else "PHOTON BEAM FIRED")
	if impacted:
		Vfx.burst(world, event_position, cartridge.accent_color, impact_direction, 12, 4.5, 0.05, 0.35)
	if cartridge.night_noise > 0.0:
		noise_emitted.emit(event_position, cartridge.night_noise)
		world.emit_night_noise(event_position, cartridge.night_noise)

# The Excavator burst removes up to three connected blocks along the impact axis.
# Hardness and tool-tier gating are owned by the world's MiningSystem so the
# rule for "what can this tool break" lives in one place.
func _mine_burst(hit: Dictionary) -> void:
	var normal: Vector3i = hit["face_normal"]
	var step := Vector3i(-normal.x, -normal.y, -normal.z)
	if step == Vector3i.ZERO:
		step = Vector3i.DOWN
	var cell: Vector3i = hit["cell"]
	var tool_tier := 1
	var tier_value = player.get("mining_tier")
	if tier_value != null:
		tool_tier = int(tier_value)
	var mined := 0
	var last_name: StringName = &""
	var blocked := false
	for depth in range(3):
		if not world._inside_world(cell):
			break
		var mined_id := world.get_block_id(cell)
		if mined_id == world.air_id:
			break
		if not MiningSystem.can_mine(world, cell, tool_tier):
			blocked = true
			break
		var result := MiningSystem.break_block(world, cell, tool_tier)
		if not bool(result.get("mined", false)):
			break
		var drop: Dictionary = result.get("drop", {})
		last_name = drop.get("block_id", &"")
		if last_name != &"":
			inventory[last_name] = int(inventory.get(last_name, 0)) + int(drop.get("count", 1))
		mined += 1
		cell += step
	if mined == 0:
		if blocked:
			_set_status("TOO HARD — BETTER TOOL NEEDED")
		else:
			_set_status("NO BLOCK IN RANGE")
	elif mined == 1:
		_set_status("MINED %s" % String(last_name).to_upper())
	else:
		_set_status("DRILLED %d %s" % [mined, String(last_name).to_upper()])

func _fire_flare(cartridge: CartridgeDef) -> void:
	var direction := -camera.global_basis.z.normalized()
	var start := camera.global_position + direction * 0.55
	var body := Vfx.flare_projectile(world, start, cartridge.accent_color)
	if body == null:
		return
	projectiles.append({
		"node": body,
		"position": start,
		"velocity": direction * 16.0 + Vector3.UP * 2.2,
		"cartridge": cartridge,
		"life": 4.0
	})
	_set_status("FLARE AWAY")

# Flares arc under gravity and plant their temporary light where they land.
func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var shot: Dictionary = projectiles[index]
		var position: Vector3 = shot["position"]
		var velocity: Vector3 = shot["velocity"]
		shot["life"] = float(shot["life"]) - delta
		var landed := false
		var steps := 3
		var step_dt := delta / float(steps)
		for substep in range(steps):
			velocity.y -= 22.0 * step_dt
			var next := position + velocity * step_dt
			var cell := Vector3i(floori(next.x), floori(next.y), floori(next.z))
			if not world._inside_world(cell) or world.get_block_id(cell) != world.air_id:
				landed = true
				break
			position = next
		shot["position"] = position
		shot["velocity"] = velocity
		var node: Node3D = shot["node"]
		if is_instance_valid(node):
			node.global_position = position
		if landed or float(shot["life"]) <= 0.0:
			_land_flare(shot, position)
			if is_instance_valid(node):
				node.queue_free()
			projectiles.remove_at(index)

func _land_flare(shot: Dictionary, position: Vector3) -> void:
	var cartridge: CartridgeDef = shot["cartridge"]
	var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	var target := cell
	if not world._inside_world(target) or world.get_block_id(target) != world.air_id:
		target = cell + Vector3i.UP
	var torch_id: int = int(world.block_ids.get(cartridge.light_block_id, -1))
	if torch_id >= 0 and world._inside_world(target) and world.get_block_id(target) == world.air_id and world.set_block(target, torch_id):
		temporary_lights.append({"cell": target, "block_id": torch_id, "remaining": cartridge.duration})
		Vfx.pillar(world, Vector3(target) + Vector3(0.5, 0.0, 0.5), cartridge.accent_color, 2.5, 0.8, 0.16)
	Vfx.burst(world, position, cartridge.accent_color, Vector3.UP, 14, 5.0, 0.06, 0.45)
	if cartridge.damage > 0.0:
		for candidate in get_tree().get_nodes_in_group("enemies"):
			var enemy := candidate as NightEnemy
			if enemy == null or not is_instance_valid(enemy):
				continue
			if enemy.global_position.distance_to(position) <= 1.8:
				enemy.apply_damage(cartridge.damage)
				combat_hit.emit(Vector3i(floori(enemy.position.x), floori(enemy.position.y), floori(enemy.position.z)), cartridge.damage, cartridge.cartridge_id)
	if cartridge.night_noise > 0.0:
		noise_emitted.emit(position, cartridge.night_noise)
		world.emit_night_noise(position, cartridge.night_noise)
	_set_status("FLARE LANDED")

func _enemy_raycast(max_distance: float) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z.normalized()
	var nearest := max_distance
	var result: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as NightEnemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var center := enemy.global_position + Vector3.UP * 0.25
		var offset := center - origin
		var along := offset.dot(direction)
		if along < 0.0 or along > nearest:
			continue
		var closest := origin + direction * along
		if closest.distance_squared_to(center) > 0.45 * 0.45:
			continue
		nearest = along
		result = {"enemy": enemy, "point": closest, "distance": along}
	return result
func _place_temporary_light(cartridge: CartridgeDef, hit: Dictionary) -> bool:
	if hit.is_empty():
		_set_status("NO SURFACE IN RANGE")
		return false
	var cell: Vector3i = hit["cell"] + hit["face_normal"]
	if not world._inside_world(cell) or world.get_block_id(cell) != world.air_id:
		_set_status("NO ROOM FOR LIGHT")
		return false
	var torch_id: int = world.block_ids[cartridge.light_block_id]
	if not world.set_block(cell, torch_id):
		return false
	var entry := {"cell": cell, "block_id": torch_id, "remaining": cartridge.duration}
	if cartridge.action == "beacon":
		entry["aura"] = _spawn_beacon_aura(cell, cartridge.accent_color)
		Vfx.pillar(world, Vector3(cell) + Vector3(0.5, 0.0, 0.5), cartridge.accent_color, 2.0, 0.9, 0.12)
		temporary_lights.append(entry)
		_set_status("BEACON DEPLOYED")
	else:
		temporary_lights.append(entry)
		_set_status("TEMPORARY LIGHT PLANTED")
	return true


func _spawn_beacon_aura(cell: Vector3i, color: Color) -> MeshInstance3D:
	var aura := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	sphere.radial_segments = 12
	sphere.rings = 6
	aura.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, 0.10)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	aura.material_override = material
	aura.position = Vector3(cell) + Vector3(0.5, 0.62, 0.5)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(aura)
	return aura

func _update_temporary_lights(delta: float) -> void:
	for index in range(temporary_lights.size() - 1, -1, -1):
		temporary_lights[index]["remaining"] -= delta
		if temporary_lights[index]["remaining"] > 0.0:
			continue
		var cell: Vector3i = temporary_lights[index]["cell"]
		var stored_id: int = temporary_lights[index].get("block_id", -1)
		if stored_id >= 0 and world._inside_world(cell) and world.get_block_id(cell) == stored_id:
			world.set_block(cell, world.air_id)
		var aura = temporary_lights[index].get("aura")
		if is_instance_valid(aura):
			aura.queue_free()
		temporary_lights.remove_at(index)


func serialize_temporary_lights() -> Array:
	var result: Array = []
	for light in temporary_lights:
		result.append({
			"cell": [int(light["cell"].x), int(light["cell"].y), int(light["cell"].z)],
			"block_id": int(light.get("block_id", -1)),
			"remaining": float(light.get("remaining", 0.0)),
			"aura": is_instance_valid(light.get("aura"))
		})
	return result


func restore_temporary_lights(saved: Array) -> void:
	temporary_lights.clear()
	for entry in saved:
		if not entry is Dictionary:
			continue
		var coords: Array = entry.get("cell", [])
		if coords.size() != 3:
			continue
		var cell := Vector3i(int(coords[0]), int(coords[1]), int(coords[2]))
		if not world._inside_world(cell):
			continue
		var remaining := float(entry.get("remaining", 0.0))
		if remaining <= 0.0:
			continue
		var light: Dictionary = {"cell": cell, "block_id": int(entry.get("block_id", -1)), "remaining": remaining}
		if bool(entry.get("aura", false)):
			light["aura"] = _spawn_beacon_aura(cell, CARTRIDGES[1].accent_color)
		temporary_lights.append(light)


func _voxel_raycast(max_distance: float) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(signf(direction.x), signf(direction.y), signf(direction.z))
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)
	for axis in range(3):
		if absf(direction[axis]) < 0.000001:
			continue
		t_delta[axis] = absf(1.0 / direction[axis])
		var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0))
		t_max[axis] = (boundary - origin[axis]) / direction[axis]
	var previous := cell
	var face_normal := Vector3i.ZERO
	var distance := 0.0
	while distance <= max_distance:
		if not world._inside_world(cell):
			return {}
		var block_id := world.get_block_id(cell)
		if block_id != world.air_id:
			return {"cell": cell, "previous_air": previous, "face_normal": face_normal, "point": origin + direction * distance, "distance": distance}
		previous = cell
		var axis := 0
		if t_max.y < t_max.x:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		distance = t_max[axis]
		if distance > max_distance:
			break
		cell[axis] += step[axis]
		face_normal = Vector3i.ZERO
		face_normal[axis] = -step[axis]
		t_max[axis] += t_delta[axis]
	return {}

func _show_hint(text: String, duration: float) -> void:
	hint_text = text
	hint_time = duration
	hint_fade = duration


func show_context_hint(text: String, duration: float) -> void:
	if hint_suppress_time > 0.0:
		return
	_show_hint(text, duration)


# Kept as the vehicle-exit hook even though the throwable actions are gone.
func stop_action_state() -> void:
	hint_time = 0.0

func _set_status(message: String) -> void:
	status_message = message
	status_time = 2.0

