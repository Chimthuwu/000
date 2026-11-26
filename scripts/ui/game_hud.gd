extends CanvasLayer
class_name GameHUD

# Terraria inventory palette: deep navy panels trimmed with warm gold, cool
# grey-blue slots and a gold selection, instead of the old teal sci-fi HUD.
const PANEL_BG := Color(0.055, 0.075, 0.145, 0.92)
const PANEL_BORDER := Color(0.58, 0.47, 0.26, 0.90)
const SLOT_BG := Color(0.16, 0.18, 0.31, 0.95)
const SLOT_BORDER := Color(0.38, 0.33, 0.22, 0.90)
const SLOT_SELECTED := Color(1.0, 0.86, 0.38, 1.0)
const TEXT_PALE := Color(0.86, 0.95, 0.91)
const TEXT_DIM := Color(0.55, 0.72, 0.68)
const TEXT_WARN := Color(0.98, 0.82, 0.52)
const ACCENT_CYAN := Color(0.15, 0.90, 1.0)
const ACCENT_MANA := Color(0.32, 0.86, 0.68)
const HEART_TEXTURE := preload("res://res/terraria3d/ui/hearts/Heart_Fill.png")
const HEART_EMPTY_TEXTURE := preload("res://res/terraria3d/ui/hearts/Heart_Middle.png")
const HEART_COUNT := 10
const MAX_HEART_ICONS := 20
const HEART_SIZE := 22.0
const HEART_SPACING := 22.0
const MAX_MANA_STARS := 10
const STAR_SIZE_MANA := 18.0
const STAR_SPACING := 20.0
const MANA_PER_STAR := 20.0
const HOTBAR_SLOT := 42.0
const HOTBAR_PAD := 4.0
## Authored HUD resolution; the project stretches this to the window.
const VP := Vector2(1280.0, 720.0)
# Every refresh rewrites label text, theme overrides and styleboxes, which
# forces a Control re-layout/re-draw. At 10 Hz the readouts still feel live and
# the HUD stops burning main-thread time on frames where nothing changed.
const HUD_REFRESH_SECONDS := 0.1

var player: VoxelPlayer
var caster: ArcaneCaster
var world: VoxelWorld

var debug_label: Label
var flashlight_label: Label
var health_bar: Panel
var health_fill: Panel
var health_fill_style: StyleBoxFlat
var heart_icons: Array[TextureRect] = []
var mana_stars: Array[ManaStar] = []
var heart_rows := 1
var held_label: Label
var held_time := 0.0
var _held_shown := &""
var inv_hover_label: Label
var inv_craft_list: VBoxContainer
var status_label: Label
var hint_panel: Panel
var hint_label: Label
var death_overlay: Control
var world_hint_label: Label
var world_hint_time := 0.0
var environment_label: Label

var biome_label: Label
var biome_intro_label: Label
var biome_intro_time := 0.0
var last_biome := -1

var pause_overlay: Control
var pause_buttons: Array[Button] = []
var paused := false
var hud_refresh := 0.0

# Agent 3 presentation additions
var dialogue_panel: Panel
var dialogue_name: Label
var dialogue_text: Label
var dialogue_footer: Label
var active_npc: NpcBase = null
var dialogue_open := false
var target_label: Label
var layer_label: Label
var target_progress: float = 0.0
var onboarding_step: int = 0
var onboarding_done: Array[bool] = [false, false, false, false]
var mining_click_player: AudioStreamPlayer
var mined_blocks: int = 0

# Agent 3 — extended presentation
var hotbar_panel: Panel
var hotbar_slots: Array[Panel] = []
var hotbar_labels: Array[Label] = []
var hotbar_counts: Array[Label] = []
var hotbar_icons: Array[TextureRect] = []
var mana_bar: Panel
var mana_caption: Label
var mana_fill: Panel
var mana_fill_style: StyleBoxFlat
var mana_label: Label
var interaction_label: Label
var notification_label: Label
var notification_time := 0.0
var notification_queue: Array[String] = []
var boss_panel: Panel
var boss_bg_panel: Panel
var boss_name_label: Label
var boss_health_fill: Panel
var boss_health_style: StyleBoxFlat
var boss_target: Node = null
var status_effects_label: Label
var toast_label: Label

# Agent 3 — inventory & crafting panels
var chest_panel: Panel
var chest_slots: Array[Dictionary] = []
var chest_inv_slots: Array[Dictionary] = []
var chest_visible := false
var chest_cell := Vector3i(-99999, -99999, -99999)
var house_label: Label
var inventory_panel: Panel
var guide_panel: Panel
var guide_list: VBoxContainer
var guide_detail: Label
var guide_visible := false
var guide_selected: CraftingRecipe = null
var guide_filter_id: StringName = &""
var inventory_visible := false
var crafting_panel: Panel
var crafting_visible := false
var inv_selected: Dictionary = {}  # {area, index}
var inv_slot_panels: Array[Dictionary] = []  # {panel, label, count, area, index}
var equip_slot_panels: Dictionary = {}
var craft_list: VBoxContainer
var craft_detail_label: Label
var craft_station_label: Label
var selected_recipe: CraftingRecipe = null
var tooltip_label: Label
var shop_panel: Panel
var shop_list: VBoxContainer
var shop_detail_label: Label
var shop_coin_label: Label
var shop_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := get_parent()
	player = main.get_node_or_null("Player") as VoxelPlayer
	world = main.get_node_or_null("VoxelWorld") as VoxelWorld
	if player != null:
		caster = player.get_node_or_null("ArcaneCaster") as ArcaneCaster
	# Drop any leftover legacy gun hint so the world hint owns the slot.
	if caster != null:
		caster.hint_time = 0.0
		caster.hint_text = ""
	_build_status()
	_build_biome()
	_build_health()
	_build_crosshair()
	_build_hint()
	_build_environment()
	_build_world_hint()
	_build_death()
	_build_pause()
	_build_target()
	_build_dialogue()
	_build_hotbar()
	_build_mana()
	_build_interaction()
	_build_notification()
	_build_boss()
	_build_status_effects()
	_build_inventory_panel()
	_build_chest_panel()
	_build_crafting_panel()
	_build_guide_panel()
	_build_shop_panel()
	_build_tooltip()
	_setup_mining_audio()
	if world != null and world.has_signal("block_edited"):
		world.block_edited.connect(_on_block_edited)
	# Wire Agent 2 gameplay state when available.
	if player != null:
		if player.has_signal("gameplay_message"):
			player.gameplay_message.connect(_on_gameplay_message)
		if player.get("inventory") != null:
			player.inventory.changed.connect(_refresh_hotbar)
			player.inventory.selection_changed.connect(_refresh_hotbar)
		if player.get("progression") != null:
			player.progression.discovered.connect(_on_discovered)
			player.progression.flag_set.connect(_on_flag_set)
		if player.get("inventory") != null:
			player.inventory.changed.connect(_refresh_inventory_panel)
			player.inventory.selection_changed.connect(_refresh_inventory_panel)
			player.inventory.equipment_changed.connect(_refresh_inventory_panel)
		if player.get("weapons") != null:
			player.weapons.mana_changed.connect(_on_mana_changed)
		if player.has_signal("container_requested"):
			player.container_requested.connect(open_chest)
	_refresh_hotbar()
	_layout_for_viewport()
	# Onboarding: first hint after a short delay
	_show_onboarding(0)


