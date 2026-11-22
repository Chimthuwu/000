extends Control
class_name ManaStar

## A single Terraria-style mana star for the HUD. Drawn procedurally so the HUD
## needs no harvested mana art: a four-point sparkle with a dark outline, filled
## from empty to full by scaling the bright core (Terraria ships partial-star
## sprites for the same effect).

const FILL := Color(0.35, 0.62, 1.0, 1.0)
const FILL_CORE := Color(0.72, 0.90, 1.0, 1.0)
const EMPTY := Color(0.16, 0.22, 0.42, 0.95)
const OUTLINE := Color(0.05, 0.09, 0.22, 0.95)

var ratio := 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _star(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(8):
		var angle := -PI * 0.5 + float(index) * PI * 0.25
		var r := radius if index % 2 == 0 else radius * 0.32
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.0
	var outer := _star(center, radius)
	draw_colored_polygon(outer, EMPTY)
	if ratio > 0.02:
		var core_radius := radius * lerpf(0.42, 0.86, ratio)
		draw_colored_polygon(_star(center, core_radius), FILL)
		if ratio > 0.55:
			draw_colored_polygon(_star(center, radius * 0.34), FILL_CORE)
	var closed := outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, OUTLINE, 1.0, true)
