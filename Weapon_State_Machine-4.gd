extends Node3D
class_name WeaponManager

# Signals
signal weapon_changed(weapon_name: String)
signal update_ammo(ammo: Array)
signal update_weapon_stack(weapons: Array)
signal hit_successful
signal add_signal_to_hud
signal connect_weapon_to_hud(weapon: WeaponResource)
signal weapon_purchased(weapon_name: String)
signal weapon_selected(weapon_slot: WeaponSlot)

# Enums
enum WeaponCategory {
	PRIMARY,
	SECONDARY,
	MELEE,
	EXPLOSIVE
}

# Exported variables
@export var animation_player: AnimationPlayer
@export var melee_hitbox: ShapeCast3D
@export var max_weapons: int = 3
@export var hands_scene: PackedScene
@export var crosshair_texture: PackedScene
@export var default_weapons: Array[PackedScene] = []

# Nodes
@onready var bullet_point: Node3D = %BulletPoint if has_node("%BulletPoint") else null
@onready var debug_bullet = preload("res://Player_Controller/Spawnable_Objects/hit_debug.tscn")
@onready var crosshair = preload("res://Player_Controller/HUD ASSETS/crosshair001.png")

# Variables
var hands_instance: Node3D = null
var current_crosshair: Control = null
var next_weapon: WeaponSlot = null
var spray_profiles: Dictionary = {}
var _count: int = 0
var shot_tween: Tween = null

var is_reloading: bool = false
var reload_interrupted: bool = false
var is_melee_attacking: bool = false
var melee_cooldown: bool = false

# Weapon system
@export var weapon_stack: Array[WeaponSlot] # Player's weapons
var current_weapon_slot: WeaponSlot = null
var available_weapons: Array[WeaponSlot] = [] # All available weapons
var weapon_instances: Dictionary = {}

var current_category: WeaponCategory = WeaponCategory.PRIMARY
var weapon_categories: Dictionary = {
	WeaponCategory.PRIMARY: null,
	WeaponCategory.SECONDARY: null,
	WeaponCategory.MELEE: null,
	WeaponCategory.EXPLOSIVE: null
}

# Weapon shop
var weapon_shop = {
	"pistol": {
		"cost": 100,
		"scene": preload("res://weapons/glock.tscn") if ResourceLoader.exists("res://weapons/glock.tscn") else null,
		"resource": preload("res://weapons/Glock.tres") if ResourceLoader.exists("res://weapons/Glock.tres") else null
	},
	"rifle": {
		"cost": 300,
		"scene": preload("res://weapons/ak-47.tscn") if ResourceLoader.exists("res://weapons/ak-47.tscn") else null,
		"resource": preload("res://weapons/AK-47.tres") if ResourceLoader.exists("res://weapons/AK-47.tres") else null
	},
	"shotgun": {
		"cost": 500,
		"scene": preload("res://weapons/spas_12.tscn") if ResourceLoader.exists("res://weapons/spas_12.tscn") else null,
		"resource": preload("res://weapons/spas_12.tres") if ResourceLoader.exists("res://weapons/spas_12.tres") else null
	}
}

func _ready() -> void:
	# Multiplayer setup
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(str(name).to_int())
	
	# Initialization
	initialize_hands()
	await get_tree().process_frame
	clear_weapons()
	load_default_weapons()
	
	if weapon_stack.is_empty():
		push_error("No weapons loaded in weapon stack!")
		return
	
	initialize_and_categorize_weapons()
	equip_default_weapon()

func clear_weapons():
	weapon_stack.clear()
	for child in get_children():
		if child is WeaponBase:
			child.queue_free()
	weapon_instances.clear()
	weapon_categories = {
		WeaponCategory.PRIMARY: null,
		WeaponCategory.SECONDARY: null,
		WeaponCategory.MELEE: null,
		WeaponCategory.EXPLOSIVE: null
	}

