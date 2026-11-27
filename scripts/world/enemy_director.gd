extends Node
class_name EnemyDirector

const CONFIG: EnemyConfig = preload("res://data/world/enemy_config.tres")
const NIGHT_CONFIG: NightConfig = preload("res://data/world/night_config.tres")
const NightlingScript = preload("res://scripts/enemies/nightling.gd")
const LampEaterScript = preload("res://scripts/enemies/lamp_eater.gd")
const HollowScript = preload("res://scripts/enemies/hollow.gd")
const FrostStalkerScript = preload("res://scripts/enemies/frost_stalker.gd")
const BogCrawlerScript = preload("res://scripts/enemies/bog_crawler.gd")
const SlimeScript = preload("res://scripts/enemies/slime.gd")
const ZombieScript = preload("res://scripts/enemies/zombie.gd")
const WardenScript = preload("res://scripts/enemies/hollow_warden.gd")
const WARDEN_BOSS: BossDef = preload("res://data/bosses/hollow_warden.tres")
const KIND_WARDEN := 99

# Agent 2 loot tables (data-driven, item ids stay in the item database).
const LOOT_NIGHTLING: LootTable = preload("res://data/loot/nightling.tres")
const LOOT_LAMP_EATER: LootTable = preload("res://data/loot/lamp_eater.tres")
const LOOT_HOLLOW: LootTable = preload("res://data/loot/hollow.tres")
const LOOT_FROST_STALKER: LootTable = preload("res://data/loot/frost_stalker.tres")
const LOOT_BOG_CRAWLER: LootTable = preload("res://data/loot/bog_crawler.tres")
const LOOT_SLIME: LootTable = preload("res://data/loot/slime.tres")
const LOOT_ZOMBIE: LootTable = preload("res://data/loot/zombie.tres")

var world: VoxelWorld
var night: NightManager
var player: VoxelPlayer
var blood_moon: BloodMoonDirector
var spawn_timer := 0.0
var rng := RandomNumberGenerator.new()
var chunk_cooldowns: Dictionary = {}

# Agent 4 can supply a room-id -> world-position provider when the Undercroft
# content lands; until then encounters use a point near the player.
var encounter_center_provider: Callable
var boss_director: BossDirector

func _ready() -> void:
	world = get_parent().get_node("VoxelWorld") as VoxelWorld
	night = get_parent().get_node("NightManager") as NightManager
	player = get_parent().get_node("Player") as VoxelPlayer
	blood_moon = get_parent().get_node_or_null("BloodMoonDirector") as BloodMoonDirector
	rng.randomize()
	boss_director = BossDirector.new()
	boss_director.bosses = [WARDEN_BOSS]
	if player != null:
		boss_director.setup(player.progression)
	# Agent 4's authored rooms are optional; when present, encounters use their
	# real world coordinates instead of the near-player fallback.
	if world != null:
		encounter_center_provider = Callable(AdventureContent, "room_center").bind(world.world_seed)

func _process(delta: float) -> void:
	if not world.is_generated or not player.spawned:
		return
	spawn_timer += delta
	for key in chunk_cooldowns.keys():
		chunk_cooldowns[key] = maxf(0.0, float(chunk_cooldowns[key]) - delta)
	var tick_seconds := CONFIG.spawn_tick_seconds
	if blood_moon != null and blood_moon.is_active:
		tick_seconds *= blood_moon.CONFIG.spawn_tick_scale
	if spawn_timer < tick_seconds:
		return
	spawn_timer = 0.0
	_spawn_from_night()

