extends SceneTree

# Checks the tree damage and fall presentation: a chop tilts and shakes the tree,
# felling makes it tumble in one direction under gravity, and it is only removed
# once it has landed.
#
# The poses are read from the vegetation state rather than from the MultiMesh:
# the headless dummy renderer does not store instance transforms, so only a
# windowed capture can prove the pixels. `debug/capture_tree_fall.gd` does that.

var _failures: Array[String] = []


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _initialize() -> void:
	var scene: Node = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node("VoxelWorld")
	var player = scene.get_node("Player")
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < 1200:
		await process_frame
		frames += 1
	var vegetation: WorldVegetation = world.vegetation

	var cell := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for candidate in vegetation.site_slots.keys():
		cell = candidate
		break
	_check("found a live tree", cell.x != (1 << 30), "cell=%s" % str(cell))
	if cell.x == 1 << 30:
		print("TREE FALL CHECK FAIL")
		quit(1)
		return

	var slot: Dictionary = vegetation.site_slots[cell]
	var upright: Transform3D = slot["transform"]
	var push := Vector3(1.0, 0.0, 0.0)

	# --- Damage --------------------------------------------------------------
	vegetation.damage_tree(cell, 0.5, push)
	var state: Dictionary = vegetation.tree_states.get(cell, {})
	_check("a chop is remembered on the tree", not state.is_empty(), "states=%d" % vegetation.tree_states.size())
	var lean_angle := rad_to_deg(float(state.get("angle", 0.0)))
	var lean_pose: Transform3D = state.get("pose", upright)
	_check("a chop tilts the trunk", lean_pose != upright and lean_angle > 0.5,
		"lean=%.2f deg" % lean_angle)
	_check("the trunk tips along the swing", lean_pose.basis.y.normalized().dot(push) > 0.0,
		"dot=%.3f" % lean_pose.basis.y.normalized().dot(push))

	# A deeper swing leans further, and the shake is a decaying impulse.
	vegetation.damage_tree(cell, 1.0, push)
	state = vegetation.tree_states[cell]
	var deep_angle := rad_to_deg(float(state.get("angle", 0.0)))
	_check("a deeper chop leans further", deep_angle > lean_angle,
		"%.2f -> %.2f deg" % [lean_angle, deep_angle])
	var shake_before := float(state.get("shake", 0.0))
	vegetation._process(0.1)
	var shake_after := float(vegetation.tree_states.get(cell, {}).get("shake", 0.0))
	_check("the shudder decays after a hit", shake_after < shake_before,
		"%.2f -> %.2f" % [shake_before, shake_after])

	# --- Falling -------------------------------------------------------------
	vegetation.fell_tree(cell, push)
	_check("felling starts a tumble instead of deleting the tree",
		vegetation.tree_falls.size() == 1, "falls=%d" % vegetation.tree_falls.size())
	var fall: Dictionary = vegetation.tree_falls[0] if not vegetation.tree_falls.is_empty() else {}
	_check("the tumble keeps the trunk's own position", (fall.get("base", Transform3D()) as Transform3D).origin == upright.origin,
		"origin=%s" % str((fall.get("base", Transform3D()) as Transform3D).origin))

	vegetation._process(0.4)
	var mid_angle := rad_to_deg(float(fall.get("angle", 0.0)))
	_check("the trunk rotates while falling", mid_angle > deep_angle + 5.0, "%.1f deg" % mid_angle)
	_check("it falls along the push direction",
		(fall["written"] as Transform3D).basis.y.normalized().dot(push) > 0.15,
		"dot=%.2f" % (fall["written"] as Transform3D).basis.y.normalized().dot(push))
	_check("it is not flat yet halfway through", mid_angle < 85.0, "%.1f deg" % mid_angle)

	vegetation._process(0.4)
	var late_angle := rad_to_deg(float(fall.get("angle", 0.0)))
	_check("the fall accelerates rather than moving at a constant rate",
		late_angle - mid_angle > mid_angle * 0.5, "%.1f -> %.1f deg" % [mid_angle, late_angle])

	vegetation._process(0.15)
	var near_ground := rad_to_deg(float(fall.get("angle", 0.0)))
	_check("the tree is almost down just before it lands", near_ground > 60.0, "%.1f deg" % near_ground)
	vegetation._process(0.4)
	_check("the tumble record is cleared once it lands", vegetation.tree_falls.is_empty(),
		"falls=%d" % vegetation.tree_falls.size())
	_check("a finished fall goes just past vertical", rad_to_deg(vegetation.TREE_FALL_RADIANS) > 90.0,
		"%.1f deg" % rad_to_deg(vegetation.TREE_FALL_RADIANS))
	_check("the felled site is still remembered", vegetation.felled_sites.has(cell),
		"felled=%d" % vegetation.felled_sites.size())

	# A tree that is only glanced keeps leaning after the shake stops, so the
	# damage stays readable if the player walks away mid-swing.
	var second := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for candidate in vegetation.site_slots.keys():
		second = candidate
		break
	if second.x != 1 << 30:
		vegetation.damage_tree(second, 0.6, push)
		for _i in range(9):
			vegetation._process(0.05)
		var rest: Dictionary = vegetation.tree_states.get(second, {})
		var rest_angle := rad_to_deg(float(rest.get("angle", 0.0)))
		_check("the lean survives the end of the swing", rest_angle > 0.3 and rest_angle < 6.0,
			"%.2f deg" % rest_angle)
		_check("the shake has stopped", absf(float(rest.get("shake", 0.0))) < 0.05,
			"shake=%.3f" % float(rest.get("shake", 0.0)))

	# And a chop that is abandoned relaxes back upright instead of leaning forever.
	vegetation._process(6.0)
	_check("an abandoned tree eases back upright", not vegetation.tree_states.has(second),
		"states=%d" % vegetation.tree_states.size())

	if _failures.is_empty():
		print("TREE FALL CHECK PASS")
		quit(0)
	else:
		print("TREE FALL CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
