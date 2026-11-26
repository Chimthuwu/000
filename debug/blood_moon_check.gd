extends SceneTree

# Exercises the Blood Moon state machine (BloodMoonDirector) and its music
# hook (MusicSynth's "blood_moon" category) without needing a full world
# boot. BloodMoonDirector's _ready() wires world/cycle/player/hud by looking
# up siblings in the live scene tree; here those are set directly so the
# dusk-roll / start / end logic can be driven and inspected in isolation.

var _failures: Array[String] = []


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _initialize() -> void:
	var director := BloodMoonDirector.new()
	director.cycle = DayNightCycle.new()
	director.player = VoxelPlayer.new()
	director.hud = null
	director.rng.randomize()

	director.player.max_health = 100.0
	director._roll_for_tonight()
	_check("no roll below the 120 HP threshold", not director.is_pending, "max_health=100")

	director.player.max_health = 150.0
	var rolled := false
	for _attempt in range(200):
		var fresh := BloodMoonDirector.new()
		fresh.cycle = DayNightCycle.new()
		fresh.player = director.player
		fresh.hud = null
		fresh.rng.randomize()
		fresh._roll_for_tonight()
		if fresh.is_pending:
			rolled = true
			fresh.cycle.free()
			fresh.free()
			break
		fresh.cycle.free()
		fresh.free()
	_check("dusk roll can trigger above the threshold", rolled, "trigger_chance=%.3f" % BloodMoonDirector.CONFIG.trigger_chance)

	# GDScript lambdas capture locals by value, so a one-element array is the
	# cheap way to let the callback write back to this scope.
	var started := [false]
	var ended := [false]
	director.blood_moon_started.connect(func(): started[0] = true)
	director.blood_moon_ended.connect(func(): ended[0] = true)
	director.is_pending = true
	director._start()
	_check("starting clears pending and sets active", not director.is_pending and director.is_active, "")
	_check("starting reddens the sky factor", is_equal_approx(director.cycle.blood_moon_factor, 1.0), "factor=%.2f" % director.cycle.blood_moon_factor)
	_check("starting emits blood_moon_started", started[0], "")

	director._end()
	_check("ending clears active", not director.is_active, "")
	_check("ending resets the sky factor", is_equal_approx(director.cycle.blood_moon_factor, 0.0), "factor=%.2f" % director.cycle.blood_moon_factor)
	_check("ending emits blood_moon_ended", ended[0], "")

	_check("blood_moon is a registered music category", MusicSynth.CATEGORIES.has("blood_moon"), "")
	var profile := MusicSynth.profile_for("blood_moon")
	_check("blood_moon has its own music profile", profile.has("bpm") and float(profile["bpm"]) > 0.0, "bpm=%s" % profile.get("bpm"))
	var bytes := MusicSynth.build_bytes("blood_moon")
	_check("blood_moon music synthesizes audio", bytes.size() > 0, "bytes=%d" % bytes.size())

	director.cycle.free()
	director.player.free()
	director.free()

	if _failures.is_empty():
		print("BLOOD MOON CHECK PASS")
		quit(0)
	else:
		print("BLOOD MOON CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
