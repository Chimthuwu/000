extends RefCounted
class_name ItemIcons

## Generated pixel-art item icons. Blocks reuse their real terrain-atlas tile,
## tinted with the block palette colour, so what the hotbar shows matches the
## block in the world. Tools, weapons, armour and consumables get small original
## glyphs instead of abbreviated item names.

const SIZE := 16

static var _cache: Dictionary = {}


static func icon_for(item_id: StringName) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id]
	var texture := _build(item_id)
	_cache[item_id] = texture
	return texture


static func clear_cache() -> void:
	_cache.clear()


static func _build(item_id: StringName) -> Texture2D:
	var def := ItemDatabase.get_item(item_id)
	if def == null:
		return _placeholder(Color(0.6, 0.6, 0.6))
	if item_id == &"torch":
		return _torch_icon()
	if def.place_block != &"":
		var block_path := "res://data/blocks/%s.tres" % String(def.place_block)
		if ResourceLoader.exists(block_path):
			var block := load(block_path) as BlockLightDef
			if block != null:
				return _block_icon(def.place_block, block.albedo)
	match def.category:
		ItemDef.Category.TOOL:
			return _tool_icon(def)
		ItemDef.Category.WEAPON:
			return _weapon_icon(def)
		ItemDef.Category.ARMOR, ItemDef.Category.ACCESSORY:
			return _armor_icon(def)
		ItemDef.Category.CONSUMABLE:
			return _consumable_icon(def)
		ItemDef.Category.QUEST:
			return _star_icon(Color(1.0, 0.82, 0.28))
		_:
			return _material_icon(def)


## A torch is furniture, not terrain, so it gets its own glyph instead of the
## generic tinted block tile (which just reads as an orange plank).
static func _torch_icon() -> Texture2D:
	var image := _blank(Color(0.10, 0.09, 0.10))
	for y in range(8, 15):
		for x in range(7, 9):
			image.set_pixel(x, y, Color(0.42, 0.30, 0.18))
	var flame := Color(1.0, 0.62, 0.18)
	var flame_core := Color(1.0, 0.86, 0.42)
	for x in range(5, 11):
		for y in range(2, 9):
			var dx := absf(float(x) - 7.5)
			var dy := float(y) - 5.0
			if dx + absf(dy) * 0.55 < 2.6:
				image.set_pixel(x, y, flame)
	for x in range(6, 10):
		for y in range(3, 8):
			var dx := absf(float(x) - 7.5)
			var dy := float(y) - 5.0
			if dx + absf(dy) * 0.55 < 1.4:
				image.set_pixel(x, y, flame_core)
	return ImageTexture.create_from_image(image)


static func _block_icon(block_id: StringName, albedo: Color) -> Texture2D:
	var atlas := TerrainAtlas.build_image()
	var tile := TerrainAtlas.tiles_for_block(block_id).y
	var rect := TerrainAtlas.tile_rect(tile)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in range(SIZE):
		for x in range(SIZE):
			var source := atlas.get_pixel(int(rect.position.x) + x, int(rect.position.y) + y)
			var shade := clampf(source.r, 0.0, 1.35)
			var color := Color(albedo.r * shade, albedo.g * shade, albedo.b * shade)
			if x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1:
				color = color.darkened(0.45)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _metal_color(tier: int) -> Color:
	var colors := [
		Color(0.62, 0.44, 0.26),
		Color(0.80, 0.48, 0.30),
		Color(0.72, 0.74, 0.78),
		Color(0.86, 0.90, 0.96),
		Color(1.0, 0.82, 0.36),
		Color(0.72, 0.46, 0.92),
	]
	return colors[clampi(tier, 0, colors.size() - 1)]


static func _tool_icon(def: ItemDef) -> Texture2D:
	var image := _blank(Color(0.16, 0.12, 0.10))
	var head := _metal_color(def.tool_tier)
	# Wooden haft running bottom-left to top-right.
	for i in range(3, 13):
		_line(image, i, 15 - i + 1, i + 1, 15 - i, Color(0.52, 0.34, 0.18))
	if def.tool_type == "axe":
		for x in range(8, 14):
			for y in range(1, 7):
				if (x - 8) + (y - 1) < 7:
					image.set_pixel(x, y, head)
	else:
		for x in range(8, 14):
			for y in range(1, 6):
				if absi(x - 11) + y < 5:
					image.set_pixel(x, y, head)
			image.set_pixel(x, 1, head.lightened(0.25))
	return ImageTexture.create_from_image(image)


