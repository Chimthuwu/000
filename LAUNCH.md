# How to launch the 3D Terraria game

## Canonical project

`Z:\GITHUB\_GAMES\Terraria3D\lumen_deepworld\`

Its `project.godot` declares:

```
config/name="Lumen: Deepworld"
run/main_scene="res://scenes/ui/main_menu.tscn"
```

## Why the old Lumen game appeared

Godot resolves `project.godot` from its working directory (or `--path`). The only
Godot executables originally lived in the **parent** folder:

```
Z:\GITHUB\_GAMES\Terraria3D\Godot_v4.7.2-stable_win64.exe
Z:\GITHUB\_GAMES\Terraria3D\project.godot   <-- OLD "Lumenfall" game
```

Double-clicking that exe therefore loaded the old `Lumenfall` project and its old
`res://scenes/world/main.tscn`. The new project was never being opened.

## Fix applied

1. Hard-linked both Godot executables into `lumen_deepworld\` (same binaries, no
   extra disk space). Double-clicking `lumen_deepworld\Godot_v4.7.2-stable_win64.exe`
   now resolves the canonical `project.godot`.
2. Added launchers that pass an explicit `--path`:
   - `Terraria3D\RUN_TERRARIA3D.bat` (recommended: checks both paths, then runs
     the canonical project with `--path`)
   - `lumen_deepworld\PLAY_3D_TERRARIA.cmd` (windowed)
   - `lumen_deepworld\PLAY_3D_TERRARIA_Console.cmd` (with diagnostics console)
   - `Terraria3D\PLAY_3D_TERRARIA.cmd` (from the parent folder)

## Verified launch identities

| Route | Project opened | Main scene |
| --- | --- | --- |
| `lumen_deepworld\Godot_..._console.exe --headless --script debug/launch_identity_check.gd` | `Lumen: Deepworld` | `res://scenes/ui/main_menu.tscn` |
| parent `Godot_..._console.exe --path lumen_deepworld ...` | `Lumen: Deepworld` | `res://scenes/ui/main_menu.tscn` |

`debug/launch_identity_check.gd` prints the resolved project name, main scene and
project root, so this can be re-checked at any time.

## Windowed visual verification (2026-11-20)

No exported game build exists in either folder (no `.pck`, no export presets);
the only executables are the hard-linked Godot 4.7.2 editor binaries. The game
is therefore launched through Godot with an explicit `--path`.

Ran with rendering (not headless):

- `debug/capture_menu.gd` loaded the canonical menu and saved
  `.captures/menu_capture.png`: black screen, title **LUMEN: DEEWORLD**, buttons
  PLAY / CONTINUE / NEW WORLD / WORLD SELECTION / SETTINGS / CONTROLS /
  CREDITS / EXIT.
- `debug/capture_world.gd` booted `scenes/world/main.tscn`, waited for spawn and
  saved `.captures/world_preview.jpg`: 3D voxel terrain (Ashen Flats), health and
  stamina bars, Excavator cartridge panel, hotbar (wood/dirt/torch), depth/hardness
  target readout, onboarding hints. `generated=true`, `spawned=true`, 537 chunks
  resident at capture time.

The windowed launcher smoke test (`RUN_TERRARIA3D.bat --quit-after 120`) exited 0
with the GL Compatibility renderer on the real GPU.

## Exported Windows build (2026-11-20)

`export_presets.cfg` defines one preset, **Windows Desktop**, which writes a
single self-contained executable (PCK embedded, no loose `.pck`):

- Build: `lumen_deepworld\build\LumenDeepworld.exe` (~105 MB) — double-click to
  play, no editor and no project files required.
- Rebuild with:
  ```
  Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    --export-release "Windows Desktop" "build/LumenDeepworld.exe"
  ```
  This needs the Godot 4.7.2 export templates (`4.7.2.stable`) installed.
- Verified: the export exited 0; the executable booted headless (exit 0, no
  script errors) both from `build/` and from a copied folder containing no
  `project.godot`, proving it is standalone.
- `build/` is git-ignored; `debug/` and `.captures/` are excluded from the PCK.

## Menu buttons (fixed this session)

`PLAY`, `CONTINUE`, `NEW WORLD`, `WORLD SELECTION`, `SETTINGS`, `CONTROLS` and
`CREDITS` were all verified with `debug/menu_click_check.gd`. Two defects were
fixed with minimal edits to Agent 3's files:

1. `main_menu.gd::_start_world()` read `instance.world` (an `@onready` var) before
   the scene entered the tree, so the handler aborted and the menu appeared dead.
   It now resolves `VoxelWorld` by node path before `add_child()` and reports
   failures on the status label instead of failing silently.
2. `game_hud.gd` had undefined `ACCENT_LUMEN` / `_show_toast()` and duplicated
   `add_child()` for the inventory and crafting panels. These are now defined /
   removed. `scenes/world/main.tscn` preflights to `ready`.

Run `gda script run res://debug/menu_click_check.gd` to re-check all buttons.
