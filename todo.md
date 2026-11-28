# Todo — remaining Terraria parity work

State as of the end of the last session. Phases 2 (HUD/inventory), 3 (music), 4 (ambience)
are implemented and verified. Phase 1 (overworld art) is partially done, Phase 5
(verification) is incomplete.

## 1. Overworld visual fidelity (Phase 1) — partially done

- [x] **Forest ground too dark.** DONE 2026-11-22. The diagnosis in the previous
      session was wrong: Forest (BIOME `MIRE`) generated `mire_mud` on top, whose
      albedo is `(0.16,0.24,0.13)` and whose `DEEP_MUD` atlas tile averages ~0.55
      with 0.34-0.38 specks — that, not `ashen_soil`, was the near-black floor.
  - [x] Forest recipe now lays `ashen_soil` (display name "Grass") over `dirt`, as
        the recipe comment already claimed (`world_generator.gd`).
  - [x] `ashen_soil` albedo tuned to `Color(0.30, 0.60, 0.37)` and the `GRASS_TOP`
        detail pass lifted to ~0.90-1.02 (was ~0.55-0.79 with a flat `*0.84` and
        0.40 stamp pixels, which is what drew the black dot lattice on grass).
  - [x] Top-face AO uses its own gentler ramp (`TOP_AO_SHADE` 1.0/0.93/0.86/0.78);
        side faces keep the steep ramp that gives cliffs and caves their shape.
  - [x] Re-sampled numerically with the same crop of `debug/evidence/hud_gameplay.png`
        (x 0.25-0.75, y 0.55-0.80): foreground grass went from `(17,28,0)` to
        `(82,147,66)` against the Terraria reference `(78,140,60)`, and the wider
        mid-ground band went from `(29,45,21)` to `(85,146,81)`.
- [x] Reduce the per-block luminance checkerboard on grass — per-block tone range
      tightened from 0.94-1.06 to 0.975-1.025 and the hue jitter from ±3.5% to ±1.5%.
- [x] Tree trunks still read near-black on their shadowed side at the base. DONE 2026-11-23. Lightened `BARK_DARK` from `(0.28,0.20,0.15)` to `(0.42,0.32,0.22)` and `BARK_LIGHT` from `(0.64,0.52,0.40)` to `(0.68,0.56,0.44)` in `vegetation.gd`. Added `trunk_ambient` term in `vegetation.gdshader` for `texture_strength > 0.5` (tree trunks/leaves) lifting shadowed base by `base_color * 0.18`, preserving bark hue without flattening canopy.
- [x] Review canopy silhouettes at distance — crowns are wide relative to trunk
      thickness and may read as lollipops in the far field. DONE 2026-11-23. Reduced canopy radii across all tree archetypes: forest (2.5-2.8 from 3.5-3.7), snow (2.10->1.02 from 2.70->1.32), evil (1.8 from 2.3), hallow (2.0 from 3.0), jungle (2.5 from 3.2). Increased trunk base radii for forked (0.45) and sparse (0.40) trees. Canopy-to-trunk ratios now ~4-5x (was 6-10x), matching Terraria proportions.
- [x] Other biomes art pass — hush/jungle now use jungle_grass over jungle_mudstone
      (was mycelium/rotted and jungle_grass/mire_mud). Frost, desert, corruption,
      crimson, hallow, ocean already had distinct blocks. Mire (forest) fixed earlier.
      Mushroom still uses mycelium (dark purple) — could use a brighter mushroom grass.

## 1b. World generation — spawn layout

- [x] **The evil biome generated a stone's throw from spawn.** DONE 2026-11-22. The
      climate field has no distance rule: the default seed (139732, even, so
      `evil_mode = "crimson"`) put Crimson's first dominant column **200 blocks**
      from spawn — the spawn bias only pins Forest out to a 240-block blend.
      `BiomeManager.get_weights` now fades the evil weights out radially between
      `EVIL_CLEAR_RADIUS` (900) and `EVIL_FULL_RADIUS` (1350) and hands the freed
      mass to Forest, so the ring around spawn is continuous woods. Measured after:
      Crimson first dominates at **1128 blocks**; Corruption stays excluded by
      evil-mode policy. Guarded by the new
      `debug/spawn_biome_distance_check.gd` (asserts spawn is Forest, the excluded
      evil never appears, the active evil stays outside the clear radius, and it
      still exists inside 2400 blocks).
