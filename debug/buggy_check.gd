extends SceneTree

# The dune buggy was removed from the Terraria-style sandbox. This guard fails
# if the vehicle node or its driving state ever returns to the playable scene.

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("BUGGY CHECK FAIL: %s %s" % [label, detail])
		return
	print("BUGGY CHECK PASS: %s %s" % [label, detail])


func _run() -> void:
	await process_frame
	await process_frame
	_check(main.get_node_or_null("Buggy") == null, "no buggy node in the world scene")
	_check(main.player != null and not main.player.driving, "player is never placed in a vehicle")
	_check(main.get("buggy") == null, "main script holds no buggy reference")
	if failures > 0:
		quit(1)
		return
	print("DUNE BUGGY REMOVAL CHECK PASS: the sandbox spawns no vehicle")
	quit(0)
