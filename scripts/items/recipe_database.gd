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
		# In an exported build Godot keeps data/recipes/foo.tres as a binary
		# resource but lists the directory entry as "foo.tres.remap"; the
		# original "foo.tres" path still has to be the one passed to load()
		# so the engine's remap table can redirect it to the packed data.
		var resource_name := file_name
		if resource_name.ends_with(".remap"):
			resource_name = resource_name.substr(0, resource_name.length() - len(".remap"))
		if not (resource_name.ends_with(".tres") or resource_name.ends_with(".res")):
			continue
		var path := RECIPE_DIR.path_join(resource_name)
		var resource := load(path)
		if not resource is CraftingRecipe:
			push_error("RECIPEDB: %s is not a CraftingRecipe" % path)
			continue
		var recipe := resource as CraftingRecipe
		if recipe.recipe_id == &"":
			recipe.recipe_id = StringName(resource_name.get_basename())
		_recipes.append(recipe)
	print("RECIPEDB: loaded %d recipes" % _recipes.size())
