extends Node

## Авторитетное состояние мира: источники ресурсов, инвентари, что в руках.
## Сервер считает и рассылает, клиенты только показывают и просят.
## Все изменения идут через сеть, локальных правок состояния на клиенте нет.

signal resources_changed()
signal inventory_changed(peer_id: int)
signal equipped_changed(peer_id: int)
signal vehicles_changed()
signal state_reset()
signal notice(text: String)

## Насколько далеко от источника может стоять игрок по мнению сервера.
## Больше, чем дистанция взаимодействия у игрока, чтобы мелкое расхождение
## позиций не рождало ложных отказов.
const MAX_HARVEST_DISTANCE := 5.5

## Дистанция, с которой сервер разрешает сесть за руль. Чуть больше, чем у
## добычи: машина большая, к ней подходят вплотную.
const MAX_VEHICLE_DISTANCE := 6.5

var resources: Dictionary = {}
## Машины: id -> {driver, position, rotation}. Водителя назначает только сервер.
var vehicles: Dictionary = {}
var inventories: Dictionary = {}
var equipped: Dictionary = {}
var positions: Dictionary = {}

var world_ready := false
## Флаг интерфейса: открыта сумка. Нужен игроку, чтобы не забирать мышь,
## когда кликают по панели.
var ui_inventory_open := false

func _ready() -> void:
	Net.roster_changed.connect(_on_roster_changed)
	Net.player_transform.connect(_on_player_transform)
	set_process(true)

func is_server() -> bool:
	return Net.is_host

static func now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func get_inventory(peer_id: int) -> Inventory:
	return inventories.get(peer_id, null)

func get_equipped(peer_id: int) -> String:
	return String(equipped.get(peer_id, ""))

func my_inventory() -> Inventory:
	return get_inventory(Net.my_id)

# --- мир -------------------------------------------------------------------

## Заполняет состояние источников и машин по списку из генератора мира.
func setup_world(resource_list: Array, vehicle_list: Array = []) -> void:
	vehicles.clear()
	for entry in vehicle_list:
		vehicles[int(entry.get("id", -1))] = {
			"driver": 0,
			"position": entry.get("position", Vector3.ZERO),
			"rotation": float(entry.get("rot_y", 0.0)),
			"speed": 0.0,
			"speed_time": 0.0,
		}
	resources.clear()
	for entry in resource_list:
		var resource_type := String(entry.get("type", ""))
		var state := Rules.new_state(resource_type)
		if state.is_empty():
			continue
		state["position"] = entry.get("position", Vector3.ZERO)
		resources[int(entry.get("id", -1))] = state
	world_ready = true
	resources_changed.emit()
	vehicles_changed.emit()

## Возрождение истощённых источников. Крутится только на сервере.
func _process(_delta: float) -> void:
	if not is_server() or not world_ready:
		return
	var now := now_seconds()
	for resource_id in resources.keys():
		var state: Dictionary = resources[resource_id]
		if bool(state.get("alive", true)):
			continue
		var respawn_at := float(state.get("respawn_at", 0.0))
		if respawn_at <= 0.0 or now < respawn_at:
			continue
		var fresh := Rules.new_state(String(state.get("type", "")))
		if fresh.is_empty():
			continue
		fresh["position"] = state.get("position", Vector3.ZERO)
		_sync_resource.rpc(int(resource_id), fresh)

# --- состав игроков --------------------------------------------------------

func _on_roster_changed(players: Dictionary) -> void:
	if not is_server():
		return
	for key in players:
		var peer_id := int(key)
		if inventories.has(peer_id):
			continue
		var inv := Inventory.new(ItemDB.START_INVENTORY)
		inventories[peer_id] = inv
		equipped[peer_id] = _default_tool(inv)
		_sync_inventory.rpc(peer_id, inv.to_dict())
		_sync_equipped.rpc(peer_id, get_equipped(peer_id))
	for key in inventories.keys():
		if players.has(int(key)):
			continue
		inventories.erase(key)
		equipped.erase(key)
		positions.erase(key)
	# Ушедший игрок не должен держать машину занятой.
	for key in vehicles:
		var state: Dictionary = vehicles[key]
		var driver := int(state.get("driver", 0))
		if driver == 0 or players.has(driver):
			continue
		state["driver"] = 0
		vehicles[key] = state
		_sync_vehicle.rpc(int(key), 0, state.get("position", Vector3.ZERO), float(state.get("rotation", 0.0)))