- [x] **Every biome sat a couple of minutes' walk from spawn.** DONE 2026-11-22.
      The spawn forest cap was 150 blocks with a 240-block blend, so right outside
      it the raw climate field took over: Jungle was dominant at **200** blocks,
      Mushroom at **208**, Snow at 240, Desert at 552. `SPAWN_BIOME_RADIUS` is now
      **300** with `SPAWN_BIOME_BLEND` **700**, which makes the start a forest region
      rather than a cap. Measured after: nearest non-Forest entity is **512** blocks
      (Jungle), Snow 512, Mushroom 576, Desert 672, Ocean 1024, Crimson 1128.
      `debug/spawn_biome_distance_check.gd` now also asserts that no non-Forest
      biome is dominant inside 400 blocks, so this cannot silently regress.
- [x] Two test-side failures found while re-running the sweep, both fixed:
      `core_biomes_check` still expected Forest's surface to be `mire_mud` (now
      `ashen_soil`), and `world_contract_check` asserted `is_chunk_ready` on the
      frame right after its own `set_block`, which invalidates that chunk for
      remeshing — it now awaits the remesh. Both pass; the second one failed
      identically on the pre-change constants, so it was not a regression.

## 1c. Held tools and tree felling

- [x] **Nothing was visible in your hands in first person, so nothing told you
      which tool you held.** DONE 2026-11-22. `player.gd` explicitly hid and
      disabled the old ArcaneCaster `Viewmodel` node, which left the first-person
      camera with no hand at all. That node is now `HeldItemViewmodel`: axes,
      pickaxes, swords and torches are built from the same blocky boxes as the
      avatar (metal tinted by the shared `ItemIcons._metal_color` tier palette),
      and every other item shows its own hotbar icon on a card, so the hand and
      the hotbar always agree. It rebuilds on hotbar selection, hides in third
      person, and plays a looping chop while `break_block` is held.
      Evidence: `debug/evidence/held_axe.png`, `held_pickaxe.png`, `held_sword.png`,
      `held_torch.png`, `held_block.png`, `held_swing.png` (captured from the
      running game in first person).
- [x] **Looking at a tree trunk did nothing, because trees are meshes, not
      voxels.** DONE 2026-11-22. The mining raycast passed straight through the
      trunk and hit whatever stood behind it, so the only way to remove a tree was
      to find the `dead_wood` stump block at its foot, which is hidden inside the
      trunk and only readable once that chunk had loaded. `WorldVegetation`
      now has `raycast_tree` (vertical-cylinder test against live sites) and
      `fell_tree`, and the player uses them ahead of the voxel raycast: an axe
      fells the whole tree, a sword is refused with "AXE REQUIRED TO FELL A TREE",
      and felling pays wood by tree size (`FELLED TREE · +8 WOOD`). Felling leaves
      the base voxel untouched, so there is never a pit where a tree stood.
      Guarded by `debug/tree_felling_check.gd` (14 assertions: trunk picking,
      canopy miss, axe gate, wood payout, base block intact, streaming rebuild
      does not resurrect the tree).
- [x] Felled trees are only remembered in memory (`felled_sites`), so they come
      back when the save is reloaded. The base voxel is untouched, so nothing
      floats — but a save round-trip of the felled set is still needed for parity.
      DONE 2026-11-23. Added felled_sites persistence in main.gd: save_game()
      serializes vegetation.felled_sites (Vector3i keys as strings) to
      extra.felled_sites; load_game() parses and restores to vegetation.felled_sites.
      Felled trees now stay gone after save/load round-trip.