func _process(delta: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(player):
		return
	# These fade per frame; the textual/theme work is throttled.
	_update_biome(delta)
	_update_held(delta)
	hud_refresh += delta
	if hud_refresh < HUD_REFRESH_SECONDS:
		return
	hud_refresh = 0.0
	_update_health()
	_update_status()
	_update_hint()
	_update_world_hint(delta)
	_update_environment()
	_update_flashlight()
	_update_target()
	_refresh_hotbar()
	_update_mana()
	_update_interaction()
	_update_notification(delta)
	_update_boss()
	_update_status_effects()
	# Onboarding progression: after enough time, advance the hint.
	if onboarding_step == 0 and not onboarding_done[0]:
		onboarding_done[0] = true


# --- Construction -----------------------------------------------------------

func _style(bg: Color, border: Color, border_width := 1, radius := 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.anti_aliasing = true
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style


func _label(text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = align
	return label


func _panel(rect: Rect2, style: StyleBoxFlat) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _build_status() -> void:
	debug_label = _label("", 11, TEXT_PALE)
	debug_label.name = "DebugReadout"
	debug_label.position = Vector2(16, 8)
	debug_label.size = Vector2(822, 96)
	debug_label.visible = false
	add_child(debug_label)

	status_label = _label("", 13, Color(1.0, 0.74, 0.28), HORIZONTAL_ALIGNMENT_CENTER)
	status_label.name = "StatusLabel"
	status_label.position = Vector2(127, 340)
	status_label.size = Vector2(600, 28)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	status_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.75))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.add_theme_constant_override("shadow_outline_size", 2)
	status_label.add_theme_constant_override("outline_size", 2)
	status_label.visible = false
	add_child(status_label)

	flashlight_label = _label("TORCH  ON", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	flashlight_label.name = "FlashlightState"
	flashlight_label.position = Vector2(600, 8)
	flashlight_label.size = Vector2(238, 12)
	add_child(flashlight_label)


func _build_biome() -> void:
	# Persistent, unobtrusive biome tag under the torch readout, plus a
	# transient crossing banner. Poll-driven against world.get_biome_at.
	biome_label = _label("", 10, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	biome_label.name = "BiomeTag"
	biome_label.position = Vector2(600, 26)
	biome_label.size = Vector2(238, 14)
	biome_label.modulate.a = 0.75
	add_child(biome_label)

	biome_intro_label = _label("", 17, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
	biome_intro_label.name = "BiomeEntering"
	biome_intro_label.position = Vector2(127, 96)
	biome_intro_label.size = Vector2(600, 26)
	biome_intro_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	biome_intro_label.add_theme_constant_override("shadow_offset_y", 2)
	biome_intro_label.visible = false
	add_child(biome_intro_label)


func _build_health() -> void:
	# Terraria draws no HEALTH caption and no numeric readout: the heart row is
	# the health bar, top-right of the screen. Each heart is 10 HP here, so a
	# 100 HP player sees ten hearts and a 200 HP player sees two rows of ten.
	heart_icons.clear()
	for index in range(MAX_HEART_ICONS):
		var heart := TextureRect.new()
		heart.name = "Heart%d" % index
		heart.texture = HEART_EMPTY_TEXTURE
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.size = Vector2(HEART_SIZE, HEART_SIZE)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.visible = false
		add_child(heart)
		heart_icons.append(heart)


func _build_crosshair() -> void:
	var crosshair := Control.new()
	crosshair.name = "Crosshair"
	crosshair.position = Vector2(421, 234)
	crosshair.size = Vector2(12, 12)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	var color := Color(0.98, 0.90, 0.72, 0.9)
	var dot := ColorRect.new()
	dot.position = Vector2(5, 5)
	dot.size = Vector2(2, 2)
	dot.color = color
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(dot)
	var offsets := [Vector2(0, 5.5), Vector2(8, 5.5), Vector2(5.5, 0), Vector2(5.5, 8)]
	for index in range(4):
		var tick := ColorRect.new()
		tick.position = offsets[index]
		tick.size = Vector2(4, 1) if index < 2 else Vector2(1, 4)
		tick.color = color
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(tick)


func _build_hint() -> void:
	hint_panel = _panel(Rect2(207, 190, 440, 96), _style(Color(0.03, 0.07, 0.09, 0.9), Color(0.22, 0.9, 0.85, 0.5), 1, 4))
	hint_panel.name = "HintPanel"
	hint_panel.visible = false

	hint_label = _label("", 11, Color(0.72, 0.96, 0.93), HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.name = "ContextHint"
	hint_label.position = Vector2(219, 202)
	hint_label.size = Vector2(416, 72)
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.visible = false
	add_child(hint_label)


func _build_environment() -> void:
	environment_label = _label("EXPOSED", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	environment_label.name = "EnvironmentState"
	environment_label.position = Vector2(96, 360)
	environment_label.size = Vector2(92, 10)
	add_child(environment_label)
	layer_label = _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	layer_label.name = "DepthLayer"
	layer_label.position = Vector2(96, 348)
	layer_label.size = Vector2(92, 10)
	add_child(layer_label)
	house_label = _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	house_label.name = "HouseState"
	house_label.position = Vector2(96, 372)
	house_label.size = Vector2(320, 10)
	house_label.visible = false
	add_child(house_label)


func _build_world_hint() -> void:
	world_hint_label = _label("", 11, Color(0.86, 0.74, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	world_hint_label.name = "WorldHint"
	world_hint_label.position = Vector2(127, 70)
	world_hint_label.size = Vector2(600, 22)
	world_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	world_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	world_hint_label.visible = false
	add_child(world_hint_label)


func _build_death() -> void:
	death_overlay = Control.new()
	death_overlay.name = "DeathOverlay"
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	death_overlay.visible = false
	add_child(death_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.0, 0.0, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(197, 130)
	panel.size = Vector2(460, 220)
	panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.02, 0.02, 0.97), Color(0.62, 0.16, 0.14, 0.8), 1, 5))
	death_overlay.add_child(panel)

	var title := _label("YOU DIED", 30, Color(0.94, 0.34, 0.28), HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(24, 30)
	title.size = Vector2(412, 44)
	panel.add_child(title)

	var subtitle := _label("RETURN TO THE WORLD SPAWN", 10, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.position = Vector2(24, 78)
	subtitle.size = Vector2(412, 16)
	panel.add_child(subtitle)

	var note := _label("Respawning at your world spawn. Your items stay with you.", 9, Color(0.55, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	note.position = Vector2(24, 104)
	note.size = Vector2(412, 16)
	panel.add_child(note)

	var button := _button("RESPAWN")
	button.position = Vector2(130, 148)
	button.size = Vector2(200, 32)
	button.pressed.connect(_on_respawn_pressed)
	panel.add_child(button)

	var footer := _label("ENTER  Respawn", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	footer.position = Vector2(24, 188)
	footer.size = Vector2(412, 12)
	panel.add_child(footer)


func show_death() -> void:
	death_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_death() -> void:
	death_overlay.visible = false


## Short, transient acknowledgement for inventory/crafting interactions.
func _show_toast(text: String) -> void:
	show_world_hint(text, 2.0)


func show_world_hint(text: String, duration := 4.0) -> void:
	world_hint_label.text = text
	world_hint_time = duration
	world_hint_label.visible = true
	world_hint_label.modulate.a = 1.0


func _update_world_hint(delta: float) -> void:
	if world_hint_time <= 0.0:
		return
	world_hint_time = maxf(0.0, world_hint_time - delta)
	world_hint_label.modulate.a = clampf(world_hint_time / 0.6, 0.0, 1.0)
	if world_hint_time <= 0.0:
		world_hint_label.visible = false


func _update_environment() -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	var cell := Vector3i(floori(player.position.x), floori(player.position.y + 0.5), floori(player.position.z))
	var voxel_light := float(world.get_light_level(cell)) / 15.0
	var lit := maxf(voxel_light, world.ambient_sky_level)
	var night := world.get_night_level(cell)
	if lit >= 0.35 and night < 0.6:
		environment_label.text = "SHELTERED"
		environment_label.add_theme_color_override("font_color", Color(0.42, 0.92, 0.68))
	elif night >= 0.6:
		environment_label.text = "NIGHT RISING"
		environment_label.add_theme_color_override("font_color", Color(0.96, 0.32, 0.26))
	else:
		environment_label.text = "EXPOSED"
		environment_label.add_theme_color_override("font_color", Color(0.96, 0.72, 0.36))
	# Depth layer readout on a separate label so the environment state text stays stable.
	if layer_label != null and WorldLayers != null:
		var surface_y2 := int(world.get_surface_height(cell.x, cell.z))
		layer_label.text = WorldLayers.layer_name(WorldLayers.layer_at(cell.y, surface_y2))


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", TEXT_PALE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color(0.07, 0.10, 0.12, 0.95), Color(0.2, 0.45, 0.42, 0.7), 1, 3))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.22, 0.21, 0.98), Color(0.3, 0.9, 0.78, 0.9), 1, 3))
	button.add_theme_stylebox_override("pressed", _style(Color(0.06, 0.15, 0.14, 1.0), ACCENT_CYAN, 1, 3))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _build_pause() -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	add_child(pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.04, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(197, 80)
	panel.size = Vector2(460, 320)
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.055, 0.07, 0.97), PANEL_BORDER, 1, 5))
	pause_overlay.add_child(panel)

	var title := _label("PAUSED", 26, TEXT_PALE)
	title.position = Vector2(24, 16)
	title.size = Vector2(300, 34)
	panel.add_child(title)

	var subtitle := _label("3D TERRARIA  ·  SANDBOX", 9, TEXT_DIM)
	subtitle.position = Vector2(25, 48)
	subtitle.size = Vector2(300, 12)
	panel.add_child(subtitle)

	var header := _label("CONTROLS", 9, Color(0.35, 0.75, 0.68))
	header.position = Vector2(24, 72)
	header.size = Vector2(200, 12)
	panel.add_child(header)

	var left_controls := ["WASD      Move", "SHIFT     Sprint", "SPACE     Jump", "LMB       Mine / Attack", "RMB       Place block", "F         Torch / light"]
	var right_controls := ["1–9, 0   Hotbar slots", "I         Inventory", "C         Crafting", "E         Interact / Talk", "V         Camera mode", "K / J     Save / Load"]
	for index in range(left_controls.size()):
		var left := _label(left_controls[index], 10, TEXT_DIM)
		left.position = Vector2(24, 92 + index * 18)
		left.size = Vector2(210, 14)
		panel.add_child(left)
		var right := _label(right_controls[index], 10, TEXT_DIM)
		right.position = Vector2(240, 92 + index * 18)
		right.size = Vector2(200, 14)
		panel.add_child(right)

	var buttons := [
		["RESUME", "_on_resume_pressed"],
		["SAVE", "_on_save_pressed"],
		["LOAD", "_on_load_pressed"],
		["QUIT", "_on_quit_pressed"]
	]
	for index in range(buttons.size()):
		var button := _button(buttons[index][0])
		button.position = Vector2(24 + index * 108, 236)
		button.size = Vector2(100, 28)
		button.pressed.connect(Callable(self, buttons[index][1]))
		panel.add_child(button)
		pause_buttons.append(button)

	var footer := _label("ESC  Resume", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	footer.position = Vector2(24, 276)
	footer.size = Vector2(412, 12)
	panel.add_child(footer)


# --- Agent 3 presentation: targeted block readout --------------------------

func _build_target() -> void:
	target_label = _label("", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	target_label.name = "TargetBlock"
	target_label.position = Vector2(300, 260)
	target_label.size = Vector2(254, 14)
	target_label.visible = false
	add_child(target_label)


func _update_target() -> void:
	if not is_instance_valid(world) or not is_instance_valid(player) or paused or death_overlay.visible:
		target_label.visible = false
		return
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		target_label.visible = false
		return
	var hit := MiningSystem.raycast(world, camera.global_position, -camera.global_basis.z, 7.0)
	if hit.is_empty():
		target_label.visible = false
		return
	var cell: Vector3i = hit["cell"]
	# Air cells report "Sky"; only solid blocks deserve a target readout.
	if world.get_block_id(cell) == world.air_id:
		target_label.visible = false
		return
	var name := MiningSystem.display_name(world, cell)
	if name == "":
		target_label.visible = false
		return
	var tier := MiningSystem.mining_tier(world, cell)
	var hard := MiningSystem.hardness(world, cell)
	target_label.text = "%s   tier %d   hardness %.2f" % [name.to_upper(), tier, hard]
	target_label.visible = true


# --- Agent 3 presentation: dialogue panel -----------------------------------

func _build_dialogue() -> void:
	dialogue_panel = _panel(Rect2(197, 300, 460, 120), _style(Color(0.03, 0.06, 0.08, 0.96), PANEL_BORDER, 1, 5))
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.visible = false
	dialogue_name = _label("", 12, Color(0.55, 0.95, 0.85))
	dialogue_name.position = Vector2(210, 308)
	dialogue_name.size = Vector2(434, 16)
	add_child(dialogue_name)
	dialogue_text = _label("", 11, TEXT_PALE)
	dialogue_text.position = Vector2(210, 332)
	dialogue_text.size = Vector2(434, 64)
	dialogue_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(dialogue_text)
	# This footer belongs to the dialogue panel. When it lived directly on the
	# CanvasLayer it stayed visible for the whole session with no dialogue open.
	dialogue_footer = _label("E  Continue    ESC  Close", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	dialogue_footer.position = Vector2(13, 98)
	dialogue_footer.size = Vector2(434, 12)
	dialogue_panel.add_child(dialogue_footer)


func open_dialogue(npc: NpcBase) -> void:
	active_npc = npc
	dialogue_open = true
	dialogue_panel.visible = true
	if npc != null:
		dialogue_name.text = npc.npc_name.to_upper()
		dialogue_text.text = npc.get_dialogue_line()
		if String(npc.npc_name).to_lower().contains("guide"):
			_show_toast("Press G for the Guide's crafting list")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _nearest_npc() -> NpcBase:
	if not is_instance_valid(player):
		return null
	var best: NpcBase = null
	var best_dist := 3.0
	for node in get_tree().get_nodes_in_group("npcs"):
		if node is NpcBase:
			var npc := node as NpcBase
			var d := npc.global_position.distance_to(player.global_position)
			if d < best_dist:
				best_dist = d
				best = npc
	return best


func close_dialogue() -> void:
	dialogue_open = false
	dialogue_panel.visible = false
	active_npc = null
	if not paused and not death_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func advance_dialogue() -> void:
	if active_npc == null:
		close_dialogue()
		return
	if not active_npc.advance_dialogue():
		close_dialogue()
		return
	dialogue_text.text = active_npc.get_dialogue_line()


# --- Agent 3 presentation: mining feedback ---------------------------------

func _on_block_edited(cell: Vector3i, _block_id: int) -> void:
	# block_edited fires for every edit including placement; spawn a burst at
	# the cell centre for break feedback.
	if not is_instance_valid(world):
		return
	var main := get_parent()
	if not (main is Node3D):
		return
	var at := Vector3(float(cell.x) + 0.5, float(cell.y) + 0.5, float(cell.z) + 0.5)
	Vfx.burst(main as Node3D, at, Color(0.95, 0.72, 0.40), Vector3.UP, 8, 3.0, 0.05, 0.28, 4.0)
	if mining_click_player != null:
		mining_click_player.play()
	mined_blocks += 1
	# Onboarding: first mined block
	if not onboarding_done[1]:
		onboarding_done[1] = true
		_show_onboarding(2)


func _setup_mining_audio() -> void:
	mining_click_player = AudioStreamPlayer.new()
	mining_click_player.bus = "UI"
	mining_click_player.volume_db = -12.0
	var stream := AudioStreamWAV.new()
	var mix_rate := 22050
	var samples := PackedFloat32Array()
	samples.resize(int(mix_rate * 0.06))
	for i in range(samples.size()):
		var t := float(i) / float(mix_rate)
		var decay := exp(-t * 40.0)
		samples[i] = sin(TAU * 620.0 * t) * decay * 0.6
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 20000.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	mining_click_player.stream = stream
	add_child(mining_click_player)


# --- Agent 3 presentation: onboarding hints ---------------------------------

func _show_onboarding(step: int) -> void:
	onboarding_step = step
	var lines := [
		"WASD to move  ·  Mouse to look  ·  SPACE to jump",
		"1-9 / wheel selects a hotbar item  ·  LMB uses it",
		"Hold LMB with a pickaxe to mine  ·  an axe on a trunk fells the whole tree",
		"RMB places a block  ·  B opens inventory  ·  C opens crafting  ·  ESC pauses",
	]
	if step < lines.size() and not onboarding_done[step]:
		show_world_hint(lines[step], 5.0)


# --- Live updates -----------------------------------------------------------

func _update_flashlight() -> void:
	var on := is_instance_valid(world) and world.flashlight_enabled
	flashlight_label.text = "TORCH  ON" if on else "TORCH  OFF"
	flashlight_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.78) if on else Color(0.42, 0.48, 0.48))


const BIOME_ACCENTS := [
	Color(0.86, 0.72, 0.45), # Forest
	Color(0.55, 0.80, 0.62), # Jungle
	Color(0.62, 0.85, 1.00), # Snow
	Color(0.60, 0.80, 0.35), # Forest
]
const BIOME_INTRO_TIME := 3.2


func _update_biome(delta: float) -> void:
	if not is_instance_valid(world) or not world.is_generated:
		return
	var cell := Vector3i(floori(player.position.x), 0, floori(player.position.z))
	var biome := world.get_biome_at(cell)
	if biome != last_biome:
		if last_biome >= 0:
			# Only announce crossings, never the initial read at spawn.
			biome_intro_label.text = "ENTERING:  %s" % BiomeManager.biome_name(biome).to_upper()
			biome_intro_time = BIOME_INTRO_TIME
		last_biome = biome
		biome_label.text = BiomeManager.biome_name(biome).to_upper()
		var accent: Color = BIOME_ACCENTS[biome] if biome < BIOME_ACCENTS.size() else TEXT_DIM
		biome_label.add_theme_color_override("font_color", accent)
		biome_intro_label.add_theme_color_override("font_color", accent)
	if biome_intro_time > 0.0:
		biome_intro_time = maxf(0.0, biome_intro_time - delta)
		var fade := 1.0
		var remaining := biome_intro_time
		if remaining > BIOME_INTRO_TIME - 0.4:
			fade = (BIOME_INTRO_TIME - remaining) / 0.4
		elif remaining < 0.8:
			fade = remaining / 0.8
		biome_intro_label.visible = true
		biome_intro_label.modulate.a = clampf(fade, 0.0, 1.0)
	else:
		biome_intro_label.visible = false


func _update_health() -> void:
	var max_health := maxf(player.max_health, 1.0)
	var ratio := clampf(player.health / max_health, 0.0, 1.0)
	var needed := clampi(ceili(max_health / 10.0), 1, MAX_HEART_ICONS)
	var lit := 0 if ratio <= 0.001 else ceili(ratio * float(needed))
	for index in range(heart_icons.size()):
		var heart := heart_icons[index]
		heart.visible = index < needed
		if not heart.visible:
			continue
		if index < lit:
			heart.texture = HEART_TEXTURE
			heart.modulate = Color(1.0, 0.82, 0.82, 1.0) if ratio < 0.35 else Color.WHITE
		else:
			heart.texture = HEART_EMPTY_TEXTURE
			heart.modulate = Color(0.55, 0.55, 0.55, 0.85)
	_layout_hearts(needed)


func _update_status() -> void:
	var remaining: float = caster.status_time
	status_label.visible = remaining > 0.0
	if not status_label.visible:
		return
	status_label.text = caster.status_message
	status_label.modulate.a = clampf(remaining / 0.45, 0.0, 1.0)


func _update_hint() -> void:
	var active: bool = caster.hint_time > 0.0
	hint_panel.visible = active
	hint_label.visible = active
	if not active:
		return
	hint_label.text = caster.hint_text
	var fade := clampf(caster.hint_time / maxf(caster.hint_fade * 0.35, 0.001), 0.0, 1.0)
	hint_panel.modulate.a = fade
	hint_label.modulate.a = fade


# --- Pause ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if death_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
			_on_respawn_pressed()
			get_viewport().set_input_as_handled()
		return
	# An open chest swallows E and ESC: close it instead of re-opening it or
	# letting the player's door/interact logic run underneath.
	if chest_visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_E or event.keycode == KEY_ESCAPE):
		close_chest()
		get_viewport().set_input_as_handled()
		return
	if chest_visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_I or event.keycode == KEY_C):
		close_chest()
		get_viewport().set_input_as_handled()
		return
	# NPC interaction: E near an NPC opens dialogue instead of the player's build action.
	if (not dialogue_open) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var npc := _nearest_npc()
		if npc != null:
			open_dialogue(npc)
			get_viewport().set_input_as_handled()
			return
	if (not dialogue_open) and (not chest_visible) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var chest_target := _chest_under_crosshair()
		if chest_target != Vector3i(-1, -1, -1):
			open_chest(chest_target)
			get_viewport().set_input_as_handled()
			return
	if dialogue_open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_E or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				advance_dialogue()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_ESCAPE:
				close_dialogue()
				get_viewport().set_input_as_handled()
				return
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			_toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_toggle_crafting()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_G:
			_toggle_guide()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_toggle_shop()
			get_viewport().set_input_as_handled()
			return
		# Terraria's ESC opens and closes the inventory over the running world.
		# It does not pause the game and does not open a pause menu.
		if (inventory_visible or crafting_visible or guide_visible or shop_visible) and event.keycode == KEY_ESCAPE:
			close_panels()
			get_viewport().set_input_as_handled()
			return
		# The save/load/quit menu moved to F1 so ESC can behave like Terraria.
		if paused and event.keycode == KEY_ESCAPE:
			resume_game()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F1:
			if paused:
				resume_game()
			else:
				pause_game()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if paused:
		resume_game()
	else:
		_toggle_inventory()
	get_viewport().set_input_as_handled()


func pause_game() -> void:
	paused = true
	pause_overlay.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_game() -> void:
	paused = false
	pause_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_respawn_pressed() -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("respawn_player"):
		parent.respawn_player()


func _on_resume_pressed() -> void:
	resume_game()


func _on_save_pressed() -> void:
	if get_parent().has_method("save_game"):
		get_parent().save_game()


func _on_load_pressed() -> void:
	if get_parent().has_method("load_game"):
		get_parent().load_game()
	resume_game()


func _on_quit_pressed() -> void:
	get_tree().quit()
# --- Terraria layout pass ----------------------------------------------------

## The HUD was originally authored for an 854x480 viewport. Reposition the key
## elements for the real 1280x720 root viewport and retire the ArcaneCaster UI.
func _layout_for_viewport() -> void:
	# The HUD is authored against the project's 1280x720 render viewport. Using
	# get_viewport().size here returned the 1920x1080 window override, which put
	# the hotbar and vitals off-screen. The stretch mode scales this layout.
	var vp := Vector2(1280.0, 720.0)
	var cx: float = vp.x * 0.5

	# These captions were added straight to the CanvasLayer, not to the panels
	# above, so hiding the panels alone left stray text on the screen edge.
	for legacy_name in ["LegacyArcaneCaption", "LegacyVitalsCaption"]:
		var legacy_node := get_node_or_null(NodePath(legacy_name))
		if legacy_node != null:
			legacy_node.visible = false
	# Terraria prints no torch or biome text over the world; the continuous
	# biome tag and torch state remain available in the F3 debug readout.
	if flashlight_label != null:
		flashlight_label.visible = false
	if biome_label != null:
		biome_label.visible = false

	# Centred crosshair.
	var crosshair := get_node_or_null("Crosshair") as Control
	if crosshair != null:
		crosshair.position = Vector2(cx - 6.0, vp.y * 0.5 - 6.0)

	# Hotbar: top-left corner, flush with the screen edge as in Terraria.
	if hotbar_panel != null:
		hotbar_panel.position = Vector2(12.0, 12.0)
	if held_label != null:
		held_label.position = Vector2(14.0, 12.0 + HOTBAR_SLOT + HOTBAR_PAD * 2.0 + 5.0)
		held_label.size = Vector2(360.0, 16.0)

	# Depth/layer/environment/house readouts are genuine world state but are not
	# part of Terraria's HUD, so they are kept small and out of the corner the
	# heart row occupies.
	if layer_label != null:
		layer_label.position = Vector2(16.0, vp.y - 40.0)
		layer_label.size = Vector2(252.0, 10.0)
		layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if environment_label != null:
		environment_label.position = Vector2(16.0, vp.y - 30.0)
		environment_label.size = Vector2(252.0, 10.0)
		environment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if house_label != null:
		house_label.position = Vector2(16.0, vp.y - 20.0)
		house_label.size = Vector2(360.0, 10.0)
	if health_bar != null:
		health_bar.visible = false
	if health_fill != null:
		health_fill.visible = false
	# Hearts and stars lay themselves out from the live max health/mana.
	if is_instance_valid(player):
		_update_health()
	_update_mana()

	# Transient text.
	if status_label != null:
		status_label.position = Vector2(cx - 300.0, vp.y - 142.0)
	if world_hint_label != null:
		world_hint_label.position = Vector2(cx - 300.0, 70.0)
	if interaction_label != null:
		interaction_label.position = Vector2(cx - 177.0, vp.y - 154.0)
	if notification_label != null:
		notification_label.position = Vector2(cx - 300.0, 120.0)
	if target_label != null:
		target_label.position = Vector2(cx - 200.0, vp.y * 0.5 - 90.0)
	if boss_panel != null:
		boss_panel.position = Vector2(cx - 177.0, 12.0)
	if biome_intro_label != null:
		biome_intro_label.position = Vector2(cx - 300.0, 96.0)


## Right-aligned rows of ten hearts, exactly like Terraria's health display.
func _layout_hearts(needed: int) -> void:
	heart_rows = int(ceil(float(needed) / 10.0))
	for index in range(mini(needed, heart_icons.size())):
		var row := index / 10
		var col := index % 10
		var in_row := mini(10, needed - row * 10)
		var x := VP.x - 14.0 - float(in_row - col) * HEART_SPACING
		heart_icons[index].position = Vector2(x, 12.0 + float(row) * (HEART_SIZE + 1.0))


## Mana stars sit directly under the hearts, right-aligned, one per 20 mana.
func _layout_mana(needed: int) -> void:
	var top := 12.0 + float(heart_rows) * (HEART_SIZE + 1.0) + 2.0
	for index in range(mini(needed, mana_stars.size())):
		var x := VP.x - 14.0 - float(needed - index) * STAR_SPACING + 2.0
		mana_stars[index].position = Vector2(x, top)


# --- Agent 3: hotbar ---------------------------------------------------------

func _build_hotbar() -> void:
	# Terraria's hotbar is the top-left row of ten slots, flush against the
	# screen corner. It doubles as the top row of the inventory when that opens.
	var width := 10.0 * HOTBAR_SLOT + HOTBAR_PAD * 2.0
	var height := HOTBAR_SLOT + HOTBAR_PAD * 2.0
	hotbar_panel = _panel(Rect2(12, 12, width, height), _style(PANEL_BG, PANEL_BORDER, 2, 3))
	hotbar_panel.name = "HotbarPanel"
	hotbar_slots.clear()
	hotbar_labels.clear()
	hotbar_counts.clear()
	hotbar_icons.clear()
	for i in range(10):
		var slot := Panel.new()
		slot.position = Vector2(HOTBAR_PAD + float(i) * HOTBAR_SLOT, HOTBAR_PAD)
		slot.size = Vector2(HOTBAR_SLOT, HOTBAR_SLOT)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 2, 2))
		hotbar_panel.add_child(slot)
		hotbar_slots.append(slot)
		var icon := TextureRect.new()
		icon.position = Vector2(4, 4)
		icon.size = Vector2(HOTBAR_SLOT - 12.0, HOTBAR_SLOT - 12.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		hotbar_icons.append(icon)
		# Name labels are kept for compatibility but never shown: Terraria
		# does not print item names inside hotbar slots.
		var lbl := _label("", 7, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
		lbl.position = Vector2(0, 20)
		lbl.size = Vector2(HOTBAR_SLOT, 8)
		lbl.visible = false
		slot.add_child(lbl)
		hotbar_labels.append(lbl)
		var cnt := _label("", 12, Color(1.0, 0.97, 0.86), HORIZONTAL_ALIGNMENT_RIGHT)
		cnt.position = Vector2(2, HOTBAR_SLOT - 17.0)
		cnt.size = Vector2(HOTBAR_SLOT - 6.0, 14)
		cnt.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 1.0))
		cnt.add_theme_constant_override("outline_size", 3)
		slot.add_child(cnt)
		hotbar_counts.append(cnt)
	# Terraria names the item you just selected, above the hotbar, then fades it.
	held_label = _label("", 12, Color(1.0, 0.95, 0.80))
	held_label.name = "HeldItemName"
	held_label.position = Vector2(14, 66)
	held_label.size = Vector2(320, 16)
	held_label.modulate.a = 0.0
	add_child(held_label)

func _refresh_hotbar(_arg: Variant = null) -> void:
	if not is_instance_valid(player) or player.get("inventory") == null:
		return
	var inv = player.inventory
	for i in range(10):
		if i >= hotbar_slots.size():
			break
		var slot_panel: Panel = hotbar_slots[i]
		var lbl: Label = hotbar_labels[i]
		var cnt: Label = hotbar_counts[i]
		var stack: Dictionary = inv.get_slot("hotbar", i)
		var id := StringName(stack.get("id", &""))
		var amount := int(stack.get("amount", 0))
		var icon: TextureRect = hotbar_icons[i] if i < hotbar_icons.size() else null
		if id == &"" or amount <= 0:
			lbl.text = ""
			cnt.text = ""
			if icon != null:
				icon.texture = null
			slot_panel.modulate.a = 0.55
		else:
			var def := ItemDatabase.get_item(id)
			var name := String(id)
			if def != null and def.display_name != "":
				name = def.display_name
			lbl.text = ""
			if icon != null:
				icon.texture = ItemIcons.icon_for(id)
			cnt.text = "%d" % amount if amount > 1 else ""
			slot_panel.modulate.a = 1.0
			slot_panel.tooltip_text = name
			# Terraria flashes the selected item's name above the hotbar.
			if held_label != null and i == int(inv.selected) and id != _held_shown:
				_held_shown = id
				held_label.text = name
				held_time = 1.8
		# Selected highlight
		var selected := int(inv.selected) == i
		var style := slot_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = SLOT_SELECTED if selected else SLOT_BORDER
			style.border_width_left = 2 if selected else 1
			style.border_width_top = 2 if selected else 1
			style.border_width_right = 2 if selected else 1
			style.border_width_bottom = 2 if selected else 1


# --- Agent 3: mana -----------------------------------------------------------

func _build_mana() -> void:
	# Terraria's mana display is a row of blue stars under the hearts, one star
	# per 20 mana, with the last star partially filled. There is no bar and no
	# caption, so neither is created.
	mana_stars.clear()
	for index in range(MAX_MANA_STARS):
		var star := ManaStar.new()
		star.name = "ManaStar%d" % index
		star.size = Vector2(STAR_SIZE_MANA, STAR_SIZE_MANA)
		star.visible = false
		add_child(star)
		mana_stars.append(star)

func _update_mana() -> void:
	if not is_instance_valid(player) or player.get("weapons") == null:
		return
	var w = player.weapons
	var maximum := float(w.max_mana)
	var current := clampf(float(w.mana), 0.0, maximum)
	var needed := clampi(ceili(maximum / MANA_PER_STAR), 1, MAX_MANA_STARS)
	for index in range(mana_stars.size()):
		var star := mana_stars[index]
		star.visible = index < needed
		if not star.visible:
			continue
		var star_floor := float(index) * MANA_PER_STAR
		star.ratio = clampf((current - star_floor) / MANA_PER_STAR, 0.0, 1.0)
	_layout_mana(needed)

func _on_mana_changed(_current: float, _maximum: float) -> void:
	_update_mana()


# --- Agent 3: interaction prompt --------------------------------------------

func _build_interaction() -> void:
	interaction_label = _label("", 11, Color(0.86, 0.95, 0.91), HORIZONTAL_ALIGNMENT_CENTER)
	interaction_label.name = "InteractionPrompt"
	interaction_label.position = Vector2(250, 380)
	interaction_label.size = Vector2(354, 20)
	interaction_label.visible = false
	add_child(interaction_label)

func _update_interaction() -> void:
	if not is_instance_valid(player):
		interaction_label.visible = false
		return
	var near_npc := false
	var npc_name := ""
	for node in get_tree().get_nodes_in_group("npc"):
		if node is Node3D:
			var n := node as Node3D
			if n.global_position.distance_to(player.global_position) <= 3.5:
				near_npc = true
				if node.has_method("get") and node.get("display_name") != null:
					npc_name = String(node.get("display_name"))
				elif node.has_method("get") and node.get("npc_name") != null:
					npc_name = String(node.get("npc_name"))
				break
	if dialogue_open:
		interaction_label.visible = false
		return
	if near_npc:
		interaction_label.text = "Press E to talk to %s" % (npc_name if npc_name != "" else "NPC")
		interaction_label.visible = true
	else:
		interaction_label.visible = false


# --- Agent 3: notifications / toasts ---------------------------------------

func _build_notification() -> void:
	notification_label = _label("", 12, Color(0.98, 0.86, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	notification_label.name = "WorldNotification"
	notification_label.position = Vector2(127, 120)
	notification_label.size = Vector2(600, 24)
	notification_label.visible = false
	add_child(notification_label)

func show_notification(text: String, duration := 3.5) -> void:
	notification_queue.append(text)
	notification_time = maxf(notification_time, duration)

func _update_notification(delta: float) -> void:
	if notification_time > 0.0:
		notification_time = maxf(0.0, notification_time - delta)
		if notification_label != null:
			notification_label.visible = true
			if notification_label.text == "" and not notification_queue.is_empty():
				notification_label.text = notification_queue.pop_front()
			notification_label.modulate.a = clampf(notification_time / 0.5, 0.0, 1.0)
		if notification_time <= 0.0:
			if notification_label != null:
				notification_label.visible = false
				notification_label.text = ""
	else:
		if not notification_queue.is_empty():
			var next: String = String(notification_queue.pop_front())
			notification_label.text = next
			notification_time = 3.5
			notification_label.visible = true
		else:
			if notification_label != null:
				notification_label.visible = false

func _on_gameplay_message(text: String) -> void:
	show_notification(text, 2.0)

func _on_discovered(key: StringName) -> void:
	show_notification("Discovered: %s" % String(key).replace("_", " ").capitalize(), 3.0)

func _on_flag_set(flag: StringName) -> void:
	show_notification("Unlocked: %s" % String(flag).replace("_", " ").capitalize(), 3.0)


# --- Agent 3: boss HUD ------------------------------------------------------

func _build_boss() -> void:
	boss_panel = _panel(Rect2(250, 12, 354, 52), _style(Color(0.04, 0.02, 0.02, 0.92), Color(0.62, 0.16, 0.14, 0.7), 1, 4))
	boss_panel.name = "BossPanel"
	boss_panel.visible = false
	boss_name_label = _label("", 12, Color(0.94, 0.34, 0.28), HORIZONTAL_ALIGNMENT_CENTER)
	boss_name_label.position = Vector2(10, 4)
	boss_name_label.size = Vector2(334, 16)
	boss_panel.add_child(boss_name_label)
	var bar_bg := _style(Color(0.02, 0.02, 0.03, 0.95), Color(0.4, 0.12, 0.10, 0.8), 1, 2)
	boss_bg_panel = Panel.new()
	boss_bg_panel.position = Vector2(10, 24)
	boss_bg_panel.size = Vector2(334, 12)
	boss_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bg_panel.add_theme_stylebox_override("panel", bar_bg)
	boss_bg_panel.visible = false
	boss_panel.add_child(boss_bg_panel)
	boss_health_style = _style(Color(0.88, 0.24, 0.18, 0.95), Color(1.0, 0.5, 0.4, 0.8), 1, 1)
	boss_health_fill = Panel.new()
	boss_health_fill.position = Vector2(11, 25)
	boss_health_fill.size = Vector2(332, 10)
	boss_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_health_fill.add_theme_stylebox_override("panel", boss_health_style)
	boss_health_fill.visible = false
	boss_panel.add_child(boss_health_fill)

func _update_boss() -> void:
	if boss_panel == null:
		return
	if boss_target == null or not is_instance_valid(boss_target):
		boss_target = null
		# Only a real boss group entry gets the boss bar. The old fallback to any
		# 100+ HP enemy showed a nameless health bar during normal play.
		for node in get_tree().get_nodes_in_group("bosses"):
			boss_target = node
			break
	if boss_target == null or not is_instance_valid(boss_target):
		boss_panel.visible = false
		boss_bg_panel.visible = false
		boss_name_label.visible = false
		boss_health_fill.visible = false
		return
	boss_panel.visible = true
	boss_bg_panel.visible = true
	boss_name_label.visible = true
	boss_health_fill.visible = true
	var nm := "BOSS"
	if boss_target.get("display_name") != null:
		nm = String(boss_target.get("display_name"))
	elif boss_target.get("boss_name") != null:
		nm = String(boss_target.get("boss_name"))
	boss_name_label.text = nm.to_upper()
	var hp := float(boss_target.get("health")) if boss_target.get("health") != null else 0.0
	var maxhp := float(boss_target.get("max_health")) if boss_target.get("max_health") != null else 1.0
	var ratio := clampf(hp / maxf(maxhp, 1.0), 0.0, 1.0)
	boss_health_fill.size.x = 332.0 * ratio

func _build_status_effects() -> void:
	status_effects_label = _label("", 9, TEXT_WARN, HORIZONTAL_ALIGNMENT_LEFT)
	status_effects_label.position = Vector2(16, 332)
	status_effects_label.size = Vector2(252, 12)
	add_child(status_effects_label)

func _update_status_effects() -> void:
	if not is_instance_valid(player) or player.get("statuses") == null:
		status_effects_label.text = ""
		return
	var st = player.statuses
	var parts: Array[String] = []
	for key in st.active.keys():
		parts.append("%s %.0fs" % [String(key).to_upper(), float(st.active[key])])
	status_effects_label.text = "  ".join(parts)


# --- Agent 3: inventory & crafting panels ------------------------------------

func _build_inventory_panel() -> void:
	# Terraria's expanded inventory: the hotbar row on top, four rows of ten
	# main slots under it, the equipment column to the right, and the crafting
	# list below that, all on the same navy/bronze panel treatment. Pressing ESC
	# opens it over a running world; it never pauses the game.
	var panel_w := 700.0
	var panel_h := 470.0
	var pad := 8.0
	var slot := HOTBAR_SLOT
	inventory_panel = _panel(Rect2(12, 12, panel_w, panel_h), _style(PANEL_BG, PANEL_BORDER, 2, 3))
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	inv_slot_panels.clear()
	equip_slot_panels.clear()

	var hotbar_y := pad
	for i in range(InventoryModel.HOTBAR_SIZE):
		_add_inventory_slot(inventory_panel, "hotbar", i, Vector2(pad + float(i) * slot, hotbar_y), slot)

	var grid_x := pad
	var grid_y := hotbar_y + slot + 2.0
	var grid_cols := 10
	for i in range(InventoryModel.MAIN_SIZE):
		var col := i % grid_cols
		var row := i / grid_cols
		_add_inventory_slot(inventory_panel, "main", i, Vector2(grid_x + float(col) * slot, grid_y + float(row) * slot), slot)

	# Equipment column, right of the grid, in Terraria's armour order.
	var eq_x := grid_x + float(grid_cols) * slot + 12.0
	var eq_labels := {"head": "HELMET", "chest": "SHIRT", "legs": "PANTS", "accessory": "ACCESSORY"}
	var eq_y := pad
	for name in InventoryModel.EQUIPMENT_SLOTS:
		var caption := _label(eq_labels.get(name, name.to_upper()), 8, TEXT_DIM)
		caption.position = Vector2(eq_x, eq_y)
		caption.size = Vector2(200, 10)
		inventory_panel.add_child(caption)
		var p := Panel.new()
		p.position = Vector2(eq_x, eq_y + 11.0)
		p.size = Vector2(slot, slot)
		p.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 2, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		var index := InventoryModel.EQUIPMENT_SLOTS.find(name)
		p.gui_input.connect(func(ev): _on_inv_slot_input("equipment", index, ev, p))
		p.mouse_exited.connect(func(): _hide_tooltip())
		inventory_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(4, 4)
		picon.size = Vector2(slot - 8.0, slot - 8.0)
		picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		equip_slot_panels[name] = {"panel": p, "label": null, "icon": picon, "slot": name}
		eq_y += 54.0

	# Crafting list, bottom-left, where Terraria grows it when a station or the
	# player's materials make something available.
	var craft_top := grid_y + 4.0 * slot + 26.0
	var craft_title := _label("CRAFTING", 9, Color(0.86, 0.76, 0.52))
	craft_title.position = Vector2(pad, craft_top)
	craft_title.size = Vector2(240, 12)
	inventory_panel.add_child(craft_title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(pad, craft_top + 15.0)
	scroll.size = Vector2(float(grid_cols) * slot, panel_h - craft_top - 58.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_panel.add_child(scroll)
	inv_craft_list = VBoxContainer.new()
	inv_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inv_craft_list)

	# Terraria shows the hovered item's name under the grid.
	inv_hover_label = _label("", 10, Color(0.92, 0.88, 0.70))
	inv_hover_label.name = "InventoryItemName"
	inv_hover_label.position = Vector2(eq_x, 4.0 + 54.0 * float(InventoryModel.EQUIPMENT_SLOTS.size()) + 4.0)
	inv_hover_label.size = Vector2(panel_w - eq_x - pad, 14)
	inventory_panel.add_child(inv_hover_label)

	var hint := _label("ESC closes  ·  click two slots to move or swap  ·  F1 save/load/quit", 9, TEXT_DIM)
	hint.position = Vector2(pad, panel_h - 20.0)
	hint.size = Vector2(panel_w - pad * 2.0, 12)
	inventory_panel.add_child(hint)


## One inventory slot: panel, icon and stack count, wired to the shared click
## handler. Used for every area so the hotbar row, grid and chest rows match.
func _add_inventory_slot(parent: Control, area: String, index: int, pos: Vector2, slot_size: float) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = Vector2(slot_size, slot_size)
	p.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 2, 2))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev): _on_inv_slot_input(area, index, ev, p))
	p.mouse_exited.connect(func(): _hide_tooltip())
	parent.add_child(p)
	var picon := TextureRect.new()
	picon.position = Vector2(4, 4)
	picon.size = Vector2(slot_size - 8.0, slot_size - 8.0)
	picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(picon)
	var pcnt := _label("", 11, Color(1.0, 0.97, 0.86), HORIZONTAL_ALIGNMENT_RIGHT)
	pcnt.position = Vector2(2, slot_size - 16.0)
	pcnt.size = Vector2(slot_size - 6.0, 13)
	pcnt.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 1.0))
	pcnt.add_theme_constant_override("outline_size", 3)
	p.add_child(pcnt)
	inv_slot_panels.append({"panel": p, "label": null, "count": pcnt, "icon": picon, "area": area, "index": index})


func _hide_tooltip() -> void:
	if tooltip_label != null:
		tooltip_label.visible = false
	if inv_hover_label != null:
		inv_hover_label.text = ""


func _build_crafting_panel() -> void:
	crafting_panel = _panel(Rect2(120, 90, 640, 400), _style(PANEL_BG, PANEL_BORDER, 2, 4))
	crafting_panel.name = "CraftingPanel"
	crafting_panel.visible = false
	# _panel() already added this node.
	var title := _label("CRAFTING", 13, Color(0.98, 0.86, 0.52))
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	crafting_panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 42)
	scroll.size = Vector2(300, 336)
	crafting_panel.add_child(scroll)
	craft_list = VBoxContainer.new()
	craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(craft_list)
	craft_station_label = _label("", 9, Color(0.74, 0.84, 0.94))
	craft_station_label.position = Vector2(12, 27)
	craft_station_label.size = Vector2(616, 12)
	crafting_panel.add_child(craft_station_label)
	craft_detail_label = _label("Select a recipe.", 10, TEXT_PALE)
	craft_detail_label.position = Vector2(322, 42)
	craft_detail_label.size = Vector2(300, 296)
	craft_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crafting_panel.add_child(craft_detail_label)
	var craft_btn := Button.new()
	craft_btn.text = "Craft"
	craft_btn.position = Vector2(290, 350)
	craft_btn.size = Vector2(120, 28)
	craft_btn.pressed.connect(_on_craft_pressed)
	crafting_panel.add_child(craft_btn)
	var hint := _label("C to close.", 8, TEXT_DIM)
	hint.position = Vector2(12, 378)
	hint.size = Vector2(616, 12)
	crafting_panel.add_child(hint)

## --- Guide -----------------------------------------------------------------
## The Guide shows what the player's currently selected material can be made
## into. Recipes come from the same RecipeDatabase the crafting system uses and
## the "have / need" numbers come from the live inventory.
func _build_guide_panel() -> void:
	guide_panel = _panel(Rect2(120, 90, 640, 400), _style(PANEL_BG, PANEL_BORDER, 2, 4))
	guide_panel.name = "GuidePanel"
	guide_panel.visible = false
	var title := _label("GUIDE", 13, Color(0.98, 0.86, 0.52))
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	guide_panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 40)
	scroll.size = Vector2(260, 340)
	guide_panel.add_child(scroll)
	guide_list = VBoxContainer.new()
	guide_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(guide_list)
	guide_detail = _label("Hold a material in a hotbar slot, then ask the Guide.", 10, TEXT_PALE)
	guide_detail.position = Vector2(290, 40)
	guide_detail.size = Vector2(330, 300)
	guide_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_panel.add_child(guide_detail)
	var hint := _label("G to close   ·   shows recipes that use your selected hotbar item", 9, TEXT_DIM)
	hint.position = Vector2(12, 378)
	hint.size = Vector2(616, 12)
	guide_panel.add_child(hint)


func _refresh_guide_list() -> void:
	if guide_list == null or player == null:
		return
	for child in guide_list.get_children():
		child.queue_free()
	var inv = player.get("inventory")
	var filter := &""
	if inv != null:
		var stack: Dictionary = inv.get_slot("hotbar", int(inv.selected))
		filter = StringName(stack.get("id", &""))
	guide_filter_id = filter
	var cs = player.get("crafting")
	var recipes := RecipeDatabase.all()
	var shown := 0
	for recipe in recipes:
		if filter != &"" and not recipe.ingredients.has(String(filter)) and recipe.output_id() != filter:
			continue
		shown += 1
		var btn := Button.new()
		var can: bool = cs != null and bool(cs.can_craft(recipe))
		btn.text = recipe.display_name
		btn.modulate = Color(1.0, 0.95, 0.80) if can else Color(0.72, 0.76, 0.82)
		btn.tooltip_text = "%s  ·  Station: %s" % ["Ready to craft" if can else "Missing materials", recipe.station if recipe.station != "none" else "hand"]
		btn.pressed.connect(func(): _select_guide_recipe(recipe))
		guide_list.add_child(btn)
	if shown == 0:
		guide_detail.text = "The Guide has nothing to suggest for that item."
	elif filter != &"":
		var def := ItemDatabase.get_item(filter)
		var item_name := String(filter)
		if def != null and def.display_name != "":
			item_name = def.display_name
		guide_detail.text = "USED IN RECIPES: %s\n\nSelect a recipe on the left to see its ingredients." % item_name.to_upper()
	else:
		guide_detail.text = "Select a hotbar item to filter, or pick a recipe on the left."


func _item_name(id: StringName) -> String:
	var def := ItemDatabase.get_item(id)
	if def != null and def.display_name != "":
		return def.display_name
	return String(id)


func _select_guide_recipe(recipe: CraftingRecipe) -> void:
	guide_selected = recipe
	if guide_detail == null:
		return
	var lines: Array[String] = [recipe.display_name.to_upper(), ""]
	if recipe.description != "":
		lines.append(recipe.description)
	lines.append("Station: " + (recipe.station if recipe.station != "none" else "hand"))
	lines.append("")
	lines.append("Ingredients:")
	var ready := true
	for key in recipe.ingredients.keys():
		var id := StringName(String(key))
		var need := int(recipe.ingredients[key])
		var have := 0
		if player != null and player.get("inventory") != null:
			have = player.inventory.count(id)
		if have < need:
			ready = false
		lines.append("  %s   %d/%d" % [_item_name(id), mini(have, need), need])
	lines.append("")
	lines.append("Result: %s x%d" % [_item_name(recipe.output_id()), recipe.output_amount()])
	lines.append("")
	if ready:
		lines.append("You have everything needed. Press C to craft it.")
	else:
		lines.append("You are missing materials for this recipe.")
	guide_detail.text = "\n".join(lines)


func _toggle_guide() -> void:
	guide_visible = not guide_visible
	if guide_panel != null:
		guide_panel.visible = guide_visible
	if guide_visible:
		inventory_visible = false
		crafting_visible = false
		shop_visible = false
		if inventory_panel != null:
			inventory_panel.visible = false
		if crafting_panel != null:
			crafting_panel.visible = false
		if shop_panel != null:
			shop_panel.visible = false
		_refresh_guide_list()
		_set_mouse_captured(false)
	else:
		_set_mouse_captured(true)


## --- Shop -------------------------------------------------------------------
## A resident merchant's buy list, a sell button for the held hotbar stack, and
## whatever quest they're offering. Always reachable with B, same as the Guide
## panel is always reachable with G - the dialogue line just points you at it.
func _build_shop_panel() -> void:
	shop_panel = _panel(Rect2(120, 90, 640, 400), _style(PANEL_BG, PANEL_BORDER, 2, 4))
	shop_panel.name = "ShopPanel"
	shop_panel.visible = false
	var title := _label("SHOP", 13, Color(0.98, 0.86, 0.52))
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	shop_panel.add_child(title)
	shop_coin_label = _label("", 10, Color(0.98, 0.86, 0.38), HORIZONTAL_ALIGNMENT_RIGHT)
	shop_coin_label.position = Vector2(420, 10)
	shop_coin_label.size = Vector2(208, 16)
	shop_panel.add_child(shop_coin_label)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 40)
	scroll.size = Vector2(300, 300)
	shop_panel.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shop_list)
	shop_detail_label = _label("Collect some coins - a merchant should turn up nearby.", 10, TEXT_PALE)
	shop_detail_label.position = Vector2(326, 40)
	shop_detail_label.size = Vector2(300, 260)
	shop_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_panel.add_child(shop_detail_label)
	var sell_btn := Button.new()
	sell_btn.text = "Sell held stack"
	sell_btn.position = Vector2(326, 310)
	sell_btn.size = Vector2(150, 28)
	sell_btn.pressed.connect(_on_sell_held_pressed)
	shop_panel.add_child(sell_btn)
	var quest_btn := Button.new()
	quest_btn.text = "Turn in quest"
	quest_btn.position = Vector2(484, 310)
	quest_btn.size = Vector2(144, 28)
	quest_btn.pressed.connect(_on_quest_turn_in_pressed)
	shop_panel.add_child(quest_btn)
	var hint := _label("B to close.", 8, TEXT_DIM)
	hint.position = Vector2(12, 378)
	hint.size = Vector2(616, 12)
	shop_panel.add_child(hint)


