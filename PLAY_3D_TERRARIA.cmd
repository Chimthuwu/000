@echo off
REM Launch Terraria 3D from this folder.
REM Keep this file beside project.godot; Godot resolves res:// from --path.
cd /d "%~dp0"
"%~dp0Godot_v4.7.2-stable_win64.exe" --path "%~dp0"
