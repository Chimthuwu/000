extends CanvasLayer
class_name GameHUD

const PANEL_BG := Color(0.035, 0.055, 0.07, 0.86)
const PANEL_BORDER := Color(0.24, 0.78, 0.70, 0.35)
const TEXT_PALE := Color(0.86, 0.95, 0.91)
const TEXT_DIM := Color(0.55, 0.72, 0.68)
const TEXT_WARN := Color(0.98, 0.82, 0.52)
const ACCENT_PROJECTOR := Color(0.15, 0.90, 1.0)
const ACCENT_LUMEN := Color(0.32, 0.86, 0.68)
const RESERVE_SEGMENTS := 6
# Every refresh rewrites label text, theme overrides and styleboxes, which
# forces a Control re-layout/re-draw. At 10 Hz the readouts still feel live and
# the HUD stops burning main-thread time on frames where nothing changed.
const HUD_REFRESH_SECONDS := 0.1

var player: VoxelPlayer
var caster: Lumencaster
var world: VoxelWorld

var debug_label: Label
var flashlight_label: Label
var loadout_panel: Panel
var accent_bar: ColorRect
var name_label: Label
var mode_label: Label
var build_label: Label
var reserve_label: Label
var reserve_segments: Array[Panel] = []
var reserve_styles: Array[StyleBoxFlat] = []
var cartridge_pips: Array[ColorRect] = []
var health_bar: Panel
var health_fill: Panel
var health_fill_style: StyleBoxFlat
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
var inventory_panel: Panel
var inventory_visible := false
var crafting_panel: Panel
var crafting_visible := false
var inv_selected: Dictionary = {}  # {area, index}
var inv_slot_panels: Array[Dictionary] = []  # {panel, label, count, area, index}
var equip_slot_panels: Dictionary = {}
var craft_list: VBoxContainer
var craft_detail_label: Label
var selected_recipe: CraftingRecipe = null
var tooltip_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := get_parent()
	player = main.get_node_or_null("Player") as VoxelPlayer
	world = main.get_node_or_null("VoxelWorld") as VoxelWorld
	if player != null:
		caster = player.get_node_or_null("Lumencaster") as Lumencaster
	# The Terraria HUD has no projector mode; suppress any leftover gun hint.
	if caster != null:
		caster.hint_time = 0.0
		caster.hint_text = ""
	_build_status()
	_build_biome()
	_build_loadout()
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
	_build_crafting_panel()
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
	_refresh_hotbar()
	_layout_for_viewport()
	_update_loadout()
	# Onboarding: first hint after a short delay
	_show_onboarding(0)


