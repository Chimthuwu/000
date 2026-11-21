# PROJECT: TERRARIA 3D

## Identity

Terraria 3D is a 3D interpretation of Terraria. It is not Lumen Deepworld, not a
horror game, and not a generic Minecraft-like sandbox. The former identity has
been retired from project configuration, visible UI, documentation, agent
instructions, resource names and active code identifiers. The only deliberately
retained legacy string is the content ID `lumen_crystal`, preserved because it
is written into existing item saves; its player-facing name is **Radiant
Crystal**.

## Core content

- Nine surface identities: Forest, Desert, Jungle, Corruption, Crimson, Hallow,
  Snow, Ocean, Mushroom.
- Corruption and Crimson are mutually exclusive by default.
- Hallow is gated behind the Underworld progression flag.
- Five vertical layers: surface, underground, caverns, Underworld and sky.
- Terraria loops: explore, mine, build, craft, equip, fight, loot, talk to NPCs,
  defeat bosses and progress.

Legacy engine biome IDs remain internal (for generated terrain and saves), but
the UI and documentation present the core roster above. Internal block names
such as `hush_soil` are implementation details, not project identity.

## Technical boundaries

- Godot 4.7.2, GDScript, GL Compatibility.
- Existing chunk streaming, deterministic world generation, terrain atlas,
  sparse save journal and gameplay systems are authoritative.
- Reference content is adapted, never used to replace the architecture.
- No parallel inventory, item, biome, enemy or save systems.

## Attribution

UI heart sprites are from [SkyUOI/Terraria3D](https://github.com/SkyUOI/Terraria3D),
MIT licensed. See `res/terraria3d/LICENSE-SkyUOI-Terraria3D.txt` and
`res/terraria3d/ATTRIBUTION.md`.
