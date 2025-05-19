extends Control

const GAME_SCENE_PATH = "res://game_scene.tscn"
const SAVED_SERVERS_PATH = "user://saved_servers.json"
const MAPS = {
    "Dust": "res://maps/Dust.tscn",
    "ZeroWall": "res://maps/ZeroWall.tscn"
}

# Сигналы
signal vip_purchased(player_id)
signal server_created(server_config: Dictionary)
signal server_selected(server_info: Dictionary)
signal player_name_changed(new_name)
signal balance_updated(new_balance)
signal case_opened(reward: Dictionary)
signal inventory_updated
signal avatar_changed
signal settings_applied
signal friend_added(friend_id)
signal friend_removed(friend_id)

# Константы
const VIP_PRICE = 1000
const VIP_DAYS = 30
const SAVE_PATH = "user://player_data.dat"
const DEFAULT_PORT = 9050
const SERVER_PORT = 9050
const MAX_PLAYERS = 16
const CASE_PRICES = {
    "basic": 500,
    "premium": 1000,
    "weapon": 1500
}
const DEFAULT_AVATAR = "res://assets/avatars/default.png"

# Переменные
var multiplayer_peer = ENetMultiplayerPeer.new()
var current_server_info: Dictionary = {}
var is_server: bool = false
var active_servers = []
var player_data = {
    "name": "Player",
    "balance": 10000,
    "is_vip": false,
    "vip_days": 0,
    "inventory": {
        "weapons": ["pistol", "rifle", "shotgun"],
        "skins": {
            "pistol": ["default"],
            "rifle": ["default"]
        },
        "characters": ["default"],
        "equipped": {
            "primary": "rifle",
            "secondary": "pistol",
            "melee": "knife",
            "explosive": null,
            "character": "default",
            "skins": {}
        }
    },
    "avatar": DEFAULT_AVATAR,
    "settings": {
        "sensitivity": 1.0,
        "keybinds": {},
        "graphics": "medium",
        "volume": 0.8
    },
    "friends": [],
    "player_id": ""
}

var available_maps = ["Dust", "ZeroWall"]
var available_modes = ["Deathmatch", "Team Deathmatch", "ZombieMode"]
var saved_servers = []
var weapon_data = {
    "pistol": {"type": "secondary", "scene": preload("res://weapons/pistol.tscn")},
    "rifle": {"type": "primary", "scene": preload("res://weapons/rifle.tscn")},
    "shotgun": {"type": "primary", "scene": preload("res://weapons/shotgun.tscn")},
    "knife": {"type": "melee", "scene": preload("res://weapons/knife.tscn")}
}
var skin_data = {
    "pistol": {
        "default": preload("res://skins/pistol/default.png"),
        "gold": preload("res://skins/pistol/gold.png")
    },
    "rifle": {
        "default": preload("res://skins/rifle/default.png"),
        "camo": preload("res://skins/rifle/camo.png")
    }
}
var character_data = {
    "default": preload("res://characters/default.tscn"),
    "ninja": preload("res://characters/ninja.tscn")
}

@onready var main_menu = $MainMenu
@onready var server_menu = $ServerMenu
@onready var inventory_menu = $InventoryMenu
@onready var cases_menu = $CasesMenu
@onready var settings_menu = $SettingsMenu
@onready var friends_menu = $FriendsMenu
@onready var file_dialog = $FileDialog
@onready var status_label = $StatusLabel

func _ready():
    randomize()
    _setup_directories()
    _load_player_data()
    _generate_player_id()
    _setup_ui()
    _connect_signals()
    load_servers()
    _update_anti_cheat_hash()
    _validate_game_files()

func _setup_directories():
    DirAccess.make_dir_recursive_absolute("user://screenshots")
    DirAccess.make_dir_recursive_absolute("user://config")
    DirAccess.make_dir_recursive_absolute("user://avatars")

func _load_player_data():
    if FileAccess.file_exists(SAVE_PATH):
        var file = FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.READ, _get_encryption_key())
        if file:
            var data = file.get_var()
            file.close()
            if _verify_data_integrity(data):
                player_data = data
            else:
                _handle_corrupted_data()
        else:
            push_error("Failed to open save file")
    _migrate_legacy_data()

