extends Node3D
class_name WeaponBase

# Важно: без @export!
var weapon_resource: WeaponResource

func set_weapon_resource(res: WeaponResource):
	weapon_resource = res
	# Можно добавить автоматическую настройку модели здесь
	if weapon_resource and has_node("Model"):
		pass

func get_weapon_resource() -> WeaponResource:
	return weapon_resource
