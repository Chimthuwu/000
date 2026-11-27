extends Node3D
class_name VoxelPlayer

## Agent 2 player controller. The proven fixed-step voxel movement is retained;
## tools, weapons, inventory, crafting and progression are layered on top.

signal died
signal respawned
signal gameplay_message(text: String)
signal mining_progress_changed(progress: float, cell: Vector3i)
signal camera_mode_changed(mode: int)
# A chest under the crosshair was interacted with. The HUD owns the panel; the
# player only reports which world cell to open.
signal container_requested(cell: Vector3i)

const MAX_HEALTH := 100.0
const PLAYER_HALF_EXTENTS := Vector3(0.32, 0.9, 0.32)
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_SPEED := 6.2
const GRAVITY := 20.0
const FIXED_STEP := 1.0 / 60.0
const COLLISION_EPSILON := 0.001
const LOOK_SENSITIVITY := 0.0022
var look_sensitivity_scale := 1.0
const REACH := 6.0
const FALL_SAFE_HEIGHT := 4.0
const FALL_DAMAGE_PER_BLOCK := 9.0

@onready var camera: Camera3D = $Camera3D
@onready var world = get_parent().get_node("VoxelWorld")

var velocity := Vector3.ZERO
var on_floor := false
var driving := false
var fixed_accumulator := 0.0
var spawned := false
var health := MAX_HEALTH
var max_health := MAX_HEALTH
var damage_cooldown := 0.0
var slow_time := 0.0
var god_mode := false
var dead := false
var axis_collided := PackedByteArray([0, 0, 0])
# Compatibility with the shared Main save/load hooks.
var regen_grace := 0.0

# --- Agent 2 gameplay state ---
var gateway: WorldGateway
var inventory: InventoryModel
var crafting: CraftingSystem
var progression: ProgressionSystem
var statuses: StatusController
var weapons: WeaponController
var npc_service: NpcService
var discovery_rewards: DiscoveryRewards
# Chests live in the world, not in the player: the store is keyed by cell.
var containers := ContainerStore.new()

var status_message := ""
var status_time := 0.0
var mining_target := Vector3i(-1, -1, -1)
var mining_progress := 0.0
## Which quarter of a tree chop was last shown, so chips fly once per stage.
var tree_damage_stage := 0
## Elapsed time on the current mining target, so a tap sound plays on a
## steady beat instead of once per frame.
var _mine_tick_clock := 0.0
var camera_mode := 1  # 0 = first person, 1 = third person (default)
var avatar: Node3D
var viewmodel: HeldItemViewmodel
var _avatar_hand: Node3D
var _avatar_held_item: Node3D
var _fall_start_y := 0.0
var _interact_cooldown := 0.0
var _discovery_check_time := 0.0

# --- Agent 1 MiningSystem integration (public, UI-visible) ---
# Tool tier is DERIVED from the equipped item, never set by hand per tool.
var mining_tier := 0
# Agent 1's collection sink. Drained into the real InventoryModel each frame.
var collected_blocks: Dictionary = {}
## Wood owed for trees that are still falling, keyed by the stump cell.
var _pending_tree_loot: Dictionary = {}
# Target readout for Agent 3's HUD and for player-facing feedback.
var target_block_name := ""
var target_mining_tier := 0
var target_can_mine := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SettingsStore.load_settings()
	look_sensitivity_scale = float(SettingsStore.get_value("input", "mouse_sensitivity", 1.0))
	add_to_group("player")
	gateway = WorldGateway.new(world)
	inventory = InventoryModel.new()
	progression = ProgressionSystem.new()
	discovery_rewards = DiscoveryRewards.new()
	statuses = StatusController.new()
	crafting = CraftingSystem.new(inventory, progression, gateway)
	npc_service = NpcService.new(inventory, progression)
	weapons = WeaponController.new()
	weapons.name = "WeaponController"
	add_child(weapons)
	weapons.player = self
	weapons.inventory = inventory
	weapons.gateway = gateway
	inventory.selection_changed.connect(_refresh_mining_tier)
	inventory.equipment_changed.connect(_refresh_mining_tier)
	inventory.changed.connect(_refresh_mining_tier)
	_refresh_mining_tier()
	_fall_start_y = position.y
	# Terraria-style game: the ArcaneCaster is gone from gameplay. The node is
	# kept only as a data source for Agent 3's legacy HUD, fully disabled.
	var legacy := get_node_or_null("ArcaneCaster")
	if legacy != null:
		legacy.set("disabled", true)
	# The first-person viewmodel shows whatever the hotbar has selected, so an
	# axe in hand is visible before you swing it.
	viewmodel = camera.get_node_or_null("Viewmodel") as HeldItemViewmodel
	if viewmodel != null:
		viewmodel.set_first_person(camera_mode == 0)
		viewmodel.set_item(inventory.held_item())
	_build_avatar()

	# Starter kit: real tools/weapons, granted once so reloads never duplicate.
	if not progression.has_flag(&"starter_kit_granted"):
		inventory.add_item(&"wooden_pickaxe", 1)
		inventory.add_item(&"wooden_axe", 1)
		inventory.add_item(&"wooden_sword", 1)
		inventory.add_item(&"torch", 10)
		inventory.add_item(&"dirt", 40)
		inventory.select(0)
		progression.set_flag(&"starter_kit_granted")


