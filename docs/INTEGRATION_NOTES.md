# Integration Notes — World Engine (256-block world)

## Shared files Agent 1 touched

- `scripts/world/biome_manager.gd`: `WORLD_Y = 256`, `SURFACE_LIFT = 168`,
  `WATER_LEVEL = 189`, two new biomes (Desert, Mushroom) and heights.
- `scripts/world/world.gd`: 256/16 vertical slab, vertical window streaming,
  palette additions, liquid solids flags, underground-biome query.
- `scripts/world/main.gd`: enables `world.player_tracking` after spawn (prevents
  a one-frame streaming recenter on the origin).
- `scripts/ui/settings_store.gd`: renamed `load()` to `load_settings()` because
  it shadowed Godot's global `load()` and broke `main_menu.gd`; call sites in
  `main_menu.gd` and `player.gd` updated.
- `scripts/ui/dev_console.gd`: `tp` accepts `desert` / `mushroom`.
- `data/world/enemy_config.tres`: added desert/mushroom weight rows.
- `scripts/save/save_manager.gd`: save v4 / block-defs v3.

## Agent 2 (player/inventory/combat)

- Tool tiers 0–5: stone/coal 1, iron 2, crystal 3, frost crystal/silver/gold 4,
  ancient/volcanic 5.
- Drain `player.collected_blocks`; use `MiningSystem.drop_for` /
  `break_block(...).drop`.
- Water/lava are non-solid; add buoyancy/lava damage using
  `MiningSystem.is_liquid` and `world.is_solid`.
- Underground spawn metadata:
  `WorldBiomes.enemy_tag(world.get_underground_biome(cell))`.
- Do not add a second mining or inventory system.

## Agent 3 (presentation/UI/audio)

- Depth label: `WorldLayers.layer_name(WorldLayers.layer_at(y, surface_y))`.
- Underground region name: `WorldBiomes.biome_name(world.get_underground_biome(cell))`.
- Ambience: `WorldBiomes.ambient_light(...)` and emissive crystal stone/lava.
- Target block: `MiningSystem.display_name/hardness` for progress UI.
- New biome fog entries are in `VoxelWorld.BIOME_FOG_SCALE/TINT` (11 entries,
  indexed by `BiomeManager` ids 0..10).

## Agent 4 (authored content / Undercroft)

- **Undercroft is not present in this copy.** Nothing is being overwritten.
- Add structures through `WorldStructures` (deterministic 96x96 grid, chunk-safe);
  add ore/biome content through the `WorldOres` tables rather than new generators.
- Coordinate before editing `world_generator.gd`.

## Agent 2 integration notes (Phase 2)

- `player.collected_blocks` is drained every frame into `InventoryModel`.
  `MiningSystem.break_block(...).drop` and `drop_for` are normalised through
  `ItemDatabase.item_id_for_drop` (aliases: `coal_ore`→`coal`,
  `deepstone`/`cavern_stone`→`stone`). All other new block drops have real
  item definitions, so no drop is nameless.
- Inventory overflow spawns an `ItemEntity` at the player instead of vanishing.
- Mining never calls `world.set_block` directly: targeting, tier gating and
  breaking all go through `MiningSystem`. The HUD can read
  `player.target_block_name`, `target_mining_tier`, `target_can_mine`,
  `mining_progress` and `player.mining_tier`.
- Tool tiers are derived from the held `ItemDef` on selection/equipment change.
  Ladder: wooden 1 → copper 2 → iron 3 → silver 4 → gold 5, matching Agent 1's
  block tiers (soil/wood 0, stone/coal/copper 1, iron 2, crystal/silver 3,
  gold/frost-crystal 4, ancient/volcanic 5).
- `EnemyDirector.spawn_encounter(room_id, kinds, count)` accepts an optional
  `encounter_center_provider: Callable(room_id) -> Vector3`; Agent 4 can set it
  when The Undercroft lands. Until then encounters spawn near the player.
  `spawn_boss(room_id)` summons the Hollow Warden (kind 99) and refuses a second
  summon while one lives or after the reward flag is granted.
