extends SceneTree

const COMPLETE := "NPC CHECK PASS: npc interaction foundation"

var main: Node
var failures := 0

func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("NPC PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("NPC FAIL: %s %s" % [label, detail])

func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _wait_world() -> void:
	var frames := 0
	while not main.world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(main.world.is_generated, "world generated", "frames=%d" % frames)

func _run() -> void:
	await _wait_world()
	var hud: GameHUD = main.get_node("HUD")
	var player: VoxelPlayer = main.player
	var npc := NpcBase.new()
	npc.npc_name = "Wanderer"
	npc.dialogue_lines = PackedStringArray(["Hello there.", "Stay in the light."])
	main.add_child(npc)
	npc.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait_frames(2)
	_check(npc.is_in_group("npcs"), "npc registered in npcs group")
	_check(npc.is_player_near(player.global_position), "npc proximity detects player")
	hud.open_dialogue(npc)
	await _wait_frames(2)
	_check(hud.dialogue_open, "dialogue opens")
	_check(hud.dialogue_panel.visible, "dialogue panel visible")
	_check(hud.dialogue_text.text == "Hello there.", "first dialogue line shown", hud.dialogue_text.text)
	hud.advance_dialogue()
	await _wait_frames(1)
	_check(hud.dialogue_text.text == "Stay in the light.", "dialogue advances", hud.dialogue_text.text)
	hud.advance_dialogue()
	await _wait_frames(1)
	_check(not hud.dialogue_open, "dialogue closes after last line")
	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
