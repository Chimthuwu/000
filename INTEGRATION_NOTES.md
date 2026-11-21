
## Agent 3 Phase 2 (Experience) — additions
- Inventory panel (I): hotbar row + 5x8 main grid + equipment slots, click-to-move/swap, tooltips.
- Crafting panel (C): recipe list, ingredients/availability, craft action via CraftingSystem.
- Discovery notifications via ProgressionSystem.discovered / flag_set.
- Audio buses (Master/Music/SFX/World/UI) via SettingsStore.
- Settings persistence: mouse sensitivity, fullscreen, audio volumes, UI scale, continue-on-boot.

## Direction correction audit — Agent 3 (Experience)
- Audited `scripts/ui/*` and `scripts/npcs/*`: no Undercroft/dungeon-centric
  framing in HUD, menus, onboarding, discovery notifications, or NPC
  presentation. Experience layer is generic sandbox-oriented (hotbar, inventory,
  crafting, equipment, boss HUD, discovery toasts, depth/layer readouts).
- Undercroft references are confined to `scripts/content/*`, `scripts/world/*`,
  and enemy/boss data (Agents 1/2/4 scope); HUD only binds to generic boss
  signals (`max_health >= 100`) and discovery signals, not to dungeon-specific
  state.
- Biome identity correction (Ashen/Jungle/etc. must not replace Terraria core
  biomes) is Agent 1/4 domain; no experience-layer changes required. Agent 3
  consumes biome names only via existing `BiomeManager`/`WorldBiomes` APIs.
- No new files or replacement projects created; changes limited to experience
  ownership.

## Reference harvest — SkyUOI/Terraria3D (Godot 4.8 / C# / Zylann Voxel)

Audited the reference at `https://github.com/SkyUOI/Terraria3D` (read-only clone,
not vendored) against the canonical project. Findings are recorded honestly so
future agents do not re-litigate them.

### Adopted / adapted into our GDScript architecture
- **Per-material block material table (concept).** The reference's
  `blocks_library.tres` maps each block to a voxel model + one shared material.
  Our `TerrainAtlas.BLOCK_TILES` already did more (top / side / bottom tiles per
  block). Extended it this pass with:
  - `GRASS_SIDE` dirt-with-fringe side faces for `dirt`, `ashen_soil`,
    `hush_soil` (previously bare dirt sides).
  - `JUNGLE_GRASS_SIDE`, `EVIL_GRASS_SIDE`, `HALLOW_GRASS_SIDE` so biome grasses
    read apart; corrupted/crimson grass now use grass tops instead of ebonstone.
  - `SNOW_SIDE` (snow cap over stone), `WET_SAND` for `ocean_sand`,
    `DEEP_MUD` for Mire silt, `ORE_CRYSTAL` for gem ores.
  - `LEAF_JUNGLE`, `LEAF_EVIL`, `LEAF_HALLOW` (corruption/crimson share evil).
  - `test_wall` mapped to brick (was unmapped).
- **Block-to-block visual variation.** The reference relies on vertex colour; we
  added deterministic per-cell luminance (0.88–1.12) and subtle per-channel hue
  jitter in `ChunkMesher` so large flats break into individual pixel-art blocks.
- **RGB8 clamp fix.** Snow/glow tiles were authored above 1.0 and clamped to flat
  white at import; pushed their detail below white so it survives RGB8.

### Deliberately not adopted
- **Reference atlas pipeline.** `scripts/generate-atlas.py` packs
  `atlas_source.json`, which lists exactly one tile (`dirt.png`); `Atlas.png` is
  a 1024² sheet that is 99% empty and one material is applied to every block
  with `uv1_scale=0.3`. Our procedural atlas (39 tiles, per-face UVs) is more
  complete, so nothing was copied.
- **Zylann Voxel module / VoxelBlockyLibrary / C#.** Incompatible with our
  chunk mesher and Godot 4.7.2; no dependency added.
- **ContentRegistry / ModLoader / Harmony hooks.** A full mod loader is far more
  abstraction than the project needs; our data `.tres` + `ItemDatabase` /
  `RecipeDatabase` already cover content registration.
- **BuffManager.** Our `StatusController` already provides the same generic
  timed-status API used by the HUD.
- **BiomeDetector.** Our `BiomeManager` already has heat/wet anchors, dither
  transitions, evil mutual exclusion and progression-gated Hallow; the
  reference's temperature/humidity idea is already represented.
- **SpawnTables / LootComponent.** Superseded by `EnemyDirector`/`enemy_config`
  and `LootTable` `.tres` data.
- **Assets.** No reference textures were copied. Its only tile is one dirt
  swatch, and its UI/`Terraria.png` art is third-party Terraria-derived; our UI
  is code-built, so importing them would add licensing risk without value.

### Verification
- `debug/terrain_atlas_check.gd` (new): 39 tiles all have pixel detail, atlas is
  deterministic, every non-air block has a material, grass sides differ from
  tops, four biome grass sides are distinct, four leaf families resolve to three
  materials (ebon/crim shared), ore tiles differ from stone, ocean sand differs
  from desert sand, and mesher UVs stay inside every tile cell. **PASS**.
- `gameplay_integration_check.gd` **PASS**, `survival_check.gd` **PASS**,
  `biome_visuals_check.gd` **PASS** after the mesher/atlas changes.
- No in-engine screenshot capture was taken (headless only); the atlas image was
  dumped and inspected visually during development, then the dump helper and
  inspection folder were removed.

### Reference audit note
The direction brief assumed a mature reference full of assets and systems; in
practice it is an early prototype: one terrain tile, a handful of C# systems,
and an unfinished mod loader. The useful ideas were architectural (per-block
material metadata, block-affiliation) and were already present or now added.