func initialize_hands() -> void:
	if hands_scene:
		hands_instance = hands_scene.instantiate()
		add_child(hands_instance)
		animation_player = hands_instance.get_node("AnimationPlayer") if hands_instance.has_node("AnimationPlayer") else null
	else:
		push_error("Hands scene not assigned!")

func load_default_weapons() -> void:
	for weapon_scene in default_weapons:
		if !weapon_scene:
			push_error("Empty weapon scene in default_weapons!")
			continue
			
		var weapon = weapon_scene.instantiate()
		var weapon_res = weapon.get_weapon_resource() if weapon.has_method("get_weapon_resource") else null
		
		if !weapon_res:
			weapon_res = preload("res://weapons/spas_12.tres")
			if weapon.has_method("set_weapon_resource"):
				weapon.set_weapon_resource(weapon_res)
				
		var slot = WeaponSlot.new()
		slot.weapon = weapon_res
		slot.current_ammo = slot.weapon.magazine_size if slot.weapon else 0
		slot.reserve_ammo = (slot.weapon.max_ammo - slot.weapon.magazine_size) if slot.weapon else 0
		weapon_stack.append(slot)
		weapon.queue_free()

func initialize_and_categorize_weapons():
	for slot in weapon_stack:
		initialize_weapon(slot)
		categorize_weapon_slot(slot)

func categorize_weapon_slot(slot: WeaponSlot):
	match slot.weapon.slot_type:
		"primary":
			if !weapon_categories[WeaponCategory.PRIMARY]:
				weapon_categories[WeaponCategory.PRIMARY] = slot
		"secondary":
			if !weapon_categories[WeaponCategory.SECONDARY]:
				weapon_categories[WeaponCategory.SECONDARY] = slot
		"melee":
			if !weapon_categories[WeaponCategory.MELEE]:
				weapon_categories[WeaponCategory.MELEE] = slot
		"explosive":
			if !weapon_categories[WeaponCategory.EXPLOSIVE]:
				weapon_categories[WeaponCategory.EXPLOSIVE] = slot

func equip_default_weapon():
	var start_weapon = null
	if weapon_categories[WeaponCategory.PRIMARY]:
		start_weapon = weapon_categories[WeaponCategory.PRIMARY]
	elif weapon_categories[WeaponCategory.SECONDARY]:
		start_weapon = weapon_categories[WeaponCategory.SECONDARY]
	else:
		start_weapon = weapon_stack[0] if !weapon_stack.is_empty() else null
		
	if start_weapon:
		var category = get_category_for_slot(start_weapon)
		enter(start_weapon, category)
	else:
		push_error("Failed to find any valid starting weapon")

func get_category_for_slot(slot: WeaponSlot) -> WeaponCategory:
	for category in weapon_categories:
		if weapon_categories[category] == slot:
			return category
	return WeaponCategory.PRIMARY  # Default fallback

func initialize_weapon(weapon_slot: WeaponSlot) -> void:
	if !is_instance_valid(weapon_slot) or !weapon_slot.weapon:
		push_error("Invalid WeaponSlot or missing WeaponResource")
		return
	
	if weapon_instances.has(weapon_slot):
		push_warning("Weapon already initialized for slot: ", weapon_slot.weapon.weapon_name)
		return
	
	if !weapon_slot.weapon.weapon_scene:
		push_error("Missing weapon scene in resource: ", weapon_slot.weapon.resource_path)
		return
	
	var weapon_scene = weapon_slot.weapon.weapon_scene.instantiate()
	
	if weapon_scene.has_method("set_weapon_resource"):
		weapon_scene.set_weapon_resource(weapon_slot.weapon)
	else:
		push_error("Weapon scene missing set_weapon_resource() method")
		weapon_scene.queue_free()
		return
	
	add_child(weapon_scene)
	weapon_instances[weapon_slot] = weapon_scene
	weapon_scene.visible = false
	
	# Sync weapon initialization in multiplayer
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("remote_initialize_weapon", weapon_slot.weapon.resource_path)