func _save_player_data():
    _update_anti_cheat_hash()
    var file = FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, _get_encryption_key())
    if file:
        file.store_var(player_data)
        file.close()
    else:
        push_error("Failed to save player data")

func _get_encryption_key() -> String:
    return OS.get_unique_id() + "secure_salt_" + str(Engine.get_frames_drawn())

func _verify_data_integrity(data) -> bool:
    if not data or not data.has("anti_cheat_hash"):
        return false
    var saved_hash = data["anti_cheat_hash"]
    data.erase("anti_cheat_hash")
    var calculated_hash = hash(str(data))
    data["anti_cheat_hash"] = saved_hash
    return saved_hash == calculated_hash

func _update_anti_cheat_hash():
    player_data.erase("anti_cheat_hash")
    player_data["anti_cheat_hash"] = hash(str(player_data))

func _handle_corrupted_data():
    OS.alert("Обнаружены поврежденные данные. Восстановлены значения по умолчанию.", "Ошибка данных")
    player_data = get_script().get_property_default_value("player_data")

func _migrate_legacy_data():
    # Для будущих обновлений
    if not player_data.has("player_id"):
        player_data["player_id"] = ""
    if not player_data["inventory"].has("equipped"):
        player_data["inventory"]["equipped"] = {
            "primary": "rifle",
            "secondary": "pistol",
            "melee": "knife",
            "explosive": null,
            "character": "default",
            "skins": {}
        }

func _generate_player_id():
    if player_data["player_id"] == "":
        player_data["player_id"] = "PID_%s_%d" % [Time.get_datetime_string_from_system(), randi() % 10000]
        _save_player_data()

# UI Functions
func _setup_ui():
    # Main Menu
    $MainMenu/PlayButton.pressed.connect(_switch_to_server_menu)
    $MainMenu/InventoryButton.pressed.connect(_open_inventory)
    $MainMenu/CasesButton.pressed.connect(_switch_to_cases_menu)
    $MainMenu/SettingsButton.pressed.connect(_switch_to_settings_menu)
    $MainMenu/FriendsButton.pressed.connect(_switch_to_friends_menu)
    $MainMenu/QuitButton.pressed.connect(get_tree().quit)
    
    # Server Menu
    $ServerMenu/CreateServerButton.pressed.connect(_create_server)
    $ServerMenu/RefreshButton.pressed.connect(load_servers)
    $ServerMenu/BackButton.pressed.connect(_switch_to_main_menu)
    
    # Populate map and mode options
    for map in available_maps:
        $ServerMenu/MapOption.add_item(map)
    for mode in available_modes:
        $ServerMenu/ModeOption.add_item(mode)
    
    # Inventory Menu
    $InventoryMenu/BackButton.pressed.connect(_switch_to_main_menu)
    $InventoryMenu/AvatarButton.pressed.connect(_open_avatar_selector)
    
    # Cases Menu
    $CasesMenu/BasicCaseButton.pressed.connect(_open_case.bind("basic"))
    $CasesMenu/PremiumCaseButton.pressed.connect(_open_case.bind("premium"))
    $CasesMenu/WeaponCaseButton.pressed.connect(_open_case.bind("weapon"))
    $CasesMenu/BackButton.pressed.connect(_switch_to_main_menu)
    
    # Settings Menu
    $SettingsMenu/SensitivitySlider.value_changed.connect(_update_sensitivity)
    $SettingsMenu/GraphicsOption.item_selected.connect(_update_graphics)
    $SettingsMenu/VolumeSlider.value_changed.connect(_update_volume)
    $SettingsMenu/BackButton.pressed.connect(_switch_to_main_menu)
    
    # Populate graphics options
    $SettingsMenu/GraphicsOption.add_item("Low")
    $SettingsMenu/GraphicsOption.add_item("Medium")
    $SettingsMenu/GraphicsOption.add_item("High")
    $SettingsMenu/GraphicsOption.selected = 1  # Default to medium
    
    # Friends Menu
    $FriendsMenu/AddFriendButton.pressed.connect(_add_friend)
    $FriendsMenu/BackButton.pressed.connect(_switch_to_main_menu)
    
    # File Dialog
    file_dialog.file_selected.connect(_on_avatar_selected)
    file_dialog.filters = ["*.png ; PNG Images"]
    
    # Status Label
    $StatusLabel/Timer.timeout.connect(_on_status_timer_timeout)
    
    _update_ui()

