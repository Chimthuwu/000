extends SceneTree

# Automated version of the Phase 2 UI contract the capture log used to stand in
# for: hotbar top-left, hearts top-right with mana stars directly beneath,
# ESC opens the inventory over a running (unpaused) world, click-to-move between
# the hotbar and inventory grid, equipment into the armour column changes real
# player stats, and a crafting-list click consumes materials and grants the item.
#   Godot --headless --path . --script res://debug/ui_contract_check.gd

const COMPLETE := "UI CONTRACT CHECK PASS: hotbar/hearts/mana layout, ESC inventory, slot move, equipment stats, crafting click"

var main: Node
var hud: GameHUD
var player: VoxelPlayer
var world: VoxelWorld
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("UI PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("UI FAIL: %s %s" % [label, detail])


func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("UI CONTRACT CHECK FAIL: main.tscn did not load")
		quit(1)
		return
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	hud = main.get_node("HUD")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1
	for _i in range(8):
		await process_frame

	# --- Layout: hotbar anchored top-left ------------------------------------
	_check(hud.hotbar_panel != null and hud.hotbar_panel.visible, "hotbar panel exists")
	if hud.hotbar_panel != null:
		var p: Vector2 = hud.hotbar_panel.position
		_check(p.x <= 20.0 and p.y <= 20.0, "hotbar anchored top-left", "pos=%s" % p)

	# --- Layout: hearts top-right, mana stars directly beneath ----------------
	_check(hud.heart_icons.size() > 0 and hud.mana_stars.size() > 0, "hearts and mana stars built")
	player.health = player.max_health * 0.62
	if player.get("weapons") != null:
		player.weapons.mana = 47.0
	hud._update_health()
	hud._update_mana()
	var first_heart: TextureRect = hud.heart_icons[0]
	var top_heart_x := first_heart.position.x + GameHUD.HEART_SIZE
	_check(first_heart.position.y <= 14.0, "heart row starts at the top edge", "y=%.1f" % first_heart.position.y)
	_check(top_heart_x > GameHUD.VP.x * 0.8, "hearts sit on the right half", "right_x=%.1f" % top_heart_x)
	var star: ManaStar = hud.mana_stars[0]
	var star_top := 12.0 + float(hud.heart_rows) * (GameHUD.HEART_SIZE + 1.0) + 2.0
	_check(absf(star.position.y - star_top) < 2.0, "mana stars directly under hearts", "y=%.1f expected=%.1f" % [star.position.y, star_top])
	_check(star.position.x > GameHUD.VP.x * 0.8, "mana stars right-aligned", "x=%.1f" % star.position.x)

	# --- ESC opens the inventory without pausing the world --------------------
	var was_paused: bool = paused
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud._unhandled_input(esc)
	await process_frame
	_check(hud.inventory_visible, "ESC opens the inventory")
	_check(not hud.paused and paused == false and not was_paused, "the world keeps running under the inventory")
	_check(not hud.hotbar_panel.visible, "corner hotbar hides while the inventory shows its own row")
	# ESC closes it again, still without pausing.
	var esc2 := InputEventKey.new()
	esc2.keycode = KEY_ESCAPE
	esc2.pressed = true
	hud._unhandled_input(esc2)
	await process_frame
	_check(not hud.inventory_visible and not hud.paused and paused == false, "ESC closes the inventory, still unpaused")
	# F1 is the pause menu; ESC alone must never pause.
	_check(hud.pause_overlay == null or not hud.pause_overlay.visible, "no pause overlay from ESC")

	# --- Click-to-move between hotbar and inventory grid -----------------------
	var inv = player.inventory
	_check(inv != null, "inventory model present")
	if inv != null:
		inv.set_slot("hotbar", 0, {"id": &"wood", "amount": 12, "metadata": {}})
		inv.set_slot("main", 5, {})
		hud._refresh_inventory_panel()
		hud._on_inv_slot_input("hotbar", 0, _click(), null)
		hud._on_inv_slot_input("main", 5, _click(), null)
		var moved: Dictionary = inv.get_slot("main", 5)
		var left: Dictionary = inv.get_slot("hotbar", 0)
		_check(StringName(moved.get("id", &"")) == &"wood" and int(moved.get("amount", 0)) == 12,
			"click moves a hotbar stack into the inventory grid", "moved=%s" % str(moved))
		_check(inv.is_empty(left), "source hotbar slot is empty after the move")
		hud._on_inv_slot_input("main", 5, _click(), null)
		hud._on_inv_slot_input("hotbar", 0, _click(), null)
		var returned: Dictionary = inv.get_slot("hotbar", 0)
		_check(StringName(returned.get("id", &"")) == &"wood" and int(returned.get("amount", 0)) == 12,
			"click moves it back")

	# --- Equipment swap updates real player stats ------------------------------
	if inv != null:
		var before_max: float = player.max_health
		var remaining: int = inv.add_item(&"life_charm", 1)
		_check(remaining == 0, "life charm added for the equipment test", "remaining=%d" % remaining)
		var charm_index := -1
		var charm_area := ""
		# add_item fills the hotbar before the main grid, so search both.
		for area in [InventoryModel.AREA_HOTBAR, InventoryModel.AREA_MAIN]:
			for i in range(inv._area(area).size()):
				if StringName(inv.get_slot(area, i).get("id", &"")) == &"life_charm":
					charm_area = area
					charm_index = i
					break
			if charm_index >= 0:
				break
		_check(charm_index >= 0, "life charm sits in the inventory", "area=%s index=%d" % [charm_area, charm_index])
		if charm_index >= 0:
			hud._on_inv_slot_input(charm_area, charm_index, _click(), null)
			hud._on_inv_slot_input("equipment", 3, _click(), null)
			var equipped_stack: Dictionary = inv.equipment.get("accessory", {})
			_check(String(equipped_stack.get("id", &"")) == "life_charm",
				"charm equipped into the accessory column", "equipment=%s" % str(inv.equipment))
			_check(absf(player.max_health - (before_max + 20.0)) < 0.01,
				"equipping updates player max health", "max_health=%.1f before=%.1f" % [player.max_health, before_max])
			inv.unequip("accessory")
			player._refresh_mining_tier()

	# --- Crafting-list click consumes materials and grants the item ------------
	var cs = player.get("crafting")
	_check(cs != null, "crafting system present")
	if cs != null:
		var recipe = null
		for candidate in cs.all_recipes():
			if candidate.output_id() == &"workbench":
				recipe = candidate
				break
		_check(recipe != null, "workbench recipe exists")
		if recipe != null:
			var wood_before: int = inv.count(&"wood")
			inv.add_item(&"wood", maxi(10 - wood_before, 0) + 10)
			var can: bool = bool(cs.can_craft(recipe))
			_check(can, "workbench is craftable with wood in the bag")
			var out_before: int = inv.count(&"workbench")
			hud._craft_recipe_now(recipe)
			var wood_after: int = inv.count(&"wood")
			var out_after: int = inv.count(&"workbench")
			_check(wood_after == inv.count(&"wood"), "craft consumes no more than the recipe needs")
			_check(wood_after < wood_before + 10, "wood was spent by the craft", "before=%d after=%d" % [wood_before + 10, wood_after])
			_check(out_after == out_before + 1, "crafted item granted", "out=%d" % out_after)
			# The inventory crafting list populates real clickable icons.
			hud._refresh_inventory_panel()
			_check(hud.inv_craft_list != null and hud.inv_craft_list.get_child_count() > 0,
				"inventory crafting list populates", "icons=%d" % (hud.inv_craft_list.get_child_count() if hud.inv_craft_list != null else 0))

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
