extends Control
class_name MainMenu

const WORLD_SCENE := "res://scenes/world/main.tscn"

@onready var title: Label = $Title

var _root_vbox: VBoxContainer
var _world_list: ItemList
var _status_label: Label
var _panel_container: Control
var _current_panel: Control = null

var _selected_seed: int = 139732

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SettingsStore.load_settings()
	# Hide the legacy minimal buttons; we build the full menu in code.
	if has_node("StartButton"):
		get_node("StartButton").visible = false
	if has_node("QuitButton"):
		get_node("QuitButton").visible = false

	_build_layout()
	_refresh_world_list()

func _build_layout() -> void:
	# Title styling
	if title != null:
		title.text = "3D TERRARIA"
		title.add_theme_font_size_override("font_size", 44)
		title.add_theme_color_override("font_color", Color(0.86, 0.95, 0.91))

	var center := VBoxContainer.new()
	center.anchors_preset = Control.PRESET_CENTER
	center.position = Vector2(300, 260)
	center.size = Vector2(680, 420)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)
	_root_vbox = center

	var buttons := [
		["PLAY", _on_play],
		["CONTINUE", _on_continue],
		["NEW WORLD", _on_new_world],
		["WORLD SELECTION", _on_world_selection],
		["SETTINGS", _on_settings],
		["CONTROLS", _on_controls],
		["CREDITS", _on_credits],
		["EXIT", _on_quit],
	]
	for entry in buttons:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(260, 34)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(entry[1])
		center.add_child(btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.72, 0.68))
	center.add_child(_status_label)

	# World selection list (hidden by default)
	_world_list = ItemList.new()
	_world_list.custom_minimum_size = Vector2(420, 160)
	_world_list.visible = false
	center.add_child(_world_list)
	_world_list.item_selected.connect(_on_world_selected)

	_panel_container = Control.new()
	_panel_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_container)

func _refresh_world_list() -> void:
	if _world_list == null:
		return
	_world_list.clear()
	var dir := DirAccess.open("user://worlds")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			var seed := int(name)
			var info := _world_info(seed)
			_world_list.add_item("%d  —  %s" % [seed, info])
		name = dir.get_next()
	dir.list_dir_end()

func _world_info(seed: int) -> String:
	var path := "user://worlds/%d/metadata.json" % seed
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "no save"
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return "corrupt"
	var data: Dictionary = parser.data
	var edited := int(data.get("edited_cells", 0))
	return "%d edits" % edited

func _on_world_selected(index: int) -> void:
	var text := _world_list.get_item_text(index)
	_selected_seed = int(text.split("  ")[0])
	_status_label.text = "Selected world %d" % _selected_seed

func _start_world(seed: int, fresh: bool) -> void:
	# NOTE: Main.world is an @onready variable. It is null until the scene is in
	# the tree, so resolve VoxelWorld by node path BEFORE add_child instead.
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		_set_menu_error("Cannot load the world scene")
		return
	var instance := packed.instantiate()
	if instance == null:
		_set_menu_error("Cannot instantiate the world scene")
		return
	var voxel_world := instance.get_node_or_null("VoxelWorld")
	if voxel_world == null:
		_set_menu_error("World scene has no VoxelWorld node")
		instance.free()
		return
	voxel_world.world_seed = seed
	if fresh:
		SettingsStore.set_value("game", "continue_on_boot", false)
	else:
		SettingsStore.set_value("game", "continue_on_boot", true)
	SettingsStore.set_value("game", "last_world_seed", seed)
	get_tree().root.add_child(instance)
	get_tree().current_scene = instance
	queue_free()


