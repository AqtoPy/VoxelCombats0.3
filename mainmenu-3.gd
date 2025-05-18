extends Control

const GAME_SCENE_PATH = "res://game_scene.tscn"
const SAVED_SERVERS_PATH = "user://saved_servers.json"
const MAPS = {
	"Dust": "res://maps/Dust.tscn",
	"ZeroWall": "res://maps/ZeroWall.tscn"
}

# Сигналы
signal vip_purchased(player_id)
signal server_created(server_config: Array)
signal server_selected(server_info: Dictionary)
signal player_name_changed(new_name)
signal balance_updated(new_balance)
signal case_opened(reward: Dictionary)

# Константы
const VIP_PRICE = 0
const VIP_DAYS = 30
const SAVE_PATH = "user://player_data.dat"
const CUSTOM_MODES_DIR = "res://game_modes/"
const DEFAULT_PORT = 9050
const SERVER_PORT = 9050
const ColorGOLD = Color(1.0, 0.84, 0.0)
const CASE_ITEMS = [
	{"type": "currency", "amount": 100, "chance": 0.4},
	{"type": "currency", "amount": 500, "chance": 0.2},
	{"type": "currency", "amount": 1000, "chance": 0.1},
	{"type": "skin", "weapon": "pistol", "skin": "gold", "chance": 0.15},
	{"type": "character", "character": "ninja", "chance": 0.1},
	{"type": "vip", "days": 7, "chance": 0.05}
]

# Переменные
var multiplayer_peer = ENetMultiplayerPeer.new()
var current_server_info: Dictionary = {}
var is_server: bool = false
var active_servers = []
var udp = PacketPeerUDP.new()
var player_data = {
	"name": "Player",
	"clan_tag": "tag",
	"balance": 10000,
	"is_vip": false,
	"vip_days": 999,
	"last_played_date": "",
	"player_id": "",
	"cases_opened": 0
}
var available_maps = ["Dust", "ZeroWall"]
var available_modes = ["Deathmatch", "Team Deathmatch", "ZombieMode"]
var custom_modes = []
var saved_servers = []

var weapon_shop_data = {
	"pistol": {"price": 0, "unlocked": true},
	"rifle": {"price": 500, "unlocked": false},
	"shotgun": {"price": 700, "unlocked": false}
}

class WeaponCategory:
	enum {
		PRIMARY,
		SECONDARY,
		EXPLOSIVE
	}

var player_weapons: Dictionary = {
	WeaponCategory.PRIMARY: null,
	WeaponCategory.SECONDARY: null,
	WeaponCategory.EXPLOSIVE: null
}

var weapon_shop = {
	"SPAS-12": {
		"category": WeaponCategory.PRIMARY,
		"cost": 3000,
		"texture": preload("res://weapons/spas12prev.PNG"),
		"scene": preload("res://weapons/spas_12.tscn")
	},
	"Glock": {
		"category": WeaponCategory.SECONDARY,
		"cost": 500,
		"texture": preload("res://weapons/glockprev.PNG"),
		"scene": preload("res://weapons/glock.tscn")
	},
	"AWP": {
		"category": WeaponCategory.EXPLOSIVE,
		"cost": 1500,
		"texture": preload("res://weapons/AWPPREV.PNG"),
		"scene": preload("res://weapons/AWP.tscn")
	}
}

var player_level: int = 1
var player_xp: int = 0
var promo_codes = {
	"FREESKIN": {"used": false, "reward": {"type": "skin", "weapon": "pistol", "skin": "gold"}},
	"START1000": {"used": false, "reward": {"type": "currency", "amount": 1000}}
}

# Ноды интерфейса
@onready var main_menu = $MainMenu
@onready var server_menu = $ServerMenu
@onready var shop_menu = $ShopMenu
@onready var cases_menu = $CasesMenu

