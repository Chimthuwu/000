# MULTI-AGENT STATUS — Lumen: Deepworld (canonical 3D Terraria)

**CANONICAL PROJECT: `Z:\GITHUB\_GAMES\Terraria3D\lumen_deepworld`.**
`Z:\GITHUB\_GAMES\Terraria3D` is the earlier workspace; Agent 4's content was
ported and adapted into the canonical tree. Neither directory was deleted; no
destructive Git operations or remote pushes were performed.

## PROJECT IDENTITY (direction correction — read first)

This is a **full 3D Terraria-style sandbox**, not an Undercroft dungeon crawler.
When launched, the player must see a recognisable sandbox world: distinct
Terraria biomes, surface exploration, mining, crafting, building, equipment and
boss progression, NPCs/settlements, and layered underground/Underworld/sky
exploration. The Undercroft is **optional discoverable content**, one small
location among many, and must never be prioritised above the core systems.

Required core surface identities: Overworld/Forest, Desert, Jungle, Corruption,
Crimson, The Hallow, Snow, Ocean, Mushroom. Corruption and Crimson are mutually
exclusive by default; The Hallow is introduced by world progression, never at
world start. Legacy names (Ashen, Hushwoods, Frostfall, Mire, Scorchlands,
Glowgrove) are **variants/sub-biomes only** and must not replace those identities.

## Direction status (updated)

`scripts/content/terraria_world_content.gd` defines the nine core biomes, the
legacy-name mapping, five vertical layer contracts, the evil-biome exclusivity
option and the Hallow introduction flag. The live engine now implements all
nine core identities: `["Ashen Flats", "Hushwoods", "Snow", "Forest", "Desert",
"Mushroom", "Jungle", "The Corruption", "The Crimson", "The Hallow", "Ocean"]`.
`debug/terraria_world_content_check.gd` PASSES with `missing_in_engine = []`, and
`debug/core_biomes_check.gd` PASSES against real generated chunks.

## Owner map

| Agent | Owns |
| --- | --- |
| 1 | World engine, generation, layers, caves, ores, structures, liquids, persistence (`scripts/world/*`, `save/*`) |
| 2 | Player, items, inventory, crafting, combat, enemies, bosses, progression, NPC services |
| 3 | HUD, menus, audio, FX, NPC presentation (`scripts/ui/*`, `audio/*`, `fx/*`, `scripts/npcs/*`) |
| 4 | World content, biomes design, structures, dungeons, treasure, encounters, secrets (`scripts/content/*`) |

## Engine state (canonical, as observed this session)

- WORLD_Y 256 / CHUNKS_Y 16, surface lifted to ~y=190, 4-row vertical streaming
  window, save v4 / block-defs v3.
- Agent 1 Phase 3 added per-column cave caches (16x16), `LiquidSim` bounded
  local flow, `WorldSky` floating islands, underground biome formations and
  nearest-first/retried mesh dispatch. Generation measured 45.58 ms/chunk
  (Phase 2 record: 64.86 ms).
- Eleven surface regions: Forest, Desert, Snow, Mushroom, Jungle, Corruption,
  Crimson, Hallow, Ocean plus the Ashen Flats and Hushwoods variants. Evil
  worlds are exclusive by seed (`set_evil_mode` supports `both`); Hallow is
  gated by the Warden progression flag. Underground biome classification and
  `WorldStructures`/`AdventureContent` stamping are unchanged.
- Agent 2 shipped items, inventory, crafting, boss kind 99 (Hollow Warden) with
  `BossDirector.spawn_encounter`/`spawn_boss`, loot, quests, `NpcService`.
- Agent 3 shipped dialogue panel, target/layer readouts, onboarding, mining
  audio, `NpcBase` presentation and main menu.

## Agent 4 contribution (ported and verified in canonical)

- `scripts/content/adventure_config.gd`, `scripts/content/adventure_content.gd`,
  `data/world/adventure_config.tres`, `debug/adventure_content_check.gd`,
  `debug/generate_adventure_config.gd`.
- One additive call in `scripts/world/world_generator.gd`; no other core file
  touched. Agent 3's `GameHUD` and Agent 2's systems were left untouched.
- The Undercroft (OPTIONAL, non-central): surface broken gate + shaft; upper
  `entry_hall`, `guard_room`, `shattered_gallery`, `hidden_cache` (false mycelium
  wall + clue blooms); `guard_drop` shaft to lower `lower_sanctum` (four-beacon
  boss arena, dais, ore ring) and `ember_vault`. Six rooms, five corridors.
- New this session: `scripts/content/terraria_world_content.gd` (core biome
  identity catalogue + five layer contracts) and `debug/terraria_world_content_check.gd`.

## Verification actually run in canonical

- `terraria_world_content_check.gd`: **PASS** (exit 0) — nine core biomes defined,
  evil exclusivity + Hallow gate, five layers, legacy aliases, honest engine gap.