@rpc("call_remote", "any_peer", "reliable")
func remote_initialize_weapon(weapon_path: String):
	var weapon_res = load(weapon_path)
	var slot = WeaponSlot.new()
	slot.weapon = weapon_res
	initialize_weapon(slot)

func enter(target_slot: WeaponSlot, category: WeaponCategory) -> void:
	if !is_instance_valid(target_slot) or !target_slot.weapon:
		push_error("Invalid weapon slot")
		return
	
	# Exit current weapon if needed
	if current_weapon_slot and current_weapon_slot != target_slot:
		exit(current_weapon_slot)
	
	# Hide all weapons
	for slot in weapon_instances:
		weapon_instances[slot].visible = false
	
	# Show selected weapon
	weapon_instances[target_slot].visible = true
	current_weapon_slot = target_slot
	current_category = category
	
	# Play appropriate animations
	match category:
		WeaponCategory.PRIMARY, WeaponCategory.SECONDARY:
			play_firearm_animations(target_slot)
		WeaponCategory.MELEE:
			play_melee_draw_animation(target_slot)
		WeaponCategory.EXPLOSIVE:
			play_explosive_draw_animation(target_slot)
	
	update_hud(target_slot)
	
	# Sync weapon change in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_weapon_changed", weapon_stack.find(target_slot), category)

@rpc("call_remote", "any_peer", "reliable")
func remote_weapon_changed(slot_index: int, category: int):
	if slot_index < 0 or slot_index >= weapon_stack.size():
		return
	enter(weapon_stack[slot_index], category)

func play_firearm_animations(slot: WeaponSlot) -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play(slot.weapon.pick_up_animation)
	
	if hands_instance:
		hands_instance.play_animation(
			slot.weapon.hands_draw_animation,
			slot.weapon.hands_animation_speed
		)

func play_melee_draw_animation(slot: WeaponSlot) -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play("melee_draw")
	
	if hands_instance:
		hands_instance.play_animation(
			"hands_melee_draw",
			slot.weapon.hands_animation_speed
		)

func play_explosive_draw_animation(slot: WeaponSlot) -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play("explosive_draw")
	
	if hands_instance:
		hands_instance.play_animation(
			"hands_explosive_draw",
			slot.weapon.hands_animation_speed
		)

func exit(current_slot: WeaponSlot) -> void:
	if !current_slot: return
	
	match current_category:
		WeaponCategory.PRIMARY, WeaponCategory.SECONDARY:
			animation_player.queue(current_slot.weapon.change_animation)
			hands_instance.play_animation(
				current_slot.weapon.hands_holster_animation,
				current_slot.weapon.hands_animation_speed
			)
		WeaponCategory.MELEE:
			animation_player.queue("melee_holster")
			hands_instance.play_animation("hands_melee_holster", 1.0)
		WeaponCategory.EXPLOSIVE:
			animation_player.queue("explosive_holster")
			hands_instance.play_animation("hands_explosive_holster", 1.0)

func switch_to_weapon(category: WeaponCategory) -> void:
	if category == current_category: 
		return
	
	var target_slot = weapon_categories.get(category)
	if target_slot:
		exit(current_weapon_slot)
		enter(target_slot, category)

func update_hud(slot: WeaponSlot) -> void:
	weapon_changed.emit(slot.weapon.weapon_name)
	
	match current_category:
		WeaponCategory.PRIMARY, WeaponCategory.SECONDARY:
			update_ammo.emit([slot.current_ammo, slot.reserve_ammo])
		WeaponCategory.MELEE:
			update_ammo.emit([0, 0])
		WeaponCategory.EXPLOSIVE:
			update_ammo.emit([slot.current_ammo, 0])

# Weapon shop functions
func buy_weapon(weapon_name: String, player_money: int) -> bool:
	if weapon_shop.has(weapon_name):
		var weapon_data = weapon_shop[weapon_name]
		if player_money >= weapon_data["cost"]:
			var new_slot = create_weapon_slot(weapon_name)
			available_weapons.append(new_slot)
			weapon_purchased.emit(weapon_name)
			
			# Sync purchase in multiplayer
			if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
				rpc("remote_weapon_purchased", weapon_name)
			return true
	return false

