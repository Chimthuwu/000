extends Node3D
class_name MenuFlyover

## The actual game world, shown behind the main menu with a slow orbiting
## camera instead of a hand-built mockup. This embeds the real VoxelWorld
## class directly (not the full Main scene) so the menu gets the real
## terrain/trees/lighting without the player, HUD, or any of the night/enemy
## systems that scene also carries.
##
## VoxelWorld only needs two siblings to be useful outside Main: a node at
## "Player/Camera3D" (its streaming-focus and lighting-camera reference) and
## a "DirectionalLight3D" (its sun). Nothing else in Main.tscn is required.

const WorldScript := preload("res://scripts/world/world.gd")

const ORBIT_RADIUS := 44.0
const ORBIT_HEIGHT := 22.0
const ORBIT_ANGULAR_SPEED := 0.035

var _rig: Node3D
var _camera: Camera3D
var _world: VoxelWorld
var _time := 0.0
var _center := Vector3(64.0, 196.0, 64.0)


func _ready() -> void:
	var env_node := WorldEnvironment.new()
	env_node.environment = load("res://data/world/world_environment.tres")
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation = Vector3(-0.785398, -0.610865, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	_rig = Node3D.new()
	_rig.name = "Player"
	add_child(_rig)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 60.0
	_camera.current = true
	_rig.add_child(_camera)
	_rig.position = _center + Vector3(0.0, ORBIT_HEIGHT, ORBIT_RADIUS)

	_world = WorldScript.new()
	_world.name = "VoxelWorld"
	_world.world_seed = 139732
	add_child(_world)


func _process(delta: float) -> void:
	_time += delta
	var angle := _time * ORBIT_ANGULAR_SPEED
	var height := ORBIT_HEIGHT + sin(_time * 0.12) * 5.0
	_rig.position = _center + Vector3(cos(angle) * ORBIT_RADIUS, height, sin(angle) * ORBIT_RADIUS)
	_camera.look_at(_center, Vector3.UP)
	# With no DayNightCycle in this standalone scene nothing ever calls these, so
	# the terrain shader's sun and ambient terms default to 0 (full night
	# darkness, regardless of the DirectionalLight3D node's own settings - the
	# custom terrain shader only reacts to World.set_sun()). Lock both to a
	# bright daytime look for the menu regardless of the real in-game time.
	_world.set_ambient_sky_level(1.0)
	_world.set_sun(Vector3(0.42, 0.78, 0.45), Color(1.0, 0.86, 0.64), 1.0)
