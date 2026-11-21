# Launching Terraria 3D

## Canonical project

```
Z:\GITHUB\_GAMES\Terraria3D-Game
```

`project.godot` declares:

```
config/name="Terraria 3D"
run/main_scene="res://scenes/ui/main_menu.tscn"
```

## Launchers

- `PLAY_3D_TERRARIA.cmd` — windowed game.
- `PLAY_3D_TERRARIA_Console.cmd` — game with a diagnostics console.

Both pass `--path "%~dp0"`, so they always load this project regardless of the
working directory.

## Manual launch

```
cd /d Z:\GITHUB\_GAMES\Terraria3D-Game
Godot_v4.7.2-stable_win64.exe --path .
```

Do not launch the `project.godot` in the sibling folder
`Z:\GITHUB\_GAMES\Terraria3D`; that is an older, unrelated project (the
Lumenfall prototype) with its own Git repository.

## Headless validation

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/world_boot_check.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/gameplay_integration_check.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://debug/core_biomes_check.gd
```

## Saves

Saves live under Godot's `user://worlds/` for the project name **Terraria 3D**.
On first launch, `WorldSave.ensure_legacy_user_data_migrated()` copies worlds
and settings from the old sibling data folder without modifying the old folder.
