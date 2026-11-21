# Terraria 3D

A 3D interpretation of Terraria built with Godot 4.7.2 and GDScript. Explore,
mine, build, craft, fight and progress through a streamed voxel world with
Terraria-style biomes, layers, enemies, NPCs and bosses.

**Project identity:** Terraria 3D is the sole identity of this project. It is
not a continuation of Lumen Deepworld, a horror game, or a generic Minecraft-like
sandbox. Development decisions must serve Terraria-style exploration, mining,
building, crafting, equipment, combat, biomes, enemies, bosses, NPCs, progression
and world content.

## Project location

The canonical project folder is:

```
Z:\GITHUB\_GAMES\Terraria3D-Game
```

The sibling folder `Z:\GITHUB\_GAMES\Terraria3D` contains an older, unrelated
project (the Lumenfall prototype). Launch this one with `--path` or the launcher
in this folder; this directory is its own Git repository.

## Run

Requires Godot 4.7.2 (GL Compatibility renderer).

```
Godot_v4.7.2-stable_win64_console.exe --path . --headless --script res://debug/world_boot_check.gd
Godot_v4.7.2-stable_win64.exe --path .
```

Or double-click `PLAY_3D_TERRARIA.cmd`.

## Controls

- WASD move, Shift sprint, Space jump, mouse look
- Third-person camera by default; V toggles first person
- Left mouse: mine with a pickaxe or attack with a weapon
- Right mouse: place the selected block
- 1-9 and 0: hotbar slots; wheel cycles the hotbar
- I inventory, C crafting, E interact/talk, F torch light
- K save, J load, F3 debug readout, ESC pause, ~ dev console

## Current content

- Deterministic 256-block-high voxel world with a streamed surface, underground,
  caverns, a lava-and-ash Underworld and sky islands.
- Nine core surface identities: Forest, Desert, Jungle, Corruption, Crimson,
  Hallow, Snow, Ocean and Mushroom. Corruption and Crimson are mutually
  exclusive by default; Hallow is progression-gated.
- Pixel-art terrain atlas with per-face UVs, top/side/bottom tiles, nearest
  filtering and biome-specific grass and foliage tiles.
- Mining and building, sparse save journal, crafting, inventory, hotbar,
  equipment, weapons, mana, health, status effects, enemies, bosses, NPC shops
  and quests.
- Terraria-style hearts on the HUD, using the filled/empty MIT-licensed sprites harvested from
  [SkyUOI/Terraria3D](https://github.com/SkyUOI/Terraria3D).

## Reference harvest

The reference repository is a Godot 4.8 C# project built around the Zylann
voxel module. Our project stays on Godot 4.7.2/GDScript and keeps its existing
world architecture. We imported the useful UI heart sprites with attribution;
the reference's 1024x1024 tile atlas is effectively blank and its only real
terrain tile is one 16x16 dirt image, so it cannot replace our generated
terrain atlas. Its C# inventory, biome and entity systems were reviewed but not
copied because equivalent GDScript systems already exist here. See
`docs/REFERENCE_HARVEST.md`.

## Validation

Headless checks live in `debug/`. Start with:

```
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/world_boot_check.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/gameplay_integration_check.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/core_biomes_check.gd
```

Visual evidence is stored under `debug/evidence/`. A headless pass does not
count as visual verification.
