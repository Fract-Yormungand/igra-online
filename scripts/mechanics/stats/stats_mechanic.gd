extends Mechanic

## Механика характеристик: сила, тело, магия, ловкость, здоровье, запас сил
## и прокачка. Считает только сервер, клиент показывает и просит. Формулы
## живут в DerivedStats и LevelRules, здесь состояние и сеть.
##
## Внешний контракт для других механик:
##   var stats = Features.mechanic("stats")
##   if stats != null: stats.damage(peer_id, 12.0)
##   if stats != null: stats.add_exp(peer_id, 11)
## Нет механики, урон и опыт просто некуда писать, остальной мир живёт.

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
## Прокачка: уровень, опыт, эволюция и раскладка очков по характеристикам.
var _level: Dictionary = {}
var _exp: Dictionary = {}
var _evolution: Dictionary = {}
var _points: Dictionary = {}
var _regen_left := REGEN_INTERVAL

func start() -> void:
	Net.roster_changed.connect(_on_roster_changed)
	if is_server():
		_sync_all()
		return
	if not Net.is_offline():
		_request_full.rpc_id(1)
	Net.connection_ready.connect(_request_when_ready)

func _process(delta: float) -> void:
	if not is_server():
		return
	_regen_left -= delta
	if _regen_left > 0.0:
		return
	_regen_left = REGEN_INTERVAL
	_tick()

## Раз в секунду: восстановление и самоурон от перегруза.
func _tick() -> void:
	for key in _attributes.keys():
		var peer_id := int(key)
		if bool(_downed.get(peer_id, false)):
			continue
		var attrs: Dictionary = _attributes[peer_id]
		var overload := DerivedStats.overload_self_damage(attrs)
		if overload > 0.0:
			_apply(peer_id, overload)
			if bool(_downed.get(peer_id, false)):
				continue
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

## Коэффициент состояния: корень из произведения долей здоровья и запаса сил.
func state_coefficient(peer_id: int) -> float:
	var hp_share: float = hp(peer_id) / maxf(1.0, max_hp(peer_id))
	var mp_share: float = mp(peer_id) / maxf(1.0, max_mp(peer_id))
	return DerivedStats.state_coefficient(hp_share, mp_share)

## Характеристики с учётом состояния: раненый слабее по всем статам сразу.
func effective_attributes(peer_id: int) -> Dictionary:
	return DerivedStats.effective(attributes(peer_id), state_coefficient(peer_id))

func speed_kmh(peer_id: int) -> float:
	return DerivedStats.speed_kmh(effective_attributes(peer_id))

func speed_mps(peer_id: int) -> float:
	return DerivedStats.speed_mps(effective_attributes(peer_id))

func actions_per_round(peer_id: int) -> int:
	return DerivedStats.actions_per_round(effective_attributes(peer_id))

# --- прокачка --------------------------------------------------------------

func level(peer_id: int) -> int:
	return int(_level.get(peer_id, 0))

func exp_value(peer_id: int) -> int:
	return int(_exp.get(peer_id, 0))

func evolution(peer_id: int) -> int:
	return int(_evolution.get(peer_id, 0))

## Сколько опыта нужно до следующего уровня по калькулятору.
func exp_next(peer_id: int) -> int:
	return LevelRules.exp_to_next(evolution(peer_id), level(peer_id))

func level_cap(peer_id: int) -> int:
	return LevelRules.level_cap(evolution(peer_id))

## Сколько очков ещё не разложено: пул эволюции и уровня минус вложенное.
func available_points(peer_id: int) -> int:
	var total := LevelRules.total_points(evolution(peer_id), level(peer_id))
	return maxi(0, total - _allocated(peer_id))

func _allocated(peer_id: int) -> int:
	var points: Dictionary = _points.get(peer_id, {})
	var total := 0
	for key in points:
		total += int(points[key])
	return total

## Всё про прокачку одной строкой для окна и тестов.
func progress(peer_id: int) -> Dictionary:
	return {
		"level": level(peer_id),
		"cap": level_cap(peer_id),
		"exp": exp_value(peer_id),
		"exp_next": exp_next(peer_id),
		"evolution": evolution(peer_id),
		"points": available_points(peer_id),
		"allocated": _allocated(peer_id),
	}

## Сводка для панели: формулы плюс текущее состояние.
func derived(peer_id: int) -> Dictionary:
	var base := attributes(peer_id)
	var result := DerivedStats.derived(base)
	var eff := effective_attributes(peer_id)
	result["coefficient"] = state_coefficient(peer_id)
	result["effective"] = eff
	result["reference_damage"] = DerivedStats.damage_through_body(
		float(eff["strength"]), float(eff["body"])
	)
	result["magic_best"] = DerivedStats.best_magic_charge(
		float(eff["magic"]), float(base["body"])
	)
	return result

# --- изменение, только сервер ----------------------------------------------

## Урон. attack это сила удара (или заряд заклинания), тело цели режет его
## по формуле удар / (удар + тело). Возвращает, сколько дошло.
func damage(peer_id: int, attack: float, kind: String = "physical") -> float:
	if not is_server() or attack <= 0.0:
		return 0.0
	_ensure(peer_id)
	if bool(_downed.get(peer_id, false)):
		return 0.0
	var body := float(effective_attributes(peer_id)["body"])
	var dealt := DerivedStats.damage_through_body(attack, body)
	return _apply(peer_id, dealt, kind)

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
	# Разложенные очки пересчитываем от стартового набора: иначе пул очков
	# разъедется с характеристиками.
	var start := DerivedStats.start_attributes()
	var points := {}
	for key in DerivedStats.ATTRIBUTE_KEYS:
		points[key] = maxi(0, int(_attributes[peer_id][key]) - int(start[key]))
	_points[peer_id] = points
	_hp[peer_id] = minf(float(_hp.get(peer_id, 0.0)), DerivedStats.max_hp(_attributes[peer_id]))
	_mp[peer_id] = minf(float(_mp.get(peer_id, 0.0)), DerivedStats.max_mp(_attributes[peer_id]))
	_push(peer_id)