func _physics_process(delta: float) -> void:
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	_interact_cooldown = maxf(0.0, _interact_cooldown - delta)
	statuses.tick(delta)
	if dead:
		return
	if driving:
		return
	if not spawned:
		if world.is_generated:
			var spawn_height: int = world.spawn_height()
			position = Vector3(float(world.spawn_origin.x) + 0.5, float(spawn_height) + 1.0, float(world.spawn_origin.z) + 0.5)
			spawned = true
			_fall_start_y = position.y
		return
	_update_light_regen(delta)
	fixed_accumulator += delta
	var steps := 0
	while fixed_accumulator >= FIXED_STEP and steps < 4:
		_simulate_fixed_step(FIXED_STEP)
		fixed_accumulator -= FIXED_STEP
		steps += 1
	if steps == 4:
		fixed_accumulator = 0.0


func _process(delta: float) -> void:
	if status_time > 0.0:
		status_time -= delta
		if status_time <= 0.0:
			status_message = ""
	if dead or driving or not spawned or get_parent().get("console_open"):
		return
	_update_camera(delta)
	_update_item_use(delta)
	if viewmodel != null:
		viewmodel.tick(delta, Input.is_action_pressed("break_block"))
	_drain_collected_blocks()
	_discovery_check_time -= delta
	if _discovery_check_time <= 0.0:
		_discovery_check_time = 0.5
		_check_discovery()