func _process(delta: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(player):
		return
	# The crossing banner fades per frame; the textual/theme work is throttled.
	_update_biome(delta)
	hud_refresh += delta
	if hud_refresh < HUD_REFRESH_SECONDS:
		return
	hud_refresh = 0.0
	_update_loadout()
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


func _build_loadout() -> void:
	loadout_panel = _panel(Rect2(16, 388, 252, 78), _style(Color(0.018, 0.028, 0.032, 0.94), Color(0.38, 0.68, 0.60, 0.50), 1, 2))
	loadout_panel.name = "LoadoutPanel"

	accent_bar = ColorRect.new()
	accent_bar.color = Color(0.25, 1.0, 0.78)
	accent_bar.position = Vector2(0, 0)
	accent_bar.size = Vector2(3, 78)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loadout_panel.add_child(accent_bar)

	name_label = _label("EXCAVATOR ROUND", 13, TEXT_PALE)
	name_label.name = "LumenReadout"
	name_label.position = Vector2(30, 393)
	name_label.size = Vector2(226, 18)
	add_child(name_label)

	mode_label = _label("LUMENCASTER", 9, TEXT_DIM)
	mode_label.position = Vector2(30, 412)
	mode_label.size = Vector2(226, 12)
	add_child(mode_label)

	for index in range(4):
		var pip := ColorRect.new()
		pip.position = Vector2(30 + index * 18, 430)
		pip.size = Vector2(14, 4)
		pip.color = Color(1, 1, 1, 0.25)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pip)
		cartridge_pips.append(pip)

	var reserve_caption := _label("LUMEN", 9, TEXT_DIM)
	reserve_caption.name = "LegacyLumenCaption"
	reserve_caption.position = Vector2(30, 442)
	reserve_caption.size = Vector2(40, 12)
	add_child(reserve_caption)

	for index in range(RESERVE_SEGMENTS):
		var segment_style := _style(Color(0.05, 0.10, 0.09, 1.0), Color(0.14, 0.24, 0.22, 0.9), 1, 1)
		segment_style.content_margin_left = 0.0
		segment_style.content_margin_right = 0.0
		segment_style.content_margin_top = 0.0
		segment_style.content_margin_bottom = 0.0
		var segment := Panel.new()
		segment.position = Vector2(74 + index * 14, 443)
		segment.size = Vector2(11, 7)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.add_theme_stylebox_override("panel", segment_style)
		add_child(segment)
		reserve_segments.append(segment)
		reserve_styles.append(segment_style)

	reserve_label = _label("100", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	reserve_label.position = Vector2(166, 440)
	reserve_label.size = Vector2(88, 12)
	add_child(reserve_label)

	build_label = _label("BUILD  ASHEN SOIL ×0   DEPTH 1", 9, TEXT_DIM)
	build_label.position = Vector2(30, 454)
	build_label.size = Vector2(226, 12)
	add_child(build_label)


func _build_health() -> void:
	var caption := _label("VITALS", 8, TEXT_DIM)
	caption.name = "LegacyVitalsCaption"
	caption.position = Vector2(16, 360)
	caption.size = Vector2(80, 10)
	add_child(caption)

	var value := _label("100", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "HealthValue"
	value.position = Vector2(188, 360)
	value.size = Vector2(80, 10)
	add_child(value)

	health_bar = Panel.new()
	health_bar.position = Vector2(16, 373)
	health_bar.size = Vector2(252, 9)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_theme_stylebox_override("panel", _style(Color(0.02, 0.035, 0.04, 0.95), Color(0.18, 0.30, 0.28, 0.9), 1, 2))
	add_child(health_bar)

	health_fill_style = _style(Color(0.32, 0.86, 0.58, 0.95), Color(0.70, 1.0, 0.86, 0.8), 1, 1)
	health_fill_style.shadow_color = Color(0.2, 0.9, 0.6, 0.45)
	health_fill_style.shadow_size = 4
	health_fill = Panel.new()
	health_fill.position = Vector2(17, 374)
	health_fill.size = Vector2(250, 7)
	health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_fill.add_theme_stylebox_override("panel", health_fill_style)
	add_child(health_fill)

	for index in range(1, 4):
		var tick := ColorRect.new()
		tick.position = Vector2(16 + 63 * index, 373)
		tick.size = Vector2(1, 9)
		tick.color = Color(0.01, 0.02, 0.02, 0.85)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tick)


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
	var gloom := world.get_gloom_level(cell)
	if lit >= 0.35 and gloom < 0.6:
		environment_label.text = "SHELTERED"
		environment_label.add_theme_color_override("font_color", Color(0.42, 0.92, 0.68))
	elif gloom >= 0.6:
		environment_label.text = "GLOOM RISING"
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
	button.add_theme_stylebox_override("pressed", _style(Color(0.06, 0.15, 0.14, 1.0), ACCENT_PROJECTOR, 1, 3))
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
	var footer := _label("E  Continue    ESC  Close", 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	footer.position = Vector2(210, 398)
	footer.size = Vector2(434, 12)
	add_child(footer)


func open_dialogue(npc: NpcBase) -> void:
	active_npc = npc
	dialogue_open = true
	dialogue_panel.visible = true
	if npc != null:
		dialogue_name.text = npc.npc_name.to_upper()
		dialogue_text.text = npc.get_dialogue_line()
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
	# the cell centre for break feedback. Placement is handled by the projector.
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
		"Hold LMB with a pickaxe to mine  ·  blocks drop into your inventory",
		"RMB places a block  ·  B opens inventory  ·  C opens crafting  ·  ESC pauses",
	]
	if step < lines.size() and not onboarding_done[step]:
		show_world_hint(lines[step], 5.0)


# --- Live updates -----------------------------------------------------------

func _update_loadout() -> void:
	var cartridge: CartridgeDef = caster.CARTRIDGES[caster.selected_cartridge]
	var accent := ACCENT_PROJECTOR if caster.projector_mode else cartridge.accent_color
	name_label.text = cartridge.display_name
	mode_label.text = "PROJECTOR MODE" if caster.projector_mode else "LUMENCASTER"
	mode_label.add_theme_color_override("font_color", accent)
	accent_bar.color = accent

	for index in range(cartridge_pips.size()):
		var pip: ColorRect = cartridge_pips[index]
		var pip_color: Color = caster.CARTRIDGES[index].accent_color
		var selected := index == caster.selected_cartridge and not caster.projector_mode
		pip.color = Color(pip_color.r, pip_color.g, pip_color.b, 1.0 if selected else 0.28)
		pip.size = Vector2(14, 6) if selected else Vector2(14, 3)
		pip.position.y = 429 if selected else 431

	var ratio := clampf(caster.reserve / caster.CONFIG.reserve_capacity, 0.0, 1.0)
	var lit := 0 if ratio <= 0.001 else ceili(ratio * float(RESERVE_SEGMENTS))
	for index in range(reserve_segments.size()):
		var style := reserve_styles[index]
		var on := index < lit
		style.bg_color = Color(0.20, 0.98, 0.74, 0.95) if on else Color(0.04, 0.08, 0.07, 1.0)
		style.border_color = Color(0.75, 1.0, 0.92, 0.85) if on else Color(0.12, 0.21, 0.19, 0.9)
		style.shadow_color = Color(0.16, 0.95, 0.68, 0.55 if on else 0.0)
		style.shadow_size = 3 if on else 0
	reserve_label.text = "%d" % roundi(caster.reserve)
	reserve_label.add_theme_color_override("font_color", TEXT_WARN if ratio < 0.2 else TEXT_DIM)

	var stock := int(caster.inventory.get(caster.selected_projector_block, 0))
	var block_name := String(caster.selected_projector_block).replace("_", " ").to_upper()
	build_label.text = "BUILD  %s ×%d    DEPTH %d" % [block_name, stock, caster.extrusion_depth]
	build_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45) if stock <= 0 else TEXT_DIM)


