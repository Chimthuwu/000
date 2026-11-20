extends SceneTree

func _initialize() -> void:
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var player = main.get("player")
	print("PROBE player=", player)
	if player != null:
		print("PROBE statuses=", player.get("statuses"))
		print("PROBE inventory=", player.get("inventory"))
		print("PROBE progression=", player.get("progression"))
		print("PROBE weapons=", player.get("weapons"))
		print("PROBE gateway=", player.get("gateway"))
	quit(0)