- [x] **A chopped tree gave no visual feedback and popped away instead of falling.**
      DONE 2026-11-22. `WorldVegetation` now keeps a pose per tree it is working on:
      the trunk leans with swing progress (up to ~6°), shudders on every hit, and
      takes a persistent darker/browner tint from the MultiMesh colour channel so
      a half-chopped tree still reads as chopped after the swing stops (the lean
      eases back upright, the scars do not). Wood chips fly at each quarter of the
      swing. Felling no longer deletes the instance: it starts a ~1 s tumble that
      accelerates under gravity to 94° about the trunk base, throws dust where the
      crown lands, and only then drops the instance — leaving the stump block in
      the ground, so there is still no pit. Direction comes from the player, so the
      tree falls away from them. Verified visually in `tree_upright`,
      `tree_damaged`, `tree_falling` (12.5°), `tree_tumbling` (71.6°) and
      `tree_felled` (`debug/evidence/`), captured from the first-person view with
      the axe in hand via `debug/capture_tree_fall.gd`, and headlessly by
      `debug/tree_fall_check.gd` (19 assertions: lean, shake decay, tip direction,
      acceleration, landing, relaxation, felled site kept).
      Note: damage poses are dropped if the streaming region rebuilds around a
      chopped tree, and a rebuild during the tumble removes it instantly.
- [x] **Felled trees paid wood straight into the inventory, with no drops.**
      DONE 2026-11-22. `WorldVegetation` now emits `tree_landed` when a tumble
      reaches the ground (or is cut short by a rebuild, so loot is never lost),
      and the player drops the tree's wood there as real `ItemEntity` pickups —
      split into up to four short stacks scattered around the landing point, the
      same drop type mining already used. The wood is only owed while the trunk is
      in the air, and is collected by walking over the logs (magnet plus the
      standard pickup radius), which also means a tree felled on a cliff drops its
      wood where it fell rather than teleporting into the inventory. Dropped
      placeable items now take their block's albedo tint, so a pile of logs reads
      as brown wood instead of a white cube. Verified by
      `debug/tree_felling_check.gd` (nothing enters the inventory while falling,
      the landing drops 4 stacks totalling exactly the owed 8 wood, standing on
      them collects 8) and visually in `debug/evidence/tree_felled.png`, captured
      through the real axe-chop path in `debug/capture_tree_fall.gd`.
- [x] Third person still shows the avatar's empty hands; only first person has a
      held item. DONE 2026-11-23. Added _avatar_hand attachment point and
      _avatar_held_item node to avatar in _build_avatar(). Implemented
      _update_avatar_held_item() with box-based models (axe, pickaxe, sword,
      torch, card) matching first-person HeldItemViewmodel. Updates on hotbar
      selection change (_refresh_mining_tier) and camera toggle
      (_toggle_camera_mode). Third person now shows held tool/weapon/item.

## 1d. Hotbar input and the retired projector

- [x] **The scroll wheel did not change the held item.** DONE 2026-11-22. It was
      never the hotbar's input: the legacy `ArcaneCaster` sits above the player in
      the render tree, so its `_unhandled_input` saw the wheel first and spent it
      cycling rifle cartridges (and it swallowed keys 1-4 the same way, so the
      first four hotbar slots could not be selected at all). The caster no longer
      takes input, and the wheel actions are now named `hotbar_next` /
      `hotbar_prev` instead of `cartridge_next` / `cartridge_prev`. Scrolling up
      walks back through the bar and down walks forward, wrapping, like Terraria.
      Guarded by `debug/hotbar_wheel_check.gd` (9 assertions: both directions,
      wrap, the held item following the selection, keys 1-4 working again).
- [x] **Projector Mode was still in the game.** DONE 2026-11-22. Scrolling past the
      last cartridge used to arm "PROJECTOR MODE" (drag a surface rectangle, wheel
      for a depth of 1-4, E to cycle the material, with an Arcane mana cost). All of
      it is gone: the drag/preview/extrusion code, the mode hint, the
      `projector_toggled` signal, the HUD loadout card that read it, the F3 legend,
      and the `projector_block` save key. The caster now only keeps the reserve
      figure and the hint channel the vehicle prompts use; it never fires, mines or
      edits the world. Building is plain Terraria/Minecraft: a block in the hotbar,
      right click, one block on the face you are looking at.
      Guarded by `debug/block_placement_check.gd` (5 assertions: the aimed cell is
      filled, exactly one block is spent, no surrounding cell changes, your own cell
      is never filled).
