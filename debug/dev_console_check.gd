extends SceneTree

# Console command wiring, toggling and gameplay side effects.

const COMPLETE := "DEV CONSOLE CHECK PASS: toggle, god, heal, spawn, tp and time"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("CONSOLE PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("CONSOLE FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	while not main.world.is_generated or not main.player.spawned:
		await process_frame
	var console: DevConsole = main.get_node("DevConsole")
	var player: VoxelPlayer = main.player
	var world: VoxelWorld = main.world

	console.show_console()
	_check(console.open and main.console_open, "console opens and claims input")
	console._execute("god")
	_check(player.god_mode, "god toggles invincibility on")
	console._execute("god")
	_check(not player.god_mode, "god toggles invincibility off")

	player.take_damage(40.0)
	console._execute("heal")
	_check(is_equal_approx(player.health, VoxelPlayer.MAX_HEALTH), "heal restores health")

	var before := get_nodes_in_group("enemies").size()
	console._execute("spawn nightling")
	await process_frame
	var after := get_nodes_in_group("enemies").size()
	_check(after == before + 1, "spawn creates one enemy in front of the player", "%d -> %d" % [before, after])

	console._execute("tp frost")
	await process_frame
	var cell := Vector3i(floori(player.position.x), 0, floori(player.position.z))
	_check(world.get_biome_at(cell) == BiomeManager.FROST, "tp moves to the requested biome", BiomeManager.biome_name(world.get_biome_at(cell)))

	console._execute("time 22")
	_check(main.cycle.phase_name == "night", "time sets the day/night phase", main.cycle.phase_name)

	console.close()
	_check(not console.open and not main.console_open, "console closes and releases input")

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