- Agent 3: `NpcService` is the gameplay data layer behind `NpcBase`; call
  `service.buy/sell/complete_quest` from dialogue/shop UI. No dialogue API was
  changed.
- Save: the existing v4 world save gained one nested key, `metadata.m4.gameplay`;
  `WorldSave` was not modified.

## Launch fix

Godot picks `project.godot` from its working directory. The Godot exe in the
parent folder loaded the old `Terraria3D/project.godot` (`Terraria 3D`), not this
project. Hard-linked exes now exist inside `Terraria3D/`, and
`PLAY_3D_TERRARIA.cmd` / the parent convenience launcher pass an explicit
`--path`. Verified with `debug/launch_identity_check.gd`: both routes report
`Terraria 3D` and `res://scenes/ui/main_menu.tscn`. See `LAUNCH.md`.

Menu buttons were fixed this session. `main_menu.gd::_start_world()` now resolves
`VoxelWorld` by node path before `add_child()` instead of reading the `@onready`
`instance.world` (which was null), and reports load failures on the status label.
Minimal edits to `game_hud.gd` defined `ACCENT_MANA` / `_show_toast()` and removed
duplicate `add_child()` calls. `debug/menu_click_check.gd` passes all seven
buttons; `scenes/world/main.tscn` preflights to `ready`.

## Terraria direction alignment (Agent 2)

- The green starting biome keeps its internal id 3 but is displayed as
  **Overworld** (`BiomeManager.biome_name(MIRE)`); spawn height is clamped above
  the water line and trees now grow in it (higher tree chance + eight landmark
  trees near spawn).
- Gameplay uses `GameplayBiome` identities (Forest/Desert/Jungle/Corruption/
  Crimson/Hallow/Snow/Ocean/Mushroom), so Agent 1 may add/reorder biome ids
  without touching enemy or loot tables. Current ids come from `BiomeManager`
  (Jungle 6, Corruption 7, Crimson 8, Hallow 9, Ocean 10).
- Corruption and Crimson should be mutually exclusive in world generation
  unless explicitly opted into; that is an Agent 1 world option.
- Equipment bonuses are real: `ItemDef.defense_bonus`, `mining_speed_bonus`,
  `move_speed_bonus`, `max_health_bonus` feed `InventoryModel.total_defense()`
  and the player's movement, mining and health caps. Three accessory items and
  recipes were added.
- World progression now has a `hardmode` flag set by the Warden victory.
- NPC roles/shops/housing flags live in `data/npc/*.tres` (`NpcProfile`) and
  `NpcService`; Agent 3 can read `profile_for(npc)` for presentation.

## Phase 4 — discovery gameplay (Agent 2)

- `BiomeDiscovery.discovery_at()` is polled from `VoxelPlayer` at 2 Hz. A one-time
  bonus is granted through `DiscoveryRewards`; physical loot remains mineable
  blocks and is collected through `MiningSystem` / `player.collected_blocks`.
- All discovery loot names resolve to item ids (aliases: `coal_ore`→`coal`,
  `deepstone`/`cavern_stone`→`stone`, etc.); `amber_ore`, `void_ore`,
  `blood_ore`, `pearl_ore`, `radiant_crystal_ore`, `coral` have real item defs.
- Guarded discovery templates spawn 2–3 existing enemies chosen from the
  Terraria biome identity table, at the streamed site coordinates. Other sites
  are exploration-only.
- `EnemyDirector.encounter_center_provider` is bound to
  `AdventureContent.room_center(room_id, seed)`; the Warden uses it for arena
  placement when an encounter is requested. The Undercroft remains optional.
- Hallow is gated by `underworld_vanquished` only; the Warden does not set it.
  A future Underworld boss/event can call `ProgressionSystem.unlock_hallow()`.

## Limitations

- Liquids settle locally after edits (`LiquidSim`) but there is no pressure,
  equalisation or ocean simulation; generated lakes/pools stay where they are.
- Liquid rendering is opaque inset geometry (terrain shader is opaque).
- Vertical window is 4 rows; extreme descent can briefly outrun generation. The
  vertical probe passes a y=150 jump, but a liquid-heavy row at y=60 stayed
  light-ready and unmeshed after 1200 headless frames (open issue).