func _merchant_npc() -> NpcBase:
	if player == null or player.npc_service == null:
		return null
	for node in get_tree().get_nodes_in_group("npcs"):
		if node is NpcBase:
			var npc := node as NpcBase
			var profile := player.npc_service.profile_for(npc)
			if profile != null and profile.role == "merchant":
				return npc
	return null


func _refresh_shop_panel() -> void:
	if shop_list == null or player == null or player.get("inventory") == null or player.npc_service == null:
		return
	for child in shop_list.get_children():
		child.queue_free()
	var coins := player.inventory.count(&"coin")
	if shop_coin_label != null:
		shop_coin_label.text = "Coins: %d" % coins
	var merchant := _merchant_npc()
	if merchant == null:
		shop_detail_label.text = "No merchant has arrived yet. Collect some coins - they should turn up nearby."
		return
	if not player.npc_service.is_resident(merchant):
		shop_detail_label.text = "%s is nearby but hasn't moved in yet. Build a sealed, lit room with a door, a chair and a workbench, then stay close while it finishes." % merchant.display_name
		return
	for raw_id in merchant.shop_items:
		var item_id := StringName(raw_id)
		var cost := player.npc_service.price(item_id)
		var btn := Button.new()
		btn.text = "%s  -  %d coin%s" % [_item_name(item_id), cost, "" if cost == 1 else "s"]
		btn.modulate = Color(1.0, 0.95, 0.80) if coins >= cost else Color(0.6, 0.62, 0.68)
		btn.pressed.connect(func(): _on_buy_pressed(item_id))
		shop_list.add_child(btn)
	var lines: Array[String] = ["%s has moved in." % merchant.display_name, ""]
	var quest := player.npc_service.available_quest(merchant)
	if quest != null:
		lines.append("QUEST - %s" % quest.display_name)
		for key in quest.required_items.keys():
			var iid := StringName(String(key))
			var need := int(quest.required_items[key])
			var have := player.inventory.count(iid)
			lines.append("  %s  %d/%d" % [_item_name(iid), mini(have, need), need])
		lines.append("")
		lines.append("Ready to turn in!" if player.npc_service.can_complete(merchant) else "Bring the rest, then press Turn in quest.")
	else:
		lines.append("No quest offered right now.")
	shop_detail_label.text = "\n".join(lines)