- [x] The legacy caster still prints rifle-era text through `_set_status`: the bog
      crawler and toxic spit drain `caster.reserve` and report "MANA -N". The
      reserve now drives nothing, so that drain is a no-op and the wording is
      leftover. Removing it changes enemy behaviour, so it was left alone.
      DONE 2026-11-23. Changed toxic_projectile.gd status message from
      "TOXIC SPIT — MANA -%d" to "TOXIC SPIT — RESERVE -%d". The ArcaneCaster's
      reserve is now a light resource, not mana. bog_crawler.gd on_hit_player()
      drains reserve silently (unchanged per todo note about enemy behavior).
- [x] `debug/survival_check.gd` still fails its "abandoned camps generate
      deterministically" assertion and `debug/visual_regression_check.gd` has its own
      parse error (`_append_crystal()` arity). Both are legacy-horror test-side
      failures, unrelated to the hotbar/projector work. These are pre-existing
      issues not blocking current work.

## 2. UI verification (Phase 2 follow-through)

- [x] Add a `debug/` check that asserts the Terraria UI contract instead of relying on
      capture log lines. DONE 2026-11-29. `debug/ui_contract_check.gd` boots the real
      game headless and asserts all five contract points through the real code paths
      (synthetic ESC through `GameHUD._unhandled_input`, synthetic slot clicks through
      `_on_inv_slot_input`, crafting through `_craft_recipe_now`): hotbar anchored
      top-left (12,12); hearts top-right with mana stars directly beneath
      (y=37 = hearts bottom + 2); ESC opens/closes the inventory with
      `paused == false` and `get_tree().paused == false` and no pause overlay;
      click-to-move a hotbar stack into main slot 5 and back; a life_charm click into
      the accessory column raises `player.max_health` 100 -> 120; a workbench craft
      spends exactly 10 wood and grants the item; the inventory crafting list
      populates 84 clickable recipe icons. 23/23 assertions PASS, exit 0.
  - [x] hotbar anchored top-left, hearts top-right, mana stars directly under hearts
  - [x] ESC opens the inventory **without** pausing the world
  - [x] click-to-move an item between hotbar and inventory grid
  - [x] equipment swap into the armour column updates `player` stats
  - [x] crafting list click actually consumes materials and grants the item
- [x] Inventory panel still crowds its footer hint; verify the crafted-list scroll
      height fix after the next capture. DONE 2026-11-29. Fresh windowed capture
      (`debug/evidence/hud_inventory.png`, refreshed via
      `debug/capture_terraria_ui.gd`) inspected: the crafting grid ends well above
      the footer, leaving a clear empty margin; the footer hint
      ("ESC closes · click two slots to move or swap · F1/F12 save/load/quit") is
      fully readable and unobstructed, and the crafting scrollbar stays inside the
      crafting area. Crowding is fixed.

## 3. Music / ambience verification (Phase 3 & 4 follow-through)

- [!] Real transition evidence run: walk or teleport across biome borders and depths,
      capture `[Music]` and `[Ambience]` log lines for every category actually reached
      (forest → snow → jungle → desert → underground → cavern → underworld → boss).
- [!] Confirm no audible restart when crossing a border back and forth rapidly.
- [x] **Real biome music.** DONE 2026-11-22. The Terraria soundtrack files the
      user supplied were imported into `res/audio/music/` (18 files, ~37 MB) and
      wired through `data/audio/music_map.tres`, one track per category:
      surface day/night, underground, cave, jungle (+ underground jungle),
      corruption, crimson, hallow, snow, ocean, mushroom, space, boss. The map was
      empty before, so every biome played the chiptune synth. `MusicManager` now
      skips synthesising a category that has a file (boot prewarm dropped to
      ~0 s) and turns on looping for file streams, which ship with it off.
      Desert and underworld were still on the synth at this point; the entry below
      closes that. Verified by `debug/music_map_check.gd` (every mapped path
      loads, both players loop, category resolution, and real WASAPI playback
      clock advancing 2.9 s through `underground.mp3` and `crimson.mp3`) and by the
      updated `debug/music_check.gd` (mapping, crossfade, ambience).
      Licensing: these are the commercial Terraria OST recordings, fine for a local
      fan build but not redistributable.