func _default_tool(inv: Inventory) -> String:
	for item_id in ItemDB.HOTBAR:
		if inv.has(item_id):
			return item_id
	return ""

func _on_player_transform(peer_id: int, position: Vector3, _yaw: float) -> void:
	positions[peer_id] = position

func note_position(peer_id: int, position: Vector3) -> void:
	positions[peer_id] = position

# --- полное состояние для нового клиента -----------------------------------

## Клиент просит состояние после того, как построил мир. Если соединение ещё
## не установлено, ждём сигнала от Net и просим тогда.
func request_state() -> void:
	if is_server():
		return
	if not is_connected_to_server():
		Net.connection_ready.connect(_request_state_when_ready, CONNECT_ONE_SHOT)
		return
	_request_state.rpc_id(1)

func is_connected_to_server() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _request_state_when_ready() -> void:
	if not is_server() and world_ready:
		_request_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_receive_state.rpc_id(
		peer_id,
		resources.duplicate(true),
		_inventories_payload(),
		equipped.duplicate(),
		vehicles.duplicate(true)
	)

func _inventories_payload() -> Dictionary:
	var payload := {}
	for peer_id in inventories:
		payload[int(peer_id)] = (inventories[peer_id] as Inventory).to_dict()
	return payload

@rpc("authority", "call_remote", "reliable")
func _receive_state(
	resource_states: Dictionary,
	inv_payload: Dictionary,
	equipped_payload: Dictionary,
	vehicle_states: Dictionary
) -> void:
	resources.clear()
	for key in resource_states:
		resources[int(key)] = resource_states[key]
	inventories.clear()
	for key in inv_payload:
		inventories[int(key)] = Inventory.from_dict(inv_payload[key])
	equipped.clear()
	for key in equipped_payload:
		equipped[int(key)] = String(equipped_payload[key])
	vehicles.clear()
	for key in vehicle_states:
		vehicles[int(key)] = vehicle_states[key]
	state_reset.emit()
	vehicles_changed.emit()
	resources_changed.emit()

# --- добыча ----------------------------------------------------------------

