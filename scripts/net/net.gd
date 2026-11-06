extends Node

## Транспорт и список игроков. Ничего не знает про ресурсы и инвентари:
## это дело Game. Задача Net: поднять сервер, подключить клиента, держать
## состав игроков и гонять позиции.

signal roster_changed(players: Dictionary)
signal status_changed(text: String)
signal connection_ready()
signal connection_lost(reason: String)
signal player_transform(peer_id: int, position: Vector3, yaw: float)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 7
const HOST_ID := 1

var is_host := false
var is_client := false
var my_id := 1
var players: Dictionary = {}

var _nick := "Игрок"
var _pending_nick := ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int, nick: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		status_changed.emit("Не удалось занять порт %d: %s" % [port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_client = false
	my_id = HOST_ID
	_nick = nick
	players = {HOST_ID: {"nick": nick}}
	status_changed.emit("Сервер на порту %d" % port)
	_broadcast_roster()
	connection_ready.emit()
	return true

func join(address: String, port: int, nick: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Не удалось начать подключение к %s:%d: %s" % [address, port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_client = true
	_pending_nick = nick
	if _pending_nick.strip_edges().is_empty():
		_pending_nick = "Игрок"
	status_changed.emit("Подключение к %s:%d" % [address, port])
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	is_client = false
	players = {}
	my_id = HOST_ID

func is_offline() -> bool:
	return multiplayer.multiplayer_peer == null

func nick_of(peer_id: int) -> String:
	return String(players.get(peer_id, {}).get("nick", "Игрок"))

func player_count() -> int:
	return players.size()

## Клиент сообщает свою позицию всем. Авторитет по позиции у клиента,
## сервер дополнительно проверяет дистанцию при добыче.
func send_transform(position: Vector3, yaw: float) -> void:
	player_transform.emit(my_id, position, yaw)
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.get_peers().is_empty():
		return
	_rpc_transform.rpc(my_id, position, yaw)

func _broadcast_roster() -> void:
	if not is_host:
		return
	_sync_roster.rpc(players)

@rpc("authority", "call_local", "reliable")
func _sync_roster(new_players: Dictionary) -> void:
	players = new_players.duplicate(true)
	roster_changed.emit(players)

@rpc("any_peer", "call_remote", "reliable")
func _register(nick: String) -> void:
	if not is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var clean := nick.strip_edges()
	if clean.length() > 16:
		clean = clean.substr(0, 16)
	if clean.is_empty():
		clean = "Игрок"
	players[peer_id] = {"nick": clean}
	print("[NET] player_joined id=%d nick=%s" % [peer_id, clean])
	status_changed.emit("Игрок %s подключился" % clean)
	_broadcast_roster()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_transform(peer_id: int, position: Vector3, yaw: float) -> void:
	# чужой игрок не может присылать позицию за другого
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	player_transform.emit(peer_id, position, yaw)

func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	status_changed.emit("Подключено, ждём список игроков")
	_register.rpc_id(1, _pending_nick)
	connection_ready.emit()

func _on_connection_failed() -> void:
	is_client = false
	status_changed.emit("Сервер не отвечает")
	connection_lost.emit("Сервер не отвечает")

func _on_server_disconnected() -> void:
	is_client = false
	status_changed.emit("Связь с сервером потеряна")
	connection_lost.emit("Связь с сервером потеряна")

func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		status_changed.emit("Подключается игрок #%d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	players.erase(peer_id)
	status_changed.emit("Игрок #%d отключился" % peer_id)
	_broadcast_roster()