@rpc("call_remote", "any_peer", "reliable")
func remote_weapon_purchased(weapon_name: String):
	var new_slot = create_weapon_slot(weapon_name)
	available_weapons.append(new_slot)
	weapon_purchased.emit(weapon_name)

func create_weapon_slot(weapon_name: String) -> WeaponSlot:
	var slot = WeaponSlot.new()
	slot.weapon = weapon_shop[weapon_name]["resource"]
	slot.current_ammo = slot.weapon.magazine
	slot.reserve_ammo = slot.weapon.max_ammo
	return slot

func select_weapon_from_menu(weapon_slot: WeaponSlot) -> void:
	if weapon_stack.size() >= max_weapons:
		weapon_stack[0] = weapon_slot
	else:
		weapon_stack.append(weapon_slot)
	
	initialize_weapon(weapon_slot)
	exit(weapon_slot)
	weapon_selected.emit(weapon_slot)
	
	# Sync selection in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_weapon_selected", weapon_stack.find(weapon_slot))

@rpc("call_remote", "any_peer", "reliable")
func remote_weapon_selected(slot_index: int):
	if slot_index < 0 or slot_index >= weapon_stack.size():
		return
	var slot = weapon_stack[slot_index]
	initialize_weapon(slot)
	exit(slot)
	weapon_selected.emit(slot)

# Combat functions
func shoot() -> void:
	if !check_valid_weapon_slot() or hands_instance.is_busy:
		return
	
	if current_weapon_slot.current_ammo <= 0:
		if current_weapon_slot.reserve_ammo > 0:
			reload()
		else:
			if animation_player.has_animation(current_weapon_slot.weapon.out_of_ammo_animation):
				animation_player.play(current_weapon_slot.weapon.out_of_ammo_animation)
		return
	
	var weapon_instance = weapon_instances[current_weapon_slot]
	var weapon_anim_player: AnimationPlayer = weapon_instance.get_node("AnimationPlayer") if weapon_instance.has_node("AnimationPlayer") else null
	
	if weapon_anim_player and weapon_anim_player.is_playing():
		return
	
	# Play animations locally
	if weapon_anim_player and weapon_anim_player.has_animation("spshoot"):
		weapon_anim_player.play("spshoot")
	
	if hands_instance.has_method("play_animation"):
		hands_instance.play_animation(
			current_weapon_slot.weapon.hands_shoot_animation,
			current_weapon_slot.weapon.hands_animation_speed
		)
	
	# Update ammo
	current_weapon_slot.current_ammo -= 1
	update_ammo.emit([current_weapon_slot.current_ammo, current_weapon_slot.reserve_ammo])
	
	# Calculate spread and load projectile
	var spread = calculate_spread()
	load_projectile.rpc(spread)
	
	# Handle automatic fire
	if current_weapon_slot.weapon.is_automatic and Input.is_action_pressed("shoot"):
		var fire_delay = 1.0 / current_weapon_slot.weapon.fire_rate
		await get_tree().create_timer(fire_delay).timeout
		if current_weapon_slot.current_ammo > 0:
			shoot()

func calculate_spread() -> Vector2:
	var spread = Vector2.ZERO
	if current_weapon_slot.weapon.weapon_spray:
		_count += 1
		var weapon_name = current_weapon_slot.weapon.weapon_name
		if spray_profiles.has(weapon_name):
			var spray_profile = spray_profiles[weapon_name]
			if spray_profile.has_method("get_spray"):
				spread = spray_profile.get_spray(
					_count, 
					current_weapon_slot.weapon.magazine_size
				)
	
	# Reset spread counter
	if shot_tween:
		shot_tween.kill()
	shot_tween = create_tween()
	shot_tween.tween_property(self, "_count", 0.0, 0.5)
	
	return spread

