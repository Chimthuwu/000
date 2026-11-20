extends SceneTree

# Agent 2 Phase 4: discovery rewards, encounters and progression integration.

var main: Node
var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DISCOVERY FAIL: %s %s" % [label, detail])
		return
	print("DISCOVERY PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	main.set_script(null)  # avoid HUD orchestration coupling
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var world: VoxelWorld = main.get_node("VoxelWorld") as VoxelWorld
	var player: VoxelPlayer = main.get_node("Player") as VoxelPlayer
	var director: EnemyDirector = main.get_node("EnemyDirector") as EnemyDirector
	var seed := int(world.world_seed)
	var frames := 0
	while not world.is_generated and frames < 6000:
		await process_frame
		frames += 1
	_check(world.is_generated, "world ready", "frames=%d" % frames)
	await process_frame

	# --- reward mapping ---------------------------------------------------------
	var bad := DiscoveryRewards.resolve_item_id("")
	_check(bad == &"", "empty loot name resolves to no item")
	bad = DiscoveryRewards.resolve_item_id("totally_fake_block")
	_check(bad == &"", "invalid loot name resolves to no item")
	_check(DiscoveryRewards.resolve_item_id("gold_ore") == &"gold_ore", "ore name maps to an item")
	_check(DiscoveryRewards.resolve_item_id("coal_ore") == &"coal", "block alias maps to its item")
	var unmapped: Array[String] = []
	for key in BiomeDiscovery.TEMPLATES.keys():
		var def: Dictionary = BiomeDiscovery.TEMPLATES[key]
		for name in (def.get("loot", []) as Array):
			if DiscoveryRewards.resolve_item_id(String(name)) == &"":
				unmapped.append(String(name))
	_check(unmapped.is_empty(), "every discovery loot name resolves", "unmapped=%s" % str(unmapped))

	# --- one-time reward claim --------------------------------------------------
	var synthetic := {
		"id": "disc_test_99", "label": "Test Vault",
		"loot": ["gold_ore", "coal_ore", "", "fake_item"]
	}
	var before := player.inventory.count(&"gold_ore")
	var first: Dictionary = player.discovery_rewards.try_claim(synthetic, player.inventory, player.progression)
	var after := player.inventory.count(&"gold_ore")
	_check(bool(first.get("claimed", false)) and after == before + 1, "discovery grants a real item", "before=%d after=%d" % [before, after])
	_check((first.get("granted", {}) as Dictionary).has(&"coal"), "alias reward granted as item id")
	_check(not (first.get("granted", {}) as Dictionary).has(&""), "empty name was skipped")
	var second: Dictionary = player.discovery_rewards.try_claim(synthetic, player.inventory, player.progression)
	_check(not bool(second.get("claimed", false)) and player.inventory.count(&"gold_ore") == after,
		"repeat visit grants nothing")

	# --- persistence ------------------------------------------------------------
	var saved_progress := player.progression.serialize()
	var fresh := ProgressionSystem.new()
	fresh.deserialize(saved_progress)
	_check(fresh.has_flag(DiscoveryRewards.claim_flag("disc_test_99")), "claim flag persists via player save")
	_check(not fresh.has_flag(&"underworld_vanquished"), "Warden/ discoveries do not unlock Hallow")

	# --- real site metadata and encounters -------------------------------------
	var guarded_site: Dictionary = {}
	var plain_site: Dictionary = {}
	for gz in range(-3, 4):
		for gx in range(-3, 4):
			var site := BiomeDiscovery.site_for(seed, gx, gz)
			if site.is_empty():
				continue
			if guarded_site.is_empty() and ["vault", "temple", "altar", "heart", "garden"].has(String(site["template"])):
				guarded_site = site
			if plain_site.is_empty() and ["house", "cabin", "ruin"].has(String(site["template"])):
				plain_site = site
	_check(not guarded_site.is_empty(), "a guarded discovery site exists near spawn", str(guarded_site.get("template", "")))
	if not guarded_site.is_empty():
		# Stream the site's chunk in before spawning, exactly as real gameplay
		# would when the player walks up to the discovery.
		var site_cell := Vector3i(int(guarded_site["x"]), int(guarded_site["y"]) + 1, int(guarded_site["z"]))
		player.position = Vector3(site_cell.x + 0.5, site_cell.y + 0.05, site_cell.z + 0.5)
		world.player_tracking = true
		var wait := 0
		while not world.is_chunk_ready(world._chunk_of(site_cell)) and wait < 2000:
			world.set_generation_focus(site_cell)
			await process_frame
			wait += 1
		_check(world.is_chunk_ready(world._chunk_of(site_cell)), "discovery chunk streamed in", "frames=%d" % wait)
		var spawned: Array = director.spawn_discovery_encounter(String(guarded_site["id"]), seed)
		_check(spawned.size() > 0, "guarded site spawns an encounter", "count=%d" % spawned.size())
		if not spawned.is_empty():
			var enemy: Node3D = spawned[0] as Node3D
			var dist := Vector2(enemy.position.x - float(guarded_site["x"]), enemy.position.z - float(guarded_site["z"])).length()
			_check(dist < 3.0, "encounter spawns at the discovery location", "dist=%.1f" % dist)
	if not plain_site.is_empty():
		var quiet: Array = director.spawn_discovery_encounter(String(plain_site["id"]), seed)
		_check(quiet.is_empty(), "exploration site has no forced encounter", str(plain_site.get("template", "")))

	# --- Undercroft arena registration -----------------------------------------
	_check(director.encounter_center_provider.is_valid(), "encounter center provider registered")
	var arena: Vector3 = director.encounter_center_provider.call("sanctum")
	_check(arena != Vector3.ZERO, "Undercroft arena resolves a world position", str(arena))

	# --- Hallow gating ----------------------------------------------------------
	player.progression.unlock_hallow()
	_check(player.progression.is_hallow_unlocked(), "Underworld event flag unlocks Hallow")

	if failures > 0:
		print("DISCOVERY RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("DISCOVERY PASS: %d checks" % checks)
	quit(0)