func _set_menu_error(message: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = message
	push_error("MainMenu: %s" % message)

func _on_play() -> void:
	_start_world(139732, true)

func _on_continue() -> void:
	var seed := int(SettingsStore.get_value("game", "last_world_seed", 139732))
	_start_world(seed, false)

func _on_new_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed := rng.randi_range(100000, 999999)
	_start_world(seed, true)

func _on_world_selection() -> void:
	if _world_list == null:
		return
	_world_list.visible = not _world_list.visible
	_status_label.text = "Select a world, then press ENTER WORLD" if _world_list.visible else ""
	if _world_list.visible:
		# Add a confirm button
		if not has_node("ConfirmWorld"):
			var btn := Button.new()
			btn.name = "ConfirmWorld"
			btn.text = "ENTER SELECTED WORLD"
			btn.custom_minimum_size = Vector2(260, 30)
			btn.pressed.connect(func():
				_start_world(_selected_seed, false)
			)
			_root_vbox.add_child(btn)

func _on_settings() -> void:
	_open_panel(_build_settings_panel())

func _on_controls() -> void:
	_open_panel(_build_controls_panel())

func _on_credits() -> void:
	_open_panel(_build_credits_panel())

func _open_panel(panel: Control) -> void:
	if _current_panel != null and is_instance_valid(_current_panel):
		_current_panel.queue_free()
	_current_panel = panel
	_panel_container.add_child(panel)

func _close_panel() -> void:
	if _current_panel != null and is_instance_valid(_current_panel):
		_current_panel.queue_free()
	_current_panel = null

func _build_settings_panel() -> Control:
	var panel := Panel.new()
	panel.position = Vector2(260, 120)
	panel.size = Vector2(760, 480)
	panel.add_theme_stylebox_override("panel", _style())
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(20, 20)
	vbox.size = Vector2(720, 440)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "SETTINGS"
	title_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_lbl)

	var cfg := SettingsStore.get_cfg()
	var sliders := [
		["Master Volume", "audio", "master"],
		["Music Volume", "audio", "music"],
		["SFX Volume", "audio", "sfx"],
		["Ambient Volume", "audio", "ambient"],
		["UI Volume", "audio", "ui"],
	]
	for entry in sliders:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = entry[0]
		lbl.custom_minimum_size = Vector2(180, 0)
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(cfg.get_value(entry[1], entry[2], 1.0))
		slider.custom_minimum_size = Vector2(260, 0)
		slider.value_changed.connect(func(v):
			SettingsStore.set_value(entry[1], entry[2], v)
		)
		row.add_child(slider)
		vbox.add_child(row)

	# Mouse sensitivity
	var ms_row := HBoxContainer.new()
	var ms_lbl := Label.new()
	ms_lbl.text = "Mouse Sensitivity"
	ms_lbl.custom_minimum_size = Vector2(180, 0)
	ms_row.add_child(ms_lbl)
	var ms_slider := HSlider.new()
	ms_slider.min_value = 0.3
	ms_slider.max_value = 2.5
	ms_slider.step = 0.05
	ms_slider.value = float(cfg.get_value("input", "mouse_sensitivity", 1.0))
	ms_slider.custom_minimum_size = Vector2(260, 0)
	ms_slider.value_changed.connect(func(v):
		SettingsStore.set_value("input", "mouse_sensitivity", v)
	)
	ms_row.add_child(ms_slider)
	vbox.add_child(ms_row)

	# UI scale
	var ui_row := HBoxContainer.new()
	var ui_lbl := Label.new()
	ui_lbl.text = "UI Scale"
	ui_lbl.custom_minimum_size = Vector2(180, 0)
	ui_row.add_child(ui_lbl)
	var ui_slider := HSlider.new()
	ui_slider.min_value = 0.8
	ui_slider.max_value = 1.4
	ui_slider.step = 0.05
	ui_slider.value = float(cfg.get_value("display", "ui_scale", 1.0))
	ui_slider.custom_minimum_size = Vector2(260, 0)
	ui_slider.value_changed.connect(func(v):
		SettingsStore.set_value("display", "ui_scale", v)
	)
	ui_row.add_child(ui_slider)
	vbox.add_child(ui_row)

	# Fullscreen toggle
	var fs_check := CheckButton.new()
	fs_check.text = "Fullscreen"
	fs_check.button_pressed = bool(cfg.get_value("display", "fullscreen", false))
	fs_check.toggled.connect(func(v):
		SettingsStore.set_value("display", "fullscreen", v)
	)
	vbox.add_child(fs_check)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(_close_panel)
	vbox.add_child(close_btn)
	return panel

func _build_controls_panel() -> Control:
	var panel := Panel.new()
	panel.position = Vector2(260, 120)
	panel.size = Vector2(760, 480)
	panel.add_theme_stylebox_override("panel", _style())
	var lbl := Label.new()
	lbl.position = Vector2(20, 20)
	lbl.size = Vector2(720, 440)
	lbl.text = "CONTROLS\n\nWASD - Move\nMouse - Look\nSpace - Jump\nShift - Sprint\nLMB - Mine / Attack\nRMB - Place block\nWheel - Hotbar selection\n1-9,0 - Hotbar slots\nI - Inventory\nC - Crafting\nE - Interact / Talk\nF - Torch / light\nV - Camera mode (third person default)\nK/J - Save/Load\n~ - Dev console\nESC - Pause"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(20, 440)
	close_btn.pressed.connect(_close_panel)
	panel.add_child(close_btn)
	return panel

func _build_credits_panel() -> Control:
	var panel := Panel.new()
	panel.position = Vector2(260, 120)
	panel.size = Vector2(760, 480)
	panel.add_theme_stylebox_override("panel", _style())
	var lbl := Label.new()
	lbl.position = Vector2(20, 20)
	lbl.size = Vector2(720, 440)
	lbl.text = "CREDITS\n\n3D Terraria\n\nA 3D Terraria sandbox adventure.\n\nWorld engine, mining, streaming, biomes — Agent 1\nGameplay, items, inventory, crafting, combat — Agent 2\nPresentation, HUD, menus, audio, NPC — Agent 3\nBiome content, structures, encounters — Agent 4\n\nBuilt with Godot 4.7.2."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(20, 440)
	close_btn.pressed.connect(_close_panel)
	panel.add_child(close_btn)
	return panel

func _on_quit() -> void:
	get_tree().quit()

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.07, 0.96)
	style.border_color = Color(0.24, 0.78, 0.70, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style