@onready var player_name_edit = $MainMenu/PlayerInfoMenu/NameEdit
@onready var clan_tag_edit = $MainMenu/PlayerInfoMenu/ClanTagEdit
@onready var balance_label = $MainMenu/PlayerInfoMenu/BalanceLabel
@onready var vip_button = $MainMenu/PlayerInfoMenu/VIPButton
@onready var vip_status_label = $MainMenu/PlayerInfoMenu/VIPStatusLabel
@onready var join_server_list = $ServerMenu/ScrollContainer/ServerList
@onready var server_name_edit = $ServerMenu/ServerConfig/NameEdit
@onready var player_limit_slider = $ServerMenu/ServerConfig/PlayersLimitSlider
@onready var player_limit_label = $ServerMenu/ServerConfig/PlayersLimitLabel
@onready var map_option = $ServerMenu/ServerConfig/MapOption
@onready var mode_option = $ServerMenu/ServerConfig/ModeOption
@onready var status_label = $StatusLabel
@onready var vip_price_label = $MainMenu/PlayerInfoMenu/VIPPrice
@onready var purchase_button = $MainMenu/PlayerInfoMenu/VIPButton
@onready var ip_edit = $ServerMenu/HBoxContainer/IPEdit
@onready var port_edit = $ServerMenu/HBoxContainer/PortSpinBox
@onready var join_status_label = $ServerMenu/StatusLabel
@onready var promo_code_edit = $MainMenu/PlayerInfoMenu/Promo
@onready var weapon_shop_list = $ShopMenu/WeaponShopList
@onready var skin_shop_list = $ShopMenu/SkinShopList
@onready var character_shop_list = $ShopMenu/CharacterShopList
@onready var level_label = $MainMenu/PlayerInfoMenu/LevelLabel
@onready var xp_bar = $MainMenu/PlayerInfoMenu/XPBar
@onready var case_button = $CasesMenu/CaseButton
@onready var case_reward_label = $CasesMenu/RewardLabel
@onready var case_reward_icon = $CasesMenu/RewardIcon
@onready var case_price_label = $CasesMenu/PriceLabel
@onready var cases_opened_label = $CasesMenu/CasesOpenedLabel
@onready var model_viewport = $MainMenu/ModelViewport
@onready var model_camera = $MainMenu/ModelViewport/ModelCamera
@onready var model_rotation_speed = 1.0

func _ready():
	equip_default_weapons()
	_setup_directories()
	_load_player_data()
	_generate_player_id()
	_setup_ui()
	_connect_signals()
	load_servers()
	setup_defaults()
	_setup_shop_ui()
	_update_level_ui()
	_setup_model_view()

func equip_default_weapons():
	player_weapons[WeaponCategory.PRIMARY] = preload("res://weapons/ak-47.tscn")
	player_weapons[WeaponCategory.SECONDARY] = preload("res://weapons/glock.tscn")

func buy_weapon(weapon_name: String, player_money: int) -> bool:
	if !weapon_shop.has(weapon_name):
		push_error("Weapon %s not found in shop!" % weapon_name)
		return false
	
	var weapon_data = weapon_shop[weapon_name]
	if player_money >= weapon_data["cost"]:
		var category = weapon_data["category"]
		player_weapons[category] = weapon_data["scene"]
		save_weapons()
		update_weapon_ui()
		return true
	return false

func equip_weapon(category: int, slot: int):
	var weapon_scene = player_weapons.get(category)
	if weapon_scene:
		# Отправляем оружие в WeaponManager
		var weapon_manager = get_node("/root/Main/Player/WeaponManager")
		weapon_manager.equip_to_slot(slot, weapon_scene)

func save_weapons():
	var save_data = {}
	for category in player_weapons:
		if player_weapons[category]:
			save_data[category] = player_weapons[category].resource_path
	# Сохраняем в FileSystem или PlayerPrefs

func update_weapon_ui():
	# Обновляем UI магазина
	$WeaponShop.update_weapons(player_weapons)
	
func _process(delta):
	# Вращение модели в главном меню
	if $MainMenu/ModelViewport/Model.visible:
		model_viewport.get_node("Model").rotate_y(delta * model_rotation_speed)

func _setup_model_view():
	model_camera.make_current()

