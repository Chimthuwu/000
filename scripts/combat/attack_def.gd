extends Resource
class_name AttackDef

## Data-only definition of a weapon attack. Kept separate from ItemDef so new
## weapon categories can be added without changing the inventory model.

@export var attack_id: StringName = &""
@export_enum("melee", "ranged", "magic", "thrown") var kind: String = "melee"
@export_range(0.0, 10000.0, 1.0) var damage: float = 10.0
@export_range(0.05, 10.0, 0.01) var cooldown: float = 0.6
@export_range(0.3, 12.0, 0.1) var range: float = 2.6
@export_range(1.0, 360.0, 1.0) var arc_degrees: float = 110.0
@export_range(0.0, 30.0, 0.1) var knockback: float = 4.0
@export_range(0.0, 60.0, 0.5) var projectile_speed: float = 20.0
@export_range(0.0, 30.0, 0.1) var projectile_gravity: float = 8.0
@export_range(0.1, 20.0, 0.1) var projectile_lifetime: float = 3.0
@export_range(0, 16, 1) var pierce: int = 0
@export_range(0.0, 200.0, 1.0) var mana_cost: float = 0.0
@export var status_id: StringName = &""
@export var status_duration: float = 0.0
@export var accent_color: Color = Color(1.0, 0.86, 0.5, 1.0)
