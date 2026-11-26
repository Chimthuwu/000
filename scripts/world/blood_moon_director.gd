extends Node
class_name BloodMoonDirector

## Terraria's Blood Moon: rolled at dusk (about 1 in 9, per the wiki), only
## once the player has grown past 120 max health. If it hits, the night that
## follows spawns faster, caps higher and leans hard into zombies (see
## EnemyDirector), with a red-tinted sky (DayNightCycle.blood_moon_factor)
## and a harsher music cue (MusicManager's "blood_moon" category) as the
## tell - no jumpscare, just dusk announcing what is coming.

signal blood_moon_started
signal blood_moon_ended

const CONFIG: BloodMoonConfig = preload("res://data/world/blood_moon_config.tres")

var world: VoxelWorld
var cycle: DayNightCycle
var player: VoxelPlayer
var hud: GameHUD
var rng := RandomNumberGenerator.new()

var is_pending := false
var is_active := false
var _last_phase := ""


func _ready() -> void:
	world = get_parent().get_node("VoxelWorld") as VoxelWorld
	cycle = get_parent().get_node("DayNightCycle") as DayNightCycle
	player = get_parent().get_node("Player") as VoxelPlayer
	hud = get_parent().get_node_or_null("HUD") as GameHUD
	rng.randomize()
	_last_phase = cycle.phase_name


func _process(_delta: float) -> void:
	if world == null or cycle == null or not world.is_generated:
		return
	var phase := cycle.phase_name
	if phase == _last_phase:
		return
	if _last_phase == "day" and phase == "twilight":
		_roll_for_tonight()
	elif phase == "night" and is_pending:
		_start()
	elif _last_phase == "night" and phase == "dawn" and is_active:
		_end()
	_last_phase = phase


func _roll_for_tonight() -> void:
	is_pending = false
	if player == null or player.max_health < CONFIG.min_max_health:
		return
	if rng.randf() < CONFIG.trigger_chance:
		is_pending = true
		if hud != null:
			hud.show_world_hint("THE BLOOD MOON IS RISING...", 5.0)


func _start() -> void:
	is_pending = false
	is_active = true
	if cycle != null:
		cycle.blood_moon_factor = 1.0
	if hud != null:
		hud.show_world_hint("THE BLOOD MOON HAS RISEN.", 5.0)
	blood_moon_started.emit()


func _end() -> void:
	is_active = false
	if cycle != null:
		cycle.blood_moon_factor = 0.0
	if hud != null:
		hud.show_world_hint("THE BLOOD MOON FADES WITH THE DAWN.", 4.0)
	blood_moon_ended.emit()
