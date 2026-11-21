extends CanvasLayer
class_name DevConsole

# Drop-down debug console. Uses _input so it consumes the toggle key, typing
# and Escape before the player, the ArcaneCaster or the pause menu see them.

const LINE_LIMIT := 9

var main: Node
var panel: Panel
var input: LineEdit
var output: RichTextLabel
var open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	main = get_parent()
	_build()
	visible = false


func _build() -> void:
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 300.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.05, 0.94)
	style.border_color = Color(0.2, 0.8, 0.7, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var title := Label.new()
	title.text = "TERRARIA 3D DEV CONSOLE  ·  ~ close"
	title.position = Vector2(12, 6)
	title.size = Vector2(500, 16)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.78))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	output = RichTextLabel.new()
	output.position = Vector2(12, 26)
	output.size = Vector2(824, 230)
	output.bbcode_enabled = false
	output.scroll_active = true
	output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output.add_theme_color_override("default_color", Color(0.78, 0.92, 0.86))
	output.add_theme_font_size_override("normal_font_size", 11)
	panel.add_child(output)

	input = LineEdit.new()
	input.position = Vector2(12, 262)
	input.size = Vector2(824, 28)
	input.placeholder_text = "god | spawn <nightling|hollow|lamp_eater|frost_stalker|bog_crawler> | tp <ashen|hush|frost|mire> | time <0-24> | heal | help"
	input.add_theme_font_size_override("font_size", 11)
	input.text_submitted.connect(_on_text_submitted)
	panel.add_child(input)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == 96 or key.physical_keycode == 96:
		if open:
			close()
		else:
			show_console()
		get_viewport().set_input_as_handled()
		return
	if open and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func show_console() -> void:
	open = true
	visible = true
	main.console_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	input.grab_focus()
	_print_line("> ready", Color(0.4, 0.9, 0.78))


func close() -> void:
	open = false
	visible = false
	main.console_open = false
	input.release_focus()
	if main.hud != null and not main.hud.death_overlay.visible and not main.hud.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _print_line(text: String, color := Color(0.78, 0.92, 0.86)) -> void:
	output.add_text("%s\n" % text)
	while output.get_line_count() > LINE_LIMIT + 1:
		var lines := output.get_text().split("\n")
		output.text = "\n".join(lines.slice(lines.size() - LINE_LIMIT - 1))


func _on_text_submitted(text: String) -> void:
	input.clear()
	var command := text.strip_edges()
	if command.is_empty():
		return
	_print_line("> %s" % command, Color(0.55, 0.95, 0.82))
	_execute(command)


func _execute(command: String) -> void:
	var parts := command.split(" ", false)
	var verb := parts[0].to_lower()
	var arg := parts[1].to_lower() if parts.size() > 1 else ""
	var player: VoxelPlayer = main.player
	var director: EnemyDirector = main.enemy_director
	match verb:
		"god":
			player.god_mode = not player.god_mode
			_print_line("god mode %s" % ("ON" if player.god_mode else "OFF"))
		"heal":
			player.full_heal()
			_print_line("health restored to %d" % int(player.health))
		"spawn":
			if arg.is_empty():
				_print_line("usage: spawn <nightling|hollow|lamp_eater|frost_stalker|bog_crawler>", Color(0.98, 0.72, 0.4))
				return
			var spawned := director.spawn_named(arg)
			_print_line("spawned %s" % arg if spawned else "unknown enemy or unloaded ground: %s" % arg, Color(0.5, 0.9, 0.7) if spawned else Color(0.98, 0.45, 0.4))
		"tp":
			if arg.is_empty():
				_print_line("usage: tp <forest|desert|jungle|corruption|crimson|hallow|snow|ocean|mushroom|ashen|hush>", Color(0.98, 0.72, 0.4))
				return
			var biome := -1
			match arg:
				"ashen": biome = BiomeManager.ASHEN
				"hush": biome = BiomeManager.HUSH
				"frost": biome = BiomeManager.FROST
				"mire": biome = BiomeManager.MIRE
				"desert": biome = BiomeManager.DESERT
				"mushroom": biome = BiomeManager.MUSHROOM
				"forest": biome = BiomeManager.MIRE
				"snow": biome = BiomeManager.FROST
				"jungle": biome = BiomeManager.JUNGLE
				"corruption": biome = BiomeManager.CORRUPTION
				"crimson": biome = BiomeManager.CRIMSON
				"hallow": biome = BiomeManager.HALLOW
				"ocean": biome = BiomeManager.OCEAN
			if biome < 0:
				_print_line("unknown biome: %s" % arg, Color(0.98, 0.45, 0.4))
				return
			var cell := _teleport_to_biome(biome)
			_print_line("teleported to %s at (%d, %d)" % [BiomeManager.biome_name(biome), cell.x, cell.y])
		"hallow":
			# Explicit debug override for the progression-gated biome.
			BiomeManager.set_hallow_enabled(arg != "off")
			_print_line("Hallow generation %s (debug override)" % ("ENABLED" if BiomeManager.hallow_enabled() else "DISABLED"))
		"time":
			if not arg.is_valid_float():
				_print_line("usage: time <0-24>", Color(0.98, 0.72, 0.4))
				return
			main.cycle.set_time_hours(float(arg))
			_print_line("time set to %.1f h (%s)" % [float(arg), main.cycle.phase_name])
		"help", "?":
			_print_line("god | spawn <name> | tp <biome> | hallow <on|off> | time <0-24> | heal | help")
		_:
			_print_line("unknown command: %s" % verb, Color(0.98, 0.45, 0.4))


# The climate anchors of the newer biomes can sit far outside the short
# find_biome_center search, so explore a wider grid before falling back.
func _find_biome_column(biome: int, seed_value: int, from: Vector2i) -> Vector2i:
	BiomeManager.configure(seed_value)
	var best := Vector2i(1 << 30, 1 << 30)
	var best_distance := INF
	for z in range(from.y - 2048, from.y + 2049, 64):
		for x in range(from.x - 2048, from.x + 2049, 64):
			if BiomeManager.surface_biome(x, z) != biome:
				continue
			var distance := Vector2(float(x - from.x), float(z - from.y)).length()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, z)
	return best


func _teleport_to_biome(biome: int) -> Vector2i:
	var player: VoxelPlayer = main.player
	var world: VoxelWorld = main.world
	var from := Vector2i(floori(player.position.x), floori(player.position.z))
	var center := _find_biome_column(biome, world.world_seed, from)
	if center.x == 1 << 30:
		center = BiomeManager.find_biome_center(biome, world.world_seed, from.x, from.y)
	var surface := world.get_surface_height(center.x, center.y)
	world.set_generation_focus(Vector3i(center.x, 0, center.y))
	player.respawn_at(Vector3(float(center.x) + 0.5, float(surface) + 1.05, float(center.y) + 0.5))
	return center