func _spawn_from_night() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var max_active := CONFIG.max_active_enemies
	if blood_moon != null and blood_moon.is_active:
		max_active = int(float(max_active) * blood_moon.CONFIG.max_active_scale)
	if enemies.size() >= max_active:
		return
	# Candidate pool: any fully-ready chunk (generated, lit and meshed) not on
	# cooldown, so a spawn never lands in frontier terrain. Dark chunks (night
	# surface, or caves at any hour — night.levels tracks light exposure, not
	# the clock) draw the full roster below; lit daylight surface draws from
	# slimes only, the one monster Terraria lets wander around in the sun.
	var candidates: Array[Vector3i] = []
	for key in world.chunk_records.keys():
		var chunk_index: Vector3i = key
		if not world.is_chunk_ready(chunk_index):
			continue
		if float(chunk_cooldowns.get(chunk_index, 0.0)) > 0.0:
			continue
		candidates.append(chunk_index)
	if candidates.is_empty():
		return
	candidates.shuffle()
	for chunk_index in candidates:
		var is_dark := float(night.levels.get(chunk_index, 0.0)) >= NIGHT_CONFIG.spawn_threshold
		var position := _find_spawn_position(chunk_index)
		if position == Vector3(-1.0, -1.0, -1.0):
			continue
		# The population is chosen from the biome at the spawn point itself,
		# not the player's biome, so border fights spawn the local wildlife.
		var biome := world.get_biome_at(Vector3i(floori(position.x), 0, floori(position.z)))
		var identity := GameplayBiome.identity_for(biome)
		var kind: int
		if is_dark:
			var hollow_count := 0
			for existing in enemies:
				if existing is Hollow:
					hollow_count += 1
			kind = CONFIG.roll_kind_identity(identity, rng.randf())
			if blood_moon != null and blood_moon.is_active and kind != EnemyConfig.KIND_HOLLOW and rng.randf() < blood_moon.CONFIG.zombie_bias:
				# Terraria's Blood Moon skews the night's population hard toward
				# zombies; Hollow encounters stay as rolled rather than piled on.
				kind = EnemyConfig.KIND_ZOMBIE
			if kind == EnemyConfig.KIND_HOLLOW and hollow_count >= CONFIG.max_active_hollows:
				# Cap reached: fall back to the identity's small game instead of
				# re-rolling, keeping the table deterministic per Terraria biome.
				kind = EnemyConfig.KIND_FROST_STALKER if identity == GameplayBiome.Identity.SNOW else EnemyConfig.KIND_NIGHTLING
		else:
			kind = EnemyConfig.KIND_SLIME
		var pack_kind := kind == EnemyConfig.KIND_NIGHTLING or kind == EnemyConfig.KIND_FROST_STALKER
		var count := mini(CONFIG.nightling_group_size, max_active - enemies.size()) if pack_kind else 1
		for index in range(count):
			var enemy: NightEnemy
			match kind:
				EnemyConfig.KIND_LAMP_EATER:
					enemy = LampEaterScript.new()
					_configure_lamp_eater(enemy)
				EnemyConfig.KIND_HOLLOW:
					enemy = HollowScript.new()
					_configure_hollow(enemy)
				EnemyConfig.KIND_FROST_STALKER:
					enemy = FrostStalkerScript.new()
					_configure_frost_stalker(enemy)
				EnemyConfig.KIND_BOG_CRAWLER:
					enemy = BogCrawlerScript.new()
					_configure_bog_crawler(enemy)
				EnemyConfig.KIND_SLIME:
					enemy = SlimeScript.new()
					_configure_slime(enemy, identity)
				EnemyConfig.KIND_ZOMBIE:
					enemy = ZombieScript.new()
					_configure_zombie(enemy)
				_:
					enemy = NightlingScript.new()
					_configure_nightling(enemy)
			# The Hollow is too tall to risk the usual jitter embedding it in
			# terrain; it spawns exactly on the checked surface cell.
			var jitter := Vector3.ZERO if kind == EnemyConfig.KIND_HOLLOW else Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
			enemy.position = position + jitter
			_finalize_enemy(enemy)
			get_parent().add_child(enemy)
		var cooldown := CONFIG.spawn_cooldown_seconds
		if blood_moon != null and blood_moon.is_active:
			cooldown *= blood_moon.CONFIG.cooldown_scale
		chunk_cooldowns[chunk_index] = cooldown
		return

func _find_spawn_position(chunk_index: Vector3i) -> Vector3:
	var surface_spawn := _find_surface_spawn_position(chunk_index)
	if surface_spawn != Vector3(-1.0, -1.0, -1.0):
		return surface_spawn
	return _find_cave_spawn_position(chunk_index)