## Начисление опыта. Уровни идут подряд, пока хватает опыта. На капе
## эволюция растёт сама: подрас у нас нет, выбирать нечего.
func add_exp(peer_id: int, amount: int) -> void:
	if not is_server() or amount <= 0:
		return
	_ensure(peer_id)
	var result := LevelRules.add_exp(
		evolution(peer_id), level(peer_id), exp_value(peer_id), amount
	)
	_level[peer_id] = int(result["level"])
	_exp[peer_id] = int(result["exp"])
	_evolution[peer_id] = int(result["evolution"])

	if int(result["levels_gained"]) > 0:
		# Как в калькуляторе: новый уровень возвращает полное здоровье и силы.
		_hp[peer_id] = max_hp(peer_id)
		_mp[peer_id] = max_mp(peer_id)
		Game.notify_peer(peer_id, "Уровень %d, свободных очков %d" % [
			level(peer_id), available_points(peer_id)
		])
		print("[STATS] #%d поднял уровень до %d, свободных очков %d" % [
			peer_id, level(peer_id), available_points(peer_id)
		])
	if int(result["evolved"]) > 0:
		Game.notify_peer(peer_id, "Эволюция %d" % evolution(peer_id))
		print("[STATS] #%d перешёл на эволюцию %d" % [peer_id, evolution(peer_id)])
	_push(peer_id)

func request_spend_point(attribute: String) -> void:
	if is_server():
		_spend_point_on_server(Net.my_id, attribute)
		return
	if Net.is_offline():
		return
	_request_point.rpc_id(1, attribute)

## Клиент просит списать запас сил (заклинания). Сервер решает сам.
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

func _spend_point_on_server(peer_id: int, attribute: String) -> void:
	if not DerivedStats.ATTRIBUTE_KEYS.has(attribute):
		return
	_ensure(peer_id)
	if available_points(peer_id) <= 0:
		Game.notify_peer(peer_id, "Свободных очков нет")
		return
	var attrs := attributes(peer_id)
	attrs[attribute] = int(attrs[attribute]) + 1
	_attributes[peer_id] = attrs
	var points: Dictionary = _points.get(peer_id, {})
	points[attribute] = int(points.get(attribute, 0)) + 1
	_points[peer_id] = points
	print("[STATS] #%d вложил очко в %s, теперь %d" % [
		peer_id, attribute, int(attrs[attribute])
	])
	_push(peer_id)

func _spend_mana(peer_id: int, amount: float) -> bool:
	_ensure(peer_id)
	var left := float(_mp.get(peer_id, 0.0))
	if left < amount:
		return false
	_mp[peer_id] = left - amount
	_push(peer_id)
	return true

func _apply(peer_id: int, dealt: float, kind: String = "physical") -> float:
	if dealt <= 0.0:
		return 0.0
	_ensure(peer_id)
	var left := maxf(0.0, float(_hp.get(peer_id, 0.0)) - dealt)
	_hp[peer_id] = left
	if left <= 0.0:
		_downed[peer_id] = true
		Game.notify_peer(peer_id, "Тебя свалили. Возвращаешься в лагерь.")
	_push(peer_id)
	if kind != "self":
		print("[STATS] #%d получил %.1f урона (%s), осталось %.1f" % [peer_id, dealt, kind, left])
	return dealt

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
		_level.erase(peer_id)
		_exp.erase(peer_id)
		_evolution.erase(peer_id)
		_points.erase(peer_id)

func _ensure(peer_id: int) -> void:
	if _attributes.has(peer_id):
		return
	var attrs := DerivedStats.start_attributes()
	_attributes[peer_id] = attrs
	_hp[peer_id] = DerivedStats.max_hp(attrs)
	_mp[peer_id] = DerivedStats.max_mp(attrs)
	_downed[peer_id] = false
	_level[peer_id] = 0
	_exp[peer_id] = 0
	_evolution[peer_id] = 0
	var points := {}
	for key in DerivedStats.ATTRIBUTE_KEYS:
		points[key] = 0
	_points[peer_id] = points

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
		"level": level(peer_id),
		"exp": exp_value(peer_id),
		"evolution": evolution(peer_id),
		"points": _points.get(peer_id, {}).duplicate(),
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
func _request_point(attribute: String) -> void:
	if not is_server():
		return
	_spend_point_on_server(multiplayer.get_remote_sender_id(), attribute)

@rpc("any_peer", "call_remote", "reliable")
func _request_mana(amount: float) -> void:
	if not is_server():
		return
	_spend_mana(multiplayer.get_remote_sender_id(), clampf(amount, 0.0, MAX_MANA_REQUEST))

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
	_level[peer_id] = maxi(0, int(payload.get("level", 0)))
	_exp[peer_id] = maxi(0, int(payload.get("exp", 0)))
	_evolution[peer_id] = maxi(0, int(payload.get("evolution", 0)))
	var points: Dictionary = payload.get("points", {})
	_points[peer_id] = points.duplicate()
	stats_changed.emit(peer_id)