- Generation is ~45.6 ms/chunk on one headless thread after the Phase 3 column
  cache (Phase 2 record: 64.86 ms; 55-56 ms measured under concurrent load).
  Deep exploration is still streamed lazily, not generated up front.
- Sky islands (`WorldSky`) are implemented as real voxels above the surface,
  with no dedicated sky biome or suspended-ruin templates yet.
- World floor is a hard slab at y=0 (no bedrock/void layer).
- No windowed visual/playtest review of the Phase 3 biomes, sky islands or flow.

## Agent 4 — Undercroft canonical port (this integration)

**Canonical project is `Terraria3D/`.** The earlier `Terraria3D/` copy was
Agent 4's initial workspace; its content has been PORTED AND ADAPTED here, not
copied verbatim.

### Ported files
- `scripts/content/adventure_config.gd` — data resource; Y fields changed to
  depth-relative `upper_room_depth` / `level_gap`; treasure uses canonical ore
  names (copper/silver/gold/ancient).
- `scripts/content/adventure_content.gd` — stamped content; adapted to
  `WorldLayers.WORLD_Y` (dynamic), depth-relative levels derived from the
  lowest local surface, and canonical block ids by name (no numeric fallbacks).
- `data/world/adventure_config.tres` — generated with `debug/generate_adventure_config.gd`.
- `debug/adventure_content_check.gd`, `debug/generate_adventure_config.gd`.
- `docs/*`, `STATE.md`, `DEVLOG.md`, `MULTI_AGENT_STATUS.md` updated/merged.

### Core-file change (Agent 1's generator, one additive call)
In `WorldGenerator.generate_chunk()` after `WorldStructures.stamp_chunk()` and
`_stamp_biome_props()`:
`AdventureContent.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)`.
Rationale: an authored single region is not a repeating WorldStructures template;
stamping during chunk generation is the only way to keep it seamless,
deterministic, save-stable and free of per-frame cost. Rollback: delete the call
or set `enable_undercroft = false` in the config resource.

### What changed versus the earlier Terraria3D copy
- WORLD_Y 64 -> 256; absolute y=12/2 -> depth-relative y=154/120 at seed 139732.
- Block ids: air 0->10, stone 3->13; all numeric fallbacks removed.
- Surface gate Y now uses `BiomeManager.get_height()` (lifted surface ~y=190).
- Stream validation holds the player position every frame because canonical
  `Main` auto-continues a save on boot and resets the player to spawn.
- Agent 3's `GameHUD` and Agent 2's gameplay systems were NOT modified.

### Verification
`adventure_content_check.gd` PASS in canonical: six rooms + five corridors
carved, buried below min surface, four beacons, 8 torches, false wall + clues,
38 ore / 10 crystal upstairs and 79 ore downstairs, deterministic and identical
after unload/reload. Other canonical checks that fail (world_gen liquid sim,
world_contract spawn-height expectations, streaming stale expectations,
ashen_flats canyon depth, biome_check, gun_feel, enemy_behavior frost slow,
dev_console spawn) were A/B tested with `enable_undercroft = false` and fail
identically — they are pre-existing in-progress issues owned by Agents 1/2,
not content regressions. Mesher, gameplay integration, NPC, survival, world
density, biome visuals and boot checks pass with content enabled.

### Integration now available
Agent 2 already ships `BossDirector.spawn_encounter(room_id)` / `spawn_boss()`
and the Hollow Warden (kind 99); wire `AdventureConfig.encounters` room ids to
those endpoints for room-entry encounters. Agent 3 can surface `clues`, secret
hints and the arena intro through the existing `GameHUD.show_world_hint()`.

## Direction correction audit (Agent 4, this session)

**Smallest changes made (within Agent 4 ownership only):**
- Added `scripts/content/terraria_world_content.gd`: nine core Terraria biome
  identities, legacy-name-as-variant mapping, five vertical layer contracts,
  evil-biome exclusivity option (`corruption` by default), Hallow progression
  flag (`hollow_warden_defeated`), and `UNDERCROFT_OPTIONAL = true`.
- Added `debug/terraria_world_content_check.gd` to verify the catalogue and
  print the honest live-engine gap.