#region Инициализация
func _setup_directories():
	DirAccess.make_dir_recursive_absolute(CUSTOM_MODES_DIR)

func setup_defaults():
	ip_edit.text = "127.0.0.1"
	port_edit.value = DEFAULT_PORT
	status_label.visible = false

func _generate_player_id():
	if player_data["player_id"] == "":
		randomize()
		player_data["player_id"] = "player_%d" % randi_range(100000, 999999)
		_save_player_data()

func _save_player_data():
	var save_data = {
		"player_data": player_data,
		"weapon_shop": weapon_shop_data,
		"promo_codes": promo_codes,
		"level": player_level,
		"xp": player_xp
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(save_data)
	file.close()

func _load_player_data():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var save_data = file.get_var()
		file.close()
		
		player_data = save_data.get("player_data", player_data)
		weapon_shop_data = save_data.get("weapon_shop", weapon_shop_data)
		promo_codes = save_data.get("promo_codes", promo_codes)
		player_level = save_data.get("level", 1)
		player_xp = save_data.get("xp", 0)
		
#endregion

#region UI
func _setup_ui():
	player_name_edit.text = player_data["name"]
	clan_tag_edit.text = "TAG"
	_update_balance_ui()
	_update_vip_status_ui()
	_update_player_limit_label(player_limit_slider.value)
	_populate_map_options()
	_populate_mode_options()
	vip_price_label.text = "VIP Статус (%d days): %d$" % [VIP_DAYS, VIP_PRICE]
	case_price_label.text = "Цена: 0$"
	#cases_opened_label.text = "Открыто кейсов: %d" % player_data["cases_opened"]

func _update_balance_ui():
	balance_label.text = " %d$" % player_data["balance"]
	purchase_button.disabled = player_data["balance"] < VIP_PRICE || player_data["is_vip"]
	case_button.disabled = player_data["balance"] < 0

func _update_vip_status_ui():
	if player_data["is_vip"]:
		vip_button.text = "VIP Активен"
		vip_button.disabled = true
		vip_status_label.text = "VIP закончится через %d дней" % player_data["vip_days"]
		vip_status_label.modulate = Color.GREEN
	else:
		vip_button.text = "Купить VIP"
		vip_button.disabled = false
		vip_status_label.text = "Обычный Игрок"
		vip_status_label.modulate = Color.WHITE

func _update_player_limit_label(value: float):
	player_limit_label.text = "Максимум Игроков: %d" % value

func _populate_map_options():
	map_option.clear()
	for map_name in MAPS.keys():
		map_option.add_item(map_name)

func _populate_mode_options():
	mode_option.clear()
	for i in range(available_modes.size()):
		mode_option.add_item(available_modes[i])
		if available_modes[i] in custom_modes:
			mode_option.set_item_icon(i, load("res://assets/icons/icon.svg"))

func _connect_signals():
	vip_button.pressed.connect(_on_vip_button_pressed)
	purchase_button.pressed.connect(_purchase_vip)
	player_name_edit.text_submitted.connect(_change_player_name)
	clan_tag_edit.text_submitted.connect(_change_clan_tag)
	player_limit_slider.value_changed.connect(_update_player_limit_label)
	case_button.pressed.connect(_open_case)

	# Menu navigation
	$MainMenu/PlayButton.pressed.connect(func(): _switch_menu("server"))
	$MainMenu/ShopButton.pressed.connect(func(): _switch_menu("shop"))
	$MainMenu/CasesButton.pressed.connect(func(): _switch_menu("cases"))
	$MainMenu/PlayerInfoButton.pressed.connect(func(): _switch_menu("player_info"))
	$MainMenu/QuitButton.pressed.connect(get_tree().quit)

	# Back buttons
	$ServerMenu/BackButton.pressed.connect(func(): _switch_menu("main"))
	$ShopMenu/BackButton.pressed.connect(func(): _switch_menu("main"))
	$CasesMenu/BackButton.pressed.connect(func(): _switch_menu("main"))
	$MainMenu/PlayerInfoMenu/BackButton.pressed.connect(func(): _switch_menu("main"))

func _switch_menu(menu_name: String):
	main_menu.visible = (menu_name == "main")
	server_menu.visible = (menu_name == "server")
	shop_menu.visible = (menu_name == "shop")
	cases_menu.visible = (menu_name == "cases")
#endregion

#region VIP
func _on_vip_button_pressed():
	if not player_data["is_vip"]:
		pass

func _purchase_vip():
	if player_data["is_vip"]:
		return
	
	if player_data["balance"] >= VIP_PRICE:
		player_data["balance"] -= VIP_PRICE
		player_data["is_vip"] = true
		player_data["vip_days"] = VIP_DAYS
		_save_player_data()
		_update_balance_ui()
		_update_vip_status_ui()
		vip_purchased.emit(player_data["player_id"])
		show_status("VIP Куплен!", Color.GREEN)
		balance_updated.emit(player_data["balance"])
#endregion

#region Игрок
func _change_player_name(new_name: String):
	new_name = new_name.strip_edges()
	if new_name.length() < 3 or new_name.length() > 16:
		show_status("Имя должно содержать 3-16 символов!", Color.RED)
		return
	
	player_data["name"] = new_name
	_save_player_data()
	player_name_changed.emit(new_name)
	show_status("Имя изменено на '%s'" % new_name, Color.GREEN)

func _change_clan_tag(new_tag: String):
	new_tag = new_tag.strip_edges().to_upper()
	if new_tag.length() > 5:
		show_status("Тег клана должен быть до 5 символов!", Color.RED)
		return
	
	player_data["clan_tag"] = new_tag
	_save_player_data()
	show_status("Тег клана изменен на '[%s]'" % new_tag, Color.GREEN)

func add_funds(amount: int):
	if amount > 0:
		player_data["balance"] += amount
		_save_player_data()
		_update_balance_ui()
		balance_updated.emit(player_data["balance"])
		show_status("+%d$! Новый баланс: %d$" % [amount, player_data["balance"]], Color.GREEN)
		
func _setup_shop_ui():
	# Очищаем списки
	for child in weapon_shop_list.get_children():
		child.queue_free()
	for child in skin_shop_list.get_children():
		child.queue_free()
	for child in character_shop_list.get_children():
		child.queue_free()
	
	# Заполняем списки магазина
	for weapon in weapon_shop_data:
		var btn = Button.new()
		btn.text = "%s (%d$)" % [weapon.capitalize(), weapon_shop_data[weapon]["price"]]
		btn.disabled = weapon_shop_data[weapon]["unlocked"]
		btn.pressed.connect(_on_weapon_purchased.bind(weapon))
		weapon_shop_list.add_child(btn)

func _update_level_ui():
	level_label.text = "%d" % player_level
	xp_bar.value = player_xp
	xp_bar.max_value = _get_xp_for_level(player_level + 1)

func _get_xp_for_level(level: int) -> int:
	return level * 1000  # Простая формула для XP

func _on_promo_code_submitted():
	var code = promo_code_edit.text.strip_edges().to_upper()
	if promo_codes.has(code) and not promo_codes[code]["used"]:
		promo_codes[code]["used"] = true
		var reward = promo_codes[code]["reward"]
		
		match reward["type"]:
			"currency":
				add_funds(reward["amount"])
				show_status("Промокод активирован! Получено %d$" % reward["amount"], Color.GREEN)
			"skin":
				show_status("Промокод активирован! Получен скин %s для %s" % [reward["skin"], reward["weapon"]], Color.GREEN)
		
		_save_player_data()
	else:
		show_status("Неверный или уже использованный промокод", Color.RED)

func _on_weapon_purchased(weapon: String):
	if player_data["balance"] >= weapon_shop_data[weapon]["price"]:
		player_data["balance"] -= weapon_shop_data[weapon]["price"]
		weapon_shop_data[weapon]["unlocked"] = true
		_save_player_data()
		_update_balance_ui()
		show_status("%s куплен!" % weapon.capitalize(), Color.GREEN)
	else:
		show_status("Недостаточно средств", Color.RED)

func _open_case():
	if player_data["balance"] < 0:
		show_status("Недостаточно средств для открытия кейса", Color.RED)
		return
	
	player_data["balance"] -= 0
	#player_data["cases_opened"] += 1
	_save_player_data()
	_update_balance_ui()
	#cases_opened_label.text = "Открыто кейсов: %d" % player_data["cases_opened"]
	
	# Анимация открытия кейса
	case_button.disabled = true
	case_reward_label.text = "Открываем кейс..."
	case_reward_label.modulate = Color.WHITE
	case_reward_icon.texture = null
	
	await get_tree().create_timer(2.0).timeout
	
	# Получаем случайный предмет
	var reward = _get_random_case_reward()
	_apply_case_reward(reward)
	
	case_button.disabled = player_data["balance"] < 500
	case_opened.emit(reward)

func _get_random_case_reward():
	var total_chance = 0.0
	for item in CASE_ITEMS:
		total_chance += item["chance"]
	
	var roll = randf_range(0.0, total_chance)
	var cumulative = 0.0
	
	for item in CASE_ITEMS:
		cumulative += item["chance"]
		if roll <= cumulative:
			return item.duplicate()
	
	return CASE_ITEMS[0].duplicate()  # Fallback

func _apply_case_reward(reward: Dictionary):
	match reward["type"]:
		"currency":
			add_funds(reward["amount"])
			case_reward_label.text = "Вы выиграли %d$!" % reward["amount"]
			case_reward_icon.texture = load("res://assets/icons/money.png")
		"skin":
			case_reward_label.text = "Вы выиграли скин %s для %s!" % [reward["skin"], reward["weapon"]]
			case_reward_icon.texture = load("res://assets/icons/skin_%s.png" % reward["skin"])
		"character":
			case_reward_label.text = "Вы выиграли персонажа %s!" % reward["character"]
			case_reward_icon.texture = load("res://assets/icons/character_%s.png" % reward["character"])
		"vip":
			player_data["vip_days"] += reward["days"]
			player_data["is_vip"] = true
			case_reward_label.text = "Вы выиграли VIP на %d дней!" % reward["days"]
			case_reward_icon.texture = load("res://assets/icons/vip.png")
			_update_vip_status_ui()
	
	_save_player_data()
	case_reward_label.modulate = Color.GOLD
#endregion

#region Сервер
func _on_create_server_pressed():
	var server_name = server_name_edit.text.strip_edges()
	if server_name == "":
		server_name = "My Server"
	
	var selected_map = map_option.get_item_text(map_option.selected)
	var selected_mode = mode_option.get_item_text(mode_option.selected)
	
	current_server_info = {
		"name": server_name,
		"ip": "127.0.0.1",  # Will be updated
		"port": DEFAULT_PORT,
		"map": selected_map,
		"mode": selected_mode,
		"max_players": int(player_limit_slider.value),
		"players": []
	}
	
	_create_network_server()

func _create_network_server():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	
	var error = multiplayer_peer.create_server(current_server_info["port"])
	
	if error == OK:
		multiplayer.multiplayer_peer = multiplayer_peer
		is_server = true
		
		# Get actual IP
		var ips = _get_local_ips()
		current_server_info["ip"] = ips[0] if ips.size() > 0 else "127.0.0.1"
		
		show_status("Сервер '%s' создан!" % current_server_info["name"], Color.GREEN)
		
		# Connect signals
		multiplayer.peer_connected.connect(_on_player_connected)
		multiplayer.peer_disconnected.connect(_on_player_disconnected)
		
		_start_game()
	else:
		show_status("Ошибка создания сервера: %d" % error, Color.RED)

func _get_local_ips() -> Array:
	var ips = []
	for ip in IP.get_local_addresses():
		if ip.count(":") == 0 and !ip.begins_with("172.") and ip != "127.0.0.1":
			ips.append(ip)
	return ips

func _on_player_connected(id: int):
	print("Игрок подключился:", id)
	current_server_info["players"].append(id)

func _on_player_disconnected(id: int):
	print("Игрок отключился:", id)
	current_server_info["players"].erase(id)
#endregion

#region Подключение к серверу
func load_servers():
	if FileAccess.file_exists(SAVED_SERVERS_PATH):
		var file = FileAccess.open(SAVED_SERVERS_PATH, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		if data is Array:
			saved_servers = data
		file.close()
	update_server_list()

func update_server_list():
	# Clear existing items
	for child in join_server_list.get_children():
		child.queue_free()
	
	# Add saved servers
	for server in saved_servers:
		if not is_valid_server(server):
			continue
			
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var btn = Button.new()
		btn.text = "%s - %s:%d" % [server.get("name", "Unnamed"), server["ip"], server["port"]]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_connect_to_server.bind(server))
		
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size.x = 40
		del_btn.pressed.connect(_remove_server.bind(server))
		
		hbox.add_child(btn)
		hbox.add_child(del_btn)
		join_server_list.add_child(hbox)

func _on_connect_button_pressed():
	var ip = ip_edit.text.strip_edges()
	var port = int(port_edit.value)
	
	if ip.is_valid_ip_address():
		var server_info = {
			"ip": ip,
			"port": port,
			"name": "Custom Server",
			"map": "Dust",
			"mode": "Deathmatch",
			"max_players": 8
		}
		_connect_to_server(server_info)
	else:
		show_status("Неверный IP адрес", Color.RED)

func _connect_to_server(server: Dictionary):
	if not is_valid_server(server):
		show_status("Неверные данные сервера", Color.RED)
		return
	
	print("Подключаемся к серверу:", server)
	
	# Create connection
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(str(server["ip"]), int(server["port"]))
	
	if error == OK:
		# Save server info exactly as received
		current_server_info = server.duplicate(true)
		
		# Add to saved servers if not exists
		var exists = false
		for s in saved_servers:
			if s["ip"] == server["ip"] and s["port"] == server["port"]:
				exists = true
				break
		
		if not exists:
			saved_servers.append(server.duplicate(true))
			save_servers()
			update_server_list()
		
		multiplayer.multiplayer_peer = peer
		is_server = false
		
		# Connect signals
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		
		show_status("Подключаемся к %s..." % server["ip"], Color.WHITE)
	else:
		show_status("Ошибка подключения: %d" % error, Color.RED)

func _on_connection_failed():
	show_status("Не удалось подключиться к серверу", Color.RED)

func _on_connected_to_server():
	_start_game()

func _remove_server(server: Dictionary):
	saved_servers.erase(server)
	save_servers()
	update_server_list()

func save_servers():
	var file = FileAccess.open(SAVED_SERVERS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved_servers))
	file.close()

func is_valid_server(server: Dictionary) -> bool:
	return server.has("ip") and server.has("port") and str(server["ip"]).is_valid_ip_address() and int(server["port"]) > 0
#endregion

#region Игра
func _start_game():
	# Load game scene
	var game_scene = load(GAME_SCENE_PATH).instantiate()
	
	# Verify map exists
	var map_path = MAPS.get(current_server_info.get("map", "Dust"), "")
	if map_path == "":
		show_status("Ошибка: карта не найдена!", Color.RED)
		return
	
	# Pass server info
	game_scene.server_info = current_server_info.duplicate(true)
	game_scene.player_data = player_data.duplicate(true)
	
	# Switch to game scene
	get_tree().root.add_child(game_scene)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = game_scene
	
	# Initialize as host or client
	if is_server:
		game_scene.init_host(player_data)
	else:
		game_scene.init_client(player_data)
#endregion

#region Утилиты
func show_status(message: String, color: Color):
	status_label.text = message
	status_label.modulate = color
	status_label.visible = true
	
	if has_node("StatusTimer"):
		$StatusTimer.queue_free()
	
	var timer = Timer.new()
	timer.name = "StatusTimer"
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(func(): status_label.visible = false)
	add_child(timer)
	timer.start()
#endregion