func _update_flashlight() -> void:
	var on := is_instance_valid(world) and world.flashlight_enabled
	flashlight_label.text = "TORCH  ON" if on else "TORCH  OFF"
	flashlight_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.78) if on else Color(0.42, 0.48, 0.48))


const BIOME_ACCENTS := [
	Color(0.86, 0.72, 0.45), # Ashen Flats
	Color(0.55, 0.80, 0.62), # Hushwoods
	Color(0.62, 0.85, 1.00), # Frostfall
	Color(0.60, 0.80, 0.35), # The Mire
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
	var ratio := clampf(player.health / 100.0, 0.0, 1.0)
	health_fill.size.x = 250.0 * ratio
	health_fill.visible = ratio > 0.001
	if ratio < 0.35:
		health_fill_style.bg_color = Color(0.88, 0.32, 0.24, 0.95)
		health_fill_style.border_color = Color(1.0, 0.70, 0.55, 0.85)
		health_fill_style.shadow_color = Color(1.0, 0.28, 0.15, 0.45)
	else:
		health_fill_style.bg_color = Color(0.32, 0.86, 0.58, 0.95)
		health_fill_style.border_color = Color(0.70, 1.0, 0.86, 0.8)
		health_fill_style.shadow_color = Color(0.2, 0.9, 0.6, 0.45)
	var value := get_node_or_null("HealthValue") as Label
	if value != null:
		value.text = "%d" % roundi(player.health)
		value.add_theme_color_override("font_color", Color(0.90, 0.45, 0.38) if ratio < 0.35 else TEXT_DIM)


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
	# NPC interaction: E near an NPC opens dialogue instead of the player's build action.
	if (not dialogue_open) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var npc := _nearest_npc()
		if npc != null:
			open_dialogue(npc)
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
		# close panels on ESC
		if (inventory_visible or crafting_visible) and event.keycode == KEY_ESCAPE:
			inventory_visible = false
			crafting_visible = false
			if inventory_panel != null: inventory_panel.visible = false
			if crafting_panel != null: crafting_panel.visible = false
			_set_mouse_captured(true)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if paused:
		resume_game()
	elif is_instance_valid(caster) and (caster.dragging or caster.projector_mode):
		return
	else:
		pause_game()
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
## elements for the real 1280x720 root viewport and retire the Lumencaster UI.
func _layout_for_viewport() -> void:
	# The HUD is authored against the project's 1280x720 render viewport. Using
	# get_viewport().size here returned the 1920x1080 window override, which put
	# the hotbar and vitals off-screen. The stretch mode scales this layout.
	var vp := Vector2(1280.0, 720.0)
	var cx: float = vp.x * 0.5

	# Retire every legacy gun/cartridge/reserve element. Gameplay no longer
	# uses them; they are kept only so _update_loadout() stays valid.
	if loadout_panel != null:
		loadout_panel.visible = false
	if name_label != null:
		name_label.visible = false
	if mode_label != null:
		mode_label.visible = false
	if build_label != null:
		build_label.visible = false
	if reserve_label != null:
		reserve_label.visible = false
	for segment in reserve_segments:
		segment.visible = false
	for pip in cartridge_pips:
		pip.visible = false
	# These captions were added straight to the CanvasLayer, not to the panels
	# above, so hiding the panels alone left stray text on the screen edge.
	for legacy_name in ["LegacyLumenCaption", "LegacyVitalsCaption", "HealthValue"]:
		var legacy_node := get_node_or_null(NodePath(legacy_name))
		if legacy_node != null:
			legacy_node.visible = false
	if flashlight_label != null:
		flashlight_label.position = Vector2(vp.x - 254.0, 8.0)

	# Centred crosshair.
	var crosshair := get_node_or_null("Crosshair") as Control
	if crosshair != null:
		crosshair.position = Vector2(cx - 6.0, vp.y * 0.5 - 6.0)

	# Hotbar: bottom centre, above the screen edge.
	if hotbar_panel != null:
		hotbar_panel.position = Vector2(cx - 213.0, vp.y - 58.0)

	# Health and mana: bottom left.
	if health_bar != null:
		health_bar.position = Vector2(16.0, vp.y - 96.0)
	if health_fill != null:
		health_fill.position = Vector2(17.0, vp.y - 95.0)
	var health_value := get_node_or_null("HealthValue") as Label
	if health_value != null:
		health_value.position = Vector2(188.0, vp.y - 109.0)
	if mana_bar != null:
		mana_bar.position = Vector2(16.0, vp.y - 82.0)
	if mana_fill != null:
		mana_fill.position = Vector2(17.0, vp.y - 81.0)
	if mana_label != null:
		mana_label.position = Vector2(188.0, vp.y - 95.0)

	# Transient text.
	if status_label != null:
		status_label.position = Vector2(cx - 300.0, vp.y - 118.0)
	if world_hint_label != null:
		world_hint_label.position = Vector2(cx - 300.0, 70.0)
	if interaction_label != null:
		interaction_label.position = Vector2(cx - 177.0, vp.y - 132.0)
	if notification_label != null:
		notification_label.position = Vector2(cx - 300.0, 120.0)
	if target_label != null:
		target_label.position = Vector2(cx - 200.0, vp.y * 0.5 - 90.0)
	if layer_label != null:
		layer_label.position = Vector2(cx - 200.0, vp.y * 0.5 - 74.0)
	if boss_panel != null:
		boss_panel.position = Vector2(cx - 177.0, 12.0)
	if biome_label != null:
		biome_label.position = Vector2(vp.x - 254.0, 26.0)
	if biome_intro_label != null:
		biome_intro_label.position = Vector2(cx - 300.0, 96.0)


# --- Agent 3: hotbar ---------------------------------------------------------

func _build_hotbar() -> void:
	hotbar_panel = _panel(Rect2(214, 420, 426, 44), _style(Color(0.02, 0.03, 0.04, 0.88), PANEL_BORDER, 1, 4))
	hotbar_panel.name = "HotbarPanel"
	hotbar_slots.clear()
	hotbar_labels.clear()
	hotbar_counts.clear()
	for i in range(10):
		var slot := Panel.new()
		slot.position = Vector2(6 + i * 42, 6)
		slot.size = Vector2(36, 32)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _style(Color(0.06, 0.09, 0.10, 0.95), Color(0.22, 0.40, 0.38, 0.7), 1, 2))
		hotbar_panel.add_child(slot)
		hotbar_slots.append(slot)
		var icon := TextureRect.new()
		icon.position = Vector2(10, 1)
		icon.size = Vector2(16, 16)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		hotbar_icons.append(icon)
		var lbl := _label("", 7, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
		lbl.position = Vector2(0, 17)
		lbl.size = Vector2(36, 8)
		slot.add_child(lbl)
		hotbar_labels.append(lbl)
		var cnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		cnt.position = Vector2(2, 22)
		cnt.size = Vector2(32, 9)
		slot.add_child(cnt)
		hotbar_counts.append(cnt)

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
		# Selected highlight
		var selected := int(inv.selected) == i
		var style := slot_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = ACCENT_PROJECTOR if selected else Color(0.22, 0.40, 0.38, 0.7)
			style.border_width_left = 2 if selected else 1
			style.border_width_top = 2 if selected else 1
			style.border_width_right = 2 if selected else 1
			style.border_width_bottom = 2 if selected else 1


# --- Agent 3: mana -----------------------------------------------------------

func _build_mana() -> void:
	var caption := _label("MANA", 8, TEXT_DIM)
	caption.position = Vector2(16, 348)
	caption.size = Vector2(80, 10)
	add_child(caption)
	mana_bar = Panel.new()
	mana_bar.position = Vector2(16, 358)
	mana_bar.size = Vector2(252, 7)
	mana_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mana_bar.add_theme_stylebox_override("panel", _style(Color(0.02, 0.035, 0.04, 0.95), Color(0.18, 0.30, 0.40, 0.9), 1, 2))
	add_child(mana_bar)
	mana_fill_style = _style(Color(0.30, 0.55, 0.95, 0.95), Color(0.60, 0.80, 1.0, 0.8), 1, 1)
	mana_fill = Panel.new()
	mana_fill.position = Vector2(17, 359)
	mana_fill.size = Vector2(250, 5)
	mana_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mana_fill.add_theme_stylebox_override("panel", mana_fill_style)
	add_child(mana_fill)
	mana_label = _label("100", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	mana_label.position = Vector2(188, 348)
	mana_label.size = Vector2(80, 10)
	add_child(mana_label)

func _update_mana() -> void:
	if not is_instance_valid(player) or player.get("weapons") == null:
		return
	var w = player.weapons
	var ratio := 0.0
	if w.max_mana > 0.0:
		ratio = clampf(w.mana / w.max_mana, 0.0, 1.0)
	if mana_fill != null:
		mana_fill.size.x = 250.0 * ratio
	mana_label.text = "%d" % roundi(w.mana)

func _on_mana_changed(current: float, maximum: float) -> void:
	if mana_label != null:
		mana_label.text = "%d" % roundi(current)


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
	boss_name_label.position = Vector2(260, 16)
	boss_name_label.size = Vector2(334, 16)
	add_child(boss_name_label)
	var bar_bg := _style(Color(0.02, 0.02, 0.03, 0.95), Color(0.4, 0.12, 0.10, 0.8), 1, 2)
	boss_bg_panel = _panel(Rect2(260, 36, 334, 12), bar_bg)
	boss_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bg_panel.visible = false
	boss_health_style = _style(Color(0.88, 0.24, 0.18, 0.95), Color(1.0, 0.5, 0.4, 0.8), 1, 1)
	boss_health_fill = Panel.new()
	boss_health_fill.position = Vector2(261, 37)
	boss_health_fill.size = Vector2(332, 10)
	boss_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_health_fill.add_theme_stylebox_override("panel", boss_health_style)
	add_child(boss_health_fill)

func _update_boss() -> void:
	if boss_panel == null:
		return
	if boss_target == null or not is_instance_valid(boss_target):
		boss_target = null
		for node in get_tree().get_nodes_in_group("bosses"):
			boss_target = node
			break
		if boss_target == null:
			for node in get_tree().get_nodes_in_group("enemies"):
				if node.get("max_health") != null and float(node.get("max_health")) >= 100.0:
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
	inventory_panel = _panel(Rect2(120, 90, 640, 400), _style(Color(0.02, 0.03, 0.04, 0.94), PANEL_BORDER, 1, 6))
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	# _panel() already added this node.
	var title := _label("INVENTORY", 13, ACCENT_LUMEN)
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	inventory_panel.add_child(title)
	var eq_x := 12
	var eq_y := 40
	for slot in ["head", "chest", "legs", "accessory"]:
		var lbl := _label(slot.to_upper(), 9, TEXT_DIM)
		lbl.position = Vector2(eq_x, eq_y)
		lbl.size = Vector2(90, 12)
		inventory_panel.add_child(lbl)
		var p := Panel.new()
		p.position = Vector2(eq_x, eq_y + 14)
		p.size = Vector2(84, 36)
		p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.09, 0.10, 0.95), Color(0.22, 0.40, 0.38, 0.7), 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_inv_slot_input("equipment", InventoryModel.EQUIPMENT_SLOTS.find(slot), ev, p))
		inventory_panel.add_child(p)
		var plbl := _label("", 9, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
		plbl.position = Vector2(2, 4)
		plbl.size = Vector2(80, 16)
		p.add_child(plbl)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(2, 22)
		pcnt.size = Vector2(80, 10)
		p.add_child(pcnt)
		equip_slot_panels[slot] = {"panel": p, "label": plbl, "count": pcnt, "slot": slot}
		eq_y += 60
	var grid_x := 110
	var grid_y := 40
	var grid_cols := 8
	for i in range(InventoryModel.MAIN_SIZE):
		var col := i % grid_cols
		var row := i / grid_cols
		var p := Panel.new()
		p.position = Vector2(grid_x + col * 44, grid_y + row * 44)
		p.size = Vector2(40, 40)
		p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.09, 0.10, 0.95), Color(0.22, 0.40, 0.38, 0.7), 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_inv_slot_input("main", i, ev, p))
		inventory_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(9, 2)
		picon.size = Vector2(22, 22)
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		var plbl := _label("", 8, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
		plbl.position = Vector2(2, 24)
		plbl.size = Vector2(36, 10)
		p.add_child(plbl)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(2, 28)
		pcnt.size = Vector2(36, 10)
		p.add_child(pcnt)
		inv_slot_panels.append({"panel": p, "label": plbl, "count": pcnt, "icon": picon, "area": "main", "index": i})
	var hb_y := grid_y + (InventoryModel.MAIN_SIZE / grid_cols + 1) * 44
	var hb_title := _label("HOTBAR", 9, TEXT_DIM)
	hb_title.position = Vector2(grid_x, hb_y - 12)
	hb_title.size = Vector2(100, 12)
	inventory_panel.add_child(hb_title)
	for i in range(InventoryModel.HOTBAR_SIZE):
		var p := Panel.new()
		p.position = Vector2(grid_x + i * 44, hb_y)
		p.size = Vector2(40, 40)
		p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.09, 0.10, 0.95), Color(0.22, 0.40, 0.38, 0.7), 1, 2))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev): _on_inv_slot_input("hotbar", i, ev, p))
		inventory_panel.add_child(p)
		var picon := TextureRect.new()
		picon.position = Vector2(9, 2)
		picon.size = Vector2(22, 22)
		picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(picon)
		var plbl := _label("", 8, TEXT_PALE, HORIZONTAL_ALIGNMENT_CENTER)
		plbl.position = Vector2(2, 24)
		plbl.size = Vector2(36, 10)
		p.add_child(plbl)
		var pcnt := _label("", 8, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		pcnt.position = Vector2(2, 28)
		pcnt.size = Vector2(36, 10)
		p.add_child(pcnt)
		inv_slot_panels.append({"panel": p, "label": plbl, "count": pcnt, "icon": picon, "area": "hotbar", "index": i})
	var hint := _label("Click two slots to move/swap. I to close.", 8, TEXT_DIM)
	hint.position = Vector2(12, 378)
	hint.size = Vector2(616, 12)
	inventory_panel.add_child(hint)
func _build_crafting_panel() -> void:
	crafting_panel = _panel(Rect2(120, 90, 640, 400), _style(Color(0.02, 0.03, 0.04, 0.94), PANEL_BORDER, 1, 6))
	crafting_panel.name = "CraftingPanel"
	crafting_panel.visible = false
	# _panel() already added this node.
	var title := _label("CRAFTING", 13, ACCENT_LUMEN)
	title.position = Vector2(12, 8)
	title.size = Vector2(200, 18)
	crafting_panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 40)
	scroll.size = Vector2(260, 340)
	crafting_panel.add_child(scroll)
	craft_list = VBoxContainer.new()
	craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(craft_list)
	craft_detail_label = _label("Select a recipe.", 10, TEXT_PALE)
	craft_detail_label.position = Vector2(290, 40)
	craft_detail_label.size = Vector2(330, 300)
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

