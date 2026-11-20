extends RefCounted
class_name SettingsStore

const SETTINGS_PATH := "user://settings.cfg"

static var _cache: ConfigFile = null

static func load_settings() -> ConfigFile:
	if _cache != null:
		return _cache
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		# Defaults
		cfg.set_value("audio", "master", 1.0)
		cfg.set_value("audio", "music", 0.8)
		cfg.set_value("audio", "sfx", 0.9)
		cfg.set_value("audio", "ui", 0.85)
		cfg.set_value("audio", "ambient", 0.7)
		cfg.set_value("input", "mouse_sensitivity", 1.0)
		cfg.set_value("display", "fullscreen", false)
		cfg.set_value("display", "ui_scale", 1.0)
		cfg.set_value("game", "last_world_seed", 139732)
		cfg.set_value("game", "continue_on_boot", false)
	apply(cfg)
	return cfg

static func get_cfg() -> ConfigFile:
	if _cache == null:
		_cache = load_settings()
	return _cache

static func save(cfg: ConfigFile) -> void:
	cfg.save(SETTINGS_PATH)
	_cache = cfg
	apply(cfg)

static func apply(cfg: ConfigFile) -> void:
	# Audio buses
	_set_bus_volume("Master", float(cfg.get_value("audio", "master", 1.0)))
	_set_bus_volume("Music", float(cfg.get_value("audio", "music", 0.8)))
	_set_bus_volume("SFX", float(cfg.get_value("audio", "sfx", 0.9)))
	_set_bus_volume("World", float(cfg.get_value("audio", "ambient", 0.7)))
	_set_bus_volume("UI", float(cfg.get_value("audio", "ui", 0.85)))
	# Display
	var fullscreen := bool(cfg.get_value("display", "fullscreen", false))
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

static func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		# Create bus (except Master which always exists)
		if bus_name == "Master":
			return
		idx = AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	linear = clampf(linear, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

static func get_value(section: String, key: String, default: Variant) -> Variant:
	return get_cfg().get_value(section, key, default)

static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := get_cfg()
	cfg.set_value(section, key, value)
	save(cfg)