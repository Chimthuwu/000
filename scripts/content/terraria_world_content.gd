extends RefCounted
class_name TerrariaWorldContent

# Agent 4 — world content / biome DESIGN authority (not the generator).
#
# CANONICAL 3D TERRARIA DIRECTION: the game is a Terraria-style sandbox. The
# nine core Terraria surface biomes below are the identities the world must
# present. The engine's existing climate ids (BiomeManager 0..5) are mapped to
# them as VARIANTS where they fit; the rest are explicit, honest gaps for
# Agent 1 to implement in world generation. This file does NOT rewrite terrain,
# add blocks, or claim any unimplemented biome works.
#
# The Undercroft is optional authored adventure content, not the game identity.

const CORE_BIOMES := [
	{
		"id": "forest", "display": "Forest", "engine_id": 3, "status": "partial",
		"variants": ["Overworld", "Forest", "Mire"],
		"layer": "surface", "enemy_theme": "forest", "structure_theme": "settlement",
		"treasure_tier": "common", "progression_flag": "", "evil": false,
		"notes": "Spawn biome. Engine id 3 is presented as Overworld; the grassy/swampy look is a variant, not a separate Mire biome.",
	},
	{
		"id": "desert", "display": "Desert", "engine_id": 4, "status": "partial",
		"variants": ["The Desert"],
		"layer": "surface", "enemy_theme": "desert", "structure_theme": "ruin",
		"treasure_tier": "uncommon", "progression_flag": "", "evil": false,
		"notes": "Engine id 4 is the hot dune/sandstone climate; Desert remains a variant name.",
	},
	{
		"id": "jungle", "display": "Jungle", "engine_id": 6, "status": "implemented",
		"variants": ["Jungle"],
		"layer": "surface", "enemy_theme": "jungle", "structure_theme": "temple",
		"treasure_tier": "uncommon", "progression_flag": "", "evil": false,
		"notes": "Engine id 6: jungle grass over mud with dense canopy trees. Jungle remains a dark variant region.",
	},
	{
		"id": "corruption", "display": "The Corruption", "engine_id": 7, "status": "implemented",
		"variants": [], "layer": "surface", "enemy_theme": "corruption",
		"structure_theme": "chasm_shrine", "treasure_tier": "rare",
		"progression_flag": "", "evil": true,
		"notes": "Engine id 7: corrupt grass over ebonstone with chasms. Mutually exclusive with The Crimson by default.",
	},
	{
		"id": "crimson", "display": "The Crimson", "engine_id": 8, "status": "implemented",
		"variants": [], "layer": "surface", "enemy_theme": "crimson",
		"structure_theme": "flesh_altar", "treasure_tier": "rare",
		"progression_flag": "", "evil": true,
		"notes": "Engine id 8: crimson grass over crimstone. Mutually exclusive with The Corruption unless both-evil is set.",
	},
	{
		"id": "hallow", "display": "The Hallow", "engine_id": 9, "status": "implemented",
		"variants": [], "layer": "surface", "enemy_theme": "hallow",
		"structure_theme": "hallow_grove", "treasure_tier": "rare",
		"progression_flag": "underworld_vanquished", "evil": false,
		"notes": "Engine id 9: hallowed grass over pearlstone. Reserved for a future end-of-pre-hardmode Underworld event; the optional Hollow Warden does NOT unlock it. Debug override: dev console `hallow on`.",
	},
	{
		"id": "snow", "display": "Snow", "engine_id": 2, "status": "partial",
		"variants": ["Snow"],
		"layer": "surface", "enemy_theme": "snow", "structure_theme": "ice_ruin",
		"treasure_tier": "uncommon", "progression_flag": "", "evil": false,
		"notes": "Engine id 2 is the frozen climate; Snow is the regional variant name.",
	},
	{
		"id": "ocean", "display": "Ocean", "engine_id": 10, "status": "implemented",
		"variants": [], "layer": "surface", "enemy_theme": "ocean",
		"structure_theme": "shipwreck", "treasure_tier": "uncommon",
		"progression_flag": "", "evil": false,
		"notes": "Engine id 10: ocean sand shore flooded to sea level, with a translucent surface plane.",
	},
	{
		"id": "mushroom", "display": "Mushroom", "engine_id": 5, "status": "partial",
		"variants": ["Mushroom"],
		"layer": "surface", "enemy_theme": "mushroom", "structure_theme": "fungal_grove",
		"treasure_tier": "uncommon", "progression_flag": "", "evil": false,
		"notes": "Engine id 5 is the glow-cap climate; Mushroom is its variant name.",
	},
]