func request_harvest(resource_id: int) -> void:
	if is_server():
		_harvest_on_server(Net.my_id, resource_id)
	else:
		_request_harvest.rpc_id(1, resource_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_harvest(resource_id: int) -> void:
	if not is_server():
		return
	_harvest_on_server(multiplayer.get_remote_sender_id(), resource_id)

## Один удар. Сервер проверяет расстояние, инструмент и состояние источника.
func _harvest_on_server(peer_id: int, resource_id: int) -> void:
	var state: Dictionary = resources.get(resource_id, {})
	if state.is_empty():
		_send_notice(peer_id, "Источник не найден")
		return
	var tool := ItemDB.tool_tag(get_equipped(peer_id))
	if not Rules.can_harvest(String(state.get("type", "")), tool):
		var need := Rules.required_tool(String(state.get("type", "")))
		_send_notice(peer_id, "Нужен инструмент: %s" % ItemDB.display_name(need))
		return
	if positions.has(peer_id):
		var spot: Vector3 = state.get("position", Vector3.ZERO)
		var dist: float = (Vector3(positions[peer_id]) - spot).length()
		if dist > MAX_HARVEST_DISTANCE:
			_send_notice(peer_id, "Далеко от источника")
			return
	var outcome := Rules.apply_hit(state, tool)
	if not bool(outcome.get("ok", false)):
		_send_notice(peer_id, String(outcome.get("reason", "Не получилось")))
		return
	var new_state: Dictionary = outcome["node_state"]
	if not bool(new_state.get("alive", true)):
		var respawn := float(Rules.spec(String(new_state.get("type", ""))).get("respawn_seconds", 30.0))
		new_state["respawn_at"] = now_seconds() + respawn
	print("[GAME] #%d добыл %s из источника #%d" % [
		peer_id, String(outcome.get("item", "")), resource_id
	])
	_sync_resource.rpc(resource_id, new_state)
	give_item(peer_id, String(outcome.get("item", "")), int(outcome.get("count", 1)))

## Выдать предмет в сумку. Возвращает false, если места нет: крафту это
## нужно, чтобы вернуть материалы, а не потерять их.
func give_item(peer_id: int, item_id: String, amount: int) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	var inv: Inventory = inventories.get(peer_id, null)
	if inv == null:
		return false
	if not inv.add(item_id, amount):
		_send_notice(peer_id, "Сумка полна: %s" % ItemDB.display_name(item_id))
		return false
	_sync_inventory.rpc(peer_id, inv.to_dict())
	return true

## Разослать сумку игрока всем. Нужно механикам, которые меняют сумку сами:
## крафт списывает материалы и кладёт готовый предмет.
func push_inventory(peer_id: int) -> void:
	var inv: Inventory = inventories.get(peer_id, null)
	if inv == null:
		return
	_sync_inventory.rpc(peer_id, inv.to_dict())

# --- инвентарь и руки ------------------------------------------------------

func request_equip(item_id: String) -> void:
	if is_server():
		_equip_on_server(Net.my_id, item_id)
	else:
		_request_equip.rpc_id(1, item_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_equip(item_id: String) -> void:
	if not is_server():
		return
	_equip_on_server(multiplayer.get_remote_sender_id(), item_id)

func _equip_on_server(peer_id: int, item_id: String) -> void:
	if not ItemDB.is_equippable(item_id):
		return
	var inv: Inventory = inventories.get(peer_id, null)
	if inv == null or not inv.has(item_id):
		return
	if get_equipped(peer_id) == item_id:
		return
	_sync_equipped.rpc(peer_id, item_id)

# --- машины ----------------------------------------------------------------

func request_vehicle_enter(vehicle_id: int) -> void:
	if is_server():
		_vehicle_enter_on_server(Net.my_id, vehicle_id)
	else:
		_request_vehicle_enter.rpc_id(1, vehicle_id)

func request_vehicle_exit() -> void:
	if is_server():
		_vehicle_exit_on_server(Net.my_id)
	else:
		_request_vehicle_exit.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_vehicle_enter(vehicle_id: int) -> void:
	if not is_server():
		return
	_vehicle_enter_on_server(multiplayer.get_remote_sender_id(), vehicle_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_vehicle_exit() -> void:
	if not is_server():
		return
	_vehicle_exit_on_server(multiplayer.get_remote_sender_id())

func _vehicle_enter_on_server(peer_id: int, vehicle_id: int) -> void:
	var state: Dictionary = vehicles.get(vehicle_id, {})
	if state.is_empty():
		_send_notice(peer_id, "Машина не найдена")
		return
	if int(state.get("driver", 0)) != 0:
		_send_notice(peer_id, "Машина занята")
		return
	for key in vehicles:
		if int(vehicles[key].get("driver", 0)) == peer_id:
			_send_notice(peer_id, "Ты уже за рулём")
			return
	if positions.has(peer_id):
		var spot: Vector3 = state.get("position", Vector3.ZERO)
		if (Vector3(positions[peer_id]) - spot).length() > MAX_VEHICLE_DISTANCE:
			_send_notice(peer_id, "Далеко от машины")
			return
	state["driver"] = peer_id
	vehicles[vehicle_id] = state
	print("[GAME] #%d сел в машину #%d" % [peer_id, vehicle_id])
	_sync_vehicle.rpc(vehicle_id, peer_id, state.get("position", Vector3.ZERO), float(state.get("rotation", 0.0)))

func _vehicle_exit_on_server(peer_id: int) -> void:
	for key in vehicles:
		var state: Dictionary = vehicles[key]
		if int(state.get("driver", 0)) != peer_id:
			continue
		state["driver"] = 0
		vehicles[key] = state
		print("[GAME] #%d вышел из машины #%d" % [peer_id, key])
		_sync_vehicle.rpc(int(key), 0, state.get("position", Vector3.ZERO), float(state.get("rotation", 0.0)))
		return

## Водитель прислал положение. Сервер запоминает его для проверки дистанции,
## а все считают по нему скорость: по ней мобы получают урон от наезда.
## Слушаем только назначенного водителя.
func note_vehicle_transform(vehicle_id: int, peer_id: int, position: Vector3, rotation_y: float) -> void:
	var state: Dictionary = vehicles.get(vehicle_id, {})
	if state.is_empty():
		return
	if int(state.get("driver", 0)) != peer_id:
		return
	var previous: Vector3 = state.get("position", position)
	state["position"] = position
	state["rotation"] = rotation_y
	state["speed"] = _measure_speed(state, previous, position)
	vehicles[vehicle_id] = state

## Скорость по двум соседним положениям. Сглаживаем, потому что пакеты
## приходят неровно и без сглаживания удар дёргался бы.
func _measure_speed(state: Dictionary, previous: Vector3, position: Vector3) -> float:
	var now := now_seconds()
	var last_time := float(state.get("speed_time", now))
	var elapsed := maxf(0.02, now - last_time)
	var flat := Vector2(position.x - previous.x, position.z - previous.z).length()
	var instant := flat / elapsed
	var old_speed := float(state.get("speed", 0.0))
	state["speed_time"] = now
	return lerpf(old_speed, instant, 0.5)

@rpc("authority", "call_local", "reliable")
func _sync_vehicle(vehicle_id: int, driver: int, position: Vector3, rotation_y: float) -> void:
	# Скорость и время замера переносим: иначе смена водителя обнуляла бы
	# счётчик наездов на ровном месте.
	var previous: Dictionary = vehicles.get(vehicle_id, {})
	vehicles[vehicle_id] = {
		"driver": driver,
		"position": position,
		"rotation": rotation_y,
		"speed": float(previous.get("speed", 0.0)),
		"speed_time": float(previous.get("speed_time", 0.0)),
	}
	vehicles_changed.emit()

# --- синхронизация ---------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_resource(resource_id: int, state: Dictionary) -> void:
	resources[resource_id] = state
	resources_changed.emit()

@rpc("authority", "call_local", "reliable")
func _sync_inventory(peer_id: int, data: Dictionary) -> void:
	inventories[peer_id] = Inventory.from_dict(data)
	inventory_changed.emit(peer_id)

@rpc("authority", "call_local", "reliable")
func _sync_equipped(peer_id: int, item_id: String) -> void:
	equipped[peer_id] = item_id
	equipped_changed.emit(peer_id)

## Публичное сообщение игроку. Им пользуются механики: урон, мобы, крафт.
## Отказ при добыче идёт через _send_notice и пишется в лог как отказ,
## а здесь обычная строка состояния, чтобы лог не путал причину.
func notify_peer(peer_id: int, text: String) -> void:
	print("[GAME] #%d: %s" % [peer_id, text])
	if peer_id == Net.my_id:
		notice.emit(text)
		return
	if Net.is_offline():
		return
	_receive_notice.rpc_id(peer_id, text)

func _send_notice(peer_id: int, text: String) -> void:
	# Отказы видно в логе сервера: так проще разбирать рассинхрон и жалобы.
	print("[GAME] отказ #%d: %s" % [peer_id, text])
	if is_server() and peer_id == Net.my_id:
		notice.emit(text)
		return
	_receive_notice.rpc_id(peer_id, text)

@rpc("authority", "call_remote", "reliable")
func _receive_notice(text: String) -> void:
	notice.emit(text)