func _build_tooltip() -> void:
	tooltip_label = _label("", 9, TEXT_PALE)
	tooltip_label.name = "Tooltip"
	tooltip_label.position = Vector2(0, 0)
	tooltip_label.size = Vector2(220, 60)
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
		var lbl: Label = entry["label"]
		var cnt: Label = entry["count"]
		var p: Panel = entry["panel"]
		var icon: TextureRect = entry.get("icon")
		if id == &"" or amount <= 0:
			lbl.text = ""
			cnt.text = ""
			if icon != null:
				icon.texture = null
			p.modulate.a = 0.5
		else:
			var def := ItemDatabase.get_item(id)
			var name := String(id)
			if def != null and def.display_name != "":
				name = def.display_name
			lbl.text = ""
			if icon != null:
				icon.texture = ItemIcons.icon_for(id)
			cnt.text = "%d" % amount if amount > 1 else ""
			p.modulate.a = 1.0
			p.tooltip_text = name
		var is_sel := (area == "hotbar" and int(inv.selected) == idx)
		var style := p.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = ACCENT_PROJECTOR if is_sel else Color(0.22, 0.40, 0.38, 0.7)
	for slot in equip_slot_panels.keys():
		var e: Dictionary = equip_slot_panels[slot]
		var p: Panel = e["panel"]
		var lbl: Label = e["label"]
		var cnt: Label = e["count"]
		var stack: Dictionary = inv.equipment.get(slot, {})
		var id := StringName(stack.get("id", &""))
		var amount := int(stack.get("amount", 0))
		if id == &"" or amount <= 0:
			lbl.text = ""
			cnt.text = ""
			p.modulate.a = 0.5
		else:
			var def := ItemDatabase.get_item(id)
			var name := String(id)
			if def != null and def.display_name != "":
				name = def.display_name
			lbl.text = name.substr(0, 6)
			cnt.text = ""
			p.modulate.a = 1.0