func _on_buy_pressed(item_id: StringName) -> void:
	var merchant := _merchant_npc()
	if merchant == null or player == null or player.npc_service == null:
		return
	if player.npc_service.buy(merchant, item_id):
		_show_toast("Bought %s." % _item_name(item_id))
	else:
		_show_toast("Not enough coins.")
	_refresh_shop_panel()


func _on_sell_held_pressed() -> void:
	var merchant := _merchant_npc()
	if merchant == null or player == null or player.npc_service == null or not player.npc_service.is_resident(merchant):
		_show_toast("No merchant to sell to.")
		return
	var stack: Dictionary = player.inventory.get_slot("hotbar", int(player.inventory.selected))
	var id := StringName(stack.get("id", &""))
	var amount := int(stack.get("amount", 0))
	if id == &"" or amount <= 0:
		_show_toast("Nothing selected to sell.")
		return
	if player.npc_service.sell(id, amount):
		_show_toast("Sold %d %s." % [amount, _item_name(id)])
	else:
		_show_toast("Could not sell that.")
	_refresh_shop_panel()


func _on_quest_turn_in_pressed() -> void:
	var merchant := _merchant_npc()
	if merchant == null or player == null or player.npc_service == null:
		return
	if player.npc_service.complete_quest(merchant):
		_show_toast("Quest complete!")
	else:
		_show_toast("Can't turn that in yet.")
	_refresh_shop_panel()


