
## Agent 3 Phase 2 (Experience) — additions
- Inventory panel (I): hotbar row + 5x8 main grid + equipment slots, click-to-move/swap, tooltips.
- Crafting panel (C): recipe list, ingredients/availability, craft action via CraftingSystem.
- Discovery notifications via ProgressionSystem.discovered / flag_set.
- Audio buses (Master/Music/SFX/World/UI) via SettingsStore.
- Settings persistence: mouse sensitivity, fullscreen, audio volumes, UI scale, continue-on-boot.

## Direction correction audit — Agent 3 (Experience)
- Audited `scripts/ui/*` and `scripts/npcs/*`: no Undercroft/dungeon-centric
  framing in HUD, menus, onboarding, discovery notifications, or NPC
  presentation. Experience layer is generic sandbox-oriented (hotbar, inventory,
  crafting, equipment, boss HUD, discovery toasts, depth/layer readouts).
- Undercroft references are confined to `scripts/content/*`, `scripts/world/*`,
  and enemy/boss data (Agents 1/2/4 scope); HUD only binds to generic boss
  signals (`max_health >= 100`) and discovery signals, not to dungeon-specific
  state.
- Biome identity correction (Ashen/Hushwoods/etc. must not replace Terraria core
  biomes) is Agent 1/4 domain; no experience-layer changes required. Agent 3
  consumes biome names only via existing `BiomeManager`/`WorldBiomes` APIs.
- No new files or replacement projects created; changes limited to experience
  ownership.
