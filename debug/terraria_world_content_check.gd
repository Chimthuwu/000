extends SceneTree

# Agent 4 direction audit. Validates the Terraria-style biome CONTENT contract
# and reports the honest gap to the live engine. It does not modify generation.
#   Godot --headless --path lumen_deepworld --script res://debug/terraria_world_content_check.gd

var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("TERRARIA CONTENT FAIL: %s %s" % [label, detail])
		return
	print("TERRARIA CONTENT PASS: %s %s" % [label, detail])


func _initialize() -> void:
	var report: Dictionary = TerrariaWorldContent.audit()
	_check(bool(report["ok"]), "Terraria biome catalogue is internally consistent", str(report["failures"]))

	var ids: Array = report["core_biomes"]
	_check(ids.size() == 9, "all nine core Terraria surface biomes are defined", "ids=%s" % str(ids))
	for required in ["forest", "desert", "jungle", "corruption", "crimson", "hallow", "snow", "ocean", "mushroom"]:
		_check(ids.has(required), "core biome defined: " + required)

	_check(bool(report["undercroft_optional"]), "Undercroft is optional content, not the game identity")
	_check(TerrariaWorldContent.evil_biomes_are_exclusive(),
		"Corruption/Crimson are mutually exclusive by default", "mode=%s" % str(report["evil_mode"]))
	_check(TerrariaWorldContent.hallow_is_progression_gated(),
		"Hallow is introduced by progression, not at world start", "flag=%s" % str(report["hallow_flag"]))
	_check(TerrariaWorldContent.HALLOW_INTRODUCTION_FLAG != "hollow_warden_defeated",
		"Hallow is not tied to the optional Hollow Warden", str(report["hallow_flag"]))
	_check(bool(report.get("hallow_debug_override", false)),
		"Hallow has an explicit debug override while the event is unimplemented")
	_check((report["layers"] as Array).size() == 5,
		"all five vertical layers have content contracts", str(report["layers"]))

	# Legacy names may only be variants of a CORE identity, never replacements.
	for legacy in TerrariaWorldContent.LEGACY_ALIASES.keys():
		var core := TerrariaWorldContent.core_name_for_legacy(String(legacy))
		_check(ids.has(core), "legacy name maps to a core biome", "%s -> %s" % [String(legacy), core])

	# Read the live engine and report the real implementation gap honestly.
	BiomeManager.configure(139732)
	var engine_names: Array = []
	for i in range(BiomeManager.BIOME_COUNT):
		engine_names.append(BiomeManager.biome_name(i))
	print("AUDIT engine surface biomes (%d): %s" % [BiomeManager.BIOME_COUNT, str(engine_names)])
	var missing: Array = report["missing_in_engine"]
	_check(missing.is_empty(),
		"every core identity is implemented by the engine",
		"missing=%s" % str(missing))
	for required_name in ["Forest", "Desert", "Jungle", "The Corruption", "The Crimson", "The Hallow", "Snow", "Ocean", "Mushroom"]:
		_check(engine_names.has(required_name), "engine exposes core biome: " + required_name)

	if failures > 0:
		quit(1)
		return
	print("TERRARIA WORLD CONTENT CHECK PASS: sandbox identity contract verified")
	quit(0)