func _toggle_shop() -> void:
	shop_visible = not shop_visible
	if shop_panel != null:
		shop_panel.visible = shop_visible
	if shop_visible:
		inventory_visible = false
		crafting_visible = false
		guide_visible = false
		if inventory_panel != null:
			inventory_panel.visible = false
		if crafting_panel != null:
			crafting_panel.visible = false
		if guide_panel != null:
			guide_panel.visible = false
		_refresh_shop_panel()
		_set_mouse_captured(false)
	else:
		_set_mouse_captured(true)


## Terraria-style item tooltip: name, stack, category/rarity, the numbers that
## matter for the item's type, then its flavour description.
func _tooltip_for(def: ItemDef, id: StringName, amount: int) -> String:
	var category_names := ["Material", "Tool", "Weapon", "Armor", "Consumable", "Block", "Quest", "Accessory"]
	var name := String(id)
	if def != null and def.display_name != "":
		name = def.display_name
	var lines: Array[String] = [name]
	if amount > 1:
		lines.append("x%d" % amount)
	if def != null:
		var header: String = category_names[clampi(int(def.category), 0, category_names.size() - 1)]
		if def.rarity > 0:
			header += "   ·   rarity %d" % (def.rarity + 1)
		lines.append(header)
		if def.is_tool:
			lines.append("%s tool · %s tier · power %.1f" % [def.tool_type.capitalize(), def.tier_name(), def.mining_power])
		if def.is_weapon and def.attack != null:
			lines.append("%s damage %.0f · range %.1f" % [String(def.attack.kind).capitalize(), def.attack.damage, def.attack.range])
		if def.armor > 0:
			lines.append("Armor %d" % def.armor)
		if def.defense_bonus > 0:
			lines.append("Defense +%d" % def.defense_bonus)
		if def.mining_speed_bonus > 0.0:
			lines.append("Mining speed +%.0f%%" % (def.mining_speed_bonus * 100.0))
		if def.move_speed_bonus > 0.0:
			lines.append("Move speed +%.0f%%" % (def.move_speed_bonus * 100.0))
		if def.max_health_bonus > 0.0:
			lines.append("Max health +%.0f" % def.max_health_bonus)
		if def.is_consumable and def.heal_amount > 0.0:
			lines.append("Restores %.0f health" % def.heal_amount)
		if def.is_consumable and def.mana_restore > 0.0:
			lines.append("Restores %.0f mana" % def.mana_restore)
		if def.description != "":
			lines.append("")
			lines.append(def.description)
		if def.value > 0:
			lines.append("")
			lines.append("Value %d" % def.value)
	return "\n".join(lines)