func _update_ui():
    # Main Menu
    $MainMenu/PlayerNameLabel.text = player_data["name"]
    $MainMenu/BalanceLabel.text = "$%d" % player_data["balance"]
    if ResourceLoader.exists(player_data["avatar"]):
        $MainMenu/AvatarTexture.texture = load(player_data["avatar"])
    else:
        $MainMenu/AvatarTexture.texture = load(DEFAULT_AVATAR)
    
    # Cases Menu
    $CasesMenu/BasicCasePrice.text = "$%d" % CASE_PRICES["basic"]
    $CasesMenu/PremiumCasePrice.text = "$%d" % CASE_PRICES["premium"]
    $CasesMenu/WeaponCasePrice.text = "$%d" % CASE_PRICES["weapon"]
    
    # Settings
    $SettingsMenu/SensitivitySlider.value = player_data["settings"]["sensitivity"]
    $SettingsMenu/VolumeSlider.value = player_data["settings"]["volume"]
    
    match player_data["settings"]["graphics"]:
        "low":
            $SettingsMenu/GraphicsOption.selected = 0
        "medium":
            $SettingsMenu/GraphicsOption.selected = 1
        "high":
            $SettingsMenu/GraphicsOption.selected = 2
    
    _update_vip_status()

func _update_vip_status():
    if player_data["is_vip"]:
        $MainMenu/VIPStatus.text = "VIP (%d дней осталось)" % player_data["vip_days"]
        $MainMenu/VIPStatus.add_theme_color_override("font_color", Color.GOLD)
    else:
        $MainMenu/VIPStatus.text = "Обычный игрок"
        $MainMenu/VIPStatus.add_theme_color_override("font_color", Color.WHITE)

# Menu Navigation
func _switch_to_main_menu():
    main_menu.visible = true
    server_menu.visible = false
    inventory_menu.visible = false
    cases_menu.visible = false
    settings_menu.visible = false
    friends_menu.visible = false

func _switch_to_server_menu():
    main_menu.visible = false
    server_menu.visible = true
    _refresh_server_list()

func _open_inventory():
    main_menu.visible = false
    inventory_menu.visible = true
    _populate_inventory()

func _switch_to_cases_menu():
    main_menu.visible = false
    cases_menu.visible = true

func _switch_to_settings_menu():
    main_menu.visible = false
    settings_menu.visible = true

func _switch_to_friends_menu():
    main_menu.visible = false
    friends_menu.visible = true
    _update_friends_list()

# Inventory System
func _populate_inventory():
    _clear_inventory_ui()
    
    # Weapons
    for weapon in player_data["inventory"]["weapons"]:
        var btn = Button.new()
        btn.text = weapon.capitalize()
        btn.pressed.connect(_equip_weapon.bind(weapon))
        $InventoryMenu/WeaponsList.add_child(btn)
    
    # Skins
    for weapon in player_data["inventory"]["skins"]:
        for skin in player_data["inventory"]["skins"][weapon]:
            var texture_btn = TextureButton.new()
            if skin_data.has(weapon) and skin_data[weapon].has(skin):
                texture_btn.texture_normal = skin_data[weapon][skin]
                texture_btn.pressed.connect(_equip_skin.bind(weapon, skin))
                $InventoryMenu/SkinsGrid.add_child(texture_btn)
    
    # Characters
    for character in player_data["inventory"]["characters"]:
        var btn = Button.new()
        btn.text = character.capitalize()
        btn.pressed.connect(_equip_character.bind(character))
        $InventoryMenu/CharactersList.add_child(btn)
    
    # Current Equipment
    $InventoryMenu/EquippedPrimary.text = "Primary: %s" % player_data["inventory"]["equipped"]["primary"]
    $InventoryMenu/EquippedSecondary.text = "Secondary: %s" % player_data["inventory"]["equipped"]["secondary"]
    $InventoryMenu/EquippedCharacter.text = "Character: %s" % player_data["inventory"]["equipped"]["character"]

