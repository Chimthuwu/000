# Reference Harvest — SkyUOI/Terraria3D

Reference: <https://github.com/SkyUOI/Terraria3D> (MIT, copyright SkyUOI).

## Imported

- `src/ui/main_game_ui/hearts/Heart_Fill.png` (filled)
- `Heart_Middle.png` (empty)

These are wired into `GameHUD` as a ten-heart health row. The old health bar is
retired. Files live in `res/terraria3d/ui/hearts/`; the reference MIT license is
copied to `res/terraria3d/LICENSE-SkyUOI-Terraria3D.txt`.

## Reviewed but not imported

- **Terrain tiles:** `resources/tiles/Atlas.png` is 1024x1024 but effectively
  blank; `dirt.png` is a single 16x16 tile. This is not a usable Terraria-style
  terrain set and is weaker than the existing generated 39-tile atlas with
  per-face UVs, biome grass sides and nearest filtering.
- **Menu background / logo / screenshot:** the reference includes a real
  Terraria title screenshot and logo. Those are franchise artwork/trademarks,
  not appropriate as this project's identity, so the menu keeps its own
  original text title.
- **C# systems:** `Inventory`, `Blocks`, `Biomes`, `Generator`, `EntityData`,
  buffs, achievements, modding and world saving are C# and depend on a custom
  Godot 4.8 build with the Zylann voxel module. Porting them would conflict with
  the existing GDScript `VoxelWorld`, `InventoryModel`, `ItemDef`,
  `CraftingSystem`, `EnemyDirector` and save systems. Their data-model ideas were
  reviewed; no duplicate system was introduced.
- **Sun/moon and inventory panel art:** reviewed. The sun/moon sprites are
  Terraria UI art tied to the reference's 2D menu; the inventory panel is a
  plain 44x44 blue square. Neither improves the current HUD enough to justify
  another asset dependency. The heart row is the genuine visible harvest.

## Adapted ideas

- Terraria-style heart presentation for health, instead of a generic bar.
- The reference's early block/biome item data confirmed our direction toward a
  core nine-biome roster; our existing engine already implements it through
  `BiomeManager`, `WorldBiomes` and `TerrariaWorldContent`.

## Applied art direction (original geometry, not copied assets)

- **Jungle:** the reference's biome identity informed a broadleaf silhouette.
  The implementation is original `WorldVegetation` geometry: thick trunks,
  buttress fins, green branch canopies and hanging vines. No horror-era claw
  trees remain as Jungle surface vegetation.
- **Sky islands:** rebuilt as layered floating terrain with a grass cap, dirt
  and stone bands, a tapered deepstone underside and stone stalactites. This is
  an original interpretation of the Terraria silhouette; no reference mesh or
  texture was used.
- **Terrain:** the existing generated 256x256 pixel-art atlas remains the
  material source because the reference atlas is effectively blank. The
  reference's atlas/UV structure was reviewed, but its actual tiles are not a
  usable replacement.

## Verification of harvested content

- The two heart sprites are the only image files imported from the reference.
  They are visible in `debug/evidence/terraria3d_hud_crop.png` and the current
  biome captures.
- The vegetation and sky-island work is visually inspected in
  `debug/evidence/biome_contact_small_1.png`, `biome_contact_small_2.png` and
  `biome_sky_final.png`; `debug/sky_island_check.gd` guards the layered cap and
  underside deterministically.
- The reference's C# gameplay systems and blank terrain atlas remain
  intentionally unported. See the sections above for why.
