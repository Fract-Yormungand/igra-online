extends Mechanic

## Механика мобов: кабаны в лесу, слаймы у камней, паук в шахте.
## Считает только сервер: он водит мобов, бьёт игроков и рассылает
## состояние. Клиент рисует и плавно догоняет. Урон идёт через механику
## характеристик, поэтому без неё мобы просто не ранят.
##
## Кабан мирный, бродит у своего места. Если его ударить, один раз
## отбрасывает обидчика и убегает 10 секунд, потом успокаивается.
## Слайм прыгает по прямой, прилипает к лицу и душит одной атакой раз в
## 3 секунды. Отбежал игрок, слайм стоит 2 секунды и прыгает снова.
## Паук кусает раз в 3 секунды, раз в 10 секунд кидает паутину и
## замедляет на 2 секунды.
##
## Выключил флаг mobs в features.cfg, и мир остаётся без зверей.

const MobScript := preload("res://scripts/mechanics/mobs/mob.gd")

const SYNC_INTERVAL := 0.15
## Дальше этого игрок моба не достаёт ударом. Чуть больше, чем у игрока:
## позиции по сети приходят с опозданием.
const PLAYER_REACH := 4.2
const REACH_SLACK := 1.0
## Сервер не верит клиенту на слово и не даёт бить чаще этого.
const ATTACK_COOLDOWN := 0.35
## После наезда моб не попадает под ту же машину, пока не отлетит.
const RAM_COOLDOWN := 0.6
## Дальше этого кабан не уходит от своего места, пока спокоен.
const HOME_RADIUS := 7.0
const FIELD_MARGIN := 3.0

const NAMES := {
	"boar": "Кабан",
	"slime": "Слайм",
	"spider": "Паук",
}

## Всё поведение в числах. Меняется здесь и только здесь.
## Сила, магия и ловкость нужны не для боя, а для награды за убийство:
## опыт считается по калькулятору из суммы характеристик моба.
const SPECS := {
	"boar": {
		"hp": 40.0, "body": 6.0, "strength": 6.0, "magic": 0.0, "agility": 4.0,
		"respawn": 30.0, "activate": 30.0,
		"speed": 1.6, "flee_speed": 9.0, "flee_time": 10.0, "push_force": 16.0,
	},
	"slime": {
		"hp": 22.0, "body": 4.0, "strength": 0.0, "magic": 4.0, "agility": 6.0,
		"respawn": 20.0, "activate": 24.0,
		"damage": 5.0, "attack_interval": 3.0, "leap_range": 8.0,
		"leap_speed": 9.0, "leap_time": 0.45, "attach_range": 1.6,
		"detach_range": 2.8, "pause_time": 2.0,
	},
	"spider": {
		"hp": 60.0, "body": 10.0, "strength": 8.0, "magic": 0.0, "agility": 10.0,
		"respawn": 60.0, "activate": 26.0,
		"damage": 8.0, "attack_interval": 3.0, "speed": 3.2,
		"melee_range": 2.6, "web_interval": 10.0, "web_range": 9.0, "slow_time": 2.0,
	},
}

var _nodes: Dictionary = {}
var _states: Dictionary = {}
var _last_attack: Dictionary = {}
var _ram_left: Dictionary = {}
var _mobs_root: Node3D
var _sync_left := 0.0

# --- жизненный цикл --------------------------------------------------------

func start() -> void:
	_build_mobs()
	if is_server():
		return
	if Net.is_offline():
		return
	Net.connection_ready.connect(_request_when_ready)
	_request_state.rpc_id(1)

func _build_mobs() -> void:
	_mobs_root = Node3D.new()
	_mobs_root.name = "Mobs"
	add_child(_mobs_root)
	for entry in WorldGen.mob_spawns():
		var mob_id := int(entry["id"])
		var mob_type := String(entry["type"])
		var spot: Vector3 = entry["position"]
		var mob := MobScript.new()
		mob.setup(mob_id, mob_type, spot, float(entry["rot_y"]))
		mob.name = "M_%d" % mob_id
		mob.set_remote(not is_server())
		_mobs_root.add_child(mob)
		_nodes[mob_id] = mob
		_states[mob_id] = _fresh_state(mob_id, mob_type, spot)