func _clear_inventory_ui():
    for child in $InventoryMenu/WeaponsList.get_children():
        child.queue_free()
    for child in $InventoryMenu/SkinsGrid.get_children():
        child.queue_free()
    for child in $InventoryMenu/CharactersList.get_children():
        child.queue_free()

func _equip_weapon(weapon_name: String):
    if not weapon_data.has(weapon_name):
        show_status("Unknown weapon: %s" % weapon_name, Color.RED)
        return
    
    var weapon_type = weapon_data[weapon_name]["type"]
    player_data["inventory"]["equipped"][weapon_type] = weapon_name
    _save_player_data()
    show_status("Экипировано: %s" % weapon_name, Color.GREEN)
    inventory_updated.emit()

func _equip_skin(weapon: String, skin: String):
    if not player_data["inventory"]["skins"].has(weapon) or not skin in player_data["inventory"]["skins"][weapon]:
        show_status("Skin not owned", Color.RED)
        return
    
    if not player_data["inventory"]["equipped"].has("skins"):
        player_data["inventory"]["equipped"]["skins"] = {}
    
    player_data["inventory"]["equipped"]["skins"][weapon] = skin
    _save_player_data()
    show_status("Скин применен: %s (%s)" % [weapon, skin], Color.GREEN)
    inventory_updated.emit()

func _equip_character(character: String):
    if not character in player_data["inventory"]["characters"]:
        show_status("Character not owned", Color.RED)
        return
    
    player_data["inventory"]["equipped"]["character"] = character
    _save_player_data()
    show_status("Персонаж выбран: %s" % character, Color.GREEN)
    inventory_updated.emit()

# Avatar System
func _open_avatar_selector():
    file_dialog.popup_centered()

func _on_avatar_selected(path: String):
    if FileAccess.file_exists(path):
        var img = Image.load_from_file(path)
        if img:
            var texture = ImageTexture.create_from_image(img)
            var save_path = "user://avatars/%s.png" % player_data["player_id"]
            if img.save_png(save_path) == OK:
                player_data["avatar"] = save_path
                _save_player_data()
                $MainMenu/AvatarTexture.texture = texture
                $InventoryMenu/AvatarTexture.texture = texture
                avatar_changed.emit()
                show_status("Аватар обновлен!", Color.GREEN)
            else:
                show_status("Не удалось сохранить аватар", Color.RED)
        else:
            show_status("Не удалось загрузить изображение", Color.RED)
    else:
        show_status("Файл не найден", Color.RED)

# Case System
func _open_case(case_type: String):
    if not CASE_PRICES.has(case_type):
        show_status("Unknown case type", Color.RED)
        return
    
    if player_data["balance"] < CASE_PRICES[case_type]:
        show_status("Недостаточно средств!", Color.RED)
        return
    
    player_data["balance"] -= CASE_PRICES[case_type]
    var reward = _get_case_reward(case_type)
    _process_reward(reward)
    
    _save_player_data()
    _update_ui()
    case_opened.emit(reward)
    show_status("Получено: %s" % _format_reward(reward), Color.GOLD)