func _build_tooltip() -> void:
	tooltip_label = _label("", 9, TEXT_PALE)
	tooltip_label.name = "Tooltip"
	tooltip_label.position = Vector2(0, 0)
	tooltip_label.size = Vector2(260, 60)
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.visible = false
	add_child(tooltip_label)

func _inv_stack(area: String, index: int) -> Dictionary:
	if player == null or player.get("inventory") == null:
		return {}
	var inv = player.inventory
	return inv.get_slot(area, index)

func _refresh_inventory_panel(_arg: Variant = null) -> void:
	if player == null or player.get("inventory") == null:
		return
	var inv = player.inventory
	for entry in inv_slot_panels:
		var area: String = entry["area"]
		var idx: int = entry["index"]
		var stack: Dictionary = inv.get_slot(area, idx)
		var id := StringName(stack.get("id", &""))
		var amount := int(stack.get("amount", 0))
		var cnt: Label = entry.get("count")
		var p: Panel = entry["panel"]
		var icon: TextureRect = entry.get("icon")
		if id == &"" or amount <= 0:
			if cnt != null:
				cnt.text = ""
			if icon != null:
				icon.texture = null
			p.modulate.a = 0.55
			p.tooltip_text = ""
		else:
			if icon != null:
				icon.texture = ItemIcons.icon_for(id)
			if cnt != null:
				cnt.text = "%d" % amount if amount > 1 else ""
			p.modulate.a = 1.0
			p.tooltip_text = _item_name(id)
		# Terraria highlights the selected hotbar slot even inside the inventory.
		var is_sel := (area == "hotbar" and int(inv.selected) == idx)
		var style := p.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = SLOT_SELECTED if is_sel else SLOT_BORDER
			var width := 2 if is_sel else 1
			style.border_width_left = width
			style.border_width_top = width
			style.border_width_right = width
			style.border_width_bottom = width
	for slot in equip_slot_panels.keys():
		var e: Dictionary = equip_slot_panels[slot]
		var p: Panel = e["panel"]
		var label: Label = e.get("label")
		var icon: TextureRect = e.get("icon")
		var stack: Dictionary = inv.equipment.get(slot, {})
		var id := StringName(stack.get("id", &""))
		var amount := int(stack.get("amount", 0))
		if id == &"" or amount <= 0:
			if icon != null:
				icon.texture = null
			p.modulate.a = 0.55
			p.tooltip_text = ""
		else:
			if icon != null:
				icon.texture = ItemIcons.icon_for(id)
			p.modulate.a = 1.0
			p.tooltip_text = _item_name(id)
			# Legacy label kept null-safe; armour slots are icon-only in Terraria.
			if label != null:
				label.text = _item_name(id).substr(0, 7)