func _fresh_state(mob_id: int, mob_type: String, spot: Vector3) -> Dictionary:
	var spec := _spec(mob_type)
	return {
		"id": mob_id,
		"type": mob_type,
		"home": spot,
		"position": spot,
		"yaw": 0.0,
		"hp": float(spec["hp"]),
		"alive": true,
		"respawn_left": 0.0,
		"mode": "calm" if mob_type == "boar" else "idle",
		"timer": 0.0,
		"phase": float(mob_id) * 1.7,
		"flee_dir": Vector3.FORWARD,
		"leap_dir": Vector3.FORWARD,
		"target": 0,
		"attached_to": 0,
		"attack_left": 0.0,
		"web_left": float(spec.get("web_interval", 0.0)),
		"knock_left": 0.0,
		"knock_dir": Vector3.ZERO,
		"knock_speed": 0.0,
	}

## Снимок состояния: его смотрят тесты и панель отладки.
func snapshot() -> Dictionary:
	var result := {}
	for key in _states:
		var state: Dictionary = _states[key]
		result[int(key)] = {
			"type": String(state["type"]),
			"position": state["position"],
			"alive": bool(state["alive"]),
			"mode": String(state["mode"]),
			"hp": float(state["hp"]),
		}
	return result

# --- серверный цикл --------------------------------------------------------

func _process(delta: float) -> void:
	if not is_server():
		return
	for key in _states.keys():
		_update_mob(int(key), delta)
	_ram_check(delta)
	if Net.is_offline():
		return
	_sync_left -= delta
	if _sync_left > 0.0:
		return
	_sync_left = SYNC_INTERVAL
	for key in _states.keys():
		var state: Dictionary = _states[key]
		_sync_mob.rpc(
			int(key), state["position"], float(state["yaw"]),
			bool(state["alive"]), float(state["hp"]), String(state["mode"])
		)

func _update_mob(mob_id: int, delta: float) -> void:
	var state: Dictionary = _states[mob_id]
	if not bool(state["alive"]):
		state["respawn_left"] = float(state["respawn_left"]) - delta
		if float(state["respawn_left"]) <= 0.0:
			_respawn(state)
		return

	var spec := _spec(String(state["type"]))
	if float(state["knock_left"]) > 0.0:
		# Отброшенный моб летит по инерции и не соображает, пока не встанет.
		_update_knock(state, delta)
		_place(state)
		return

	var target := _nearest_player(Vector3(state["position"]), float(spec["activate"]))
	state["target"] = target
	match String(state["type"]):
		"boar":
			_update_boar(state, spec, delta)
		"slime":
			_update_slime(state, spec, target, delta)
		"spider":
			_update_spider(state, spec, target, delta)
	_place(state)

func _update_knock(state: Dictionary, delta: float) -> void:
	state["knock_left"] = float(state["knock_left"]) - delta
	var direction: Vector3 = state["knock_dir"]
	var speed := float(state["knock_speed"])
	state["position"] = Vector3(state["position"]) + direction * speed * delta
	state["knock_speed"] = maxf(0.0, speed - RamRules.KNOCK_DECAY * delta)
	state["yaw"] = _yaw_of(direction)
	if float(state["knock_left"]) <= 0.0:
		state["knock_left"] = 0.0
		state["knock_speed"] = 0.0