func _get_case_reward(case_type: String) -> Dictionary:
    var rewards = []
    var weights = []
    
    match case_type:
        "basic":
            rewards = [
                {"type": "currency", "amount": 200, "weight": 40},
                {"type": "skin", "weapon": "pistol", "skin": "gold", "weight": 10},
                {"type": "currency", "amount": 100, "weight": 50}
            ]
        "premium":
            rewards = [
                {"type": "character", "name": "ninja", "weight": 20},
                {"type": "vip", "days": 7, "weight": 5},
                {"type": "skin", "weapon": "rifle", "skin": "camo", "weight": 15},
                {"type": "currency", "amount": 500, "weight": 60}
            ]
        "weapon":
            rewards = [
                {"type": "weapon", "name": "shotgun", "weight": 15},
                {"type": "currency", "amount": 500, "weight": 30},
                {"type": "skin", "weapon": "pistol", "skin": "gold", "weight": 10},
                {"type": "vip", "days": 1, "weight": 5},
                {"type": "currency", "amount": 1000, "weight": 40}
            ]
    
    var total_weight = rewards.reduce(func(acc, r): return acc + r.get("weight", 0), 0)
    var roll = randi() % total_weight
    var cumulative = 0
    
    for reward in rewards:
        cumulative += reward.get("weight", 0)
        if roll < cumulative:
            return reward.duplicate()
    
    return rewards[0].duplicate()

func _process_reward(reward: Dictionary):
    match reward["type"]:
        "currency":
            player_data["balance"] += reward["amount"]
            balance_updated.emit(player_data["balance"])
        "skin":
            if not player_data["inventory"]["skins"].has(reward["weapon"]):
                player_data["inventory"]["skins"][reward["weapon"]] = []
            if not reward["skin"] in player_data["inventory"]["skins"][reward["weapon"]]:
                player_data["inventory"]["skins"][reward["weapon"]].append(reward["skin"])
                inventory_updated.emit()
        "character":
            if not reward["name"] in player_data["inventory"]["characters"]:
                player_data["inventory"]["characters"].append(reward["name"])
                inventory_updated.emit()
        "vip":
            player_data["is_vip"] = true
            player_data["vip_days"] += reward["days"]
            vip_purchased.emit(player_data["player_id"])
        "weapon":
            if not reward["name"] in player_data["inventory"]["weapons"]:
                player_data["inventory"]["weapons"].append(reward["name"])
                inventory_updated.emit()

func _format_reward(reward: Dictionary) -> String:
    match reward["type"]:
        "currency":
            return "$%d" % reward["amount"]
        "skin":
            return "%s skin for %s" % [reward["skin"], reward["weapon"]]
        "character":
            return "Character: %s" % reward["name"]
        "vip":
            return "VIP for %d days" % reward["days"]
        "weapon":
            return "Weapon: %s" % reward["name"]
        _:
            return "Unknown reward"

# Settings System
func _update_sensitivity(value: float):
    player_data["settings"]["sensitivity"] = value
    _save_player_data()
    settings_applied.emit()

func _update_graphics(index: int):
    var qualities = ["low", "medium", "high"]
    if index < qualities.size():
        player_data["settings"]["graphics"] = qualities[index]
        _save_player_data()
        _apply_graphics_settings()
        settings_applied.emit()

func _update_volume(value: float):
    player_data["settings"]["volume"] = value
    _save_player_data()
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
    settings_applied.emit()

func _apply_graphics_settings():
    match player_data["settings"]["graphics"]:
        "low":
            ProjectSettings.set_setting("rendering/quality/intended_usage/framebuffer_allocation", 0)
            get_tree().root.set_msaa(Window.MSAA_DISABLED)
        "medium":
            ProjectSettings.set_setting("rendering/quality/intended_usage/framebuffer_allocation", 1)
            get_tree().root.set_msaa(Window.MSAA_4X)
        "high":
            ProjectSettings.set_setting("rendering/quality/intended_usage/framebuffer_allocation", 2)
            get_tree().root.set_msaa(Window.MSAA_8X)

# Friends System
func _update_friends_list():
    for child in $FriendsMenu/FriendsList.get_children():
        child.queue_free()
    
    for friend_id in player_data["friends"]:
        var hbox = HBoxContainer.new()
        var label = Label.new()
        label.text = friend_id
        var join_btn = Button.new()
        join_btn.text = "Join"
        join_btn.pressed.connect(_join_friend_server.bind(friend_id))
        var remove_btn = Button.new()
        remove_btn.text = "Remove"
        remove_btn.pressed.connect(_remove_friend.bind(friend_id))
        
        hbox.add_child(label)
        hbox.add_child(join_btn)
        hbox.add_child(remove_btn)
        $FriendsMenu/FriendsList.add_child(hbox)