## The recipe list shared by the C panel (select, then Craft) and the expanded
## inventory (Terraria crafts on click).
func _fill_recipe_list(container: VBoxContainer, craft_on_click: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	if player == null or player.get("crafting") == null:
		return
	var cs = player.crafting
	for recipe in cs.all_recipes():
		var btn := Button.new()
		var can := cs.can_craft(recipe)
		btn.text = "%s%s" % [recipe.display_name, "" if can else "  ·  " + _craft_suffix(cs.reason(recipe))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = not can
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 11)
		if craft_on_click:
			btn.pressed.connect(func(): _craft_recipe_now(recipe))
		else:
			btn.pressed.connect(func(): _select_recipe(recipe))
		container.add_child(btn)


func _refresh_inv_craft_list() -> void:
	if inv_craft_list == null:
		return
	_fill_recipe_list(inv_craft_list, true)


## Terraria crafting lists fire the recipe directly when clicked.
func _craft_recipe_now(recipe: CraftingRecipe) -> void:
	if player == null or player.get("crafting") == null:
		return
	var cs = player.crafting
	if cs.craft(recipe):
		_show_toast("Crafted %s" % recipe.display_name)
		_refresh_inventory_panel()
		_refresh_inv_craft_list()
	else:
		_show_toast(cs.reason(recipe))


func _on_inv_slot_input(area: String, index: int, ev: InputEvent, _p: Panel) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):		if ev is InputEventMouseMotion:
			var stack := _inv_stack(area, index)
			var id := StringName(stack.get("id", &""))
			if id != &"":
				var def := ItemDatabase.get_item(id)
				tooltip_label.text = _tooltip_for(def, id, int(stack.get("amount", 0)))
				tooltip_label.visible = true
				tooltip_label.position = get_viewport().get_mouse_position() + Vector2(12, 12)
				if inv_hover_label != null:
					inv_hover_label.text = _item_name(id)
			else:
				_hide_tooltip()
			return
	if inv_selected.is_empty():
		inv_selected = {"area": area, "index": index, "slot": ""}
		if area == "equipment":
			var slots := ["head", "chest", "legs", "accessory"]
			if index >= 0 and index < slots.size():
				inv_selected["slot"] = slots[index]
		_show_toast("Selected slot")
	else:
		var a: String = inv_selected["area"]
		var i: int = inv_selected["index"]
		if player != null and player.get("inventory") != null:
			var inv = player.inventory
			if area == "equipment":
				var slots := ["head", "chest", "legs", "accessory"]
				if index >= 0 and index < slots.size():
					inv.equip(slots[index], a, i)
			elif a == "equipment":
				var slots := ["head", "chest", "legs", "accessory"]
				if i >= 0 and i < slots.size():
					inv.unequip(slots[i])
					if area != "equipment":
						# move previously equipped? leave in inventory via unequip returns to main
						pass
			else:
				inv.swap_slots(a, i, area, index)
		inv_selected.clear()
		_refresh_inventory_panel()

## The stations you can actually reach, exactly as CraftingSystem decides it.
func _station_summary() -> String:
	var names := ["workbench", "furnace", "anvil"]
	var found: Array[String] = []
	var cs = player.get("crafting") if player != null else null
	if cs != null:
		for station in names:
			if bool(cs.station_available(station)):
				found.append(station.replace("workbench", "work bench").to_upper())
	if found.is_empty():
		return "NO STATION IN REACH  ·  craft a Work Bench (10 wood), then stand beside it"
	return "STATIONS IN REACH: " + "   ·   ".join(found)


func _refresh_crafting_list() -> void:
	if craft_list == null or player == null or player.get("crafting") == null:
		return
	if craft_station_label != null:
		craft_station_label.text = _station_summary()
	_fill_recipe_list(craft_list, false)


## Compact failure tags so a list row never clips its own reason.
func _craft_suffix(reason: String) -> String:
	if reason.begins_with("STATION REQUIRED:"):
		var station := reason.substr(17).strip_edges().to_lower()
		if station == "workbench":
			return "needs bench"
		return "needs " + station
	match reason:
		"MISSING INGREDIENTS":
			return "no materials"
		"LOCKED":
			return "locked"
	return reason.to_lower()


func _select_recipe(r: CraftingRecipe) -> void:
	selected_recipe = r
	if craft_detail_label == null:
		return
	if player == null or player.get("crafting") == null:
		return
	var cs = player.crafting
	var lines: Array[String] = [r.display_name, ""]
	if r.description != "":
		lines.append(r.description)
	lines.append("Station: " + (r.station if r.station != "none" else "hand"))
	lines.append("Ingredients:")
	for k in r.ingredients.keys():
		var have := 0
		if player.get("inventory") != null:
			have = player.inventory.count(StringName(k))
		lines.append("  %s: %d/%d" % [String(k), have, int(r.ingredients[k])])
	lines.append("Output: %s x%d" % [String(r.output_id()), r.output_amount()])
	lines.append("Status: " + cs.reason(r))
	craft_detail_label.text = "\n".join(lines)