func _on_inv_slot_input(area: String, index: int, ev: InputEvent, _p: Panel) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		if ev is InputEventMouseMotion:
			var stack := _inv_stack(area, index)
			var id := StringName(stack.get("id", &""))
			if id != &"":
				var def := ItemDatabase.get_item(id)
				var name := String(id)
				if def != null and def.display_name != "":
					name = def.display_name
				var desc := ""
				if def != null:
					desc = def.description
				tooltip_label.text = name + ("\n" + desc if desc != "" else "")
				tooltip_label.visible = true
				tooltip_label.position = get_viewport().get_mouse_position() + Vector2(12, 12)
			else:
				tooltip_label.visible = false
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

func _refresh_crafting_list() -> void:
	if craft_list == null or player == null or player.get("crafting") == null:
		return
	for c in craft_list.get_children():
		c.queue_free()
	var cs = player.crafting
	for r in cs.all_recipes():
		var btn := Button.new()
		var can := cs.can_craft(r)
		btn.text = "%s%s" % [r.display_name, "" if can else " (locked)"]
		btn.disabled = not can
		btn.pressed.connect(func(): _select_recipe(r))
		craft_list.add_child(btn)

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

func _toggle_inventory() -> void:
	inventory_visible = not inventory_visible
	if inventory_panel != null:
		inventory_panel.visible = inventory_visible
	if inventory_visible:
		crafting_visible = false
		if crafting_panel != null:
			crafting_panel.visible = false
		_refresh_inventory_panel()
		_refresh_crafting_list()
		_set_mouse_captured(false)
	else:
		_set_mouse_captured(true)

func _toggle_crafting() -> void:
	crafting_visible = not crafting_visible
	if crafting_panel != null:
		crafting_panel.visible = crafting_visible
	if crafting_visible:
		inventory_visible = false
		if inventory_panel != null:
			inventory_panel.visible = false
		_refresh_crafting_list()
		_set_mouse_captured(false)
	else:
		_set_mouse_captured(true)

func _set_mouse_captured(captured: bool) -> void:
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
