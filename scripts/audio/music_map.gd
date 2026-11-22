extends Resource
class_name MusicMap

## Editable mapping from world state to music. The music manager resolves a
## category ("surface_day", "underground", ...) from world state and looks it up
## here. Leave an entry empty to use the built-in procedural track for that
## category; point it at a licensed or original audio file to replace it without
## touching any code. Categories left empty use the built-in procedural synth.
##
## `tracks` is keyed by the categories printed in the music log, so an artist
## can match a real track to a category by reading the log during play:
##   surface_day  surface_night  underground  cave  jungle  underground_jungle
##   desert  snow  ocean  mushroom  hallow  corruption  crimson
##   underground_corruption  underground_crimson  underground_hallow
##   underworld  space  boss
##
## `ambience` is keyed by "wind", "forest", "water", "cave", "rain", "lava".

## Current contents point at the Terraria soundtrack files in res/audio/music.
@export var tracks: Dictionary = {}
@export var ambience: Dictionary = {}
## Seconds for a crossfade. Both players ramp together, so the total loudness
## stays roughly constant instead of doubling.
@export var fade_seconds := 1.5
## A new category must hold this long before the track changes, which stops
## rapid flip-flopping when the player walks along a biome border.
@export var switch_hold_seconds := 0.9


func track_for(category: String) -> String:
	return String(tracks.get(category, ""))


func ambience_for(category: String) -> String:
	return String(ambience.get(category, ""))
