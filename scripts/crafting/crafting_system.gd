extends RefCounted
class_name CraftingSystem

## Recipe-driven crafting. Validation and consumption are atomic: a recipe
## either fully succeeds (ingredients removed, outputs added) or changes nothing.

var inventory: InventoryModel
var progression: ProgressionSystem
var gateway: WorldGateway


func _init(inv: InventoryModel, prog: ProgressionSystem, gw: WorldGateway) -> void:
	inventory = inv
	progression = prog
	gateway = gw


func station_available(station: String) -> bool:
	if station == &"none" or station == "":
		return true
	if gateway == null:
		return false
	return gateway.has_station(StringName(station))


func has_ingredients(recipe: CraftingRecipe) -> bool:
	if recipe == null:
		return false
	if progression != null and recipe.required_flag != &"" and not progression.has_flag(recipe.required_flag):
		return false
	for id in recipe.ingredients.keys():
		if not inventory.has_item(StringName(id), int(recipe.ingredients[id])):
			return false
	return true


func can_craft(recipe: CraftingRecipe) -> bool:
	return has_ingredients(recipe) and station_available(recipe.station)


## Returns true only when the whole recipe was applied.
func craft(recipe: CraftingRecipe) -> bool:
	if not can_craft(recipe):
		return false
	for id in recipe.ingredients.keys():
		if not inventory.consume(StringName(id), int(recipe.ingredients[id])):
			return false
	var outputs: Dictionary = recipe.outputs
	if outputs.is_empty():
		var single := recipe.output_id()
		if single != &"":
			outputs = {single: recipe.yield_count}
	for id in outputs.keys():
		var left := inventory.add_item(StringName(id), int(outputs[id]))
		if left > 0:
			push_warning("CRAFT: output overflow for %s (%d lost)" % [String(id), left])
	return true


func available() -> Array[CraftingRecipe]:
	var result: Array[CraftingRecipe] = []
	for recipe in RecipeDatabase.all():
		if can_craft(recipe):
			result.append(recipe)
	return result


func all_recipes() -> Array[CraftingRecipe]:
	return RecipeDatabase.all()


func reason(recipe: CraftingRecipe) -> String:
	if recipe == null:
		return "NO RECIPE"
	if progression != null and recipe.required_flag != &"" and not progression.has_flag(recipe.required_flag):
		return "LOCKED"
	if not has_ingredients(recipe):
		return "MISSING INGREDIENTS"
	if not station_available(recipe.station):
		return "STATION REQUIRED: %s" % recipe.station.to_upper()
	return "READY"