func _find_surface_spawn_position(coords: Vector3i) -> Vector3:
	for attempt in range(12):
		var x := coords.x * 16 + rng.randi_range(1, 14)
		var z := coords.z * 16 + rng.randi_range(1, 14)
		var floor_y: int = world.get_surface_height(x, z)
		var spawn := Vector3(x + 0.5, floor_y + 1.05, z + 0.5)
		var distance := spawn.distance_to(player.position)
		if distance < CONFIG.min_spawn_distance or distance > CONFIG.max_spawn_distance:
			continue
		if world._chunk_of(Vector3i(x, floor_y, z)) != coords:
			continue
		var headroom_clear := true
		for level in range(1, 4):
			if world.get_block_id(Vector3i(x, floor_y + level, z)) != world.air_id:
				headroom_clear = false
				break
		if not headroom_clear:
			continue
		if _is_visible_from_player(spawn):
			continue
		return spawn
	return Vector3(-1.0, -1.0, -1.0)

func _find_cave_spawn_position(coords: Vector3i) -> Vector3:
	var min_y := coords.y * 16 + 1
	var max_y := coords.y * 16 + 14
	for attempt in range(16):
		var x := coords.x * 16 + rng.randi_range(1, 14)
		var z := coords.z * 16 + rng.randi_range(1, 14)
		var highest := mini(max_y, world.get_surface_height(x, z) - 2)
		if highest < min_y:
			continue
		var y := rng.randi_range(min_y, highest)
		var cell := Vector3i(x, y, z)
		if world.get_block_id(cell) != world.air_id or world.get_block_id(cell + Vector3i.UP) != world.air_id:
			continue
		if world.get_block_id(Vector3i(x, y - 1, z)) == world.air_id:
			continue
		var spawn := Vector3(x + 0.5, y + 0.05, z + 0.5)
		var distance := spawn.distance_to(player.position)
		if distance < CONFIG.min_spawn_distance or distance > CONFIG.max_spawn_distance:
			continue
		if world._chunk_of(Vector3i(x, y, z)) != coords:
			continue
		if _is_visible_from_player(spawn):
			continue
		return spawn
	return Vector3(-1.0, -1.0, -1.0)

func debug_spawn_nightlings(count: int = 3) -> void:
	_debug_spawn(EnemyConfig.KIND_NIGHTLING, count)

func debug_spawn_lamp_eater() -> void:
	_debug_spawn(EnemyConfig.KIND_LAMP_EATER, 1)

func debug_spawn_hollow() -> void:
	_debug_spawn(EnemyConfig.KIND_HOLLOW, 1)

func debug_spawn_frost_stalker() -> void:
	_debug_spawn(EnemyConfig.KIND_FROST_STALKER, 1)

func debug_spawn_bog_crawler() -> void:
	_debug_spawn(EnemyConfig.KIND_BOG_CRAWLER, 1)

func debug_spawn_slime(count: int = 1) -> void:
	_debug_spawn(EnemyConfig.KIND_SLIME, count)

func debug_spawn_zombie(count: int = 1) -> void:
	_debug_spawn(EnemyConfig.KIND_ZOMBIE, count)


# Console endpoint: spawn one configured enemy on the ground in front of the
# player's current view, reusing the same factory the natural spawner uses.
func spawn_named(name: String) -> bool:
	var kind := -1
	match name.to_lower():
		"nightling": kind = EnemyConfig.KIND_NIGHTLING
		"lamp_eater": kind = EnemyConfig.KIND_LAMP_EATER
		"hollow": kind = EnemyConfig.KIND_HOLLOW
		"frost_stalker": kind = EnemyConfig.KIND_FROST_STALKER
		"bog_crawler": kind = EnemyConfig.KIND_BOG_CRAWLER
		"slime": kind = EnemyConfig.KIND_SLIME
		"zombie": kind = EnemyConfig.KIND_ZOMBIE
	if kind < 0 or not world.is_generated or not player.spawned:
		return false
	var source := world.player_camera if is_instance_valid(world.player_camera) else player.camera
	var forward := -source.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var target := player.position + forward * 4.0
	var x := floori(target.x)
	var z := floori(target.z)
	if not world._inside_world(Vector3i(x, 0, z)) or not world.is_chunk_loaded_at(Vector3i(x, 20, z)):
		return false
	var surface := world.get_surface_height(x, z)
	var enemy := _make_enemy(kind)
	enemy.position = Vector3(float(x) + 0.5, float(surface) + 1.05, float(z) + 0.5)
	get_parent().add_child(enemy)
	return true


