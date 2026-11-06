extends Mechanic

## Механика характеристик: сила, тело, магия, ловкость плюс здоровье и запас
## сил. Считает только сервер, клиент показывает и просит.
##
## Внешний контракт для других механик:
##   var stats = Features.mechanic("stats")
##   if stats != null: stats.damage(peer_id, 20.0, DerivedStats.DAMAGE_PHYSICAL)
## Механики мобов и крафта не обязаны проверять, есть ли статистика: сервер
## сам решит, чему верить. Без этой механики урон просто некуда писать.

signal stats_changed(peer_id: int)

const REGEN_INTERVAL := 1.0
const HP_REGEN := 1.5
const MP_REGEN := 8.0
## Сколько здоровья возвращается при возврате в лагерь после падения.
const REVIVE_HP_SHARE := 0.5
## Потолок на одно списание запаса сил: клиент не может списать всё разом.
const MAX_MANA_REQUEST := 40.0

var _attributes: Dictionary = {}
var _hp: Dictionary = {}
var _mp: Dictionary = {}
var _downed: Dictionary = {}
var _regen_left := REGEN_INTERVAL

func start() -> void:
	Net.roster_changed.connect(_on_roster_changed)
	if is_server():
		_sync_all()
		return
	_request_full.rpc_id(1)
	Net.connection_ready.connect(_request_when_ready)

func _process(delta: float) -> void:
	if not is_server():
		return
	_regen_left -= delta
	if _regen_left > 0.0:
		return
	_regen_left = REGEN_INTERVAL
	_regen_tick()

func _regen_tick() -> void:
	for key in _attributes.keys():
		var peer_id := int(key)
		if bool(_downed.get(peer_id, false)):
			continue
		var attrs: Dictionary = _attributes[peer_id]
		var hp_now: float = float(_hp.get(peer_id, 0.0))
		var mp_now: float = float(_mp.get(peer_id, 0.0))
		var hp_new: float = minf(DerivedStats.max_hp(attrs), hp_now + HP_REGEN)
		var mp_new: float = minf(DerivedStats.max_mp(attrs), mp_now + MP_REGEN)
		if is_equal_approx(hp_new, hp_now) and is_equal_approx(mp_new, mp_now):
			continue
		_hp[peer_id] = hp_new
		_mp[peer_id] = mp_new
		_push(peer_id)

# --- чтение ----------------------------------------------------------------

func attributes(peer_id: int) -> Dictionary:
	return DerivedStats.normalized(_attributes.get(peer_id, DerivedStats.start_attributes()))

func derived(peer_id: int) -> Dictionary:
	return DerivedStats.derived(attributes(peer_id))

func max_hp(peer_id: int) -> float:
	return DerivedStats.max_hp(attributes(peer_id))

func max_mp(peer_id: int) -> float:
	return DerivedStats.max_mp(attributes(peer_id))

func hp(peer_id: int) -> float:
	return float(_hp.get(peer_id, max_hp(peer_id)))

func mp(peer_id: int) -> float:
	return float(_mp.get(peer_id, max_mp(peer_id)))

func is_downed(peer_id: int) -> bool:
	return bool(_downed.get(peer_id, false))

func speed_multiplier(peer_id: int) -> float:
	return DerivedStats.speed_multiplier(attributes(peer_id))

func dodge_chance(peer_id: int) -> float:
	return DerivedStats.dodge_chance(attributes(peer_id))

func physical_power(peer_id: int) -> float:
	return DerivedStats.physical_power(attributes(peer_id))

# --- изменение, только сервер ----------------------------------------------

## Наносит урон и возвращает, сколько дошло после сопротивления.
## Урон кладёт игрока, но не выключает его: клиент сам уводит тело в лагерь
## и просит подъём. Так позиция остаётся клиентской, как и у всей игры.
func damage(peer_id: int, amount: float, kind: String = DerivedStats.DAMAGE_PHYSICAL) -> float:
	if not is_server() or amount <= 0.0:
		return 0.0
	_ensure(peer_id)
	if bool(_downed.get(peer_id, false)):
		return 0.0
	var dealt := DerivedStats.damage_after_resistance(amount, kind, _attributes[peer_id])
	var left := maxf(0.0, float(_hp.get(peer_id, 0.0)) - dealt)
	_hp[peer_id] = left
	if left <= 0.0:
		_downed[peer_id] = true
		Game.notify_peer(peer_id, "Тебя свалили. Возвращаешься в лагерь.")
	_push(peer_id)
	return dealt

func heal(peer_id: int, amount: float) -> void:
	if not is_server() or amount <= 0.0:
		return
	_ensure(peer_id)
	var cap := DerivedStats.max_hp(_attributes[peer_id])
	_hp[peer_id] = minf(cap, float(_hp.get(peer_id, 0.0)) + amount)
	_push(peer_id)

