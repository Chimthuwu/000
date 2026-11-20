# Agent Contracts

Stable interfaces other agents should build against. Owned by **Agent 1**.

## Block data

`BlockLightDef` fields: `block_id`, `attenuation`, `albedo`, `emitted_light`,
`display_name`, `hardness`, `mining_tier`, `drop_block_id`, `drop_count`,
`is_solid_block`.

Palette order is the save/network id. **Append only.** Phase 2 additions:
`water`, `lava`, `magma_stone`, `frost_stone`, `mycelium_stone`,
`ancient_ore`, `frost_crystal_ore`, `fungal_ore`, `volcanic_crystal_ore`,
`desert_sand`, `sandstone`, `mushroom_soil`, `cactus`, `mushroom_stem`,
`mushroom_cap`, `crystal_stone`.

## Vertical model (`scripts/world/world_layers.gd`)

```gdscript
WorldLayers.WORLD_Y            # 256
WorldLayers.CHUNKS_Y           # 16
WorldLayers.SURFACE_LIFT       # 168 (surface ~y=190)
WorldLayers.UPPER_DEPTH        # 24
WorldLayers.UNDERGROUND_DEPTH  # 64
WorldLayers.DEEP_DEPTH         # 108
WorldLayers.CAVERN_DEPTH       # 150

layer_at(y, surface_y) -> int      # enum Layer: SURFACE/UPPER/UNDERGROUND/DEEP/CAVERN/ABYSS/UNDERWORLD/SKY
zone_at(y, surface_y) -> int       # 0 surface, 1 shallow, 2 deep, 3 abyss
depth_ratio(y, surface_y) -> float
depth_below_surface(y, surface_y) -> int
layer_name(layer) -> String
```

Bands are **depth-relative**: always pass the local `surface_y`.

## Surface biomes (`BiomeManager`)

Six biomes, ids stable: `0` Ashen Flats, `1` Hushwoods, `2` Frostfall,
`3` The Mire, `4` The Scorchlands (desert), `5` Glowgrove (mushroom).

```gdscript
BiomeManager.BIOME_COUNT # 6
BiomeManager.get_weights(x, z) -> PackedFloat32Array
BiomeManager.dominant_biome(x, z) -> int
BiomeManager.surface_biome(x, z) -> int
BiomeManager.get_height(x, z) -> int
BiomeManager.biome_name(id) -> String
BiomeManager.sky_mode(x, z) -> int   # 1 open / 2 canopy / 3 overcast
```

## Underground biomes (`scripts/world/world_biomes.gd`)

```gdscript
WorldBiomes.configure(seed)
WorldBiomes.underground_biome_at(x, y, z, surface_y, surface_biome) -> int
WorldBiomes.stone_name(underground_biome, depth) -> StringName
WorldBiomes.enemy_tag(underground_biome) -> StringName
WorldBiomes.ambient_light(underground_biome) -> float
WorldBiomes.biome_name(underground_biome) -> String
```

Enum `Underground`: NORMAL, FUNGAL, VOLCANIC, CRYSTAL, FROZEN, ANCIENT.
Runtime: `VoxelWorld.get_underground_biome(cell) -> int`.
`enemy_tag` / `ambient_light` are metadata for Agent 2/3; they do not spawn or
render anything by themselves.

## World streaming (`VoxelWorld`)

- `WORLD_Y = 256`, `CHUNKS_Y = 16`; surface ~y=190.
- Resident vertical window only (`VERTICAL_ABOVE = 1`, `VERTICAL_BELOW = 2`);
  deep rows stream in on descent and unload behind.
- Mesh dispatch is nearest-first; chunks whose face neighbours are not installed
  are retried (not dropped), so window shifts recover without a remesh storm.
- `WorldCaves.build_cache(origin)` builds the 16x16 cave/aquifer table used by
  `is_cave_cached` / `liquid_at_cached`; chunks above the local surface skip it.
- Unloaded rows outside the window are treated as solid frontier for lighting
  and meshing.
- `spawn_origin` / `spawn_height()` are the only legal spawn sources.
- `player_tracking` is enabled by `main.gd` after the player spawns; until then
  streaming stays anchored to the spawn column.

## Liquids

`water` / `lava` are block ids with `is_solid_block = false`; `world.is_solid`
is false for them. Generation stays deterministic and static:
`WorldCaves.liquid_at(x,y,z,surface_y)` -> 0/1/2 (and the cached form used by
the generator). Rendering is inset liquid volumes via
`ChunkMesher._append_liquid`.

Runtime settling is `LiquidSim` (`scripts/world/liquid_sim.gd`), local and
bounded:

