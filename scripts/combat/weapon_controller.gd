extends Node3D
class_name WeaponController

## Turns the held ItemDef into an actual attack. Melee uses a forward arc;
## ranged/magic/thrown spawn a GameProjectile. AttackDef carries all tuning so
## new weapon categories only need a new branch here, not new inventory code.

signal attacked(attack_id: StringName)
signal mana_changed(current: float, maximum: float)

var player: Node3D
var inventory: InventoryModel
var gateway: WorldGateway
var cooldown := 0.0
var mana := 100.0
var max_mana := 100.0


func _ready() -> void:
	set_physics_process(false)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	mana = minf(max_mana, mana + 4.0 * delta)
	mana_changed.emit(mana, max_mana)


func try_attack() -> bool:
	if cooldown > 0.0 or inventory == null:
		return false
	var item_id := inventory.held_item()
	var def := ItemDatabase.get_item(item_id)
	if def == null or def.attack == null:
		return false
	var attack := def.attack
	if attack.mana_cost > mana:
		if player != null and player.has_method("set_status"):
			player.call("set_status", "NOT ENOUGH MANA")
		return false
	cooldown = attack.cooldown
	mana -= attack.mana_cost
	mana_changed.emit(mana, max_mana)
	if player != null:
		Sfx.swing(player, player.global_position)
	match attack.kind:
		"melee":
			_melee(attack)
		"ranged", "magic", "thrown":
			_launch(attack)
		_:
			_melee(attack)
	if attack.status_id != &"" and attack.status_duration > 0.0 and player != null:
		var statuses := player.get("statuses") as StatusController
		if statuses != null:
			statuses.apply(attack.status_id, attack.status_duration)
	attacked.emit(attack.attack_id)
	return true


func _aim_origin() -> Vector3:
	if player != null and player.has_method("aim_origin"):
		return player.call("aim_origin")
	if player != null:
		return player.global_position + Vector3.UP * 1.6
	return global_position


func _aim_direction() -> Vector3:
	if player != null and player.has_method("aim_direction"):
		return player.call("aim_direction")
	return -global_transform.basis.z


func _melee(attack: AttackDef) -> void:
	var origin := _aim_origin()
	var forward := _aim_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var half_dot := cos(deg_to_rad(attack.arc_degrees * 0.5))
	var hit_any := false
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance > attack.range or distance < 0.001:
			continue
		if offset.normalized().dot(forward) < half_dot:
			continue
		if enemy.has_method("apply_damage"):
			enemy.call("apply_damage", attack.damage, attack.knockback, origin, player)
		Vfx.burst(get_parent(), enemy.global_position + Vector3.UP * 0.4,
			attack.accent_color, offset.normalized(), 12, 5.0, 0.06, 0.32)
		hit_any = true
	if hit_any and player != null and player.has_method("set_status"):
		player.call("set_status", "HIT")


func _launch(attack: AttackDef) -> void:
	var start := _aim_origin() + _aim_direction() * 0.4
	GameProjectile.spawn(get_parent(), start, _aim_direction(), attack, gateway, player)