static func _weapon_icon(def: ItemDef) -> Texture2D:
	var image := _blank(Color(0.16, 0.12, 0.10))
	var accent := Color(0.82, 0.86, 0.94)
	if def.attack != null:
		accent = def.attack.accent_color
	# Blade.
	for i in range(2, 13):
		image.set_pixel(i, 15 - i, accent)
		image.set_pixel(i + 1, 15 - i, accent.darkened(0.22))
	# Guard and grip.
	for i in range(2, 6):
		image.set_pixel(i + 3, 9 - i + 4, Color(0.62, 0.44, 0.20))
	for i in range(0, 4):
		image.set_pixel(2 + i, 13 - i, Color(0.42, 0.28, 0.14))
	return ImageTexture.create_from_image(image)


static func _armor_icon(def: ItemDef) -> Texture2D:
	var image := _blank(Color(0.14, 0.12, 0.14))
	var metal := _metal_color(2)
	if def.category == ItemDef.Category.ACCESSORY:
		for x in range(SIZE):
			for y in range(SIZE):
				var dx := float(x - 8) + 0.5
				var dy := float(y - 8) + 0.5
				var radius := sqrt(dx * dx + dy * dy)
				if radius > 4.2 and radius < 6.6:
					image.set_pixel(x, y, Color(0.98, 0.78, 0.34) if y < 8 else Color(0.72, 0.54, 0.20))
	else:
		for x in range(3, 13):
			for y in range(3, 13):
				if (x < 5 or x > 10) and y < 5:
					continue
				var edge := x == 3 or x == 12 or y == 3 or y == 12
				image.set_pixel(x, y, metal.darkened(0.35) if edge else metal)
		for x in range(7, 9):
			image.set_pixel(x, 5, Color(0.20, 0.18, 0.22))
	return ImageTexture.create_from_image(image)


static func _consumable_icon(def: ItemDef) -> Texture2D:
	var image := _blank(Color(0.10, 0.12, 0.14))
	var liquid := Color(0.92, 0.24, 0.34)
	if def.mana_restore > 0.0:
		liquid = Color(0.32, 0.52, 1.0)
	elif def.heal_amount > 0.0 and def.mana_restore <= 0.0:
		liquid = Color(0.96, 0.32, 0.28)
	for x in range(5, 11):
		for y in range(6, 14):
			image.set_pixel(x, y, liquid.darkened(0.25 if x == 5 or x == 10 else 0.0))
	for x in range(7, 9):
		image.set_pixel(x, 3, Color(0.78, 0.70, 0.52))
	for x in range(6, 10):
		image.set_pixel(x, 2, Color(0.62, 0.50, 0.34))
	return ImageTexture.create_from_image(image)


static func _material_icon(def: ItemDef) -> Texture2D:
	var image := _blank(Color(0.13, 0.12, 0.11))
	var color := _rarity_color(def.rarity)
	for x in range(4, 12):
		for y in range(6, 11):
			var edge := x == 4 or x == 11 or y == 6 or y == 10
			image.set_pixel(x, y, color.darkened(0.35) if edge else color)
	image.set_pixel(6, 7, color.lightened(0.35))
	image.set_pixel(9, 9, color.darkened(0.2))
	return ImageTexture.create_from_image(image)


static func _star_icon(color: Color) -> Texture2D:
	var image := _blank(Color(0.12, 0.10, 0.10))
	for x in range(SIZE):
		for y in range(SIZE):
			var dx := absf(float(x) - 7.5)
			var dy := absf(float(y) - 7.5)
			if dx + dy < 3.0 or (dx < 1.0 and dy < 7.0) or (dy < 1.0 and dx < 7.0):
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _rarity_color(rarity: int) -> Color:
	var colors := [
		Color(0.78, 0.78, 0.74),
		Color(0.90, 0.62, 0.30),
		Color(0.66, 0.82, 0.98),
		Color(0.96, 0.82, 0.36),
		Color(0.86, 0.48, 0.92),
	]
	return colors[clampi(rarity, 0, colors.size() - 1)]


static func _placeholder(color: Color) -> Texture2D:
	var image := _blank(color)
	return ImageTexture.create_from_image(image)


static func _blank(color: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image


static func _line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in range(steps + 1):
		var t := float(i) / float(maxi(steps, 1))
		var x := clampi(roundi(lerpf(float(x0), float(x1), t)), 0, SIZE - 1)
		var y := clampi(roundi(lerpf(float(y0), float(y1), t)), 0, SIZE - 1)
		image.set_pixel(x, y, color)
