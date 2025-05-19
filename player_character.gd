extends CharacterBody3D

## === Movement Settings === ##
@export_category("Movement Settings")
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var air_control: float = 0.3
@export var ground_acceleration: float = 12.0  # Увеличено для лучшего контроля
@export var friction: float = 6.0
@export var gravity: float = 9.8
@export var max_air_speed: float = 10.0

## === Player Settings === ##
@export_category("Player Settings")
@export var player_name: String = "Player":
    set(value):
        player_name = value
        update_nickname_display()
@export var clan_tag: String = "":
    set(value):
        clan_tag = value
        update_nickname_display()
@export var health: int = 100:
    set(value):
        health = clamp(value, 0, 100)
        if health <= 0 and is_alive:
            die()

## === Camera Settings === ##
@export_category("Camera Settings")
@export var mouse_sensitivity: float = 0.2
@export var max_look_angle: float = 90.0
@export var min_look_angle: float = -90.0

## === Components === ##
@onready var camera_pivot = %Camera
@onready var camera = %MainCamera
@onready var weapon_manager = $Camera/LeanPivot/MainCamera/Weapons_Manager
@onready var nickname_label = $NameLabel
@onready var death_camera = $Camera3D
@onready var respawn_timer = $RespawnTimer
@onready var skin_mesh = $CharacterMesh  # Новая нода для скина

## === Variables === ##
var current_speed: float = 0.0
var is_running: bool = false
var wish_dir: Vector3 = Vector3.ZERO
var player_id: int = 0
var is_vip: bool = false  # Новая переменная VIP статуса
var is_grounded: bool = false
var was_grounded: bool = false
var is_alive: bool = true
var killer_id: int = -1
var team: String = ""

# Network sync
var sync_position: Vector3
var sync_rotation: Vector2
var last_sync_time: float = 0.0
const SYNC_INTERVAL: float = 0.1

func _ready():
    if multiplayer.has_multiplayer_peer():
        player_id = multiplayer.get_unique_id()
        set_multiplayer_authority(player_id)
    
    if is_multiplayer_authority():
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
        camera.current = true
        death_camera.current = false
    else:
        set_process(false)
        camera.current = false
    
    update_nickname_display()
    _load_skin()  # Загрузка скина при старте

func _physics_process(delta):
    if not is_multiplayer_authority() or not is_alive:
        return
    
    _handle_movement(delta)
    _handle_jump()
    
    move_and_slide()
    
    was_grounded = is_grounded
    is_grounded = is_on_floor()
    
    # Синхронизация состояния
    last_sync_time += delta
    if last_sync_time >= SYNC_INTERVAL:
        last_sync_time = 0.0
        _sync_player_state()

func _handle_movement(delta):
    var input_dir = Input.get_vector("left", "right", "up", "down")
    var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    
    var target_speed = run_speed if is_running else walk_speed
    
    if is_grounded:
        # Улучшенное управление на земле
        var current_vel = velocity
        current_vel.y = 0
        
        var speed_diff = target_speed - current_vel.length()
        if speed_diff > 0:
            var accel = ground_acceleration * delta
            velocity += direction * accel
        
        # Применение трения
        if direction.length() == 0:
            velocity = velocity.lerp(Vector3.ZERO, friction * delta)
    else:
        # Воздушный контроль
        var air_accel = ground_acceleration * air_control * delta
        velocity += direction * air_accel
        velocity.x = clamp(velocity.x, -max_air_speed, max_air_speed)
        velocity.z = clamp(velocity.z, -max_air_speed, max_air_speed)
    
    # Гравитация
    if not is_grounded:
        velocity.y -= gravity * delta

func _handle_jump():
    if Input.is_action_just_pressed("jump") and is_grounded:
        velocity.y = jump_velocity
        if is_vip:  # VIP бонусы
            velocity.y *= 1.15

func update_nickname_display():
    var display_text = ("[%s] %s" % [clan_tag, player_name]).strip_edges()
    nickname_label.text = display_text
    nickname_label.visible = !is_multiplayer_authority()

func _load_skin():
    # Загрузка скина из сохраненных данных игрока
    var skin_data = PlayerData.get_equipped_skin()
    if skin_data:
        var skin_material = load(skin_data.material_path)
        skin_mesh.set_surface_override_material(0, skin_material)

func die():
    if not is_alive: return
    
    is_alive = false
    visible = false
    nickname_label.visible = false
    
    if is_multiplayer_authority():
        camera.current = false
        death_camera.current = true
        respawn_timer.start(5.0)

@rpc("call_local")
func respawn():
    is_alive = true
    health = 100
    visible = true
    nickname_label.visible = !is_multiplayer_authority()
    
    if is_multiplayer_authority():
        death_camera.current = false
        camera.current = true
        _teleport_to_spawn_point()

func _teleport_to_spawn_point():
    var spawn_points = get_tree().get_nodes_in_group("spawn_%s" % team)
    if spawn_points.size() > 0:
        global_transform.origin = spawn_points.pick_random().global_transform.origin

@rpc("call_local")
func set_vip_status(status: bool):
    is_vip = status
    # Применить VIP визуальные эффекты
    $VIPIndicator.visible = status

@rpc("call_local")
func set_damage(amount: int, attacker_id: int):
    if not is_alive: return
    health -= amount
    if health <= 0:
        killer_id = attacker_id
        die()

func _sync_player_state():
    rpc("_remote_update_state", 
        global_position,
        Vector2(rotation.y, camera_pivot.rotation.x),
        velocity)

@rpc("unreliable", "any_peer")
func _remote_update_state(pos: Vector3, rot: Vector2, vel: Vector3):
    if not is_multiplayer_authority():
        global_position = pos.lerp(global_position, 0.5)
        rotation.y = lerp_angle(rotation.y, rot.x, 0.5)
        camera_pivot.rotation.x = lerp_angle(camera_pivot.rotation.x, rot.y, 0.5)
        velocity = vel.lerp(velocity, 0.5)

func _input(event):
    if not is_multiplayer_authority() or not is_alive:
        return
    
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
        camera_pivot.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
        camera_pivot.rotation.x = clamp(
            camera_pivot.rotation.x,
            deg_to_rad(min_look_angle),
            deg_to_rad(max_look_angle)
        )
    
    if event.is_action_pressed("sprint"):
        is_running = true
    if event.is_action_released("sprint"):
        is_running = false
    
    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(
            Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED 
            else Input.MOUSE_MODE_CAPTURED
        )