@rpc("call_remote", "any_peer", "reliable")
func load_projectile(spread: Vector2) -> void:
	if !current_weapon_slot or !bullet_point:
		return
	
	var projectile: Projectile = current_weapon_slot.weapon.projectile_to_load.instantiate()
	projectile.position = bullet_point.global_position
	projectile.rotation = owner.rotation
	bullet_point.add_child(projectile)
	add_signal_to_hud.emit(projectile)
	var bullet_point_origin = bullet_point.global_position
	projectile._set_projectile(
		current_weapon_slot.weapon.damage,
		spread,
		current_weapon_slot.weapon.fire_range,
		bullet_point_origin
	)

func reload() -> void:
	if !check_valid_weapon_slot() or is_reloading:
		return
	
	if current_weapon_slot.current_ammo == current_weapon_slot.weapon.magazine_size:
		return
	
	if current_weapon_slot.reserve_ammo <= 0:
		play_empty_reload_animation()
		return
	
	start_reload_sequence()
	
	# Sync reload in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_reload_start")

@rpc("call_remote", "any_peer", "reliable")
func remote_reload_start():
	if !check_valid_weapon_slot() or is_reloading:
		return
	start_reload_sequence()

func start_reload_sequence() -> void:
	is_reloading = true
	reload_interrupted = false
	
	if hands_instance.has_method("play_animation"):
		hands_instance.play_animation(
			current_weapon_slot.weapon.hands_reload_animation,
			current_weapon_slot.weapon.hands_animation_speed
		)
	
	var weapon_instance = weapon_instances[current_weapon_slot]
	if weapon_instance.has_node("AnimationPlayer"):
		var weapon_anim = weapon_instance.get_node("AnimationPlayer")
		if weapon_anim.has_animation("reload"):
			weapon_anim.play("reload")
	
	if current_weapon_slot.weapon.incremental_reload:
		await get_tree().create_timer(current_weapon_slot.weapon.reload_time).timeout
		if !reload_interrupted:
			finish_incremental_reload()
	else:
		if weapon_instance.has_node("AnimationPlayer"):
			await weapon_instance.get_node("AnimationPlayer").animation_finished
		if !reload_interrupted:
			finish_full_reload()

func finish_incremental_reload() -> void:
	if current_weapon_slot.reserve_ammo > 0:
		current_weapon_slot.current_ammo += 1
		current_weapon_slot.reserve_ammo -= 1
		update_ammo.emit([current_weapon_slot.current_ammo, current_weapon_slot.reserve_ammo])
	
	if should_continue_reloading():
		start_reload_sequence()
	else:
		is_reloading = false
		
		# Sync reload finish in multiplayer
		if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
			rpc("remote_reload_finish")

func finish_full_reload() -> void:
	var needed = current_weapon_slot.weapon.magazine_size - current_weapon_slot.current_ammo
	var can_add = min(needed, current_weapon_slot.reserve_ammo)
	
	current_weapon_slot.current_ammo += can_add
	current_weapon_slot.reserve_ammo -= can_add
	
	update_ammo.emit([current_weapon_slot.current_ammo, current_weapon_slot.reserve_ammo])
	is_reloading = false
	
	# Sync reload finish in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_reload_finish")

@rpc("call_remote", "any_peer", "reliable")
func remote_reload_finish():
	is_reloading = false

func play_empty_reload_animation() -> void:
	var weapon_instance = weapon_instances[current_weapon_slot]
	if weapon_instance.has_node("AnimationPlayer"):
		var weapon_anim = weapon_instance.get_node("AnimationPlayer")
		if weapon_anim.has_animation("reload_empty"):
			weapon_anim.play("reload_empty")

	if hands_instance.has_method("play_animation"):
		hands_instance.play_animation(
			current_weapon_slot.weapon.hands_empty_reload_animation,
			current_weapon_slot.weapon.hands_animation_speed
		)