- `adventure_content_check.gd`: **PASS** (exit 0) — buried
  depth-relative rooms, deterministic stamping, graph connectivity, live carved
  interiors/floors, 8 torches, 4 beacons, false wall + 2 clues, 38+79 ore and
  10 crystal, lower-level streaming on descent, unload/reload identity.
- PASS with content enabled: `world_boot_check`, `mesher_fixture_check`,
  `gameplay_integration_check`, `npc_check`, `survival_check`,
  `world_density_check`, `biome_visuals_check`.
- FAIL but A/B confirmed pre-existing (same failures with content disabled):
  `world_gen_check` (liquid sim), `world_contract_check` (spawn-height/ready
  expectations), `streaming_check` (stale spawn expectations),
  `ashen_flats_check` (canyon depth), `biome_check`, `gun_feel_check`,
  `enemy_behavior_check` (frost slow), `dev_console_check` (spawn enemy).
  These belong to Agents 1/2 in-progress work and were not modified.

## Launch / menu fix (this session)

The old game appeared because the only Godot exe sat beside the OLD
`Terraria3D/project.godot`. Hard-linked exes and `PLAY_3D_TERRARIA.cmd` launchers
now open the canonical project explicitly (see `LAUNCH.md`, verified by
`debug/launch_identity_check.gd`). Menu buttons that "did nothing" were caused
by `main_menu.gd` reading `@onready` `instance.world` before adding the scene to
the tree, plus compile errors in Agent 3's `game_hud.gd`. Both were fixed with
minimal edits; `debug/menu_click_check.gd` now passes for all seven buttons and
`scenes/world/main.tscn` preflights to `ready`.

## Agent 1 Phase 3 deliverables

- `WorldCaves.build_cache` / `is_cave_cached` / `liquid_at_cached`: 16x16
  per-column shaft/ravine/chasm + aquifer table; generator skips the cache for
  chunks above the local surface. Equivalence to the uncached functions is
  asserted in `world_gen_check`.
- `LiquidSim` (`scripts/world/liquid_sim.gd`): local, bounded settling for water
  and lava after player edits; cap 512 pending cells, 12 updates/frame, lava on
  every third tick, unloaded cells skipped, silent writes so flow stays out of
  the save journal. `VoxelWorld.set_block(cell, id, journal := true)` is the
  journal switch; mining/player edits keep the default.
- `WorldSky.stamp_chunk`: deterministic floating islands with soil caps, vines
  and crystal beacons; chunk-seam safe, stamped during generation.
- `_stamp_underground_props`: giant mushrooms, crystal/ice pillars and magma
  vents placed in cave air by underground biome.
- Streaming: nearest-first mesh dispatch and a retry set for chunks whose face
  neighbours are not installed yet.
- Checks: `world_gen_check` PASS (cache equivalence, sky, liquids, perf),
  `world_boot_check` PASS, `debug/vertical_travel_check.gd` added. The vertical
  probe passes the y=150 descent and return; a liquid-heavy y=60 row stays lit
  but unmeshed after 1200 headless frames (open issue). No visual playtest.

## Terraria direction alignment (Agent 2, this session)

- `GameplayBiome` adapter maps world ids to Terraria identities; enemy spawning
  uses identity tables. Reserved ids 6–9 for Corruption/Crimson/Hallow/Ocean.
- Spawn region is the green "Overworld" (internal MIRE id, displayed as
  Overworld), above water, with trees.
- Accessories provide real defence/mining/movement/health bonuses.
- Warden victory sets the `hardmode` world-progression flag.
- NPC roles, shops and housing flags are data-driven (`NpcProfile`).

## Phase 4 — Agent 2 discovery gameplay

Discovery rewards are claimed exactly once through progression flags, mapped
through the item database, and persisted in the existing save. Guarded discovery
sites spawn small biome-themed encounters; exploration sites stay quiet. The
Undercroft room provider is wired and the Hallow remains locked behind the
Underworld flag. `debug/agent2_discovery_check.gd` PASS (20 checks).

## Outstanding integration work (core identity first)

- **Agent 1 (done):** all nine core biomes are generated with signature
  surfaces, evil exclusivity and the Hallow gate; displayed names are core
  identities, with Ashen Flats and Hushwoods kept as regional variants.
  Remaining: biome-specific structures (temple, chasm shrine, flesh altar,
  hallow grove, shipwreck) and biome enemy/loot tables.
- **Agent 2:** expose `ProgressionSystem.has_flag("hollow_warden_defeated")` as
  the Hallow unlock condition; add biome-themed enemy/loot tables for the new
  identities.
- **Agent 3:** present the core biome names in the HUD and layer labels.
- Wire `AdventureConfig.encounters` room ids into Agent 2's `BossDirector` for
  room-entry encounters and boss activation.
- Surface `AdventureConfig.clues`, secret reveal hint and arena intro through
  Agent 3's `GameHUD.show_world_hint()`/dialogue layer.
