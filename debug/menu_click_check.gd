extends SceneTree

# Reproduces menu button activation without a mouse. Each label is tested with
# a FRESH menu instance, because play buttons free the menu.

var failures := 0


func _find_button(menu: Control, label: String) -> Button:
	for node in menu.find_children("*", "Button", true, false):
		if (node as Button).text == label:
			return node as Button
	return null


func _initialize() -> void:
	for label in ["SETTINGS", "CONTROLS", "CREDITS", "WORLD SELECTION", "PLAY", "CONTINUE", "NEW WORLD"]:
		await _test(label)
	var ok: String = "PASS" if failures == 0 else "FAIL (%d)" % failures
	print("MENU CLICK CHECK %s" % ok)
	quit(0 if failures == 0 else 1)


func _test(label: String) -> void:
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var btn := _find_button(menu, label)
	if btn == null:
		print("MENU BUTTON %s: MISSING" % label)
		failures += 1
	else:
		btn.pressed.emit()
		await process_frame
		await process_frame
		var worlds: Array = []
		for node in root.get_children():
			if node.has_method("save_game"):
				worlds.append(str(node.name))
		var started := not worlds.is_empty()
		var menu_alive := is_instance_valid(menu)
		var panel_ok := menu_alive and menu.get("_current_panel") != null
		var list_ok := menu_alive and bool(menu.get("_world_list").visible)
		var result := started if label in ["PLAY", "CONTINUE", "NEW WORLD"] else (panel_ok if label in ["SETTINGS", "CONTROLS", "CREDITS"] else list_ok)
		print("MENU CLICK %-16s -> handled=%s worlds=%s" % [label, str(result), str(worlds)])
		if not result:
			failures += 1
	for node in root.get_children():
		if node.has_method("save_game"):
			node.free()
	if is_instance_valid(menu):
		menu.free()