## Кабан ходит кругами у дома. Бежит он только от обидчика, после удара.
func _update_boar(state: Dictionary, spec: Dictionary, delta: float) -> void:
	if String(state["mode"]) == "flee":
		state["timer"] = float(state["timer"]) - delta
		var flee_dir: Vector3 = state["flee_dir"]
		state["position"] = Vector3(state["position"]) + flee_dir * float(spec["flee_speed"]) * delta
		state["yaw"] = _yaw_of(flee_dir)
		if float(state["timer"]) <= 0.0:
			state["mode"] = "calm"
			state["timer"] = 0.0
		return

	state["phase"] = float(state["phase"]) + delta * 0.6
	var angle := float(state["phase"])
	var away := Vector3(cos(angle), 0.0, sin(angle))
	var spot: Vector3 = Vector3(state["position"]) + away * float(spec["speed"]) * delta
	var home: Vector3 = state["home"]
	if spot.distance_to(home) > HOME_RADIUS:
		spot = home + (spot - home).normalized() * HOME_RADIUS
	state["position"] = spot
	state["yaw"] = _yaw_of(away)

## Слайм: прилип, душит, отпустил, постоял и прыгает снова.
func _update_slime(state: Dictionary, spec: Dictionary, target: int, delta: float) -> void:
	var mode := String(state["mode"])

	if mode == "attached":
		var victim := int(state["attached_to"])
		if victim == 0 or not Game.positions.has(victim):
			_detach(state, spec)
			return
		var player_spot := _position_of(victim)
		if _flat_distance(Vector3(state["position"]), player_spot) > float(spec["detach_range"]):
			_detach(state, spec)
			return
		state["position"] = player_spot + Vector3(0.0, 1.15, 0.0)
		state["attack_left"] = float(state["attack_left"]) - delta
		if float(state["attack_left"]) <= 0.0:
			state["attack_left"] = float(spec["attack_interval"])
			_hit_player(victim, float(spec["damage"]), "slime", "Слайм душит")
		return

	if mode == "leap":
		state["timer"] = float(state["timer"]) - delta
		var leap_dir: Vector3 = state["leap_dir"]
		state["position"] = Vector3(state["position"]) + leap_dir * float(spec["leap_speed"]) * delta
		state["yaw"] = _yaw_of(leap_dir)
		if float(state["timer"]) <= 0.0:
			_land_slime(state, spec)
		return

	if mode == "pause":
		state["timer"] = float(state["timer"]) - delta
		if float(state["timer"]) <= 0.0:
			state["mode"] = "idle"
		return

	if target == 0:
		return
	var player_spot := _position_of(target)
	if _flat_distance(Vector3(state["position"]), player_spot) > float(spec["leap_range"]):
		return
	var to_player := _flat_direction(Vector3(state["position"]), player_spot)
	state["mode"] = "leap"
	state["timer"] = float(spec["leap_time"])
	state["leap_dir"] = to_player
	state["yaw"] = _yaw_of(to_player)

## Приземлился: попал в игрока, значит повис на нём, иначе стоит 2 секунды.
func _land_slime(state: Dictionary, spec: Dictionary) -> void:
	var victim := _nearest_player(Vector3(state["position"]), float(spec["attach_range"]))
	if victim == 0:
		_detach(state, spec)
		return
	state["mode"] = "attached"
	state["attached_to"] = victim
	state["attack_left"] = 0.0

func _detach(state: Dictionary, spec: Dictionary) -> void:
	state["mode"] = "pause"
	state["timer"] = float(spec["pause_time"])
	state["attached_to"] = 0
	state["attack_left"] = 0.0

func _update_spider(state: Dictionary, spec: Dictionary, target: int, delta: float) -> void:
	state["attack_left"] = maxf(0.0, float(state["attack_left"]) - delta)
	state["web_left"] = maxf(0.0, float(state["web_left"]) - delta)
	if target == 0:
		return

	var here := Vector3(state["position"])
	var player_spot := _position_of(target)
	var flat := _flat_distance(here, player_spot)

	if flat <= float(spec["web_range"]) and float(state["web_left"]) <= 0.0:
		state["web_left"] = float(spec["web_interval"])
		_slow_player(target, float(spec["slow_time"]))
		Game.notify_peer(target, "Паутина облепила ноги: движение медленнее")

	if flat > float(spec["melee_range"]):
		var to_player := _flat_direction(here, player_spot)
		state["position"] = here + to_player * float(spec["speed"]) * delta
		state["yaw"] = _yaw_of(to_player)
		return

	if float(state["attack_left"]) <= 0.0:
		state["attack_left"] = float(spec["attack_interval"])
		_hit_player(target, float(spec["damage"]), "spider", "Паук укусил")