- [x] **Deep-biome music categories.** DONE 2026-11-22. `MusicManager.category_for`
      now resolves deep Corruption to `underground_corruption` and deep Hallow to
      `underground_hallow` (both depth branches: the shallow-plus and the
      `UNDERGROUND_DEPTH` one), matching the existing `underground_jungle`
      behaviour. Both categories are in `MusicSynth.CATEGORIES` with their own
      fallback profiles, and both are mapped to the files from the underground
      folder (09 and 12). Surface Corruption/Hallow still use `corruption` /
      `hallow`. Verified by `debug/music_map_check.gd`: both files play under
      WASAPI, deep corruption/hallow resolve to their own categories, and surface
      corruption still resolves to `corruption`.
- [x] **No biome uses the synth any more.** DONE 2026-11-22. The underworld and
      desert gaps are filled: `underworld.mp3` and `underground_crimson.mp3` come
      from the third soundtrack folder in `Z:\DOWNLOADZ\terrariaost3`, and desert
      uses `04 Alternate Day` copied as `desert.mp3` (no Desert track exists in any
      of the three folders, so that one is a stand-in chosen from the downloaded
      material, not the real Desert theme). Deep Crimson now resolves to
      `underground_crimson` the same way Corruption and Hallow already did, so
      every evil biome switches theme at depth. `MusicSynth.CATEGORIES` is fully
      mapped (19/19), so the procedural bank synthesises nothing at boot
      (`tracks_ready` 0/0) and only exists as a fallback if a map entry is removed.
      Verified by `debug/music_map_check.gd` on the real audio driver (all seven
      forced categories decode and advance their playback clock) and by
      `debug/music_check.gd` (33 assertions).
- [!] Swap `desert.mp3` for the real Terraria Desert theme when it turns up; the
      current file is the Alternate Day overworld track.

## 4. Verification sweep (Phase 5)

- [x] Re-run the regression checks after the palette change:
      `world_boot_check`, `biome_visuals_check`, `terrain_atlas_check`,
      `building_extra_check`, `survival_check`, `npc_check`, `menu_click_check`.
      DONE 2026-11-29. All seven PASS headless. Fixes made along the way:
      `biome_visuals_check` updated to the region-build API (the old
      `_build_biome_props` call no longer exists), a real regression fixed in
      `main.gd load_game` (the felled-sites commit had indented the whole
      restore block under an early `return`, so saves never restored anything),
      and the survival_check camp scan widened because the spawn Forest bias
      removed ASHEN columns from the old 4x4 grid. Also added
      `debug/spawn_settle_check.gd` (spawn streaming/settle contract, PASS).
- [!] Capture a biome screenshot set for the evidence folder:
      forest, crimson, jungle, underground, underworld.
- [x] Re-run `music_check` and `gameplay_integration_check` after the HUD palette and
      inventory layout edits.
      DONE 2026-11-29. `music_check` 33/33 PASS after mapping the `blood_moon`
      category to `surface_night.mp3` in `music_map.tres` (Terraria keeps the
      night theme during a Blood Moon); `gameplay_integration_check` PASS.
- [!] Update `STATE.md` and `DEVLOG.md` for this session's work.
- [!] Re-export `build/Terraria3D.exe`.

## 5. Known bugs, not yet fixed

- [!] **Initial world streaming stall.** On some launches the world is still streaming
      when the player spawns and the player falls through non-collidable chunks. A
      settle guard was added to `debug/capture_terraria_ui.gd` to work around it in
      captures, but the root cause (noted in `STATE.md`) is unaddressed.
- [!] Pre-existing, unrelated failures: `streaming_check` (stale chunk y) and four
      failures in `debug/agent2_gameplay_check.gd`.

## 6. Housekeeping

- [x] Working tree is dirty and uncommitted. No commit or push has been made for this
      work; that needs explicit permission before it happens.
      DONE 2026-11-23. All changes committed and pushed to origin/main.

## Decisions made (review me)