- Updated the five shared docs to lead with the sandbox identity and to label
  the Undercroft as optional discoverable content.
- No engine files, GameHUD, gameplay scripts, block ids or save schema changed.

**Implementation status:** the engine generates all nine core identities
(ids 0..10). Forest/Desert/Snow/Mushroom use their core names; Forest and
Jungle remain variants. Corruption and Crimson are seed-exclusive by default
(explicit `both` option); The Hallow is zero-weight by default and reserved for
a future `underworld_vanquished` Underworld event (NOT the Hollow Warden). The
dev console `hallow on|off` command is the debug override. Ocean exists as
climate regions and as edge oceans beyond |x|=3200 (full at 3900).

Underground identity follows the surface biome: Jungle mudstone with large
chambers and amber, Corruption ebonstone with void ore and altar landmarks,
Crimson crimstone with blood ore, Hallow pearlstone/radiant crystal caverns and
groves, Ocean reefstone/seabed with pearl ore, coral and shipwrecks. New block
ids are appended after the previous palette, so existing save block indices are
unchanged and the save format remains v4/block-defs v3. Biome fog arrays, the
water plane and item drop aliases were extended.

Remaining content work: dedicated enemy species (existing enemy kinds are themed
through `GameplayBiome`/`EnemyConfig` weights), more biome loot/treasure, and a
windowed visual review.

**Verification:** `terraria_world_content_check.gd` PASS; `adventure_content_check.gd`
PASS (optional content still works); `world_boot_check`, `npc_check`,
`mesher_fixture_check` PASS. Existing A/B-confirmed failures from other agents
were left untouched. No human windowed playtest yet.

## Agent 4 — Phase 4 biome discoveries

**Implemented (my ownership only):** `scripts/content/biome_discovery.gd` and
`debug/biome_discovery_check.gd`. One additive change in `adventure_content.gd`
calls `BiomeDiscovery.stamp_chunk()` from the already-coordinated generator
hook, and discoveries run independently of `enable_undercroft`. No Agent 1,
Agent 2 or Agent 3 file was edited.

**Reused, not duplicated:** Agent 1's `BiomeManager` ids/height/flatness,
`WorldLayers.WORLD_Y`, `WorldStructures._site()` for separation, and the
existing chunk byte-array hook; Agent 2's block-name-to-item mapping contract;
Agent 3's HUD is untouched (hints are published as data).

**Content:** houses/cabins/ruins/hidden passages/vaults (Forest and variants),
buried temples + fossil chambers (Desert), jungle temples + root caves + rare
vaults (Jungle), shadow altars/chasms/resource vaults (Corruption), crimson
hearts + organic chambers (Crimson), crystal gardens + suspended formations +
magical vaults (Hallow), shipwrecks + submerged caves + coastal vaults (Ocean),
frozen cabins + ice caverns (Snow), glowing groves + fungal chambers (Mushroom).
Secrets use false walls marked by mycelium with pale-bloom clues.

**Placement safety:** 128-block candidate grid, 44-block spawn clearance, 30-block
separation from WorldStructures sites, Undercroft exclusion, flat-ground rule
for surface sites, depth-relative underground levels, chunk-clipped writes,
deterministic RNG, solid floors and sealed shells.

**Integration asks:**
- Agent 2: map `discovery_at().loot` block names with `ItemDatabase.item_id_for_drop`
  when wiring discovery rewards; assign `EnemyDirector.encounter_center_provider`
  to a lambda calling `AdventureContent.room_center(room_id, world.world_seed)`.
- Agent 3: display `discovery_at().label/hint` as exploration discoveries.

**Verification:** `biome_discovery_check.gd` PASS (templates exist for all 11
engine ids, palette/loot names valid, deterministic stamping, chunk writes,
descriptor, live streamed site at (180,154,59)). Regressions PASS:
`terraria_world_content_check`, `adventure_content_check`, `world_boot_check`,
`world_gen_check`, `core_biomes_check`, `npc_check`, `mesher_fixture_check`,
`gameplay_integration_check`, `survival_check`, `world_density_check`.
No human windowed playtest yet.