# --- удар игрока -----------------------------------------------------------

func request_attack(target_mob_id: int) -> void:
	if is_server():
		_attack_on_server(Net.my_id, target_mob_id)
		return
	if Net.is_offline():
		return
	_request_attack.rpc_id(1, target_mob_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(target_mob_id: int) -> void:
	if not is_server():
		return
	_attack_on_server(multiplayer.get_remote_sender_id(), target_mob_id)

## Сервер сам решает, дошёл ли удар: проверяет расстояние и темп.
func _attack_on_server(peer_id: int, mob_id: int) -> void:
	var state: Dictionary = _states.get(mob_id, {})
	if state.is_empty() or not bool(state["alive"]):
		return
	if not Game.positions.has(peer_id):
		return
	if _flat_distance(Vector3(Game.positions[peer_id]), Vector3(state["position"])) > PLAYER_REACH + REACH_SLACK:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_attack.get(peer_id, 0)) < int(ATTACK_COOLDOWN * 1000.0):
		return
	_last_attack[peer_id] = now

	var spec := _spec(String(state["type"]))
	var strength := 10.0
	var stats := _stats()
	if stats != null:
		strength = float(stats.effective_attributes(peer_id)["strength"])
	# Оружие в руке усиливает удар, инструмент бьёт как кулак. Сама формула
	# урона не меняется: сила проходит через тело моба.
	var weapon := ItemDB.attack_multiplier(Game.get_equipped(peer_id))
	var dealt := DerivedStats.damage_through_body(strength * weapon, float(spec["body"]))
	state["hp"] = maxf(0.0, float(state["hp"]) - dealt)
	print("[MOBS] #%d ударил %s #%d на %.1f, осталось %.1f" % [
		peer_id, String(NAMES.get(String(state["type"]), "моб")), mob_id, dealt, float(state["hp"])
	])
	# Каждый удар изнашивает инструмент в руке, даже если моб умер.
	Game.spend_tool(peer_id)

	if float(state["hp"]) <= 0.0:
		_kill(state, peer_id)
		return
	if String(state["type"]) == "boar":
		_boar_react(peer_id, state)

## Один раз отбрасывает обидчика и убегает. Второй удар в спину уже не
## толкает, кабан просто продолжает бежать.
func _boar_react(attacker: int, state: Dictionary) -> void:
	var boar_spot := Vector3(state["position"])
	var away := _flat_direction(boar_spot, _position_of(attacker))
	state["flee_dir"] = -away
	state["yaw"] = _yaw_of(-away)
	if String(state["mode"]) == "flee":
		return
	state["mode"] = "flee"
	state["timer"] = float(_spec("boar")["flee_time"])
	_send_push(attacker, away, float(_spec("boar")["push_force"]))
	Game.notify_peer(attacker, "Кабан боднул и убежал")

func _kill(state: Dictionary, hunter: int) -> void:
	state["alive"] = false
	state["mode"] = "dead"
	state["respawn_left"] = float(_spec(String(state["type"]))["respawn"])
	var mob_id := int(state["id"])
	var node = _nodes.get(mob_id, null)
	if node != null:
		node.visible = false
	var reward := reward_for(String(state["type"]))
	var mob_name := String(NAMES.get(String(state["type"]), "Моб"))
	if hunter != 0:
		_grant_exp(hunter, reward)
		Game.notify_peer(hunter, "%s сбит: +%d опыта" % [mob_name, reward])
	print("[MOBS] %s #%d сбит игроком #%d, награда %d" % [String(state["type"]), mob_id, hunter, reward])

