extends Node

# Константы
const MAPS = {
	"Dust": "res://maps/Dust.tscn",
	"ZeroWall": "res://maps/ZeroWall.tscn"
}

const TEAMS = {
	RED = {"name": "Red", "color": Color.RED, "spawn_points": []},
	BLUE = {"name": "Blue", "color": Color.BLUE, "spawn_points": []},
	SPECTATOR = {"name": "Spectator", "color": Color.WHITE}
}

# Сигналы
signal player_spawned(player)
signal game_initialized
signal team_selected(team)
signal chat_message_received(message)

# Сетевые переменные
var server_info: Dictionary
var player_data: Dictionary
var players = {}
var local_player_id: int = 0
var player_teams = {}  # {player_id: team_name}
var chat_history = []

# UI элементы
@onready var team_select_ui = preload("res://team_select.tscn").instantiate()
@onready var chat_ui = preload("res://chat.tscn").instantiate()

func _ready():
	# Инициализация сети
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.peer_connected.connect(_on_player_connected)
		multiplayer.multiplayer_peer.peer_disconnected.connect(_on_player_disconnected)
		
		if multiplayer.is_server():
			load_map(server_info["map"])
			_find_spawn_points()
		
		# Инициализация UI
		add_child(team_select_ui)
		team_select_ui.visible = false
		team_select_ui.team_selected.connect(_on_team_selected)
		
		add_child(chat_ui)
		chat_ui.send_message.connect(_on_chat_message_sent)

func _exit_tree():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.peer_connected.disconnect(_on_player_connected)
		multiplayer.multiplayer_peer.peer_disconnected.disconnect(_on_player_disconnected)

#region Map Loading
func load_map(map_name: String):
	var map_path = MAPS.get(map_name, "")
	if map_path == "" or not ResourceLoader.exists(map_path):
		push_error("Map not found: " + map_name)
		return
	
	# Удаление старой карты
	for child in get_children():
		if child.is_in_group("map"):
			child.queue_free()
	
	var map = load(map_path).instantiate()
	map.add_to_group("map")
	add_child(map)
	
	if multiplayer.is_server():
		rpc("sync_map", map_name)

@rpc("call_local", "reliable")
func sync_map(map_name: String):
	if not multiplayer.is_server():
		load_map(map_name)

func _find_spawn_points():
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node.team == "Red":
			TEAMS.RED["spawn_points"].append(node.global_position)
		elif node.team == "Blue":
			TEAMS.BLUE["spawn_points"].append(node.global_position)
#endregion

#region Player Management
func init_host(player_data: Dictionary):
	local_player_id = multiplayer.get_unique_id()
	show_team_select()
	game_initialized.emit()

func init_client(player_data: Dictionary):
	local_player_id = multiplayer.get_unique_id()
	show_team_select()
	rpc_id(1, "request_spawn", local_player_id, player_data)

@rpc("any_peer", "reliable")
func request_spawn(player_id: int, player_data: Dictionary):
	if multiplayer.is_server():
		var team = get_available_team()
		player_teams[player_id] = team
		rpc_id(player_id, "approve_spawn", team)
		rpc("spawn_player", player_id, player_data, team)

@rpc("call_local", "reliable")
func spawn_player(player_id: int, player_data: Dictionary, team: String):
	if players.has(player_id):
		return
	
	var player_scene = load("res://player_character.tscn").instantiate()
	player_scene.name = str(player_id)
	player_scene.player_name = player_data["name"]
	player_scene.team = team
	
	if player_id == multiplayer.get_unique_id():
		player_scene.set_multiplayer_authority(player_id)
		setup_player_controls(player_scene)
	
	# Выбор позиции спавна
	var spawn_points = TEAMS.get(team.to_upper(), TEAMS.SPECTATOR)["spawn_points"]
	if spawn_points.size() > 0:
		player_scene.global_position = spawn_points[randi() % spawn_points.size()]
	
	add_child(player_scene)
	players[player_id] = player_scene
	player_spawned.emit(player_scene)

func get_available_team():
	var red_count = player_teams.values().count("Red")
	var blue_count = player_teams.values().count("Blue")
	return "Red" if red_count <= blue_count else "Blue"

func _on_player_connected(id: int):
	print("Player connected: ", id)

func _on_player_disconnected(id: int):
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	player_teams.erase(id)
#endregion

#region Team Selection
func show_team_select():
	team_select_ui.visible = true
	team_select_ui.set_teams(TEAMS)

func _on_team_selected(team: String):
	team_select_ui.visible = false
	if multiplayer.is_server():
		player_teams[local_player_id] = team
		spawn_player(local_player_id, {"name": "Player"}, team)
	else:
		rpc_id(1, "request_team_change", local_player_id, team)

@rpc("any_peer", "reliable")
func request_team_change(player_id: int, team: String):
	if multiplayer.is_server():
		player_teams[player_id] = team
		rpc("update_player_team", player_id, team)

@rpc("call_local", "reliable")
func update_player_team(player_id: int, team: String):
	if players.has(player_id):
		players[player_id].team = team
		# Телепортация к новым спавн-поинтам
		var spawn_points = TEAMS.get(team.to_upper(), TEAMS.SPECTATOR)["spawn_points"]
		if spawn_points.size() > 0:
			players[player_id].global_position = spawn_points[randi() % spawn_points.size()]
#endregion

#region Chat System
func _on_chat_message_sent(message: String, is_team_chat: bool):
	var player_id = multiplayer.get_unique_id()
	var team = player_teams.get(player_id, "Spectator")
	rpc_id(1, "receive_chat_message", player_id, message, is_team_chat, team)

@rpc("any_peer", "reliable")
func receive_chat_message(sender_id: int, message: String, is_team_chat: bool, team: String):
	var sender_name = players[sender_id].player_name if players.has(sender_id) else "Unknown"
	var formatted_message = format_message(sender_name, message, is_team_chat, team)
	
	if multiplayer.is_server():
		# Рассылка сообщения
		if is_team_chat:
			for player_id in player_teams:
				if player_teams[player_id] == team:
					rpc_id(player_id, "add_chat_message", formatted_message)
		else:
			rpc("add_chat_message", formatted_message)
	else:
		chat_ui.add_message(formatted_message)

@rpc("call_local", "reliable")
func add_chat_message(message: String):
	chat_history.append(message)
	chat_ui.update_chat(message)

func format_message(sender: String, message: String, is_team: bool, team: String) -> String:
	var color = TEAMS[team.to_upper()]["color"].to_html() if team != "Spectator" else "#FFFFFF"
	var prefix = "[TEAM] " if is_team else "[ALL] "
	return "[color={color}]{prefix}{sender}:[/color] {message}".format({
		"color": color,
		"prefix": prefix,
		"sender": sender,
		"message": message
	})
#endregion

#region Game Modes
func setup_deathmatch():
	if multiplayer.is_server():
		rpc("sync_game_mode", "deathmatch")

func setup_team_deathmatch():
	if multiplayer.is_server():
		rpc("sync_game_mode", "team_deathmatch")

@rpc("call_local", "reliable")
func sync_game_mode(mode: String):
	match mode:
		"deathmatch":
			print("Setting up Deathmatch")
		"team_deathmatch":
			print("Setting up Team Deathmatch")
#endregion

func setup_player_controls(player):
	# Настройка управления
	pass
