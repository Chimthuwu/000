@echo off
REM Launch the canonical 3D Terraria project (Lumen: Deepworld).
REM Double-click this file. Do NOT double-click the Godot.exe in the parent
REM folder - that one sits beside the old Lumenfall project.godot and opens
REM the original Lumen game.
cd /d "%~dp0"
"%~dp0Godot_v4.7.2-stable_win64.exe" --path "%~dp0"