func interrupt_reload() -> void:
	if is_reloading:
		reload_interrupted = true
		is_reloading = false
		
		var weapon_instance = weapon_instances[current_weapon_slot]
		if weapon_instance.has_node("AnimationPlayer"):
			weapon_instance.get_node("AnimationPlayer").stop()
		
		if hands_instance.has_method("stop_animation"):
			hands_instance.stop_animation()

func should_continue_reloading() -> bool:
	return (
		!reload_interrupted and
		current_weapon_slot.current_ammo < current_weapon_slot.weapon.magazine_size and
		current_weapon_slot.reserve_ammo > 0 and
		Input.is_action_pressed("reload")
	)

# Melee functions
func melee() -> void:
	if !check_valid_weapon_slot() or is_melee_attacking or melee_cooldown:
		return
	
	if (animation_player.is_playing() and 
		(animation_player.current_animation == current_weapon_slot.weapon.shoot_animation or
		 animation_player.current_animation == current_weapon_slot.weapon.reload_animation)):
		return
	
	start_melee_attack()
	
	# Sync melee in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_melee_attack")

@rpc("call_remote", "any_peer", "reliable")
func remote_melee_attack():
	if !check_valid_weapon_slot() or is_melee_attacking or melee_cooldown:
		return
	start_melee_attack()

func start_melee_attack() -> void:
	is_melee_attacking = true
	
	var weapon_instance = weapon_instances[current_weapon_slot]
	if weapon_instance.has_node("AnimationPlayer"):
		var weapon_anim = weapon_instance.get_node("AnimationPlayer")
		if weapon_anim.has_animation("melee"):
			weapon_anim.play("melee")
	
	if hands_instance.has_method("play_animation"):
		hands_instance.play_animation(
			current_weapon_slot.weapon.hands_melee_animation,
			current_weapon_slot.weapon.hands_animation_speed
		)
	
	melee_hitbox.force_shapecast_update()
	await get_tree().create_timer(0.2).timeout
	check_melee_hit()
	
	if weapon_instance.has_node("AnimationPlayer"):
		await weapon_instance.get_node("AnimationPlayer").animation_finished
	is_melee_attacking = false
	
	melee_cooldown = true
	await get_tree().create_timer(0.5).timeout
	melee_cooldown = false

func check_melee_hit() -> void:
	if !melee_hitbox.is_colliding():
		return
	
	for i in range(melee_hitbox.get_collision_count()):
		var target = melee_hitbox.get_collider(i)
		if target and target.is_in_group("Target") and target.has_method("hit_successful"):
			var direction = (target.global_position - global_position).normalized()
			var position = melee_hitbox.get_collision_point(i)
			
			target.hit_successful(
				current_weapon_slot.weapon.melee_damage, 
				direction, 
				position
			)
			hit_successful.emit()

# Weapon drop
func drop(slot: WeaponSlot) -> void:
	if !check_valid_weapon_slot() or !slot.weapon.can_be_dropped or weapon_stack.size() <= 1:
		return
		
	var weapon_index = weapon_stack.find(slot)
	if weapon_index != -1:
		weapon_stack.remove_at(weapon_index)
		update_weapon_stack.emit(weapon_stack)

		if slot.weapon.weapon_drop:
			var weapon_dropped = slot.weapon.weapon_drop.instantiate()
			weapon_dropped.weapon = slot
			weapon_dropped.global_transform = bullet_point.global_transform
			get_tree().root.add_child(weapon_dropped)
			
			animation_player.play(current_weapon_slot.weapon.drop_animation)
			weapon_index = max(weapon_index - 1, 0)
			exit(weapon_stack[weapon_index])
			
			# Sync drop in multiplayer
			if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
				rpc("remote_weapon_drop", weapon_index)

