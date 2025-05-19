extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var weapon_position: Marker3D = $WeaponPosition
@onready var camera: Camera3D = get_viewport().get_camera_3d()

# Состояния рук
enum HandState {
    IDLE,
    DRAWING,
    HOLSTERING,
    AIMING,
    SHOOTING,
    RELOADING,
    MELEE,
    SWAY
}

# Настройки реалистичного поведения
const SWAY_SPEED = 8.0
const SWAY_AMOUNT = 0.05
const POSITION_LERP_SPEED = 10.0
const ROTATION_LERP_SPEED = 12.0
const MOVEMENT_SWAY_AMOUNT = 0.01
const BREATHING_AMOUNT = 0.002
const BREATHING_SPEED = 0.5
const RECOIL_RETURN_SPEED = 5.0
const WEAPON_BOB_AMOUNT = 0.005
const WEAPON_BOB_SPEED = 10.0

var current_state: HandState = HandState.IDLE
var is_busy: bool = false
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
var sway_offset: Vector3 = Vector3.ZERO
var movement_offset: Vector3 = Vector3.ZERO
var recoil_offset: Vector3 = Vector3.ZERO
var breathing_offset: Vector3 = Vector3.ZERO
var bob_offset: Vector3 = Vector3.ZERO
var last_camera_rotation: Vector3 = Vector3.ZERO
var time: float = 0.0

func _ready():
    target_position = position
    target_rotation = rotation
    last_camera_rotation = camera.global_rotation
    animation_player.animation_finished.connect(_on_animation_finished)

func _process(delta):
    time += delta
    
    # Пропускаем обновление, если руки заняты анимацией
    if is_busy and current_state != HandState.SWAY:
        return
    
    _update_sway(delta)
    _update_breathing(delta)
    _update_movement_effects(delta)
    _update_recoil(delta)
    _apply_smooth_movement(delta)

func _update_sway(delta: float):
    # Плавное следование за камерой с задержкой
    var camera_rotation_diff = camera.global_rotation - last_camera_rotation
    last_camera_rotation = camera.global_rotation
    
    # Добавляем эффект инерции при повороте
    var sway_target = Vector3(
        -camera_rotation_diff.y * SWAY_AMOUNT * 10,
        camera_rotation_diff.x * SWAY_AMOUNT * 10,
        0
    )
    
    sway_offset = sway_offset.lerp(sway_target, delta * SWAY_SPEED)

func _update_breathing(delta: float):
    # Эффект дыхания
    breathing_offset = Vector3(
        sin(time * BREATHING_SPEED) * BREATHING_AMOUNT,
        cos(time * BREATHING_SPEED * 0.5) * BREATHING_AMOUNT,
        0
    )

func _update_movement_effects(delta: float):
    # Эффект покачивания при движении
    var player_velocity = get_parent().velocity if get_parent().has_method("get_velocity") else Vector3.ZERO
    var movement_intensity = clamp(player_velocity.length() * 0.1, 0.0, 1.0)
    
    bob_offset = Vector3(
        sin(time * WEAPON_BOB_SPEED) * WEAPON_BOB_AMOUNT * movement_intensity,
        abs(cos(time * WEAPON_BOB_SPEED * 0.5)) * WEAPON_BOB_AMOUNT * movement_intensity * 2,
        0
    )

func _update_recoil(delta: float):
    # Плавное возвращение после отдачи
    recoil_offset = recoil_offset.lerp(Vector3.ZERO, delta * RECOIL_RETURN_SPEED)

func _apply_smooth_movement(delta: float):
    # Плавное применение всех эффектов
    var total_offset = sway_offset + movement_offset + breathing_offset + bob_offset + recoil_offset
    
    position = position.lerp(target_position + total_offset, delta * POSITION_LERP_SPEED)
    rotation = rotation.lerp(target_rotation, delta * ROTATION_LERP_SPEED)

func play_animation(anim_name: String, speed: float = 1.0) -> void:
    if is_busy or not animation_player.has_animation(anim_name):
        return
    
    is_busy = true
    
    # Останавливаем текущую анимацию перед воспроизведением новой
    animation_player.stop()
    animation_player.play(anim_name, -1, speed)
    
    match anim_name:
        "draw": 
            current_state = HandState.DRAWING
        "holster": 
            current_state = HandState.HOLSTERING
        "shoot": 
            current_state = HandState.SHOOTING
            # Добавляем эффект отдачи
            _add_recoil(Vector3(randf_range(-0.01, 0.01), randf_range(0.02, 0.05))
        "reload": 
            current_state = HandState.RELOADING
        "melee": 
            current_state = HandState.MELEE
        "aim_in", "aim_out": 
            current_state = HandState.AIMING
        _: 
            current_state = HandState.IDLE

func _add_recoil(horizontal: float, vertical: float):
    # Эффект отдачи при стрельбе
    recoil_offset += Vector3(
        horizontal,
        vertical,
        0
    )

func get_weapon_position() -> Marker3D:
    return weapon_position

func _on_animation_finished(anim_name: String):
    is_busy = false
    
    match anim_name:
        "draw", "holster", "reload", "melee", "aim_out":
            current_state = HandState.IDLE
        "aim_in":
            current_state = HandState.AIMING
        "shoot":
            current_state = HandState.AIMING if Input.is_action_pressed("aim") else HandState.IDLE