func _debug_spawn(kind: int, count: int) -> void:
	if not world.is_generated or not player.spawned:
		return
	for index in range(count):
		var cell_x := 0
		var cell_z := 0
		var found_column := false
		for attempt in range(8):
			var angle := rng.randf_range(0.0, TAU)
			var distance := rng.randf_range(5.0, 8.0)
			cell_x = floori(player.position.x + cos(angle) * distance)
			cell_z = floori(player.position.z + sin(angle) * distance)
			if world._inside_world(Vector3i(cell_x, 0, cell_z)) and world.is_chunk_loaded_at(Vector3i(cell_x, 20, cell_z)):
				found_column = true
				break
		if not found_column:
			continue
		var surface: int = world.get_surface_height(cell_x, cell_z)
		var enemy: NightEnemy = _make_enemy(kind)
		enemy.position = Vector3(cell_x + 0.5, surface + 1.05, cell_z + 0.5)
		_finalize_enemy(enemy)
		get_parent().add_child(enemy)


func _finalize_enemy(enemy: NightEnemy) -> void:
	var surface := world.get_surface_height(floori(enemy.position.x), floori(enemy.position.z))
	var depth := maxf(0.0, float(surface - floori(enemy.position.y)))
	enemy.difficulty_scale = 1.0 + clampf(depth / 64.0, 0.0, 2.0)
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)


func _on_enemy_died(_enemy: Node, _position: Vector3) -> void:
	if player != null and player.progression != null:
		player.progression.add_stat(&"enemies_defeated", 1.0)


func _make_enemy(kind: int) -> NightEnemy:
	var enemy: NightEnemy
	match kind:
		KIND_WARDEN:
			enemy = WardenScript.new()
			enemy.loot_table = WARDEN_BOSS.loot_table
		EnemyConfig.KIND_LAMP_EATER:
			enemy = LampEaterScript.new()
			_configure_lamp_eater(enemy)
		EnemyConfig.KIND_HOLLOW:
			enemy = HollowScript.new()
			_configure_hollow(enemy)
		EnemyConfig.KIND_FROST_STALKER:
			enemy = FrostStalkerScript.new()
			_configure_frost_stalker(enemy)
		EnemyConfig.KIND_BOG_CRAWLER:
			enemy = BogCrawlerScript.new()
			_configure_bog_crawler(enemy)
		EnemyConfig.KIND_SLIME:
			enemy = SlimeScript.new()
			_configure_slime(enemy)
		EnemyConfig.KIND_ZOMBIE:
			enemy = ZombieScript.new()
			_configure_zombie(enemy)
		_:
			enemy = NightlingScript.new()
			_configure_nightling(enemy)
	return enemy


func _configure_nightling(enemy: NightEnemy) -> void:
	enemy.move_speed = CONFIG.nightling_speed
	enemy.max_health = CONFIG.nightling_health
	enemy.touch_damage = CONFIG.nightling_damage
	enemy.attack_range = CONFIG.nightling_attack_range
	enemy.dissolve_light_level = CONFIG.nightling_dissolve_light
	enemy.loot_table = LOOT_NIGHTLING


