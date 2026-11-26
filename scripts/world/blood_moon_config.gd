extends Resource
class_name BloodMoonConfig

## Tuning for the Blood Moon event. Terraria rolls this at dusk, about 1 in 9
## nights, only once the player has grown past 120 max health - a cheap
## stand-in for "far enough into the game to survive it".

@export_range(0.0, 1.0, 0.001) var trigger_chance := 0.111
@export_range(0.0, 500.0, 1.0) var min_max_health := 120.0
@export_range(0.05, 1.0, 0.01) var spawn_tick_scale := 0.4
@export_range(1.0, 4.0, 0.05) var max_active_scale := 1.75
@export_range(0.0, 1.0, 0.01) var zombie_bias := 0.65
@export_range(0.1, 1.0, 0.01) var cooldown_scale := 0.4