# Legacy names are retained ONLY as variants of a core Terraria biome above.
# They are not independent identities and must not displace the core names.
const LEGACY_ALIASES := {
	"ashen_flats": "forest",
	"jungle": "jungle",
	"snow": "snow",
	"mire": "forest",
	"desert": "desert",
	"mushroom": "mushroom",
}

# Terraria-style vertical model. Agent 1's WorldLayers provides the bands;
# this is the CONTENT contract for what belongs in each band.
const LAYERS := [
	{"id": "surface", "display": "Surface", "content": "forest/desert/jungle/snow/ocean/mushroom villages, ruins, evil biomes, Hallow after progression"},
	{"id": "underground", "display": "Underground", "content": "tunnels, soil/rock caves, first ore tiers, buried caches, NPC cables"},
	{"id": "caverns", "display": "Caverns", "content": "large open caverns, lava aquifers, crystal/fungal grottoes, rare ore"},
	{"id": "underworld", "display": "Underworld", "content": "lava seas, ash/obsidian terrain, forge ruins, boss arena"},
	{"id": "sky", "display": "Sky / Floating Islands", "content": "WorldSky islands, clouds, sky loot, balloon/accessory discoveries"},
]

# World-generation options Agent 1 must honour in BiomeManager/WorldGenerator.
const EVIL_BIOME_MODE := "corruption"  # corruption | crimson | both
# Reserved for Agent 2's future Underworld/end-of-pre-hardmode event. The
# optional Hollow Warden boss is explicitly NOT this trigger.
const HALLOW_INTRODUCTION_FLAG := "underworld_vanquished"
const HALLOW_DEBUG_OVERRIDE := true

# Undercroft is discoverable optional content, never the central identity.
const UNDERCROFT_OPTIONAL := true

# Phase 4: biome-specific discoveries are CORE sandbox content and are enabled
# independently of the optional Undercroft.
const ENABLE_BIOME_DISCOVERIES := true


static func core_biome_ids() -> Array:
	var ids: Array = []
	for biome in CORE_BIOMES:
		ids.append(String((biome as Dictionary)["id"]))
	return ids


static func descriptor(id: String) -> Dictionary:
	for biome in CORE_BIOMES:
		var d: Dictionary = biome
		if String(d["id"]) == id:
			return d
	return {}


static func core_name_for_legacy(legacy: String) -> String:
	var key := legacy.to_lower().replace(" ", "_")
	return String(LEGACY_ALIASES.get(key, ""))


static func implemented_biomes() -> Array:
	var ids: Array = []
	for biome in CORE_BIOMES:
		var d: Dictionary = biome
		if int(d["engine_id"]) >= 0:
			ids.append(String(d["id"]))
	return ids


static func missing_biomes() -> Array:
	var ids: Array = []
	for biome in CORE_BIOMES:
		var d: Dictionary = biome
		if int(d["engine_id"]) < 0:
			ids.append(String(d["id"]))
	return ids


static func evil_biomes_are_exclusive() -> bool:
	return EVIL_BIOME_MODE != "both"


static func hallow_is_progression_gated() -> bool:
	var d := descriptor("hallow")
	return not String(d.get("progression_flag", "")).is_empty()


static func layer_ids() -> Array:
	var ids: Array = []
	for layer in LAYERS:
		ids.append(String((layer as Dictionary)["id"]))
	return ids


# Honest audit: definitions + the gap between them and the live engine.
static func audit() -> Dictionary:
	var expected := ["forest", "desert", "jungle", "corruption", "crimson", "hallow", "snow", "ocean", "mushroom"]
	var ids := core_biome_ids()
	var failures: Array = []
	if ids.size() != expected.size():
		failures.append("core biome count")
	for id in expected:
		if not ids.has(id):
			failures.append("missing definition:" + id)
	if not evil_biomes_are_exclusive():
		failures.append("evil biomes not exclusive")
	if not hallow_is_progression_gated():
		failures.append("hallow not gated")
	if layer_ids().size() != 5:
		failures.append("layer coverage")
	if not UNDERCROFT_OPTIONAL:
		failures.append("undercroft not optional")
	for alias in LEGACY_ALIASES.keys():
		if not ids.has(String(LEGACY_ALIASES[alias])):
			failures.append("bad legacy alias:" + String(alias))
	return {
		"ok": failures.is_empty(),
		"failures": failures,
		"core_biomes": ids,
		"implemented": implemented_biomes(),
		"missing_in_engine": missing_biomes(),
		"layers": layer_ids(),
		"evil_mode": EVIL_BIOME_MODE,
		"hallow_flag": HALLOW_INTRODUCTION_FLAG,
		"hallow_debug_override": HALLOW_DEBUG_OVERRIDE,
		"undercroft_optional": UNDERCROFT_OPTIONAL,
	}