func _configure_lamp_eater(enemy: NightEnemy) -> void:
	enemy.move_speed = CONFIG.lamp_eater_speed
	enemy.max_health = CONFIG.lamp_eater_health
	enemy.touch_damage = CONFIG.lamp_eater_damage
	enemy.attack_range = CONFIG.lamp_eater_attack_range
	enemy.dissolve_light_level = 15
	enemy.loot_table = LOOT_LAMP_EATER
	if enemy is LampEater:
		enemy.extinguish_distance = CONFIG.lamp_eater_extinguish_distance
		enemy.extinguish_seconds = CONFIG.lamp_eater_extinguish_seconds
		enemy.target_radius = CONFIG.lamp_eater_target_radius
		enemy.target_blocks = CONFIG.lamp_eater_target_blocks


func _configure_hollow(enemy: NightEnemy) -> void:
	# The Hollow is a statue while observed; unobserved it closes at a sprint.
	enemy.move_speed = CONFIG.hollow_chase_speed
	enemy.max_health = CONFIG.hollow_health
	enemy.touch_damage = CONFIG.hollow_damage
	enemy.attack_range = CONFIG.hollow_attack_range
	enemy.attack_interval = CONFIG.hollow_attack_interval
	enemy.dissolve_light_level = 16
	enemy.loot_table = LOOT_HOLLOW


func _configure_frost_stalker(enemy: NightEnemy) -> void:
	enemy.move_speed = CONFIG.frost_stalker_speed
	enemy.max_health = CONFIG.frost_stalker_health
	enemy.touch_damage = CONFIG.frost_stalker_damage
	enemy.attack_range = CONFIG.frost_stalker_attack_range
	enemy.dissolve_light_level = CONFIG.frost_stalker_dissolve_light
	enemy.loot_table = LOOT_FROST_STALKER


func _configure_bog_crawler(enemy: NightEnemy) -> void:
	enemy.move_speed = CONFIG.bog_crawler_speed
	enemy.max_health = CONFIG.bog_crawler_health
	enemy.touch_damage = CONFIG.bog_crawler_damage
	enemy.attack_range = CONFIG.bog_crawler_attack_range
	enemy.dissolve_light_level = 15
	enemy.loot_table = LOOT_BOG_CRAWLER
	if enemy is LampEater:
		enemy.extinguish_distance = CONFIG.bog_crawler_extinguish_distance
		enemy.extinguish_seconds = CONFIG.bog_crawler_extinguish_seconds
		enemy.target_radius = CONFIG.bog_crawler_target_radius
		enemy.target_blocks = CONFIG.lamp_eater_target_blocks


## Slime is not a nocturnal creature: leaving dissolve_light_level at its
## NightEnemy default (never dissolves) means it keeps hopping around after
## sunrise, unlike the dissolve-in-light enemies above.
func _configure_slime(enemy: NightEnemy, identity := -1) -> void:
	enemy.move_speed = CONFIG.slime_speed
	enemy.max_health = CONFIG.slime_health
	enemy.touch_damage = CONFIG.slime_damage
	enemy.attack_range = CONFIG.slime_attack_range
	enemy.loot_table = LOOT_SLIME
	if enemy is Slime:
		enemy.configure_skin(_slime_skin_for(identity))


func _slime_skin_for(identity: int) -> int:
	match identity:
		GameplayBiome.Identity.CORRUPTION:
			return Slime.SKIN_PURPLE
		GameplayBiome.Identity.SNOW, GameplayBiome.Identity.OCEAN:
			return Slime.SKIN_BLUE
		GameplayBiome.Identity.DESERT, GameplayBiome.Identity.HALLOW:
			return Slime.SKIN_GOLD
		_:
			return Slime.SKIN_BLUE


func _configure_zombie(enemy: NightEnemy) -> void:
	enemy.move_speed = CONFIG.zombie_speed
	enemy.max_health = CONFIG.zombie_health
	enemy.touch_damage = CONFIG.zombie_damage
	enemy.attack_range = CONFIG.zombie_attack_range
	enemy.loot_table = LOOT_ZOMBIE