func _on_craft_pressed() -> void:
	if selected_recipe == null or player == null or player.get("crafting") == null:
		return
	var cs = player.crafting
	if cs.craft(selected_recipe):
		_show_toast("Crafted %s" % selected_recipe.display_name)
		_refresh_inventory_panel()
		_refresh_crafting_list()
		_select_recipe(selected_recipe)
	else:
		_show_toast(cs.reason(selected_recipe))

## --- Chests ----------------------------------------------------------------
## Terraria chests are shared world containers: the panel shows the chest's 20
## slots beside the player's inventory, and a click moves the whole stack one
## way. Stacks that do not fit stay where they were, so nothing is ever lost.

func _build_chest_panel() -> void:
	chest_panel = _panel(Rect2(140, 80, 660, 440), _style(PANEL_BG, PANEL_BORDER, 2, 4))
	chest_panel.name = "ChestPanel"
	chest_panel.visible = false
	var title := _label("CHEST", 13, Color(0.98, 0.86, 0.52))
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	chest_panel.add_child(title)
	var hint := _label("Click a stack to move it between the chest and your bag.", 9, TEXT_DIM)
	hint.position = Vector2(12, 26)
	hint.size = Vector2(400, 12)
	chest_panel.add_child(hint)
	for i in range(ContainerStore.SLOTS):
		var col := i % 5
		var row := i / 5
		var p := Panel.new()
		p.position = Vector2(12 + col * 44, 44 + row * 44)
		p.size = Vector2(40, 40)
		p.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_chest_slot_input(i, ev))
		chest_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(3, 3)
		picon.size = Vector2(34, 34)
		picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(2, 28)
		pcnt.size = Vector2(36, 10)
		p.add_child(pcnt)
		chest_slots.append({"panel": p, "count": pcnt, "icon": picon})
	var bag_title := _label("YOUR INVENTORY", 10, Color(0.98, 0.86, 0.52))
	bag_title.position = Vector2(250, 44)
	bag_title.size = Vector2(200, 14)
	chest_panel.add_child(bag_title)
	for i in range(InventoryModel.MAIN_SIZE):
		var col := i % 8
		var row := i / 8
		var p := Panel.new()
		p.position = Vector2(250 + col * 44, 62 + row * 44)
		p.size = Vector2(40, 40)
		p.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_chest_inv_slot_input("main", i, ev))
		chest_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(3, 3)
		picon.size = Vector2(34, 34)
		picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(2, 28)
		pcnt.size = Vector2(36, 10)
		p.add_child(pcnt)
		chest_inv_slots.append({"panel": p, "count": pcnt, "icon": picon, "area": "main", "index": i})
	var hotbar_title := _label("HOTBAR", 9, TEXT_DIM)
	hotbar_title.position = Vector2(250, 288)
	hotbar_title.size = Vector2(100, 12)
	chest_panel.add_child(hotbar_title)
	for i in range(InventoryModel.HOTBAR_SIZE):
		var p := Panel.new()
		p.position = Vector2(250 + i * 40, 302)
		p.size = Vector2(36, 36)
		p.add_theme_stylebox_override("panel", _style(SLOT_BG, SLOT_BORDER, 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_chest_inv_slot_input("hotbar", i, ev))
		chest_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(2, 2)
		picon.size = Vector2(32, 32)
		picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(1, 24)
		pcnt.size = Vector2(33, 10)
		p.add_child(pcnt)
		chest_inv_slots.append({"panel": p, "count": pcnt, "icon": picon, "area": "hotbar", "index": i})
	var footer := _label("E or ESC closes the chest.", 9, TEXT_DIM)
	footer.position = Vector2(12, 415)
	footer.size = Vector2(400, 12)
	chest_panel.add_child(footer)


func _chest_under_crosshair() -> Vector3i:
	if player == null or world == null or not world.is_generated:
		return Vector3i(-1, -1, -1)
	var from: Vector3 = player.aim_origin()
	var direction: Vector3 = player.aim_direction()
	var hit := MiningSystem.raycast(world, from, direction, 6.0)
	if hit.is_empty():
		return Vector3i(-1, -1, -1)
	var cell: Vector3i = hit["cell"]
	var chest_id: int = int(world.block_ids.get(&"chest", -1))
	if chest_id < 0 or world.get_block_id(cell) != chest_id:
		return Vector3i(-1, -1, -1)
	return cell


func open_chest(cell: Vector3i) -> void:
	if player == null or player.get("containers") == null:
		return
	chest_cell = cell
	chest_visible = true
	if chest_panel != null:
		chest_panel.visible = true
	inventory_visible = false
	crafting_visible = false
	guide_visible = false
	if inventory_panel != null:
		inventory_panel.visible = false
	if crafting_panel != null:
		crafting_panel.visible = false
	if guide_panel != null:
		guide_panel.visible = false
	_refresh_chest_panel()
	_set_mouse_captured(false)


func close_chest() -> void:
	chest_visible = false
	if chest_panel != null:
		chest_panel.visible = false
	chest_cell = Vector3i(-99999, -99999, -99999)
	_set_mouse_captured(true)


func _refresh_chest_panel() -> void:
	if player == null or player.get("containers") == null:
		return
	var store: ContainerStore = player.containers
	var stacks: Array[Dictionary] = store.slots(chest_cell)
	for i in range(chest_slots.size()):
		var entry: Dictionary = chest_slots[i]
		var stack: Dictionary = stacks[i] if i < stacks.size() else {}
		_fill_slot_entry(entry, StringName(stack.get("id", &"")), int(stack.get("amount", 0)))
	for entry in chest_inv_slots:
		var stack: Dictionary = player.inventory.get_slot(entry["area"], entry["index"])
		_fill_slot_entry(entry, StringName(stack.get("id", &"")), int(stack.get("amount", 0)))


func _fill_slot_entry(entry: Dictionary, id: StringName, amount: int) -> void:
	var icon: TextureRect = entry.get("icon")
	var cnt: Label = entry.get("count")
	var p: Panel = entry.get("panel")
	if id == &"" or amount <= 0:
		if icon != null:
			icon.texture = null
		if cnt != null:
			cnt.text = ""
		p.modulate.a = 0.45
		p.tooltip_text = ""
		return
	if icon != null:
		icon.texture = ItemIcons.icon_for(id)
	if cnt != null:
		cnt.text = "%d" % amount if amount > 1 else ""
	p.modulate.a = 1.0
	p.tooltip_text = _item_name(id)


func _on_chest_slot_input(index: int, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if player == null or player.get("containers") == null:
		return
	var store: ContainerStore = player.containers
	var stack: Dictionary = store.slots(chest_cell)[index]
	var id := StringName(stack.get("id", &""))
	var amount := int(stack.get("amount", 0))
	if id == &"" or amount <= 0:
		return
	var taken: Dictionary = store.take(chest_cell, index, amount)
	var left := player.inventory.add_item(StringName(taken.get("id", &"")), int(taken.get("amount", 0)))
	if left > 0:
		store.deposit(chest_cell, StringName(taken.get("id", &"")), left)
	_refresh_chest_panel()
	_refresh_inventory_panel()


func _on_chest_inv_slot_input(area: String, index: int, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if player == null or player.get("containers") == null:
		return
	var stack: Dictionary = player.inventory.get_slot(area, index)
	var id := StringName(stack.get("id", &""))
	var amount := int(stack.get("amount", 0))
	if id == &"" or amount <= 0:
		return
	var store: ContainerStore = player.containers
	var left := store.deposit(chest_cell, id, amount, stack.get("metadata", {}))
	var moved := amount - left
	if moved > 0:
		var remaining := {"id": id, "amount": amount - moved, "metadata": stack.get("metadata", {}).duplicate(true)}
		player.inventory.set_slot(area, index, remaining)
	_refresh_chest_panel()
	_refresh_inventory_panel()


## Housing readout: how close the room around the player is to a valid home.
func set_house_status(text: String, valid: bool) -> void:
	if house_label == null:
		return
	house_label.visible = text != ""
	house_label.text = text
	house_label.add_theme_color_override("font_color", Color(0.42, 0.92, 0.68) if valid else Color(0.96, 0.72, 0.36))


## Opens/closes the Terraria expanded inventory. The world keeps simulating: the
## inventory is an overlay, not a pause screen.
func _toggle_inventory() -> void:
	inventory_visible = not inventory_visible
	if inventory_panel != null:
		inventory_panel.visible = inventory_visible
	# The inventory lays out its own hotbar row, so the corner hotbar hides
	# while it is open instead of being drawn twice.
	if hotbar_panel != null:
		hotbar_panel.visible = not inventory_visible
	if inventory_visible:
		crafting_visible = false
		guide_visible = false
		shop_visible = false
		if crafting_panel != null:
			crafting_panel.visible = false
		if guide_panel != null:
			guide_panel.visible = false
		if shop_panel != null:
			shop_panel.visible = false
		if held_label != null:
			held_label.visible = false
		_refresh_inventory_panel()
		_refresh_inv_craft_list()
		_set_mouse_captured(false)
	else:
		if tooltip_label != null:
			tooltip_label.visible = false
		if held_label != null:
			held_label.visible = true
		_set_mouse_captured(true)


## Closes every overlay panel and gives the mouse back to the camera.
func close_panels() -> void:
	inventory_visible = false
	crafting_visible = false
	guide_visible = false
	shop_visible = false
	if inventory_panel != null: inventory_panel.visible = false
	if crafting_panel != null: crafting_panel.visible = false
	if guide_panel != null: guide_panel.visible = false
	if shop_panel != null: shop_panel.visible = false
	if tooltip_label != null: tooltip_label.visible = false
	if hotbar_panel != null: hotbar_panel.visible = true
	if held_label != null: held_label.visible = true
	_set_mouse_captured(true)


## Terraria names the item you just selected above the hotbar for a moment.
func _update_held(delta: float) -> void:
	if held_label == null:
		return
	held_time = maxf(held_time - delta, 0.0)
	held_label.modulate.a = clampf(held_time / 0.5, 0.0, 1.0)

func _toggle_crafting() -> void:
	crafting_visible = not crafting_visible
	if crafting_panel != null:
		crafting_panel.visible = crafting_visible
	if crafting_visible:
		inventory_visible = false
		shop_visible = false
		if inventory_panel != null:
			inventory_panel.visible = false
		if shop_panel != null:
			shop_panel.visible = false
		_refresh_crafting_list()
		_set_mouse_captured(false)
	else:
		_set_mouse_captured(true)

func _set_mouse_captured(captured: bool) -> void:
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
