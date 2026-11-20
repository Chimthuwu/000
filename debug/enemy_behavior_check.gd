extends SceneTree

# Hollow observation speed, Frost Stalker slow and Bog Crawler Lumen drain.

const COMPLETE := "ENEMY BEHAVIOR CHECK PASS: hollow freeze/sprint, frost slow, bog toxin"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("ENEMY PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("ENEMY FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	while not main.world.is_generated or not main.player.spawned:
		await process_frame
	var player: VoxelPlayer = main.player
	var caster: Lumencaster = player.get_node("Lumencaster")
	var director: EnemyDirector = main.enemy_director
	var config: EnemyConfig = preload("res://data/world/enemy_config.tres")
	main.get_node("EnemyDirector").set_process(false)
	main.get_node("GloomManager").set_process(false)

	# --- Hollow: observed statue, unobserved sprinter ---
	_check(is_equal_approx(config.hollow_chase_speed, 7.0), "Hollow chase speed is configured", "speed=%.1f" % config.hollow_chase_speed)
	var hollow: Hollow = director._make_enemy(EnemyConfig.KIND_HOLLOW)
	main.add_child(hollow)
	await process_frame
	var flat_start := Vector3(64.5, float(main.world.spawn_height()) + 1.0, 70.5)
	player.position = Vector3(64.5, float(main.world.spawn_height()) + 1.0, 64.5)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	hollow.position = flat_start
	main.world.set_flashlight_enabled(false)
	player.camera.look_at(hollow.global_position + Vector3.UP * 1.75, Vector3.UP)
	await process_frame
	_check(hollow.is_observed() and hollow.frozen, "crosshair observation freezes the Hollow")
	_check(is_equal_approx(hollow.move_speed, config.hollow_chase_speed), "Hollow uses the fast unobserved speed")
	player.camera.rotate_y(PI)
	await process_frame
	await process_frame
	_check(not hollow.is_observed(), "turning away removes observation")
	# UNOBSERVE_DELAY is 0.20 s; process frames alone may not cross it.
	hollow.unobserve_timer = 1.0
	hollow._process(0.016)
	_check(not hollow.frozen, "Hollow unfreezes once unobserved")
	hollow.queue_free()

	# --- Frost Stalker: 3-second slow on hit ---
	player.slow_time = 0.0
	var stalker: FrostStalker = director._make_enemy(EnemyConfig.KIND_FROST_STALKER)
	main.add_child(stalker)
	stalker.on_hit_player()
	_check(is_equal_approx(player.slow_time, 3.0), "Frost Stalker applies a 3 s slow", "slow=%.1f" % player.slow_time)
	stalker.queue_free()
	player.slow_time = 0.0

	# --- Bog Crawler: toxic spittle drains Lumen ---
	var crawler: BogCrawler = director._make_enemy(EnemyConfig.KIND_BOG_CRAWLER)
	main.add_child(crawler)
	caster.reserve = 100.0
	crawler.global_position = player.position + Vector3(0.0, 0.0, -4.0)
	crawler._spit(player.position)
	var projectiles := []
	for child in main.get_children():
		if child is ToxicProjectile:
			projectiles.append(child)
	_check(projectiles.size() == 1, "Bog Crawler spawns a toxic projectile")
	if projectiles.size() == 1:
		projectiles[0]._hit_player()
		_check(is_equal_approx(caster.reserve, 100.0 - ToxicProjectile.DRAIN), "toxic projectile drains Lumen reserve", "reserve=%.0f" % caster.reserve)
	crawler.queue_free()

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