func _add_friend():
    var friend_id = $FriendsMenu/FriendIDEdit.text.strip_edges()
    if friend_id == "":
        show_status("Введите ID друга", Color.RED)
        return
    
    if friend_id == player_data["player_id"]:
        show_status("Нельзя добавить себя", Color.RED)
        return
    
    if friend_id in player_data["friends"]:
        show_status("Этот друг уже добавлен", Color.YELLOW)
        return
    
    player_data["friends"].append(friend_id)
    _save_player_data()
    _update_friends_list()
    friend_added.emit(friend_id)
    show_status("Друг добавлен: %s" % friend_id, Color.GREEN)
    $FriendsMenu/FriendIDEdit.text = ""

func _remove_friend(friend_id: String):
    player_data["friends"].erase(friend_id)
    _save_player_data()
    _update_friends_list()
    friend_removed.emit(friend_id)
    show_status("Друг удален: %s" % friend_id, Color.GREEN)

func _join_friend_server(friend_id: String):
    show_status("Запрашиваем информацию о сервере друга...", Color.WHITE)
    
    # Эмуляция ответа сервера
    await get_tree().create_timer(1.0).timeout
    
    var server_info = {
        "ip": "127.0.0.1",  # В реальной игре это будет IP друга
        "port": DEFAULT_PORT,
        "name": "%s's Server" % friend_id,
        "map": "Dust",
        "mode": "Deathmatch",
        "players": 1,
        "max_players": MAX_PLAYERS
    }
    
    _connect_to_server(server_info)

# Server System
func load_servers():
    if FileAccess.file_exists(SAVED_SERVERS_PATH):
        var file = FileAccess.open(SAVED_SERVERS_PATH, FileAccess.READ)
        var data = JSON.parse_string(file.get_as_text())
        if typeof(data) == TYPE_ARRAY:
            saved_servers = data
        file.close()
    _refresh_server_list()

func _refresh_server_list():
    for child in $ServerMenu/ServerList.get_children():
        child.queue_free()
    
    for server in saved_servers:
        var btn = Button.new()
        btn.text = "%s - %s:%d (%d/%d)" % [
            server.get("name", "Unnamed"),
            server.get("ip", "127.0.0.1"),
            server.get("port", DEFAULT_PORT),
            server.get("players", 0),
            server.get("max_players", MAX_PLAYERS)
        ]
        btn.pressed.connect(_connect_to_server.bind(server))
        $ServerMenu/ServerList.add_child(btn)

func _create_server():
    var server_name = $ServerMenu/ServerNameEdit.text.strip_edges()
    if server_name == "":
        server_name = "%s's Server" % player_data["name"]
    
    var selected_map = available_maps[$ServerMenu/MapOption.selected]
    var selected_mode = available_modes[$ServerMenu/ModeOption.selected]
    
    var server_config = {
        "name": server_name,
        "ip": _get_local_ip(),
        "port": DEFAULT_PORT,
        "map": selected_map,
        "mode": selected_mode,
        "max_players": $ServerMenu/MaxPlayersSlider.value,
        "password": $ServerMenu/PasswordEdit.text,
        "rules": {
            "friendly_fire": $ServerMenu/FriendlyFireCheck.button_pressed,
            "weapon_restrictions": []
        },
        "players": 1
    }
    
    current_server_info = server_config
    is_server = true
    
    # Сохраняем сервер в список
    if not server_config in saved_servers:
        saved_servers.append(server_config)
        var file = FileAccess.open(SAVED_SERVERS_PATH, FileAccess.WRITE)
        file.store_string(JSON.stringify(saved_servers))
        file.close()
    
    _start_server()

func _get_local_ip() -> String:
    for ip in IP.get_local_addresses():
        if ip.count(".") == 3 and not ip.begins_with("127."):
            return ip
    return "127.0.0.1"

