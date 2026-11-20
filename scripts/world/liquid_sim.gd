extends RefCounted
class_name LiquidSim

# Bounded, local liquid settling. This is deliberately NOT a global fluid
# simulation: only cells queued by player edits (or by an earlier flow step) are
# visited, at most MAX_PENDING are tracked, and the world processes a small
# budget per frame. Unloaded cells are dropped instead of queued forever.
#
# Rules:
#   * liquid falls straight down into air when possible;
#   * otherwise it spreads into one deterministic horizontal neighbour;
#   * water settles every processed update, lava only every LAVA_INTERVAL ticks;
#   * simulation edits are silent (`set_block(..., false)`) so they do not bloat
#     the sparse save journal. The player's original place/break still journals.

const MAX_PENDING := 512
const LAVA_INTERVAL := 3

var water_id := -1
var lava_id := -1
var air_id := 0

var _pending: Array[Vector3i] = []
var _deferred: Array[Vector3i] = []
var _pending_set: Dictionary = {}
var _tick := 0


func configure(world) -> void:
	water_id = int(world.block_ids.get(&"water", -1))
	lava_id = int(world.block_ids.get(&"lava", -1))
	air_id = world.air_id


func clear() -> void:
	_pending.clear()
	_deferred.clear()
	_pending_set.clear()


func pending_count() -> int:
	return _pending.size() + _deferred.size()


# Called for player edits only: the edited cell and its six neighbours may now
# admit or release liquid.
func on_block_changed(_world, cell: Vector3i, _block_id: int) -> void:
	if water_id < 0 and lava_id < 0:
		return
	enqueue(cell)
	for offset in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		enqueue(cell + offset)


func enqueue(cell: Vector3i) -> void:
	if _pending_set.size() >= MAX_PENDING or _pending_set.has(cell):
		return
	_pending_set[cell] = true
	_pending.append(cell)


func process(world, budget: int) -> int:
	if _pending.is_empty() and _deferred.is_empty():
		return 0
	_tick += 1
	if not _deferred.is_empty():
		for cell in _deferred:
			if not _pending_set.has(cell) and _pending_set.size() < MAX_PENDING:
				_pending_set[cell] = true
				_pending.append(cell)
		_deferred.clear()
	var processed := 0
	while processed < budget and not _pending.is_empty():
		var cell: Vector3i = _pending.pop_front()
		_pending_set.erase(cell)
		var id: int = world.get_block_id(cell)
		if id == air_id or (id != water_id and id != lava_id):
			continue
		# Lava advances on a slower cadence, so it visibly creeps.
		if id == lava_id and (_tick % LAVA_INTERVAL) != 0:
			# Deferred cells must NOT enter _pending_set: the set describes the
			# pending queue, and rotation would otherwise skip (and drop) them.
			if _deferred.size() < MAX_PENDING:
				_deferred.append(cell)
			continue
		processed += 1
		var below := cell + Vector3i.DOWN
		if _can_flow(world, below):
			world.set_block(cell, air_id, false)
			world.set_block(below, id, false)
			enqueue(cell)
			enqueue(below)
			continue
		# Horizontal spread: one deterministic direction per update keeps the
		# queue bounded (each step can add at most one new cell).
		var directions := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		var hash_value := absi(cell.x * 73856093 + cell.y * 19349663 + cell.z * 83492791 + _tick)
		var direction := Vector3i(directions[hash_value % 4])
		var side := cell + direction
		if _can_flow(world, side):
			world.set_block(side, id, false)
			enqueue(side)
	return processed


func _can_flow(world, cell: Vector3i) -> bool:
	return world._inside_world(cell) and world.is_chunk_loaded_at(cell) and world.get_block_id(cell) == air_id