@rpc("call_remote", "any_peer", "reliable")
func remote_weapon_drop(slot_index: int):
	if slot_index < 0 or slot_index >= weapon_stack.size():
		return
	
	var slot = weapon_stack[slot_index]
	if !slot.weapon.can_be_dropped or weapon_stack.size() <= 1:
		return
		
	weapon_stack.remove_at(slot_index)
	update_weapon_stack.emit(weapon_stack)
	
	if slot.weapon.weapon_drop:
		var weapon_dropped = slot.weapon.weapon_drop.instantiate()
		weapon_dropped.weapon = slot
		weapon_dropped.global_transform = bullet_point.global_transform
		get_tree().root.add_child(weapon_dropped)
		
		animation_player.play(current_weapon_slot.weapon.drop_animation)
		slot_index = max(slot_index - 1, 0)
		exit(weapon_stack[slot_index])

# Input handling
func _process(delta: float) -> void:
	if !is_instance_valid(current_weapon_slot) or !hands_instance:
		return

	if hands_instance.is_busy:
		return

	if Input.is_action_pressed("Shoot"):
		if check_valid_weapon_slot() and current_weapon_slot.current_ammo > 0:
			shoot()
		else:
			if check_valid_weapon_slot() and current_weapon_slot.reserve_ammo > 0:
				reload()

	if check_valid_weapon_slot() and current_weapon_slot.current_ammo <= 0:
		if current_weapon_slot.reserve_ammo > 0:
			reload()

	handle_weapon_switch_input()

	if weapon_instances.has(current_weapon_slot):
		var weapon_node = weapon_instances[current_weapon_slot]
		if weapon_node:
			weapon_node.global_transform = hands_instance.get_node("WeaponPosition").global_transform

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon_1"):
		switch_to_weapon(WeaponCategory.PRIMARY)
	elif event.is_action_pressed("weapon_2"):
		switch_to_weapon(WeaponCategory.SECONDARY)
	elif event.is_action_pressed("weapon_3"):
		switch_to_weapon(WeaponCategory.MELEE)
	elif event.is_action_pressed("weapon_4"):
		switch_to_weapon(WeaponCategory.EXPLOSIVE)
		
	if event.is_action_pressed("Shoot"):
		if check_valid_weapon_slot():
			shoot()
	
	if event.is_action_released("Shoot"):
		if check_valid_weapon_slot():
			shot_count_update()
	
	if event.is_action_pressed("Reload"):
		if check_valid_weapon_slot():
			reload()
		
	if event.is_action_pressed("Drop_Weapon"):
		if check_valid_weapon_slot():
			drop(current_weapon_slot)
		
	if event.is_action_pressed("Melee"):
		if check_valid_weapon_slot():
			melee()

func handle_weapon_switch_input() -> void:
	var scroll_value = Input.get_axis("WeaponDown", "WeaponUp")
	if scroll_value != 0:
		var current_index = weapon_stack.find(current_weapon_slot)
		var new_index = wrapi(current_index + scroll_value, 0, weapon_stack.size())
		var new_slot = weapon_stack[new_index]
		
		if new_slot != current_weapon_slot:
			exit(current_weapon_slot)
			enter(new_slot, WeaponCategory.PRIMARY)

# Utility functions
func check_valid_weapon_slot() -> bool:
	return (
		is_instance_valid(current_weapon_slot) and 
		is_instance_valid(current_weapon_slot.weapon) and 
		weapon_instances.has(current_weapon_slot)
	)

func shot_count_update() -> void:
	shot_tween = get_tree().create_tween()
	shot_tween.tween_property(self, "_count", 0, 1)

func aim(is_aiming: bool):
	if is_aiming:
		hands_instance.play_animation(current_weapon_slot.weapon.hands_aim_in_animation,
						  current_weapon_slot.weapon.hands_animation_speed)
	else:
		hands_instance.play_animation(current_weapon_slot.weapon.hands_aim_out_animation,
						  current_weapon_slot.weapon.hands_animation_speed)

func set_weapon_visibility(slot: WeaponSlot, visible: bool):
	if slot in weapon_instances:
		weapon_instances[slot].visible = visible

