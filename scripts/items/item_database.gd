extends RefCounted
class_name ItemDatabase

## Loads every ItemDef .tres under res://data/items once and caches it by id.
## Gameplay state stores only StringName ids; the UI resolves them through here.

const ITEM_DIR := "res://data/items"

# Agent 1's MiningSystem drops the block's own id when a block has no explicit
# drop_block_id. These aliases map world block ids onto the gameplay item ids
# without duplicating an inventory or changing Agent 1's block data.
const BLOCK_DROP_ALIASES: Dictionary = {
	&"coal_ore": &"coal",
	&"deepstone": &"stone",
	&"cavern_stone": &"stone",
	&"ashen_soil": &"dirt",
	&"rotted_dirt": &"dirt",
	&"rotted_ashen_soil": &"dirt",
	&"hush_soil": &"dirt",
	&"canyon_gravel": &"stone",
	&"dead_wood": &"wood",
	&"pale_wood": &"wood",
	&"beacon": &"torch",
	&"toxic_silt": &"mire_mud",
	&"jungle_grass": &"dirt",
	&"corrupted_grass": &"dirt",
	&"crimson_grass": &"dirt",
	&"hallowed_grass": &"dirt",
	&"ocean_sand": &"dirt",
	&"ebonstone": &"stone",
	&"crimstone": &"stone",
	&"pearlstone": &"stone",
	&"jungle_leaves": &"wood",
	&"ebon_leaves": &"wood",
	&"crim_leaves": &"wood",
	&"hallow_leaves": &"wood",
	&"jungle_mudstone": &"stone",
	&"reefstone": &"stone",
	&"coral": &"dirt",
	&"amber_ore": &"iron_ore",
	&"void_ore": &"silver_ore",
	&"blood_ore": &"gold_ore",
	&"radiant_crystal_ore": &"lumen_crystal",
	&"pearl_ore": &"silver_ore",
	&"ash": &"dirt",
	&"obsidian": &"stone",
	&"hellstone": &"stone",
	# An open door is a block *state*; breaking it still yields the door.
	&"wood_door_open": &"wood_door",
}

static var _items: Dictionary = {}
static var _loaded := false

static func all() -> Dictionary:
	if not _loaded:
		_reload()
	return _items


static func get_item(id: StringName) -> ItemDef:
	if not _loaded:
		_reload()
	return _items.get(id) as ItemDef


static func has(id: StringName) -> bool:
	return get_item(id) != null


static func stack_limit(id: StringName) -> int:
	var def := get_item(id)
	return def.stack_limit if def != null else 99


## Normalises a MiningSystem drop id (a block id) to an inventory item id.
static func item_id_for_drop(block_id: StringName) -> StringName:
	return BLOCK_DROP_ALIASES.get(block_id, block_id)


static func reload() -> void:
	_loaded = false
	_reload()


static func _reload() -> void:
	_loaded = true
	_items.clear()
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_error("ITEMDB: cannot open %s" % ITEM_DIR)
		return
	for file_name in dir.get_files():
		# Godot's export pipeline can convert text resources (.tres) to binary
		# (.res) when packing, so a plain ".tres" filter sees zero files in an
		# exported build even though the same .tres loads fine from source.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := ITEM_DIR.path_join(file_name)
		var resource := load(path)
		if not resource is ItemDef:
			push_error("ITEMDB: %s is not an ItemDef" % path)
			continue
		var def := resource as ItemDef
		if def.item_id == &"":
			def.item_id = StringName(file_name.get_basename())
		if _items.has(def.item_id):
			push_error("ITEMDB: duplicate item id %s" % String(def.item_id))
			continue
		_items[def.item_id] = def
	print("ITEMDB: loaded %d item definitions" % _items.size())
