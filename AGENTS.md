# PROJECT: TERRARIA 3D

This repository is **Terraria 3D**, a 3D interpretation of Terraria built with
Godot 4.7.2 and GDScript.

## Non-negotiable identity

- Never describe or brand the project as Lumen, Lumen Deepworld, Lumenfall or a
  horror sandbox.
- Do not drift back toward survival-horror design, a dungeon-crawler identity,
  a generic Minecraft clone, or the legacy Ashen Flats/Hushwoods/Mire framing.
- Terraria 3D is the sole game identity in code, UI, documentation, metadata,
  save metadata and build output.
- The legacy content ID `lumen_crystal` is retained only for save compatibility;
  its display name is **Radiant Crystal** and new documents should call it that.

## Direction

All development decisions must serve Terraria-style:

- exploration and discovery
- mining and building
- crafting, equipment, inventories and hotbars
- combat, enemies, bosses and loot
- biomes, vertical layers and world generation
- NPCs, services, quests and progression
- day/night, events and Terraria-like world content

Core surface roster: **Forest, Desert, Jungle, Corruption, Crimson, Hallow,
Snow, Ocean and Mushroom**. Corruption and Crimson are mutually exclusive by
default; Hallow is progression-gated.

## Engineering rules

- Keep Godot 4.7.2 and GDScript. Do not convert to C#, upgrade Godot, or add the
  Zylann voxel module.
- Extend existing `VoxelWorld`, `BiomeManager`, `InventoryModel`, `ItemDef`,
  `CraftingSystem`, `NightManager`, `EnemyDirector`, save and rendering systems.
  Do not create parallel duplicate systems.
- Preserve numeric block palette order and existing save compatibility. Add new
  block IDs at the end.
- A feature is complete only when it works in the running game. Report exactly
  what was visually verified and what was only tested headlessly.
- Do not commit, push, reset, clean or force-checkout unless the user asks.

## Git repository safety

This directory is its own Git repository (remote
`https://github.com/Chimthuwu/000.git`). The sibling folder
`Z:\GITHUB\_GAMES\Terraria3D` is a *different* project with a *different* remote
(`Chimthuwu/Lumen`) and a long history of its own. Before touching Git:

- Enter this canonical directory first and stay in it for every Git command.
- Run `git rev-parse --show-toplevel` and confirm it prints exactly
  `Z:/GITHUB/_GAMES/Terraria3D-Game`.
- Run `git remote get-url origin` and confirm it prints exactly
  `https://github.com/Chimthuwu/000.git`.
- Never stage from an ancestor or sibling directory, and never run `git add -A`
  from `Z:\GITHUB\_GAMES`, `Z:\GITHUB` or any other parent folder.
- Never assume a folder name proves repository identity; check the root and the
  remote instead.
- Never commit or push without explicit user permission.

The helper `CHECK_REPO.cmd` in this folder performs those checks and exits
non-zero when run outside the canonical repository or against the wrong remote.
Run it before staging anything.