func _unhandled_input(event: InputEvent) -> void:
	if driving:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := LOOK_SENSITIVITY * look_sensitivity_scale
		rotation.y -= event.relative.x * sens
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sens, -1.52, 1.52)
	if get_parent().get("console_open"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			inventory.select(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_0:
			inventory.select(9)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_V:
			_toggle_camera_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_try_interact()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.is_action_pressed("hotbar_next"):
			inventory.cycle_selection(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("hotbar_prev"):
			inventory.cycle_selection(-1)
			get_viewport().set_input_as_handled()


# --- Movement (retained from the accepted controller) -------------------------

func _simulate_fixed_step(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if not get_parent().get("console_open"):
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var move_direction := (global_basis * local_direction).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	speed *= 1.0 + inventory.bonus_move_speed()
	if slow_time > 0.0 or statuses.has(&"slow"):
		speed *= 0.45
	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed
	if on_floor and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	var was_on_floor := on_floor
	on_floor = false
	axis_collided.fill(0)
	var displacement := velocity * delta
	for axis in [0, 2, 1]:
		var amount := _sweep_axis(axis, displacement[axis])
		if axis != 1 and axis_collided[axis] != 0 and was_on_floor and absf(displacement[axis]) > 0.0:
			var saved_y := position.y
			var up_amount := _sweep_axis(1, 1.01)
			if up_amount >= 1.01 - COLLISION_EPSILON:
				position.y += up_amount
				axis_collided[axis] = 0
				amount = _sweep_axis(axis, displacement[axis])
				if axis_collided[axis] != 0:
					position.y = saved_y
					amount = 0.0
			else:
				position.y = saved_y
		position[axis] += amount
		if axis_collided[axis] != 0:
			velocity[axis] = 0.0
	if axis_collided[1] == 1:
		on_floor = true
	if was_on_floor and not on_floor and velocity.y <= 0.0:
		_fall_start_y = position.y
	elif not was_on_floor and on_floor:
		_apply_fall_damage(_fall_start_y - position.y)


func _sweep_axis(axis: int, motion: float) -> float:
	if absf(motion) < 0.000001:
		return 0.0
	var center := position + Vector3(0.0, PLAYER_HALF_EXTENTS.y, 0.0)
	var end_center := center
	end_center[axis] += motion
	var start_min := center - PLAYER_HALF_EXTENTS
	var end_min := end_center - PLAYER_HALF_EXTENTS
	var start_max := center + PLAYER_HALF_EXTENTS
	var end_max := end_center + PLAYER_HALF_EXTENTS
	var low := Vector3i(floori(minf(start_min.x, end_min.x)), floori(minf(start_min.y, end_min.y)), floori(minf(start_min.z, end_min.z)))
	var high := Vector3i(floori(maxf(start_max.x, end_max.x)), floori(maxf(start_max.y, end_max.y)), floori(maxf(start_max.z, end_max.z)))
	var allowed := motion
	for z in range(low.z, high.z + 1):
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector3i(x, y, z)
				if not world.is_solid(cell) or not _overlaps_other_axes(center, cell, axis):
					continue
				if motion > 0.0:
					var gap := float(cell[axis]) - (center[axis] + PLAYER_HALF_EXTENTS[axis])
					if gap >= -COLLISION_EPSILON and gap < allowed:
						allowed = maxf(0.0, gap - COLLISION_EPSILON)
						axis_collided[axis] = 1
				elif motion < 0.0:
					var gap := (center[axis] - PLAYER_HALF_EXTENTS[axis]) - float(cell[axis] + 1)
					if gap >= -COLLISION_EPSILON and -gap < -allowed:
						allowed = -maxf(0.0, gap - COLLISION_EPSILON)
						axis_collided[axis] = 1
	return allowed


func _overlaps_other_axes(center: Vector3, cell: Vector3i, ignored_axis: int) -> bool:
	for axis in range(3):
		if axis == ignored_axis:
			continue
		if center[axis] + PLAYER_HALF_EXTENTS[axis] <= float(cell[axis]) + COLLISION_EPSILON:
			return false
		if center[axis] - PLAYER_HALF_EXTENTS[axis] >= float(cell[axis] + 1) - COLLISION_EPSILON:
			return false
	return true


## All block targeting goes through Agent 1's MiningSystem, so raycast rules
## and the block data stay authoritative in one place.
func _voxel_raycast(max_distance: float) -> Dictionary:
	return MiningSystem.raycast(world, aim_origin(), aim_direction(), max_distance)


func _player_overlaps_cell(cell: Vector3i) -> bool:
	var center := position + Vector3(0.0, PLAYER_HALF_EXTENTS.y, 0.0)
	var min_player := center - PLAYER_HALF_EXTENTS
	var max_player := center + PLAYER_HALF_EXTENTS
	return max_player.x > cell.x and min_player.x < cell.x + 1 and max_player.y > cell.y and min_player.y < cell.y + 1 and max_player.z > cell.z and min_player.z < cell.z + 1


# --- Camera -------------------------------------------------------------------

func aim_origin() -> Vector3:
	if camera_mode == 0:
		return camera.global_position
	return global_position + Vector3.UP * 1.62


func aim_direction() -> Vector3:
	return -camera.global_basis.z.normalized()


func _build_avatar() -> void:
	# A small blocky explorer so third person actually shows the player.
	avatar = Node3D.new()
	avatar.name = "Avatar"
	add_child(avatar)
	_avatar_box(Vector3(0.52, 0.58, 0.30), Vector3(0.0, 1.06, 0.0), Color(0.20, 0.42, 0.62))
	_avatar_box(Vector3(0.34, 0.32, 0.32), Vector3(0.0, 1.54, 0.0), Color(0.86, 0.68, 0.52))
	_avatar_box(Vector3(0.12, 0.10, 0.12), Vector3(0.0, 1.74, 0.0), Color(0.34, 0.22, 0.14))
	_avatar_box(Vector3(0.16, 0.46, 0.18), Vector3(-0.34, 1.06, 0.0), Color(0.16, 0.34, 0.52))
	_avatar_box(Vector3(0.16, 0.46, 0.18), Vector3(0.34, 1.06, 0.0), Color(0.16, 0.34, 0.52))
	_avatar_box(Vector3(0.20, 0.54, 0.22), Vector3(-0.14, 0.34, 0.0), Color(0.28, 0.24, 0.30))
	_avatar_box(Vector3(0.20, 0.54, 0.22), Vector3(0.14, 0.34, 0.0), Color(0.28, 0.24, 0.30))
	# Right hand attachment point for third-person held item (at right shoulder height)
	_avatar_hand = Node3D.new()
	_avatar_hand.name = "HandAttach"
	_avatar_hand.position = Vector3(0.34, 1.06, 0.2)
	avatar.add_child(_avatar_hand)
	# Third-person held item model (built from same boxes as first-person viewmodel)
	_avatar_held_item = Node3D.new()
	_avatar_held_item.name = "HeldItemAvatar"
	_avatar_hand.add_child(_avatar_held_item)
	avatar.visible = camera_mode == 1


func _avatar_box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	# A whisper of self-illumination keeps the avatar readable under the deep
	# canopy shadows instead of turning into a black silhouette.
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.22
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	avatar.add_child(part)


## Builds/updates the third-person held item model to match the hotbar selection.
## Reuses the same box-based construction as the first-person viewmodel.
func _update_avatar_held_item() -> void:
		if _avatar_held_item == null:
			return
		# Clear existing model
		for child in _avatar_held_item.get_children():
			child.queue_free()
		var held_id := inventory.held_item()
		if held_id == &"":
			return
		var def := ItemDatabase.get_item(held_id)
		if def == null:
			return
		# Position the held item in the hand (offset from hand attachment)
		_avatar_held_item.position = Vector3(0.0, -0.08, 0.0)
		_avatar_held_item.rotation = Vector3(0.0, -0.45, 0.10)
		# Reuse the same build logic as HeldItemViewmodel but inline here
		# to avoid duplicating the viewmodel node in third person.
		if def.is_tool and def.tool_type == "axe":
			_build_avatar_axe(def)
		elif def.is_tool and def.tool_type == "pickaxe":
			_build_avatar_pickaxe(def)
		elif def.is_weapon:
			_build_avatar_sword(def)
		elif def.item_id == &"torch":
			_build_avatar_torch()
		else:
			_build_avatar_card(def)


func _build_avatar_axe(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier)
	# Handle
	_avatar_held_box(Vector3(0.052, 0.52, 0.052), Vector3(0.0, -0.02, 0.0), Color(0.46, 0.32, 0.20), Vector3(0.0, 0.0, 0.06))
	_avatar_held_box(Vector3(0.058, 0.10, 0.058), Vector3(-0.014, -0.26, 0.0), Color(0.30, 0.20, 0.12), Vector3(0.0, 0.0, 0.06))
	# Head
	_avatar_held_box(Vector3(0.040, 0.150, 0.055), Vector3(0.018, 0.215, -0.055), metal, Vector3(0.10, 0.0, 0.0))
	_avatar_held_box(Vector3(0.052, 0.190, 0.030), Vector3(0.020, 0.245, -0.140), metal, Vector3(0.24, 0.0, 0.0))
	_avatar_held_box(Vector3(0.030, 0.200, 0.014), Vector3(0.020, 0.248, -0.163), metal.lightened(0.35), Vector3(0.24, 0.0, 0.0))
	_avatar_held_box(Vector3(0.050, 0.048, 0.060), Vector3(0.016, 0.200, 0.006), metal.darkened(0.25))


func _build_avatar_pickaxe(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier)
	_avatar_held_box(Vector3(0.052, 0.52, 0.052), Vector3(0.0, -0.02, 0.0), Color(0.46, 0.32, 0.20), Vector3(0.0, 0.0, 0.06))
	_avatar_held_box(Vector3(0.058, 0.10, 0.058), Vector3(-0.014, -0.26, 0.0), Color(0.30, 0.20, 0.12), Vector3(0.0, 0.0, 0.06))
	_avatar_held_box(Vector3(0.150, 0.046, 0.048), Vector3(0.010, 0.215, 0.0), metal)
	_avatar_held_box(Vector3(0.120, 0.040, 0.040), Vector3(-0.115, 0.196, 0.0), metal, Vector3(0.0, 0.0, 0.42))
	_avatar_held_box(Vector3(0.120, 0.040, 0.040), Vector3(0.135, 0.196, 0.0), metal, Vector3(0.0, 0.0, -0.42))
	_avatar_held_box(Vector3(0.070, 0.026, 0.034), Vector3(-0.175, 0.150, 0.0), metal.lightened(0.30), Vector3(0.0, 0.0, 0.42))
	_avatar_held_box(Vector3(0.070, 0.026, 0.034), Vector3(0.195, 0.150, 0.0), metal.lightened(0.30), Vector3(0.0, 0.0, -0.42))


func _build_avatar_sword(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier) if def.tool_tier > 0 else Color(0.72, 0.76, 0.80)
	_avatar_held_box(Vector3(0.050, 0.130, 0.048), Vector3(0.0, -0.02, 0.0), Color(0.44, 0.30, 0.18))
	_avatar_held_box(Vector3(0.055, 0.030, 0.058), Vector3(0.0, 0.050, 0.0), metal.darkened(0.35))
	_avatar_held_box(Vector3(0.185, 0.030, 0.050), Vector3(0.0, 0.075, 0.0), metal.darkened(0.15))
	_avatar_held_box(Vector3(0.052, 0.420, 0.016), Vector3(0.0, 0.300, 0.0), metal)
	_avatar_held_box(Vector3(0.014, 0.400, 0.020), Vector3(0.0, 0.298, -0.002), metal.lightened(0.40))
	_avatar_held_box(Vector3(0.036, 0.060, 0.016), Vector3(0.0, 0.540, 0.0), metal.lightened(0.20))


func _build_avatar_torch() -> void:
	_avatar_held_box(Vector3(0.038, 0.300, 0.038), Vector3(0.0, -0.04, 0.0), Color(0.42, 0.30, 0.18))
	_avatar_held_box(Vector3(0.072, 0.090, 0.072), Vector3(0.0, 0.156, 0.0), Color(1.0, 0.68, 0.24).lightened(0.25), Vector3.ZERO, 2.6)
	_avatar_held_box(Vector3(0.044, 0.060, 0.044), Vector3(0.0, 0.216, 0.0), Color(1.0, 0.68, 0.24), Vector3.ZERO, 3.4)


func _build_avatar_card(def: ItemDef) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.21, 0.21)
	var part := MeshInstance3D.new()
	part.name = "Card"
	part.mesh = quad
	# Use unshaded material so icons keep their art colors
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = ItemIcons.icon_for(def.item_id)
	part.material_override = mat
	part.position = Vector3(0.0, 0.06, 0.0)
	part.rotation = Vector3(0.0, -0.45, 0.10)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_avatar_held_item.add_child(part)
	# Small plinth under the card
	_avatar_held_box(Vector3(0.11, 0.026, 0.08), Vector3(0.0, -0.070, 0.008), Color(0.30, 0.20, 0.12))


func _avatar_held_box(size: Vector3, at: Vector3, color: Color, box_rotation := Vector3.ZERO, glow := 0.16) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.rotation = box_rotation
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_avatar_held_item.add_child(part)
	return part


func _tier_color(tier: int) -> Color:
	return ItemIcons._metal_color(tier)


func _toggle_camera_mode() -> void:
	camera_mode = 1 - camera_mode
	if avatar != null:
		avatar.visible = camera_mode == 1
	if viewmodel != null:
		viewmodel.set_first_person(camera_mode == 0)
	# Update third-person held item to match current selection
	_update_avatar_held_item()
	if camera_mode == 0:
		camera.position = Vector3(0.0, 1.62, 0.0)
	camera_mode_changed.emit(camera_mode)
	set_status("CAMERA: %s" % ("FIRST PERSON" if camera_mode == 0 else "THIRD PERSON"))


func _update_camera(delta: float) -> void:
	if camera_mode == 0:
		camera.position = Vector3(0.0, 1.62, 0.0)
		return
	var head := global_position + Vector3.UP * 1.62
	var back := camera.global_basis.z.normalized()
	var desired := head + back * 3.4 + Vector3.UP * 0.80
	var steps := 16
	var safe := head
	for index in range(1, steps + 1):
		var probe := head.lerp(desired, float(index) / float(steps))
		var cell := Vector3i(floori(probe.x), floori(probe.y), floori(probe.z))
		if gateway.inside(cell) and gateway.is_solid(cell):
			desired = safe
			break
		safe = probe
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 12.0, 0.0, 1.0))


# --- Item use / mining / placement -------------------------------------------

func _update_item_use(delta: float) -> void:
	var held_id := inventory.held_item()
	var def := ItemDatabase.get_item(held_id)
	if Input.is_action_pressed("break_block"):
		if def != null and def.is_weapon:
			weapons.try_attack()
			_reset_mining()
			return
		if def != null and def.is_consumable:
			if Input.is_action_just_pressed("break_block"):
				_use_consumable(def)
			_reset_mining()
			return
		_update_mining(delta, def)
	else:
		_reset_mining()
	if Input.is_action_just_pressed("place_block"):
		_try_place_block(def)


func _reset_mining() -> void:
	mining_target = Vector3i(-1, -1, -1)
	tree_damage_stage = 0
	_mine_tick_clock = 0.0
	if mining_progress > 0.0:
		mining_progress = 0.0
		mining_progress_changed.emit(0.0, mining_target)


## Target readout + progress. All rules come from Agent 1's MiningSystem.
func _update_mining(delta: float, def: ItemDef) -> void:
	if not gateway.ready():
		return
	# Trees are meshes, not voxels, so they need their own hit test; otherwise
	# the ray goes straight through the trunk and hits whatever is behind it.
	var vegetation: WorldVegetation = world.get("vegetation")
	if vegetation != null:
		var tree := vegetation.raycast_tree(aim_origin(), aim_direction(), REACH)
		if not tree.is_empty():
			_chop_tree(delta, def, tree)
			return
	var hit := _voxel_raycast(REACH)
	if hit.is_empty():
		target_block_name = ""
		target_can_mine = false
		_reset_mining()
		return
	var cell: Vector3i = hit["cell"]
	target_block_name = MiningSystem.display_name(world, cell)
	target_mining_tier = MiningSystem.mining_tier(world, cell)
	target_can_mine = MiningSystem.can_mine(world, cell, mining_tier)
	if cell != mining_target:
		mining_target = cell
		mining_progress = 0.0
	if not target_can_mine:
		mining_progress = 0.0
		mining_progress_changed.emit(0.0, cell)
		set_status("%s  ·  %s PICKAXE REQUIRED" % [target_block_name.to_upper(), _tier_label(target_mining_tier).to_upper()])
		return
	var hardness := MiningSystem.hardness(world, cell)
	var rate := 0.18 / hardness
	if def != null and def.is_tool:
		rate = (def.mining_speed + inventory.bonus_mining_speed()) / hardness
		if def.effective_blocks.has(gateway.get_block_name(cell)):
			rate *= 1.6
	mining_progress += rate * delta
	mining_progress_changed.emit(clampf(mining_progress, 0.0, 1.0), cell)
	if mining_progress >= 1.0:
		_complete_mining(cell)
		return
	_mine_tick_clock -= delta
	if _mine_tick_clock <= 0.0:
		_mine_tick_clock = 0.22
		Sfx.mine(world, Vector3(cell) + Vector3(0.5, 0.5, 0.5))


## Chopping a trunk needs an axe, the way Terraria does, and fells the whole
## tree instead of one block at a time.
func _chop_tree(delta: float, def: ItemDef, tree: Dictionary) -> void:
	var cell: Vector3i = tree["cell"]
	target_block_name = "Tree"
	target_mining_tier = 0
	var has_axe := def != null and def.is_tool and def.tool_type == "axe"
	target_can_mine = has_axe
	if cell != mining_target:
		mining_target = cell
		mining_progress = 0.0
		tree_damage_stage = 0
	if not has_axe:
		mining_progress = 0.0
		mining_progress_changed.emit(0.0, cell)
		set_status("AXE REQUIRED TO FELL A TREE")
		return
	# A starting axe used to fell a tree in a single swing or two; this keeps the
	# base pace slow and lets a better axe's mining_speed matter proportionally more.
	var rate := 0.10 + def.mining_speed * 0.08
	mining_progress += rate * delta
	mining_progress_changed.emit(clampf(mining_progress, 0.0, 1.0), cell)
	# The tree leans a little further with every swing and shakes on each hit, so
	# the damage is visible well before it goes over.
	var push := (Vector3(cell) + Vector3(0.5, 0.0, 0.5) - global_position)
	push.y = 0.0
	if push.length() < 0.05:
		push = (-global_basis.z)
	world.vegetation.damage_tree(cell, clampf(mining_progress, 0.0, 1.0), push)
	var stage := clampi(int(mining_progress * 4.0), 0, 4)
	if stage > tree_damage_stage:
		tree_damage_stage = stage
		Vfx.burst(world, Vector3(cell) + Vector3(0.5, 1.2, 0.5), Color(0.55, 0.37, 0.29),
			Vector3.UP, 8, 3.2, 0.05, 0.45)
		Sfx.chop(world, Vector3(cell) + Vector3(0.5, 1.2, 0.5))
	if mining_progress < 1.0:
		return
	var wood := maxi(3, roundi(2.0 + float(tree.get("height", 5.0))))
	if not world.vegetation.fell_tree(cell, push):
		_reset_mining()
		return
	# The stump block stays behind: it is still mineable, and leaving the voxels
	# alone means a felled tree never leaves a pit in the ground. The wood is not
	# handed over yet: the trunk has to hit the ground, and the logs land where it
	# comes down so they can be walked over and picked up.
	if not world.vegetation.tree_landed.is_connected(_on_tree_landed):
		world.vegetation.tree_landed.connect(_on_tree_landed)
	_pending_tree_loot[cell] = wood
	progression.discover(&"wood")
	progression.add_stat(&"trees_felled", 1.0)
	gateway.emit_noise(Vector3(cell), 4.0)
	Vfx.burst(world, Vector3(cell) + Vector3(0.5, 1.4, 0.5), Color(0.55, 0.37, 0.29), Vector3.UP, 14, 3.0, 0.06, 0.4)
	Sfx.fell(world, Vector3(cell) + Vector3(0.5, 1.4, 0.5))
	set_status("TREE FELLING")
	_reset_mining()


## A felled tree hit the ground: drop its wood as real pickups at the landing
## point, split into a few logs so it reads like lumber rather than one cube.
func _on_tree_landed(cell: Vector3i, at: Vector3, _fall_seconds: float) -> void:
	var wood := int(_pending_tree_loot.get(cell, 0))
	if wood <= 0:
		return
	_pending_tree_loot.erase(cell)
	const SCATTER := [
		Vector3(0.0, 0.0, 0.0), Vector3(0.55, 0.0, 0.25), Vector3(-0.45, 0.0, 0.4),
		Vector3(0.2, 0.0, -0.5),
	]
	var stacks := clampi(int(ceil(float(wood) / 3.0)), 1, SCATTER.size())
	var remaining := wood
	for index in range(stacks):
		var amount := int(ceil(float(remaining) / float(stacks - index)))
		remaining -= amount
		var offset: Vector3 = SCATTER[index]
		ItemEntity.spawn(get_parent(), at + offset + Vector3.UP * 0.45, &"wood", amount)
	set_status("FELLED TREE  ·  %d WOOD DROPPED" % wood)


## One place derives the tier from the equipped tool. No per-tool logic exists.
func _refresh_mining_tier(_a: Variant = null, _b: Variant = null) -> void:
	if viewmodel != null:
		viewmodel.set_item(inventory.held_item())
	# Update third-person held item to match current selection
	_update_avatar_held_item()
	var def := ItemDatabase.get_item(inventory.held_item())
	mining_tier = def.tool_tier if def != null and def.is_tool and def.tool_type == "pickaxe" else 0
	max_health = MAX_HEALTH + inventory.bonus_max_health()
	health = minf(health, max_health)


func _tier_label(tier: int) -> String:
	var names := ["Bare Hands", "Wood", "Copper", "Iron", "Silver", "Gold"]
	return names[clampi(tier, 0, names.size() - 1)]


## Doors are two block states of one object, like Terraria: a closed door is
## solid, an open one is passable. Interacting swaps them without ever
## creating or consuming an item.
func _toggle_door() -> bool:
	if not gateway.ready():
		return false
	var hit := _voxel_raycast(REACH)
	if hit.is_empty():
		return false
	var cell: Vector3i = hit["cell"]
	var block_name := gateway.get_block_name(cell)
	var target := &""
	if block_name == &"wood_door":
		target = &"wood_door_open"
	elif block_name == &"wood_door_open":
		target = &"wood_door"
	if target == &"":
		return false
	var block_id := gateway.block_id_for(target)
	if block_id < 0:
		return false
	if not world.set_block(cell, block_id):
		return false
	set_status("DOOR %s" % ("OPEN" if target == &"wood_door_open" else "CLOSED"))
	return true


func _complete_mining(cell: Vector3i) -> void:
	# Agent 1 owns break rules, tier gating and the drop descriptor.
	var was_chest := gateway.get_block_name(cell) == &"chest"
	var result := MiningSystem.break_block(world, cell, mining_tier)
	if not bool(result.get("mined", false)):
		mining_progress = 0.0
		if bool(result.get("blocked", false)):
			set_status("TIER TOO LOW")
		return
	if was_chest:
		# Terraria drops a chest's contents on the ground, never deleting them.
		for stack in containers.empty_into(cell):
			ItemEntity.spawn(get_parent(), Vector3(cell) + Vector3(0.5, 0.7, 0.5), StringName(stack.get("id", &"")), int(stack.get("amount", 0)))
	var drop: Dictionary = result.get("drop", {})
	var drop_id := ItemDatabase.item_id_for_drop(StringName(drop.get("block_id", &"")))
	var count := int(drop.get("count", 0))
	if drop_id != &"" and count > 0:
		# Agent 1's sink; drained into the real InventoryModel next frame.
		collected_blocks[drop_id] = int(collected_blocks.get(drop_id, 0)) + count
		progression.discover(drop_id)
	progression.add_stat(&"blocks_mined", 1.0)
	gateway.emit_noise(Vector3(cell), 3.0)
	Vfx.burst(world, Vector3(cell) + Vector3(0.5, 0.5, 0.5), Color(0.92, 0.72, 0.42), Vector3.UP, 10, 3.5, 0.05, 0.3)
	Sfx.mine(world, Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	set_status("MINED %s" % target_block_name.to_upper())
	mining_progress = 0.0
	mining_progress_changed.emit(0.0, cell)
	target_block_name = ""


## Drains Agent 1's collection sink into the single InventoryModel. Overflow
## becomes a real dropped ItemEntity so nothing is silently lost.
## One-time discovery bonus for Agent 4's authored sites. Physical loot remains
## mineable blocks; this only acknowledges the discovery and grants a small
## unique reward that cannot be claimed twice.
func _check_discovery() -> void:
	if not world.is_generated or not BiomeDiscovery.enabled():
		return
	var cell := Vector3i(floori(position.x), floori(position.y + 0.5), floori(position.z))
	var discovery := BiomeDiscovery.discovery_at(int(world.world_seed), cell)
	if discovery.is_empty():
		return
	var discovery_id := String(discovery.get("id", ""))
	if discovery_id == "" or discovery_rewards.was_claimed(discovery_id, progression):
		return
	var result: Dictionary = discovery_rewards.try_claim(discovery, inventory, progression)
	if bool(result.get("claimed", false)):
		set_status("DISCOVERED: %s" % String(discovery.get("label", "SOMETHING")).to_upper())


func _drain_collected_blocks() -> void:
	if collected_blocks.is_empty():
		return
	for id_variant in collected_blocks.keys():
		var id := StringName(id_variant)
		var leftover := inventory.add_item(id, int(collected_blocks[id_variant]))
		if leftover > 0:
			ItemEntity.spawn(world, position + Vector3.UP * 0.6, id, leftover)
	collected_blocks.clear()


## Public deposit used by loot/tests: accepts a block id or an item id.
func deposit_drops(block_or_item_id: StringName, amount: int) -> int:
	var id := ItemDatabase.item_id_for_drop(block_or_item_id)
	var leftover := inventory.add_item(id, amount)
	if leftover > 0:
		ItemEntity.spawn(world, position + Vector3.UP * 0.6, id, leftover)
	return leftover


func _try_place_block(def: ItemDef) -> void:
	if def == null or def.place_block == &"":
		return
	var hit := _voxel_raycast(REACH)
	if hit.is_empty():
		return
	var cell: Vector3i = hit["previous_air"]
	if _player_overlaps_cell(cell):
		return
	# Agent 1 owns placement validation as well.
	if MiningSystem.place_block(world, cell, _placement_block(def)):
		inventory.consume(def.item_id, 1)
		Sfx.place(world, Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	else:
		set_status("CANNOT PLACE THERE")


## Stairs are four facing variants of one item; pick the variant whose high
## side points away from the player, like Minecraft does on placement.
func _placement_block(def: ItemDef) -> StringName:
	var base := String(def.place_block)
	var material := ""
	if base.begins_with("wood_stairs"):
		material = "wood"
	elif base.begins_with("stone_stairs"):
		material = "stone"
	if material == "":
		return def.place_block
	var aim := aim_direction()
	if absf(aim.x) >= absf(aim.z):
		return StringName("%s_stairs_%s" % [material, "e" if aim.x > 0.0 else "w"])
	return StringName("%s_stairs_%s" % [material, "s" if aim.z > 0.0 else "n"])


func _use_consumable(def: ItemDef) -> void:
	if not inventory.consume(def.item_id, 1):
		return
	if def.heal_amount > 0.0:
		health = minf(max_health, health + def.heal_amount)
	if def.mana_restore > 0.0 and weapons != null:
		weapons.mana = minf(weapons.max_mana, weapons.mana + def.mana_restore)
	if def.item_id == &"mana_crystal" and weapons != null:
		progression.add_stat(&"mana_crystals_used", 1.0)
		weapons.apply_mana_crystal_bonus(int(progression.get_stat(&"mana_crystals_used")))
	if def.applies_status != &"":
		statuses.apply(def.applies_status, def.status_duration)
	set_status("USED %s" % def.display_name.to_upper())


func _try_interact() -> void:
	if _interact_cooldown > 0.0:
		return
	_interact_cooldown = 0.35
	if _toggle_door():
		return
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as Node3D
		if npc == null or not is_instance_valid(npc):
			continue
		if npc.global_position.distance_to(global_position) <= 3.5 and npc.has_method("interact"):
			npc.call("interact", self)
			return
	# Shops / quests are exposed as data; Agent 3 renders the actual UI.
	set_status("NOTHING TO INTERACT WITH")


# --- Survival -----------------------------------------------------------------

func set_status(text: String) -> void:
	status_message = text
	status_time = 2.0
	gameplay_message.emit(text)


func _apply_fall_damage(distance: float) -> void:
	if distance <= FALL_SAFE_HEIGHT or god_mode or dead:
		return
	var amount := (distance - FALL_SAFE_HEIGHT) * FALL_DAMAGE_PER_BLOCK
	health = maxf(0.0, health - amount)
	set_status("FELL %d BLOCKS" % roundi(distance))
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		died.emit()


func _update_light_regen(delta: float) -> void:
	if health >= max_health or not world.is_generated or statuses.has(&"poison"):
		return
	if regen_grace > 0.0:
		regen_grace = maxf(0.0, regen_grace - delta)
		return
	var cell := Vector3i(floori(position.x), floori(position.y + 0.5), floori(position.z))
	var voxel_light := float(world.get_light_level(cell)) / 15.0
	var effective_light := maxf(voxel_light, world.ambient_sky_level)
	if effective_light >= 0.35 and world.get_night_level(cell) < 0.6:
		health = minf(max_health, health + 1.5 * delta)
	if statuses.has(&"regen"):
		health = minf(max_health, health + 4.0 * delta)
	if statuses.has(&"poison"):
		health = maxf(0.0, health - 3.0 * delta)
		if health <= 0.0 and not dead:
			dead = true
			died.emit()


func take_damage(amount: float) -> void:
	if god_mode or dead or damage_cooldown > 0.0 or amount <= 0.0:
		return
	var reduction := clampf(float(inventory.total_defense()) * 0.015, 0.0, 0.75)
	var actual := amount * (1.0 - reduction)
	health = maxf(0.0, health - actual)
	damage_cooldown = 0.7
	set_status("HIT  -%d" % roundi(actual))
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		progression.add_stat(&"deaths", 1.0)
		died.emit()


func full_heal() -> void:
	health = max_health
	damage_cooldown = 0.0
	slow_time = 0.0
	statuses.clear()


func apply_slow(duration: float) -> void:
	# Keep the legacy timer and the status effect in sync so both movement
	# paths and older save/restore code observe the same slow duration.
	slow_time = maxf(slow_time, duration)
	statuses.apply(&"slow", duration)


func respawn_at(spawn: Vector3) -> void:
	position = spawn
	velocity = Vector3.ZERO
	on_floor = false
	fixed_accumulator = 0.0
	damage_cooldown = 0.0
	dead = false
	health = max_health
	_fall_start_y = position.y
	_reset_mining()
	respawned.emit()


# --- Save contract (Agent 1 folds "gameplay" into metadata.m4) ----------------

func serialize_gameplay_state() -> Dictionary:
	var boss_state: Dictionary = {}
	var director = get_parent().get_node_or_null("EnemyDirector")
	if director != null and director.boss_director != null:
		boss_state = director.boss_director.serialize()
	return {
		"boss": boss_state,
		"inventory": inventory.serialize(),
		"progression": progression.serialize(),
		"statuses": statuses.serialize(),
		"mana": weapons.mana if weapons != null else 100.0,
		"camera_mode": camera_mode,
		"player_stats": {"health": health, "god_mode": god_mode},
		"containers": containers.serialize(),
	}


func deserialize_gameplay_state(data: Dictionary) -> void:
	if data.has("boss"):
		var director = get_parent().get_node_or_null("EnemyDirector")
		if director != null and director.boss_director != null:
			director.boss_director.deserialize(data["boss"])
	if data.has("inventory"):
		inventory.deserialize(data["inventory"])
	if data.has("progression"):
		progression.deserialize(data["progression"])
		if weapons != null:
			weapons.apply_mana_crystal_bonus(int(progression.get_stat(&"mana_crystals_used")))
	if data.has("containers"):
		var stored: Variant = data["containers"]
		if stored is Dictionary:
			containers.deserialize(stored)
	if data.has("statuses"):
		statuses.deserialize(data["statuses"])
	if data.has("mana") and weapons != null:
		weapons.mana = clampf(float(data["mana"]), 0.0, weapons.max_mana)
	if data.has("camera_mode"):
		camera_mode = clampi(int(data["camera_mode"]), 0, 1)
	var saved_stats: Dictionary = data.get("player_stats", {})
	if not saved_stats.is_empty():
		health = clampf(float(saved_stats.get("health", health)), 0.0, max_health)
		god_mode = bool(saved_stats.get("god_mode", god_mode))
		dead = health <= 0.0