- only cells disturbed by a player edit (and their six neighbours) are queued;
- water falls into air, otherwise spreads into one deterministic horizontal
  neighbour; lava follows the same rule but only every third update;
- at most 512 cells are tracked and 12 updates run per frame;
- unloaded cells are dropped rather than queued, so a streaming frontier cannot
  create an infinite update queue;
- flow writes use `set_block(cell, id, false)` (silent), so derived flow is not
  journaled; the player's original place/break still is.

`VoxelWorld.set_block(cell, id, journal := true)`: keep the default for gameplay
and tooling; pass `false` only for derived/simulation writes. Agent 2 may read
`MiningSystem.is_liquid` / `world.is_solid` for buoyancy and lava damage.

## Ores (`scripts/world/world_ores.gd`)

```gdscript
WorldOres.ore_at(x, y, z, surface_y, biome, underground_biome = -1) -> StringName
```

Per-biome tables `BIOME_ORES` (6 entries), plus underground-biome signature
materials and volcanic-depth additions. One material per 8x6x8 vein cell.

## Structures (`scripts/world/world_structures.gd`)

```gdscript
WorldStructures.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)
```

One site per 96x96 grid cell; chunk-safe; templates: mine entrance, ruin,
ancient chamber, treasure vault, crystal shrine, watchtower.

## Sky islands (`scripts/world/world_sky.gd`)

```gdscript
WorldSky.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)
```

One deterministic island candidate per 80x80 grid cell (42% chance), floating
24-52 blocks above the local surface. Soil-capped stone ellipsoid, hanging vines
and an occasional crystal beacon. Stamped during generation, writes only cells
inside the current chunk, so seams are identical from both sides. Islands are
ordinary world voxels (mineable, persistent); there is no fake sky biome.

## MiningSystem

```gdscript
raycast / definition / display_name / hardness / mining_tier
can_mine / is_liquid / is_replaceable / can_place
drop_for / break_block -> {mined, drop, block_id, display_name, hardness}
place_block
```

Gameplay, UI and combat must use `MiningSystem`, not raw `world.set_block`.

## Persistence

Sparse journal from `VoxelWorld.block_edited`, saved by `WorldSave`
(save v4, block-defs v3). Old saves are rejected. Liquid-simulation writes are
deliberately silent (`journal = false`) and therefore are not saved; only the
player edit that caused the flow is journaled.

## Terraria biome identity adapter (Agent 2)

World generation keeps numeric ids; gameplay reasons about Terraria identities:

```gdscript
GameplayBiome.identity_for(world_biome) -> int   # Identity enum
GameplayBiome.display_name_for(world_biome) -> String
```

Mapping uses `BiomeManager` constants: ASHEN/MIRE → FOREST (MIRE is the green
"Forest/Overworld" spawn), HUSH/JUNGLE → JUNGLE, FROST → SNOW, DESERT → DESERT,
MUSHROOM → MUSHROOM, CORRUPTION → CORRUPTION, CRIMSON → CRIMSON, HALLOW →
HALLOW, OCEAN → OCEAN. Gameplay reads the constants, so Agent 1 owns the ids.
`EnemyConfig.weights_for_identity()` / `roll_kind_identity()` read matching
tables; `EnemyDirector` spawns by identity, not raw ids.

## Discovery gameplay (Agent 2)

```gdscript
DiscoveryRewards.resolve_item_id(loot_name: String) -> StringName
DiscoveryRewards.claim_flag(discovery_id: String) -> StringName
DiscoveryRewards.try_claim(discovery, inventory, progression) -> Dictionary
EnemyDirector.spawn_discovery_encounter(discovery_id: String, world_seed: int) -> Array
EnemyDirector.encounter_center_provider  # bound to AdventureContent.room_center
```

Discovery loot names are resolved through `ItemDatabase.item_id_for_drop`;
invalid/empty names are skipped. Rewards are claimed once via a progression flag
(`disc_claimed_<id>`) and therefore persist in the v4 save. Physical treasure is
stamped as mineable blocks by Agent 4 and collected through `MiningSystem`.
Only guarded templates (vault/temple/altar/heart/garden/wreck/floating) spawn a
small encounter; other sites stay pure exploration.

Hallow introduction is `ProgressionSystem.unlock_hallow()` → flag
`underworld_vanquished`, read by Agent 1's `main.gd`. The optional Hollow Warden
never sets it.

## Agent 2 gameplay APIs (published, stable)

