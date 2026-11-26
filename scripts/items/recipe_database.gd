extends RefCounted
class_name RecipeDatabase

const RECIPE_DIR := "res://data/recipes"

static var _recipes: Array[CraftingRecipe] = []
static var _loaded := false

static func all() -> Array[CraftingRecipe]:
	if not _loaded:
		_reload()
	return _recipes


static func get_recipe(id: StringName) -> CraftingRecipe:
	if not _loaded:
		_reload()
	for recipe in _recipes:
		if recipe.recipe_id == id:
			return recipe
	return null


static func reload() -> void:
	_loaded = false
	_reload()


static func _reload() -> void:
	_loaded = true
	_recipes.clear()
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("RECIPEDB: cannot open %s" % RECIPE_DIR)
		return
	var names: Array[String] = []
	names.assign(dir.get_files())
	names.sort()
	for file_name in names:
		# Godot's export pipeline can convert text resources (.tres) to binary
		# (.res) when packing, so a plain ".tres" filter sees zero files in an
		# exported build even though the same .tres loads fine from source.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := RECIPE_DIR.path_join(file_name)
		var resource := load(path)
		if not resource is CraftingRecipe:
			push_error("RECIPEDB: %s is not a CraftingRecipe" % path)
			continue
		var recipe := resource as CraftingRecipe
		if recipe.recipe_id == &"":
			recipe.recipe_id = StringName(file_name.get_basename())
		_recipes.append(recipe)
	print("RECIPEDB: loaded %d recipes" % _recipes.size())
