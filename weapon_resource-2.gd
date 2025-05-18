@icon("res://Player_Controller/scripts/Weapon_State_Machine/weapon_resource_icon.svg")

extends Resource
class_name WeaponResource

signal update_overlay
signal zoom_changed(is_zoomed: bool)

# Группа Weapon Base
@export_category("Base Settings")
@export var weapon_id: String
@export var weapon_name: String
@export var hands_draw_animation: String
@export var hands_holster_animation: String
@export var hands_melee_animation: String
@export var hands_shoot_animation: String
@export var hands_reload_animation: String
@export var hands_animation_speed: float = 1.0
@export var slot_type: String # "primary", "secondary", "melee", "grenade"
@export var crosshair_type: String = "dot"
@export var unlock_price: int = 0
@export var unlocked: bool = true

# Групка Animations
@export_category("Weapon Animations")
@export var pick_up_animation: String
@export var shoot_animation: String
@export var reload_animation: String
@export var change_animation: String
@export var drop_animation: String
@export var out_of_ammo_animation: String
@export var melee_animation: String
@export var inspect_animation: String
@export var arms_animations: Dictionary = {
	"reload": "reload_rifle",
	"shoot": "shoot_rifle"
}

# Группа Stats
@export_category("Weapon Stats")
@export var damage: int
@export var fire_rate: float
@export var has_ammo: bool = true
@export var magazine_size: int
@export var max_ammo: int
@export var reload_time: float
@export var is_automatic: bool
@export var fire_range: int
@export var melee_damage: float
@export var can_zoom: bool
@export var zoom_fov: float = 30.0

# Группа Visuals
@export_category("Visual Settings")
@export var weapon_scene: PackedScene
@export var default_skin: Texture2D
@export var has_scope: bool
@export var scope_texture: Texture2D
@export var viewmodel_position: Vector3
@export var viewmodel_rotation: Vector3

# Группа Behavior
@export_category("Weapon Behavior")
@export var can_be_dropped: bool
@export var weapon_drop: PackedScene
@export var weapon_spray: PackedScene
@export var projectile_to_load: PackedScene
@export var incremental_reload: bool
@export var bullet_count: int = 1 # Для дробовиков
@export var spread_angle: float = 0.0