| Type / path | Contract |
| --- | --- |
| `ItemDef` (`scripts/items/item_def.gd`) | id, display name, description, icon id, category, stack limit, rarity, value, equipment slot, tool properties, `AttackDef`, consumable fields, place block, armour. |
| `ItemDatabase` | `get_item(id)`, `all()`, `has(id)`, `stack_limit(id)`, `item_id_for_drop(block_id)`. Items live in `data/items/*.tres`. |
| `InventoryModel` | 10 hotbar + 40 main slots, 4 equipment slots; `add_item`, `remove_item`, `consume`, `has_item`, `count`, `swap_slots`, `split_stack`, `select`, `held_item`, `equip`, `unequip`, `total_armor`, `serialize`, `deserialize`. Signals: `changed`, `item_added`, `item_removed`, `selection_changed`, `equipment_changed`. Slot: `{id:StringName, amount:int, metadata:Dictionary}`. |
| `CraftingRecipe` / `RecipeDatabase` / `CraftingSystem` | `can_craft`, `craft`, `available`, `reason`. Recipes in `data/recipes/*.tres`; stations `none/workbench/furnace/anvil`; flag unlocks via ProgressionSystem. |
| `ProgressionSystem` | `set_flag`, `has_flag`, `discover`, `has_discovered`, `add_stat`, `serialize`, `deserialize`. |
| `AttackDef` / `GameProjectile` / `WeaponController` | `kind` = melee/ranged/magic/thrown; melee uses a forward arc, others spawn a `GameProjectile` with gravity/pierce/mana cost. |
| `GloomEnemy` | `apply_damage(amount, knockback, from, source)`, signal `died(enemy, position)`, `loot_table`, `difficulty_scale`. |
| `BossDef` / `BossDirector` | data in `data/bosses/*.tres`; `spawn_encounter(room_id)`, `spawn_boss(room_id)`, defeat flags, reward duplication guard. |
| `NpcService` (`scripts/npc/npc_service.gd`) | `buy`, `sell`, `can_buy`, `complete_quest`, `available_quest`. Uses Agent 3's `NpcBase` fields; no duplicate NPC node. |
| Player save | `serialize_gameplay_state()` / `deserialize_gameplay_state()` nested at `metadata.m4.gameplay`; includes inventory, equipment, hotbar, progression, boss state, stats. |

Agent 2 consumes only the world endpoints in this document. All block
break/place goes through `MiningSystem`; `get_mining_info` is not required.

## Agent 4 — Authored adventure content (canonical port)

`scripts/content/adventure_content.gd` (`AdventureContent`, static/pure) and
`scripts/content/adventure_config.gd` (`AdventureConfig`).

- `AdventureContent.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)`:
  deterministic content stamping called from `WorldGenerator.generate_chunk()`
  immediately after `WorldStructures.stamp_chunk()`. Additive; disable with
  `AdventureConfig.enable_undercroft = false`. The Undercroft is ONE authored
  multi-room region, not a repeating 96x96 template, so it is not registered in
  `WorldStructures.TEMPLATES`.
- `AdventureContent.region_levels(world_seed) -> Dictionary`: depth-relative
  levels sampled from the LOWEST local surface across the region (`upper`,
  `lower`, `min_surface`, `max_surface`). Rooms stay buried regardless of
  `SURFACE_LIFT` / WORLD_Y tuning.
- `AdventureContent.volumes(world_seed)`, `volumes_for(levels)`,
  `room_at(cell, world_seed)`, `region_bounds(world_seed)`,
  `validate_region(world_seed, block_ids)`.
- Stable room ids: `entry_hall`, `guard_room`, `shattered_gallery`,
  `hidden_cache`, `lower_sanctum`, `ember_vault`.
- Block ids resolve from `VoxelWorld.block_ids` by NAME only — no numeric
  fallbacks (canonical `air`=10, `stone`=13, `water`=0).
- Encounter data (`AdventureConfig.encounters`) uses `EnemyConfig.KIND_*`.
  Kind 99 is Agent 2's implemented Hollow Warden boss; Agent 2's
  `BossDirector.spawn_encounter(room_id)` / `spawn_boss(room_id)` are the
  runtime endpoints for these room ids.
- Treasure entries use canonical block names and map to items through Agent 2's
  `ItemDatabase.item_id_for_drop(block_id)`.

## Terraria-style biome CONTENT contract (Agent 4 direction correction)

`scripts/content/terraria_world_content.gd` (`TerrariaWorldContent`) is the
content-level authority for biome IDENTITY. It does not own generation.

- Nine core surface identities: `forest`, `desert`, `jungle`, `corruption`,
  `crimson`, `hallow`, `snow`, `ocean`, `mushroom`.
