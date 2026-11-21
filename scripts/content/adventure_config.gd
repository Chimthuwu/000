extends Resource
class_name AdventureConfig

# Agent 4 — World Design / Adventure Architect.
#
# Data contract for the authored initial adventure region "The Undercroft".
# PORTED to the canonical Terraria 3D project and adapted to its vertical
# model: WORLD_Y = 256, SURFACE_LIFT = 168, depth-relative WorldLayers bands.
# Room Y is therefore expressed as DEPTH BELOW THE REGION'S MINIMUM SURFACE,
# never as an absolute Y, so the region stays buried under mountains and
# riverbeds alike. Geometry templates live in AdventureContent.
#
# See docs/AGENT_CONTRACTS.md and docs/INTEGRATION_NOTES.md in the canonical
# project for the integration contract with Agents 1-3.

## Master switch; false restores Agent 1's baseline world exactly.
@export var enable_undercroft := true

## World-column anchor of the surface landmark / entrance shaft.
## 56,96 keeps clear of the river (x ~ 104), the ravine (x ~ 25) and spawn.
@export var anchor_x := 56
@export var anchor_z := 96

## Depth below the lowest local surface at which the upper rooms are cut.
## WorldLayers.UPPER_DEPTH = 18; 26 leaves a solid cap over every room.
@export_range(8, 90, 1) var upper_room_depth := 26
## Vertical separation between the upper rooms and the lower boss level.
@export_range(12, 90, 1) var level_gap := 34
@export_range(3, 8, 1) var room_height := 5
@export_range(4, 12, 1) var arena_height := 8

## Salts keep content RNG independent from terrain/ore/structure RNG.
@export var feature_salt := 30211

## Surface landmark switch (broken gate, waystone, gravel approach path).
@export var enable_surface_gate := true

## Encounter compositions. Pure data: {room, kind, count}.
## kind uses EnemyConfig.KIND_* (Agent 2). Kind 99 is reserved for the boss.
@export var encounters: Array = [
	{"room": "entry_hall", "kind": 0, "count": 2},
	{"room": "guard_room", "kind": 1, "count": 1},
	{"room": "guard_room", "kind": 0, "count": 1},
	{"room": "shattered_gallery", "kind": 0, "count": 2},
	{"room": "lower_sanctum", "kind": 99, "count": 1},
]

## Treasure placement: {room, block, count, rarity}. Block names are canonical
## VoxelWorld.block_ids names (e.g. iron_ore, silver_ore, lumen_crystal).
@export var treasure: Array = [
	{"room": "entry_hall", "block": "iron_ore", "count": 3, "rarity": "common"},
	{"room": "guard_room", "block": "copper_ore", "count": 4, "rarity": "common"},
	{"room": "shattered_gallery", "block": "silver_ore", "count": 2, "rarity": "uncommon"},
	{"room": "hidden_cache", "block": "lumen_crystal", "count": 4, "rarity": "rare"},
	{"room": "hidden_cache", "block": "gold_ore", "count": 3, "rarity": "rare"},
	{"room": "ember_vault", "block": "ancient_ore", "count": 4, "rarity": "rare"},
	{"room": "ember_vault", "block": "lumen_crystal", "count": 4, "rarity": "rare"},
]

## Discoverable secrets: a false wall hides a room; clue blocks flank it.
@export var secrets: Array = [
	{
		"id": "gallery_false_wall",
		"room": "hidden_cache",
		"marker_block": "mycelium",
		"clue_block": "pale_bloom",
		"reveal_hint": "A violet seam in the stone. Two pale blooms mark the spot.",
	},
]

## Boss arena design. Geometry is authored; the boss entity is Agent 2's.
@export var boss_arena: Dictionary = {
	"room": "lower_sanctum",
	"boss_kind": 99,
	"boss_name": "The Hollow Warden",
	"beacon_count": 4,
	"intro_hint": "Four cold beacons ring a dais. The air here is suffocating.",
	"reward": "jungle_seed_core",
}

## World events, data only until the runtime event bus exists.
@export var world_events: Array = [
	{
		"id": "undercroft_awakening",
		"trigger": "proximity",
		"room": "lower_sanctum",
		"radius": 12.0,
		"duration": 0.0,
		"effect": "spawn_boss",
		"once": true,
	},
	{
		"id": "gallery_whispers",
		"trigger": "night_above",
		"room": "shattered_gallery",
		"threshold": 0.65,
		"duration": 20.0,
		"effect": "hint",
		"hint": "Something scrapes stone somewhere behind the walls.",
	},
]

## Environmental-storytelling strings keyed by room id.
@export var clues: Dictionary = {
	"entry_hall": "BROKEN GATE — someone barricaded this way from the inside.",
	"guard_room": "The watch is still here. Nothing edible remains.",
	"shattered_gallery": "Tool marks, then panic. They stopped digging.",
	"hidden_cache": "A cache they never lived to spend.",
	"lower_sanctum": "The dais is warm. It was waiting for you.",
	"ember_vault": "Smells of old smoke. The ore was gathered, not mined.",
}