## Опыт за убийство по калькулятору: сумма характеристик моба, делённая на
## пять. Считается от данных вида, а не от текущего здоровья.
func reward_for(mob_type: String) -> int:
	var spec := _spec(mob_type)
	return LevelRules.exp_reward(
		float(spec.get("hp", 0.0)),
		float(spec.get("strength", 0.0)),
		float(spec.get("magic", 0.0)),
		float(spec.get("body", 0.0)),
		float(spec.get("agility", 0.0))
	)

## Опыт получает тот, кто добил: у наезда это водитель, у удара бьющий.
func _grant_exp(peer_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var stats := _stats()
	if stats != null:
		stats.add_exp(peer_id, amount)

func _respawn(state: Dictionary) -> void:
	var mob_id := int(state["id"])
	var mob_type := String(state["type"])
	var home: Vector3 = state["home"]
	var fresh := _fresh_state(mob_id, mob_type, home)
	fresh["phase"] = float(state["phase"])
	_states[mob_id] = fresh
	var node = _nodes.get(mob_id, null)
	if node != null:
		node.visible = true
		node.position = home

# --- наезд машины ----------------------------------------------------------

## Машину ведёт клиент, поэтому скорость сервер считает сам по присланным
## положениям. На слово клиенту про удар не верим.
func _ram_check(delta: float) -> void:
	for key in _ram_left.keys():
		_ram_left[key] = maxf(0.0, float(_ram_left[key]) - delta)
	for vehicle_id in Game.vehicles:
		var vehicle: Dictionary = Game.vehicles[vehicle_id]
		var driver := int(vehicle.get("driver", 0))
		if driver == 0:
			continue
		var speed := float(vehicle.get("speed", 0.0))
		if not RamRules.can_hit(speed):
			continue
		var car_spot: Vector3 = vehicle.get("position", Vector3.ZERO)
		for mob_key in _states:
			var mob_id := int(mob_key)
			if float(_ram_left.get(mob_id, 0.0)) > 0.0:
				continue
			var state: Dictionary = _states[mob_id]
			if not bool(state["alive"]):
				continue
			if _flat_distance(car_spot, Vector3(state["position"])) > RamRules.HIT_RADIUS:
				continue
			_ram_mob(state, speed, car_spot, driver)

func _ram_mob(state: Dictionary, speed: float, car_spot: Vector3, driver: int) -> void:
	var mob_id := int(state["id"])
	var spec := _spec(String(state["type"]))
	var dealt := RamRules.damage(speed, float(spec["body"]))
	state["hp"] = maxf(0.0, float(state["hp"]) - dealt)
	_ram_left[mob_id] = RAM_COOLDOWN

	# Слайм на лице мешает водителю: наезд сбивает его с игрока.
	if String(state["mode"]) == "attached":
		_detach(state, spec)

	var away := _flat_direction(car_spot, Vector3(state["position"]))
	state["knock_dir"] = away
	state["knock_left"] = RamRules.KNOCK_TIME
	state["knock_speed"] = RamRules.knock_speed(speed)
	if String(state["type"]) == "boar":
		state["mode"] = "flee"
		state["timer"] = float(_spec("boar")["flee_time"])
		state["flee_dir"] = away

	var mob_name := String(NAMES.get(String(state["type"]), "моб"))
	print("[MOBS] машина #%d сбила %s #%d на %.0f км/ч, урон %.1f, осталось %.1f" % [
		driver, mob_name, mob_id, speed * 3.6, dealt, float(state["hp"])
	])
	if float(state["hp"]) <= 0.0:
		_kill(state, driver)
		return
	Game.notify_peer(driver, "Сбил: %s" % mob_name)

# --- игроки и урон ---------------------------------------------------------

func _nearest_player(spot: Vector3, radius: float) -> int:
	var best := 0
	var best_distance := radius
	var stats := _stats()
	for key in Game.positions:
		var peer_id := int(key)
		if stats != null and bool(stats.is_downed(peer_id)):
			continue
		var flat := _flat_distance(spot, Vector3(Game.positions[key]))
		if flat > best_distance:
			continue
		best = peer_id
		best_distance = flat
	return best

func _hit_player(peer_id: int, attack: float, kind: String, text: String) -> void:
	var stats := _stats()
	if stats == null:
		return
	var dealt: float = stats.damage(peer_id, attack, kind)
	if dealt <= 0.0:
		return
	Game.notify_peer(peer_id, "%s: -%d" % [text, int(round(dealt))])

## Паутина: скорость режет клиент-владелец, решает сервер.
func _slow_player(peer_id: int, seconds: float) -> void:
	_apply_slow_locally(peer_id, seconds)
	if Net.is_offline():
		return
	_receive_slow.rpc(peer_id, seconds)

@rpc("authority", "call_remote", "reliable")
func _receive_slow(peer_id: int, seconds: float) -> void:
	_apply_slow_locally(peer_id, seconds)

func _apply_slow_locally(peer_id: int, seconds: float) -> void:
	if Net.my_id != peer_id:
		return
	var player := local_player()
	if player != null:
		player.apply_slow(seconds)

func _send_push(peer_id: int, direction: Vector3, force: float) -> void:
	_apply_push_locally(peer_id, direction, force)
	if Net.is_offline():
		return
	_receive_push.rpc(peer_id, direction, force)

@rpc("authority", "call_remote", "reliable")
func _receive_push(peer_id: int, direction: Vector3, force: float) -> void:
	_apply_push_locally(peer_id, direction, force)

func _apply_push_locally(peer_id: int, direction: Vector3, force: float) -> void:
	if Net.my_id != peer_id:
		return
	var player := local_player()
	if player != null:
		player.apply_push(direction, force)

func _stats() -> Node:
	return Features.mechanic("stats")

# --- общее -----------------------------------------------------------------

func _spec(mob_type: String) -> Dictionary:
	return SPECS.get(mob_type, SPECS["boar"])

func _place(state: Dictionary) -> void:
	var mob_id := int(state["id"])
	var node: Node3D = _nodes.get(mob_id, null)
	if node == null:
		return
	var spot := _clamp_field(Vector3(state["position"]))
	state["position"] = spot
	node.position = spot
	node.rotation.y = float(state["yaw"])

func _clamp_field(spot: Vector3) -> Vector3:
	var limit := WorldGen.PLATFORM_SIZE * 0.5 - FIELD_MARGIN
	return Vector3(clampf(spot.x, -limit, limit), spot.y, clampf(spot.z, -limit, limit))

func _position_of(peer_id: int) -> Vector3:
	return Vector3(Game.positions.get(peer_id, Vector3.ZERO))

func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	if direction.length() < 0.01:
		return Vector3.FORWARD
	return direction.normalized()

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

# --- сеть ------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_mob(mob_id: int, spot: Vector3, yaw: float, alive: bool, hp: float, mode: String) -> void:
	var state: Dictionary = _states.get(mob_id, {})
	if state.is_empty():
		return
	state["position"] = spot
	state["yaw"] = yaw
	state["alive"] = alive
	state["hp"] = hp
	state["mode"] = mode
	_states[mob_id] = state
	var mob = _nodes.get(mob_id, null)
	if mob == null:
		return
	var max_hp := maxf(1.0, float(_spec(String(state["type"]))["hp"]))
	mob.apply_state(spot, yaw, alive, hp / max_hp)

@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for key in _states:
		var state: Dictionary = _states[key]
		_sync_mob.rpc_id(
			sender, int(key), state["position"], float(state["yaw"]),
			bool(state["alive"]), float(state["hp"]), String(state["mode"])
		)

func _request_when_ready() -> void:
	if is_server() or Net.is_offline():
		return
	_request_state.rpc_id(1)