- Human windowed playtest of navigation and encounter pacing.
- Resolve the pre-existing failing checks listed above (other agents).
- Investigate the deep liquid-heavy chunk that stays light-ready but unmeshed in
  the vertical probe (`debug/vertical_travel_check.gd`).- Human windowed review of the new sky islands, underground formations and liquid flow.

## Phase 4 biome world (Agent 1, this session)

- Underground identity follows the surface: Jungle mudstone + large chambers,
  Corruption ebonstone, Crimson crimstone, Hallow pearlstone + crystal caverns,
  Ocean reefstone + seabed caves. Signature ores: amber/void/blood/radiant
  crystal/pearl. All block ids appended; save v4/block-defs v3 unchanged.
- Biome landmarks: Jungle ziggurat, evil altar rings, Hallow grove, Ocean
  shipwreck; Ocean coral and Hallow radiant spires as props.
- Edge oceans: |x| 3200–3900 blends Ocean to full, flooded to sea level with the
  existing water blocks/LiquidSim; no hard wall.
- Hallow gate corrected: NOT the optional Hollow Warden. Reserved flag
  `underworld_vanquished` for a future Underworld event; dev console
  `hallow on|off` is the debug override. Main no longer listens for Warden flags.
- Enemy metadata already flows through `GameplayBiome`/`EnemyConfig`; new biome
  identities use the corruption/crimson/hallow/ocean/jungle weight tables, but
  no new enemy species or loot tables exist yet.
- Checks: core_biomes, terraria content, world_gen (save/mining/liquids),
  streaming, world_contract, biome, biome_surface, biome_visuals and boot PASS;
  adventure check now waits for the gallery-edge chunk before counting.

## Agent 4 Phase 4 deliverables

- `scripts/content/biome_discovery.gd` (new): reusable room/landmark/cave
  templates with biome-specific palettes for all 11 engine surface ids,
  deterministic 128-block site grid, spawn/Undercroft/WorldStructures separation,
  solid floors, sealed shells, chunk-clipped writes, false-wall secrets.
- `debug/biome_discovery_check.gd` (new): definition/palette/loot validation,
  determinism, chunk writes, descriptor and live streamed-site verification.
- `scripts/content/terraria_world_content.gd`: added
  `ENABLE_BIOME_DISCOVERIES = true` (core content, independent of the optional
  Undercroft).
- `scripts/content/adventure_content.gd`: discovery stamping added to the
  existing generator hook (no new Agent 1 edit) plus a pure `room_center()`
  provider for Agent 2's encounter hook.
- The five shared docs updated; no core-system file was modified.

**Phase 4 verification (all exit 0):** `biome_discovery_check`,
`terraria_world_content_check`, `adventure_content_check`, `world_boot_check`,
`world_gen_check`, `core_biomes_check`, `npc_check`, `mesher_fixture_check`,
`gameplay_integration_check`, `survival_check`, `world_density_check`.

**Still pending:** Agent 2 wiring of discovery loot rewards and the encounter
center provider; Agent 3 discovery hints; human windowed playtest.

## CRITICAL FIX — spawning player could not move (this session)

User report: launched `build/LumenDeepworld.exe`, saw the canonical menu/world,
but could barely move. Diagnosed with a headless input probe: the spawn cell
contained `air` (id 9) but `VoxelWorld.is_solid()` returned true, so
`Player._sweep_axis()` stopped horizontal motion at ~0.18 blocks. Root cause:
`data/blocks/air.tres` never set `is_solid_block = false`, and `BlockLightDef`
defaults that field to `true`. Water/lava already set it correctly.

**Fix:** one line in `data/blocks/air.tres` — `is_solid_block = false`.
Verified: W movement now advances 5 blocks/second continuously; all previously
passing checks still pass. `streaming_check` still fails on stale chunk-y=1
expectations (pre-existing, unrelated). Exported executable rebuilt:
`lumen_deepworld/build/LumenDeepworld.exe` (2026-11-21 00:01) now contains the
fix and all Phase 4 content. The old build (23:08) was stale.

## Branding + HUD cleanup (user feedback)

- Desktop shortcut: `C:\Users\Serge\Desktop\3D Terraria.lnk` → latest build.
- Menu title changed to `3D TERRARIA` and credits relabelled; the internal
  `config/name = "Lumen: Deepworld"` was deliberately left unchanged to avoid
  moving the `user://` save/settings directory.
- HUD: legacy Lumenfall captions (`LUMEN`, `VITALS`, health value) were added
  directly to the CanvasLayer and survived hiding the old panels, and a stale
  `PROJECTOR MODE` hint was shown. Named those captions, hid them in
  `_layout_for_viewport()`, and cleared the legacy caster hint at HUD `_ready`.
- The running game locked `build/LumenDeepworld.exe`, so a NEW standalone build
  `build/3DTerraria.exe` was exported (00:26) and the shortcut repointed to it.
  Close the old game and launch the shortcut. Checks PASS: `menu_click_check`,
  `gameplay_integration_check`, `npc_check`, `world_boot_check`,
  `biome_discovery_check`.