func set_attributes(peer_id: int, new_attributes: Dictionary) -> void:
	if not is_server():
		return
	_ensure(peer_id)
	_attributes[peer_id] = DerivedStats.normalized(new_attributes)
	_hp[peer_id] = minf(float(_hp.get(peer_id, 0.0)), DerivedStats.max_hp(_attributes[peer_id]))
	_mp[peer_id] = minf(float(_mp.get(peer_id, 0.0)), DerivedStats.max_mp(_attributes[peer_id]))
	_push(peer_id)

## Клиент просит списать запас сил (бег). Сервер решает сам.
func request_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	if is_server():
		_spend_mana(Net.my_id, amount)
		return
	if Net.is_offline():
		return
	_request_mana.rpc_id(1, amount)

func request_revive() -> void:
	if is_server():
		_revive_on_server(Net.my_id)
		return
	if Net.is_offline():
		return
	_request_revive.rpc_id(1)

func _spend_mana(peer_id: int, amount: float) -> bool:
	_ensure(peer_id)
	var left := float(_mp.get(peer_id, 0.0))
	if left < amount:
		return false
	_mp[peer_id] = left - amount
	_push(peer_id)
	return true

func _revive_on_server(peer_id: int) -> void:
	_ensure(peer_id)
	if not bool(_downed.get(peer_id, false)):
		return
	_downed[peer_id] = false
	_hp[peer_id] = DerivedStats.max_hp(_attributes[peer_id]) * REVIVE_HP_SHARE
	_mp[peer_id] = DerivedStats.max_mp(_attributes[peer_id]) * REVIVE_HP_SHARE
	Game.notify_peer(peer_id, "Очнулся в лагере. Силы вернулись наполовину.")
	_push(peer_id)

# --- состав игроков и сеть -------------------------------------------------

func _on_roster_changed(players: Dictionary) -> void:
	if not is_server():
		return
	for key in players:
		var peer_id := int(key)
		if _attributes.has(peer_id):
			continue
		_ensure(peer_id)
		_push(peer_id)
	for key in _attributes.keys():
		var peer_id := int(key)
		if players.has(peer_id):
			continue
		_attributes.erase(peer_id)
		_hp.erase(peer_id)
		_mp.erase(peer_id)
		_downed.erase(peer_id)

func _ensure(peer_id: int) -> void:
	if _attributes.has(peer_id):
		return
	var attrs := DerivedStats.start_attributes()
	_attributes[peer_id] = attrs
	_hp[peer_id] = DerivedStats.max_hp(attrs)
	_mp[peer_id] = DerivedStats.max_mp(attrs)
	_downed[peer_id] = false

func _sync_all() -> void:
	for key in Net.players:
		var peer_id := int(key)
		_ensure(peer_id)
		_push(peer_id)

func _payload(peer_id: int) -> Dictionary:
	var attrs: Dictionary = _attributes.get(peer_id, DerivedStats.start_attributes())
	return {
		"attributes": attrs.duplicate(),
		"hp": float(_hp.get(peer_id, 0.0)),
		"mp": float(_mp.get(peer_id, 0.0)),
		"downed": bool(_downed.get(peer_id, false)),
	}

func _push(peer_id: int) -> void:
	if not is_server():
		return
	_send(peer_id, -1)

## target меньше нуля: всем. Иначе конкретному игроку.
func _send(peer_id: int, target: int) -> void:
	var payload := _payload(peer_id)
	if Net.is_offline():
		_sync_stats(peer_id, payload)
		return
	if target < 0:
		_sync_stats.rpc(peer_id, payload)
	else:
		_sync_stats.rpc_id(target, peer_id, payload)

func _request_when_ready() -> void:
	if is_server():
		return
	_request_full.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_full() -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for key in Net.players:
		var peer_id := int(key)
		_ensure(peer_id)
		_send(peer_id, sender)

@rpc("any_peer", "call_remote", "reliable")
func _request_mana(amount: float) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_spend_mana(sender, clampf(amount, 0.0, MAX_MANA_REQUEST))

@rpc("any_peer", "call_remote", "reliable")
func _request_revive() -> void:
	if not is_server():
		return
	_revive_on_server(multiplayer.get_remote_sender_id())

@rpc("authority", "call_local", "reliable")
func _sync_stats(peer_id: int, payload: Dictionary) -> void:
	_attributes[peer_id] = DerivedStats.normalized(payload.get("attributes", {}))
	_hp[peer_id] = float(payload.get("hp", 0.0))
	_mp[peer_id] = float(payload.get("mp", 0.0))
	_downed[peer_id] = bool(payload.get("downed", false))
	stats_changed.emit(peer_id)
