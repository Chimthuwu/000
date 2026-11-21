extends RefCounted
class_name TreeAtlas

## Deterministic pixel-art tree atlas. It is deliberately separate from the
## terrain atlas because foliage needs real cutout alpha and trunks need a
## different texel scale. Colour comes from the vegetation vertex tint; the
## atlas supplies bark grain and leaf silhouettes.

const TILE_SIZE := 16
const COLUMNS := 4
const ROWS := 4
const SIZE := TILE_SIZE * COLUMNS
const INSET := 0.04

enum Tile {
	BARK = 0,
	LEAF = 1,
	LEAF_JUNGLE = 2,
	NEEDLE = 3,
	LEAF_EVIL = 4,
	LEAF_HALLOW = 5,
	FROND = 6,
	MUSHROOM = 7,
}

static var _texture: ImageTexture


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(build_image())
	return _texture


static func build_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for tile in range(8):
		_paint_tile(image, tile)
	return image


static func uv(tile: int, local: Vector2) -> Vector2:
	var column := tile % COLUMNS
	var row := floori(float(tile) / float(COLUMNS))
	var inside := Vector2(
		clampf(local.x, INSET, 1.0 - INSET),
		clampf(local.y, INSET, 1.0 - INSET)
	)
	return Vector2((float(column) + inside.x) / float(COLUMNS), (float(row) + inside.y) / float(ROWS))


static func _paint_tile(image: Image, tile: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17011 + tile * 3571
	var ox := (tile % COLUMNS) * TILE_SIZE
	var oy := floori(float(tile) / float(COLUMNS)) * TILE_SIZE
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var color := Color(0, 0, 0, 0)
			match tile:
				Tile.BARK:
					color = _bark(x, y, rng)
				Tile.LEAF, Tile.LEAF_JUNGLE, Tile.LEAF_EVIL, Tile.LEAF_HALLOW:
					color = _leaf(x, y, rng, tile)
				Tile.NEEDLE:
					color = _needle(x, y, rng)
				Tile.FROND:
					color = _frond(x, y, rng)
				Tile.MUSHROOM:
					color = _mushroom(x, y, rng)
			image.set_pixel(ox + x, oy + y, color)


static func _bark(x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var value := 0.62 + rng.randf() * 0.22
	if x % 4 == 0:
		value *= 0.72
	if x % 7 == 2 and y % 5 < 3:
		value *= 0.82
	if (x * 5 + y * 3) % 19 == 0:
		value = 0.42
	if y == 0 or y == TILE_SIZE - 1:
		value *= 0.80
	return Color(value, value, value, 1.0)


static func _leaf(x: int, y: int, rng: RandomNumberGenerator, tile: int) -> Color:
	var cx := float(x) - 7.5
	var cy := float(y) - 7.5
	var shape := cx * cx * 1.15 + cy * cy
	var ragged := shape + rng.randf_range(-7.0, 7.0)
	var cutoff := 44.0
	if tile == Tile.LEAF_JUNGLE:
		cutoff = 58.0
	elif tile == Tile.LEAF_EVIL:
		cutoff = 35.0
	elif tile == Tile.LEAF_HALLOW:
		cutoff = 48.0
	if ragged > cutoff:
		return Color(0, 0, 0, 0)
	if rng.randf() < 0.075:
		return Color(0, 0, 0, 0)
	var value := 0.72 + rng.randf() * 0.28
	if cy > 3.0:
		value *= 0.78
	if (x * 3 + y * 5) % 11 == 0:
		value *= 1.18
	return Color(value, value, value, 1.0)


static func _needle(x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var diagonal := absf((float(x) - 7.5) + (float(y) - 7.5) * 1.4)
	var other := absf((float(x) - 7.5) - (float(y) - 7.5) * 0.8)
	if diagonal > 9.5 and other > 8.5:
		return Color(0, 0, 0, 0)
	if rng.randf() < 0.08:
		return Color(0, 0, 0, 0)
	var value := 0.66 + rng.randf() * 0.30
	if y % 4 == 0:
		value *= 0.70
	return Color(value, value, value, 1.0)


static func _frond(x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var t := float(x) / float(TILE_SIZE - 1)
	var center := 7.0 + sin(t * PI) * 3.0
	var width := 1.3 + sin(t * PI) * 3.0
	if absf(float(y) - center) > width:
		return Color(0, 0, 0, 0)
	if rng.randf() < 0.10:
		return Color(0, 0, 0, 0)
	var value := 0.62 + rng.randf() * 0.34
	if y % 3 == 0:
		value *= 0.76
	return Color(value, value, value, 1.0)


static func _mushroom(x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var cx := float(x) - 7.5
	var cy := float(y) - 8.0
	if absf(cx) > 6.5 or cy < -7.0 or cy > 6.0:
		return Color(0, 0, 0, 0)
	var value := 0.76 + rng.randf() * 0.18
	if cy < -3.0:
		value = 0.92
	if (x * 3 + y * 2) % 17 == 0:
		value = 0.44
	return Color(value, value, value, 1.0)
