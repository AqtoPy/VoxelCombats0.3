extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var weapon_position: Marker3D = $WeaponPosition

var is_busy: bool = false

enum HandState {
	IDLE,
	DRAWING,
	HOLSTERING,
	AIMING,
	SHOOTING,
	RELOADING,
	MELEE
}

var current_state: HandState = HandState.IDLE

func play_animation(anim_name: String, speed: float = 1.0) -> void:
	is_busy = true
	
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name, -1, speed)
		match anim_name:
			"draw": current_state = HandState.DRAWING
			"holster": current_state = HandState.HOLSTERING
			"shoot": current_state = HandState.SHOOTING
			"reload": current_state = HandState.RELOADING
			"melee": current_state = HandState.MELEE
			"aim_in", "aim_out": current_state = HandState.AIMING
			_: current_state = HandState.IDLE
	is_busy = false

func get_weapon_position() -> Marker3D:
	return weapon_position

func _on_animation_finished(anim_name: String):
	if anim_name in ["draw", "holster", "reload", "melee", "aim_out"]:
		current_state = HandState.IDLE
	elif anim_name == "aim_in":
		current_state = HandState.AIMING