- Legacy engine names are variants only: `ashen_flats`/`mire` -> `forest`,
  `hushwoods` -> `jungle`, `frostfall` -> `snow`, `scorchlands` -> `desert`,
  `glowgrove` -> `mushroom`. They must not displace the core names in UI or docs.
- `TerrariaWorldContent.audit() -> Dictionary` reports `core_biomes`,
  `implemented`, `missing_in_engine`, `layers`, `evil_mode`, `hallow_flag`.
- Generation hook (implemented in `BiomeManager`):
  `set_evil_mode("corruption" | "crimson" | "both")` / `evil_mode()`;
  `set_hallow_enabled(bool)` / `hallow_enabled()`. The seed-derived default is
  exclusive. `main.gd` enables Hallow from the `hushwood_seed_granted` or
  `hollow_warden_defeated` progression flag; enabling affects newly streamed
  chunks only.
- Five vertical layer content contracts: `surface`, `underground`, `caverns`,
  `underworld`, `sky` (Agent 1's `WorldLayers` / `WorldSky` supply the bands).
- `UNDERCROFT_OPTIONAL = true`: the dungeon is one discoverable location, never
  the game's identity or a prerequisite for core progression.
- Engine ids: 0 Ashen Flats (forest variant), 1 Hushwoods (jungle variant),
  2 Snow, 3 Forest, 4 Desert, 5 Mushroom, 6 Jungle, 7 The Corruption,
  8 The Crimson, 9 The Hallow, 10 Ocean. Verified by
  `debug/terraria_world_content_check.gd` (`missing_in_engine = []`) and
  `debug/core_biomes_check.gd` (generated signature surfaces, underground
  stones/ores, exclusivity, Hallow gate, edge oceans).
- Underground identity: `WorldBiomes.Underground` now includes JUNGLE,
  CORRUPTION, CRIMSON, HALLOW, OCEAN. Signature stone: `jungle_mudstone`,
  `ebonstone`, `crimstone`, `pearlstone`, `reefstone`. Signature ores:
  `amber_ore`, `void_ore`, `blood_ore`, `radiant_crystal_ore`, `pearl_ore`.
- Ocean edge rule: `BiomeManager.OCEAN_EDGE_START = 3200`,
  `OCEAN_EDGE_FULL = 3900` (|x|). Past the full edge the ocean continues; there
  is no hard world wall.
- Hallow unlock: `HALLOW_INTRODUCTION_FLAG = "underworld_vanquished"` is
  reserved for Agent 2's future Underworld event. The optional Hollow Warden
  must not unlock it. Debug override: dev console `hallow on|off`
  (`BiomeManager.set_hallow_enabled`).

## Phase 4 — Biome-specific discoveries (`scripts/content/biome_discovery.gd`)

`BiomeDiscovery` is static/pure and stamped from the EXISTING
`AdventureContent.stamp_chunk()` generator hook — no new Agent 1 file edit.

- `BiomeDiscovery.TEMPLATES`: reusable template definitions (room / landmark /
  cave builders) with per-template block palette, size, loot names, secret flag
  and display label.
- `BiomeDiscovery.BY_BIOME`: maps Agent 1's real `BiomeManager` ids to template
  ids. All 11 surface ids (0..10) have at least two templates, covering the nine
  core Terraria identities and their variants.
- `BiomeDiscovery.site_for(world_seed, grid_x, grid_z) -> Dictionary`: one
  jittered candidate per 128x128 cell. Skips spawn, the Undercroft footprint,
  and any site within 30 blocks of `WorldStructures._site()` (Agent 1's real
  placement API) — no destructive overlap.
- `BiomeDiscovery.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)`:
  chunk-clipped deterministic stamping; floors stay solid, interiors are air,
  shells seal rooms, surface sites require flat ground.
- `BiomeDiscovery.sites_near(...)` / `discovery_at(world_seed, cell) -> Dictionary`
  publish `{id, label, template, biome, tier, loot, hint}` for presentation and
  loot integration.
- Loot/rewards are DATA ONLY: block names map through Agent 2's
  `ItemDatabase.item_id_for_drop(block_id)`; no item, loot-table or boss
  framework was duplicated. Wiring discovery rewards into `InventoryModel` is
  an Agent 2 task.
- Undercroft remains optional (`TerrariaWorldContent.UNDERCROFT_OPTIONAL`) and
  discoveries work when `AdventureConfig.enable_undercroft = false`.
- `AdventureContent.room_center(room_id, world_seed) -> Vector3` is the pure
  provider for Agent 2's published `EnemyDirector.encounter_center_provider`.