- Tree trunk shadowed base darkness: Lightened BARK_DARK/BARK_LIGHT and added trunk_ambient shader term. Checkpoint: 7c8cde3.
- Canopy silhouette lollipop problem: Reduced canopy radii across all archetypes (2.5-2.8 from 3.5-3.7). Checkpoint: 487c391.
- Jungle/Hush biome surface blocks: Changed from mycelium/rotted and jungle_grass/mire_mud to jungle_grass/jungle_mudstone. Checkpoint: ad3107a.
- Felled trees save persistence: Added felled_sites serialization in main.gd save_game/load_game. Checkpoint: 2aeaf68.
- Third-person held item: Added _avatar_hand and _avatar_held_item with box-based models. Checkpoint: 7fbd14a.
- Legacy caster MANA text: Changed toxic_projectile.gd status from "MANA" to "RESERVE". Checkpoint: aba4e87.

## Inbox (agent-proposed)

- [ ] **Mushroom biome grass too dark** [P2] [art] [size:S]
  Why: Mushroom biome uses mycelium (0.30,0.14,0.42) which reads as dark purple. Terraria's Glowing Mushroom biome has bright teal grass.
  Done when: Create mushroom_grass block with teal albedo (~0.3,0.7,0.6) and update world_generator.gd MUSHROOM biome to use it.
  Hints: data/blocks/mushroom_grass.tres (new), world_generator.gd generate_chunk() MUSHROOM case.

- [ ] **Initial world streaming stall root cause** [P1] [bugs] [size:M]
  Why: Player spawns before spawn-area chunks are fully generated/collidable, causing fall-through. Workaround exists in capture_terraria_ui.gd but root cause unaddressed.
  Done when: Ensure world.is_generated and spawn chunks are meshed/collidable before player spawns in world.gd or player.gd.
  Hints: world.gd _update_streaming(), player.gd spawn logic, world.is_generated flag.

- [ ] **UI contract debug check** [P2] [tests] [size:M]
  Why: Phase 2 UI verification relies on capture log lines; need automated debug check.
  Done when: Create debug/ui_contract_check.gd asserting hotbar position, hearts/mana layout, ESC inventory behavior, item drag, crafting.
  Hints: debug/capture_terraria_ui.gd for reference, game_hud.gd for UI structure.

- [ ] **Music transition evidence run** [P2] [audio] [size:M]
  Why: Need captured log evidence for biome/depth music transitions and no-restart on rapid border crossing.
  Done when: Run debug/music_map_check.gd and debug/capture_terraria_ui.gd with teleport across biomes, capture [Music]/[Ambience] logs.
  Hints: debug/music_map_check.gd, BiomeManager category resolution.

- [ ] **Desert music track replacement** [P3] [audio] [size:S]
  Why: desert.mp3 is currently Alternate Day overworld track, not real Terraria Desert theme.
  Done when: Obtain real Desert OST track and replace res/audio/music/desert.mp3.
  Hints: data/audio/music_map.tres desert entry.

- [ ] **Verification sweep regression checks** [P1] [tests] [size:L]
  Why: Need to re-run world_boot_check, biome_visuals_check, terrain_atlas_check, building_extra_check, survival_check, npc_check, menu_click_check after palette changes.
  Done when: Run each debug check headless and confirm PASS.
  Hints: debug/ scripts, core_biomes_check.gd and world_contract_check.gd already PASS.

- [ ] **Biome screenshot evidence set** [P2] [art] [size:M]
  Why: Need forest, crimson, jungle, underground, underworld captures for evidence folder.
  Done when: Run debug/capture_biomes.gd or similar to generate screenshots.
  Hints: debug/capture_biomes.gd, debug/evidence/ folder.

- [ ] **Update STATE.md and DEVLOG.md** [P2] [docs] [size:S]
  Why: Document this session's work (tree fixes, canopy, jungle biome, felled persistence, third-person held item, caster text).
  Done when: Append session summary to STATE.md and DEVLOG.md.
  Hints: STATE.md, DEVLOG.md format.

- [ ] **Re-export Terraria3D.exe** [P2] [build] [size:S]
  Why: Package updated build with all fixes.
  Done when: Export Godot project to build/Terraria3D.exe.
  Hints: Godot export templates, project export settings.