func _start_server():
    var peer = ENetMultiplayerPeer.new()
    var err = peer.create_server(current_server_info["port"], current_server_info["max_players"])
    if err == OK:
        multiplayer.multiplayer_peer = peer
        multiplayer.peer_connected.connect(_on_player_connected)
        multiplayer.peer_disconnected.connect(_on_player_disconnected)
        
        show_status("Сервер запущен: %s" % current_server_info["name"], Color.GREEN)
        _start_game()
    else:
        show_status("Ошибка создания сервера: %d" % err, Color.RED)

func _on_player_connected(id: int):
    print("Player connected: ", id)
    # Здесь должна быть логика проверки и синхронизации игроков

func _on_player_disconnected(id: int):
    print("Player disconnected: ", id)
    # Очистка данных игрока

func _connect_to_server(server_info: Dictionary):
    current_server_info = server_info
    is_server = false
    
    var peer = ENetMultiplayerPeer.new()
    var err = peer.create_client(server_info["ip"], server_info["port"])
    if err == OK:
        multiplayer.multiplayer_peer = peer
        multiplayer.connection_failed.connect(_on_connection_failed)
        multiplayer.connected_to_server.connect(_on_connected_to_server)
        
        show_status("Подключение к %s..." % server_info["ip"], Color.WHITE)
    else:
        show_status("Ошибка подключения: %d" % err, Color.RED)

func _on_connection_failed():
    show_status("Не удалось подключиться к серверу", Color.RED)
    multiplayer.multiplayer_peer = null

func _on_connected_to_server():
    show_status("Успешное подключение!", Color.GREEN)
    _start_game()

func _start_game():
    var game_scene = load(GAME_SCENE_PATH).instantiate()
    if game_scene:
        game_scene.server_info = current_server_info
        game_scene.player_data = player_data
        game_scene.is_server = is_server
        
        get_tree().root.add_child(game_scene)
        get_tree().current_scene.queue_free()
        get_tree().current_scene = game_scene
    else:
        show_status("Failed to load game scene", Color.RED)

# Utility Functions
func show_status(message: String, color: Color = Color.WHITE):
    status_label.text = message
    status_label.modulate = color
    status_label.visible = true
    $StatusLabel/Timer.start(3.0)

func _on_status_timer_timeout():
    status_label.visible = false

func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _save_player_data()
        get_tree().quit()

# Anti-Cheat Protection
func _validate_game_files():
    var required_files = [
        "res://weapons/pistol.tscn",
        "res://weapons/rifle.tscn",
        "res://characters/default.tscn"
    ]
    
    for file in required_files:
        if not FileAccess.file_exists(file):
            OS.alert("Обнаружены модифицированные файлы игры", "Ошибка целостности")
            get_tree().quit()

func _verify_player_data():
    if not _verify_data_integrity(player_data):
        OS.alert("Обнаружены модифицированные данные игрока", "Ошибка данных")
        _handle_corrupted_data()

func _check_for_cheats():
    # Проверка на невозможные значения
    if player_data["balance"] > 1000000:
        player_data["balance"] = 10000
        _save_player_data()
    
    # Проверка на неразблокированное оружие
    for weapon in player_data["inventory"]["weapons"]:
        if not weapon_data.has(weapon):
            player_data["inventory"]["weapons"] = ["pistol", "rifle"]
            _save_player_data()
            break

# VIP System
func purchase_vip():
    if player_data["is_vip"]:
        show_status("Вы уже имеете VIP статус", Color.YELLOW)
        return
    
    if player_data["balance"] < VIP_PRICE:
        show_status("Недостаточно средств для покупки VIP", Color.RED)
        return
    
    player_data["balance"] -= VIP_PRICE
    player_data["is_vip"] = true
    player_data["vip_days"] += VIP_DAYS
    _save_player_data()
    _update_ui()
    vip_purchased.emit(player_data["player_id"])
    show_status("VIP статус активирован на %d дней!" % VIP_DAYS, Color.GOLD)

func update_vip_days():
    if player_data["is_vip"]:
        player_data["vip_days"] -= 1
        if player_data["vip_days"] <= 0:
            player_data["is_vip"] = false
            player_data["vip_days"] = 0
            show_status("Ваш VIP статус истек", Color.YELLOW)
        _save_player_data()
        _update_ui()