## Agent 2 / Agent 4 encounter API. `room_id` is reserved for AdventureContent;
## when no provider is registered the encounter spawns near the player.
## Agent 4 discovery encounters. Most sites are pure exploration/treasure; only
## the guarded templates get a small themed group. Enemies use existing kinds
## selected from the Terraria biome identity table.
func spawn_discovery_encounter(discovery_id: String, world_seed: int) -> Array:
	var spawned: Array = []
	var parts := discovery_id.split("_")
	if parts.size() != 3 or parts[0] != "disc":
		return spawned
	var grid_x := int(parts[1])
	var grid_z := int(parts[2])
	var site := BiomeDiscovery.site_for(world_seed, grid_x, grid_z)
	if site.is_empty():
		return spawned
	var template := String(site.get("template", ""))
	const GUARDED := ["vault", "temple", "altar", "heart", "garden", "wreck", "floating"]
	if not GUARDED.has(template):
		return spawned
	var count := 3 if BiomeDiscovery._tier(int(site.get("biome", 0))) == "rare" else 2
	var identity := GameplayBiome.identity_for(int(site.get("biome", 0)))
	for index in range(count):
		var cell := Vector3i(int(site["x"]), int(site["y"]) + 1, int(site["z"]))
		if not world.is_chunk_ready(world._chunk_of(cell)):
			continue
		var kind := CONFIG.roll_kind_identity(identity, rng.randf())
		var enemy: NightEnemy = _make_enemy(kind)
		enemy.position = Vector3(cell.x + 0.5 + rng.randf_range(-1.0, 1.0), cell.y + 0.05, cell.z + 0.5 + rng.randf_range(-1.0, 1.0))
		_finalize_enemy(enemy)
		get_parent().add_child(enemy)
		spawned.append(enemy)
	return spawned


func spawn_encounter(room_id: String, kinds: Array = [], count := 3) -> Array:
	var spawned: Array = []
	if not world.is_generated or not player.spawned:
		return spawned
	var center := _encounter_center(room_id)
	for index in range(maxi(0, count)):
		var kind := int(kinds[index % kinds.size()]) if not kinds.is_empty() else EnemyConfig.KIND_NIGHTLING
		if kind == KIND_WARDEN:
			continue
		var enemy: NightEnemy = _make_enemy(kind)
		enemy.position = center + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		_finalize_enemy(enemy)
		get_parent().add_child(enemy)
		spawned.append(enemy)
	return spawned


## Spawns the reserved-kind boss. A second call while one lives or after the
## reward has been granted is rejected, so rewards cannot be duplicated.
func spawn_boss(_room_id: String = "") -> Node:
	if not world.is_generated or not player.spawned or boss_director == null:
		return null
	if boss_director.has_flag_reward(&"jungle_seed_granted") or boss_director.boss_is_defeated(WARDEN_BOSS.boss_id):
		return null
	for existing in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(existing):
			return null
	var center := _encounter_center(_room_id)
	var boss: NightEnemy = WardenScript.new()
	boss.position = center + Vector3.UP * 0.2
	_finalize_enemy(boss)
	get_parent().add_child(boss)
	boss.add_to_group("bosses")
	if not boss.died.is_connected(_on_boss_died):
		boss.died.connect(_on_boss_died)
	if boss_director.can_summon(WARDEN_BOSS):
		boss_director.summon(WARDEN_BOSS)
	return boss


func _on_boss_died(_boss: Node, position: Vector3) -> void:
	if boss_director != null:
		boss_director.on_boss_defeated(WARDEN_BOSS, get_parent(), position)


func _encounter_center(room_id: String) -> Vector3:
	if encounter_center_provider.is_valid():
		var result: Variant = encounter_center_provider.call(room_id)
		if result is Vector3 and (result as Vector3) != Vector3.ZERO:
			return result
	return player.position + Vector3(0.0, 0.0, -10.0)


func _is_visible_from_player(target: Vector3) -> bool:
	var start := player.camera.global_position
	var offset := target - start
	var steps := ceili(offset.length() * 3.0)
	for step_index in range(1, steps):
		var point := start + offset * (float(step_index) / float(steps))
		var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if world._inside_world(cell) and world.get_block_id(cell) != world.air_id:
			return false
	return true