func get_weapon_instance(slot: WeaponSlot) -> Node3D:
	return weapon_instances.get(slot)

func equip_to_slot(slot: int, weapon_scene: PackedScene):
	if slot >= weapon_stack.size():
		weapon_stack.resize(slot + 1)
	
	var new_weapon = weapon_scene.instantiate()
	var weapon_slot = WeaponSlot.new()
	weapon_slot.weapon = new_weapon.weapon_resource
	weapon_stack[slot] = weapon_slot
	update_weapon_stack.emit(weapon_stack)
	
	# Sync equip in multiplayer
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_equip_to_slot", slot, weapon_slot.weapon.resource_path)

@rpc("call_remote", "any_peer", "reliable")
func remote_equip_to_slot(slot: int, weapon_path: String):
	if slot >= weapon_stack.size():
		weapon_stack.resize(slot + 1)
	
	var weapon_res = load(weapon_path)
	var weapon_slot = WeaponSlot.new()
	weapon_slot.weapon = weapon_res
	weapon_stack[slot] = weapon_slot
	update_weapon_stack.emit(weapon_stack)

# Animation callbacks
func _on_animation_finished(anim_name: String) -> void:
	if !current_weapon_slot:
		return
		
	if anim_name == current_weapon_slot.weapon.shoot_animation:
		if current_weapon_slot.weapon.auto_fire and Input.is_action_pressed("Shoot"):
			shoot()

	if anim_name == current_weapon_slot.weapon.change_animation:
		change_weapon(next_weapon)
	
	if anim_name == current_weapon_slot.weapon.reload_animation and !current_weapon_slot.weapon.incremental_reload:
		calculate_reload()

func change_weapon(new_slot: WeaponSlot) -> void:
	if !weapon_stack.has(new_slot):
		return
	
	if current_weapon_slot:
		weapon_instances[current_weapon_slot].visible = false
	
	enter(new_slot, WeaponCategory.PRIMARY)

func calculate_reload() -> void:
	# 1. Проверка валидности текущего оружия
	if !check_valid_weapon_slot():
		return
	
	# 2. Проверка необходимости перезарядки
	if current_weapon_slot.current_ammo == current_weapon_slot.weapon.magazine_size:
		# Если магазин уже полный, пропускаем перезарядку
		if animation_player:
			var anim_length = animation_player.get_animation(current_weapon_slot.weapon.reload_animation).length
			animation_player.advance(anim_length)
		return
	
	# 3. Проверка наличия патронов
	if current_weapon_slot.reserve_ammo <= 0:
		play_empty_reload_animation()
		return
	
	# 4. Расчет количества патронов для перезарядки
	var reload_amount = 0
	
	if current_weapon_slot.weapon.incremental_reload:
		# Инкрементальная перезарядка (по одному патрону, например для дробовиков)
		reload_amount = 1
	else:
		# Полная перезарядка (замена всего магазина)
		var needed = current_weapon_slot.weapon.magazine_size - current_weapon_slot.current_ammo
		reload_amount = min(needed, current_weapon_slot.reserve_ammo)
	
	# 5. Обновление количества патронов
	current_weapon_slot.current_ammo += reload_amount
	current_weapon_slot.reserve_ammo -= reload_amount
	
	# 6. Синхронизация в мультиплеере
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("remote_update_ammo", current_weapon_slot.current_ammo, current_weapon_slot.reserve_ammo)
	
	# 7. Обновление HUD
	update_ammo.emit([current_weapon_slot.current_ammo, current_weapon_slot.reserve_ammo])
	
	# 8. Сброс счетчика выстрелов для разброса
	shot_count_update()

@rpc("call_remote", "any_peer", "reliable")
func remote_update_ammo(current: int, reserve: int):
	if !check_valid_weapon_slot():
		return
	current_weapon_slot.current_ammo = current
	current_weapon_slot.reserve_ammo = reserve
	update_ammo.emit([current, reserve])
